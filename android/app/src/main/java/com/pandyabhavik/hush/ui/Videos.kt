package com.pandyabhavik.hush.ui

import android.app.Activity
import android.content.pm.ActivityInfo
import android.view.LayoutInflater
import android.view.WindowManager
import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.requiredSize
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.grid.LazyGridState
import androidx.compose.foundation.lazy.grid.itemsIndexed
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.rounded.AspectRatio
import androidx.compose.material.icons.rounded.Forward10
import androidx.compose.material.icons.rounded.Pause
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material.icons.rounded.Replay
import androidx.compose.material.icons.rounded.Replay10
import androidx.compose.material.icons.rounded.ScreenRotation
import androidx.compose.material.icons.rounded.StayCurrentLandscape
import androidx.compose.material.icons.rounded.StayCurrentPortrait
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.VideoSize
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.ui.PlayerView
import com.pandyabhavik.hush.HushModel
import com.pandyabhavik.hush.R
import com.pandyabhavik.hush.data.Video
import com.pandyabhavik.hush.data.VideoFolder
import com.pandyabhavik.hush.data.timeText
import kotlinx.coroutines.delay

/** The Videos tab: music videos from the one folder you chose, 16:9 tiles. */
@Composable
fun VideosTab(model: HushModel, query: String, state: LazyGridState, padding: PaddingValues, chooseFolder: () -> Unit) {
    val folder = model.videosFolder
    if (folder == null) {
        EmptyMessage(
            "Your music videos",
            "Choose the folder your music videos are in, such as Music Videos. Hush reads only that folder.",
            "Choose Videos Folder" to chooseFolder,
        )
        return
    }
    val videos = remember(model.library, query) {
        if (query.isEmpty()) model.library.videos else model.library.videos.filter { it.searchKey.contains(query) }
    }
    if (model.loaded && !model.refreshing && model.library.videos.isEmpty()) {
        EmptyMessage(
            "No music videos",
            "Hush found no videos in ${VideoFolder.name(folder)}. Videos copied there show up when you pull down to refresh.",
            "Choose Another Folder" to chooseFolder,
        )
        return
    }
    val actions = LocalActions.current
    // While a video plays, the tiles underneath stop reading frames: those reads use the same few
    // hardware video decoders the player needs, and could make the video fail to start.
    val playingVideo = model.video != null
    BoxWithConstraints {
        val columns = if (maxWidth < 600.dp) 2 else if (maxWidth < 900.dp) 3 else 4
        val targets = if (query.isEmpty()) letterTargets(videos, Video::letter) else emptyList()
        LibraryGrid(state, columns, padding, targets, rowSpacing = 20.dp) {
            itemsIndexed(videos, key = { _, v -> v.id }) { _, video ->
                Column(Modifier.clickableQuiet { actions.playVideo(video) }) {
                    Box(Modifier.fillMaxWidth().aspectRatio(16f / 9f).clip(RoundedCornerShape(8.dp)).background(Hush.card)) {
                        Cover(null, Modifier.fillMaxSize(), 0.dp, uri = video.uri.takeUnless { playingVideo }, aspect = 16f / 9f, videoFrame = true)
                        if (video.durationMs > 0) Text(
                            timeText(video.durationMs),
                            style = Hush.sans(11.sp),
                            modifier = Modifier.align(Alignment.BottomEnd).padding(6.dp)
                                .background(Color.Black.copy(alpha = 0.6f), RoundedCornerShape(4.dp)).padding(horizontal = 5.dp, vertical = 1.dp),
                        )
                    }
                    Spacer(Modifier.height(8.dp))
                    Text(video.title, style = Hush.sans(14.sp), maxLines = 2, overflow = TextOverflow.Ellipsis)
                    video.artist?.let { Text(it, style = Hush.sans(12.5.sp, Hush.muted), maxLines = 1, overflow = TextOverflow.Ellipsis) }
                }
            }
        }
    }
}

/** Player errors that mean a decoder was busy or failed to start, not that the file can't play. */
private val retryable = setOf(
    PlaybackException.ERROR_CODE_DECODER_INIT_FAILED,
    PlaybackException.ERROR_CODE_DECODER_QUERY_FAILED,
    PlaybackException.ERROR_CODE_DECODING_FAILED,
)

