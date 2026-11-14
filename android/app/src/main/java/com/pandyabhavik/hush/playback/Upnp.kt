package com.pandyabhavik.hush.playback

import android.content.Context
import android.net.wifi.WifiManager
import java.io.ByteArrayOutputStream
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.HttpURLConnection
import java.net.InetAddress
import java.net.SocketTimeoutException
import java.net.URL

/**
 * A speaker on the Wi-Fi that Hush can play to: a Sonos room (or group of rooms), or any other
 * UPnP/DLNA "media renderer" (many TVs, AV receivers and network speakers).
 */
data class Speaker(
    /** Stable across searches: the Sonos group coordinator's id, or the device's UDN. */
    val id: String,
    val name: String,
    /** "Sonos", "Sonos · 3 rooms", or the maker and model. */
    val detail: String,
    val host: String,
    val avTransport: String,
    val rendering: String?,
    /** Sonos only: the volume of the whole group. */
    val groupRendering: String?,
    val sonos: Boolean,
)

class UpnpError(message: String) : Exception(message)

/** SOAP calls to a renderer, and finding renderers with SSDP. */
object Upnp {
    const val AV_TRANSPORT = "urn:schemas-upnp-org:service:AVTransport:1"
    const val RENDERING = "urn:schemas-upnp-org:service:RenderingControl:1"
    const val GROUP_RENDERING = "urn:schemas-upnp-org:service:GroupRenderingControl:1"
    private const val ZONE_TOPOLOGY = "urn:schemas-upnp-org:service:ZoneGroupTopology:1"

    /** Calls [action] and returns the response body; throws on a network error or a SOAP fault. */
    fun call(controlUrl: String, service: String, action: String, args: List<Pair<String, String>> = listOf("InstanceID" to "0")): String {
        val body = buildString {
            append("<?xml version=\"1.0\" encoding=\"utf-8\"?>")
            append("<s:Envelope xmlns:s=\"http://schemas.xmlsoap.org/soap/envelope/\" s:encodingStyle=\"http://schemas.xmlsoap.org/soap/encoding/\">")
            append("<s:Body><u:").append(action).append(" xmlns:u=\"").append(service).append("\">")
            for ((name, value) in args) append('<').append(name).append('>').append(escape(value)).append("</").append(name).append('>')
            append("</u:").append(action).append("></s:Body></s:Envelope>")
        }.toByteArray(Charsets.UTF_8)
        val connection = URL(controlUrl).openConnection() as HttpURLConnection
        try {
            connection.connectTimeout = 4000
            connection.readTimeout = 8000
            connection.requestMethod = "POST"
            connection.doOutput = true
            connection.setRequestProperty("Content-Type", "text/xml; charset=\"utf-8\"")
            connection.setRequestProperty("SOAPACTION", "\"$service#$action\"")
            connection.setFixedLengthStreamingMode(body.size)
            connection.outputStream.use { it.write(body) }
            val code = connection.responseCode
            val stream = if (code in 200..299) connection.inputStream else connection.errorStream
            val text = stream?.use { String(it.readBytes(), Charsets.UTF_8) }.orEmpty()
            if (code !in 200..299) {
                val upnpCode = tag(text, "errorCode")
                throw UpnpError("$action failed ($code${upnpCode?.let { ", UPnP $it" } ?: ""})")
            }
            return text
        } finally {
            connection.disconnect()
        }
    }

    fun escape(text: String): String = buildString(text.length) {
        for (c in text) when (c) {
            '&' -> append("&amp;")
            '<' -> append("&lt;")
            '>' -> append("&gt;")
            '"' -> append("&quot;")
            '\'' -> append("&apos;")
            else -> append(c)
        }
    }

    fun unescape(text: String): String = text
        .replace("&lt;", "<").replace("&gt;", ">").replace("&quot;", "\"").replace("&apos;", "'").replace("&amp;", "&")

    /** The text of the first <name> element (any namespace prefix), unescaped. */
    fun tag(xml: String, name: String): String? =
        Regex("<(?:[A-Za-z0-9_]+:)?$name(?:\\s[^>]*)?>(.*?)</(?:[A-Za-z0-9_]+:)?$name>", RegexOption.DOT_MATCHES_ALL)
            .find(xml)?.groupValues?.get(1)?.let(::unescape)?.trim()

