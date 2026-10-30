package com.pandyabhavik.hush

import androidx.compose.ui.test.hasSetTextAction
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.test.performTextInput
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.swipeDown
import androidx.compose.ui.test.swipeLeft
import androidx.compose.ui.test.swipeRight
import androidx.lifecycle.Lifecycle
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeFalse
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

/** The library: every section, search, the options menus, refresh, About, and the sidebar on the inner screen. */
@RunWith(AndroidJUnit4::class)
class LibraryTest : HushTestBase() {

    /** Top-left first: true when [a] comes before [b] in a grid read left to right, top to bottom. */
    private fun comesBefore(a: String, b: String): Boolean {
        val ra = node(button(a)).fetchSemanticsNode().boundsInWindow
        val rb = node(button(b)).fetchSemanticsNode().boundsInWindow
        return if (kotlin.math.abs(ra.top - rb.top) > 4f) ra.top < rb.top else ra.left < rb.left
    }

    @Test
    fun everySectionShowsItsContent() {
        openSection("Albums")
        showTitles()
        waitDisplayed(button("Hush Test Album"))
        waitDisplayed(button("Guest Album"))
        shot("lib-01-albums")

        openSection("Songs")
        waitDisplayed(songRow("Hush Test One"))
        waitDisplayed(songRow("Guest Song A"))
        shot("lib-02-songs")
        if (wide) {
            // The Songs toolbar's Shuffle All.
            tap(button("Shuffle All"))
            waitUntil("shuffled playback", 15_000) { model.player.isPlaying && model.player.shuffled }
            assertEquals(model.library.songs.size, model.player.queue.size)
        }

        openSection("Playlists")
        waitDisplayed(button("Choose Playlists Folder"))
        shot("lib-03-playlists-empty")

        openSection("Artists")
        waitDisplayed(button("Guest Singer"))
        waitDisplayed(button("Hush Test Artist"))
        waitDisplayed(button("Quiet Players"))
        shot("lib-04-artists")

        openSection("Videos")
        waitDisplayed(button("Choose Videos Folder"))
        shot("lib-05-videos-empty")

        // Back to the first section, and its content is there again.
        openSection("Albums")
        waitDisplayed(button("Hush Test Album"))
    }

    @Test
    fun compactTabsFollowSwipes() {
        assumeFalse("cover screen only", wide)
        openSection("Albums")
        compose.onRoot().performTouchInput { swipeLeft(startX = width * 0.85f, endX = width * 0.1f) }
        waitDisplayed(songRow("Hush Test One"))
        assertEquals("Songs", model.prefs.getString("tab", ""))
        compose.onRoot().performTouchInput { swipeRight(startX = width * 0.1f, endX = width * 0.9f) }
        waitNotDisplayed(songRow("Hush Test One"))
        waitUntil("the Albums tab") { model.prefs.getString("tab", "") == "Albums" }
    }

    @Test
    fun searchFiltersAndCancels() {
        openSection("Songs")
        tap(desc("Search"))
        waitDisplayed(hasSetTextAction())
        waitDisplayed(button("Cancel"))
        node(hasSetTextAction()).performTextInput("three")
        waitNotDisplayed(text("Hush Test One"))
        waitDisplayed(songRow("Hush Test Three"))
        shot("lib-10-search-three")

        // Clearing the field brings everything back; the search stays open.
        tap(desc(if (wide) "Clear search" else "Clear"))
        waitDisplayed(songRow("Hush Test One"))
        assertTrue(exists(button("Cancel")))

        node(hasSetTextAction()).performTextInput("guest")
        waitDisplayed(songRow("Guest Song A"))
        waitNotDisplayed(text("Hush Test One"))
        // A song with Guest Singer on it is found by the singer's name.
        waitDisplayed(songRow("Hush Test Two"))

        // Something that matches nothing.
        tap(desc(if (wide) "Clear search" else "Clear"))
        node(hasSetTextAction()).performTextInput("zzqx")
        waitNotDisplayed(songRow("Guest Song A"))
        shot("lib-11-search-nothing")

        tap(button("Cancel"))
        waitGone(button("Cancel"))
        waitDisplayed(songRow("Hush Test One"))

        // Artists, and Back closes the search.
        openSection("Artists")
        tap(desc("Search"))
        node(hasSetTextAction()).performTextInput("guest")
        waitDisplayed(button("Guest Singer"))
        waitNotDisplayed(button("Quiet Players"))
        shot("lib-12-search-artists")
        pressBack()
        // Back may first put the keyboard away.
        if (exists(button("Cancel"))) pressBack()
        waitGone(button("Cancel"))
        waitDisplayed(button("Quiet Players"))
    }

