package com.pandyabhavik.hush.ui

import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.FiniteAnimationSpec
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.gestures.animateScrollBy
import androidx.compose.foundation.gestures.scrollBy
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.PlaylistAdd
import androidx.compose.material.icons.automirrored.rounded.PlaylistPlay
import androidx.compose.material.icons.rounded.Album
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.Mic
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material.icons.rounded.Shuffle
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.composed
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.pandyabhavik.hush.HushModel
import com.pandyabhavik.hush.data.Song
import kotlinx.coroutines.delay
import kotlin.math.max
import kotlin.math.sin

sealed interface Route {
    data class AlbumPage(val key: String) : Route
    data class PlaylistPage(val id: String) : Route
    data class ArtistPage(val id: String) : Route
}

/** What any screen can do: open pages, the player, play songs. */
@Stable
class HushActions(
    val model: HushModel,
    private val push: (Route) -> Unit,
    private val showPlayer: (Boolean) -> Unit,
    private val showVideo: (com.pandyabhavik.hush.data.Video?) -> Unit,
) {
    fun playVideo(video: com.pandyabhavik.hush.data.Video) = showVideo(video)

    fun open(route: Route) {
        showPlayer(false)
        push(route)
    }
    fun openPlayer() = showPlayer(true)
    fun closePlayer() = showPlayer(false)

    fun openAlbumOf(song: Song) = open(Route.AlbumPage(song.albumKey))
    fun openArtistOf(song: Song) {
        val artists = model.library.creditedArtists(song)
        artists.firstOrNull()?.let { open(Route.ArtistPage(it.id)) }
    }
}

val LocalActions = staticCompositionLocalOf<HushActions> { error("No actions") }

@Composable
fun HushMaterialTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = darkColorScheme(
            background = Hush.paper,
            surface = Hush.card,
            surfaceContainer = Hush.card,
            primary = Hush.ink,
            onPrimary = Color.Black,
            onSurface = Hush.ink,
            onBackground = Hush.ink,
            onSurfaceVariant = Hush.muted,
            surfaceVariant = Hush.card,
            outline = Hush.outline,
        ),
        content = content,
    )
}

// ---------------------------------------------------------------------------------------------
// Press feedback: no ripples. Tiles shrink a little, buttons pop, plain controls dim.
// ---------------------------------------------------------------------------------------------

/**
 * A quiet tap (and optional long press) with no ripple. While pressed the element scales to
 * [scale] and fades to [dim], like the iPhone's press styles: tiles 0.965 / 0.85, pop buttons 0.86.
 */
@OptIn(ExperimentalFoundationApi::class)
fun Modifier.pressable(
    scale: Float = 0.965f,
    dim: Float = 0.85f,
    enabled: Boolean = true,
    role: Role? = Role.Button,
    spec: FiniteAnimationSpec<Float>? = null,
    onLongClick: (() -> Unit)? = null,
    onClick: () -> Unit,
): Modifier = composed {
    val source = remember { MutableInteractionSource() }
    val pressed by source.collectIsPressedAsState()
    val haptics = LocalHapticFeedback.current
    val animation = spec ?: Hush.tilePress
    val s by animateFloatAsState(if (pressed) scale else 1f, animation, label = "pressScale")
    val a by animateFloatAsState(if (pressed) dim else 1f, animation, label = "pressDim")
    this
        .graphicsLayer {
            scaleX = s
            scaleY = s
            alpha = a
        }
        .combinedClickable(
            interactionSource = source,
            indication = null,
            enabled = enabled,
            role = role,
            onLongClick = onLongClick?.let { long ->
                {
                    haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                    long()
                }
            },
            onClick = onClick,
        )
}

/** Tiles: scale 0.965 and a slight fade while pressed. */
fun Modifier.tilePressable(onLongClick: (() -> Unit)? = null, onClick: () -> Unit): Modifier =
    pressable(scale = 0.965f, dim = 0.85f, onLongClick = onLongClick, onClick = onClick)

/** A plain tap: no ripple, the element dims while pressed. */
fun Modifier.clickableQuiet(onClick: () -> Unit): Modifier = pressable(scale = 1f, dim = 0.45f, onClick = onClick)

/** Keeps touches from reaching whatever is drawn underneath (pages sit over the library). */
fun Modifier.blockTouches(): Modifier = this.pointerInput(Unit) {
    awaitPointerEventScope { while (true) awaitPointerEvent() }
}