    /** "0:03:12" or "00:03:12.500" to milliseconds; null for "NOT_IMPLEMENTED" and the like. */
    fun parseTime(text: String?): Long? {
        val parts = text?.trim()?.split(':') ?: return null
        if (parts.size != 3) return null
        val h = parts[0].toLongOrNull() ?: return null
        val m = parts[1].toLongOrNull() ?: return null
        val s = parts[2].toDoubleOrNull() ?: return null
        return ((h * 3600 + m * 60) * 1000 + s * 1000).toLong()
    }

    fun formatTime(ms: Long): String {
        val total = (ms / 1000).coerceAtLeast(0)
        return "%d:%02d:%02d".format(total / 3600, (total / 60) % 60, total % 60)
    }

    // MARK: Finding speakers

    private val searchTargets = listOf(
        "urn:schemas-upnp-org:device:ZonePlayer:1",
        "urn:schemas-upnp-org:device:MediaRenderer:1",
    )

    /** Looks for speakers on the Wi-Fi for about three seconds. Blocking: call off the main thread. */
    fun search(context: Context): List<Speaker> {
        val wifi = context.applicationContext.getSystemService(WifiManager::class.java)
        val lock = wifi?.createMulticastLock("hush-speakers")?.apply { setReferenceCounted(false); acquire() }
        val locations = linkedSetOf<String>()
        try {
            DatagramSocket().use { socket ->
                socket.soTimeout = 400
                val group = InetAddress.getByName("239.255.255.250")
                repeat(2) {
                    for (target in searchTargets) {
                        val message = "M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\nMAN: \"ssdp:discover\"\r\nMX: 2\r\nST: $target\r\n\r\n"
                        val bytes = message.toByteArray(Charsets.US_ASCII)
                        runCatching { socket.send(DatagramPacket(bytes, bytes.size, group, 1900)) }
                    }
                }
                val buffer = ByteArray(4096)
                val until = System.currentTimeMillis() + 3000
                while (System.currentTimeMillis() < until) {
                    val packet = DatagramPacket(buffer, buffer.size)
                    try {
                        socket.receive(packet)
                    } catch (_: SocketTimeoutException) {
                        continue
                    }
                    val text = String(packet.data, 0, packet.length, Charsets.ISO_8859_1)
                    text.lineSequence()
                        .firstOrNull { it.startsWith("location:", ignoreCase = true) }
                        ?.substringAfter(':')?.trim()
                        ?.let(locations::add)
                }
            }
        } catch (_: Exception) {
            // No network: nothing found.
        } finally {
            runCatching { lock?.release() }
        }

        val devices = locations.mapNotNull { runCatching { describe(it) }.getOrNull() }
        val sonos = devices.filter { it.sonos }
        val others = devices.filter { !it.sonos && it.avTransport != null }
            .distinctBy { it.udn }
            .map {
                Speaker(
                    id = it.udn, name = it.friendlyName, detail = listOfNotNull(it.manufacturer, it.model).joinToString(" ").ifBlank { "Speaker" },
                    host = it.host, avTransport = it.avTransport!!, rendering = it.rendering, groupRendering = null, sonos = false,
                )
            }
        return (sonosGroups(sonos) + others).sortedBy { it.name.lowercase() }
    }

    private class Description(
        val location: String, val host: String, val udn: String, val friendlyName: String, val roomName: String?,
        val manufacturer: String?, val model: String?, val avTransport: String?, val rendering: String?, val sonos: Boolean,
    )

