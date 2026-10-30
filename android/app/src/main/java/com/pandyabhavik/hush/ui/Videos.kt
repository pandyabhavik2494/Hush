package com.pandyabhavik.hush.ui

import android.Manifest
import android.app.Activity
import android.content.pm.PackageManager
import android.view.ViewGroup
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.grid.LazyGridState
import androidx.compose.foundation.lazy.grid.itemsIndexed
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.rounded.Movie
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.content.ContextCompat
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.ui.AspectRatioFrameLayout
import androidx.media3.ui.PlayerView
import com.pandyabhavik.hush.HushModel
import com.pandyabhavik.hush.data.Video
import com.pandyabhavik.hush.data.timeText

/** The Videos tab: music videos from any "Music Videos" folder on the phone, 16:9 tiles. */
@Composable
fun VideosTab(model: HushModel, query: String, state: LazyGridState, padding: PaddingValues) {
    val context = LocalContext.current
    var granted by remember {
        mutableStateOf(ContextCompat.checkSelfPermission(context, Manifest.permission.READ_MEDIA_VIDEO) == PackageManager.PERMISSION_GRANTED)
    }
    val request = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { ok ->
        granted = ok
        if (ok) model.refresh()
    }
    if (!granted) {
        Column(Modifier.fillMaxSize().padding(horizontal = 40.dp, vertical = 80.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            Text("Your music videos", style = Hush.serif(24.sp), textAlign = TextAlign.Center)
            Spacer(Modifier.height(10.dp))
            Text(
                "Hush shows the videos in your Music Videos folder. Allow it to see your videos (choose Allow all).",
                style = Hush.sans(15.sp, Hush.muted), textAlign = TextAlign.Center,
            )
            Spacer(Modifier.height(24.dp))
            PillButton("Allow Access to Videos", Icons.Rounded.Movie, filled = true, Modifier.width(280.dp)) {
                request.launch(Manifest.permission.READ_MEDIA_VIDEO)
            }
        }
        return
    }
    val videos = remember(model.library, query) {
        if (query.isEmpty()) model.library.videos else model.library.videos.filter { it.searchKey.contains(query) }
    }
    if (model.loaded && model.library.videos.isEmpty()) {
        Column(Modifier.fillMaxSize().padding(horizontal = 40.dp, vertical = 80.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            Text("No music videos", style = Hush.serif(24.sp), textAlign = TextAlign.Center)
            Spacer(Modifier.height(10.dp))
            Text("Hush shows videos kept in a folder called Music Videos.", style = Hush.sans(15.sp, Hush.muted), textAlign = TextAlign.Center)
        }
        return
    }
    val actions = LocalActions.current
    BoxWithConstraints {
        val columns = if (maxWidth < 600.dp) 2 else if (maxWidth < 900.dp) 3 else 4
        val targets = if (query.isEmpty()) letterTargets(videos, Video::letter) else emptyList()
        LibraryGrid(state, columns, padding, targets, rowSpacing = 20.dp) {
            itemsIndexed(videos, key = { _, v -> v.id }) { _, video ->
                Column(Modifier.clickableQuiet { actions.playVideo(video) }) {
                    Box(Modifier.fillMaxWidth().aspectRatio(16f / 9f).clip(RoundedCornerShape(8.dp)).background(Hush.card)) {
                        Cover(null, Modifier.fillMaxSize(), 0.dp, uri = video.uri, aspect = 16f / 9f)
                        Text(
                            timeText(video.durationMs),
                            style = Hush.sans(11.sp),
                            modifier = Modifier.align(Alignment.BottomEnd).padding(6.dp)
                                .background(Color.Black.copy(alpha = 0.6f), RoundedCornerShape(4.dp)).padding(horizontal = 5.dp, vertical = 1.dp),
                        )
                    }
                    Spacer(Modifier.height(6.dp))
                    Text(video.title, style = Hush.sans(14.sp), maxLines = 2, overflow = TextOverflow.Ellipsis)
                    video.artist?.let { Text(it, style = Hush.sans(12.5.sp, Hush.muted), maxLines = 1, overflow = TextOverflow.Ellipsis) }
                }
            }
        }
    }
}

/** A full-screen video player. Music pauses while it plays; back closes it. */
@Composable
fun VideoPlayer(video: Video, onClose: () -> Unit) {
    val context = LocalContext.current
    val actions = LocalActions.current
    var error by remember { mutableStateOf<String?>(null) }
    val player = remember(video.id) {
        ExoPlayer.Builder(context).build().apply {
            setMediaItem(MediaItem.fromUri(video.uri))
            prepare()
            playWhenReady = true
        }
    }
    DisposableEffect(video.id) {
        if (actions.model.player.isPlaying) actions.model.player.togglePlayback()
        val listener = object : Player.Listener {
            override fun onPlayerError(e: PlaybackException) {
                error = "This video can't play on Android. Videos bought from iTunes are copy-protected, " +
                    "so only videos without protection play here."
            }
        }
        player.addListener(listener)
        val window = (context as? Activity)?.window
        val insets = window?.let { WindowCompat.getInsetsController(it, it.decorView) }
        insets?.systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
        insets?.hide(WindowInsetsCompat.Type.systemBars())
        window?.addFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        onDispose {
            player.removeListener(listener)
            player.release()
            insets?.show(WindowInsetsCompat.Type.systemBars())
            window?.clearFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        }
    }
    BackHandler(onBack = onClose)
    Box(Modifier.fillMaxSize().background(Color.Black).blockTouches()) {
        AndroidView(
            factory = { ctx ->
                PlayerView(ctx).apply {
                    layoutParams = ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
                    resizeMode = AspectRatioFrameLayout.RESIZE_MODE_FIT
                    setShowNextButton(false)
                    setShowPreviousButton(false)
                    this.player = player
                }
            },
            modifier = Modifier.fillMaxSize(),
        )
        Box(Modifier.safeDrawingPadding().padding(8.dp)) {
            PlainIconButton(Icons.AutoMirrored.Rounded.ArrowBack, "Close video", onClick = onClose)
        }
        error?.let {
            Text(
                it, style = Hush.sans(16.sp), textAlign = TextAlign.Center,
                modifier = Modifier.align(Alignment.Center).padding(40.dp),
            )
        }
    }
}
