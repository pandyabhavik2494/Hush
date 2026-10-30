package com.pandyabhavik.hush.data

import android.content.Context
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.provider.DocumentsContract
import org.json.JSONObject
import java.io.File

/**
 * Music videos come from one folder you pick (for example "Music Videos"); Hush sees nothing else.
 * Titles and artists come from the video's tags, else from an "Artist - Title" file name.
 * What's read from each file is cached, so later launches don't open every video again.
 */
object VideoFolder {
    private val extensions = setOf("mp4", "m4v", "mov", "mkv", "webm", "3gp")

    private data class Entry(val uri: Uri, val name: String, val size: Long, val modified: Long)

    fun load(context: Context, folder: String): List<Video> {
        val uri = Uri.parse(folder)
        val entries = ArrayList<Entry>()
        runCatching {
            if (uri.scheme == "file") walkFiles(File(uri.path!!), 0, entries)
            else walkTree(context, uri, DocumentsContract.getTreeDocumentId(uri), 0, entries)
        }
        val cacheFile = File(context.filesDir, "video-info.json")
        val old = runCatching { JSONObject(cacheFile.readText()) }.getOrDefault(JSONObject())
        val fresh = JSONObject()
        val videos = entries.map { entry ->
            val key = "${entry.uri}|${entry.size}|${entry.modified}"
            val info = old.optJSONObject(key) ?: read(context, entry.uri)?.also { fresh.put(key, it) } ?: JSONObject()
            if (old.has(key)) fresh.put(key, info)
            val base = entry.name.substringBeforeLast('.')
            val title = info.optString("title").takeIf { it.isNotBlank() && it != base } ?: base.substringAfter(" - ")
            val artist = info.optString("artist").trim().takeIf { it.isNotEmpty() && it != "<unknown>" }
                ?: base.takeIf { it.contains(" - ") }?.substringBefore(" - ")?.trim()
            Video(
                id = entry.uri.toString(),
                uri = entry.uri,
                title = title.trim(),
                artist = artist,
                durationMs = info.optLong("duration"),
                searchKey = LibrarySearch.key(title, artist),
                letter = LibraryAlphabet.section(title),
            )
        }
        if (fresh.toString() != old.toString()) runCatching { cacheFile.writeText(fresh.toString()) }
        return videos.sortedWith(compareBy(LibraryAlphabet.comparator) { it.title })
    }

    /** The video's length and tags, or null if it couldn't be read this time (it's tried again next time). */
    private fun read(context: Context, uri: Uri): JSONObject? {
        val info = JSONObject()
        val retriever = MediaMetadataRetriever()
        return try {
            retriever.setDataSource(context, uri)
            info.put("duration", retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0L)
            retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_TITLE)?.let { info.put("title", it) }
            retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_ARTIST)?.let { info.put("artist", it) }
            info
        } catch (_: Exception) {
            // Unreadable files still show, by file name.
            null
        } finally {
            runCatching { retriever.release() }
        }
    }

    private fun isVideo(name: String) = !name.startsWith(".") && name.substringAfterLast('.', "").lowercase() in extensions

    private fun walkTree(context: Context, tree: Uri, documentId: String, depth: Int, into: MutableList<Entry>) {
        if (depth > 3) return
        val children = DocumentsContract.buildChildDocumentsUriUsingTree(tree, documentId)
        val dirs = ArrayList<String>()
        context.contentResolver.query(
            children,
            arrayOf(
                DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                DocumentsContract.Document.COLUMN_MIME_TYPE,
                DocumentsContract.Document.COLUMN_SIZE,
                DocumentsContract.Document.COLUMN_LAST_MODIFIED,
            ),
            null, null, null,
        )?.use { c ->
            while (c.moveToNext()) {
                val id = c.getString(0) ?: continue
                val name = c.getString(1) ?: continue
                if (name.startsWith(".")) continue
                if (c.getString(2) == DocumentsContract.Document.MIME_TYPE_DIR) dirs += id
                else if (isVideo(name)) into += Entry(
                    DocumentsContract.buildDocumentUriUsingTree(tree, id), name,
                    if (c.isNull(3)) 0 else c.getLong(3), if (c.isNull(4)) 0 else c.getLong(4),
                )
            }
        }
        for (dir in dirs) walkTree(context, tree, dir, depth + 1, into)
    }

    /** A plain folder (used by the tests, which can't use the folder picker). */
    private fun walkFiles(dir: File, depth: Int, into: MutableList<Entry>) {
        if (depth > 3) return
        for (file in dir.listFiles().orEmpty()) {
            if (file.isDirectory) walkFiles(file, depth + 1, into)
            else if (isVideo(file.name)) into += Entry(Uri.fromFile(file), file.name, file.length(), file.lastModified())
        }
    }

    /** The folder's name for display, such as "Music Videos". */
    fun name(folder: String): String {
        val uri = Uri.parse(folder)
        if (uri.scheme == "file") return File(uri.path!!).name
        return runCatching { DocumentsContract.getTreeDocumentId(uri).substringAfterLast(':').substringAfterLast('/') }
            .getOrNull()?.ifBlank { null } ?: "your folder"
    }
}
