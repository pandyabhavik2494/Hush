package com.pandyabhavik.hush.data

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withPermit
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder

/**
 * Artist photos from Deezer's public catalog. Only the artist's name is sent. Photos are saved on
 * the phone; a "no photo" answer is remembered until you refresh the library.
 */
object ArtistPhotos {
    private val lookups = Semaphore(3)

    private fun folder(context: Context) = File(context.filesDir, "artist-photos").apply { mkdirs() }

    suspend fun photo(context: Context, artist: Artist): Bitmap? = withContext(Dispatchers.IO) {
        val dir = folder(context)
        val file = File(dir, "${artist.id}.jpg")
        if (file.exists()) return@withContext BitmapFactory.decodeFile(file.path)
        val miss = File(dir, "${artist.id}.miss")
        if (miss.exists()) return@withContext null
        lookups.withPermit {
            val url = runCatching { lookup(artist) }.getOrElse { return@withPermit null }
            if (url == null) {
                miss.createNewFile()
                return@withPermit null
            }
            val bytes = runCatching { download(url) }.getOrNull() ?: return@withPermit null
            file.writeBytes(bytes)
            BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
        }
    }

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
