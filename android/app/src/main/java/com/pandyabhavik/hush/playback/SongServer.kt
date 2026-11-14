package com.pandyabhavik.hush.playback

import android.content.ContentUris
import android.content.Context
import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.provider.MediaStore
import android.util.Size
import java.io.BufferedReader
import java.io.ByteArrayOutputStream
import java.io.FileInputStream
import java.io.InputStreamReader
import java.io.OutputStream
import java.net.DatagramSocket
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.ServerSocket
import java.net.Socket
import java.security.SecureRandom
import java.util.concurrent.Executors

/**
 * A small web server on the phone, so a speaker or TV on the same Wi-Fi can fetch the song it was
 * asked to play (Sonos and other network speakers play from a web address, not from the phone itself).
 *
 * It serves only songs and their covers, by MediaStore id, under a random key made fresh each time
 * it starts, so nothing else on the network can browse the library. Range requests are answered,
 * which is how a speaker seeks.
 */
class SongServer(private val context: Context) {
    private val key = ByteArray(12).also { SecureRandom().nextBytes(it) }.joinToString("") { "%02x".format(it) }
    private var socket: ServerSocket? = null
    private val workers = Executors.newCachedThreadPool { r -> Thread(r, "hush-server").apply { isDaemon = true } }

    /** "http://192.168.1.20:41234/<key>", reachable from the device at [peer]; null until started. */
    @Volatile var base: String? = null; private set

    /** Starts (once) and works out the phone's address on the network that reaches [peer]. */
    fun start(peer: InetAddress?) {
        val server = socket ?: ServerSocket().also {
            it.reuseAddress = true
            it.bind(InetSocketAddress(0))
            socket = it
            Thread({ acceptLoop(it) }, "hush-server-accept").apply { isDaemon = true }.start()
        }
        val host = localAddressToward(peer) ?: return
        base = "http://${host.hostAddress}:${server.localPort}/$key"
    }

    fun stop() {
        base = null
        runCatching { socket?.close() }
        socket = null
    }

    /** With the file's extension on the end: some speakers (Sonos among them) go by it. */
    fun songUrl(id: String, mimeType: String): String? = base?.let { "$it/song/$id.${extension(mimeType)}" }
    fun coverUrl(id: String): String? = base?.let { "$it/cover/$id" }

    /** The phone's own address on the interface that leads to [peer] (Wi-Fi, usually). */
    private fun localAddressToward(peer: InetAddress?): InetAddress? {
        if (peer != null) {
            runCatching {
                DatagramSocket().use { probe ->
                    probe.connect(peer, 9)
                    val local = probe.localAddress
                    if (local != null && !local.isAnyLocalAddress && !local.isLoopbackAddress) return local
                }
            }
        }
        return java.net.NetworkInterface.getNetworkInterfaces()?.toList().orEmpty()
            .filter { it.isUp && !it.isLoopback }
            .sortedBy { if (it.name.startsWith("wlan")) 0 else 1 }
            .flatMap { it.inetAddresses.toList() }
            .firstOrNull { it is java.net.Inet4Address && it.isSiteLocalAddress }
    }

    private fun acceptLoop(server: ServerSocket) {
        while (!server.isClosed) {
            val client = runCatching { server.accept() }.getOrNull() ?: break
            workers.execute { runCatching { handle(client) }; runCatching { client.close() } }
        }
    }

    private fun handle(client: Socket) {
        client.soTimeout = 30_000
        val reader = BufferedReader(InputStreamReader(client.getInputStream(), Charsets.ISO_8859_1))
        val request = reader.readLine() ?: return
        val headers = mutableMapOf<String, String>()
        while (true) {
            val line = reader.readLine() ?: break
            if (line.isEmpty()) break
            val colon = line.indexOf(':')
            if (colon > 0) headers[line.substring(0, colon).trim().lowercase()] = line.substring(colon + 1).trim()
        }
        val parts = request.split(' ')
        val method = parts.getOrNull(0) ?: return
        val path = parts.getOrNull(1)?.substringBefore('?') ?: return
        val out = client.getOutputStream()
        if (method == "OPTIONS") return respond(out, 204, "No Content", emptyMap())
        if (method != "GET" && method != "HEAD") return respond(out, 405, "Method Not Allowed", emptyMap())

        val segments = path.trim('/').split('/')
        if (segments.size != 3 || segments[0] != key) return respond(out, 404, "Not Found", emptyMap())
        val id = segments[2].substringBefore('.').toLongOrNull() ?: return respond(out, 404, "Not Found", emptyMap())
        val uri = ContentUris.withAppendedId(MediaStore.Audio.Media.getContentUri(MediaStore.VOLUME_EXTERNAL), id)
        when (segments[1]) {
            "song" -> sendSong(out, uri, headers["range"], head = method == "HEAD")
            "cover" -> sendCover(out, uri, head = method == "HEAD")
            else -> respond(out, 404, "Not Found", emptyMap())
        }
    }