/** How the picture fits the screen, as in VLC. */
enum class VideoFit(val label: String) {
    Fit("Best Fit"), Fill("Fill"), Stretch("Stretch"), Wide("16:9"), Standard("4:3"), Original("Original Size");

    /** The picture's size in pixels inside a [w] x [h] screen, for a video of [aspect] and [videoW] x [videoH] pixels. */
    fun size(w: Float, h: Float, aspect: Float, videoW: Float, videoH: Float): Pair<Float, Float> {
        fun fit(a: Float) = if (w / h > a) h * a to h else w to w / a
        return when (this) {
            Fit -> fit(aspect)
            Fill -> if (w / h > aspect) w to w / aspect else h * aspect to h
            Stretch -> w to h
            Wide -> fit(16f / 9f)
            Standard -> fit(4f / 3f)
            Original -> videoW to videoH
        }
    }
}

/** Which way the video is shown. These work even with the phone's rotation lock on. */
enum class VideoTurn(val label: String, val orientation: Int) {
    Auto("Auto-Rotate", ActivityInfo.SCREEN_ORIENTATION_SENSOR),
    Landscape("Landscape", ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE),
    Portrait("Portrait", ActivityInfo.SCREEN_ORIENTATION_SENSOR_PORTRAIT),
}

/**
 * A full-screen video player. Music pauses while it plays; back closes it.
 * Tap shows or hides the controls; double-tap the left or right side to skip 10 seconds.
 */