    private fun describe(location: String): Description? {
        val url = URL(location)
        val connection = url.openConnection() as HttpURLConnection
        val xml = try {
            connection.connectTimeout = 2000
            connection.readTimeout = 3000
            connection.inputStream.use { input ->
                val out = ByteArrayOutputStream()
                input.copyTo(out)
                String(out.toByteArray(), Charsets.UTF_8)
            }
        } finally {
            connection.disconnect()
        }
        val base = "${url.protocol}://${url.host}:${if (url.port > 0) url.port else 80}"
        fun absolute(path: String?): String? = when {
            path.isNullOrBlank() -> null
            path.startsWith("http") -> path
            path.startsWith("/") -> base + path
            else -> "$base/$path"
        }
        var avTransport: String? = null
        var rendering: String? = null
        Regex("<service>(.*?)</service>", RegexOption.DOT_MATCHES_ALL).findAll(xml).forEach { match ->
            val service = match.groupValues[1]
            val type = tag(service, "serviceType") ?: return@forEach
            val control = absolute(tag(service, "controlURL"))
            if (type.contains(":AVTransport:") && avTransport == null) avTransport = control
            if (type.contains(":RenderingControl:") && rendering == null) rendering = control
        }
        val manufacturer = tag(xml, "manufacturer")
        return Description(
            location = location, host = url.host, udn = tag(xml, "UDN") ?: location,
            friendlyName = tag(xml, "friendlyName") ?: url.host, roomName = tag(xml, "roomName"),
            manufacturer = manufacturer, model = tag(xml, "modelName"),
            avTransport = avTransport, rendering = rendering,
            sonos = manufacturer?.contains("Sonos", ignoreCase = true) == true,
        )
    }

    /**
     * Sonos rooms, as the Sonos app shows them: one entry per group, named after its rooms, played
     * through the group's coordinator (so the whole group plays). Hidden parts of a room (a Sub,
     * surrounds, the second of a stereo pair) aren't listed.
     */
    private fun sonosGroups(devices: List<Description>): List<Speaker> {
        if (devices.isEmpty()) return emptyList()
        val byHost = devices.associateBy { it.host }
        val state = devices.firstNotNullOfOrNull { device ->
            runCatching {
                tag(call("http://${device.host}:1400/ZoneGroupTopology/Control", ZONE_TOPOLOGY, "GetZoneGroupState", emptyList()), "ZoneGroupState")
            }.getOrNull()
        }
        if (state != null) {
            val groups = Regex("<ZoneGroup\\s([^>]*)>(.*?)</ZoneGroup>", RegexOption.DOT_MATCHES_ALL).findAll(state).mapNotNull { group ->
                val coordinator = attribute(group.groupValues[1], "Coordinator") ?: return@mapNotNull null
                val members = Regex("<ZoneGroupMember\\s([^>]*?)/?>").findAll(group.groupValues[2])
                    .map { it.groupValues[1] }
                    .filter { attribute(it, "Invisible") != "1" }
                    .toList()
                val lead = members.firstOrNull { attribute(it, "UUID") == coordinator } ?: return@mapNotNull null
                val host = attribute(lead, "Location")?.let { runCatching { URL(it).host }.getOrNull() } ?: return@mapNotNull null
                val rooms = members.mapNotNull { attribute(it, "ZoneName") }.distinct()
                val leadRoom = attribute(lead, "ZoneName") ?: rooms.firstOrNull() ?: "Sonos"
                val name = if (rooms.size > 1) "$leadRoom + ${rooms.size - 1}" else leadRoom
                val model = byHost[host]?.model
                sonosSpeaker(coordinator, name, if (rooms.size > 1) "Sonos · ${rooms.size} rooms" else listOfNotNull("Sonos", model?.removePrefix("Sonos ")).joinToString(" "), host)
            }.toList()
            if (groups.isNotEmpty()) return groups
        }
        // Couldn't read the groups: one entry per room.
        return devices.distinctBy { it.roomName ?: it.friendlyName }.map {
            sonosSpeaker(it.udn.removePrefix("uuid:"), it.roomName ?: it.friendlyName, "Sonos", it.host)
        }
    }

    private fun sonosSpeaker(id: String, name: String, detail: String, host: String) = Speaker(
        id = id, name = name, detail = detail, host = host,
        avTransport = "http://$host:1400/MediaRenderer/AVTransport/Control",
        rendering = "http://$host:1400/MediaRenderer/RenderingControl/Control",
        groupRendering = "http://$host:1400/MediaRenderer/GroupRenderingControl/Control",
        sonos = true,
    )

    private fun attribute(attributes: String, name: String): String? =
        Regex("(?:^|\\s)$name=\"([^\"]*)\"").find(attributes)?.groupValues?.get(1)?.let(::unescape)
}
