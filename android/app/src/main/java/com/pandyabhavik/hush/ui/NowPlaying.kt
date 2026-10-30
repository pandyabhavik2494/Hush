package com.pandyabhavik.hush.ui

import android.view.HapticFeedbackConstants
import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.Crossfade
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animate
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.scaleOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.slideOutVertically
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.Orientation
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.gestures.draggable
import androidx.compose.foundation.gestures.rememberDraggableState
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.QueueMusic
import androidx.compose.material.icons.rounded.Add
import androidx.compose.material.icons.rounded.Album
import androidx.compose.material.icons.rounded.KeyboardArrowDown
import androidx.compose.material.icons.rounded.Mic
import androidx.compose.material.icons.rounded.MoreHoriz
import androidx.compose.material.icons.rounded.Pause
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material.icons.rounded.Repeat
import androidx.compose.material.icons.rounded.RepeatOne
import androidx.compose.material.icons.rounded.Shuffle
import androidx.compose.material.icons.rounded.SkipNext
import androidx.compose.material.icons.rounded.SkipPrevious
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.minimumInteractiveComponentSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.lerp
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.input.pointer.positionChanged
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.semantics.ProgressBarRangeInfo
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.progressBarRangeInfo
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.setProgress
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.media3.common.Player
import com.pandyabhavik.hush.data.Song
import com.pandyabhavik.hush.data.timeText
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull
import kotlin.math.max

/** Colours used over the cover-coloured Now Playing background. */
internal object PlayerInk {
    val cream = Color(0xFFF7F1E4)
    val accent = Color(0xFFE6C88E)
    val glyph = Color(0xFF3A120F)
    val gold = Color(0xFFC9A86B)
    val secondary = cream.copy(alpha = 0.72f)
    val idle = cream.copy(alpha = 0.55f)
    val track = Color.White.copy(alpha = 0.2f)
}

/**
 * The player, in the manner of Apple Music: the background drifts slowly in the cover's own
 * colours, the cover sits large with a soft shadow and sinks a little while paused, the title and
 * artist sit left with a "…" menu, then the scrubber, the transport, and shuffle / Up Next / repeat.
 *
 * Compact (the cover screen): one column; the cover takes whatever height the controls leave, so
 * nothing falls off a short screen or at large text sizes. Swipe down to close, swipe the cover
 * to change songs; Up Next is a sheet.
 * Wide (>= 600 dp, the unfolded screen): the Mac layout, cover beside the details when there is
 * the width for it and above them otherwise; Up Next is a 360 dp panel at the right.
 */
