package com.pandyabhavik.hush.playback

import android.app.PendingIntent
import android.content.ContentUris
import android.content.Intent
import android.media.AudioDeviceCallback
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.net.wifi.WifiManager
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.provider.MediaStore
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.session.MediaSession
import androidx.media3.session.MediaSessionService
import com.google.common.util.concurrent.Futures
import com.google.common.util.concurrent.ListenableFuture
import com.pandyabhavik.hush.MainActivity
import com.pandyabhavik.hush.data.Prefs
import java.net.InetAddress

/**
 * Plays in the background, with lock-screen and notification controls. Music plays on the phone
 * (its speaker, or whatever Bluetooth or wired output is chosen) through ExoPlayer, or on a Sonos
 * or other Wi-Fi speaker through [SpeakerPlayer]; the session moves between the two, carrying the
 * queue, the place in the song and whether it was playing.
 */
@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
class PlaybackService : MediaSessionService() {
    private var session: MediaSession? = null
    private lateinit var prefs: Prefs
    private lateinit var phone: ExoPlayer
    private var speakerPlayer: SpeakerPlayer? = null
    private var server: SongServer? = null
    private val main = Handler(Looper.getMainLooper())
    private var wifiLock: WifiManager.WifiLock? = null
    private var wakeLock: PowerManager.WakeLock? = null
    /** One for both players, so a song isn't counted twice when it moves between them. */
    private val saver by lazy { SessionSaver() }

    override fun onCreate() {
        super.onCreate()
        prefs = Prefs(this)
        val player = ExoPlayer.Builder(this)
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(C.USAGE_MEDIA)
                    .setContentType(C.AUDIO_CONTENT_TYPE_MUSIC)
                    .build(),
                true,
            )
            .setHandleAudioBecomingNoisy(true)
            .setWakeMode(C.WAKE_MODE_LOCAL)
            .build()
        phone = player
        player.addListener(saver)

        val openApp = PendingIntent.getActivity(
            this, 0, Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        session = MediaSession.Builder(this, player)
            .setSessionActivity(openApp)
            .setCallback(Callback())
            .build()
        Speakers.service = this
        getSystemService(AudioManager::class.java)?.registerAudioDeviceCallback(outputs, main)
    }

    // MARK: Where the music plays

    /** Hands the queue to [speaker] on the Wi-Fi. */
    fun useSpeaker(speaker: Speaker) {
        if (session == null || speakerPlayer?.speaker?.id == speaker.id) return
        Speakers.connecting = speaker
        Speakers.problem = null
        val songs = server ?: SongServer(applicationContext).also { server = it }
        // Finding the phone's own address on the Wi-Fi touches the network: not on the main thread.
        Thread({
            val ok = runCatching { songs.start(InetAddress.getByName(speaker.host)) }.isSuccess && songs.base != null
            main.post {
                if (Speakers.connecting?.id != speaker.id) return@post
                if (ok) switchToSpeaker(speaker, songs) else {
                    Speakers.connecting = null
                    Speakers.problem = "Hush couldn't reach ${speaker.name}. Is the phone on the same Wi-Fi?"
                }
            }
        }, "hush-speaker-start").start()
    }

    private fun switchToSpeaker(speaker: Speaker, songs: SongServer) {
        val s = session ?: return
        val from = s.player
        val place = Place.of(from)
        val target = SpeakerPlayer(applicationContext, speaker, songs) { problem -> Speakers.problem = problem }
        target.addListener(saver)
        target.addListener(locks)
        target.repeatMode = place.repeatMode
        target.setMediaItems(place.items, place.index, place.positionMs)
        target.playWhenReady = place.playWhenReady
        if (place.items.isNotEmpty()) target.prepare()
        if (from is SpeakerPlayer) {
            from.stopSpeaker()
            from.release()
        } else {
            phone.pause()
            phone.stop()
        }
        s.player = target
        speakerPlayer = target
        Speakers.current = speaker
        Speakers.connecting = null
        Speakers.volume = target.speakerVolume
        holdLocks(place.playWhenReady)
    }

    /** Back to the phone; [device] is the output to use, or null for Android's own choice. */
    fun usePhone(device: AudioDeviceInfo?) {
        Speakers.connecting = null
        val s = session
        val remote = speakerPlayer
        if (s != null && remote != null) {
            val place = Place.of(remote)
            remote.stopSpeaker()
            remote.release()
            speakerPlayer = null
            phone.repeatMode = place.repeatMode
            phone.setMediaItems(place.items.map(::resolve), place.index, place.positionMs)
            phone.playWhenReady = place.playWhenReady
            if (place.items.isNotEmpty()) phone.prepare()
            s.player = phone
            Speakers.current = null
            server?.stop()
            server = null
            holdLocks(false)
        }
        phone.setPreferredAudioDevice(device)
        Speakers.phoneOutput = device?.id
    }

    fun setSpeakerVolume(value: Int) {
        speakerPlayer?.setVolume(value)
    }

    /** The queue and the place in it, carried from one player to the other. */
    private class Place(val items: List<MediaItem>, val index: Int, val positionMs: Long, val playWhenReady: Boolean, val repeatMode: Int) {
        companion object {
            fun of(player: Player) = Place(
                items = (0 until player.mediaItemCount).map { player.getMediaItemAt(it) },
                index = player.currentMediaItemIndex.coerceAtLeast(0),
                positionMs = player.currentPosition.coerceAtLeast(0),
                playWhenReady = player.playWhenReady,
                repeatMode = player.repeatMode,
            )
        }
    }

