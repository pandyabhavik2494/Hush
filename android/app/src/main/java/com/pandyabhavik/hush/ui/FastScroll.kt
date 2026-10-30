package com.pandyabhavik.hush.ui

import android.view.HapticFeedbackConstants
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.LinearOutSlowInEasing
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.grid.LazyGridState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.filter
import kotlinx.coroutines.launch
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/** The first item of each letter, for the A–Z index. */
fun <T> letterTargets(items: List<T>, letter: (T) -> String, offset: Int = 0): List<Pair<String, Int>> {
    val targets = ArrayList<Pair<String, Int>>()
    var last: String? = null
    items.forEachIndexed { i, item ->
        val l = letter(item)
        if (l != last) {
            targets += l to i + offset
            last = l
        }
    }
    return targets
}

/** Shown while the list moves (or a finger is on the strip), hidden 0.4 s after it stops. */
@Composable
private fun rememberShown(scrolling: Boolean, touching: Boolean): Boolean {
    var shown by remember { mutableStateOf(false) }
    LaunchedEffect(scrolling, touching) {
        if (scrolling || touching) shown = true
        else {
            delay(400)
            shown = false
        }
    }
    return shown
}

/** The fade: in 180 ms ease-out, out 180 ms ease-in-out. */
@Composable
private fun fade(shown: Boolean): Float =
    animateFloatAsState(
        if (shown) 1f else 0f,
        if (shown) tween(180, easing = LinearOutSlowInEasing) else tween(180, easing = FastOutSlowInEasing),
        label = "scrollerFade",
    ).value

/** The strip's backdrop: translucent dark glass in a capsule with a faint ink edge. */
private fun Modifier.glassCapsule(): Modifier =
    this.background(Hush.glass, CircleShape).border(0.5.dp, Hush.edge, CircleShape)

/**
 * A quiet A–Z strip on the right edge: touch or drag a letter to jump there. Letters are spread
 * evenly over the height; the touched letter grows in a small lit box. With [visible] false the
 * strip is transparent and lets touches through.
 */
@Composable
fun FastScrollIndex(
    targets: List<Pair<String, Int>>,
    modifier: Modifier = Modifier,
    visible: Boolean = true,
    onTouch: (Boolean) -> Unit = {},
    onJump: (Int) -> Unit,
) {
    if (targets.size < 2) return
    val haptics = LocalHapticFeedback.current
    val density = LocalDensity.current
    var height by remember { mutableIntStateOf(1) }
    var active by remember { mutableStateOf<String?>(null) }
    var dragging by remember { mutableStateOf(false) }
    val jump by rememberUpdatedState(onJump)
    val touch by rememberUpdatedState(onTouch)
    val alpha = fade(visible)

    fun pick(y: Float) {
        val usable = height.toFloat()
        val i = ((y / usable) * targets.size).toInt().coerceIn(0, targets.lastIndex)
        val (letter, index) = targets[i]
        if (letter != active) {
            active = letter
            haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)
            jump(index)
        }
    }

    // The active letter clears 0.55 s after the finger lifts.
    LaunchedEffect(dragging) {
        if (!dragging && active != null) {
            delay(550)
            active = null
        }
    }

    Box(
        modifier
            .width(32.dp)
            .fillMaxHeight()
            .graphicsLayer { this.alpha = alpha }
            .then(
                if (visible || dragging) Modifier.pointerInput(targets) {
                    awaitEachGesture {
                        val down = awaitFirstDown(requireUnconsumed = false)
                        dragging = true
                        touch(true)
                        down.consume()
                        pick(down.position.y - 6.dp.toPx())
                        while (true) {
                            val event = awaitPointerEvent()
                            val change = event.changes.firstOrNull { it.id == down.id } ?: break
                            if (!change.pressed) break
                            change.consume()
                            pick(change.position.y - 6.dp.toPx())
                        }
                        dragging = false
                        touch(false)
                    }
                } else Modifier,
            ),
        contentAlignment = Alignment.CenterEnd,
    ) {
        Column(
            Modifier
                .padding(end = 3.dp)
                .width(17.dp)
                .fillMaxHeight()
                .glassCapsule()
                .padding(vertical = 6.dp)
                .onSizeChanged { height = it.height.coerceAtLeast(1) },
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            val cell = with(density) { (height.toFloat() / targets.size).toDp() }
            val regular = (cell.value * 0.52f).coerceIn(9f, 12f)
            val big = min(15f, max(regular + 3f, cell.value * 0.76f))
            for ((letter, _) in targets) {
                val isActive = letter == active
                val grow by animateFloatAsState(
                    if (isActive) 1f else 0f,
                    if (dragging) tween(70, easing = LinearOutSlowInEasing)
                    else if (isActive) spring(0.72f, 987f) else spring(0.76f, 386f),
                    label = "letter",
                )
                Box(Modifier.fillMaxWidth().weight(1f), contentAlignment = Alignment.Center) {
                    if (grow > 0.01f) {
                        Box(
                            Modifier
                                .size(15.dp, min(26f, cell.value - 2f).coerceAtLeast(8f).dp)
                                .graphicsLayer { this.alpha = grow }
                                .background(Hush.accent.copy(alpha = 0.2f), RoundedCornerShape(5.dp))
                                .border(0.7.dp, Hush.accent.copy(alpha = 0.55f), RoundedCornerShape(5.dp)),
                        )
                    }
                    // Sized to the cell, not the reader's font scale, so the strip never overflows.
                    val sizeDp = regular + (big - regular) * grow
                    Text(
                        letter,
                        style = Hush.sans(
                            with(density) { sizeDp.dp.toSp() },
                            if (isActive) Hush.accent else Hush.muted,
                            FontWeight.SemiBold,
                        ),
                        maxLines = 1,
                        softWrap = false,
                    )
                }
            }
        }
    }
}

