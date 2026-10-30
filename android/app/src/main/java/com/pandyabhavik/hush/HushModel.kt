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
            reload(delayMs = 2000)
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
        if (!loaded && loadJob == null) reload()
    }

    /**
     * Reads the library again. A newer reload replaces one still running, so the last change
     * (a folder just picked, songs just copied) always wins and an older read never lands on top.
     */
    private fun reload(delayMs: Long = 0, forgetMisses: Boolean = false) {
        loadJob?.cancel()
        loadJob = viewModelScope.launch {
            if (delayMs > 0) delay(delayMs)
            if (forgetMisses) withContext(Dispatchers.IO) { ArtistPhotos.forgetMisses(getApplication()) }
            load()
            refreshing = false
        }
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
        refreshing = true
        reload(forgetMisses = true)
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

    /** Stop reading videos from the chosen folder. */
    fun forgetVideosFolder() {
        val old = videosFolder ?: return
        if (playlistsFolder != old && old.startsWith("content:")) {
            runCatching {
                getApplication<Application>().contentResolver
                    .releasePersistableUriPermission(Uri.parse(old), Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
        }
        prefs.videosFolder = null
        videosFolder = null
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
