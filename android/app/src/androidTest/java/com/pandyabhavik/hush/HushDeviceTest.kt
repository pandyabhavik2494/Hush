package com.pandyabhavik.hush

import android.content.pm.ActivityInfo
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.test.ExperimentalTestApi
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.click
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.hasSetTextAction
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTextInput
import androidx.compose.ui.test.performTouchInput
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.pandyabhavik.hush.data.PlaylistFiles
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/**
 * The original smoke tests: a song plays, album and artist pages play, playlist files match,
 * videos ask for a folder and play, search works, the sections show. See [HushTestBase] for the media.
 */
@OptIn(ExperimentalTestApi::class)
@RunWith(AndroidJUnit4::class)
class HushDeviceTest : HushTestBase() {

    @Test
    fun tappingASongPlaysIt() {
        shot("01-albums")
        openSection("Songs")
        shot("02-songs")
        tap(songRow("Hush Test One"))
        waitPlaying("Hush Test One")
        // Keep playing for a while: a crash during playback would end the test here.
        Thread.sleep(4000)
        assertTrue("still playing", model.player.isPlaying)
        assertEquals("Hush Test One", currentTitle())
        shot("03-playing")

        openNowPlaying()
        shot("04-player")
        // Every control has to fit on screen, on the cover screen too.
        for (control in listOf("Shuffle", "Repeat", "Previous", "Next", "Close", "Up Next", "Position")) {
            node(desc(control)).assertIsDisplayed()
        }
        val first = model.player.currentId
        tap(desc("Next"))
        waitUntil("the next song") { model.player.currentId != first }
        playerPlayPause().performClick()
        waitUntil("a pause") { !model.player.isPlaying }
        tap(desc("Up Next"))
        shot("05-up-next")
    }

    @Test
    fun albumAndArtistPagesPlay() {
        openAlbumOf("Hush Test Two")
        shot("06-album")
        tap(button("Play"))
        waitPlaying("Hush Test One")
        tap(button("Shuffle"))
        waitUntil("shuffled playback", 15_000) { model.player.isPlaying && model.player.shuffled }
        Thread.sleep(2000)

        tap(button("Hush Test Artist") and hasTestTag("miniPlayer").not())
        waitDisplayed(hasText("3 songs", substring = true))
        shot("07-artist")
        // "Hush Test Artist & Guest Singer" credits both singers.
        assertTrue(model.library.artists.any { it.name == "Guest Singer" })
    }

    @Test
    fun playlistFilesMatchSongsOnThePhone() {
        val songs = model.library.songs
        val lines = listOf(
            "#EXTM3U",
            "#EXTINF:30,Hush Test Artist - Hush Test Three",
            "/Volumes/SSD/Music/Music/Media.localized/Music/Hush Test Artist/Hush Test Album/03 Hush Test Three.m4a",
            "/Volumes/SSD/Music/Music/Media.localized/Music/Somewhere Else/Other Album/01 Hush Test One.m4a",
            "#EXTINF:30,Hush Test Artist - Hush Test Two",
            "/not/on/this/phone.m4a",
            "/Volumes/SSD/Music/Music/Media.localized/Music/Nobody/Nothing/99 Missing.m4a",
        )
        val matched = PlaylistFiles.match(lines, songs).map { it.title }
        assertEquals(listOf("Hush Test Three", "Hush Test One", "Hush Test Two"), matched)
    }

    private fun showVideoControls() {
        if (!exists(desc("Close video"))) {
            compose.onRoot().performTouchInput { click(Offset(width * 0.1f, height * 0.5f)) }
            waitUntil("the video controls", 3_000) { exists(desc("Close video")) }
        }
    }

    @Test
    fun videosAskForOneFolder() {
        openSection("Videos")
        assertTrue(model.videosFolder == null)
        waitDisplayed(hasText("Choose Videos Folder"))
        shot("08a-videos-choose-folder")
    }

    @Test
    fun playsAMusicVideo() {
        useTestVideosFolder()
        openSection("Videos")
        waitDisplayed(button("Hush Test Video"), 10_000)
        assertEquals("Hush Test Artist", model.library.videos.first { it.title == "Hush Test Video" }.artist)
        shot("08-videos")
        tap(button("Hush Test Video"))
        waitUntil("the video to play", 8_000) { exists(desc("Pause")) }
        assertTrue(compose.onAllNodes(hasText("can't play", substring = true)).fetchSemanticsNodes().isEmpty())
        shot("09-video-playing")

        // The picture modes, in turn, like VLC.
        for (label in listOf("Fill", "Stretch", "16:9", "4:3", "Original Size", "Best Fit")) {
            showVideoControls()
            compose.onNode(hasContentDescription("Picture:", substring = true)).performClick()
            waitUntil("picture mode $label", 3_000) { exists(desc("Picture: $label")) }
            if (label == "Fill" || label == "Stretch") shot("09-video-$label")
        }

        // Turning works whatever the phone's rotation lock says.
        showVideoControls()
        compose.onNode(hasContentDescription("Turn:", substring = true)).performClick()
        waitUntil("landscape", 3_000) { compose.activity.requestedOrientation == ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE }
        Thread.sleep(1500)
        shot("09-video-landscape")
        showVideoControls()
        compose.onNode(hasContentDescription("Turn:", substring = true)).performClick()
        waitUntil("portrait", 3_000) { compose.activity.requestedOrientation == ActivityInfo.SCREEN_ORIENTATION_SENSOR_PORTRAIT }
        showVideoControls()
        compose.onNode(hasContentDescription("Turn:", substring = true)).performClick()
        waitUntil("auto-rotate", 3_000) { compose.activity.requestedOrientation == ActivityInfo.SCREEN_ORIENTATION_SENSOR }

        showVideoControls()
        tap(desc("Close video"))
        assertEquals(ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED, compose.activity.requestedOrientation)
        assertTrue(model.video == null)
        assertFalse(compose.activity.isFinishing)
    }

    @Test
    fun searchFindsSongs() {
        openSection("Songs")
        tap(desc("Search"))
        node(hasSetTextAction()).performTextInput("three")
        waitNotDisplayed(text("Hush Test One"))
        waitDisplayed(hasText("Hush Test Three", substring = true))
        shot("13-search")
        tap(button("Cancel"))
        waitDisplayed(hasText("Hush Test One", substring = true))
    }

    @Test
    fun coversAndPlaylistsTabsShow() {
        openSection("Albums")
        shot("10-albums-grid")
        openSection("Playlists")
        shot("11-playlists-empty")
        openSection("Artists")
        waitDisplayed(text("Guest Singer"))
        shot("12-artists")
        // The cover screen has the tab row; the inner screen has the sidebar instead.
        assertEquals(!wide, exists(hasTestTag("tabs")))
    }
}
