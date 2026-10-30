package com.pandyabhavik.hush

import android.os.Handler
import android.os.HandlerThread
import android.os.SystemClock
import android.util.Log
import android.view.Choreographer
import android.view.FrameMetrics
import android.view.Window
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.swipeDown
import androidx.compose.ui.test.swipeUp
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

/**
 * A quick check that Hush stays responsive: scrolling the long album grid and the songs list must
 * not stall the main thread, and opening a page, Now Playing and a video must be quick. The limits
 * are generous (the CI emulator draws in software); the numbers are logged (tag HushPerf) and saved
 * next to the screenshots as perf-<size>.txt so slow-downs can be compared between builds.
 */
@RunWith(AndroidJUnit4::class)
class PerfTest : HushTestBase() {

    /** Watches the main thread: the gaps between frames, and how long each frame took to draw. */
    private inner class FrameWatch {
        private val gaps = ArrayList<Long>()
        private val draws = ArrayList<Long>()
        @Volatile private var running = false
        private var last = 0L
        private val thread = HandlerThread("frame-metrics").apply { start() }
        private lateinit var window: Window

        private val callback = object : Choreographer.FrameCallback {
            override fun doFrame(frameTimeNanos: Long) {
                if (!running) return
                if (last != 0L) synchronized(gaps) { gaps += (frameTimeNanos - last) / 1_000_000 }
                last = frameTimeNanos
                Choreographer.getInstance().postFrameCallback(this)
            }
        }
        private val metrics = Window.OnFrameMetricsAvailableListener { _, frame, _ ->
            synchronized(draws) { draws += frame.getMetric(FrameMetrics.TOTAL_DURATION) / 1_000_000 }
        }

        fun start() {
            window = compose.activity.window
            running = true
            last = 0L
            compose.runOnUiThread {
                window.addOnFrameMetricsAvailableListener(metrics, Handler(thread.looper))
                Choreographer.getInstance().postFrameCallback(callback)
            }
        }

        /** Stops and returns a summary; the longest gap between frames is what a person would feel as a stall. */
        fun stop(): Stats {
            running = false
            compose.runOnUiThread { runCatching { window.removeOnFrameMetricsAvailableListener(metrics) } }
            thread.quitSafely()
            val g = synchronized(gaps) { gaps.sorted() }
            val d = synchronized(draws) { draws.sorted() }
            return Stats(
                frames = g.size,
                maxGapMs = g.lastOrNull() ?: 0,
                p90GapMs = g.getOrNull((g.size * 0.9).toInt().coerceAtMost(g.size - 1)) ?: 0,
                slowFrames = g.count { it > 100 },
                drawn = d.size,
                p90DrawMs = d.getOrNull((d.size * 0.9).toInt().coerceAtMost(d.size - 1)) ?: 0,
                maxDrawMs = d.lastOrNull() ?: 0,
            )
        }
    }

    private data class Stats(
        val frames: Int, val maxGapMs: Long, val p90GapMs: Long, val slowFrames: Int,
        val drawn: Int, val p90DrawMs: Long, val maxDrawMs: Long,
    )

    private val report = StringBuilder()

    private fun record(line: String) {
        Log.i("HushPerf", "$sizeName $line")
        report.append(line).append('\n')
    }

    private fun save(name: String) {
        runCatching {
            val dir = compose.activity.getExternalFilesDir(null) ?: return
            val file = File(dir, "perf-$sizeName-$name.txt")
            file.writeText(report.toString())
            shell("mkdir -p $SCREENS")
            shell("cp ${file.absolutePath} $SCREENS/")
        }
    }

    private fun scroll(times: Int, up: Boolean) {
        repeat(times) {
            compose.onRoot().performTouchInput {
                if (up) swipeUp(startY = height * 0.75f, endY = height * 0.25f, durationMillis = 150)
                else swipeDown(startY = height * 0.25f, endY = height * 0.75f, durationMillis = 150)
            }
            compose.waitForIdle()
        }
    }

    private fun measureScroll(label: String, firstItem: SemanticsMatcher): Stats {
        val watch = FrameWatch()
        val start = SystemClock.uptimeMillis()
        watch.start()
        scroll(6, up = true)
        val movedAway = !isDisplayed(firstItem)
        scroll(8, up = false)
        val stats = watch.stop()
        val took = SystemClock.uptimeMillis() - start
        record("$label: ${took} ms for 14 flings; $stats")
        assertTrue("$label: the list should have scrolled away from its first item", movedAway)
        waitDisplayed(firstItem)
        assertTrue("$label: took $took ms for 14 flings (limit $SCROLL_LIMIT_MS)", took < SCROLL_LIMIT_MS)
        assertTrue("$label: the main thread stalled for ${stats.maxGapMs} ms (limit $STALL_LIMIT_MS)", stats.maxGapMs < STALL_LIMIT_MS)
        return stats
    }

    private fun timed(label: String, limitMs: Long, action: () -> Unit, done: () -> Boolean) {
        val start = SystemClock.uptimeMillis()
        action()
        waitUntil(label, limitMs * 2) { done() }
        val took = SystemClock.uptimeMillis() - start
        record("$label: $took ms")
        assertTrue("$label took $took ms (limit $limitMs)", took < limitMs)
    }

    @Test
    fun scrollingAndOpeningStayQuick() {
        try {
            measureEverything()
        } finally {
            save("summary")
        }
    }

    private fun measureEverything() {
        assertTrue(
            "The test media should have 40+ albums (android/ci/make-test-media.sh); found ${model.library.albums.size}",
            model.library.albums.size >= 40,
        )
        record("library: ${model.library.songs.size} songs, ${model.library.albums.size} albums; wide=$wide")

        openSection("Albums")
        showTitles()
        waitDisplayed(button("Guest Album"))
        measureScroll("albums grid", button("Guest Album"))
        shot("perf-01-albums")

        openSection("Songs")
        waitDisplayed(songRow("Guest Song A"))
        measureScroll("songs list", songRow("Guest Song A"))

        openSection("Artists")
        waitDisplayed(button("Guest Singer"))
        record("artists shown")

        // Opening things.
        openSection("Albums")
        timed("open an album page", 3_000, { node(button("Hush Test Album")).performClick() }) {
            isDisplayed(button("Shuffle"))
        }
        timed("play from the album page", 5_000, { tap(button("Play")) }) { model.player.isPlaying }
        timed("open Now Playing", 3_000, { node(hasTestTag("miniPlayer")).performClick() }) {
            exists(desc("Repeat")) && isDisplayed(desc("Next"))
        }
        closeNowPlayingWithButton()
        tap(desc("Back"))

        useTestVideosFolder()
        openSection("Videos")
        waitDisplayed(button("Hush Test Video"))
        timed("open a video", 3_000, { node(button("Hush Test Video")).performClick() }) {
            model.video != null && (exists(desc("Pause")) || exists(desc("Close video")))
        }
    }

    companion object {
        /** No single main-thread stall this long while scrolling (generous: the emulator draws in software). */
        const val STALL_LIMIT_MS = 1_500L
        const val SCROLL_LIMIT_MS = 45_000L
    }
}