    /**
     * A new Bluetooth or wired output connecting takes over, as it would in any other app; and when
     * the chosen output goes away, Android picks again.
     */
    private val outputs = object : AudioDeviceCallback() {
        override fun onAudioDevicesAdded(addedDevices: Array<out AudioDeviceInfo>) {
            if (Speakers.phoneOutput != null && addedDevices.any { it.isSink && it.type in PhoneOutputs.external }) {
                phone.setPreferredAudioDevice(null)
                Speakers.phoneOutput = null
            }
        }

        override fun onAudioDevicesRemoved(removedDevices: Array<out AudioDeviceInfo>) {
            if (removedDevices.any { it.id == Speakers.phoneOutput }) {
                phone.setPreferredAudioDevice(null)
                Speakers.phoneOutput = null
            }
        }
    }

    /** While a Wi-Fi speaker plays, the phone keeps its Wi-Fi awake: the speaker reads the song from it. */
    private val locks = object : Player.Listener {
        override fun onPlayWhenReadyChanged(playWhenReady: Boolean, reason: Int) = holdLocks(playWhenReady && speakerPlayer != null)
    }

    private fun holdLocks(on: Boolean) {
        if (on) {
            val wifi = wifiLock ?: getSystemService(WifiManager::class.java)
                ?.createWifiLock(WifiManager.WIFI_MODE_FULL_HIGH_PERF, "hush:speaker")
                ?.apply { setReferenceCounted(false) }
                .also { wifiLock = it }
            val wake = wakeLock ?: getSystemService(PowerManager::class.java)
                ?.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "hush:speaker")
                ?.apply { setReferenceCounted(false) }
                .also { wakeLock = it }
            runCatching { wifi?.acquire() }
            runCatching { wake?.acquire(6 * 60 * 60 * 1000L) }
        } else {
            runCatching { wifiLock?.takeIf { it.isHeld }?.release() }
            runCatching { wakeLock?.takeIf { it.isHeld }?.release() }
        }
    }

    override fun onGetSession(controllerInfo: MediaSession.ControllerInfo): MediaSession? = session

    override fun onTaskRemoved(rootIntent: Intent?) {
        val player = session?.player
        if (player == null || !player.playWhenReady || player.mediaItemCount == 0) stopSelf()
    }

    override fun onDestroy() {
        getSystemService(AudioManager::class.java)?.unregisterAudioDeviceCallback(outputs)
        speakerPlayer?.run {
            stopSpeaker()
            release()
        }
        speakerPlayer = null
        server?.stop()
        server = null
        holdLocks(false)
        if (Speakers.service === this) Speakers.service = null
        Speakers.current = null
        Speakers.connecting = null
        session?.release()
        phone.release()
        session = null
        super.onDestroy()
    }

    private inner class Callback : MediaSession.Callback {
        /** Controllers send items by id only; give them their file. */
        override fun onAddMediaItems(
            mediaSession: MediaSession,
            controller: MediaSession.ControllerInfo,
            mediaItems: MutableList<MediaItem>,
        ): ListenableFuture<MutableList<MediaItem>> =
            Futures.immediateFuture(mediaItems.map { resolve(it) }.toMutableList())

        /** "Play" from the lock screen or headphones after Hush was closed: the last queue. */
        override fun onPlaybackResumption(
            mediaSession: MediaSession,
            controller: MediaSession.ControllerInfo,
        ): ListenableFuture<MediaSession.MediaItemsWithStartPosition> {
            val (ids, index, position) = prefs.session()
                ?: return Futures.immediateFailedFuture(UnsupportedOperationException())
            val items = ids.map { resolve(MediaItem.Builder().setMediaId(it).build()) }
            return Futures.immediateFuture(
                MediaSession.MediaItemsWithStartPosition(items, index.coerceIn(0, items.lastIndex), position),
            )
        }
    }

    private fun resolve(item: MediaItem): MediaItem {
        if (item.localConfiguration != null) return item
        val id = item.mediaId.toLongOrNull() ?: return item
        val uri = ContentUris.withAppendedId(MediaStore.Audio.Media.getContentUri(MediaStore.VOLUME_EXTERNAL), id)
        return item.buildUpon().setUri(uri).build()
    }

    /** Remembers the queue and position, and counts plays. */
    private inner class SessionSaver : Player.Listener {
        private var countedFor: String? = null

        override fun onEvents(player: Player, events: Player.Events) {
            if (events.contains(Player.EVENT_TIMELINE_CHANGED)) {
                val ids = (0 until player.mediaItemCount).map { player.getMediaItemAt(it).mediaId }
                prefs.saveSession(ids, player.currentMediaItemIndex, player.currentPosition)
            } else if (events.containsAny(Player.EVENT_MEDIA_ITEM_TRANSITION, Player.EVENT_IS_PLAYING_CHANGED)) {
                // The queue is unchanged (it can be the whole library): only where we are in it.
                prefs.saveSessionPlace(player.currentMediaItemIndex, player.currentPosition)
            }
            if (events.contains(Player.EVENT_MEDIA_ITEM_TRANSITION) || events.contains(Player.EVENT_IS_PLAYING_CHANGED)) {
                val id = player.currentMediaItem?.mediaId
                if (player.isPlaying && id != null && id != countedFor) {
                    countedFor = id
                    id.toLongOrNull()?.let(prefs::countPlay)
                }
            }
        }

        override fun onMediaItemTransition(mediaItem: MediaItem?, reason: Int) {
            // Each new song (or another round of a repeated one) counts again.
            countedFor = null
        }
    }
}
