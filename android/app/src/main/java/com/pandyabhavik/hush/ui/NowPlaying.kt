package com.pandyabhavik.hush.ui

import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.gestures.detectVerticalDragGestures
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
import androidx.compose.material.icons.rounded.KeyboardArrowDown
import androidx.compose.material.icons.rounded.Pause
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material.icons.rounded.Repeat
import androidx.compose.material.icons.rounded.RepeatOne
import androidx.compose.material.icons.rounded.Shuffle
import androidx.compose.material.icons.rounded.SkipNext
import androidx.compose.material.icons.rounded.SkipPrevious
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.media3.common.Player
import com.pandyabhavik.hush.data.Song
import com.pandyabhavik.hush.data.timeText
import kotlin.math.roundToInt

/**
 * The player: the cover big and crisp, the title in serif, one quiet "Artist · Album" line, the
 * scrubber and transport, with shuffle and repeat at the bottom edges. Swipe down to close.
 * On the Fold's wide inner screen the cover sits on the left and the controls on the right.
 */
@Composable
fun NowPlaying(onClose: () -> Unit) {
    val actions = LocalActions.current
    val model = actions.model
    val player = model.player
    val song = model.library.song(player.currentId)
    var showQueue by remember { mutableStateOf(false) }
    var dragY by remember { mutableFloatStateOf(0f) }

    BackHandler { if (showQueue) showQueue = false else onClose() }

    BoxWithConstraints(
        Modifier
            .fillMaxSize()
            .offset { IntOffset(0, dragY.coerceAtLeast(0f).roundToInt()) }
            .background(Hush.paper)
            .pointerInput(Unit) {
                detectVerticalDragGestures(
                    onDragEnd = {
                        if (dragY > 140.dp.toPx()) onClose()
                        dragY = 0f
                    },
                    onDragCancel = { dragY = 0f },
                ) { change, amount ->
                    change.consume()
                    dragY += amount
                }
            }
            .statusBarsPadding()
            .navigationBarsPadding(),
    ) {
        val wide = maxWidth >= 600.dp && maxWidth > maxHeight * 0.85f
        Column(Modifier.fillMaxSize()) {
            Row(Modifier.fillMaxWidth().height(52.dp).padding(horizontal = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                PlainIconButton(Icons.Rounded.KeyboardArrowDown, "Close", size = 32.dp, onClick = onClose)
                Spacer(Modifier.weight(1f))
                PlainIconButton(
                    Icons.AutoMirrored.Rounded.QueueMusic, "Up Next",
                    tint = if (showQueue) Hush.ink else Hush.muted,
                ) { showQueue = !showQueue }
            }
            if (song == null) {
                Spacer(Modifier.weight(1f))
                return@Column
            }
            if (wide) {
                Row(Modifier.fillMaxSize().padding(horizontal = 32.dp, vertical = 12.dp), verticalAlignment = Alignment.CenterVertically) {
                    Box(Modifier.weight(1f).fillMaxHeight(), contentAlignment = Alignment.Center) {
                        PlayerCover(song)
                    }
                    Spacer(Modifier.width(40.dp))
                    Box(Modifier.weight(1f).fillMaxHeight()) {
                        AnimatedContent(showQueue, transitionSpec = { fadeIn() togetherWith fadeOut() }, label = "side") { queue ->
                            if (queue) UpNext(Modifier.fillMaxSize())
                            else Column(Modifier.fillMaxSize(), verticalArrangement = Arrangement.Center) { Controls(song, onClose) }
                        }
                    }
                }
            } else {
                AnimatedContent(showQueue, transitionSpec = { fadeIn() togetherWith fadeOut() }, label = "queue") { queue ->
                    if (queue) {
                        UpNext(Modifier.fillMaxSize())
                    } else {
                        Column(Modifier.fillMaxSize()) {
                            Box(Modifier.fillMaxWidth().padding(horizontal = Hush.sideMargin), contentAlignment = Alignment.Center) {
                                PlayerCover(song)
                            }
                            Spacer(Modifier.weight(1f))
                            Controls(song, onClose)
                            Spacer(Modifier.height(8.dp))
                        }
                    }
                }
            }
        }
    }
}

/** The cover, crisp, inside a thin black border; swipe it sideways to change songs. */
@Composable
private fun PlayerCover(song: Song) {
    val player = LocalActions.current.model.player
    var drag by remember { mutableFloatStateOf(0f) }
    Box(
        Modifier
            .widthIn(max = 560.dp)
            .fillMaxWidth()
            .offset { IntOffset((drag * 0.5f).roundToInt(), 0) }
            .pointerInput(Unit) {
                detectHorizontalDragGestures(
                    onDragEnd = {
                        if (drag < -80.dp.toPx()) player.next() else if (drag > 80.dp.toPx()) player.previous()
                        drag = 0f
                    },
                    onDragCancel = { drag = 0f },
                ) { change, amount ->
                    change.consume()
                    drag += amount
                }
            }
            .background(Color.Black, RoundedCornerShape(10.dp))
            .padding(1.dp),
    ) {
        Cover(song, Modifier.fillMaxWidth(), 8.dp)
    }
}

@Composable
private fun Controls(song: Song, onClose: () -> Unit) {
    val actions = LocalActions.current
    val player = actions.model.player
    Column(Modifier.fillMaxWidth().padding(horizontal = Hush.sideMargin)) {
        Text(song.title, style = Hush.serif(29.sp), maxLines = 2, overflow = TextOverflow.Ellipsis)
        Spacer(Modifier.height(4.dp))
        Row {
            Text(
                song.artist, style = Hush.sans(16.sp, Hush.muted), maxLines = 1, overflow = TextOverflow.Ellipsis,
                modifier = Modifier.weight(1f, fill = false).clickableQuiet { actions.openArtistOf(song) },
            )
            Text(" · ", style = Hush.sans(16.sp, Hush.muted))
            Text(
                song.album, style = Hush.sans(16.sp, Hush.muted), maxLines = 1, overflow = TextOverflow.Ellipsis,
                modifier = Modifier.weight(1f, fill = false).clickableQuiet { actions.openAlbumOf(song) },
            )
        }
        Spacer(Modifier.height(24.dp))
        Scrubber()
        Spacer(Modifier.height(20.dp))
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically) {
            PlainIconButton(Icons.Rounded.SkipPrevious, "Previous", size = 30.dp) { player.previous() }
            Spacer(Modifier.width(48.dp))
            Box(
                Modifier.size(76.dp).clip(CircleShape).background(Hush.ink).clickableQuiet { player.togglePlayback() },
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    if (player.isPlaying) Icons.Rounded.Pause else Icons.Rounded.PlayArrow,
                    contentDescription = if (player.isPlaying) "Pause" else "Play",
                    tint = Color.Black, modifier = Modifier.size(38.dp),
                )
            }
            Spacer(Modifier.width(48.dp))
            PlainIconButton(Icons.Rounded.SkipNext, "Next", size = 30.dp) { player.next() }
        }
        Spacer(Modifier.height(16.dp))
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            PlainIconButton(Icons.Rounded.Shuffle, "Shuffle", tint = if (player.shuffled) Hush.ink else Hush.iconOff) {
                player.toggleShuffle()
            }
            Spacer(Modifier.weight(1f))
            PlainIconButton(
                if (player.repeatMode == Player.REPEAT_MODE_ONE) Icons.Rounded.RepeatOne else Icons.Rounded.Repeat,
                "Repeat",
                tint = if (player.repeatMode == Player.REPEAT_MODE_OFF) Hush.iconOff else Hush.ink,
            ) { player.cycleRepeat() }
        }
    }
}

