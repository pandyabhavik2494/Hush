package com.pandyabhavik.hush.data

import android.content.Context
import android.net.Uri
import android.provider.DocumentsContract
import java.text.Normalizer

/**
 * Playlists come from .m3u / .m3u8 files in a folder you pick once (for example the Playlists
 * folder copied from the Mac). Each line is matched to a song on the phone by the end of its path
 * (artist folder / album folder / file name), so the Mac's full paths work as they are.
 * A picture named like a playlist ("Road Trip.jpg"), anywhere in that folder, becomes its cover.
 */
object PlaylistFiles {
    private data class Entry(val name: String, val uri: Uri, val isDir: Boolean)

    fun load(context: Context, treeUriString: String, songs: List<Song>): List<Playlist> {
        val treeUri = Uri.parse(treeUriString)
        val files = ArrayList<Entry>()
        runCatching {
            walk(context, treeUri, DocumentsContract.getTreeDocumentId(treeUri), depth = 0, into = files)
        }
        val playlistFiles = files.filter { !it.isDir && (it.name.endsWith(".m3u8", true) || it.name.endsWith(".m3u", true)) }
        val images = files.filter { !it.isDir && imageExtensions.any { ext -> it.name.endsWith(ext, true) } }
            .associateBy { normalize(it.name.substringBeforeLast('.')) }

        val matcher = Matcher(songs)
        return playlistFiles.mapNotNull { file ->
            val name = file.name.substringBeforeLast('.')
            val lines = runCatching {
                context.contentResolver.openInputStream(file.uri)?.bufferedReader(Charsets.UTF_8)?.use { it.readLines() }
            }.getOrNull() ?: return@mapNotNull null
            val matched = parse(lines).mapNotNull { matcher.match(it) }
            if (matched.isEmpty()) return@mapNotNull null
            val covers = ArrayList<Song>()
            val seenAlbums = HashSet<String>()
            for (song in matched) {
                if (seenAlbums.add(song.albumKey)) covers += song
                if (covers.size == 4) break
            }
            Playlist(
                id = normalize(name),
                name = name,
                songs = matched,
                coverUri = images[normalize(name)]?.uri,
                coverSongs = if (covers.size == 4) covers else covers.take(1),
                searchKey = LibrarySearch.key(name),
                songSearchKey = LibrarySearch.songsKey(matched),
                letter = LibraryAlphabet.section(name),
            )
        }.distinctBy { it.id }.sortedWith(compareBy(LibraryAlphabet.comparator) { it.name })
    }

    private val imageExtensions = listOf(".jpg", ".jpeg", ".png", ".webp")

    private fun walk(context: Context, tree: Uri, documentId: String, depth: Int, into: MutableList<Entry>) {
        if (depth > 3) return
        val children = DocumentsContract.buildChildDocumentsUriUsingTree(tree, documentId)
        val dirs = ArrayList<String>()
        context.contentResolver.query(
            children,
            arrayOf(
                DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                DocumentsContract.Document.COLUMN_MIME_TYPE,
            ),
            null, null, null,
        )?.use { c ->
            while (c.moveToNext()) {
                val id = c.getString(0)
                val name = c.getString(1) ?: continue
                val isDir = c.getString(2) == DocumentsContract.Document.MIME_TYPE_DIR
                if (name.startsWith(".")) continue
                into += Entry(name, DocumentsContract.buildDocumentUriUsingTree(tree, id), isDir)
                if (isDir) dirs += id
            }
        }
        for (dir in dirs) walk(context, tree, dir, depth + 1, into)
    }

    /** A playlist line: its path, plus "Artist - Title" from #EXTINF when present. */
    private data class Line(val path: String, val info: String?)

    private fun parse(lines: List<String>): List<Line> {
        val result = ArrayList<Line>()
        var info: String? = null
        for (raw in lines) {
            val line = raw.trim().removePrefix("﻿")
            when {
                line.isEmpty() -> Unit
                line.startsWith("#EXTINF", ignoreCase = true) -> info = line.substringAfter(',', "").trim().ifEmpty { null }
                line.startsWith("#") -> Unit
                else -> {
                    result += Line(Uri.decode(line.removePrefix("file://")), info)
                    info = null
                }
            }
        }
        return result
    }

    private fun normalize(text: String): String =
        Normalizer.normalize(text, Normalizer.Form.NFC).lowercase().trim()

    private fun components(path: String): List<String> =
        path.replace('\\', '/').split('/').filter { it.isNotEmpty() }.map { normalize(it) }

    private class Matcher(songs: List<Song>) {
        private val byTail3 = HashMap<String, Song>()
        private val byTail2 = HashMap<String, Song>()
        private val byFile = HashMap<String, MutableList<Song>>()
        private val byInfo = HashMap<String, Song>()

        init {
            for (song in songs) {
                val parts = components(song.path)
                if (parts.size >= 3) byTail3.putIfAbsent(parts.takeLast(3).joinToString("/"), song)
                if (parts.size >= 2) byTail2.putIfAbsent(parts.takeLast(2).joinToString("/"), song)
                parts.lastOrNull()?.let { byFile.getOrPut(it) { ArrayList() }.add(song) }
                byInfo.putIfAbsent(LibrarySearch.fold("${song.artist} - ${song.title}"), song)
            }
        }

        fun match(line: Line): Song? {
            val parts = components(line.path)
            if (parts.isNotEmpty()) {
                if (parts.size >= 3) byTail3[parts.takeLast(3).joinToString("/")]?.let { return it }
                if (parts.size >= 2) byTail2[parts.takeLast(2).joinToString("/")]?.let { return it }
                val sameName = byFile[parts.last()].orEmpty()
                if (sameName.size == 1) return sameName.first()
                if (sameName.size > 1 && parts.size >= 2) {
                    // Several "01 Intro.m4a": pick the one whose album matches the folder name.
                    val folder = LibrarySearch.fold(parts[parts.size - 2])
                    sameName.firstOrNull { LibrarySearch.fold(it.album) == folder }?.let { return it }
                }
            }
            line.info?.let { info -> byInfo[LibrarySearch.fold(info)]?.let { return it } }
            return null
        }
    }
}