/** The largest a cover may be drawn so it is never shown at more than ~1.3x its pixels. */
@Composable
fun maxCoverSize(pixels: Int = Hush.coverPixels): Dp =
    with(LocalDensity.current) { (pixels * Hush.maxCoverScale).toDp() }

/** Scrolls so the item at [index] sits in the middle of the list (estimating rows not yet laid out). */
internal suspend fun LazyListState.centerItem(index: Int, animate: Boolean, spec: FiniteAnimationSpec<Float> = Hush.snappy) {
    val info = layoutInfo
    val visible = info.visibleItemsInfo
    if (visible.isEmpty()) return
    val target = visible.firstOrNull { it.index == index }
    val (offset, size) = if (target != null) {
        target.offset to target.size
    } else {
        val rows = visible.filter { it.index > 0 }.ifEmpty { visible }
        val average = rows.sumOf { it.size } / rows.size
        val last = visible.last()
        val first = visible.first()
        if (index > last.index) (last.offset + last.size + (index - last.index - 1) * average) to average
        else (first.offset - (first.index - index) * average) to average
    }
    val viewport = if (info.orientation == androidx.compose.foundation.gestures.Orientation.Vertical) info.viewportSize.height else info.viewportSize.width
    val center = viewport / 2 + info.viewportStartOffset
    val delta = (offset + size / 2 - center).toFloat()
    if (animate) animateScrollBy(delta, spec) else scrollBy(delta)
}

// ---------------------------------------------------------------------------------------------
// Menus
// ---------------------------------------------------------------------------------------------

/** A dark, rounded drop-down menu with a faint edge. */
@Composable
fun HushMenu(expanded: Boolean, onDismiss: () -> Unit, modifier: Modifier = Modifier, content: @Composable ColumnScope.() -> Unit) {
    DropdownMenu(
        expanded = expanded,
        onDismissRequest = onDismiss,
        modifier = modifier.width(250.dp),
        shape = RoundedCornerShape(14.dp),
        containerColor = Color(0xFF1C1C1A),
        tonalElevation = 0.dp,
        shadowElevation = 12.dp,
        border = BorderStroke(0.5.dp, Hush.edge),
        content = content,
    )
}

/** A menu line: the words, a check when chosen, and the icon at the end (as in iPhone menus). */
@Composable
fun HushMenuItem(
    text: String,
    icon: ImageVector? = null,
    checked: Boolean? = null,
    destructive: Boolean = false,
    enabled: Boolean = true,
    onClick: () -> Unit,
) {
    val color = if (destructive) Color(0xFFFF6B5E) else Hush.ink
    DropdownMenuItem(
        text = { Text(text, style = Hush.sans(16.sp, color), maxLines = 2, overflow = TextOverflow.Ellipsis) },
        onClick = onClick,
        enabled = enabled,
        leadingIcon = checked?.let { on ->
            { Box(Modifier.size(20.dp)) { if (on) Icon(Icons.Rounded.Check, null, tint = Hush.ink, modifier = Modifier.size(20.dp)) } }
        },
        trailingIcon = icon?.let { { Icon(it, null, tint = if (destructive) color else Hush.muted, modifier = Modifier.size(20.dp)) } },
        modifier = Modifier.heightIn(min = 48.dp),
    )
}

/** A thin line between menu groups. */
@Composable
fun HushMenuDivider() {
    Box(Modifier.fillMaxWidth().padding(vertical = 4.dp).heightIn(min = 0.5.dp).background(Hush.line))
}

/** Play Next / Add to Queue, plus Go to Album / Artist for a single song. */
@Composable
fun SongMenu(songs: List<Song>, expanded: Boolean, onDismiss: () -> Unit, song: Song? = null, extra: @Composable (() -> Unit)? = null) {
    val actions = LocalActions.current
    HushMenu(expanded, onDismiss) {
        HushMenuItem("Play Next", Icons.AutoMirrored.Rounded.PlaylistPlay) { actions.model.player.playNext(songs); onDismiss() }
        HushMenuItem("Add to Queue", Icons.AutoMirrored.Rounded.PlaylistAdd) { actions.model.player.addToQueue(songs); onDismiss() }
        if (song != null) {
            HushMenuDivider()
            HushMenuItem("Go to Album", Icons.Rounded.Album) { onDismiss(); actions.openAlbumOf(song) }
            HushMenuItem("Go to Artist", Icons.Rounded.Mic) { onDismiss(); actions.openArtistOf(song) }
        }
        extra?.invoke()
    }
}