/** A 3 dp track with an ink fill; drag or tap anywhere on it to move through the song. */
@Composable
private fun Scrubber() {
    val player = LocalActions.current.model.player
    var width by remember { mutableFloatStateOf(1f) }
    var scrubbing by remember { mutableStateOf<Float?>(null) }
    val duration = player.durationMs
    val fraction = scrubbing ?: if (duration > 0) (player.positionMs.toFloat() / duration).coerceIn(0f, 1f) else 0f
    Column {
        Box(
            Modifier
                .fillMaxWidth()
                .height(28.dp)
                .onSizeChanged { width = it.width.toFloat().coerceAtLeast(1f) }
                .pointerInput(duration) {
                    detectTapGestures { offset ->
                        if (duration > 0) player.seek(((offset.x / width).coerceIn(0f, 1f) * duration).toLong())
                    }
                }
                .pointerInput(duration) {
                    detectHorizontalDragGestures(
                        onDragStart = { scrubbing = (it.x / width).coerceIn(0f, 1f) },
                        onDragEnd = {
                            scrubbing?.let { if (duration > 0) player.seek((it * duration).toLong()) }
                            scrubbing = null
                        },
                        onDragCancel = { scrubbing = null },
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
            Text(timeText((fraction * duration).toLong()), style = Hush.sans(12.sp, Hush.muted))
            Spacer(Modifier.weight(1f))
            Text("-" + timeText(duration - (fraction * duration).toLong()), style = Hush.sans(12.sp, Hush.muted))
        }
    }
}