@Composable
fun NowPlaying(onClose: () -> Unit) {
    val actions = LocalActions.current
    val model = actions.model
    val player = model.player
    val song = model.library.song(player.currentId)
    var showQueue by rememberSaveable { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    val density = LocalDensity.current
    val view = LocalView.current

    // Swipe down to close: the screen follows the finger and shrinks a little, with rounded corners.
    var dragY by remember { mutableFloatStateOf(0f) }
    var settle by remember { mutableStateOf<Job?>(null) }
    var closing by remember { mutableStateOf(false) }
    val close: () -> Unit = {
        closing = true
        view.performHapticFeedback(HapticFeedbackConstants.CONTEXT_CLICK)
        onClose()
    }
    val dragState = rememberDraggableState { delta ->
        if (!closing) dragY = (dragY + delta).coerceAtLeast(0f)
    }

    // Opened again while the closing animation still runs: start from a clean slate.
    LaunchedEffect(model.playerOpen) {
        if (model.playerOpen) {
            settle?.cancel()
            closing = false
            dragY = 0f
        }
    }

    // Off while the close animation runs, so a second back reaches the page underneath.
    BackHandler(enabled = model.playerOpen && !closing) { if (showQueue) showQueue = false else close() }

    BoxWithConstraints(
        Modifier
            .fillMaxSize()
            .graphicsLayer {
                val shrink = 200.dp.toPx()
                val scale = 1f - 0.1f * (dragY / shrink).coerceIn(0f, 1f)
                translationY = dragY
                scaleX = scale
                scaleY = scale
                transformOrigin = TransformOrigin(0.5f, 0f)
                shape = RoundedCornerShape(if (dragY > 0f) 28.dp else 0.dp)
                clip = dragY > 0f
            }
            .blockTouches()
            .draggable(
                state = dragState,
                orientation = Orientation.Vertical,
                enabled = !showQueue && !closing,
                onDragStarted = { settle?.cancel() },
                onDragStopped = { velocity ->
                    if (dragY > with(density) { 120.dp.toPx() } || velocity > 1800f) {
                        close()
                    } else {
                        settle = scope.launch {
                            animate(dragY, 0f, animationSpec = spring(dampingRatio = 0.8f, stiffness = 322f)) { value, _ -> dragY = value }
                        }
                    }
                },
            ),
    ) {
        CoverBackdrop(song, Modifier.fillMaxSize())
        val wide = maxWidth >= 600.dp
        val screenHeight = maxHeight
        if (song == null) {
            Box(Modifier.fillMaxSize().statusBarsPadding().padding(8.dp)) {
                PlayerIconButton(Icons.Rounded.KeyboardArrowDown, "Close", PlayerInk.cream, 32.dp, onClick = close)
            }
        } else if (wide) {
            WidePlayer(song, showQueue, onToggleQueue = { showQueue = !showQueue }, onClose = close)
        } else {
            CompactPlayer(song, showQueue, onToggleQueue = { showQueue = !showQueue }, onClose = close)
        }

        // Up Next on the cover screen: a sheet over the player, as on iPhone.
        AnimatedVisibility(visible = showQueue && !wide, enter = fadeIn(tween(200)), exit = fadeOut(tween(200))) {
            Box(
                Modifier
                    .fillMaxSize()
                    .background(Color.Black.copy(alpha = 0.45f))
                    .pointerInput(Unit) { detectTapGestures { showQueue = false } },
            )
        }
        AnimatedVisibility(
            visible = showQueue && !wide,
            modifier = Modifier.align(Alignment.BottomCenter),
            enter = slideInVertically(spring(dampingRatio = 0.86f, stiffness = 247f)) { it },
            exit = slideOutVertically(tween(240)) { it },
        ) {
            UpNextSheet(screenHeight, onClose = { showQueue = false })
        }
    }
}

// MARK: - Layouts

@Composable
private fun CompactPlayer(song: Song, showQueue: Boolean, onToggleQueue: () -> Unit, onClose: () -> Unit) {
    val player = LocalActions.current.model.player
    Column(Modifier.fillMaxSize().statusBarsPadding().navigationBarsPadding()) {
        // Top bar: close at the start, a grabber in the middle.
        Box(Modifier.fillMaxWidth().height(48.dp).padding(horizontal = 6.dp)) {
            PlayerIconButton(
                Icons.Rounded.KeyboardArrowDown, "Close", PlayerInk.cream, 32.dp,
                modifier = Modifier.align(Alignment.CenterStart), onClick = onClose,
            )
            Box(
                Modifier.align(Alignment.Center).size(width = 36.dp, height = 5.dp)
                    .clip(CircleShape).background(PlayerInk.cream.copy(alpha = 0.3f)),
            )
        }
        // The cover gets the height the controls leave (never the other way round): on a short
        // screen or with large text it shrinks, and every control stays on screen.
        BoxWithConstraints(
            Modifier.weight(1f).fillMaxWidth().padding(horizontal = 24.dp, vertical = 6.dp),
            contentAlignment = Alignment.Center,
        ) {
            val side = minOf(maxWidth, maxHeight)
            if (side > 0.dp) PlayerArt(song, side, 10.dp, CoverShadow(Color.Black.copy(alpha = 0.5f), 34.dp, 18.dp))
        }
        Spacer(Modifier.height(18.dp))
        TrackInfo(
            song, titleSize = 29.sp, minTitleSize = 22.sp, titleLines = 2,
            modifier = Modifier.padding(start = 24.dp, end = 12.dp),
        )
        Spacer(Modifier.height(12.dp))
        PlayerScrubber(thin = 4.dp, thick = 9.dp, modifier = Modifier.padding(horizontal = 24.dp))
        Spacer(Modifier.height(8.dp))
        Row(
            Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(40.dp, Alignment.CenterHorizontally),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            PlayerIconButton(Icons.Rounded.SkipPrevious, "Previous", PlayerInk.cream, 42.dp, box = 56.dp, haptic = true) { player.previous() }
            PlayPauseButton(player.isPlaying, 76.dp, PlayerInk.cream, PlayerInk.glyph) { player.togglePlayback() }
            PlayerIconButton(Icons.Rounded.SkipNext, "Next", PlayerInk.cream, 42.dp, box = 56.dp, haptic = true) { player.next() }
        }
        Spacer(Modifier.height(10.dp))
        ModeRow(showQueue, onToggleQueue, Modifier.padding(horizontal = 16.dp))
        Spacer(Modifier.height(6.dp))
    }
}

@Composable
private fun WidePlayer(song: Song, showQueue: Boolean, onToggleQueue: () -> Unit, onClose: () -> Unit) {
    Row(Modifier.fillMaxSize()) {
        Column(Modifier.weight(1f).fillMaxHeight().statusBarsPadding().navigationBarsPadding()) {
            Row(
                Modifier.fillMaxWidth().height(64.dp).padding(horizontal = 16.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                CircleIconButton(Icons.Rounded.KeyboardArrowDown, "Close", onClick = onClose)
                Spacer(Modifier.weight(1f))
                Text("Hush", style = TextStyle(fontFamily = Hush.wordmark, fontSize = 20.sp, color = PlayerInk.cream.copy(alpha = 0.65f)))
                Spacer(Modifier.weight(1f))
                Spacer(Modifier.width(48.dp))
            }
            BoxWithConstraints(
                Modifier.weight(1f).fillMaxWidth().padding(start = 40.dp, end = 40.dp, bottom = 24.dp),
            ) {
                val sideBySide = maxWidth > maxHeight * 0.85f
                val shadow = CoverShadow(Color.Black.copy(alpha = 0.55f), 45.dp, 30.dp)
                if (sideBySide) {
                    val gap = 48.dp
                    val details = ((maxWidth - gap) * 0.45f).coerceIn(300.dp, 460.dp)
                    val cover = minOf(520.dp, maxHeight - 16.dp, maxWidth - gap - details).coerceAtLeast(0.dp)
                    Row(
                        Modifier.fillMaxSize(),
                        horizontalArrangement = Arrangement.spacedBy(gap, Alignment.CenterHorizontally),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        if (cover > 0.dp) PlayerArt(song, cover, 22.dp, shadow)
                        WideDetails(song, showQueue, onToggleQueue, titleSize = 46.sp, titleLines = 3, modifier = Modifier.width(details))
                    }
                } else {
                    Column(Modifier.fillMaxSize(), horizontalAlignment = Alignment.CenterHorizontally) {
                        BoxWithConstraints(Modifier.weight(1f).fillMaxWidth().padding(vertical = 8.dp), contentAlignment = Alignment.Center) {
                            val side = minOf(520.dp, maxWidth, maxHeight)
                            if (side > 0.dp) PlayerArt(song, side, 22.dp, shadow)
                        }
                        Spacer(Modifier.height(20.dp))
                        WideDetails(
                            song, showQueue, onToggleQueue, titleSize = 34.sp, titleLines = 2,
                            modifier = Modifier.widthIn(max = 560.dp).fillMaxWidth(),
                        )
                    }
                }
            }
        }
        AnimatedVisibility(
            visible = showQueue,
            enter = slideInHorizontally(tween(300, easing = FastOutSlowInEasing)) { it } + fadeIn(tween(300)),
            exit = slideOutHorizontally(tween(300, easing = FastOutSlowInEasing)) { it } + fadeOut(tween(300)),
        ) {
            UpNextPanel(Modifier.width(360.dp).fillMaxHeight(), onClose = onToggleQueue, onColor = true)
        }
    }
}

@Composable
private fun WideDetails(
    song: Song, showQueue: Boolean, onToggleQueue: () -> Unit, titleSize: TextUnit, titleLines: Int, modifier: Modifier,
) {
    val model = LocalActions.current.model
    val player = model.player
    Column(modifier) {
        TrackInfo(song, titleSize = titleSize, minTitleSize = 28.sp, titleLines = titleLines)
        Spacer(Modifier.height(16.dp))
        PlayerScrubber(thin = 6.dp, thick = 10.dp, fill = PlayerInk.accent)
        Spacer(Modifier.height(6.dp))
        Row(
            Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceEvenly,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            PlayerIconButton(Icons.Rounded.SkipPrevious, "Previous", PlayerInk.cream, 40.dp, box = 56.dp, haptic = true) { player.previous() }
            PlayPauseButton(player.isPlaying, 76.dp, PlayerInk.cream, PlayerInk.glyph) { player.togglePlayback() }
            PlayerIconButton(Icons.Rounded.SkipNext, "Next", PlayerInk.cream, 40.dp, box = 56.dp, haptic = true) { player.next() }
        }
        Spacer(Modifier.height(8.dp))
        ModeRow(showQueue, onToggleQueue)
        val next = player.upNext.firstOrNull()?.let { model.library.song(it) }
        if (next != null) {
            Spacer(Modifier.height(10.dp))
            Box(Modifier.fillMaxWidth().height(1.dp).background(PlayerInk.cream.copy(alpha = 0.14f)))
            Row(
                Modifier
                    .fillMaxWidth()
                    .height(52.dp)
                    .clip(RoundedCornerShape(8.dp))
                    .clickable(onClickLabel = "Show Up Next") { if (!showQueue) onToggleQueue() },
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    "NEXT", style = Hush.sans(11.sp, PlayerInk.cream.copy(alpha = 0.6f), FontWeight.Bold).copy(letterSpacing = 0.9.sp),
                )
                Spacer(Modifier.width(12.dp))
                Cover(next, Modifier.size(28.dp), 5.dp)
                Spacer(Modifier.width(12.dp))
                Text(
                    "${next.title} · ${next.artist}", style = Hush.sans(13.sp, PlayerInk.cream.copy(alpha = 0.85f)),
                    maxLines = 1, overflow = TextOverflow.Ellipsis,
                )
            }
        }
    }
}

// MARK: - Pieces

/**
 * The cover: crossfades when the song changes (once the new picture is ready, so it never
 * flashes the placeholder), sinks a little while paused and springs back when playing.
 * Swipe it sideways to change songs.
 */
@Composable
private fun PlayerArt(song: Song, size: Dp, radius: Dp, shadow: CoverShadow) {
    val player = LocalActions.current.model.player
    val context = LocalContext.current
    val view = LocalView.current
    val scope = rememberCoroutineScope()
    val px = with(LocalDensity.current) { size.roundToPx() }
    var shown by remember { mutableStateOf(song) }
    LaunchedEffect(song.id) {
        if (song.id != shown.id) {
            withTimeoutOrNull(700) { Covers.load(context, song.uri, px) }
            shown = song
        }
    }
    // Read in the layer below, so the spring doesn't recompose the cover every frame.
    val scale = animateFloatAsState(
        if (player.isPlaying) 1f else 0.84f, spring(dampingRatio = 0.66f, stiffness = 240f), label = "pauseScale",
    )
    var drag by remember { mutableFloatStateOf(0f) }
    var settle by remember { mutableStateOf<Job?>(null) }
    Box(
        Modifier
            .size(size)
            .graphicsLayer {
                translationX = drag * 0.5f
                scaleX = scale.value
                scaleY = scale.value
            }
            .pointerInput(Unit) {
                detectHorizontalDragGestures(
                    onDragStart = { settle?.cancel() },
                    onDragEnd = {
                        val threshold = 80.dp.toPx()
                        if (drag < -threshold) {
                            view.performHapticFeedback(HapticFeedbackConstants.CONTEXT_CLICK)
                            player.next()
                        } else if (drag > threshold) {
                            view.performHapticFeedback(HapticFeedbackConstants.CONTEXT_CLICK)
                            player.previous()
                        }
                        settle = scope.launch { animate(drag, 0f, animationSpec = spring(0.8f, 322f)) { v, _ -> drag = v } }
                    },
                    onDragCancel = {
                        settle = scope.launch { animate(drag, 0f, animationSpec = spring(0.8f, 322f)) { v, _ -> drag = v } }
                    },
                ) { change, amount ->
                    change.consume()
                    drag += amount
                }
            },
    ) {
        Crossfade(shown, Modifier.fillMaxSize(), animationSpec = tween(350, easing = FastOutSlowInEasing), label = "cover") { s ->
            Cover(s, Modifier.fillMaxSize(), radius, shadow = shadow)
        }
    }
}

/** Title (serif, shrinking to fit), "Artist · Album" links beneath, and the "…" menu. */
@Composable
private fun TrackInfo(song: Song, titleSize: TextUnit, minTitleSize: TextUnit, titleLines: Int, modifier: Modifier = Modifier) {
    val actions = LocalActions.current
    var menu by remember { mutableStateOf(false) }
    var artistMenu by remember { mutableStateOf(false) }
    val artists = remember(song, actions.model.library) { actions.model.library.creditedArtists(song) }
    Row(modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f)) {
            var size by remember(song.id, titleSize) { mutableFloatStateOf(titleSize.value) }
            Text(
                song.title,
                style = Hush.serif(size.sp, PlayerInk.cream).copy(letterSpacing = (-0.3).sp, lineHeight = (size * 1.18f).sp),
                maxLines = titleLines, overflow = TextOverflow.Ellipsis,
                onTextLayout = { if (it.hasVisualOverflow && size > minTitleSize.value) size = max(minTitleSize.value, size - 2f) },
            )
            Row(verticalAlignment = Alignment.CenterVertically) {
                val link = Hush.sans(16.sp, PlayerInk.secondary)
                Box(Modifier.weight(1f, fill = false)) {
                    Text(
                        song.artist, style = link, maxLines = 1, overflow = TextOverflow.Ellipsis,
                        modifier = Modifier
                            .minimumInteractiveComponentSize()
                            .clickable(enabled = artists.isNotEmpty()) {
                                if (artists.size > 1) artistMenu = true else actions.openArtistOf(song)
                            },
                    )
                    HushMenu(artistMenu, { artistMenu = false }) {
                        artists.forEach { artist ->
                            HushMenuItem(artist.name, Icons.Rounded.Mic) { artistMenu = false; actions.open(Route.ArtistPage(artist.id)) }
                        }
                    }
                }
                Text(" · ", style = link)
                Text(
                    song.album, style = link, maxLines = 1, overflow = TextOverflow.Ellipsis,
                    modifier = Modifier
                        .weight(1f, fill = false)
                        .minimumInteractiveComponentSize()
                        .clickable { actions.openAlbumOf(song) },
                )
            }
        }
        Box {
            PlayerIconButton(Icons.Rounded.MoreHoriz, "More", PlayerInk.cream, 26.dp) { menu = true }
            SongActionsMenu(song, menu) { menu = false }
        }
    }
}