    @Test
    fun albumsOptionsMenu() {
        openSection("Albums")
        tap(desc("Options"))
        for (item in listOf("Alphabetical", "Most played", "Show Titles")) waitDisplayed(button(item))
        if (wide) {
            for (item in listOf("Choose Playlists Folder…", "Choose Videos Folder…", "Refresh Library", "About Hush")) waitDisplayed(button(item))
        }
        shot("lib-20-albums-options")
        tap(button("Most played"))
        waitGone(button("Show Titles"))
        assertEquals("MostPlayed", model.prefs.getString("sort", ""))
        tap(desc("Options"))
        tap(button("Alphabetical"))
        assertEquals("Alphabetical", model.prefs.getString("sort", ""))

        // Titles under the covers, on and off.
        val titlesOn = wide
        tap(desc("Options"))
        tap(button("Show Titles"))
        if (titlesOn) waitNotDisplayed(button("Hush Test Album")) else waitDisplayed(button("Hush Test Album"))
        shot("lib-21-titles-toggled")
        tap(desc("Options"))
        tap(button("Show Titles"))
        if (titlesOn) waitDisplayed(button("Hush Test Album")) else waitNotDisplayed(button("Hush Test Album"))

        if (wide) {
            tap(desc("Options"))
            assertRefreshReadsTheLibrary { tap(button("Refresh Library")) }

            tap(desc("Options"))
            tap(button("About Hush"))
            waitDisplayed(button("Done"))
            shot("lib-22-about")
            tap(button("Done"))
            waitGone(button("Done"))
        }
    }

    @Test
    fun artistsSortOptions() {
        openSection("Artists")
        tap(desc("Options"))
        for (item in listOf("Favorites", "Most songs", "Alphabetical", "Most played")) waitDisplayed(button(item))
        if (!wide) waitDisplayed(button("Look for Missing Photos"))
        shot("lib-30-artists-options")
        tap(button("Alphabetical"))
        waitUntil("A to Z") { model.prefs.getString("artistSort", "") == "Alphabetical" }
        compose.waitForIdle()
        assertTrue("Guest Singer before Quiet Players, A to Z", comesBefore("Guest Singer", "Quiet Players"))
        assertTrue("Guest Singer before Hush Test Artist, A to Z", comesBefore("Guest Singer", "Hush Test Artist"))

        tap(desc("Options"))
        tap(button("Most songs"))
        waitUntil("most songs first") { model.prefs.getString("artistSort", "") == "MostSongs" }
        compose.waitForIdle()
        assertTrue("Quiet Players (40 songs) first", comesBefore("Quiet Players", "Guest Singer"))

        tap(desc("Options"))
        tap(button("Most played"))
        waitUntil("most played") { model.prefs.getString("artistSort", "") == "MostPlayed" }

        tap(desc("Options"))
        tap(button("Favorites"))
        waitUntil("favourites") { model.prefs.getString("artistSort", "") == "Favorites" }
        // No favourites yet: everyone shows.
        waitDisplayed(button("Quiet Players"))

        if (!wide) {
            tap(desc("Options"))
            assertRefreshReadsTheLibrary { tap(button("Look for Missing Photos")) }
        }
    }

    @Test
    fun otherSectionsOptionsMenus() {
        openSection("Playlists")
        tap(desc("Options"))
        waitDisplayed(button("Show Titles"))
        waitDisplayed(button("Choose Playlists Folder…"))
        shot("lib-40-playlists-options")
        pressBack()
        waitGone(button("Choose Playlists Folder…"))

        openSection("Videos")
        tap(desc("Options"))
        waitDisplayed(button("Choose Videos Folder…"))
        shot("lib-41-videos-options")
        pressBack()
        waitGone(button("Choose Videos Folder…"))

        openSection("Songs")
        tap(desc("Options"))
        waitDisplayed(button("Most played"))
        tap(button("Most played"))
        waitUntil("songs by plays") { model.prefs.getString("sort", "") == "MostPlayed" }
        waitDisplayed(songRow("Hush Test One"))
    }

