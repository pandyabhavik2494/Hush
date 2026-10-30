package com.pandyabhavik.hush

import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.click
import androidx.compose.ui.test.hasSetTextAction
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.longClick
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performSemanticsAction
import androidx.compose.ui.test.performTextInput
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.swipeDown
import androidx.compose.ui.test.swipeLeft
import androidx.compose.ui.test.swipeRight
import androidx.compose.ui.test.swipeUp
import androidx.compose.ui.unit.dp
import androidx.media3.common.Player
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.pandyabhavik.hush.ui.Route
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith
import kotlin.math.abs

/** Now Playing, the transport, shuffle and repeat, the scrubber, Up Next, the mini player and the player bar. */
@RunWith(AndroidJUnit4::class)
class PlaybackTest : HushTestBase() {

    private fun waitPosition(targetMs: Long, what: String) =
        waitUntil(what, 5_000) { abs(model.player.positionMs - targetMs) < 2_500 }

    @Test
    fun nowPlayingTransport() {
        playFromSongs("Hush Test One")
        openNowPlaying()
        for (control in listOf("Close", "Shuffle", "Up Next", "Repeat", "Previous", "Next", "More", "Position")) {
            node(desc(control)).assertIsDisplayed()
        }
        playerPlayPause().assertIsDisplayed()
        shot("play-01-now-playing")

        // Pause and play.
        playerPlayPause().performClick()
        waitUntil("a pause") { !model.player.isPlaying }
        playerPlayPause().performClick()
        waitPlaying("Hush Test One")

        // Next, then Previous in the first three seconds goes back a song.
        val next = model.player.upNext.first()
        tap(desc("Next"))
        waitUntil("the next song") { model.player.currentId == next }
        tap(desc("Previous"))
        waitUntil("the song before") { currentTitle() == "Hush Test One" }

        // Later in a song, Previous starts it again.
        waitUntil("a few seconds of music", 8_000) { model.player.positionMs > 4_000 }
        tap(desc("Previous"))
        waitUntil("the song to start again") { currentTitle() == "Hush Test One" && model.player.positionMs < 3_000 }

        // Shuffle on and off.
        assertEquals("Off", stateOf(desc("Shuffle")))
        tap(desc("Shuffle"))
        waitUntil("shuffle on") { model.player.shuffled && stateOf(desc("Shuffle")) == "On" }
        tap(desc("Shuffle"))
        waitUntil("shuffle off") { !model.player.shuffled && stateOf(desc("Shuffle")) == "Off" }

        // Repeat: off, all, one, off.
        tap(desc("Repeat"))
        waitUntil("repeat all") { model.player.repeatMode == Player.REPEAT_MODE_ALL && stateOf(desc("Repeat")) == "On" }
        tap(desc("Repeat"))
        waitUntil("repeat one") { model.player.repeatMode == Player.REPEAT_MODE_ONE }
        shot("play-02-repeat-one")
        tap(desc("Repeat"))
        waitUntil("repeat off") { model.player.repeatMode == Player.REPEAT_MODE_OFF && stateOf(desc("Repeat")) == "Off" }

        // The scrubber: by accessibility, then by a touch a quarter of the way along.
        waitUntil("the song's length") { model.player.durationMs > 0 }
        val duration = model.player.durationMs
        node(desc("Position")).performSemanticsAction(SemanticsActions.SetProgress) { it(0.5f) }
        waitPosition(duration / 2, "a seek to the middle")
        node(desc("Position")).performTouchInput { click(Offset(width * 0.25f, centerY)) }
        waitPosition(duration / 4, "a seek to a quarter")
        shot("play-03-scrubbed")
        assertTrue(model.player.isPlaying)

        closeNowPlayingWithButton()
        waitDisplayed(hasTestTag("miniPlayer"))
    }

    @Test
    fun nowPlayingClosesByBackAndSwipe() {
        playFromSongs("Hush Test One")
        openNowPlaying()
        pressBack()
        waitNowPlayingClosed()
        assertTrue(model.pages.isEmpty())

        openNowPlaying()
        compose.onRoot().performTouchInput { swipeDown(startY = height * 0.12f, endY = height * 0.8f, durationMillis = 250) }
        waitNowPlayingClosed()
        shot("play-10-swiped-closed")

        // Still playing, and it opens again.
        assertTrue(model.player.isPlaying)
        openNowPlaying()
        closeNowPlayingWithButton()
    }