/** Go to Album, and Go to each credited artist. */
@Composable
internal fun SongActionsMenu(song: Song, expanded: Boolean, extra: (@Composable () -> Unit)? = null, onDismiss: () -> Unit) {
    val actions = LocalActions.current
    val artists = actions.model.library.creditedArtists(song)
    HushMenu(expanded, onDismiss) {
        HushMenuItem("Go to Album", Icons.Rounded.Album) { onDismiss(); actions.openAlbumOf(song) }
        artists.forEach { artist ->
            HushMenuItem("Go to ${artist.name}", Icons.Rounded.Mic) { onDismiss(); actions.open(Route.ArtistPage(artist.id)) }
        }
        extra?.invoke()
    }
}

/** Shuffle at the start, Up Next in the middle, repeat at the end. */
@Composable
private fun ModeRow(showQueue: Boolean, onToggleQueue: () -> Unit, modifier: Modifier = Modifier) {
    val player = LocalActions.current.model.player
    Row(modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        ModeToggle(Icons.Rounded.Shuffle, "Shuffle", on = player.shuffled) { player.toggleShuffle() }
        Spacer(Modifier.weight(1f))
        ModeToggle(Icons.AutoMirrored.Rounded.QueueMusic, "Up Next", on = showQueue, onClick = onToggleQueue)
        Spacer(Modifier.weight(1f))
        ModeToggle(
            if (player.repeatMode == Player.REPEAT_MODE_ONE) Icons.Rounded.RepeatOne else Icons.Rounded.Repeat,
            "Repeat",
            on = player.repeatMode != Player.REPEAT_MODE_OFF,
        ) { player.cycleRepeat() }
    }
}

