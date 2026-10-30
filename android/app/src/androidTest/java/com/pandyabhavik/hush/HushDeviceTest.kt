package com.pandyabhavik.hush

import android.Manifest
import androidx.compose.ui.test.ExperimentalTestApi
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.longClick
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onFirst
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollToIndex
import androidx.compose.ui.test.performTouchInput
import androidx.lifecycle.ViewModelProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.rule.GrantPermissionRule
import com.pandyabhavik.hush.data.PlaylistFiles
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Runs on an emulator in CI with test songs and a test video copied onto it
 * (see android/ci/device-tests.sh). Screenshots go to /sdcard/Download/hush-screens.
 */
@OptIn(ExperimentalTestApi::class)
@RunWith(AndroidJUnit4::class)
class HushDeviceTest {
    @get:Rule(order = 0)
    val permissions: GrantPermissionRule = GrantPermissionRule.grant(
        Manifest.permission.READ_MEDIA_AUDIO,
        Manifest.permission.READ_MEDIA_VIDEO,
        Manifest.permission.POST_NOTIFICATIONS,
    )

    @get:Rule(order = 1)
    val compose = createAndroidComposeRule<MainActivity>()

    private val model get() = ViewModelProvider(compose.activity)[HushModel::class.java]

    private fun shot(name: String) {
        compose.waitForIdle()
        Thread.sleep(400)
        val automation = InstrumentationRegistry.getInstrumentation().uiAutomation
        automation.executeShellCommand("mkdir -p /sdcard/Download/hush-screens").close()
        val size = compose.activity.resources.displayMetrics.let { "${it.widthPixels}x${it.heightPixels}" }
        automation.executeShellCommand("screencap -p /sdcard/Download/hush-screens/$size-$name.png").close()
        Thread.sleep(600)
    }

    @Before
    fun waitForLibrary() {
        compose.waitUntil(30_000) { model.loaded && model.library.songs.size >= 3 }
        compose.waitUntil(15_000) { model.player.currentId != null || compose.activity.isFinishing.not() }
    }

    private fun openTab(index: Int, title: String) {
        compose.onNodeWithTag("tabs").performScrollToIndex(index)
        compose.onNodeWithText(title).performClick()
        compose.waitForIdle()
    }

    @Test
    fun tappingASongPlaysIt() {
        shot("01-albums")
        openTab(1, "Songs")
        shot("02-songs")
        compose.onNodeWithText("Hush Test One").performClick()
        compose.waitUntil(15_000) { model.player.isPlaying }
        // Keep playing for a while: a crash during playback would end the test here.
        Thread.sleep(4000)
        assertTrue("still playing", model.player.isPlaying)
        assertEquals("Hush Test One", model.library.song(model.player.currentId)?.title)
        shot("03-playing")

        compose.onNodeWithTag("miniPlayer").performClick()
        compose.waitUntil(5_000) { compose.onAllNodes(hasContentDescription("Up Next")).fetchSemanticsNodes().isNotEmpty() }
        shot("04-player")
        val first = model.player.currentId
        compose.onNodeWithContentDescription("Next").performClick()
        compose.waitUntil(10_000) { model.player.currentId != first }
        compose.onNodeWithContentDescription("Pause").performClick()
        compose.waitUntil(5_000) { !model.player.isPlaying }
        compose.onNodeWithContentDescription("Up Next").performClick()
        shot("05-up-next")
    }

    @Test
    fun albumAndArtistPagesPlay() {
        openTab(1, "Songs")
        compose.onNodeWithText("Hush Test Two").performTouchInput { longClick() }
        compose.onNodeWithText("Go to Album").performClick()
        compose.waitUntil(5_000) { compose.onAllNodes(hasText("Shuffle")).fetchSemanticsNodes().isNotEmpty() }
        shot("06-album")
        compose.onNodeWithText("Play").performClick()
        compose.waitUntil(15_000) { model.player.isPlaying }
        assertEquals("Hush Test One", model.library.song(model.player.currentId)?.title)
        compose.onNodeWithText("Shuffle").performClick()
        compose.waitUntil(15_000) { model.player.isPlaying && model.player.shuffled }
        Thread.sleep(2000)

        compose.onNodeWithText("Hush Test Artist").performClick()
        compose.waitUntil(5_000) { compose.onAllNodes(hasText("3 songs", substring = true)).fetchSemanticsNodes().isNotEmpty() }
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

    @Test
    fun playsAMusicVideo() {
        openTab(4, "Videos")
        compose.waitUntil(10_000) { compose.onAllNodes(hasText("Hush Test Video")).fetchSemanticsNodes().isNotEmpty() }
        shot("08-videos")
        compose.onNodeWithText("Hush Test Video").performClick()
        Thread.sleep(4000)
        assertTrue(compose.onAllNodes(hasText("can't play", substring = true)).fetchSemanticsNodes().isEmpty())
        shot("09-video-playing")
        compose.onNodeWithContentDescription("Close video").performClick()
        compose.waitForIdle()
        assertFalse(compose.activity.isFinishing)
    }

    @Test
    fun coversAndPlaylistsTabsShow() {
        compose.onAllNodesWithText("Albums").onFirst().performClick()
        shot("10-albums-grid")
        openTab(2, "Playlists")
        shot("11-playlists-empty")
        openTab(3, "Artists")
        shot("12-artists")
        assertTrue(compose.onAllNodes(hasTestTag("tabs")).fetchSemanticsNodes().isNotEmpty())
    }
}
