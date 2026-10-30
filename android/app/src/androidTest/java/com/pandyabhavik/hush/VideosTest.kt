package com.pandyabhavik.hush

import android.content.pm.ActivityInfo
import android.os.SystemClock
import android.util.Log
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.test.click
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollToIndex
import androidx.compose.ui.test.performTouchInput
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Videos. The owner reports that on the unfolded screen a tap on a video often doesn't open it,
 * so opening is tested strictly: every single tap, by the test framework and through the real
 * input system, on the picture and on the title, must open the video within a couple of seconds.
 */
@RunWith(AndroidJUnit4::class)
class VideosTest : HushTestBase() {

    private val videos = listOf("Hush Test Video", "Second Video")

    private fun showVideoControls() {
        if (!exists(desc("Close video"))) {
            compose.onRoot().performTouchInput { click(Offset(width * 0.1f, height * 0.5f)) }
            waitUntil("the video controls", 3_000) { exists(desc("Close video")) }
        }
    }

    private fun waitVideoOpen(title: String, what: String) {
        val start = SystemClock.uptimeMillis()
        waitUntil(what, 3_000) { model.video?.title == title }
        Log.i(TAG, "$what: opened in ${SystemClock.uptimeMillis() - start} ms")
        waitUntil("the video player for '$title'", 5_000) { exists(desc("Close video")) || exists(desc("Pause")) || exists(desc("Play")) }
    }

    private fun closeVideo(useButton: Boolean) {
        if (useButton) {
            showVideoControls()
            tap(desc("Close video"))
        } else {
            pressBack()
        }
        waitUntil("the video to close") { model.video == null }
        assertEquals(ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED, compose.activity.requestedOrientation)
        videos.forEach { waitDisplayed(button(it)) }
        // The system bars come back after a video; let the layout settle before the next real tap.
        Thread.sleep(700)
        compose.waitForIdle()
    }

    @Test
    fun everyTapOnAVideoTileOpensIt() {
        useTestVideosFolder()
        openSection("Videos")
        videos.forEach { waitDisplayed(button(it), 10_000) }
        shot("videos-01-grid")

        val ways = listOf("framework tap", "real tap on the picture", "real tap on the title")
        var round = 0
        repeat(2) {
            for (title in videos) {
                for (way in ways) {
                    round++
                    val tile = button(title)
                    when (way) {
                        "framework tap" -> tap(tile)
                        // The picture is the top 16:9 of the tile; the title is under it.
                        "real tap on the picture" -> realTap(tile, 0.5f, 0.3f)
                        else -> realTap(tile, 0.3f, 0.85f)
                    }
                    waitVideoOpen(title, "tap #$round ($way) on '$title' to open it")
                    if (round == 1) shot("videos-02-first-open")
                    assertTrue(compose.onAllNodes(hasText("can't play", substring = true)).fetchSemanticsNodes().isEmpty())
                    closeVideo(useButton = round % 2 == 0)
                }
            }
        }
    }

    /** The Videos tab (cover screen) or sidebar item (inner screen), tapped for real, every time. */
    @Test
    fun theVideosSectionOpensEveryTime() {
        useTestVideosFolder()
        repeat(5) { i ->
            openSection(if (i % 2 == 0) "Albums" else "Songs")
            if (!wide) {
                compose.onNode(hasTestTag("tabs")).performScrollToIndex(4)
                compose.waitForIdle()
            }
            realTap(button("Videos"))
            waitUntil("tap #${i + 1} on Videos to show the videos", 3_000) { isDisplayed(button("Hush Test Video")) }
        }
        // Straight into a video from there.
        realTap(button("Second Video"), 0.5f, 0.3f)
        waitVideoOpen("Second Video", "a real tap on Second Video")
        closeVideo(useButton = true)
    }

    @Test
    fun videoControls() {
        val startedWide = wide
        useTestVideosFolder()
        openSection("Videos")
        tap(button("Hush Test Video"))
        waitVideoOpen("Hush Test Video", "the video to open")

        // Pause and play.
        showVideoControls()
        tap(desc("Pause"))
        waitUntil("the video to pause") { exists(desc("Play")) }
        shot("videos-10-paused")
        // Paused, the controls stay; a tap hides them and another shows them.
        compose.onRoot().performTouchInput { click(Offset(width * 0.1f, height * 0.5f)) }
        waitGone(desc("Close video"))
        compose.onRoot().performTouchInput { click(Offset(width * 0.1f, height * 0.5f)) }
        waitDisplayed(desc("Close video"))
        tap(desc("Play"))
        waitUntil("the video to play") { exists(desc("Pause")) || !exists(desc("Close video")) }

        // Skipping: back 10 s at the start is fine; ahead past the end shows Play Again.
        showVideoControls()
        tap(desc("Back 10 seconds"))
        repeat(3) {
            showVideoControls()
            if (exists(desc("Play again"))) return@repeat
            tap(desc("Ahead 10 seconds"))
        }
        waitUntil("the end of the video", 10_000) { exists(desc("Play again")) }
        shot("videos-11-ended")
        tap(desc("Play again"))
        waitUntil("the video to play again") { exists(desc("Pause")) || !exists(desc("Close video")) }

        // Picture modes go round in turn.
        for (label in listOf("Fill", "Stretch", "16:9", "4:3", "Original Size", "Best Fit")) {
            showVideoControls()
            node(hasContentDescription("Picture:", substring = true)).performClick()
            waitUntil("picture mode $label", 3_000) { exists(desc("Picture: $label")) }
        }

        // Turning, then closing puts the screen back to normal.
        showVideoControls()
        tap(hasContentDescription("Turn:", substring = true))
        waitUntil("landscape", 3_000) { compose.activity.requestedOrientation == ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE }
        Thread.sleep(1500)
        shot("videos-12-landscape")
        closeVideo(useButton = false)
        // Turned back to the phone's own way (the cover screen in landscape would be the wide layout).
        waitUntil("the screen to turn back", 10_000) { wide == startedWide }
        compose.waitForIdle()

        // Music that was playing pauses for a video.
        playFromSongs("Hush Test One")
        openSection("Videos")
        tap(button("Second Video"))
        waitVideoOpen("Second Video", "the second video to open")
        waitUntil("the music to pause") { !model.player.isPlaying }
        closeVideo(useButton = true)
    }
}