@Composable
fun VideoPlayer(video: Video, onClose: () -> Unit) {
    val context = LocalContext.current
    val activity = context as? Activity
    val actions = LocalActions.current
    val model = actions.model
    val prefs = model.prefs
    var error by remember(video.id) { mutableStateOf<String?>(null) }
    var fit by remember { mutableStateOf(runCatching { VideoFit.valueOf(prefs.getString("videoFit", "Fit")) }.getOrDefault(VideoFit.Fit)) }
    var turn by remember { mutableStateOf(runCatching { VideoTurn.valueOf(prefs.getString("videoTurn", "Auto")) }.getOrDefault(VideoTurn.Auto)) }
    var videoSize by remember { mutableStateOf(VideoSize.UNKNOWN) }
    var playing by remember { mutableStateOf(true) }
    var ended by remember { mutableStateOf(false) }
    var position by remember { mutableLongStateOf(0L) }
    var duration by remember { mutableLongStateOf(0L) }
    var controls by remember { mutableStateOf(true) }
    var poke by remember { mutableIntStateOf(0) }
    var notice by remember { mutableStateOf<String?>(null) }
    var scrubbing by remember { mutableStateOf(false) }

    val player = remember(video.id) {
        // If the hardware decoder can't start (busy reading tile frames, say), try the next one.
        ExoPlayer.Builder(context, DefaultRenderersFactory(context).setEnableDecoderFallback(true))
            // Like music: other sound pauses, and unplugging headphones pauses the video.
            .setAudioAttributes(
                AudioAttributes.Builder().setUsage(C.USAGE_MEDIA).setContentType(C.AUDIO_CONTENT_TYPE_MOVIE).build(),
                true,
            )
            .setHandleAudioBecomingNoisy(true)
            .build().apply {
            setMediaItem(MediaItem.fromUri(video.uri))
            // Back where it was if Android rebuilt the screen while it played.
            if (model.videoResume?.first == video.id) seekTo(model.videoResume!!.second)
            prepare()
            playWhenReady = true
        }
    }
    var retried by remember(video.id) { mutableStateOf(false) }
    DisposableEffect(video.id) {
        if (model.player.isPlaying) model.player.togglePlayback()
        model.videoResume = null
        val listener = object : Player.Listener {
            override fun onPlayerError(e: PlaybackException) {
                // A decoder that was busy is worth one more try before giving up.
                if (!retried && e.errorCode in retryable) {
                    retried = true
                    player.prepare()
                    return
                }
                error = "This video can't play on Android. Videos bought from iTunes are copy-protected, " +
                    "so only videos without protection play here."
            }
            override fun onVideoSizeChanged(size: VideoSize) { videoSize = size }
            override fun onIsPlayingChanged(isPlaying: Boolean) { playing = isPlaying }
            override fun onPlaybackStateChanged(state: Int) {
                ended = state == Player.STATE_ENDED
                if (ended) controls = true
                duration = player.duration.coerceAtLeast(0L)
            }
        }
        player.addListener(listener)
        val window = activity?.window
        val insets = window?.let { WindowCompat.getInsetsController(it, it.decorView) }
        insets?.systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
        insets?.hide(WindowInsetsCompat.Type.systemBars())
        window?.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        onDispose {
            // Still showing this video means Android rebuilt the screen rather than you closing it.
            if (model.video?.id == video.id) model.videoResume = video.id to player.currentPosition
            player.removeListener(listener)
            player.release()
            insets?.show(WindowInsetsCompat.Type.systemBars())
            window?.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        }
    }
    // Turning follows the button, not the phone's rotation lock; the app goes back to normal on close.
    DisposableEffect(turn) {
        activity?.requestedOrientation = turn.orientation
        onDispose { }
    }
    DisposableEffect(Unit) {
        onDispose { activity?.requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED }
    }
    // Leaving Hush pauses the video.
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    DisposableEffect(lifecycle, player) {
        val observer = LifecycleEventObserver { _, event -> if (event == Lifecycle.Event.ON_STOP) player.pause() }
        lifecycle.addObserver(observer)
        onDispose { lifecycle.removeObserver(observer) }
    }
    LaunchedEffect(player) {
        while (true) {
            position = player.currentPosition
            duration = player.duration.takeIf { it > 0 } ?: duration
            delay(250)
        }
    }
    // Controls fade after a few seconds of playing untouched.
    LaunchedEffect(controls, playing, poke, scrubbing) {
        if (controls && playing && !scrubbing) {
            delay(3500)
            controls = false
        }
    }
    LaunchedEffect(notice) {
        if (notice != null) {
            delay(1200)
            notice = null
        }
    }

    fun touch() { poke++ }
    fun skip(ms: Long) {
        val target = (player.currentPosition + ms).coerceAtLeast(0L)
        player.seekTo(if (player.duration > 0) target.coerceAtMost(player.duration) else target)
        touch()
    }
    fun playPause() {
        when {
            ended -> { player.seekTo(0); player.play() }
            player.isPlaying -> player.pause()
            else -> player.play()
        }
        touch()
    }

    BackHandler(onBack = onClose)
    BoxWithConstraints(
        Modifier
            .fillMaxSize()
            .background(Color.Black)
            .blockTouches()
            .clipToBounds()
            .pointerInput(Unit) {
                detectTapGestures(
                    onTap = { controls = !controls; touch() },
                    onDoubleTap = { offset ->
                        val forward = offset.x > size.width / 2
                        skip(if (forward) 10_000 else -10_000)
                        notice = if (forward) "+10 s" else "−10 s"
                    },
                )
            },
        contentAlignment = Alignment.Center,
    ) {
        val density = LocalDensity.current
        val screenW = constraints.maxWidth.toFloat()
        val screenH = constraints.maxHeight.toFloat()
        val vw = videoSize.width.toFloat()
        val vh = videoSize.height.toFloat()
        // Until the first frame gives the video's size, the surface waits, tiny, so it exists.
        val surfaceSize = if (vw > 0 && vh > 0) {
            val par = if (videoSize.pixelWidthHeightRatio > 0) videoSize.pixelWidthHeightRatio else 1f
            val (w, h) = fit.size(screenW, screenH, vw * par / vh, vw * par, vh)
            Modifier.requiredSize(with(density) { w.toDp() }, with(density) { h.toDp() })
        } else {
            Modifier.size(1.dp)
        }
        AndroidView(
            factory = { ctx -> LayoutInflater.from(ctx).inflate(R.layout.video_surface, null) as PlayerView },
            update = { it.player = player },
            onRelease = { it.player = null },
            modifier = surfaceSize,
        )

        AnimatedVisibility(controls, Modifier.fillMaxSize(), enter = fadeIn(tween(150)), exit = fadeOut(tween(250))) {
            VideoControls(
                video = video,
                playing = playing && !ended,
                ended = ended,
                position = position,
                duration = duration,
                fit = fit,
                turn = turn,
                onClose = onClose,
                onPlayPause = ::playPause,
                onSkip = ::skip,
                onSeek = { player.seekTo(it); position = it; touch() },
                onScrubbing = { scrubbing = it },
                onFit = {
                    fit = VideoFit.entries[(fit.ordinal + 1) % VideoFit.entries.size]
                    prefs.putString("videoFit", fit.name)
                    notice = fit.label
                    touch()
                },
                onTurn = {
                    turn = VideoTurn.entries[(turn.ordinal + 1) % VideoTurn.entries.size]
                    prefs.putString("videoTurn", turn.name)
                    notice = turn.label
                    touch()
                },
            )
        }

        notice?.let {
            Text(
                it, style = Hush.sans(17.sp),
                modifier = Modifier.align(Alignment.Center).offset(y = (-96).dp)
                    .background(Color.Black.copy(alpha = 0.65f), RoundedCornerShape(10.dp))
                    .padding(horizontal = 18.dp, vertical = 10.dp),
            )
        }
        error?.let {
            Text(
                it, style = Hush.sans(16.sp), textAlign = TextAlign.Center,
                modifier = Modifier.align(Alignment.Center).padding(40.dp),
            )
        }
    }
}