/**
 * For lists not in A–Z order: a thin track with a thumb the size of what is on screen.
 * Drag the thumb (or anywhere on the rail) to scrub; [onScrub] gets 0..1.
 */
@Composable
fun ScrollRail(
    progress: Float,
    visibleFraction: Float,
    modifier: Modifier = Modifier,
    visible: Boolean = true,
    onTouch: (Boolean) -> Unit = {},
    onScrub: (Float) -> Unit,
) {
    var height by remember { mutableIntStateOf(1) }
    var dragging by remember { mutableStateOf(false) }
    val scrub by rememberUpdatedState(onScrub)
    val touch by rememberUpdatedState(onTouch)
    val alpha = fade(visible)
    val density = LocalDensity.current
    val inset = with(density) { 10.dp.toPx() }
    val trackH = (height - inset * 2).coerceAtLeast(1f)
    val thumbH = max(with(density) { 38.dp.toPx() }, trackH * visibleFraction.coerceIn(0f, 1f)).coerceAtMost(trackH)
    val thumbY = inset + (trackH - thumbH) * progress.coerceIn(0f, 1f)
    val geometry by rememberUpdatedState(floatArrayOf(inset, trackH, thumbH))

    Box(
        modifier
            .width(32.dp)
            .fillMaxHeight()
            .graphicsLayer { this.alpha = alpha }
            .then(
                if (visible || dragging) Modifier.pointerInput(Unit) {
                    awaitEachGesture {
                        val down = awaitFirstDown(requireUnconsumed = false)
                        dragging = true
                        touch(true)
                        down.consume()
                        fun at(y: Float): Float {
                            val (top, track, thumb) = geometry
                            return ((y - top - thumb / 2) / (track - thumb).coerceAtLeast(1f)).coerceIn(0f, 1f)
                        }
                        scrub(at(down.position.y))
                        while (true) {
                            val event = awaitPointerEvent()
                            val change = event.changes.firstOrNull { it.id == down.id } ?: break
                            if (!change.pressed) break
                            change.consume()
                            scrub(at(change.position.y))
                        }
                        dragging = false
                        touch(false)
                    }
                } else Modifier,
            ),
        contentAlignment = Alignment.CenterEnd,
    ) {
        Box(
            Modifier
                .padding(end = 3.dp)
                .width(13.dp)
                .fillMaxHeight()
                .glassCapsule()
                .onSizeChanged { height = it.height.coerceAtLeast(1) },
        ) {
            Box(
                Modifier
                    .align(Alignment.TopCenter)
                    .padding(vertical = 10.dp)
                    .width(2.dp)
                    .fillMaxHeight()
                    .background(Hush.line.copy(alpha = 0.65f), CircleShape),
            )
            Box(
                Modifier
                    .align(Alignment.TopCenter)
                    .offset { IntOffset(0, thumbY.roundToInt()) }
                    .size(5.dp, with(density) { thumbH.toDp() })
                    .background(Hush.accent.copy(alpha = 0.9f), CircleShape),
            )
        }
    }
}

