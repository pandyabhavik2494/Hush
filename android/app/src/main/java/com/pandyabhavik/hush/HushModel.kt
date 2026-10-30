package com.pandyabhavik.hush

import android.app.Application
import android.content.Intent
import android.database.ContentObserver
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.pandyabhavik.hush.data.ArtistPhotos
import com.pandyabhavik.hush.data.Library
import com.pandyabhavik.hush.data.LibraryLoader
import com.pandyabhavik.hush.data.Prefs
import com.pandyabhavik.hush.data.Video
import com.pandyabhavik.hush.playback.PlayerConnection
import com.pandyabhavik.hush.ui.Route
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** The library, settings and the player, shared by every screen. */
class HushModel(application: Application) : AndroidViewModel(application) {
    val prefs = Prefs(application)
    val player = PlayerConnection(application, prefs)

    var library by mutableStateOf(Library()); private set
    var loaded by mutableStateOf(false); private set
    var refreshing by mutableStateOf(false); private set
    var favoriteArtists by mutableStateOf(prefs.favoriteArtists); private set
    var playCounts by mutableStateOf(prefs.playCounts()); private set
    var playlistsFolder by mutableStateOf(prefs.playlistsFolder); private set
    var videosFolder by mutableStateOf(prefs.videosFolder); private set

    // Where you are in the app. Kept here, not in the screen, so nothing resets when the phone
    // is folded or unfolded, rotated, or Android rebuilds the screen.
    val pages = mutableStateListOf<Route>()
    var playerOpen by mutableStateOf(false)
    var video by mutableStateOf<Video?>(null)
    var videoResume: Pair<String, Long>? = null

    private var loadJob: Job? = null
    private var observing = false

    private val observer = object : ContentObserver(Handler(Looper.getMainLooper())) {
        override fun onChange(selfChange: Boolean) {
            // Songs being copied arrive in bursts; wait for things to settle.
            loadJob?.cancel()
            loadJob = viewModelScope.launch {
                delay(2000)
                load()
            }
        }
    }

    fun start() {
        player.connect()
        if (!observing) {
            observing = true
            getApplication<Application>().contentResolver.registerContentObserver(
                MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, true, observer,
            )
        }
        if (!loaded) viewModelScope.launch { load() }
    }

    private suspend fun load() {
        val app = getApplication<Application>()
        val playlists = playlistsFolder
        val videos = videosFolder
        library = withContext(Dispatchers.IO) { LibraryLoader.load(app, playlists, videos) }
        playCounts = prefs.playCounts()
        loaded = true
    }

    /** Pull to refresh: reread everything and look again for missing artist photos. */
    fun refresh() {
        if (refreshing) return
        refreshing = true
        viewModelScope.launch {
            withContext(Dispatchers.IO) { ArtistPhotos.forgetMisses(getApplication()) }
            load()
            refreshing = false
        }
    }

    fun refreshPlayCounts() {
        playCounts = prefs.playCounts()
    }

    fun setPlaylistsFolder(uri: Uri) {
        swapFolder(playlistsFolder, uri)
        prefs.playlistsFolder = uri.toString()
        playlistsFolder = uri.toString()
        refresh()
    }

    /** Hush may read only this folder for videos (no access to the phone's other videos). */
    fun setVideosFolder(uri: Uri) {
        swapFolder(videosFolder, uri)
        prefs.videosFolder = uri.toString()
        videosFolder = uri.toString()
        refresh()
    }

    private fun swapFolder(old: String?, new: Uri) {
        val resolver = getApplication<Application>().contentResolver
        if (new.scheme == "content") resolver.takePersistableUriPermission(new, Intent.FLAG_GRANT_READ_URI_PERMISSION)
        val held = listOfNotNull(playlistsFolder, videosFolder)
        // Let go of the old folder unless the other setting still uses it.
        if (old != null && old != new.toString() && held.count { it == old } == 1) {
            runCatching { resolver.releasePersistableUriPermission(Uri.parse(old), Intent.FLAG_GRANT_READ_URI_PERMISSION) }
        }
    }

    fun isFavorite(artistId: String) = artistId in favoriteArtists

    fun toggleFavorite(artistId: String) {
        favoriteArtists = if (artistId in favoriteArtists) favoriteArtists - artistId else favoriteArtists + artistId
        prefs.favoriteArtists = favoriteArtists
    }

    override fun onCleared() {
        getApplication<Application>().contentResolver.unregisterContentObserver(observer)
        player.release()
        super.onCleared()
    }
}
