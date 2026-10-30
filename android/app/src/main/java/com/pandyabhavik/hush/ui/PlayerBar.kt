package com.pandyabhavik.hush.ui

import android.view.HapticFeedbackConstants
import androidx.compose.animation.animateColorAsState
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
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.QueueMusic
import androidx.compose.material.icons.rounded.SkipNext
import androidx.compose.material.icons.rounded.SkipPrevious
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/** The Mac palette used by the wide player bar. */
private object BarInk {
    val surface = Color(0xFF1E1C19)
    val secondary = Color(0xFFA9A69F)
    val icon = Color(0xFFB8B5AE)
    val gold = Color(0xFFC9A86B)
    val paper = Color(0xFF0A0A09)
}

/**
 * The player bar for the wide (unfolded) screen: a floating capsule, 72 dp high, inset 16 dp from
 * the edges and at most 720 dp wide, centred. Cover and song at the start (tap to open Now
 * Playing, press and hold for Go to Album / Artist), previous / play / next, and the Up Next
 * toggle. A thin progress line runs along its bottom edge.
 *
 * Draw it at the bottom of the screen with the 16 dp inset (and `navigationBarsPadding()`) in
 * [modifier]; the shadow spills outside its bounds, so don't clip its parent. While Now Playing is open
 * it hides itself from accessibility (and tests), so its buttons never double the player's.
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun PlayerBar(upNextOpen: Boolean, onToggleUpNext: () -> Unit, modifier: Modifier = Modifier) {
    val actions = LocalActions.current
    val model = actions.model
    val player = model.player
    val song = model.library.song(player.currentId) ?: return
    val view = LocalView.current
    var menu by remember { mutableStateOf(false) }
    val shape = RoundedCornerShape(24.dp)

    Box(
        modifier
            .fillMaxWidth()
            .then(if (model.playerOpen) Modifier.clearAndSetSemantics { } else Modifier),
        contentAlignment = Alignment.BottomCenter,
    ) {
        Box(
            Modifier
                .widthIn(max = 720.dp)
                .fillMaxWidth()
                .height(72.dp)
                .softShadow(CoverShadow(Color.Black.copy(alpha = 0.5f), 24.dp, 10.dp), 24.dp)
                .clip(shape)
                .background(BarInk.surface.copy(alpha = 0.94f))
                .border(1.dp, Color.White.copy(alpha = 0.10f), shape)
                .blockTouches(),
        ) {
            Row(
                Modifier.fillMaxWidth().fillMaxHeight().padding(start = 12.dp, end = 10.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                // Cover and song: open Now Playing.
                Box(Modifier.weight(1f)) {
                    Row(
                        Modifier
                            .testTag("miniPlayer")
                            .fillMaxWidth()
                            .height(60.dp)
                            .clip(RoundedCornerShape(14.dp))
                            .combinedClickable(
                                onClickLabel = "Open Now Playing",
                                onLongClick = {
                                    view.performHapticFeedback(HapticFeedbackConstants.LONG_PRESS)
                                    menu = true
                                },
                                onClick = { actions.openPlayer() },
                            )
                            .padding(horizontal = 4.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Cover(song, Modifier.size(48.dp), 10.dp)
                        Spacer(Modifier.width(12.dp))
                        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                            Text(song.title, style = Hush.sans(14.sp, Hush.ink, FontWeight.SemiBold), maxLines = 1, overflow = TextOverflow.Ellipsis)
                            Text(
                                "${song.artist} · ${song.album}", style = Hush.sans(12.sp, BarInk.secondary),
                                maxLines = 1, overflow = TextOverflow.Ellipsis,
                            )
                        }
                    }
                    SongActionsMenu(song, menu) { menu = false }
                }
                Spacer(Modifier.width(12.dp))
                PlayerIconButton(Icons.Rounded.SkipPrevious, "Previous", Hush.ink, 28.dp, haptic = true) { player.previous() }
                PlayPauseButton(player.isPlaying, 44.dp, BarInk.gold, BarInk.paper) { player.togglePlayback() }
                PlayerIconButton(Icons.Rounded.SkipNext, "Next", Hush.ink, 28.dp, haptic = true) { player.next() }
                Spacer(Modifier.width(8.dp))
                UpNextToggle(upNextOpen, onToggleUpNext)
            }
            // Reads the position only while drawing, so the bar doesn't recompose four times a second.
            PlaybackProgressLine(BarInk.gold.copy(alpha = 0.9f), Modifier.align(Alignment.BottomStart).fillMaxWidth().height(2.dp))
        }
    }
}

/** The Up Next toggle: gold on a soft gold square while the panel is open. */
@Composable
private fun UpNextToggle(open: Boolean, onClick: () -> Unit) {
    val fill by animateColorAsState(if (open) BarInk.gold.copy(alpha = 0.18f) else Color.Transparent, tween(200), label = "upNextFill")
    val tint by animateColorAsState(if (open) BarInk.gold else BarInk.icon, tween(200), label = "upNextTint")
    Box(
        Modifier
            .size(48.dp)
            .clip(RoundedCornerShape(12.dp))
            .clickable(role = Role.Button, onClick = onClick)
            .semantics { stateDescription = if (open) "Open" else "Closed" },
        contentAlignment = Alignment.Center,
    ) {
        Box(Modifier.size(38.dp).clip(RoundedCornerShape(10.dp)).background(fill))
        Icon(Icons.AutoMirrored.Rounded.QueueMusic, contentDescription = "Up Next", tint = tint, modifier = Modifier.size(22.dp))
    }
}