/** What the scroller needs to know about a lazy list or grid. */
private class ScrollFacts(
    val scrolling: () -> Boolean,
    val overflows: () -> Boolean,
    val progress: () -> Float,
    val visibleFraction: () -> Float,
    val firstIndex: () -> Int,
    val jump: suspend (Int) -> Unit,
    val total: () -> Int,
    val visibleCount: () -> Int,
)

/**
 * The fast-scroll overlay for a grid (iPhone FastScrollContainer): the A–Z index when [targets]
 * holds more than one letter, otherwise the scroll rail. It appears only while the list moves
 * and only when the list is taller than the screen. Also gives one light tick per row scrolled.
 */
@Composable
fun BoxScope.FastScroller(state: LazyGridState, targets: List<Pair<String, Int>>, top: Dp, bottom: Dp, columns: Int = 1) {
    val facts = remember(state) {
        ScrollFacts(
            scrolling = { state.isScrollInProgress },
            overflows = { state.canScrollForward || state.canScrollBackward },
            progress = {
                val info = state.layoutInfo
                val total = info.totalItemsCount
                val visible = info.visibleItemsInfo.size
                if (total <= visible) 0f else state.firstVisibleItemIndex.toFloat() / (total - visible).coerceAtLeast(1)
            },
            visibleFraction = {
                val info = state.layoutInfo
                if (info.totalItemsCount == 0) 1f else info.visibleItemsInfo.size.toFloat() / info.totalItemsCount
            },
            firstIndex = { state.firstVisibleItemIndex },
            jump = { state.scrollToItem(it) },
            total = { state.layoutInfo.totalItemsCount },
            visibleCount = { state.layoutInfo.visibleItemsInfo.size },
        )
    }
    Scroller(facts, targets, top, bottom, columns)
}

/** The same overlay for a list; ticks every [tickEvery] rows. */
@Composable
fun BoxScope.FastScroller(state: LazyListState, targets: List<Pair<String, Int>>, top: Dp, bottom: Dp, tickEvery: Int = 2) {
    val facts = remember(state) {
        ScrollFacts(
            scrolling = { state.isScrollInProgress },
            overflows = { state.canScrollForward || state.canScrollBackward },
            progress = {
                val info = state.layoutInfo
                val total = info.totalItemsCount
                val visible = info.visibleItemsInfo.size
                if (total <= visible) 0f else state.firstVisibleItemIndex.toFloat() / (total - visible).coerceAtLeast(1)
            },
            visibleFraction = {
                val info = state.layoutInfo
                if (info.totalItemsCount == 0) 1f else info.visibleItemsInfo.size.toFloat() / info.totalItemsCount
            },
            firstIndex = { state.firstVisibleItemIndex },
            jump = { state.scrollToItem(it) },
            total = { state.layoutInfo.totalItemsCount },
            visibleCount = { state.layoutInfo.visibleItemsInfo.size },
        )
    }
    Scroller(facts, targets, top, bottom, tickEvery)
}

@Composable
private fun BoxScope.Scroller(facts: ScrollFacts, targets: List<Pair<String, Int>>, top: Dp, bottom: Dp, rowSize: Int) {
    val scope = rememberCoroutineScope()
    val view = LocalView.current
    var touching by remember { mutableStateOf(false) }
    val scrolling by remember(facts) { derivedStateOf { facts.scrolling() } }
    val overflows by remember(facts) { derivedStateOf { facts.overflows() } }
    val shown = rememberShown(scrolling, touching) && overflows

    // One light tick per row while a finger drags or flings the list.
    LaunchedEffect(facts, rowSize) {
        snapshotFlow { facts.firstIndex() / rowSize.coerceAtLeast(1) }
            .distinctUntilChanged()
            .filter { facts.scrolling() }
            .collect { view.performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK) }
    }

    val place = Modifier
        .align(Alignment.TopEnd)
        .padding(top = top + 8.dp, bottom = bottom + 16.dp)
    if (targets.size > 1) {
        FastScrollIndex(targets, place, visible = shown, onTouch = { touching = it }) { index ->
            scope.launch { facts.jump(index) }
        }
    } else {
        val progress by remember(facts) { derivedStateOf { facts.progress() } }
        val fraction by remember(facts) { derivedStateOf { facts.visibleFraction() } }
        ScrollRail(progress, fraction, place, visible = shown, onTouch = { touching = it }) { f ->
            val last = (facts.total() - facts.visibleCount()).coerceAtLeast(0)
            scope.launch { facts.jump((f * last).roundToInt()) }
        }
    }
}