    @Test
    fun nowPlayingLinksAndMenu() {
        playFromSongs("Hush Test One")
        val one = song("Hush Test One")

        openNowPlaying()
        // The "…" menu (the last one: a page underneath may have its own).
        val more = compose.onAllNodes(desc("More"))
        more[more.fetchSemanticsNodes().size - 1].performClick()
        waitDisplayed(button("Go to Album"))
        waitDisplayed(button("Go to Hush Test Artist"))
        shot("play-20-player-menu")
        tap(button("Go to Album"))
        waitUntil("the album page") { model.pages.lastOrNull() == Route.AlbumPage(one.albumKey) && !model.playerOpen }
        tap(desc("Back"))
        waitUntil("back in the library") { model.pages.isEmpty() }

        // The artist and album names under the title are links.
        openNowPlaying()
        tap(button("Hush Test Artist"))
        waitUntil("the artist page") { model.pages.lastOrNull() is Route.ArtistPage && !model.playerOpen }
        tap(desc("Back"))
        waitUntil("back in the library") { model.pages.isEmpty() }

        openNowPlaying()
        tap(button("Hush Test Album"))
        waitUntil("the album page") { model.pages.lastOrNull() == Route.AlbumPage(one.albumKey) && !model.playerOpen }
        // Now Playing opens over a page too, and closing it leaves the page.
        openNowPlaying()
        closeNowPlayingWithButton()
        assertTrue(model.pages.lastOrNull() is Route.AlbumPage)
        waitDisplayed(button("Shuffle"))
    }

    @Test
    fun miniPlayerOrPlayerBar() {
        playFromSongs("Hush Test One")
        val bar = hasTestTag("miniPlayer")
        waitDisplayed(bar)
        shot("play-30-bar")

        // Play and pause from the bar (only Now Playing is closed, so there's one button).
        tap(desc("Pause"))
        waitUntil("a pause") { !model.player.isPlaying }
        tap(desc("Play"))
        waitPlaying("Hush Test One")

        val next = model.player.upNext.first()
        if (wide) {
            tap(desc("Next"))
            waitUntil("the next song") { model.player.currentId == next }
            tap(desc("Previous"))
            waitUntil("the song before") { currentTitle() == "Hush Test One" }
        } else {
            // Swipe the mini player left for the next song, right for the one before, up to open the player.
            node(bar).performTouchInput { swipeLeft(startX = width * 0.8f, endX = width * 0.1f, durationMillis = 200) }
            waitUntil("the next song") { model.player.currentId == next }
            node(bar).performTouchInput { swipeRight(startX = width * 0.1f, endX = width * 0.8f, durationMillis = 200) }
            waitUntil("the song before") { currentTitle() == "Hush Test One" }
            Thread.sleep(500)
            node(bar).performTouchInput { swipeUp(startY = height * 0.9f, endY = -height * 2f, durationMillis = 200) }
            waitUntil("Now Playing to open") { model.playerOpen && exists(desc("Repeat")) }
            closeNowPlayingWithButton()
        }

        // Press and hold the bar: Go to Album / the artists.
        Thread.sleep(500)
        node(bar).performTouchInput { longClick(Offset(width * 0.3f, centerY)) }
        compose.waitForIdle()
        waitDisplayed(button("Go to Album"))
        shot("play-31-bar-menu")
        tap(button("Go to Album"))
        waitUntil("the album page") { model.pages.lastOrNull() is Route.AlbumPage }
        tap(desc("Back"))
        waitUntil("back in the library") { model.pages.isEmpty() }

        // A tap opens Now Playing.
        openNowPlaying()
        closeNowPlayingWithButton()
    }

    private fun dragHandle(rowDp: Float, rows: Float) {
        val handle = compose.onAllNodes(desc("Reorder"), useUnmergedTree = true)[0]
        val distance = with(compose.density) { rowDp.dp.toPx() } * rows
        handle.performTouchInput {
            down(center)
            repeat(30) { moveBy(Offset(0f, distance / 30f)) }
            up()
        }
        compose.waitForIdle()
    }