    private fun sendSong(out: OutputStream, uri: Uri, range: String?, head: Boolean) {
        val fd = runCatching { context.contentResolver.openFileDescriptor(uri, "r") }.getOrNull()
            ?: return respond(out, 404, "Not Found", emptyMap())
        fd.use {
            val size = it.statSize
            val type = speakerMimeType(context.contentResolver.getType(uri))
            var start = 0L
            var end = size - 1
            var partial = false
            if (range != null && range.startsWith("bytes=") && size > 0) {
                val spec = range.removePrefix("bytes=").substringBefore(',')
                val from = spec.substringBefore('-').trim()
                val to = spec.substringAfter('-', "").trim()
                if (from.isEmpty() && to.isNotEmpty()) {
                    start = (size - (to.toLongOrNull() ?: 0)).coerceAtLeast(0)
                } else {
                    start = from.toLongOrNull() ?: 0
                    if (to.isNotEmpty()) end = (to.toLongOrNull() ?: end).coerceAtMost(size - 1)
                }
                if (start >= size || start > end) {
                    return respond(out, 416, "Range Not Satisfiable", mapOf("Content-Range" to "bytes */$size"))
                }
                partial = true
            }
            val length = (end - start + 1).coerceAtLeast(0)
            val headers = buildMap {
                put("Content-Type", type)
                put("Content-Length", length.toString())
                put("Accept-Ranges", "bytes")
                if (partial) put("Content-Range", "bytes $start-$end/$size")
            }
            if (partial) writeHead(out, 206, "Partial Content", headers) else writeHead(out, 200, "OK", headers)
            if (head) return
            FileInputStream(it.fileDescriptor).use { input ->
                input.channel.position(start)
                val buffer = ByteArray(64 * 1024)
                var left = length
                while (left > 0) {
                    val read = input.read(buffer, 0, minOf(buffer.size.toLong(), left).toInt())
                    if (read < 0) break
                    out.write(buffer, 0, read)
                    left -= read
                }
            }
            out.flush()
        }
    }

    private fun sendCover(out: OutputStream, uri: Uri, head: Boolean) {
        val (bytes, type) = cover(uri) ?: return respond(out, 404, "Not Found", emptyMap())
        writeHead(out, 200, "OK", mapOf("Content-Type" to type, "Content-Length" to bytes.size.toString(), "Cache-Control" to "max-age=3600"))
        if (!head) out.write(bytes)
        out.flush()
    }

    /** The song's own embedded picture when there is one, else MediaStore's thumbnail. */
    private fun cover(uri: Uri): Pair<ByteArray, String>? {
        val retriever = MediaMetadataRetriever()
        val embedded = try {
            retriever.setDataSource(context, uri)
            retriever.embeddedPicture
        } catch (_: Exception) {
            null
        } finally {
            runCatching { retriever.release() }
        }
        if (embedded != null && embedded.size > 4) {
            val png = embedded[0] == 0x89.toByte() && embedded[1] == 'P'.code.toByte()
            return embedded to if (png) "image/png" else "image/jpeg"
        }
        val thumb = runCatching { context.contentResolver.loadThumbnail(uri, Size(800, 800), null) }.getOrNull() ?: return null
        val bytes = ByteArrayOutputStream().use { thumb.compress(Bitmap.CompressFormat.JPEG, 90, it); it.toByteArray() }
        return bytes to "image/jpeg"
    }

    private fun respond(out: OutputStream, code: Int, reason: String, headers: Map<String, String>) {
        writeHead(out, code, reason, headers + ("Content-Length" to "0"))
        out.flush()
    }

    private fun writeHead(out: OutputStream, code: Int, reason: String, headers: Map<String, String>) {
        val text = StringBuilder("HTTP/1.1 $code $reason\r\n")
        // Some renderers are web pages: let them read the answer.
        text.append("Access-Control-Allow-Origin: *\r\n")
        text.append("Access-Control-Allow-Headers: Range, Content-Type\r\n")
        text.append("Access-Control-Expose-Headers: Content-Length, Content-Range, Accept-Ranges\r\n")
        text.append("Connection: close\r\n")
        for ((name, value) in headers) text.append(name).append(": ").append(value).append("\r\n")
        text.append("\r\n")
        out.write(text.toString().toByteArray(Charsets.ISO_8859_1))
    }

    companion object {
        fun extension(mimeType: String): String = when (mimeType) {
            "audio/mpeg" -> "mp3"
            "audio/mp4" -> "m4a"
            "audio/flac" -> "flac"
            "audio/wav" -> "wav"
            "audio/aac" -> "aac"
            "audio/ogg" -> "ogg"
            else -> mimeType.substringAfter('/').substringAfter("x-")
        }

        /** MediaStore's type for a song, in the spelling network speakers expect. */
        fun speakerMimeType(type: String?): String = when (type?.lowercase()) {
            null, "" -> "audio/mpeg"
            "audio/x-flac" -> "audio/flac"
            "audio/x-wav" -> "audio/wav"
            "audio/x-m4a", "audio/m4a", "audio/aac-adts" -> if (type.lowercase() == "audio/aac-adts") "audio/aac" else "audio/mp4"
            "audio/mp3" -> "audio/mpeg"
            else -> type
        }
    }
}
