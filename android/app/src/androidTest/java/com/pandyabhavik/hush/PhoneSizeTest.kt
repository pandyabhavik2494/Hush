package com.pandyabhavik.hush

import android.util.Log
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.test.performScrollToNode
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.After
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Every screen size the app runs at (the Fold's cover and inner screens, and a regular phone such
 * as the S25 Edge): the player's controls sit fully on screen, upright and turned sideways, and
 * a screenshot of each main screen is kept to look over.
 */
@RunWith(AndroidJUnit4::class)
class PhoneSizeTest : HushTestBase() {
    private var originalSize: String? = null
    private var physicalSize: String? = null

    @Before
    fun rememberScreen() {
        val sizes = shell("wm size")
        originalSize = Regex("Override size: (\\d+x\\d+)").find(sizes)?.groupValues?.get(1)
        physicalSize = Regex("Physical size: (\\d+x\\d+)").find(sizes)?.groupValues?.get(1)
    }

    @After
    fun restoreScreen() {
        shell(if (originalSize != null) "wm size $originalSize" else "wm size reset")
        runCatching { compose.waitUntil(10_000) { !landscape() } }
    }

    private fun landscape() = compose.activity.resources.configuration.let { it.screenWidthDp > it.screenHeightDp }

    /** Turns the phone sideways by swapping the display's width and height (density stays). */
    private fun turnSideways() {
        val (w, h) = (originalSize ?: physicalSize ?: return).split("x").map { it.toInt() }
        shell("wm size ${h}x$w")
        waitUntil("the screen to turn sideways", 15_000) { landscape() }
        idle()
        Thread.sleep(800)
        idle()
    }

    /** The node's bounds lie fully inside the window, not cut off at any edge. */
    private fun assertFullyOnScreen(what: String, bounds: Rect) {
        val root = compose.onRoot().fetchSemanticsNode().boundsInWindow
        val inside = bounds.left >= root.left - 1f && bounds.top >= root.top - 1f &&
            bounds.right <= root.right + 1f && bounds.bottom <= root.bottom + 1f && bounds.width > 0f && bounds.height > 0f
        if (!inside) rawShot("FAILED-$what-cut-off")
        assertTrue("$what is cut off: $bounds, screen $root", inside)
    }

    private fun assertPlayerControlsOnScreen() {
        for (control in listOf("Close", "Shuffle", "Up Next", "Play On", "Repeat", "Previous", "Next")) {
            assertFullyOnScreen(control, node(desc(control)).fetchSemanticsNode().boundsInWindow)
        }
        assertFullyOnScreen("Play/Pause", playerPlayPause().fetchSemanticsNode().boundsInWindow)
        assertFullyOnScreen("Position", node(desc("Position")).fetchSemanticsNode().boundsInWindow)
    }

    @Test
    fun theLibraryAndPagesAtThisSize() {
        val c = compose.activity.resources.configuration
        Log.i(TAG, "Screen ${c.screenWidthDp} x ${c.screenHeightDp} dp, font scale ${c.fontScale}")
        for (section in listOf("Albums", "Songs", "Artists", "Playlists")) {
            openSection(section)
            shot("size-01-${section.lowercase()}")
        }
        openAlbumOf("Hush Test Two")
        assertFullyOnScreen("Album Play", node(button("Play")).fetchSemanticsNode().boundsInWindow)
        assertFullyOnScreen("Album Shuffle", node(button("Shuffle")).fetchSemanticsNode().boundsInWindow)
        shot("size-02-album")
    }

    @Test
    fun nowPlayingFitsUprightAndSideways() {
        playFromSongs("Hush Test Two")
        shot("size-10-library-playing")
        openNowPlaying()
        assertPlayerControlsOnScreen()
        shot("size-11-now-playing")

        tap(desc("Play On"))
        waitDisplayed(text("This Phone"))
        shot("size-12-play-on")
        pressBack()
        waitGone(text("This Phone"))

        turnSideways()
        assertTrue("Now Playing still open", model.playerOpen)
        waitDisplayed(desc("Repeat"))
        assertPlayerControlsOnScreen()
        shot("size-20-now-playing-sideways")

        // Up Next beside the player, the controls still usable.
        tap(desc("Up Next"))
        idle()
        Thread.sleep(500)
        shot("size-21-up-next-sideways")
        tap(desc("Up Next"))
        idle()

        tap(desc("Play On"))
        waitDisplayed(text("This Phone"))
        val noSpeakers = text("No speakers found. Check that the phone is on the same Wi-Fi as your Sonos.")
        waitUntil("the speaker search to end", 15_000) { exists(noSpeakers) }
        compose.onNode(hasTestTag("playOnList")).performScrollToNode(noSpeakers)
        waitDisplayed(noSpeakers)
        shot("size-22-play-on-sideways")
        pressBack()
        waitGone(text("This Phone"))

        closeNowPlayingWithButton()
        shot("size-23-library-sideways")
        assertTrue("still playing", model.player.isPlaying)
    }
}