/** A mode button: a soft cream square behind it when on, the icon dimmed when off. */
@Composable
private fun ModeToggle(icon: ImageVector, description: String, on: Boolean, onClick: () -> Unit) {
    val view = LocalView.current
    val fill by animateColorAsState(if (on) PlayerInk.cream.copy(alpha = 0.16f) else Color.Transparent, tween(200), label = "modeFill")
    val tint by animateColorAsState(if (on) PlayerInk.cream else PlayerInk.idle, tween(200), label = "modeTint")
    Box(
        Modifier
            .size(48.dp)
            .clip(RoundedCornerShape(12.dp))
            .clickable(role = Role.Button) {
                view.performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK)
                onClick()
            }
            .semantics { stateDescription = if (on) "On" else "Off" },
        contentAlignment = Alignment.Center,
    ) {
        Box(Modifier.size(38.dp).clip(RoundedCornerShape(10.dp)).background(fill))
        Icon(icon, contentDescription = description, tint = tint, modifier = Modifier.size(24.dp))
    }
}

/** An icon with no background, in a touch box of at least 48 dp; presses scale it down a touch. */
@Composable
internal fun PlayerIconButton(
    icon: ImageVector, description: String, tint: Color, iconSize: Dp, modifier: Modifier = Modifier,
    box: Dp = 48.dp, haptic: Boolean = false, onClick: () -> Unit,
) {
    val view = LocalView.current
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    val scale by animateFloatAsState(if (pressed) 0.86f else 1f, spring(dampingRatio = 0.5f, stiffness = 632f), label = "press")
    Box(
        modifier
            .size(max(box.value, 48f).dp)
            .clip(CircleShape)
            .clickable(interactionSource = interaction, indication = null, role = Role.Button) {
                if (haptic) view.performHapticFeedback(HapticFeedbackConstants.CONTEXT_CLICK)
                onClick()
            },
        contentAlignment = Alignment.Center,
    ) {
        Icon(
            icon, contentDescription = description, tint = tint,
            modifier = Modifier.size(iconSize).graphicsLayer { scaleX = scale; scaleY = scale },
        )
    }
}