@Composable
private fun VideoControls(
    video: Video, playing: Boolean, ended: Boolean, position: Long, duration: Long, fit: VideoFit, turn: VideoTurn,
    onClose: () -> Unit, onPlayPause: () -> Unit, onSkip: (Long) -> Unit, onSeek: (Long) -> Unit,
    onScrubbing: (Boolean) -> Unit, onFit: () -> Unit, onTurn: () -> Unit,
) {
    val shade = Color.Black.copy(alpha = 0.55f)
    Box(Modifier.fillMaxSize()) {
        // Top: back, the title, and the picture and turning buttons.
        Row(
            Modifier
                .align(Alignment.TopCenter)
                .fillMaxWidth()
                .background(Brush.verticalGradient(listOf(shade, Color.Transparent)))
                .safeDrawingPadding()
                .padding(horizontal = 8.dp, vertical = 6.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            PlainIconButton(Icons.AutoMirrored.Rounded.ArrowBack, "Close video", size = 28.dp, box = 56.dp, onClick = onClose)
            Column(Modifier.weight(1f).padding(horizontal = 6.dp)) {
                Text(video.title, style = Hush.serif(19.sp), maxLines = 1, overflow = TextOverflow.Ellipsis)
                video.artist?.let { Text(it, style = Hush.sans(13.sp, Hush.muted), maxLines = 1, overflow = TextOverflow.Ellipsis) }
            }
            PlainIconButton(Icons.Rounded.AspectRatio, "Picture: ${fit.label}", size = 28.dp, box = 56.dp, onClick = onFit)
            PlainIconButton(
                when (turn) {
                    VideoTurn.Auto -> Icons.Rounded.ScreenRotation
                    VideoTurn.Landscape -> Icons.Rounded.StayCurrentLandscape
                    VideoTurn.Portrait -> Icons.Rounded.StayCurrentPortrait
                },
                "Turn: ${turn.label}", size = 28.dp, box = 56.dp, onClick = onTurn,
            )
        }

        // Middle: back 10 seconds, play or pause, ahead 10 seconds.
        Row(Modifier.align(Alignment.Center), verticalAlignment = Alignment.CenterVertically) {
            PlainIconButton(Icons.Rounded.Replay10, "Back 10 seconds", size = 40.dp, box = 72.dp) { onSkip(-10_000) }
            Spacer(Modifier.width(36.dp))
            Box(
                Modifier.size(84.dp).clip(CircleShape).background(Color.Black.copy(alpha = 0.45f)).clickableQuiet(onPlayPause),
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    when {
                        ended -> Icons.Rounded.Replay
                        playing -> Icons.Rounded.Pause
                        else -> Icons.Rounded.PlayArrow
                    },
                    contentDescription = when {
                        ended -> "Play again"
                        playing -> "Pause"
                        else -> "Play"
                    },
                    tint = Hush.ink, modifier = Modifier.size(52.dp),
                )
            }
            Spacer(Modifier.width(36.dp))
            PlainIconButton(Icons.Rounded.Forward10, "Ahead 10 seconds", size = 40.dp, box = 72.dp) { onSkip(10_000) }
        }

        // Bottom: where you are in the video.
        Box(
            Modifier
                .align(Alignment.BottomCenter)
                .fillMaxWidth()
                .background(Brush.verticalGradient(listOf(Color.Transparent, shade)))
                .safeDrawingPadding()
                .padding(horizontal = 24.dp, vertical = 12.dp),
        ) {
            SeekBar(position, duration, onSeek, onScrubbing = onScrubbing)
        }
    }
}
