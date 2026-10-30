package com.pandyabhavik.hush

import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.performClick
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.pandyabhavik.hush.ui.Route
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/** Album, artist and playlist pages: open from tiles, Play, Shuffle, rows, the "…" menus, links and Back; long-press menus. */
@RunWith(AndroidJUnit4::class)
class PagesTest : HushTestBase() {

    private fun album(title: String) = model.library.albums.first { it.title == title }
    private fun artist(name: String) = model.library.artists.first { it.name == name }

    private fun back() {
        compose.waitForIdle()
        tap(desc("Back"))
    }

    @Test
    fun albumPageFromItsTile() {
        val hushAlbum = album("Hush Test Album")
        openSection("Albums")
        showTitles()
        tap(button("Hush Test Album"))
        waitUntil("the album page") { model.pages.lastOrNull() == Route.AlbumPage(hushAlbum.key) }
        waitDisplayed(button("Play"))
        waitDisplayed(button("Shuffle"))
        for (title in listOf("Hush Test One", "Hush Test Two", "Hush Test Three")) waitDisplayed(songRow(title))
        shot("pages-01-album")

        tap(button("Play"))
        waitPlaying("Hush Test One")
        assertEquals(hushAlbum.songs.map { it.mediaId }, model.player.queue)
        assertTrue(!model.player.shuffled)

        tap(button("Shuffle"))
        waitUntil("shuffled album", 15_000) { model.player.isPlaying && model.player.shuffled }
        assertEquals(hushAlbum.songs.map { it.mediaId }.toSet(), model.player.queue.toSet())

        // A track row plays from that track, in album order.
        tap(songRow("Hush Test Three"))
        waitPlaying("Hush Test Three")
        assertTrue(!model.player.shuffled)
        shot("pages-02-album-playing")

        // The page's "…" menu.
        tap(desc("More"))
        tap(button("Play Next"))
        waitUntil("the album next in Up Next") { model.player.upNext.take(3) == hushAlbum.songs.map { it.mediaId } }
        tap(desc("More"))
        tap(button("Add to Queue"))
        waitUntil("the album at the end of the queue") { model.player.queue.takeLast(3) == hushAlbum.songs.map { it.mediaId } }
        tap(desc("More"))
        shot("pages-03-album-menu")
        tap(button(if (wide) "Go to Artist" else "Go to Hush Test Artist"))
        waitUntil("the artist page") { model.pages.lastOrNull() == Route.ArtistPage(artist("Hush Test Artist").id) }
        waitDisplayed(hasText("3 songs", substring = true))

        back()
        waitUntil("back on the album") { model.pages.lastOrNull() == Route.AlbumPage(hushAlbum.key) }
        waitDisplayed(button("Shuffle"))
        back()
        waitUntil("back in the library") { model.pages.isEmpty() }
        waitDisplayed(button("Hush Test Album"))
    }

    @Test
    fun albumArtistLinkAndBackKey() {
        openAlbumOf("Hush Test Two")
        tap(songRow("Hush Test Artist"))
        waitUntil("the artist page") { model.pages.lastOrNull() is Route.ArtistPage }
        pressBack()
        waitUntil("back on the album") { model.pages.lastOrNull() is Route.AlbumPage }
        pressBack()
        waitUntil("back in the library") { model.pages.isEmpty() }
        waitDisplayed(songRow("Hush Test Two"))
    }

    @Test
    fun artistPageFromItsTile() {
        val guest = artist("Guest Singer")
        val guestAlbum = album("Guest Album")
        openSection("Artists")
        tap(button("Guest Singer"))
        waitUntil("the artist page") { model.pages.lastOrNull() == Route.ArtistPage(guest.id) }
        waitDisplayed(hasText("2 albums", substring = true))
        waitDisplayed(button("Play"))
        shot("pages-10-artist")

        tap(button("Play"))
        waitPlaying()
        assertEquals(guest.songs.map { it.mediaId }, model.player.queue)
        tap(button("Shuffle"))
        waitUntil("shuffled artist", 15_000) { model.player.isPlaying && model.player.shuffled }

        // Favourite, and back again.
        if (wide) {
            tap(desc("Add to Favourites"))
            waitUntil("a favourite") { model.isFavorite(guest.id) }
            waitDisplayed(desc("Remove from Favourites"))
            tap(desc("Remove from Favourites"))
        } else {
            tap(desc("More"))
            for (item in listOf("Add to Favorites", "Play Next", "Add to Queue")) waitDisplayed(button(item))
            tap(button("Add to Favorites"))
            waitUntil("a favourite") { model.isFavorite(guest.id) }
            tap(desc("More"))
            tap(button("Remove from Favorites"))
        }
        waitUntil("not a favourite") { !model.isFavorite(guest.id) }

        tap(desc("More"))
        tap(button("Add to Queue"))
        waitUntil("the artist's songs queued") { model.player.queue.takeLast(guest.songs.size) == guest.songs.map { it.mediaId } }

        // One of the artist's albums.
        val albumCard = button("Guest Album") and hasText("2 songs", substring = true)
        scrollUntilDisplayed(albumCard)
        shot("pages-11-artist-albums")
        tap(albumCard)
        waitUntil("the Guest Album page") { model.pages.lastOrNull() == Route.AlbumPage(guestAlbum.key) }
        waitDisplayed(songRow("Guest Song B"))
        tap(songRow("Guest Song B"))
        waitPlaying("Guest Song B")

        back()
        waitUntil("back on the artist") { model.pages.lastOrNull() == Route.ArtistPage(guest.id) }
        back()
        waitUntil("back in the library") { model.pages.isEmpty() }
    }