/** The Mac's round header button over the cover colours: 36 dp to see, 48 dp to touch. */
@Composable
private fun CircleIconButton(icon: ImageVector, description: String, on: Boolean = false, onClick: () -> Unit) {
    Box(
        Modifier.size(48.dp).clip(CircleShape).clickable(role = Role.Button, onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Box(
            Modifier
                .size(36.dp)
                .clip(CircleShape)
                .background(if (on) PlayerInk.gold.copy(alpha = 0.16f) else Color.White.copy(alpha = 0.10f)),
        )
        Icon(icon, contentDescription = description, tint = if (on) PlayerInk.gold else Color.White, modifier = Modifier.size(22.dp))
    }
}

/** A round play/pause button; the symbol pops when it changes, and the button gives under the finger. */
@Composable
internal fun PlayPauseButton(
    playing: Boolean, diameter: Dp, fill: Color, glyph: Color, modifier: Modifier = Modifier, onClick: () -> Unit,
) {
    val view = LocalView.current
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    val scale by animateFloatAsState(if (pressed) 0.9f else 1f, spring(dampingRatio = 0.5f, stiffness = 632f), label = "playPress")
    Box(
        modifier
            .size(max(diameter.value, 48f).dp)
            .clip(CircleShape)
            .clickable(interactionSource = interaction, indication = null, role = Role.Button) {
                view.performHapticFeedback(HapticFeedbackConstants.CONFIRM)
                onClick()
            }
            .semantics { contentDescription = if (playing) "Pause" else "Play" },
        contentAlignment = Alignment.Center,
    ) {
        Box(
            Modifier
                .size(diameter)
                .graphicsLayer { scaleX = scale; scaleY = scale }
                .clip(CircleShape)
                .background(fill),
            contentAlignment = Alignment.Center,
        ) {
            AnimatedContent(
                playing,
                transitionSpec = {
                    (scaleIn(spring(dampingRatio = 0.55f, stiffness = 439f), initialScale = 0.5f) + fadeIn(tween(120))) togetherWith
                        (scaleOut(tween(120), targetScale = 0.5f) + fadeOut(tween(120)))
                },
                label = "playGlyph",
            ) { isPlaying ->
                Icon(
                    if (isPlaying) Icons.Rounded.Pause else Icons.Rounded.PlayArrow,
                    contentDescription = null, tint = glyph,
                    modifier = Modifier
                        .size(diameter * 0.52f)
                        .offset(x = if (isPlaying) 0.dp else diameter * 0.03f),
                )
            }
        }
    }
}

/**
 * The scrubber: a rounded line that thickens under the finger (no knob), with the time so far and
 * the time left beneath. Touch anywhere along it to scrub; the song moves there on release.
 */
@Composable
private fun PlayerScrubber(thin: Dp, thick: Dp, modifier: Modifier = Modifier, fill: Color = PlayerInk.cream) {
    val player = LocalActions.current.model.player
    val view = LocalView.current
    val currentDuration by rememberUpdatedState(player.durationMs)
    var scrub by remember { mutableStateOf<Float?>(null) }
    // The position ticks four times a second. It is read only while drawing the line and in a
    // derived state that changes once a second, so the ticks don't recompose the scrubber.
    val fraction: () -> Float = remember {
        {
            val d = currentDuration
            scrub ?: if (d > 0) (player.positionMs.toFloat() / d).coerceIn(0f, 1f) else 0f
        }
    }
    val times by remember {
        derivedStateOf {
            val d = currentDuration
            val elapsed = (fraction() * d).toLong()
            ScrubTimes(
                if (d > 0) timeText(elapsed) else "--:--",
                if (d > 0) "\u2212" + timeText(d - elapsed) else "--:--",
                if (d > 0) ((elapsed / 1000) * 1000f / d).coerceIn(0f, 1f) else 0f,
            )
        }
    }
    val thickness by animateDpAsState(if (scrub != null) thick else thin, tween(150, easing = FastOutSlowInEasing), label = "scrubThickness")
    Column(modifier.fillMaxWidth()) {
        Box(
            Modifier
                .fillMaxWidth()
                .height(32.dp)
                .semantics {
                    contentDescription = "Position"
                    progressBarRangeInfo = ProgressBarRangeInfo(times.fraction, 0f..1f)
                    setProgress { value ->
                        if (currentDuration > 0) player.seek((value.coerceIn(0f, 1f) * currentDuration).toLong())
                        true
                    }
                }
                .pointerInput(Unit) {
                    awaitEachGesture {
                        val down = awaitFirstDown()
                        down.consume()
                        val width = size.width.toFloat().coerceAtLeast(1f)
                        scrub = (down.position.x / width).coerceIn(0f, 1f)
                        var released = false
                        try {
                            while (true) {
                                val event = awaitPointerEvent()
                                val change = event.changes.firstOrNull { it.id == down.id } ?: break
                                if (!change.pressed) {
                                    change.consume()
                                    released = true
                                    break
                                }
                                if (change.positionChanged()) {
                                    change.consume()
                                    scrub = (change.position.x / width).coerceIn(0f, 1f)
                                }
                            }
                            val at = scrub
                            if (released && at != null && currentDuration > 0) {
                                player.seek((at * currentDuration).toLong())
                                view.performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK)
                            }
                        } finally {
                            scrub = null
                        }
                    }
                },
            contentAlignment = Alignment.CenterStart,
        ) {
            Box(
                Modifier
                    .fillMaxWidth()
                    .height(thickness)
                    .clip(CircleShape)
                    .background(PlayerInk.track)
                    .drawBehind { drawRect(fill, size = Size(size.width * fraction(), size.height)) },
            )
        }
        val timeStyle = Hush.sans(12.sp, PlayerInk.secondary, FontWeight.Medium).copy(fontFeatureSettings = "tnum")
        Row(Modifier.fillMaxWidth().offset(y = (-4).dp)) {
            Text(times.elapsed, style = timeStyle)
            Spacer(Modifier.weight(1f))
            Text(times.left, style = timeStyle)
        }
    }
}