// ---------------------------------------------------------------------------------------------
// Song rows and the now-playing mark
// ---------------------------------------------------------------------------------------------

/** A song in a list: cover, title, artist; the playing one gets a mark on its cover. Long-press for more. */
@Composable
fun SongRow(
    song: Song,
    isCurrent: Boolean,
    isPlaying: Boolean,
    modifier: Modifier = Modifier,
    horizontalPadding: Dp = Hush.sideMargin,
    onClick: () -> Unit,
) {
    var menu by remember { mutableStateOf(false) }
    Box(modifier) {
        Row(
            Modifier
                .fillMaxWidth()
                .heightIn(min = 64.dp)
                .pressable(scale = 1f, dim = 0.6f, onLongClick = { menu = true }, onClick = onClick)
                .padding(horizontal = horizontalPadding, vertical = 6.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Box {
                Cover(song, Modifier.size(48.dp), 6.dp)
                if (isCurrent) NowPlayingBadge(isPlaying, 18.dp, Modifier.align(Alignment.BottomEnd).offset(3.dp, 3.dp))
            }
            Column(Modifier.padding(start = 14.dp).weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                Text(
                    song.title.ifBlank { "Untitled" },
                    style = Hush.sans(16.sp, weight = if (isCurrent) FontWeight.SemiBold else FontWeight.Medium),
                    maxLines = 1, overflow = TextOverflow.Ellipsis,
                )
                Text(song.artist.ifBlank { "Unknown Artist" }, style = Hush.sub13, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
        }
        SongMenu(listOf(song), menu, { menu = false }, song = song)
    }
}

private val barSpeeds = floatArrayOf(8.2f, 10.6f, 7.1f)
private val barPhases = floatArrayOf(0f, 1.9f, 3.4f)
private val barRest = floatArrayOf(0.45f, 0.85f, 0.6f)

/**
 * Three bars that dance while the song plays (the iPhone's NowPlayingBars): two sine waves per
 * bar at about 30 fps, settling to rest heights when paused.
 */
@Composable
fun Equalizer(playing: Boolean, modifier: Modifier = Modifier, color: Color = Hush.ink) {
    var time by remember { mutableFloatStateOf(0f) }
    val motion by animateFloatAsState(if (playing) 1f else 0f, tween(300, easing = FastOutSlowInEasing), label = "bars")
    LaunchedEffect(playing) {
        if (!playing) return@LaunchedEffect
        val base = time
        val start = withFrameNanos { it }
        while (true) {
            withFrameNanos { time = base + (it - start) / 1_000_000_000f }
            delay(30)
        }
    }
    Spacer(
        modifier.drawBehind {
            val h = size.height
            val barW = max(2.dp.toPx(), h * 0.2f)
            val gap = max(1.5.dp.toPx(), h * 0.14f)
            val total = barW * 3 + gap * 2
            var x = (size.width - total) / 2f
            for (i in 0..2) {
                val s = barSpeeds[i]
                val p = barPhases[i]
                val wave = sin(time * s + p) * 0.6f + sin(time * s * 0.53f + 2 * p) * 0.4f
                val live = 0.3f + 0.7f * ((wave + 1f) / 2f)
                val level = barRest[i] + (live - barRest[i]) * motion
                val barH = h * level
                drawRoundRect(color, Offset(x, h - barH), Size(barW, barH), CornerRadius(barW / 2f))
                x += barW + gap
            }
        },
    )
}

/** The bars in black on an ink circle, overhanging a cover's corner. */
@Composable
fun NowPlayingBadge(playing: Boolean, size: Dp, modifier: Modifier = Modifier) {
    Box(
        modifier
            .size(size)
            .shadow(3.dp, CircleShape, ambientColor = Color.Black.copy(alpha = 0.3f), spotColor = Color.Black.copy(alpha = 0.3f))
            .background(Hush.accent, CircleShape),
        contentAlignment = Alignment.Center,
    ) {
        Equalizer(playing, Modifier.size(size * 0.5f, size * 0.46f), Color.Black)
    }
}

/** A track number in equal-width digits, or the bars for the current song. */
@Composable
fun TrackNumberLabel(number: Int, isCurrent: Boolean, isPlaying: Boolean, modifier: Modifier = Modifier, alignment: Alignment = Alignment.CenterEnd) {
    Box(modifier, contentAlignment = alignment) {
        if (isCurrent) Equalizer(isPlaying, Modifier.size(15.dp, 13.dp), Hush.accent)
        else Text(if (number > 0) number.toString() else "·", style = Hush.mono(15.sp), maxLines = 1, softWrap = false)
    }
}

/** A hairline between rows, starting [start] in from the left. */
@Composable
fun TrackDivider(start: Dp, modifier: Modifier = Modifier, end: Dp = 0.dp) {
    Box(
        modifier
            .fillMaxWidth()
            .padding(start = start, end = end)
            .heightIn(min = 0.6.dp, max = 0.6.dp)
            .background(Hush.line.copy(alpha = 0.55f)),
    )
}

// ---------------------------------------------------------------------------------------------
// Buttons
// ---------------------------------------------------------------------------------------------

/** Play (filled) and Shuffle (outlined): equal capsules side by side. */
@Composable
fun PlayShuffleButtons(songs: List<Song>, modifier: Modifier = Modifier, enabled: Boolean = songs.isNotEmpty()) {
    val player = LocalActions.current.model.player
    Row(
        modifier.fillMaxWidth().graphicsLayer { alpha = if (enabled) 1f else 0.45f },
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Pill("Play", Icons.Rounded.PlayArrow, filled = true, Modifier.weight(1f), enabled) { player.play(songs) }
        Pill("Shuffle", Icons.Rounded.Shuffle, filled = false, Modifier.weight(1f), enabled) { player.playShuffled(songs) }
    }
}

/** A capsule button: ink with black words when [filled], else a thin outline with ink words. */
@Composable
fun PillButton(label: String, icon: ImageVector, filled: Boolean, modifier: Modifier, onClick: () -> Unit) =
    Pill(label, icon, filled, modifier, enabled = true, onClick = onClick)

@Composable
private fun Pill(
    label: String,
    icon: ImageVector,
    filled: Boolean,
    modifier: Modifier,
    enabled: Boolean,
    onClick: () -> Unit,
) {
    val shape = CircleShape
    Row(
        modifier
            .heightIn(min = 48.dp)
            .pressable(scale = 0.86f, dim = 1f, enabled = enabled, spec = Hush.popPress, onClick = onClick)
            .clip(shape)
            .then(if (filled) Modifier.background(Hush.ink) else Modifier.border(1.dp, Hush.outline, shape))
            .padding(horizontal = 16.dp, vertical = 10.dp),
        horizontalArrangement = Arrangement.Center,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        val color = if (filled) Color.Black else Hush.ink
        Icon(icon, contentDescription = null, tint = color, modifier = Modifier.size(if (filled) 20.dp else 18.dp))
        Spacer(Modifier.width(8.dp))
        Text(label, style = Hush.sans(16.sp, color, FontWeight.SemiBold), maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}

/** A plain icon button: no background, no ripple, at least 48 dp to touch; dims while pressed. */
@Composable
fun PlainIconButton(
    icon: ImageVector,
    description: String,
    tint: Color = Hush.ink,
    size: Dp = 26.dp,
    box: Dp = Hush.tapTarget,
    onClick: () -> Unit,
) {
    Box(
        Modifier.size(box).pressable(scale = 1f, dim = 0.4f, onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Icon(icon, contentDescription = description, tint = tint, modifier = Modifier.size(size))
    }
}

/** The accent capsule used in empty states: black words on ink. */
@Composable
fun AccentCapsule(label: String, modifier: Modifier = Modifier, onClick: () -> Unit) {
    Box(
        modifier
            .heightIn(min = 48.dp)
            .pressable(scale = 0.86f, dim = 1f, spec = Hush.popPress, onClick = onClick)
            .background(Hush.accent, CircleShape)
            .padding(horizontal = 18.dp, vertical = 11.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(label, style = Hush.sans(14.sp, Color.Black, FontWeight.SemiBold), maxLines = 2)
    }
}

/** "1 song", "12 songs". */
fun songCount(n: Int): String = if (n == 1) "1 song" else "$n songs"

/** "48 minutes", "1 hour, 5 minutes" for footers; null under a minute. */
fun longDurationText(ms: Long): String? {
    val minutes = Math.round(ms / 60000.0).toInt()
    if (minutes <= 0) return null
    fun unit(n: Int, word: String) = if (n == 1) "1 $word" else "$n ${word}s"
    if (minutes < 60) return unit(minutes, "minute")
    val hours = minutes / 60
    val rest = minutes % 60
    return if (rest == 0) unit(hours, "hour") else "${unit(hours, "hour")}, ${unit(rest, "minute")}"
}

