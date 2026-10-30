package com.pandyabhavik.hush.playback

import android.app.PendingIntent
import android.content.ContentUris
import android.content.Intent
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

/** Plays in the background, with lock-screen and notification controls. */
class PlaybackService : MediaSessionService() {
    private var session: MediaSession? = null
    private lateinit var prefs: Prefs

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
        player.addListener(SessionSaver(player))

        val openApp = PendingIntent.getActivity(
            this, 0, Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        session = MediaSession.Builder(this, player)
            .setSessionActivity(openApp)
            .setCallback(Callback())
            .build()
    }

    override fun onGetSession(controllerInfo: MediaSession.ControllerInfo): MediaSession? = session

    override fun onTaskRemoved(rootIntent: Intent?) {
        val player = session?.player
        if (player == null || !player.playWhenReady || player.mediaItemCount == 0) stopSelf()
    }

    override fun onDestroy() {
        session?.run {
            player.release()
            release()
        }
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
    private inner class SessionSaver(private val player: ExoPlayer) : Player.Listener {
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
