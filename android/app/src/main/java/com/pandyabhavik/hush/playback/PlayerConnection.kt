package com.pandyabhavik.hush.playback

import android.content.ComponentName
import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.Player
import androidx.media3.session.MediaController
import androidx.media3.session.SessionToken
import com.pandyabhavik.hush.data.Prefs
import com.pandyabhavik.hush.data.Song
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.guava.await
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

/**
 * The app's side of playback: talks to [PlaybackService] and exposes what's playing as Compose
 * state. Shuffle is Hush's own (it reorders what's coming up), so Up Next always shows the real order.
 */
class PlayerConnection(private val context: Context, private val prefs: Prefs) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private var controller: MediaController? = null

    var currentId by mutableStateOf<String?>(null); private set
    var isPlaying by mutableStateOf(false); private set
    var queue by mutableStateOf<List<String>>(emptyList()); private set
    var currentIndex by mutableIntStateOf(0); private set
    var positionMs by mutableLongStateOf(0L); private set
    var durationMs by mutableLongStateOf(0L); private set
    var repeatMode by mutableIntStateOf(Player.REPEAT_MODE_OFF); private set
    var shuffled by mutableStateOf(prefs.getBoolean("shuffled", false)); private set

    /** The upcoming songs in their unshuffled order, to put back when shuffle is turned off. */
    private var unshuffledOrder: List<String> = emptyList()

    val upNext: List<String> get() = queue.drop(currentIndex + 1)

    fun connect() {
        if (controller != null) return
        val token = SessionToken(context, ComponentName(context, PlaybackService::class.java))
        scope.launch {
            val c = runCatching { MediaController.Builder(context, token).buildAsync().await() }.getOrNull() ?: return@launch
            controller = c
            c.addListener(object : Player.Listener {
                override fun onEvents(player: Player, events: Player.Events) = refresh()
            })
            if (c.mediaItemCount == 0) restoreSession(c)
            refresh()
            while (isActive) {
                controller?.let {
                    positionMs = it.currentPosition
                    durationMs = it.duration.coerceAtLeast(0)
                }
                delay(if (isPlaying) 250 else 1000)
            }
        }
    }

    fun release() {
        controller?.let { prefs.savePosition(it.currentPosition) }
        controller?.release()
        controller = null
    }

    private fun restoreSession(c: MediaController) {
        val (ids, index, position) = prefs.session() ?: return
        c.setMediaItems(ids.map(::item), index.coerceIn(0, ids.lastIndex), position)
        c.prepare()
    }

    private fun refresh() {
        val c = controller ?: return
        currentId = c.currentMediaItem?.mediaId
        isPlaying = c.isPlaying
        currentIndex = c.currentMediaItemIndex
        queue = (0 until c.mediaItemCount).map { c.getMediaItemAt(it).mediaId }
        repeatMode = c.repeatMode
        positionMs = c.currentPosition
        durationMs = c.duration.coerceAtLeast(0)
    }

    private fun item(id: String): MediaItem = MediaItem.Builder().setMediaId(id).build()

    private fun item(song: Song): MediaItem = MediaItem.Builder()
        .setMediaId(song.mediaId)
        .setMediaMetadata(
            MediaMetadata.Builder()
                .setTitle(song.title)
                .setArtist(song.artist)
                .setAlbumTitle(song.album)
                .setAlbumArtist(song.albumArtist)
                .build(),
        )
        .build()

    // MARK: Playing

    fun play(songs: List<Song>, startIndex: Int = 0) {
        val c = controller ?: return
        if (songs.isEmpty()) return
        setShuffle(false)
        c.setMediaItems(songs.map(::item), startIndex.coerceIn(0, songs.lastIndex), 0)
        c.prepare()
        c.play()
    }

    fun playShuffled(songs: List<Song>) {
        val c = controller ?: return
        if (songs.isEmpty()) return
        unshuffledOrder = songs.map { it.mediaId }
        setShuffle(true)
        c.setMediaItems(songs.shuffled().map(::item), 0, 0)
        c.prepare()
        c.play()
    }

    fun togglePlayback() {
        val c = controller ?: return
        if (c.isPlaying) c.pause() else {
            if (c.playbackState == Player.STATE_IDLE) c.prepare()
            if (c.playbackState == Player.STATE_ENDED) c.seekToDefaultPosition(0)
            c.play()
        }
    }

    fun next() = controller?.seekToNextMediaItem() ?: Unit

    /** Back to the start of the song, or to the previous one in the first three seconds. */
    fun previous() {
        val c = controller ?: return
        if (c.currentPosition > 3000 || !c.hasPreviousMediaItem()) c.seekTo(0) else c.seekToPreviousMediaItem()
    }

    fun seek(ms: Long) {
        controller?.seekTo(ms)
        positionMs = ms
    }

    fun cycleRepeat() {
        val c = controller ?: return
        c.repeatMode = when (c.repeatMode) {
            Player.REPEAT_MODE_OFF -> Player.REPEAT_MODE_ALL
            Player.REPEAT_MODE_ALL -> Player.REPEAT_MODE_ONE
            else -> Player.REPEAT_MODE_OFF
        }
    }

    fun toggleShuffle() {
        val c = controller ?: return
        val start = c.currentMediaItemIndex + 1
        val upcoming = (start until c.mediaItemCount).map { c.getMediaItemAt(it) }
        if (!shuffled) {
            unshuffledOrder = upcoming.map { it.mediaId }
            setShuffle(true)
            if (upcoming.size > 1) c.replaceMediaItems(start, c.mediaItemCount, upcoming.shuffled())
        } else {
            setShuffle(false)
            val rank = unshuffledOrder.withIndex().associate { it.value to it.index }
            val ordered = upcoming.sortedBy { rank[it.mediaId] ?: Int.MAX_VALUE }
            if (upcoming.size > 1) c.replaceMediaItems(start, c.mediaItemCount, ordered)
        }
    }

    private fun setShuffle(on: Boolean) {
        shuffled = on
        prefs.putBoolean("shuffled", on)
    }

    // MARK: Up Next

    fun playNext(songs: List<Song>) {
        val c = controller ?: return
        if (c.mediaItemCount == 0) return play(songs)
        c.addMediaItems(c.currentMediaItemIndex + 1, songs.map(::item))
    }

    fun addToQueue(songs: List<Song>) {
        val c = controller ?: return
        if (c.mediaItemCount == 0) return play(songs)
        c.addMediaItems(songs.map(::item))
    }

    /** [offset] counts from the first song after the current one. */
    fun jumpToUpNext(offset: Int) {
        val c = controller ?: return
        c.seekToDefaultPosition(c.currentMediaItemIndex + 1 + offset)
        c.play()
    }

    fun removeFromUpNext(offset: Int) {
        val c = controller ?: return
        c.removeMediaItem(c.currentMediaItemIndex + 1 + offset)
    }

    fun moveInUpNext(from: Int, to: Int) {
        val c = controller ?: return
        if (from == to) return
        val base = c.currentMediaItemIndex + 1
        c.moveMediaItem(base + from, base + to)
    }

    fun clearUpNext() {
        val c = controller ?: return
        val start = c.currentMediaItemIndex + 1
        if (start < c.mediaItemCount) c.removeMediaItems(start, c.mediaItemCount)
    }
}
