package com.pandyabhavik.hush.ui

import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.gestures.detectVerticalDragGestures
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

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

/** A quiet A–Z strip on the right edge: touch or drag a letter to jump there. */
@Composable
fun FastScrollIndex(targets: List<Pair<String, Int>>, modifier: Modifier = Modifier, onJump: (Int) -> Unit) {
    if (targets.size < 2) return
    val haptics = LocalHapticFeedback.current
    var height by remember { mutableIntStateOf(1) }
    var active by remember { mutableStateOf<String?>(null) }
    fun pick(y: Float) {
        val i = ((y / height) * targets.size).toInt().coerceIn(0, targets.lastIndex)
        val (letter, index) = targets[i]
        if (letter != active) {
            active = letter
            haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)
            onJump(index)
        }
    }
    Column(
        modifier
            .width(32.dp)
            .onSizeChanged { height = it.height.coerceAtLeast(1) }
            .pointerInput(targets) {
                detectTapGestures(onPress = { pick(it.y); tryAwaitRelease(); active = null })
            }
            .pointerInput(targets) {
                detectVerticalDragGestures(
                    onDragStart = { pick(it.y) },
                    onDragEnd = { active = null },
                    onDragCancel = { active = null },
                ) { change, _ -> pick(change.position.y) }
            }
            .padding(vertical = 4.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        for ((letter, _) in targets) {
            Text(
                letter,
                style = Hush.sans(12.sp, if (letter == active) Hush.ink else Hush.muted, FontWeight.SemiBold),
                modifier = Modifier.padding(vertical = 1.5.dp),
            )
        }
    }
}
