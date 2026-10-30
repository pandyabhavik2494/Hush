package com.pandyabhavik.hush.ui

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.snap
import androidx.compose.animation.core.spring
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectVerticalDragGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.PlaylistPlay
import androidx.compose.material.icons.rounded.Add
import androidx.compose.material.icons.rounded.AddCircle
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.DragHandle
import androidx.compose.material.icons.rounded.RemoveCircleOutline
import androidx.compose.material.icons.rounded.Search
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.zIndex
import com.pandyabhavik.hush.data.LibrarySearch
import com.pandyabhavik.hush.data.Song
import kotlin.math.roundToInt

/** The Mac's palette for the Up Next panel. */
private object PanelInk {
    val panel = Color(0xFF141311)
    val muted = Color(0xFF9C9A95)
    val gold = Hush.gold
}

/**
 * Up Next as on iPhone: the song playing now, then what comes after it. Tap a song to jump to it,
 * the minus to remove it, and drag the handle to move it.
 */
@Composable
fun UpNext(modifier: Modifier = Modifier) {
    val model = LocalActions.current.model
    val player = model.player
    val current = model.library.song(player.currentId)
    val upNext = rememberUpNext()
    QueueList(
        upNext, rowHeight = 64.dp, modifier = modifier,
        header = {
            item(key = "nowHeader") { SectionTitle("Now Playing", Modifier.padding(start = 20.dp, top = 8.dp, bottom = 6.dp)) }
            if (current != null) {
                item(key = "now") {
                    QueueRow(
                        current, isCurrent = true, playing = player.isPlaying,
                        modifier = Modifier.padding(horizontal = 20.dp).height(64.dp),
                    )
                }
            }
            item(key = "upNextHeader") {
                Row(
                    Modifier.fillMaxWidth().padding(start = 20.dp, end = 8.dp, top = 14.dp, bottom = 4.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Column(Modifier.weight(1f)) {
                        SectionTitle("Up Next")
                        if (upNext.isNotEmpty()) {
                            Text(
                                if (upNext.size == 1) "1 song" else "${upNext.size} songs",
                                style = Hush.sans(11.sp, Hush.muted, FontWeight.Medium),
                            )
                        }
                    }
                    if (upNext.isNotEmpty()) TextAction("Clear") { player.clearUpNext() }
                }
            }
            if (upNext.isEmpty()) {
                item(key = "empty") {
                    Column(
                        Modifier.fillMaxWidth().padding(horizontal = 32.dp, vertical = 28.dp),
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        Icon(
                            Icons.AutoMirrored.Rounded.PlaylistPlay, contentDescription = null,
                            tint = Hush.ink.copy(alpha = 0.85f), modifier = Modifier.size(30.dp),
                        )
                        Text("Nothing up next", style = Hush.serif(17.sp))
                        Text(
                            "Tap Add Songs, or press and hold any song, album or playlist and choose Play Next or Add to Queue.",
                            style = Hush.sans(13.sp, Hush.muted), textAlign = TextAlign.Center,
                        )
                    }
                }
            }
        },
    ) { offset, song, handle ->
        Row(
            Modifier
                .fillMaxSize()
                .clickable { player.jumpToUpNext(offset) }
                .padding(start = 20.dp, end = 0.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            QueueRow(song, isCurrent = false, playing = false, modifier = Modifier.weight(1f))
            PlainIconButton(Icons.Rounded.RemoveCircleOutline, "Remove", tint = Hush.muted, size = 22.dp) { player.removeFromUpNext(offset) }
            Box(handle.size(48.dp), contentAlignment = Alignment.Center) {
                Icon(Icons.Rounded.DragHandle, contentDescription = "Reorder", tint = Hush.muted)
            }
        }
        Box(
            Modifier.align(Alignment.BottomStart).fillMaxWidth().padding(start = 78.dp).height(0.5.dp).background(Hush.line.copy(alpha = 0.6f)),
        )
    }
}

@Composable
private fun SectionTitle(text: String, modifier: Modifier = Modifier) {
    Text(text, style = Hush.serif(15.sp).copy(fontWeight = FontWeight.SemiBold), modifier = modifier)
}

/**
 * A song in the queue: cover, title, "Artist · Album". The current song gets the now-playing badge.
 */
@Composable
private fun QueueRow(
    song: Song, isCurrent: Boolean, playing: Boolean, modifier: Modifier = Modifier,
    art: Dp = 46.dp, artRadius: Dp = 8.dp, titleSize: Float = 14f, subSize: Float = 12f,
    titleColor: Color = Hush.ink, subColor: Color = Hush.muted,
) {
    Row(modifier, verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.size(art)) {
            Cover(song, Modifier.fillMaxSize(), artRadius)
            if (isCurrent) NowPlayingBadge(playing, 17.dp, Modifier.align(Alignment.BottomEnd).offset(3.dp, 3.dp))
        }
        Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Text(song.title, style = Hush.sans(titleSize.sp, titleColor, FontWeight.SemiBold), maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text("${song.artist} · ${song.album}", style = Hush.sans(subSize.sp, subColor), maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
    }
}

/** A song coming up and where it really is in the queue (counted from the song after the current one). */
private class QueueEntry(val offset: Int, val song: Song)

/**
 * The songs coming up. A queued song no longer in the library is left out of the list but keeps
 * its place in the count, so jump, remove and move always act on the song that was tapped.
 */
@Composable
private fun rememberUpNext(): List<QueueEntry> {
    val model = LocalActions.current.model
    val player = model.player
    val queue = player.queue
    val index = player.currentIndex
    val library = model.library
    return remember(queue, index, library) {
        queue.drop(index + 1).withIndex().mapNotNull { (offset, id) -> library.song(id)?.let { QueueEntry(offset, it) } }
    }
}

/**
 * The upcoming songs, reorderable by dragging a handle: the dragged row follows the finger and the
 * others slide out of its way. [header] items come first. [row] gets the song's queue offset.
 */
@Composable
private fun QueueList(
    upNext: List<QueueEntry>,
    rowHeight: Dp,
    modifier: Modifier = Modifier,
    header: LazyListScope.() -> Unit = {},
    row: @Composable BoxScope.(offset: Int, song: Song, handle: Modifier) -> Unit,
) {
    val player = LocalActions.current.model.player
    val rowPx = with(LocalDensity.current) { rowHeight.toPx() }
    // Shown order: the queue, or after a drop the new order until the player reports it, so the
    // dropped row stays where it was put instead of jumping back for a moment.
    var shown by remember(upNext) { mutableStateOf(upNext) }
    val entries by rememberUpdatedState(shown)
    var dragging by remember { mutableStateOf<Int?>(null) }
    var dragOffset by remember { mutableFloatStateOf(0f) }
    val target = dragging?.let { (it + (dragOffset / rowPx).roundToInt()).coerceIn(0, shown.lastIndex.coerceAtLeast(0)) }

    LazyColumn(modifier) {
        header()
        itemsIndexed(shown, key = { i, e -> "q$i-${e.song.id}" }) { index, entry ->
            val from = dragging
            val isDragged = from == index
            val makeRoom = when {
                from == null || target == null || isDragged -> 0f
                from < target && index in (from + 1)..target -> -rowPx
                from > target && index in target until from -> rowPx
                else -> 0f
            }
            // Rows glide aside while dragging; on the drop they settle at once (the list reorders
            // in the same frame), or they would slide in from where they were.
            val shift by animateFloatAsState(
                makeRoom,
                if (from == null) snap<Float>() else spring<Float>(dampingRatio = 0.85f, stiffness = 632f),
                label = "makeRoom",
            )
            // Keyed on the list too: `shown` is a new state for each queue, and the drop must write the current one.
            val handle = Modifier.pointerInput(index, upNext) {
                fun reset() {
                    if (dragging == index || dragging == null) {
                        dragging = null
                        dragOffset = 0f
                    }
                }
                try {
                    detectVerticalDragGestures(
                        onDragStart = { dragging = index; dragOffset = 0f },
                        onDragEnd = {
                            val list = entries
                            val to = (index + (dragOffset / rowPx).roundToInt()).coerceIn(0, list.lastIndex.coerceAtLeast(0))
                            if (index in list.indices && to != index) {
                                val moved = list[index]
                                val toOffset = list[to].offset
                                shown = list.toMutableList().apply { add(to, removeAt(index)) }
                                player.moveInUpNext(moved.offset, toOffset)
                            }
                            dragging = null
                            dragOffset = 0f
                        },
                        onDragCancel = { reset() },
                    ) { change, amount ->
                        change.consume()
                        dragOffset += amount
                    }
                } finally {
                    // The gesture was cut off (the row left the list, or the queue moved on).
                    reset()
                }
            }
            Box(
                Modifier
                    .fillMaxWidth()
                    .height(rowHeight)
                    .zIndex(if (isDragged) 1f else 0f)
                    .graphicsLayer {
                        translationY = if (isDragged) dragOffset else shift
                        shadowElevation = if (isDragged) 16f else 0f
                        alpha = if (isDragged) 0.95f else 1f
                    }
                    .background(if (isDragged) Color(0xFF262624) else Color.Transparent),
            ) {
                row(this, entry.offset, entry.song, handle)
            }
        }
        item(key = "bottom") { Spacer(Modifier.height(24.dp)) }
    }
}

/** Find songs and put them next or at the end of the queue (the iPhone's Add Songs sheet). */
@Composable
internal fun AddSongs(
    modifier: Modifier = Modifier, ink: Color = Hush.ink, muted: Color = Hush.muted, accent: Color = Hush.ink,
    field: Color = Color(0xFF2A2A28),
) {
    val model = LocalActions.current.model
    val player = model.player
    var text by rememberSaveable { mutableStateOf("") }
    val query = LibrarySearch.query(text)
    val library = model.library
    val found = remember(query, library) {
        if (query.isEmpty()) emptyList() else library.songs.filter { it.searchKey.contains(query) }.take(200)
    }
    val focus = remember { FocusRequester() }
    LaunchedEffect(Unit) { runCatching { focus.requestFocus() } }
    Column(modifier) {
        Row(
            Modifier
                .padding(horizontal = 16.dp, vertical = 6.dp)
                .fillMaxWidth()
                .height(48.dp)
                .clip(RoundedCornerShape(12.dp))
                .background(field)
                .padding(horizontal = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(Icons.Rounded.Search, contentDescription = null, tint = muted, modifier = Modifier.size(20.dp))
            Spacer(Modifier.width(8.dp))
            Box(Modifier.weight(1f)) {
                if (text.isEmpty()) Text("Find a song, album or artist", style = Hush.sans(16.sp, muted), maxLines = 1)
                BasicTextField(
                    text, { text = it }, singleLine = true,
                    textStyle = Hush.sans(16.sp, ink),
                    cursorBrush = SolidColor(ink),
                    modifier = Modifier.fillMaxWidth().focusRequester(focus),
                )
            }
        }
        // Results stay above the keyboard.
        LazyColumn(Modifier.fillMaxWidth().weight(1f).imePadding()) {
            items(found, key = { it.id }) { song ->
                Row(
                    Modifier.fillMaxWidth().height(62.dp).padding(start = 16.dp, end = 4.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    QueueRow(song, isCurrent = false, playing = false, modifier = Modifier.weight(1f), titleColor = ink, subColor = muted)
                    PlainIconButton(Icons.AutoMirrored.Rounded.PlaylistPlay, "Play Next", tint = accent, size = 24.dp) { player.playNext(listOf(song)) }
                    PlainIconButton(Icons.Rounded.AddCircle, "Add to Queue", tint = accent, size = 24.dp) { player.addToQueue(listOf(song)) }
                }
            }
            item { Spacer(Modifier.height(24.dp)) }
        }
    }
}

/**
 * The Mac's Up Next panel (360 dp at the right edge): a heading, the song playing now on a gold
 * card, then the queue. [onColor] is the version laid over Now Playing's cover colours.
 */
@Composable
fun UpNextPanel(modifier: Modifier = Modifier, onClose: () -> Unit, onColor: Boolean = false) {
    val model = LocalActions.current.model
    val player = model.player
    val current = model.library.song(player.currentId)
    val upNext = rememberUpNext()
    var adding by rememberSaveable { mutableStateOf(false) }
    Row(
        modifier
            .background(if (onColor) Color.Black.copy(alpha = 0.28f) else PanelInk.panel.copy(alpha = 0.96f))
            .blockTouches(),
    ) {
        Box(Modifier.width(1.dp).fillMaxHeight().background(if (onColor) Color.White.copy(alpha = 0.10f) else Hush.line))
        Column(
            Modifier
                .weight(1f)
                .fillMaxHeight()
                .then(if (onColor) Modifier.statusBarsPadding().navigationBarsPadding() else Modifier),
        ) {
            Row(
                Modifier.fillMaxWidth().padding(start = 18.dp, end = 6.dp, top = if (onColor) 8.dp else 12.dp, bottom = 6.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(if (adding) "Add Songs" else "Up Next", style = Hush.serif(22.sp), modifier = Modifier.weight(1f))
                if (adding) {
                    TextAction("Done", color = PanelInk.gold) { adding = false }
                } else {
                    PlainIconButton(Icons.Rounded.Add, "Add Songs", tint = Hush.ink, size = 24.dp) { adding = true }
                }
                PlainIconButton(Icons.Rounded.Close, "Close Up Next", tint = PanelInk.muted, size = 22.dp, onClick = onClose)
            }
            if (adding) {
                AddSongs(Modifier.weight(1f), muted = PanelInk.muted, accent = PanelInk.gold, field = Hush.ink.copy(alpha = 0.07f))
                return@Column
            }
            QueueList(
                upNext, rowHeight = 56.dp, modifier = Modifier.weight(1f),
                header = {
                    if (current != null) {
                        item(key = "now") {
                            Row(
                                Modifier
                                    .padding(horizontal = 14.dp, vertical = 4.dp)
                                    .fillMaxWidth()
                                    .clip(RoundedCornerShape(12.dp))
                                    .background(PanelInk.gold.copy(alpha = 0.10f))
                                    .padding(10.dp),
                                verticalAlignment = Alignment.CenterVertically,
                            ) {
                                Cover(current, Modifier.size(44.dp), 6.dp)
                                Spacer(Modifier.width(12.dp))
                                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                                    Text(current.title, style = Hush.sans(13.sp, Hush.ink, FontWeight.SemiBold), maxLines = 1, overflow = TextOverflow.Ellipsis)
                                    Text(current.artist, style = Hush.sans(11.5.sp, PanelInk.muted), maxLines = 1, overflow = TextOverflow.Ellipsis)
                                }
                                Spacer(Modifier.width(6.dp))
                                Equalizer(player.isPlaying, Modifier.size(width = 12.dp, height = 12.dp), color = PanelInk.gold)
                            }
                        }
                    }
                    item(key = "listHeader") {
                        Row(
                            Modifier.fillMaxWidth().padding(start = 18.dp, end = 6.dp, top = 10.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Text(
                                if (upNext.isEmpty()) "NOTHING QUEUED" else "${upNext.size} TO COME",
                                style = Hush.sans(10.5.sp, PanelInk.muted, FontWeight.Bold).copy(letterSpacing = 0.85.sp),
                                modifier = Modifier.weight(1f),
                            )
                            if (upNext.isNotEmpty()) TextAction("Clear", color = PanelInk.gold) { player.clearUpNext() }
                        }
                    }
                    if (upNext.isEmpty()) {
                        item(key = "empty") {
                            Text(
                                "Press and hold any song and choose Play Next or Add to Queue.",
                                style = Hush.sans(12.sp, PanelInk.muted),
                                modifier = Modifier.padding(horizontal = 18.dp, vertical = 4.dp),
                            )
                        }
                    }
                },
            ) { offset, song, handle ->
                Row(
                    Modifier
                        .fillMaxSize()
                        .padding(horizontal = 6.dp)
                        .clip(RoundedCornerShape(8.dp))
                        .clickable { player.jumpToUpNext(offset) }
                        .padding(start = 8.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    QueueRow(
                        song, isCurrent = false, playing = false, modifier = Modifier.weight(1f),
                        art = 36.dp, artRadius = 5.dp, titleSize = 13f, subSize = 11.5f, subColor = PanelInk.muted,
                    )
                    PlainIconButton(Icons.Rounded.Close, "Remove", tint = PanelInk.muted, size = 16.dp) { player.removeFromUpNext(offset) }
                    Box(handle.size(48.dp), contentAlignment = Alignment.Center) {
                        Icon(Icons.Rounded.DragHandle, contentDescription = "Reorder", tint = PanelInk.muted, modifier = Modifier.size(20.dp))
                    }
                }
            }
        }
    }
}