/** What the scrubber's labels show; equal values don't recompose. */
private data class ScrubTimes(val elapsed: String, val left: String, val fraction: Float)

/**
 * The cover's edge colours as a softly drifting gradient, shaded so cream text always reads.
 * Keeps the old colours until the new ones are ready, then blends over 0.7 s.
 */
@Composable
internal fun CoverBackdrop(song: Song?, modifier: Modifier = Modifier) {
    val context = LocalContext.current
    val fallback = remember { ArtworkColors.Edges(Color(0xFF3A2C18), Color(0xFF14110C)) }
    var edges by remember { mutableStateOf(song?.uri?.let(ArtworkColors::cached) ?: fallback) }
    LaunchedEffect(song?.uri) {
        val uri = song?.uri ?: return@LaunchedEffect
        edges = ArtworkColors.edges(context, uri) ?: fallback
    }
    val top by animateColorAsState(edges.top, tween(700, easing = FastOutSlowInEasing), label = "edgeTop")
    val bottom by animateColorAsState(edges.bottom, tween(700, easing = FastOutSlowInEasing), label = "edgeBottom")
    val drift = rememberInfiniteTransition(label = "drift")
    val t by drift.animateFloat(0f, 1f, infiniteRepeatable(tween(19_000, easing = LinearEasing), RepeatMode.Reverse), label = "driftT")
    val u by drift.animateFloat(0f, 1f, infiniteRepeatable(tween(27_000, easing = LinearEasing), RepeatMode.Reverse), label = "driftU")
    Box(
        modifier.drawBehind {
            val w = size.width
            val h = size.height
            drawRect(Color.Black)
            drawRect(Brush.verticalGradient(listOf(top, bottom)))
            val reach = max(w, h)
            drawRect(
                Brush.radialGradient(
                    listOf(top.copy(alpha = 0.75f), Color.Transparent),
                    center = Offset(w * (0.1f + 0.8f * t), h * (0.08f + 0.18f * u)),
                    radius = reach * 0.7f,
                ),
            )
            drawRect(
                Brush.radialGradient(
                    listOf(bottom.copy(alpha = 0.75f), Color.Transparent),
                    center = Offset(w * (0.9f - 0.8f * u), h * (0.92f - 0.2f * t)),
                    radius = reach * 0.75f,
                ),
            )
            drawRect(
                Brush.radialGradient(
                    listOf(lerp(top, bottom, 0.5f).copy(alpha = 0.5f), Color.Transparent),
                    center = Offset(w * (0.3f + 0.4f * u), h * (0.4f + 0.2f * t)),
                    radius = reach * 0.5f,
                ),
            )
            // Darken for legibility (the Mac's shade, a little stronger at the bottom).
            val topShade = 0.18f + 0.30f * top.brightness()
            val bottomShade = 0.30f + 0.40f * bottom.brightness()
            drawRect(
                Brush.verticalGradient(
                    0f to Color.Black.copy(alpha = topShade.coerceAtMost(0.9f)),
                    0.45f to Color.Black.copy(alpha = (topShade + 0.08f).coerceAtMost(0.9f)),
                    1f to Color.Black.copy(alpha = (bottomShade + 0.25f).coerceAtMost(0.92f)),
                ),
            )
        },
    )
}

