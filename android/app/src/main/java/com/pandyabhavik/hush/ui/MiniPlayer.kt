package com.pandyabhavik.hush.ui

import android.os.SystemClock
import android.view.HapticFeedbackConstants
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.animate
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.scaleOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
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
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Pause
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.input.pointer.util.VelocityTracker
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlin.math.abs

/**
 * The iPhone's mini player: a solid dark card, 64 dp high with 18 dp corners, the cover, the song
 * and play/pause, and a thin progress line along the bottom. Tap or swipe up to open the player,
 * swipe left for the next song and right for the previous one, press and hold for more.
 */
@Composable
fun MiniPlayer(modifier: Modifier = Modifier) {
    val actions = LocalActions.current
    val model = actions.model
    val player = model.player
    val song = model.library.song(player.currentId) ?: return
    val view = LocalView.current
    val scope = rememberCoroutineScope()
    var offsetX by remember { mutableFloatStateOf(0f) }
    var settle by remember { mutableStateOf<Job?>(null) }
    var lastDragEnd by remember { mutableLongStateOf(0L) }
    var menu by remember { mutableStateOf(false) }
    val shape = RoundedCornerShape(18.dp)

    fun springBack() {
        settle = scope.launch { animate(offsetX, 0f, animationSpec = spring(dampingRatio = 0.8f, stiffness = 322f)) { v, _ -> offsetX = v } }
    }
    val tapsAllowed = { SystemClock.uptimeMillis() - lastDragEnd > 400 }

    Box(modifier.padding(start = 12.dp, end = 12.dp, bottom = 4.dp)) {
        Box(
            Modifier
                .testTag("miniPlayer")
                .fillMaxWidth()
                .height(64.dp)
                .pointerInput(Unit) {
                    detectTapGestures(
                        onTap = { if (tapsAllowed()) actions.openPlayer() },
                        onLongPress = {
                            view.performHapticFeedback(HapticFeedbackConstants.LONG_PRESS)
                            menu = true
                        },
                    )
                }
                .pointerInput(Unit) {
                    val tracker = VelocityTracker()
                    var total = Offset.Zero
                    var crossed = false
                    val threshold = 64.dp.toPx()
                    fun finish() {
                        lastDragEnd = SystemClock.uptimeMillis()
                        springBack()
                    }
                    detectDragGestures(
                        onDragStart = {
                            settle?.cancel()
                            tracker.resetTracking()
                            total = Offset.Zero
                            crossed = false
                        },
                        onDragEnd = {
                            val velocity = tracker.calculateVelocity()
                            val dx = total.x
                            val dy = total.y
                            // Where a fling would carry the finger, roughly.
                            val flingDx = velocity.x * 0.25f
                            if (abs(dy) > abs(dx) && dy < -30.dp.toPx()) {
                                actions.openPlayer()
                            } else if (abs(dx) > abs(dy) && (abs(dx) > threshold || abs(flingDx) > 240.dp.toPx())) {
                                view.performHapticFeedback(HapticFeedbackConstants.CONTEXT_CLICK)
                                if (dx + flingDx < 0) player.next() else player.previous()
                            }
                            finish()
                        },
                        onDragCancel = { finish() },
                    ) { change, amount ->
                        change.consume()
                        tracker.addPosition(change.uptimeMillis, change.position)
                        total += amount
                        offsetX = if (abs(total.x) > abs(total.y)) total.x * 0.35f else 0f
                        val over = abs(total.x) > threshold
                        if (over != crossed) {
                            crossed = over
                            if (over) view.performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK)
                        }
                    }
                },
        ) {
            Box(
                Modifier
                    .fillMaxWidth()
                    .height(64.dp)
                    .graphicsLayer { translationX = offsetX }
                    .clip(shape)
                    .background(Hush.card)
                    .border(1.dp, Hush.ink.copy(alpha = 0.06f), shape),
            ) {
                Row(
                    Modifier.fillMaxWidth().fillMaxHeight().padding(start = 10.dp, end = 6.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Cover(song, Modifier.size(44.dp), 7.dp)
                    Spacer(Modifier.width(12.dp))
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        Text(song.title, style = Hush.sans(15.sp, weight = FontWeight.SemiBold), maxLines = 1, overflow = TextOverflow.Ellipsis)
                        Text(song.artist, style = Hush.sans(13.sp, Hush.muted), maxLines = 1, overflow = TextOverflow.Ellipsis)
                    }
                    Spacer(Modifier.width(4.dp))
                    MiniPlayPause(player.isPlaying) {
                        if (tapsAllowed()) {
                            view.performHapticFeedback(HapticFeedbackConstants.CONFIRM)
                            player.togglePlayback()
                        }
                    }
                }
                // The progress: only the filled part, clipped by the rounded corners; drawn from
                // the position without recomposing the card.
                PlaybackProgressLine(Hush.ink, Modifier.align(Alignment.BottomStart).fillMaxWidth().height(2.dp))
            }
        }
        Box(Modifier.align(Alignment.TopStart)) {
            SongActionsMenu(song, menu) { menu = false }
        }
    }
}

/** Play/pause with no background: the glyph pops when it changes; 48 dp to touch. */
@Composable
private fun MiniPlayPause(playing: Boolean, onClick: () -> Unit) {
    Box(
        Modifier
            .size(48.dp)
            .clip(CircleShape)
            .clickable(role = Role.Button, onClick = onClick)
            .semantics { contentDescription = if (playing) "Pause" else "Play" },
        contentAlignment = Alignment.Center,
    ) {
        AnimatedContent(
            playing,
            transitionSpec = {
                (scaleIn(spring(dampingRatio = 0.55f, stiffness = 439f), initialScale = 0.5f) + fadeIn(tween(120))) togetherWith
                    (scaleOut(tween(120), targetScale = 0.5f) + fadeOut(tween(120)))
            },
            label = "miniGlyph",
        ) { isPlaying ->
            Icon(
                if (isPlaying) Icons.Rounded.Pause else Icons.Rounded.PlayArrow,
                contentDescription = null, tint = Hush.ink, modifier = Modifier.size(28.dp),
            )
        }
    }
}
