package com.pandyabhavik.hush.data

import android.content.Context
import android.graphics.Bitmap
import android.graphics.ImageDecoder
import android.util.LruCache
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withPermit
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import kotlin.math.roundToInt

/**
 * Artist photos from Deezer's public catalog. Only the artist's name is sent. Photos are saved on
 * the phone; a "no photo" answer is remembered until you refresh the library.
 */
object ArtistPhotos {
    private val lookups = Semaphore(3)

    /** Decoded photos, by artist and size bucket, so scrolling back never reads the file again. */
    private val memory = object : LruCache<String, Bitmap>(24 * 1024 * 1024) {
        override fun sizeOf(key: String, value: Bitmap) = value.allocationByteCount
    }

    private val buckets = intArrayOf(240, 480, 720, 1200)

    private fun bucket(px: Int): Int = buckets.firstOrNull { px <= it } ?: buckets.last()

    private fun folder(context: Context) = File(context.filesDir, "artist-photos").apply { mkdirs() }

    /** The photo at [px] if it is in memory already (the size asked for, or bigger). */
    fun cached(artist: Artist, px: Int): Bitmap? {
        val size = bucket(px)
        for (b in buckets) if (b >= size) memory.get("${artist.id}@$b")?.let { return it }
        return null
    }

    /**
     * The artist's photo, decoded to fit [px] (Deezer's are 1000 px; a grid tile needs far
     * fewer), or null when there is none.
     */
    suspend fun photo(context: Context, artist: Artist, px: Int = 1200): Bitmap? {
        cached(artist, px)?.let { return it }
        val size = bucket(px)
        val bitmap = withContext(Dispatchers.IO) {
            val dir = folder(context)
            val file = File(dir, "${artist.id}.jpg")
            if (file.exists()) return@withContext decode(file, size)
            val miss = File(dir, "${artist.id}.miss")
            if (miss.exists()) return@withContext null
            lookups.withPermit {
                // Another request may have fetched it while this one waited.
                if (file.exists()) return@withPermit decode(file, size)
                val url = runCatching { lookup(artist) }.getOrElse { return@withPermit null }
                if (url == null) {
                    miss.createNewFile()
                    return@withPermit null
                }
                val bytes = runCatching { download(url) }.getOrNull() ?: return@withPermit null
                // Written aside and moved into place, so a half-written photo is never read.
                val part = File(dir, "${artist.id}.part")
                part.writeBytes(bytes)
                if (!part.renameTo(file)) {
                    part.delete()
                    return@withPermit null
                }
                decode(file, size)
            }
        }
        bitmap?.let { memory.put("${artist.id}@$size", it) }
        return bitmap
    }

    /** Decodes the saved photo to fit [size], scaling down only. */
    private fun decode(file: File, size: Int): Bitmap? = runCatching {
        ImageDecoder.decodeBitmap(ImageDecoder.createSource(file)) { decoder, info, _ ->
            val long = maxOf(info.size.width, info.size.height)
            if (long > size) {
                val scale = size.toFloat() / long
                decoder.setTargetSize(
                    (info.size.width * scale).roundToInt().coerceAtLeast(1),
                    (info.size.height * scale).roundToInt().coerceAtLeast(1),
                )
            }
        }
    }.getOrNull()

    fun forgetMisses(context: Context) {
        folder(context).listFiles { f -> f.name.endsWith(".miss") }?.forEach { it.delete() }
    }

    /** The photo's address, or null if Deezer has no exact match (throws when offline). */
    private fun lookup(artist: Artist): String? {
        val query = URLEncoder.encode(artist.name, "UTF-8")
        val json = JSONObject(String(download("https://api.deezer.com/search/artist?q=$query&limit=10")))
        val data = json.optJSONArray("data") ?: return null
        for (i in 0 until data.length()) {
            val item = data.getJSONObject(i)
            if (ArtistCredits.key(item.optString("name")) != artist.id) continue
            val picture = item.optString("picture_xl").ifEmpty { item.optString("picture_big") }
            // Deezer's grey silhouette has an empty image id ("/artist//").
            return picture.takeIf { it.isNotEmpty() && !it.contains("/artist//") }
        }
        return null
    }

    private fun download(address: String): ByteArray {
        val connection = URL(address).openConnection() as HttpURLConnection
        connection.connectTimeout = 10_000
        connection.readTimeout = 15_000
        try {
            if (connection.responseCode != 200) error("HTTP ${connection.responseCode}")
            return connection.inputStream.use { it.readBytes() }
        } finally {
            connection.disconnect()
        }
    }
}