// MARK: - Up Next sheet (cover screen)

/** The iPhone's Up Next sheet: opens at about 60 % of the screen; drag up for more, down to close. */
@Composable
private fun UpNextSheet(screenHeight: Dp, onClose: () -> Unit) {
    val scope = rememberCoroutineScope()
    val density = LocalDensity.current
    val medium = screenHeight * 0.62f
    val large = screenHeight * 0.94f
    var height by remember { mutableFloatStateOf(medium.value) }
    var settle by remember { mutableStateOf<Job?>(null) }
    var adding by rememberSaveable { mutableStateOf(false) }
    // Finding songs brings up the keyboard: open the sheet fully so the results show above it.
    LaunchedEffect(adding) {
        if (adding && height < large.value) {
            settle?.cancel()
            animate(height, large.value, animationSpec = spring(dampingRatio = 0.86f, stiffness = 400f)) { v, _ -> height = v }
        }
    }
    val dragState = rememberDraggableState { delta ->
        val dp = with(density) { delta.toDp().value }
        height = (height - dp).coerceIn(0f, large.value)
    }
    val shape = RoundedCornerShape(topStart = 22.dp, topEnd = 22.dp)
    Column(
        Modifier
            .fillMaxWidth()
            .height(height.dp)
            .clip(shape)
            .background(Color(0xFF1C1C1A).copy(alpha = 0.97f))
            .blockTouches()
            .navigationBarsPadding(),
    ) {
        Column(
            Modifier
                .fillMaxWidth()
                .draggable(
                    state = dragState,
                    orientation = Orientation.Vertical,
                    onDragStarted = { settle?.cancel() },
                    onDragStopped = { velocity ->
                        val velocityDp = with(density) { velocity.toDp().value }
                        val projected = height - velocityDp * 0.15f
                        val target = when {
                            projected < medium.value * 0.6f -> 0f
                            projected < (medium.value + large.value) / 2f -> medium.value
                            else -> large.value
                        }
                        settle = scope.launch {
                            animate(height, target, animationSpec = spring(dampingRatio = 0.86f, stiffness = 400f)) { v, _ -> height = v }
                            if (target == 0f) onClose()
                        }
                    },
                ),
        ) {
            Box(
                Modifier.align(Alignment.CenterHorizontally).padding(top = 8.dp).size(width = 36.dp, height = 5.dp)
                    .clip(CircleShape).background(Hush.muted.copy(alpha = 0.6f)),
            )
            Box(Modifier.fillMaxWidth().height(52.dp).padding(horizontal = 8.dp)) {
                if (adding) {
                    Text("Add Songs", style = Hush.sans(17.sp, Hush.ink, FontWeight.SemiBold), modifier = Modifier.align(Alignment.Center))
                    TextAction("Done", Modifier.align(Alignment.CenterEnd)) { adding = false }
                } else {
                    TextAction("Add Songs", Modifier.align(Alignment.CenterStart), icon = Icons.Rounded.Add) { adding = true }
                    Text("Up Next", style = Hush.sans(17.sp, Hush.ink, FontWeight.SemiBold), modifier = Modifier.align(Alignment.Center))
                }
            }
        }
        if (adding) AddSongs(Modifier.weight(1f)) else UpNext(Modifier.weight(1f))
    }
}

