package com.pandyabhavik.hush.ui

import androidx.compose.foundation.gestures.detectVerticalDragGestures
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.DragHandle
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
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.zIndex
import kotlin.math.roundToInt

/** What plays next. Tap to jump, drag the handle to reorder, × to remove. */
@Composable
fun UpNext(modifier: Modifier = Modifier) {
    val model = LocalActions.current.model
    val player = model.player
    val upNext = player.upNext.mapNotNull { model.library.song(it) }
    val rowHeight = 60.dp
    val rowPx = with(LocalDensity.current) { rowHeight.toPx() }
    var dragging by remember { mutableStateOf<Int?>(null) }
    var dragOffset by remember { mutableFloatStateOf(0f) }

    Column(modifier) {
        Row(Modifier.fillMaxWidth().padding(start = Hush.sideMargin, end = 8.dp, top = 4.dp, bottom = 8.dp), verticalAlignment = Alignment.CenterVertically) {
            Text("Up Next", style = Hush.serif(29.sp), modifier = Modifier.weight(1f))
            if (upNext.isNotEmpty()) {
                Text("Clear", style = Hush.sans(15.sp, Hush.muted), modifier = Modifier.clickableQuiet { player.clearUpNext() }.padding(12.dp))
            }
        }
        if (upNext.isEmpty()) {
            Text(
                "Nothing after this song.", style = Hush.sans(15.sp, Hush.muted),
                modifier = Modifier.padding(horizontal = Hush.sideMargin, vertical = 12.dp),
            )
            return@Column
        }
        LazyColumn(state = rememberLazyListState(), modifier = Modifier.fillMaxSize()) {
            itemsIndexed(upNext, key = { i, s -> "$i-${s.id}" }) { index, song ->
                val isDragged = dragging == index
                Row(
                    Modifier
                        .fillMaxWidth()
                        .height(rowHeight)
                        .zIndex(if (isDragged) 1f else 0f)
                        .graphicsLayer {
                            translationY = if (isDragged) dragOffset else 0f
                            shadowElevation = if (isDragged) 8f else 0f
                        }
                        .alpha(if (isDragged) 0.9f else 1f)
                        .clickableQuiet { player.jumpToUpNext(index) }
                        .padding(start = Hush.sideMargin, end = 4.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Cover(song, Modifier.size(44.dp), 6.dp)
                    Column(Modifier.padding(start = 12.dp).weight(1f)) {
                        Text(song.title, style = Hush.sans(15.sp, weight = FontWeight.Medium), maxLines = 1, overflow = TextOverflow.Ellipsis)
                        Text(song.artist, style = Hush.sans(13.sp, Hush.muted), maxLines = 1, overflow = TextOverflow.Ellipsis)
                    }
                    PlainIconButton(Icons.Rounded.Close, "Remove", tint = Hush.muted, size = 20.dp) { player.removeFromUpNext(index) }
                    Box(
                        Modifier.size(44.dp).pointerInput(index, upNext.size) {
                            detectVerticalDragGestures(
                                onDragStart = { dragging = index; dragOffset = 0f },
                                onDragEnd = {
                                    val to = (index + (dragOffset / rowPx).roundToInt()).coerceIn(0, upNext.lastIndex)
                                    player.moveInUpNext(index, to)
                                    dragging = null
                                    dragOffset = 0f
                                },
                                onDragCancel = { dragging = null; dragOffset = 0f },
                            ) { change, amount ->
                                change.consume()
                                dragOffset += amount
                            }
                        },
                        contentAlignment = Alignment.Center,
                    ) {
                        Icon(Icons.Rounded.DragHandle, contentDescription = "Reorder", tint = Hush.muted)
                    }
                }
            }
            item { Spacer(Modifier.height(24.dp)) }
        }
    }
}
