package com.pandyabhavik.hush

import android.Manifest
import android.content.pm.ActivityInfo
import android.net.Uri
import android.os.ParcelFileDescriptor
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.test.click
import androidx.compose.ui.test.onRoot
import java.io.File
import androidx.compose.ui.test.ExperimentalTestApi
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.longClick
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onFirst
import androidx.compose.ui.test.onLast
import androidx.compose.ui.test.hasTextExactly
import androidx.compose.ui.test.hasClickAction
import androidx.compose.ui.test.hasSetTextAction
import androidx.compose.ui.test.performTextInput
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
import org.junit.After
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

    /** Tests share the app's settings; leave the videos folder unset for the next one. */
    @After
    fun forgetTestVideosFolder() {
        if (model.videosFolder != null) compose.runOnUiThread { model.forgetVideosFolder() }
    }

    /** A library section: a tab on the cover screen, a sidebar item on the inner screen. */
    private fun openTab(index: Int, title: String) {
        if (compose.onAllNodes(hasTestTag("tabs")).fetchSemanticsNodes().isNotEmpty()) {
            compose.onNodeWithTag("tabs").performScrollToIndex(index)
        }
        compose.onAllNodes(hasTextExactly(title) and hasClickAction()).onFirst().performClick()
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
        // Every control has to fit on screen, on the cover screen too.
        for (control in listOf("Shuffle", "Repeat", "Previous", "Next", "Close")) {
            compose.onNodeWithContentDescription(control).assertIsDisplayed()
        }
        val first = model.player.currentId
        compose.onNodeWithContentDescription("Next").performClick()
        compose.waitUntil(10_000) { model.player.currentId != first }
        compose.onAllNodes(hasContentDescription("Pause")).onLast().performClick()
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

        compose.onNode(hasTextExactly("Hush Test Artist") and hasClickAction()).performClick()
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

    /** The folder picker can't be driven in a test, so the test video is copied into a plain folder Hush may read. */
    private fun useTestVideosFolder() {
        val app = compose.activity.applicationContext
        val dir = File(app.filesDir, "test-videos").apply { mkdirs() }
        val target = File(dir, "Hush Test Artist - Hush Test Video.mp4")
        if (!target.exists()) {
            val automation = InstrumentationRegistry.getInstrumentation().uiAutomation
            val pipe = automation.executeShellCommand("cat '/sdcard/Music Videos/Hush Test Artist - Hush Test Video.mp4'")
            ParcelFileDescriptor.AutoCloseInputStream(pipe).use { input -> target.outputStream().use { input.copyTo(it) } }
        }
        compose.runOnUiThread { model.setVideosFolder(Uri.fromFile(dir)) }
        compose.waitUntil(20_000) { model.library.videos.isNotEmpty() && !model.refreshing }
    }

    private fun showVideoControls() {
        if (compose.onAllNodes(hasContentDescription("Close video")).fetchSemanticsNodes().isEmpty()) {
            compose.onRoot().performTouchInput { click(Offset(width * 0.1f, height * 0.5f)) }
            compose.waitUntil(3_000) { compose.onAllNodes(hasContentDescription("Close video")).fetchSemanticsNodes().isNotEmpty() }
        }
    }

    @Test
    fun videosAskForOneFolder() {
        openTab(4, "Videos")
        assertTrue(model.videosFolder == null)
        compose.waitUntil(5_000) { compose.onAllNodes(hasText("Choose Videos Folder")).fetchSemanticsNodes().isNotEmpty() }
        shot("08a-videos-choose-folder")
    }

    @Test
    fun playsAMusicVideo() {
        useTestVideosFolder()
        openTab(4, "Videos")
        compose.waitUntil(10_000) { compose.onAllNodes(hasText("Hush Test Video")).fetchSemanticsNodes().isNotEmpty() }
        assertEquals("Hush Test Artist", model.library.videos.first().artist)
        shot("08-videos")
        compose.onNodeWithText("Hush Test Video").performClick()
        compose.waitUntil(8_000) { compose.onAllNodes(hasContentDescription("Pause")).fetchSemanticsNodes().isNotEmpty() }
        assertTrue(compose.onAllNodes(hasText("can't play", substring = true)).fetchSemanticsNodes().isEmpty())
        shot("09-video-playing")

        // The picture modes, in turn, like VLC.
        for (label in listOf("Fill", "Stretch", "16:9", "4:3", "Original Size", "Best Fit")) {
            showVideoControls()
            compose.onNode(hasContentDescription("Picture:", substring = true)).performClick()
            compose.waitUntil(3_000) { compose.onAllNodes(hasContentDescription("Picture: $label")).fetchSemanticsNodes().isNotEmpty() }
            if (label == "Fill" || label == "Stretch") shot("09-video-$label")
        }

        // Turning works whatever the phone's rotation lock says.
        showVideoControls()
        compose.onNode(hasContentDescription("Turn:", substring = true)).performClick()
        compose.waitUntil(3_000) {
            compose.activity.requestedOrientation == ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE
        }
        Thread.sleep(1500)
        shot("09-video-landscape")
        showVideoControls()
        compose.onNode(hasContentDescription("Turn:", substring = true)).performClick()
        compose.waitUntil(3_000) { compose.activity.requestedOrientation == ActivityInfo.SCREEN_ORIENTATION_SENSOR_PORTRAIT }
        showVideoControls()
        compose.onNode(hasContentDescription("Turn:", substring = true)).performClick()
        compose.waitUntil(3_000) { compose.activity.requestedOrientation == ActivityInfo.SCREEN_ORIENTATION_SENSOR }

        showVideoControls()
        compose.onNodeWithContentDescription("Close video").performClick()
        compose.waitForIdle()
        assertEquals(ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED, compose.activity.requestedOrientation)
        assertTrue(model.video == null)
        assertFalse(compose.activity.isFinishing)
    }

    @Test
    fun searchFindsSongs() {
        openTab(1, "Songs")
        compose.onNodeWithContentDescription("Search").performClick()
        compose.onNode(hasSetTextAction()).performTextInput("three")
        compose.waitUntil(5_000) { compose.onAllNodes(hasText("Hush Test One", substring = true)).fetchSemanticsNodes().isEmpty() }
        assertTrue(compose.onAllNodes(hasText("Hush Test Three", substring = true)).fetchSemanticsNodes().isNotEmpty())
        shot("13-search")
        compose.onNodeWithText("Cancel").performClick()
        compose.waitUntil(5_000) { compose.onAllNodes(hasText("Hush Test One", substring = true)).fetchSemanticsNodes().isNotEmpty() }
    }

    @Test
    fun coversAndPlaylistsTabsShow() {
        openTab(0, "Albums")
        shot("10-albums-grid")
        openTab(2, "Playlists")
        shot("11-playlists-empty")
        openTab(3, "Artists")
        compose.waitUntil(5_000) { compose.onAllNodes(hasText("Guest Singer")).fetchSemanticsNodes().isNotEmpty() }
        shot("12-artists")
        assertTrue(compose.onAllNodes(hasTestTag("tabs")).fetchSemanticsNodes().isNotEmpty())
    }
}