    @Test
    fun favouriteFromArtistTile() {
        openSection("Artists")
        val guest = model.library.artists.first { it.name == "Guest Singer" }
        longPress(button("Guest Singer"))
        for (item in listOf("Play Next", "Add to Queue")) waitDisplayed(button(item))
        shot("lib-50-artist-menu")
        tap(button(if (wide) "Add to Favourites" else "Add to Favorites"))
        waitUntil("Guest Singer to be a favourite") { model.isFavorite(guest.id) }
        if (wide) {
            waitDisplayed(text("FAVOURITES"))
        } else {
            // The cover screen's Favorites sort shows only favourites once there are any.
            waitNotDisplayed(button("Quiet Players"))
        }
        shot("lib-51-favourite")
        longPress(button("Guest Singer"))
        tap(button(if (wide) "Remove from Favourites" else "Remove from Favorites"))
        waitUntil("Guest Singer to be no longer a favourite") { !model.isFavorite(guest.id) }
        waitDisplayed(button("Quiet Players"))

        // The group menu's Play Next / Add to Queue start playback when nothing is playing.
        longPress(button("Guest Singer"))
        tap(button("Add to Queue"))
        waitPlaying()
        assertTrue(currentTitle() in guest.songs.map { it.title })
    }

    @Test
    fun aboutFromTheWordmark() {
        tap(button("Hush"))
        waitDisplayed(button("Done"))
        waitDisplayed(hasText("songs", substring = true))
        shot("lib-60-about")
        tap(button("Done"))
        waitGone(button("Done"))
    }

    @Test
    fun refreshReadsTheLibraryAgain() {
        openSection("Albums")
        val songs = model.library.songs.size
        assertRefreshReadsTheLibrary {
            if (wide) {
                tap(desc("Refresh"))
            } else {
                compose.onRoot().performTouchInput { swipeDown(startY = height * 0.35f, endY = height * 0.85f, durationMillis = 600) }
            }
        }
        assertEquals(songs, model.library.songs.size)
    }

    @Test
    fun wideSidebarHidesAndShows() {
        assumeTrue("inner screen only", wide)
        waitDisplayed(text("LIBRARY"))
        tap(desc("Hide sidebar"))
        waitGone(text("LIBRARY"))
        waitDisplayed(desc("Show sidebar"))
        shot("lib-70-sidebar-hidden")
        // With the sidebar gone the grid gets the room: Hush Test Album is still there.
        waitDisplayed(button("Hush Test Album"))
        assertFalse(model.prefs.getBoolean("wideSidebar", true))
        tap(desc("Show sidebar"))
        waitDisplayed(text("LIBRARY"))
        assertTrue(model.prefs.getBoolean("wideSidebar", false))

        // The toggle on a page works too.
        openAlbumOf("Hush Test One")
        tap(desc("Hide sidebar"))
        waitGone(text("LIBRARY"))
        waitDisplayed(button("Shuffle"))
        shot("lib-71-album-no-sidebar")
        tap(desc("Show sidebar"))
        waitDisplayed(text("LIBRARY"))
    }

    /** "Choose … Folder" opens the system folder picker, and coming back leaves Hush as it was. */
    @Test
    fun folderPickersOpen() {
        val activity = compose.activity
        for ((section, label) in listOf("Playlists" to "Choose Playlists Folder", "Videos" to "Choose Videos Folder")) {
            openSection(section)
            tap(button(label))
            waitUntil("the system folder picker for $section", 10_000) { !activity.lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED) }
            Thread.sleep(1500)
            rawShot("lib-80-picker-$section")
            for (i in 0 until 3) {
                if (activity.lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED)) break
                shell("input keyevent 4")
                Thread.sleep(1500)
            }
            waitUntil("Hush to come back from the picker", 10_000) { activity.lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED) }
            waitDisplayed(button(label))
            assertTrue(if (section == "Playlists") model.playlistsFolder == null else model.videosFolder == null)
        }
    }
}