/** A text button in the sheet's bar, 48 dp tall. */
@Composable
internal fun TextAction(label: String, modifier: Modifier = Modifier, icon: ImageVector? = null, color: Color = Hush.ink, onClick: () -> Unit) {
    Row(
        modifier
            .height(48.dp)
            .clip(RoundedCornerShape(24.dp))
            .clickable(role = Role.Button, onClick = onClick)
            .padding(horizontal = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (icon != null) {
            Icon(icon, contentDescription = null, tint = color, modifier = Modifier.size(20.dp))
            Spacer(Modifier.width(6.dp))
        }
        Text(label, style = Hush.sans(16.sp, color, FontWeight.SemiBold))
    }
}

/** A thin line to drag or tap, with the time so far and the time left beneath (used by the video player). */
@Composable
fun SeekBar(
    positionMs: Long, duration: Long, onSeek: (Long) -> Unit, modifier: Modifier = Modifier,
    onScrubbing: (Boolean) -> Unit = {},
) {
    val seek by rememberUpdatedState(onSeek)
    val scrubbingChanged by rememberUpdatedState(onScrubbing)
    var width by remember { mutableFloatStateOf(1f) }
    var scrubbing by remember { mutableStateOf<Float?>(null) }
    val fraction = scrubbing ?: if (duration > 0) (positionMs.toFloat() / duration).coerceIn(0f, 1f) else 0f
    Column(modifier) {
        Box(
            Modifier
                .fillMaxWidth()
                .height(36.dp)
                .onSizeChanged { width = it.width.toFloat().coerceAtLeast(1f) }
                .pointerInput(duration) {
                    detectTapGestures { offset ->
                        if (duration > 0) seek(((offset.x / width).coerceIn(0f, 1f) * duration).toLong())
                    }
                }
                .pointerInput(duration) {
                    detectHorizontalDragGestures(
                        onDragStart = {
                            scrubbing = (it.x / width).coerceIn(0f, 1f)
                            scrubbingChanged(true)
                        },
                        onDragEnd = {
                            scrubbing?.let { if (duration > 0) seek((it * duration).toLong()) }
                            scrubbing = null
                            scrubbingChanged(false)
                        },
                        onDragCancel = { scrubbing = null; scrubbingChanged(false) },
                    ) { change, _ ->
                        change.consume()
                        scrubbing = (change.position.x / width).coerceIn(0f, 1f)
                    }
                },
            contentAlignment = Alignment.CenterStart,
        ) {
            val thickness = if (scrubbing != null) 5.dp else 3.dp
            Box(Modifier.fillMaxWidth().height(thickness).clip(RoundedCornerShape(2.dp)).background(Hush.track))
            Box(Modifier.fillMaxWidth(fraction).height(thickness).clip(RoundedCornerShape(2.dp)).background(Hush.ink))
        }
        Row(Modifier.fillMaxWidth()) {
            Text(timeText((fraction * duration).toLong()), style = Hush.sans(13.sp, Hush.muted).copy(fontFeatureSettings = "tnum"))
            Spacer(Modifier.weight(1f))
            Text("-" + timeText(duration - (fraction * duration).toLong()), style = Hush.sans(13.sp, Hush.muted).copy(fontFeatureSettings = "tnum"))
        }
    }
}

