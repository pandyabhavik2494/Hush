package com.pandyabhavik.hush.playback

import android.content.ContentUris
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.provider.MediaStore
import androidx.media3.common.C
import androidx.media3.common.DeviceInfo
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.Player
import androidx.media3.common.SimpleBasePlayer
import androidx.media3.common.util.UnstableApi
import com.google.common.util.concurrent.Futures
import com.google.common.util.concurrent.ListenableFuture
import java.util.concurrent.Executors

/** What Hush knows about a song from MediaStore, for a speaker that only gets a web address. */
data class SongInfo(val title: String, val artist: String, val album: String, val durationMs: Long, val mimeType: String)

/**
 * Plays Hush's queue on a Sonos (or other UPnP/DLNA) speaker. The queue stays on the phone; the
 * speaker is given one song at a time as a web address on [server], and Hush moves to the next song
 * when the speaker reports the last one finished. The speaker is asked where it is once a second.
 */
@UnstableApi
class SpeakerPlayer(
    private val context: Context,
    val speaker: Speaker,
    private val server: SongServer,
    /** Told about a speaker that stopped answering or turned a song down. */
    private val onProblem: (String) -> Unit,
) : SimpleBasePlayer(Looper.getMainLooper()) {

    private class Entry(val uid: Any, val item: MediaItem)

    private val main = Handler(Looper.getMainLooper())
    private val io = Executors.newSingleThreadExecutor { r -> Thread(r, "hush-speaker").apply { isDaemon = true } }

    private val entries = mutableListOf<Entry>()
    private var index = 0
    private var playWhenReady = false
    private var playbackState = Player.STATE_IDLE
    private var repeatMode = Player.REPEAT_MODE_OFF
    private var volume = 20
    private var muted = false

    /** Where the speaker said it was, and when it said so. */
    private var positionMs = 0L
    private var positionAt = SystemClock.elapsedRealtime()
    private var speakerPlaying = false

    /** The entry the speaker has been given, and whether it has been heard playing it. */
    private var loadedUid: Any? = null
    private var loadedUrl: String? = null
    private var heardPlaying = false
    /** Bumped on every load, so an answer about an older song is ignored. */
    private var generation = 0
    private var failuresInARow = 0
    private var released = false

    @Volatile private var catalog: Map<String, SongInfo> = emptyMap()
    private var playlistCache: List<MediaItemData>? = null


    // MARK: State

    override fun getState(): State {
        val playlist = playlistCache ?: entries.map { entry ->
            val info = catalog[entry.item.mediaId]
            MediaItemData.Builder(entry.uid)
                .setMediaItem(entry.item)
                .setMediaMetadata(metadata(entry.item, info))
                .setDurationUs(info?.durationMs?.takeIf { it > 0 }?.let { it * 1000 } ?: C.TIME_UNSET)
                .setIsSeekable(true)
                .build()
        }.also { playlistCache = it }
        val empty = playlist.isEmpty()
        val state = when {
            empty && playbackState != Player.STATE_IDLE -> Player.STATE_ENDED
            else -> playbackState
        }
        val anchor = positionMs
        val since = positionAt
        val moving = speakerPlaying && playWhenReady && state == Player.STATE_READY
        return State.Builder()
            .setAvailableCommands(COMMANDS)
            .setPlayWhenReady(playWhenReady, Player.PLAY_WHEN_READY_CHANGE_REASON_USER_REQUEST)
            .setPlaybackState(state)
            .setRepeatMode(repeatMode)
            .setPlaylist(playlist)
            .setCurrentMediaItemIndex(if (empty) C.INDEX_UNSET else index.coerceIn(0, playlist.lastIndex))
            .setContentPositionMs(PositionSupplier {
                if (moving) anchor + (SystemClock.elapsedRealtime() - since) else anchor
            })
            .setDeviceInfo(DEVICE)
            .setDeviceVolume(volume)
            .setIsDeviceMuted(muted)
            .build()
    }

    private fun metadata(item: MediaItem, info: SongInfo?): MediaMetadata {
        val given = item.mediaMetadata
        if (given.title != null || info == null) return given
        return given.buildUpon()
            .setTitle(info.title)
            .setArtist(info.artist)
            .setAlbumTitle(info.album)
            .build()
    }

    private fun changed(playlist: Boolean = false) {
        if (playlist) playlistCache = null
        invalidateState()
    }

    private fun current(): Entry? = entries.getOrNull(index)

    private fun setPosition(ms: Long) {
        positionMs = ms.coerceAtLeast(0)
        positionAt = SystemClock.elapsedRealtime()
    }

    // MARK: Commands from Hush, the notification and the lock screen

    override fun handleSetMediaItems(mediaItems: MutableList<MediaItem>, startIndex: Int, startPositionMs: Long): ListenableFuture<*> {
        entries.clear()
        mediaItems.forEach { entries += Entry(Any(), it) }
        index = if (startIndex == C.INDEX_UNSET) 0 else startIndex.coerceIn(0, (entries.size - 1).coerceAtLeast(0))
        setPosition(if (startPositionMs == C.TIME_UNSET) 0 else startPositionMs)
        loadedUid = null
        if (entries.isEmpty()) {
            if (playbackState != Player.STATE_IDLE) playbackState = Player.STATE_ENDED
            stopSpeaker()
        } else if (playbackState != Player.STATE_IDLE) {
            load(positionMs)
        }
        changed(playlist = true)
        return Futures.immediateVoidFuture()
    }

    override fun handlePrepare(): ListenableFuture<*> {
        if (entries.isEmpty()) {
            playbackState = Player.STATE_ENDED
        } else {
            playbackState = Player.STATE_BUFFERING
            load(positionMs)
        }
        changed()
        return Futures.immediateVoidFuture()
    }

    override fun handleSetPlayWhenReady(playWhenReady: Boolean): ListenableFuture<*> {
        this.playWhenReady = playWhenReady
        commandAt = SystemClock.elapsedRealtime()
        val entry = current()
        if (entry != null && playbackState != Player.STATE_IDLE && playbackState != Player.STATE_ENDED) {
            if (loadedUid !== entry.uid) {
                load(positionMs)
            } else {
                val position = currentPositionNow()
                setPosition(position)
                speakerPlaying = playWhenReady
                send { if (playWhenReady) play() else pause() }
            }
        }
        changed()
        return Futures.immediateVoidFuture()
    }

    override fun handleStop(): ListenableFuture<*> {
        setPosition(currentPositionNow())
        playbackState = Player.STATE_IDLE
        loadedUid = null
        stopSpeaker()
        changed()
        return Futures.immediateVoidFuture()
    }

    override fun handleRelease(): ListenableFuture<*> {
        released = true
        main.removeCallbacksAndMessages(null)
        io.shutdown()
        return Futures.immediateVoidFuture()
    }

    override fun handleSetRepeatMode(repeatMode: Int): ListenableFuture<*> {
        this.repeatMode = repeatMode
        changed()
        return Futures.immediateVoidFuture()
    }

    override fun handleSeek(mediaItemIndex: Int, positionMs: Long, seekCommand: Int): ListenableFuture<*> {
        if (entries.isEmpty()) return Futures.immediateVoidFuture()
        val target = if (mediaItemIndex == C.INDEX_UNSET) index else mediaItemIndex.coerceIn(0, entries.lastIndex)
        val position = if (positionMs == C.TIME_UNSET) 0 else positionMs
        val sameSong = target == index && loadedUid === current()?.uid
        index = target
        setPosition(position)
        if (playbackState == Player.STATE_ENDED) playbackState = Player.STATE_BUFFERING
        if (playbackState != Player.STATE_IDLE) {
            if (sameSong) {
                val gen = generation
                send { if (gen == generation) seek(position) }
            } else {
                load(position)
            }
        }
        changed()
        return Futures.immediateVoidFuture()
    }

    override fun handleAddMediaItems(index: Int, mediaItems: MutableList<MediaItem>): ListenableFuture<*> {
        val at = index.coerceIn(0, entries.size)
        entries.addAll(at, mediaItems.map { Entry(Any(), it) })
        if (entries.size == mediaItems.size) {
            this.index = 0
        } else if (at <= this.index) {
            this.index += mediaItems.size
        }
        changed(playlist = true)
        return Futures.immediateVoidFuture()
    }

    override fun handleRemoveMediaItems(fromIndex: Int, toIndex: Int): ListenableFuture<*> {
        val playing = current()
        val from = fromIndex.coerceIn(0, entries.size)
        val to = toIndex.coerceIn(from, entries.size)
        repeat(to - from) { entries.removeAt(from) }
        when {
            entries.isEmpty() -> {
                index = 0
                if (playbackState != Player.STATE_IDLE) playbackState = Player.STATE_ENDED
                loadedUid = null
                stopSpeaker()
            }
            playing != null && entries.any { it === playing } -> index = entries.indexOf(playing)
            else -> {
                // The song playing was removed: on to whatever now sits in its place.
                index = from.coerceAtMost(entries.lastIndex)
                setPosition(0)
                if (playbackState != Player.STATE_IDLE) load(0)
            }
        }
        changed(playlist = true)
        return Futures.immediateVoidFuture()
    }

    override fun handleMoveMediaItems(fromIndex: Int, toIndex: Int, newIndex: Int): ListenableFuture<*> {
        val playing = current()
        val moved = entries.subList(fromIndex, toIndex).toList()
        repeat(toIndex - fromIndex) { entries.removeAt(fromIndex) }
        entries.addAll(newIndex.coerceIn(0, entries.size), moved)
        if (playing != null) index = entries.indexOf(playing)
        changed(playlist = true)
        return Futures.immediateVoidFuture()
    }

    override fun handleReplaceMediaItems(fromIndex: Int, toIndex: Int, mediaItems: MutableList<MediaItem>): ListenableFuture<*> {
        val playing = current()
        val from = fromIndex.coerceIn(0, entries.size)
        val to = toIndex.coerceIn(from, entries.size)
        repeat(to - from) { entries.removeAt(from) }
        entries.addAll(from, mediaItems.map { Entry(Any(), it) })
        if (playing != null && entries.any { it === playing }) {
            index = entries.indexOf(playing)
        } else if (playing != null && index in from until to) {
            // The song playing was swapped for another at the same place.
            index = index.coerceAtMost(entries.lastIndex)
            setPosition(0)
            if (playbackState != Player.STATE_IDLE && entries.isNotEmpty()) load(0)
        }
        changed(playlist = true)
        return Futures.immediateVoidFuture()
    }

    override fun handleSetDeviceVolume(deviceVolume: Int, flags: Int): ListenableFuture<*> {
        setVolume(deviceVolume)
        return Futures.immediateVoidFuture()
    }

    override fun handleIncreaseDeviceVolume(flags: Int): ListenableFuture<*> {
        setVolume(volume + 3)
        return Futures.immediateVoidFuture()
    }

    override fun handleDecreaseDeviceVolume(flags: Int): ListenableFuture<*> {
        setVolume(volume - 3)
        return Futures.immediateVoidFuture()
    }

    override fun handleSetDeviceMuted(muted: Boolean, flags: Int): ListenableFuture<*> {
        this.muted = muted
        changed()
        send {
            runCatching {
                if (speaker.groupRendering != null) {
                    Upnp.call(speaker.groupRendering, Upnp.GROUP_RENDERING, "SetGroupMute", listOf("InstanceID" to "0", "DesiredMute" to if (muted) "1" else "0"))
                } else if (speaker.rendering != null) {
                    Upnp.call(speaker.rendering, Upnp.RENDERING, "SetMute", listOf("InstanceID" to "0", "Channel" to "Master", "DesiredMute" to if (muted) "1" else "0"))
                }
            }
        }
        return Futures.immediateVoidFuture()
    }

    /** The speaker's volume, 0 to 100. */
    val speakerVolume: Int get() = volume

    /** The latest volume asked for and not yet sent; a dragged slider sends only where it ends up. */
    private val pendingVolume = java.util.concurrent.atomic.AtomicInteger(-1)

    fun setVolume(value: Int) {
        val target = value.coerceIn(0, 100)
        volume = target
        Speakers.volume = target
        changed()
        if (pendingVolume.getAndSet(target) != -1) return
        send {
            val target = pendingVolume.getAndSet(-1)
            if (target >= 0) runCatching {
                if (speaker.groupRendering != null) {
                    Upnp.call(speaker.groupRendering, Upnp.GROUP_RENDERING, "SetGroupVolume", listOf("InstanceID" to "0", "DesiredVolume" to target.toString()))
                } else if (speaker.rendering != null) {
                    Upnp.call(speaker.rendering, Upnp.RENDERING, "SetVolume", listOf("InstanceID" to "0", "Channel" to "Master", "DesiredVolume" to target.toString()))
                }
            }
        }
    }

    /** Stops the speaker (when Hush moves elsewhere), without waiting for it. */
    fun stopSpeaker() {
        generation++
        send { runCatching { Upnp.call(speaker.avTransport, Upnp.AV_TRANSPORT, "Stop") } }
    }

    // MARK: Talking to the speaker

    private fun currentPositionNow(): Long =
        if (speakerPlaying && playWhenReady && playbackState == Player.STATE_READY) {
            positionMs + (SystemClock.elapsedRealtime() - positionAt)
        } else {
            positionMs
        }

    private fun send(block: Calls.() -> Unit) {
        if (released) return
        runCatching { io.execute { runCatching { calls.block() } } }
    }

    private inner class Calls {
        fun play() = Upnp.call(speaker.avTransport, Upnp.AV_TRANSPORT, "Play", listOf("InstanceID" to "0", "Speed" to "1"))
        fun pause() = runCatching { Upnp.call(speaker.avTransport, Upnp.AV_TRANSPORT, "Pause") }
        fun seek(ms: Long) = runCatching {
            Upnp.call(speaker.avTransport, Upnp.AV_TRANSPORT, "Seek", listOf("InstanceID" to "0", "Unit" to "REL_TIME", "Target" to Upnp.formatTime(ms)))
        }
    }

    private val calls = Calls()

    /** Gives the speaker the current song, from [startMs], and plays it if Hush is playing. */
    private fun load(startMs: Long) {
        val entry = current() ?: return
        val gen = ++generation
        loadedUid = entry.uid
        heardPlaying = false
        speakerPlaying = false
        setPosition(startMs)
        if (playbackState != Player.STATE_IDLE) playbackState = Player.STATE_BUFFERING
        val play = playWhenReady
        val id = entry.item.mediaId
        val given = entry.item.mediaMetadata
        io.execute {
            if (gen != generation) return@execute
            val info = catalog[id] ?: lookup(id)
            val mime = SongServer.speakerMimeType(info?.mimeType)
            val url = server.songUrl(id, mime)
            if (url == null) {
                main.post { failed(gen, "Hush couldn't share the song on the Wi-Fi") }
                return@execute
            }
            val title = given.title?.toString() ?: info?.title ?: "Song"
            val artist = given.artist?.toString() ?: info?.artist ?: ""
            val album = given.albumTitle?.toString() ?: info?.album ?: ""
            val meta = didl(id, url, title, artist, album, server.coverUrl(id), mime, info?.durationMs ?: 0)
            try {
                Upnp.call(speaker.avTransport, Upnp.AV_TRANSPORT, "SetAVTransportURI", listOf("InstanceID" to "0", "CurrentURI" to url, "CurrentURIMetaData" to meta))
                if (gen != generation) return@execute
                if (startMs > 1000) {
                    // Some speakers refuse to seek until the song has loaded: a few tries.
                    for (attempt in 0 until 6) {
                        if (calls.seek(startMs).isSuccess) break
                        Thread.sleep(300)
                    }
                }
                if (play && gen == generation) calls.play()
                main.post {
                    if (gen != generation) return@post
                    loadedUrl = url
                    failuresInARow = 0
                }
            } catch (e: Exception) {
                main.post { failed(gen, e.message ?: "The speaker didn't answer") }
            }
        }
    }

    /** A song the speaker wouldn't take: skip it, unless nothing is working at all. */
    private fun failed(gen: Int, reason: String) {
        if (gen != generation || released) return
        failuresInARow++
        if (failuresInARow >= 3 || entries.size <= 1) {
            playWhenReady = false
            playbackState = Player.STATE_READY
            loadedUid = null
            onProblem("${speaker.name}: $reason")
            changed()
            return
        }
        val next = nextIndex() ?: run {
            playbackState = Player.STATE_ENDED
            changed()
            return
        }
        index = next
        load(0)
        changed()
    }

    private fun nextIndex(): Int? = when {
        repeatMode == Player.REPEAT_MODE_ONE -> index
        index + 1 < entries.size -> index + 1
        repeatMode == Player.REPEAT_MODE_ALL && entries.isNotEmpty() -> 0
        else -> null
    }

    // MARK: Asking the speaker where it is

    private var pollInFlight = false
    /** When Hush last played or paused: the speaker's answers lag behind for a moment. */
    private var commandAt = 0L
    private val settled: Boolean get() = SystemClock.elapsedRealtime() - commandAt > 3000
    private var silentPolls = 0

    private val poller = object : Runnable {
        override fun run() {
            if (released) return
            if (!pollInFlight && loadedUid != null) poll()
            main.postDelayed(this, if (playWhenReady) 1000 else 3000)
        }
    }

    private fun poll() {
        pollInFlight = true
        val gen = generation
        io.execute {
            val result = runCatching {
                val transport = Upnp.call(speaker.avTransport, Upnp.AV_TRANSPORT, "GetTransportInfo")
                val position = Upnp.call(speaker.avTransport, Upnp.AV_TRANSPORT, "GetPositionInfo")
                Triple(Upnp.tag(transport, "CurrentTransportState"), position, Upnp.tag(position, "TrackURI"))
            }
            main.post {
                pollInFlight = false
                if (gen != generation || released) return@post
                val (state, position, uri) = result.getOrElse {
                    if (++silentPolls == 8) onProblem("${speaker.name} stopped answering")
                    return@post
                }
                silentPolls = 0
                heard(state.orEmpty(), Upnp.parseTime(Upnp.tag(position, "RelTime")), Upnp.parseTime(Upnp.tag(position, "TrackDuration")), uri)
            }
        }
    }

    private fun heard(state: String, relMs: Long?, durationMs: Long?, uri: String?) {
        // Something else is playing on the speaker now (the Sonos app, say): let go of it.
        if (loadedUrl != null && !uri.isNullOrEmpty() && !uri.contains("/song/") && state == "PLAYING" && heardPlaying) {
            playWhenReady = false
            speakerPlaying = false
            loadedUid = null
            loadedUrl = null
            playbackState = Player.STATE_READY
            changed()
            return
        }
        if (relMs != null) setPosition(relMs)
        when (state) {
            "PLAYING" -> {
                heardPlaying = true
                speakerPlaying = true
                if (playbackState != Player.STATE_IDLE) playbackState = Player.STATE_READY
                if (!playWhenReady && settled) playWhenReady = true // Played from the speaker's own button.
            }
            "PAUSED_PLAYBACK" -> {
                speakerPlaying = false
                if (playbackState != Player.STATE_IDLE) playbackState = Player.STATE_READY
                // Paused on the speaker itself (or another app): show it paused here too.
                if (heardPlaying && playWhenReady && settled) playWhenReady = false
            }
            "TRANSITIONING" -> speakerPlaying = false
            "STOPPED", "NO_MEDIA_PRESENT" -> {
                speakerPlaying = false
                if (heardPlaying && playWhenReady && settled) {
                    // The song finished.
                    val next = nextIndex()
                    if (next == null) {
                        playbackState = Player.STATE_ENDED
                        loadedUid = null
                    } else {
                        index = next
                        load(0)
                    }
                } else if (!playWhenReady && playbackState == Player.STATE_BUFFERING) {
                    playbackState = Player.STATE_READY
                }
            }
        }
        if (durationMs != null && durationMs > 0) {
            val entry = current()
            if (entry != null && catalog[entry.item.mediaId]?.durationMs?.let { it <= 0 } != false) {
                catalog = catalog + (entry.item.mediaId to (catalog[entry.item.mediaId]
                    ?: SongInfo("", "", "", durationMs, "")).copy(durationMs = durationMs))
                playlistCache = null
            }
        }
        changed()
    }

    private fun readVolume() {
        runCatching {
            val level = if (speaker.groupRendering != null) {
                Upnp.tag(Upnp.call(speaker.groupRendering, Upnp.GROUP_RENDERING, "GetGroupVolume"), "CurrentVolume")
            } else if (speaker.rendering != null) {
                Upnp.tag(Upnp.call(speaker.rendering, Upnp.RENDERING, "GetVolume", listOf("InstanceID" to "0", "Channel" to "Master")), "CurrentVolume")
            } else null
            level?.toIntOrNull()?.let { v -> main.post { volume = v; Speakers.volume = v; changed() } }
        }
    }

    // MARK: Songs

    private fun readCatalog(): Map<String, SongInfo> {
        val map = HashMap<String, SongInfo>()
        runCatching {
            context.contentResolver.query(
                MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
                arrayOf(MediaStore.Audio.Media._ID, MediaStore.Audio.Media.TITLE, MediaStore.Audio.Media.ARTIST,
                    MediaStore.Audio.Media.ALBUM, MediaStore.Audio.Media.DURATION, MediaStore.Audio.Media.MIME_TYPE),
                null, null, null,
            )?.use { c ->
                while (c.moveToNext()) {
                    map[c.getLong(0).toString()] = SongInfo(
                        c.getString(1).orEmpty(), c.getString(2).orEmpty(), c.getString(3).orEmpty(), c.getLong(4), c.getString(5).orEmpty(),
                    )
                }
            }
        }
        return map
    }

    private fun lookup(id: String): SongInfo? {
        val longId = id.toLongOrNull() ?: return null
        val uri = ContentUris.withAppendedId(MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, longId)
        return runCatching {
            context.contentResolver.query(
                uri,
                arrayOf(MediaStore.Audio.Media.TITLE, MediaStore.Audio.Media.ARTIST, MediaStore.Audio.Media.ALBUM,
                    MediaStore.Audio.Media.DURATION, MediaStore.Audio.Media.MIME_TYPE),
                null, null, null,
            )?.use { c ->
                if (c.moveToFirst()) SongInfo(c.getString(0).orEmpty(), c.getString(1).orEmpty(), c.getString(2).orEmpty(), c.getLong(3), c.getString(4).orEmpty()) else null
            }
        }.getOrNull()
    }

    /** DIDL-Lite: the song's name, artist, album and cover, which Sonos shows in its app and on its screen. */
    private fun didl(id: String, url: String, title: String, artist: String, album: String, cover: String?, mime: String, durationMs: Long): String {
        val e = Upnp::escape
        val duration = if (durationMs > 0) " duration=\"${Upnp.formatTime(durationMs)}.000\"" else ""
        return "<DIDL-Lite xmlns:dc=\"http://purl.org/dc/elements/1.1/\" xmlns:upnp=\"urn:schemas-upnp-org:metadata-1-0/upnp/\" " +
            "xmlns:r=\"urn:schemas-rinconnetworks-com:metadata-1-0/\" xmlns=\"urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/\">" +
            "<item id=\"hush-$id\" parentID=\"hush\" restricted=\"1\">" +
            "<dc:title>${e(title)}</dc:title>" +
            "<dc:creator>${e(artist)}</dc:creator>" +
            "<upnp:artist>${e(artist)}</upnp:artist>" +
            "<upnp:album>${e(album)}</upnp:album>" +
            (cover?.let { "<upnp:albumArtURI>${e(it)}</upnp:albumArtURI>" } ?: "") +
            "<upnp:class>object.item.audioItem.musicTrack</upnp:class>" +
            "<res protocolInfo=\"http-get:*:$mime:*\"$duration>${e(url)}</res>" +
            "</item></DIDL-Lite>"
    }

    // Last, once everything above is set up.
    init {
        io.execute {
            val read = readCatalog()
            main.post { if (!released) { catalog = read; playlistCache = null; invalidateState() } }
            readVolume()
        }
        main.post(poller)
    }

    private companion object {
        val DEVICE: DeviceInfo = DeviceInfo.Builder(DeviceInfo.PLAYBACK_TYPE_REMOTE).setMinVolume(0).setMaxVolume(100).build()

        val COMMANDS: Player.Commands = Player.Commands.Builder()
            .addAll(
                Player.COMMAND_PLAY_PAUSE,
                Player.COMMAND_PREPARE,
                Player.COMMAND_STOP,
                Player.COMMAND_SEEK_TO_DEFAULT_POSITION,
                Player.COMMAND_SEEK_IN_CURRENT_MEDIA_ITEM,
                Player.COMMAND_SEEK_TO_PREVIOUS_MEDIA_ITEM,
                Player.COMMAND_SEEK_TO_PREVIOUS,
                Player.COMMAND_SEEK_TO_NEXT_MEDIA_ITEM,
                Player.COMMAND_SEEK_TO_NEXT,
                Player.COMMAND_SEEK_TO_MEDIA_ITEM,
                Player.COMMAND_SET_REPEAT_MODE,
                Player.COMMAND_GET_CURRENT_MEDIA_ITEM,
                Player.COMMAND_GET_TIMELINE,
                Player.COMMAND_GET_METADATA,
                Player.COMMAND_SET_MEDIA_ITEM,
                Player.COMMAND_CHANGE_MEDIA_ITEMS,
                Player.COMMAND_GET_DEVICE_VOLUME,
                Player.COMMAND_SET_DEVICE_VOLUME_WITH_FLAGS,
                Player.COMMAND_ADJUST_DEVICE_VOLUME_WITH_FLAGS,
                Player.COMMAND_RELEASE,
            )
            .build()
    }
}
