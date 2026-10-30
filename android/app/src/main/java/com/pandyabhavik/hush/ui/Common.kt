package com.pandyabhavik.hush.ui

import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material.icons.rounded.Shuffle
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.pandyabhavik.hush.HushModel
import com.pandyabhavik.hush.data.Song

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
) {
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

/** A song in a list: cover, title, artist; the playing one gets a mark. Long-press for more. */
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun SongRow(song: Song, isCurrent: Boolean, isPlaying: Boolean, onClick: () -> Unit) {
    var menu by remember { mutableStateOf(false) }
    val haptics = LocalHapticFeedback.current
    Box {
        Row(
            Modifier
                .fillMaxWidth()
                .height(64.dp)
                .combinedClickable(onClick = onClick, onLongClick = {
                    haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                    menu = true
                })
                .padding(horizontal = Hush.sideMargin),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Cover(song, Modifier.size(48.dp), 6.dp)
            Column(Modifier.padding(start = 14.dp).weight(1f)) {
                Text(song.title, style = Hush.title16, maxLines = 1, overflow = TextOverflow.Ellipsis)
                Text(song.artist, style = Hush.sub13, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
            if (isCurrent) {
                Spacer(Modifier.width(12.dp))
                Equalizer(isPlaying, Modifier.size(14.dp))
            }
        }
        SongMenu(listOf(song), menu, { menu = false }, song = song)
    }
}

/** Play Next / Add to Queue, plus Go to Album / Artist for a single song. */
@Composable
fun SongMenu(songs: List<Song>, expanded: Boolean, onDismiss: () -> Unit, song: Song? = null, extra: @Composable (() -> Unit)? = null) {
    val actions = LocalActions.current
    DropdownMenu(expanded = expanded, onDismissRequest = onDismiss, containerColor = Hush.card) {
        DropdownMenuItem(text = { Text("Play Next") }, onClick = { actions.model.player.playNext(songs); onDismiss() })
        DropdownMenuItem(text = { Text("Add to Queue") }, onClick = { actions.model.player.addToQueue(songs); onDismiss() })
        if (song != null) {
            DropdownMenuItem(text = { Text("Go to Album") }, onClick = { onDismiss(); actions.openAlbumOf(song) })
            DropdownMenuItem(text = { Text("Go to Artist") }, onClick = { onDismiss(); actions.openArtistOf(song) })
        }
        extra?.invoke()
    }
}

/** Three little bars that dance while the song plays. */
@Composable
fun Equalizer(playing: Boolean, modifier: Modifier = Modifier, color: Color = Hush.ink) {
    val transition = rememberInfiniteTransition(label = "eq")
    val bars = listOf(420, 560, 360).mapIndexed { i, duration ->
        transition.animateFloat(
            initialValue = 0.3f, targetValue = 1f,
            animationSpec = infiniteRepeatable(tween(duration), RepeatMode.Reverse),
            label = "bar$i",
        )
    }
    val still = listOf(0.45f, 0.8f, 0.6f)
    Row(modifier, horizontalArrangement = Arrangement.spacedBy(2.dp), verticalAlignment = Alignment.Bottom) {
        bars.forEachIndexed { i, bar ->
            Box(
                Modifier
                    .weight(1f)
                    .fillMaxHeight(if (playing) bar.value else still[i])
                    .clip(RoundedCornerShape(1.dp))
                    .background(color),
            )
        }
    }
}

/** Play (filled) and Shuffle (outlined), side by side. */
@Composable
fun PlayShuffleButtons(songs: List<Song>, modifier: Modifier = Modifier) {
    val player = LocalActions.current.model.player
    Row(modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        PillButton("Play", Icons.Rounded.PlayArrow, filled = true, Modifier.weight(1f)) { player.play(songs) }
        PillButton("Shuffle", Icons.Rounded.Shuffle, filled = false, Modifier.weight(1f)) { player.playShuffled(songs) }
    }
}

@Composable
fun PillButton(label: String, icon: androidx.compose.ui.graphics.vector.ImageVector, filled: Boolean, modifier: Modifier, onClick: () -> Unit) {
    val shape = RoundedCornerShape(12.dp)
    Row(
        modifier
            .height(48.dp)
            .clip(shape)
            .then(if (filled) Modifier.background(Hush.ink) else Modifier.border(1.dp, Hush.outline, shape))
            .clickableQuiet(onClick),
        horizontalArrangement = Arrangement.Center,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        val color = if (filled) Color.Black else Hush.ink
        Icon(icon, contentDescription = null, tint = color, modifier = Modifier.size(20.dp))
        Spacer(Modifier.width(6.dp))
        Text(label, style = Hush.sans(16.sp, color, FontWeight.SemiBold))
    }
}

/** A 44 dp icon button with no ripple circle, like the iPhone's plain buttons. */
@Composable
fun PlainIconButton(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    description: String,
    tint: Color = Hush.ink,
    size: Dp = 24.dp,
    onClick: () -> Unit,
) {
    Box(Modifier.size(Hush.tapTarget).clip(RoundedCornerShape(22.dp)).clickableQuiet(onClick), contentAlignment = Alignment.Center) {
        Icon(icon, contentDescription = description, tint = tint, modifier = Modifier.size(size))
    }
}

fun Modifier.clickableQuiet(onClick: () -> Unit): Modifier = this.clickable(onClick = onClick)

/** Keeps touches from reaching whatever is drawn underneath (pages sit over the library). */
fun Modifier.blockTouches(): Modifier = this.pointerInput(Unit) {
    awaitPointerEventScope { while (true) awaitPointerEvent() }
}
