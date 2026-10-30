package com.pandyabhavik.hush.data

import android.content.ContentUris
import android.content.Context
import android.provider.MediaStore

/** Reads the songs on the phone from MediaStore and builds albums and artists from them. */
object LibraryLoader {

    fun load(context: Context, playlistsFolder: String?): Library {
        val songs = loadSongs(context)
        val albums = buildAlbums(songs)
        val artists = buildArtists(albums)
        val playlists = playlistsFolder?.let { PlaylistFiles.load(context, it, songs) } ?: emptyList()
        return Library(songs, albums, artists, playlists)
    }

    private fun loadSongs(context: Context): List<Song> {
        val collection = MediaStore.Audio.Media.getContentUri(MediaStore.VOLUME_EXTERNAL)
        val projection = arrayOf(
            MediaStore.Audio.Media._ID,
            MediaStore.Audio.Media.TITLE,
            MediaStore.Audio.Media.ARTIST,
            MediaStore.Audio.Media.ALBUM,
            MediaStore.Audio.Media.ALBUM_ARTIST,
            MediaStore.Audio.Media.DURATION,
            MediaStore.Audio.Media.TRACK,
            MediaStore.Audio.Media.YEAR,
            MediaStore.Audio.Media.RELATIVE_PATH,
            MediaStore.Audio.Media.DISPLAY_NAME,
        )
        val songs = ArrayList<Song>()
        context.contentResolver.query(
            collection, projection, "${MediaStore.Audio.Media.IS_MUSIC} != 0", null, null,
        )?.use { c ->
            val idCol = c.getColumnIndexOrThrow(MediaStore.Audio.Media._ID)
            val titleCol = c.getColumnIndexOrThrow(MediaStore.Audio.Media.TITLE)
            val artistCol = c.getColumnIndexOrThrow(MediaStore.Audio.Media.ARTIST)
            val albumCol = c.getColumnIndexOrThrow(MediaStore.Audio.Media.ALBUM)
            val albumArtistCol = c.getColumnIndexOrThrow(MediaStore.Audio.Media.ALBUM_ARTIST)
            val durationCol = c.getColumnIndexOrThrow(MediaStore.Audio.Media.DURATION)
            val trackCol = c.getColumnIndexOrThrow(MediaStore.Audio.Media.TRACK)
            val yearCol = c.getColumnIndexOrThrow(MediaStore.Audio.Media.YEAR)
            val pathCol = c.getColumnIndexOrThrow(MediaStore.Audio.Media.RELATIVE_PATH)
            val nameCol = c.getColumnIndexOrThrow(MediaStore.Audio.Media.DISPLAY_NAME)
            while (c.moveToNext()) {
                val id = c.getLong(idCol)
                val fileName = c.getString(nameCol) ?: ""
                val title = c.getString(titleCol)?.takeIf { it.isNotBlank() } ?: fileName.substringBeforeLast('.')
                val artist = c.getString(artistCol).cleanTag() ?: "Unknown Artist"
                val album = c.getString(albumCol).cleanTag() ?: "Unknown Album"
                val albumArtist = c.getString(albumArtistCol).cleanTag()
                val track = c.getInt(trackCol)
                val year = c.getInt(yearCol).takeIf { it > 0 }
                songs += Song(
                    id = id,
                    uri = ContentUris.withAppendedId(collection, id),
                    title = title,
                    artist = artist,
                    album = album,
                    albumArtist = albumArtist,
                    durationMs = c.getLong(durationCol),
                    track = track % 1000,
                    disc = (track / 1000).coerceAtLeast(1),
                    year = year,
                    path = (c.getString(pathCol) ?: "") + fileName,
                    albumKey = LibrarySearch.fold(album) + "|" + LibrarySearch.fold(albumArtist ?: ""),
                    searchKey = LibrarySearch.key(title, artist, album),
                )
            }
        }
        return songs.sortedWith(compareBy(LibraryAlphabet.comparator) { it.title })
    }

    private fun String?.cleanTag(): String? =
        this?.trim()?.takeIf { it.isNotEmpty() && it != "<unknown>" }

    private fun buildAlbums(songs: List<Song>): List<Album> =
        songs.groupBy { it.albumKey }.map { (key, items) ->
            val ordered = items.sortedWith(compareBy<Song> { it.disc }.thenBy { it.track }.thenBy { it.title })
            val first = ordered.first()
            val artist = first.albumArtist
                ?: ordered.groupingBy { it.artist }.eachCount().maxByOrNull { it.value }?.key
                ?: "Unknown Artist"
            Album(
                key = key,
                title = first.album,
                artist = artist,
                year = ordered.firstNotNullOfOrNull { it.year },
                songs = ordered,
                searchKey = LibrarySearch.key(first.album, artist),
                songSearchKey = LibrarySearch.songsKey(ordered),
                letter = LibraryAlphabet.section(first.album),
            )
        }.sortedWith(compareBy(LibraryAlphabet.comparator) { it.title })

    /**
     * One artist per name credited on any song (duets count for each singer; the album artist,
     * often the composer on soundtracks, counts too). Same rules as the iPhone app.
     */
    private fun buildArtists(albums: List<Album>): List<Artist> {
        class Builder {
            val spellings = HashMap<String, Int>()
            val albumSongs = LinkedHashMap<String, MutableList<Song>>()
        }
        val builders = HashMap<String, Builder>()
        for (album in albums) {
            for (song in album.songs) {
                val credited = ArtistCredits.names(song.artist) + ArtistCredits.names(song.albumArtist)
                val seen = HashSet<String>()
                for (name in credited) {
                    val key = ArtistCredits.key(name)
                    if (!seen.add(key)) continue
                    val builder = builders.getOrPut(key) { Builder() }
                    builder.spellings[name] = (builder.spellings[name] ?: 0) + 1
                    builder.albumSongs.getOrPut(album.key) { ArrayList() }.add(song)
                }
            }
        }
        val albumsByKey = albums.associateBy { it.key }
        return builders.mapNotNull { (key, builder) ->
            val name = ArtistCredits.displayName(key)
                ?: builder.spellings.entries.maxWithOrNull(compareBy<Map.Entry<String, Int>> { it.value }.thenByDescending { it.key })?.key
                ?: return@mapNotNull null
            val artistAlbums = builder.albumSongs.mapNotNull { (albumKey, songs) ->
                val album = albumsByKey[albumKey] ?: return@mapNotNull null
                ArtistAlbum(albumKey, album.title, album.year, album.cover, songs)
            }.sortedWith(
                compareBy<ArtistAlbum> { it.year == null }
                    .thenByDescending { it.year ?: 0 }
                    .thenBy(LibraryAlphabet.comparator) { it.title },
            )
            val songs = artistAlbums.flatMap { it.songs }
            Artist(
                id = key,
                name = name,
                albums = artistAlbums,
                songs = songs,
                cover = artistAlbums.maxByOrNull { it.songs.size }?.cover,
                searchKey = LibrarySearch.key(name),
                songSearchKey = LibrarySearch.songsKey(songs),
                letter = LibraryAlphabet.section(name),
            )
        }.sortedWith(compareBy(LibraryAlphabet.comparator) { it.name })
    }
}
