package com.pandyabhavik.hush.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Pause
import androidx.compose.material.icons.rounded.PlayArrow
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
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlin.math.abs
import kotlin.math.roundToInt

/**
 * The quiet mini player: a solid card with the cover, the song and play/pause. Swipe left for the
 * next song, right for the previous one. Tap to open the player; long-press for more.
 */
@Composable
fun MiniPlayer(modifier: Modifier = Modifier) {
    val actions = LocalActions.current
    val model = actions.model
    val player = model.player
    val song = model.library.song(player.currentId) ?: return
    val haptics = LocalHapticFeedback.current
    var drag by remember { mutableFloatStateOf(0f) }
    var menu by remember { mutableStateOf(false) }
    val shape = RoundedCornerShape(18.dp)

    Box(modifier.padding(horizontal = 12.dp)) {
        Box(
            Modifier
                .fillMaxWidth()
                .height(64.dp)
                .clip(shape)
                .background(Hush.card)
                .border(1.dp, Hush.ink.copy(alpha = 0.06f), shape)
                .pointerInput(Unit) {
                    detectTapGestures(
                        onTap = { actions.openPlayer() },
                        onLongPress = {
                            haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                            menu = true
                        },
                    )
                }
                .pointerInput(Unit) {
                    detectHorizontalDragGestures(
                        onDragEnd = {
                            val threshold = 60.dp.toPx()
                            if (abs(drag) > threshold) {
                                haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                                if (drag < 0) player.next() else player.previous()
                            }
                            drag = 0f
                        },
                        onDragCancel = { drag = 0f },
                    ) { change, amount ->
                        change.consume()
                        drag += amount
                    }
                },
        ) {
            Row(
                Modifier.fillMaxWidth().fillMaxHeight().offset { IntOffset((drag * 0.4f).roundToInt(), 0) }.padding(start = 10.dp, end = 6.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Cover(song, Modifier.size(44.dp), 7.dp)
                Column(Modifier.padding(start = 12.dp).weight(1f)) {
                    Text(song.title, style = Hush.sans(15.sp, weight = FontWeight.SemiBold), maxLines = 1, overflow = TextOverflow.Ellipsis)
                    Text(song.artist, style = Hush.sans(13.sp, Hush.muted), maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
                PlainIconButton(
                    if (player.isPlaying) Icons.Rounded.Pause else Icons.Rounded.PlayArrow,
                    if (player.isPlaying) "Pause" else "Play",
                    size = 30.dp,
                ) { player.togglePlayback() }
            }
            // A thin progress line along the bottom edge.
            val progress = if (player.durationMs > 0) (player.positionMs.toFloat() / player.durationMs).coerceIn(0f, 1f) else 0f
            Box(
                Modifier.align(Alignment.BottomStart).fillMaxWidth(progress).height(2.dp).background(Hush.ink),
            )
        }
        SongMenu(listOf(song), menu, { menu = false }, song = song)
    }
}
