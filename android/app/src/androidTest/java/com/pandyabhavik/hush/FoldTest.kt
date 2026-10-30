package com.pandyabhavik.hush

import android.util.Log
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.test.click
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTouchInput
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.pandyabhavik.hush.ui.Route
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Folding and unfolding, simulated by switching the display between the Fold's two screen sizes
 * (`wm size` / `wm density`) in the middle of a test. Whatever is open (a page, Now Playing, a video,
 * the chosen section) has to survive the switch both ways, and keep working.
 */
@RunWith(AndroidJUnit4::class)
class FoldTest : HushTestBase() {
    private var originalSize: String? = null
    private var originalDensity: String? = null
    private var startedWide = false

    @Before
    fun rememberScreen() {
        originalSize = Regex("Override size: (\\d+x\\d+)").find(shell("wm size"))?.groupValues?.get(1)
        originalDensity = Regex("Override density: (\\d+)").find(shell("wm density"))?.groupValues?.get(1)
        startedWide = wide
        Log.i(TAG, "Fold test starts at ${originalSize ?: "the physical size"}, density ${originalDensity ?: "physical"}, wide=$startedWide")
    }

    @After
    fun restoreScreen() {
        shell(if (originalSize != null) "wm size $originalSize" else "wm size reset")
        shell(if (originalDensity != null) "wm density $originalDensity" else "wm density reset")
        runCatching { compose.waitUntil(10_000) { wide == startedWide } }
    }

    /** Switches to the other screen: unfolds the cover screen, or folds the inner one. */
    private fun flip(label: String) {
        val toWide = !wide
        if (toWide) {
            shell("wm size 1968x2184")
            shell("wm density 374")
        } else {
            shell("wm size 1080x2520")
            shell("wm density 420")
        }
        waitUntil("the screen to ${if (toWide) "unfold" else "fold"}", 15_000) { wide == toWide }
        compose.waitForIdle()
        Thread.sleep(800)
        compose.waitForIdle()
        shot("fold-$label-${if (toWide) "unfolded" else "folded"}")
    }

    @Test
    fun anAlbumPageSurvives() {
        openAlbumOf("Hush Test Two")
        val page = model.pages.last()
        repeat(2) { i ->
            flip("album-$i")
            assertEquals(page, model.pages.lastOrNull())
            waitDisplayed(button("Shuffle"))
            waitDisplayed(songRow("Hush Test Three"))
            // And it still works in the new layout.
            tap(songRow(if (i == 0) "Hush Test Three" else "Hush Test One"))
            waitPlaying(if (i == 0) "Hush Test Three" else "Hush Test One")
        }
        tap(desc("Back"))
        waitUntil("back in the library") { model.pages.isEmpty() }
    }

    @Test
    fun nowPlayingSurvives() {
        playFromSongs("Hush Test One")
        openNowPlaying()
        repeat(2) { i ->
            val playing = model.player.currentId
            flip("player-$i")
            assertTrue("Now Playing still open", model.playerOpen)
            waitDisplayed(desc("Repeat"))
            waitDisplayed(desc("Next"))
            assertEquals(playing, model.player.currentId)
            assertTrue("still playing", model.player.isPlaying)
            tap(desc("Next"))
            waitUntil("the next song") { model.player.currentId != playing }
        }
        closeNowPlayingWithButton()
    }

    @Test
    fun aVideoSurvives() {
        useTestVideosFolder()
        openSection("Videos")
        tap(button("Hush Test Video"))
        waitUntil("the video to open", 3_000) { model.video?.title == "Hush Test Video" }
        repeat(2) { i ->
            flip("video-$i")
            assertEquals("Hush Test Video", model.video?.title)
            if (!exists(desc("Close video"))) {
                compose.onRoot().performTouchInput { click(Offset(width * 0.1f, height * 0.5f)) }
            }
            waitUntil("the video controls after the switch", 3_000) { exists(desc("Close video")) }
            assertTrue(compose.onAllNodes(hasText("can't play", substring = true)).fetchSemanticsNodes().isEmpty())
        }
        node(desc("Close video")).performClick()
        waitUntil("the video to close") { model.video == null }
    }

    @Test
    fun theChosenSectionSurvives() {
        openSection("Artists")
        waitDisplayed(button("Guest Singer"))
        repeat(2) { i ->
            flip("artists-$i")
            waitDisplayed(button("Guest Singer"))
            waitDisplayed(button("Quiet Players"))
        }
        openSection("Songs")
        flip("songs")
        waitDisplayed(songRow("Hush Test One"))
        tap(songRow("Hush Test One"))
        waitPlaying("Hush Test One")
    }

    @Test
    fun aPlaylistPageAndThePlayerBarSurvive() {
        val playlist = injectTestPlaylist()
        if (wide) {
            openSection("Albums")
            tap(button("Hush Test Mix"))
        } else {
            openSection("Playlists")
            showTitles()
            tap(button("Hush Test Mix"))
        }
        waitUntil("the playlist page") { model.pages.lastOrNull() == Route.PlaylistPage(playlist.id) }
        tap(button("Play"))
        waitPlaying("Hush Test Three")
        flip("playlist")
        assertEquals(Route.PlaylistPage(playlist.id), model.pages.lastOrNull())
        waitDisplayed(button("Shuffle"))
        // The mini player or player bar is there and opens Now Playing.
        openNowPlaying()
        closeNowPlayingWithButton()
        tap(desc("Back"))
        waitUntil("back in the library") { model.pages.isEmpty() }
    }
}
