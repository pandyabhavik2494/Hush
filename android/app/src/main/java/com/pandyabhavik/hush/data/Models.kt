package com.pandyabhavik.hush.data

import android.net.Uri

/** One song in the phone's music library (MediaStore). */
data class Song(
    val id: Long,
    val uri: Uri,
    val title: String,
    val artist: String,
    val album: String,
    val albumArtist: String?,
    val durationMs: Long,
    val track: Int,
    val disc: Int,
    val year: Int?,
    /** Folder and file name, e.g. "Music/Arijit Singh/Aashiqui 2/01 Tum Hi Ho.m4a". */
    val path: String,
    val albumKey: String,
    val searchKey: String,
) {
    val mediaId: String get() = id.toString()
}

data class Album(
    val key: String,
    val title: String,
    val artist: String,
    val year: Int?,
    val songs: List<Song>,
    val searchKey: String,
    val songSearchKey: String,
    val letter: String,
) {
    val cover: Song get() = songs.first()
}

/** An album as it appears on an artist's page: only the songs credited to that artist. */
data class ArtistAlbum(
    val albumKey: String,
    val title: String,
    val year: Int?,
    val cover: Song,
    val songs: List<Song>,
)

data class Artist(
    /** Normalized name, so "A.R. Rahman" and "A. R. Rahman" share one artist. */
    val id: String,
    val name: String,
    val albums: List<ArtistAlbum>,
    val songs: List<Song>,
    val cover: Song?,
    val searchKey: String,
    val songSearchKey: String,
    val letter: String,
)

data class Playlist(
    val id: String,
    val name: String,
    val songs: List<Song>,
    /** The playlist's own cover (an image named like the playlist), if there is one. */
    val coverUri: Uri?,
    /** Up to four covers for a mosaic when there's no cover image. */
    val coverSongs: List<Song>,
    val searchKey: String,
    val songSearchKey: String,
    val letter: String,
) {
    val durationMs: Long get() = songs.sumOf { it.durationMs }
}

/** A music video kept on the phone (in a "Music Videos" folder). */
data class Video(
    val id: Long,
    val uri: Uri,
    val title: String,
    val artist: String?,
    val durationMs: Long,
    val searchKey: String,
    val letter: String,
)

data class Library(
    val videos: List<Video> = emptyList(),
    val songs: List<Song> = emptyList(),
    val albums: List<Album> = emptyList(),
    val artists: List<Artist> = emptyList(),
    val playlists: List<Playlist> = emptyList(),
) {
    val songsById: Map<Long, Song> by lazy { songs.associateBy { it.id } }
    val albumsByKey: Map<String, Album> by lazy { albums.associateBy { it.key } }
    val artistsById: Map<String, Artist> by lazy { artists.associateBy { it.id } }
    val playlistsById: Map<String, Playlist> by lazy { playlists.associateBy { it.id } }

    fun song(mediaId: String?): Song? = mediaId?.toLongOrNull()?.let { songsById[it] }

    /** The artists credited on a song ("A & B feat. C"), as library artists. */
    fun creditedArtists(song: Song): List<Artist> =
        (ArtistCredits.names(song.artist) + ArtistCredits.names(song.albumArtist))
            .map { ArtistCredits.key(it) }
            .distinct()
            .mapNotNull { artistsById[it] }
}