    @Test
    fun upNextReorderRemoveJumpAddClear() {
        playFromSongs("Hush Test One")
        openNowPlaying()
        tap(desc("Up Next"))
        if (wide) waitDisplayed(desc("Close Up Next")) else waitDisplayed(button("Clear"))
        waitUntil("the queue rows") { exists(desc("Reorder"), unmerged = true) }
        shot("play-40-up-next")

        // Drag the first song down two places.
        val original = model.player.upNext
        assertTrue("a long enough queue", original.size >= 5)
        dragHandle(if (wide) 56f else 64f, 2.35f)
        waitUntil("the first song moved two places down") {
            model.player.upNext.getOrNull(2) == original[0] && model.player.upNext.getOrNull(0) == original[1]
        }
        shot("play-41-reordered")

        // Remove the first one.
        val reordered = model.player.upNext
        tap(desc("Remove"))
        waitUntil("a song removed") { model.player.upNext == reordered.drop(1) }

        // Tap a song in the queue to play it.
        val target = model.player.upNext[1]
        tap(songRow(model.library.song(target)!!.title))
        waitUntil("the tapped song to play") { model.player.currentId == target }

        // Add Songs: find one and add it to the end.
        if (wide) tap(desc("Add Songs")) else tap(button("Add Songs"))
        waitDisplayed(hasSetTextAction())
        node(hasSetTextAction()).performTextInput("guest song")
        waitDisplayed(desc("Add to Queue"))
        shot("play-42-add-songs")
        tap(desc("Add to Queue"))
        waitUntil("a Guest song at the end") { model.library.song(model.player.queue.last())?.title?.startsWith("Guest Song") == true }
        tap(button("Done"))
        waitGone(hasSetTextAction())

        // Clear.
        tap(button("Clear"))
        waitUntil("an empty Up Next") { model.player.upNext.isEmpty() }
        waitDisplayed(text(if (wide) "NOTHING QUEUED" else "Nothing up next"))
        shot("play-43-cleared")

        // Close Up Next; the player stays open.
        if (wide) {
            tap(desc("Close Up Next"))
        } else {
            pressBack()
            // The first Back may only put the keyboard away.
            if (exists(text("Nothing up next"))) pressBack()
        }
        waitUntil("Up Next to close") { !exists(desc("Reorder"), unmerged = true) && !exists(text(if (wide) "NOTHING QUEUED" else "Nothing up next")) }
        assertTrue(model.playerOpen)
        node(desc("Repeat")).assertIsDisplayed()
    }

    /** The inner screen's "NEXT" line under the controls opens Up Next. */
    @Test
    fun wideNextLineOpensUpNext() {
        assumeTrue("inner screen only", wide)
        playFromSongs("Hush Test One")
        openNowPlaying()
        tap(button("NEXT"))
        waitDisplayed(desc("Close Up Next"))
        tap(desc("Up Next"))
        waitGone(desc("Close Up Next"))
    }

    /** The inner screen's Up Next panel from the player bar, over the library. */
    @Test
    fun wideUpNextPanelFromTheBar() {
        assumeTrue("inner screen only", wide)
        playFromSongs("Hush Test One")
        tap(desc("Up Next"))
        waitDisplayed(desc("Close Up Next"))
        shot("play-50-panel")
        val before = model.player.upNext
        tap(desc("Remove"))
        waitUntil("a song removed") { model.player.upNext == before.drop(1) }

        // Tapping outside closes it.
        compose.onRoot().performTouchInput { click(Offset(width * 0.4f, height * 0.4f)) }
        waitGone(desc("Close Up Next"))
        // The bar's toggle opens and closes it.
        tap(desc("Up Next"))
        waitDisplayed(desc("Close Up Next"))
        tap(desc("Up Next"))
        waitGone(desc("Close Up Next"))
        // Back closes it.
        tap(desc("Up Next"))
        waitDisplayed(desc("Close Up Next"))
        pressBack()
        waitGone(desc("Close Up Next"))
        // And its own close button; Clear empties it.
        tap(desc("Up Next"))
        tap(button("Clear"))
        waitUntil("an empty Up Next") { model.player.upNext.isEmpty() }
        tap(desc("Close Up Next"))
        waitGone(desc("Close Up Next"))
    }

    /** A song that finishes moves on to the next; at the end of the queue playback stops and Play starts again. */
    @Test
    fun songsFinishAndTheQueueEnds() {
        openAlbumOf("Guest Song A")
        tap(button("Play"))
        waitPlaying("Guest Song A")
        assertEquals(2, model.player.queue.size)
        openNowPlaying()
        waitUntil("the song's length") { model.player.durationMs > 0 }
        node(desc("Position")).performSemanticsAction(SemanticsActions.SetProgress) { it(0.95f) }
        waitUntil("the next song after the first ends", 15_000) { currentTitle() == "Guest Song B" && model.player.isPlaying }
        waitUntil("the song's length") { model.player.durationMs > 0 }
        node(desc("Position")).performSemanticsAction(SemanticsActions.SetProgress) { it(0.95f) }
        waitUntil("playback to stop at the end of the queue", 15_000) { !model.player.isPlaying }
        assertEquals("Guest Song B", currentTitle())
        shot("play-60-queue-ended")
        playerPlayPause().performClick()
        waitPlaying()
    }
}