    @Test
    fun playlistPage() {
        val playlist = injectTestPlaylist()
        if (wide) {
            // The sidebar lists playlists; this one opens straight from there.
            openSection("Albums")
            tap(button("Hush Test Mix"))
        } else {
            openSection("Playlists")
            showTitles()
            tap(button("Hush Test Mix"))
        }
        waitUntil("the playlist page") { model.pages.lastOrNull() == Route.PlaylistPage(playlist.id) }
        waitDisplayed(button("Play"))
        for (song in playlist.songs) waitDisplayed(songRow(song.title))
        shot("pages-20-playlist")

        tap(button("Play"))
        waitPlaying("Hush Test Three")
        assertEquals(playlist.songs.map { it.mediaId }, model.player.queue)
        tap(songRow("Guest Song A"))
        waitPlaying("Guest Song A")
        tap(button("Shuffle"))
        waitUntil("shuffled playlist", 15_000) { model.player.isPlaying && model.player.shuffled }

        tap(desc("More"))
        waitDisplayed(button("Play Next"))
        tap(button("Add to Queue"))
        waitUntil("the playlist queued") { model.player.queue.takeLast(3) == playlist.songs.map { it.mediaId } }
        shot("pages-21-playlist-playing")

        back()
        waitUntil("back in the library") { model.pages.isEmpty() }
        if (wide) {
            // Opening from the sidebar chose the Playlists section; its grid has the tile.
            val tiles = compose.onAllNodes(button("Hush Test Mix")).fetchSemanticsNodes()
            assertTrue("the playlist in the sidebar and in the grid", tiles.size >= 2)
            // The grid's tile is the one further right.
            val gridIndex = tiles.indices.maxByOrNull { tiles[it].boundsInWindow.left }!!
            compose.onAllNodes(button("Hush Test Mix"))[gridIndex].performClick()
            waitUntil("the playlist page from its tile") { model.pages.lastOrNull() == Route.PlaylistPage(playlist.id) }
            back()
        }
    }

    @Test
    fun songLongPressMenu() {
        playFromSongs("Hush Test One")
        val two = song("Hush Test Two")
        val guestB = song("Guest Song B")

        longPress(songRow("Hush Test Two"))
        for (item in listOf("Play Next", "Add to Queue", "Go to Album", "Go to Artist")) waitDisplayed(button(item))
        shot("pages-30-song-menu")
        tap(button("Play Next"))
        waitUntil("Hush Test Two next") { model.player.upNext.firstOrNull() == two.mediaId }

        longPress(songRow("Guest Song B"))
        tap(button("Add to Queue"))
        waitUntil("Guest Song B last") { model.player.queue.lastOrNull() == guestB.mediaId }
        assertEquals("Hush Test One", currentTitle())

        longPress(songRow("Hush Test Two"))
        tap(button("Go to Album"))
        waitUntil("the album page") { model.pages.lastOrNull() == Route.AlbumPage(two.albumKey) }
        back()
        waitUntil("back in the library") { model.pages.isEmpty() }

        longPress(songRow("Hush Test Two"))
        tap(button("Go to Artist"))
        // The first credited singer.
        waitUntil("the artist page") { model.pages.lastOrNull() == Route.ArtistPage(artist("Hush Test Artist").id) }
        back()
        waitUntil("back in the library") { model.pages.isEmpty() }
    }

    @Test
    fun albumTileLongPressMenu() {
        val guestAlbum = album("Guest Album")
        openSection("Albums")
        showTitles()
        longPress(button("Guest Album"))
        waitDisplayed(button("Play Next"))
        waitDisplayed(button("Add to Queue"))
        shot("pages-40-album-tile-menu")
        if (wide) {
            for (item in listOf("Play", "Shuffle", "Go to Artist")) waitDisplayed(button(item))
            tap(button("Play"))
            waitPlaying("Guest Song A")
            assertEquals(guestAlbum.songs.map { it.mediaId }, model.player.queue)
            longPress(button("Guest Album"))
            tap(button("Go to Artist"))
            waitUntil("the artist page") { model.pages.lastOrNull() == Route.ArtistPage(artist("Guest Singer").id) }
            back()
        } else {
            // Nothing is playing, so Add to Queue starts the album.
            tap(button("Add to Queue"))
            waitPlaying("Guest Song A")
            longPress(button("Hush Test Album"))
            tap(button("Play Next"))
            waitUntil("Hush Test Album next") {
                model.player.upNext.take(3) == album("Hush Test Album").songs.map { it.mediaId }
            }
        }
    }
}
