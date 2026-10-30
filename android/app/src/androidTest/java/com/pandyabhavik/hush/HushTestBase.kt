package com.pandyabhavik.hush

import android.Manifest
import android.content.Context
import android.net.Uri
import android.os.ParcelFileDescriptor
import android.util.Log
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.SemanticsNodeInteraction
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.hasClickAction
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.longClick
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollToIndex
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.swipeUp
import androidx.lifecycle.ViewModelProvider
import androidx.media3.common.Player
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.rule.GrantPermissionRule
import com.pandyabhavik.hush.data.Library
import com.pandyabhavik.hush.data.LibraryAlphabet
import com.pandyabhavik.hush.data.LibrarySearch
import com.pandyabhavik.hush.data.Playlist
import com.pandyabhavik.hush.data.Song
import com.pandyabhavik.hush.playback.PlayerConnection
import com.pandyabhavik.hush.ui.Route
import org.junit.After
import org.junit.Before
import org.junit.Rule
import org.junit.rules.ExternalResource
import org.junit.rules.TestRule
import java.io.File

/**
 * Shared set-up for the device tests. They run on an emulator in CI (android/ci/device-tests.sh)
 * once at the Fold's cover-screen size and once at its inner-screen size, with the media from
 * android/ci/make-test-media.sh on the phone:
 *  - "Hush Test Album" by Hush Test Artist (2024): Hush Test One, Hush Test Two (with Guest Singer), Hush Test Three
 *  - "Guest Album" by Guest Singer (2023): Guest Song A, Guest Song B
 *  - 40 one-song albums "Quiet Album 01".."Quiet Album 40" by Quiet Players (so lists are long enough to scroll)
 *  - two music videos, "Hush Test Video" (Hush Test Artist) and "Second Video" (Guest Singer),
 *    also copied to /data/local/tmp/hush-videos with spaces turned into underscores.
 *
 * Every test starts from fresh settings and an empty player, so tests do not depend on each other.
 * Screenshots go to /sdcard/Download/hush-screens (pulled into the CI results).
 */
abstract class HushTestBase {
    @get:Rule(order = 0)
    val permissions: GrantPermissionRule = GrantPermissionRule.grant(
        Manifest.permission.READ_MEDIA_AUDIO,
        Manifest.permission.POST_NOTIFICATIONS,
    )

    /** Settings (sort, tab, titles, favourites, folders) are cleared before the app starts. */
    @get:Rule(order = 1)
    val freshSettings: TestRule = object : ExternalResource() {
        override fun before() {
            InstrumentationRegistry.getInstrumentation().targetContext
                .getSharedPreferences("hush", Context.MODE_PRIVATE).edit().clear().commit()
        }
    }

    @get:Rule(order = 2)
    val compose = createAndroidComposeRule<MainActivity>()

    private var hushModel: HushModel? = null
    protected val model: HushModel
        get() = hushModel ?: ViewModelProvider(compose.activity)[HushModel::class.java].also { hushModel = it }

    /** The unfolded (inner) layout: 600 dp and wider. */
    protected val wide: Boolean
        get() = compose.activity.resources.configuration.screenWidthDp >= 600

    protected val sizeName: String
        get() = compose.activity.resources.displayMetrics.let { "${it.widthPixels}x${it.heightPixels}" }

    @Before
    fun startClean() {
        waitUntil("the library to load", 30_000) { model.loaded && model.library.songs.size >= 3 && !model.refreshing }
        // The playback service outlives each test's screen: empty it, so every test starts with nothing playing.
        val deadline = System.currentTimeMillis() + 10_000
        while (controller() == null && System.currentTimeMillis() < deadline) Thread.sleep(100)
        val c = controller()
        if (c != null) {
            compose.runOnUiThread {
                c.stop()
                c.clearMediaItems()
                c.repeatMode = Player.REPEAT_MODE_OFF
            }
            waitUntil("the player to empty", 5_000) { model.player.currentId == null && model.player.queue.isEmpty() }
        } else {
            Log.w(TAG, "Could not reach the media controller; the test starts with whatever was playing")
            Thread.sleep(2_000)
        }
        compose.waitForIdle()
    }

    @After
    fun quietDown() {
        runCatching {
            val c = controller()
            compose.runOnUiThread {
                model.video = null
                model.playerOpen = false
                c?.pause()
            }
        }
    }

    /** The app's MediaController (private in PlayerConnection), to reset the player between tests. */
    private fun controller(): Player? = runCatching {
        val field = PlayerConnection::class.java.getDeclaredField("controller")
        field.isAccessible = true
        field.get(model.player) as Player?
    }.getOrNull()

    // ------------------------------------------------------------------ Shell and screenshots

    protected fun shell(command: String): String {
        val pipe = InstrumentationRegistry.getInstrumentation().uiAutomation.executeShellCommand(command)
        return ParcelFileDescriptor.AutoCloseInputStream(pipe).bufferedReader().use { it.readText() }
    }

    protected fun shot(name: String) {
        compose.waitForIdle()
        Thread.sleep(400)
        rawShot(name)
        Thread.sleep(300)
    }

    /** A screenshot without waiting for the app to settle (for failures). */
    protected fun rawShot(name: String) {
        runCatching {
            shell("mkdir -p $SCREENS")
            shell("screencap -p $SCREENS/$sizeName-$name.png")
        }
    }

    /** The system Back key, through the real input path. */
    protected fun pressBack() {
        shell("input keyevent 4")
        compose.waitForIdle()
    }

    // ------------------------------------------------------------------ Finding things

    protected fun text(value: String) = hasText(value)
    protected fun desc(value: String) = hasContentDescription(value)
    protected fun button(value: String) = hasText(value) and hasClickAction()

    /** A tappable song row (not the player bar, which shows the same title on the wide screen). */
    protected fun songRow(title: String) = hasText(title) and hasClickAction() and !hasTestTag("miniPlayer")

    protected fun exists(matcher: SemanticsMatcher, unmerged: Boolean = false): Boolean =
        compose.onAllNodes(matcher, unmerged).fetchSemanticsNodes(atLeastOneRootRequired = false).isNotEmpty()

    protected fun count(matcher: SemanticsMatcher): Int =
        compose.onAllNodes(matcher).fetchSemanticsNodes(atLeastOneRootRequired = false).size

    /** The first node matching [matcher] that is actually on screen (pager pages beside the current one are not). */
    private fun displayedIndex(matcher: SemanticsMatcher, unmerged: Boolean = false): Int? {
        val all = compose.onAllNodes(matcher, unmerged)
        val n = all.fetchSemanticsNodes(atLeastOneRootRequired = false).size
        for (i in 0 until n) if (runCatching { all[i].assertIsDisplayed() }.isSuccess) return i
        return null
    }

    protected fun isDisplayed(matcher: SemanticsMatcher, unmerged: Boolean = false) = displayedIndex(matcher, unmerged) != null

    protected fun node(matcher: SemanticsMatcher, unmerged: Boolean = false): SemanticsNodeInteraction {
        val i = displayedIndex(matcher, unmerged) ?: run {
            rawShot("FAILED-not-on-screen")
            throw AssertionError("Nothing on screen matches: ${matcher.description}")
        }
        return compose.onAllNodes(matcher, unmerged)[i]
    }

    protected fun waitUntil(what: String, timeoutMs: Long = 5_000, condition: () -> Boolean) {
        try {
            compose.waitUntil(timeoutMs, condition)
        } catch (e: Throwable) {
            if (e is AssertionError && e.message?.startsWith("Timed out") == true) throw e
            rawShot("FAILED-" + what.replace(Regex("[^A-Za-z0-9]+"), "-").take(60))
            throw AssertionError("Timed out after $timeoutMs ms waiting for $what", e)
        }
    }

    protected fun waitDisplayed(matcher: SemanticsMatcher, timeoutMs: Long = 5_000) =
        waitUntil("'${matcher.description}' on screen", timeoutMs) { isDisplayed(matcher) }

    protected fun waitNotDisplayed(matcher: SemanticsMatcher, timeoutMs: Long = 5_000) =
        waitUntil("'${matcher.description}' to leave the screen", timeoutMs) { !isDisplayed(matcher) }

    protected fun waitGone(matcher: SemanticsMatcher, timeoutMs: Long = 5_000) =
        waitUntil("'${matcher.description}' to go away", timeoutMs) { !exists(matcher) }

    protected fun tap(matcher: SemanticsMatcher, timeoutMs: Long = 5_000) {
        compose.waitForIdle()
        waitDisplayed(matcher, timeoutMs)
        node(matcher).performClick()
        compose.waitForIdle()
    }

    protected fun longPress(matcher: SemanticsMatcher) {
        compose.waitForIdle()
        waitDisplayed(matcher)
        node(matcher).performTouchInput { longClick() }
        compose.waitForIdle()
    }

    /** Taps through the real input system (adb's `input tap`), at a fraction of the node's bounds. */
    protected fun realTap(matcher: SemanticsMatcher, fx: Float = 0.5f, fy: Float = 0.5f) {
        compose.waitForIdle()
        waitDisplayed(matcher)
        val bounds = node(matcher).fetchSemanticsNode().boundsInWindow
        val activity = compose.activity
        val origin = IntArray(2)
        compose.runOnUiThread { activity.window.decorView.getLocationOnScreen(origin) }
        val x = origin[0] + bounds.left + bounds.width * fx
        val y = origin[1] + bounds.top + bounds.height * fy
        shell("input tap ${x.toInt()} ${y.toInt()}")
    }

    /** Scrolls the screen's main list up a little at a time until [matcher] is on screen. */
    protected fun scrollUntilDisplayed(matcher: SemanticsMatcher, swipes: Int = 10) {
        repeat(swipes) {
            if (isDisplayed(matcher)) return
            compose.onRoot().performTouchInput { swipeUp(startY = height * 0.7f, endY = height * 0.45f, durationMillis = 500) }
            compose.waitForIdle()
        }
        waitDisplayed(matcher)
    }

    protected fun stateOf(matcher: SemanticsMatcher): String? =
        node(matcher).fetchSemanticsNode().config.getOrNull(SemanticsProperties.StateDescription)

    // ------------------------------------------------------------------ Library sections

    private val compactTabs = listOf("Albums", "Songs", "Playlists", "Artists", "Videos")

    /** A library section: a tab on the cover screen, a sidebar item on the inner screen. */
    protected fun openSection(title: String) {
        compose.waitForIdle()
        if (!wide) {
            compose.onNode(hasTestTag("tabs")).performScrollToIndex(compactTabs.indexOf(title))
            compose.waitForIdle()
        }
        tap(button(title))
    }

    /** Album and playlist titles under the covers (on by default on the inner screen, off on the cover screen). */
    protected fun showTitles() {
        val key = if (wide) "wideTitles" else "showTitles"
        if (model.prefs.getBoolean(key, wide)) return
        tap(desc("Options"))
        tap(button("Show Titles"))
        waitUntil("titles to be on") { model.prefs.getBoolean(key, wide) }
    }

    // ------------------------------------------------------------------ Playback

    protected fun song(title: String): Song = model.library.songs.first { it.title == title }
    protected fun currentTitle(): String? = model.library.song(model.player.currentId)?.title
    protected fun upNextTitles(): List<String?> = model.player.upNext.map { model.library.song(it)?.title }

    protected fun waitPlaying(title: String? = null, timeoutMs: Long = 15_000) =
        waitUntil(if (title == null) "music to play" else "'$title' to play", timeoutMs) {
            model.player.isPlaying && (title == null || currentTitle() == title)
        }

    /** Plays a song by tapping it in the Songs list. */
    protected fun playFromSongs(title: String) {
        openSection("Songs")
        tap(songRow(title))
        waitPlaying(title)
    }

    /** Opens Now Playing from the mini player (cover screen) or the player bar (inner screen). */
    protected fun openNowPlaying() {
        compose.waitForIdle()
        waitDisplayed(hasTestTag("miniPlayer"))
        node(hasTestTag("miniPlayer")).performClick()
        waitUntil("Now Playing to open") { model.playerOpen && exists(desc("Repeat")) }
        compose.waitForIdle()
    }

    protected fun closeNowPlayingWithButton() {
        tap(desc("Close"))
        waitNowPlayingClosed()
    }

    protected fun waitNowPlayingClosed() =
        waitUntil("Now Playing to close") { !model.playerOpen && !exists(desc("Repeat")) }

    /** Now Playing's play/pause (the mini player keeps its own under it on the cover screen, earlier in the tree). */
    protected fun playerPlayPause(): SemanticsNodeInteraction {
        val all = compose.onAllNodes(desc("Pause") or desc("Play"))
        return all[all.fetchSemanticsNodes().size - 1]
    }

    /** Opens the album page of a song through its long-press menu in Songs. */
    protected fun openAlbumOf(songTitle: String) {
        openSection("Songs")
        longPress(songRow(songTitle))
        tap(button("Go to Album"))
        waitUntil("the album page") { model.pages.lastOrNull() is Route.AlbumPage }
        waitDisplayed(button("Shuffle"))
    }

    // ------------------------------------------------------------------ Test-only content

    /**
     * The folder picker can't be driven in a test, so the test videos are copied into a plain
     * folder Hush may read. They are on the phone under /data/local/tmp/hush-videos with spaces
     * as underscores (shell commands from a test can't quote paths).
     */
    protected fun useTestVideosFolder(minimum: Int = 2) {
        val app = compose.activity.applicationContext
        val dir = File(app.filesDir, "test-videos").apply { mkdirs() }
        val names = shell("ls $DEVICE_VIDEOS").lines().map { it.trim() }.filter { it.endsWith(".mp4") }
        for (name in names) {
            val target = File(dir, name.replace('_', ' '))
            if (target.exists() && target.length() > 0) continue
            val pipe = InstrumentationRegistry.getInstrumentation().uiAutomation.executeShellCommand("cat $DEVICE_VIDEOS/$name")
            ParcelFileDescriptor.AutoCloseInputStream(pipe).use { input -> target.outputStream().use { input.copyTo(it) } }
        }
        compose.runOnUiThread { model.setVideosFolder(Uri.fromFile(dir)) }
        waitUntil("$minimum test videos to load", 20_000) { model.library.videos.size >= minimum && !model.refreshing }
    }

    /**
     * Hush reads playlists only from a folder chosen in the system picker, which a test can't
     * drive, so a playlist ("Hush Test Mix": Hush Test Three, Guest Song A, Hush Test One) is put
     * straight into the loaded library.
     */
    protected fun injectTestPlaylist(): Playlist {
        val library = model.library
        val songs = listOf("Hush Test Three", "Guest Song A", "Hush Test One").map { song(it) }
        val name = "Hush Test Mix"
        val playlist = Playlist(
            id = LibrarySearch.fold(name),
            name = name,
            songs = songs,
            coverUri = null,
            coverSongs = songs.take(1),
            searchKey = LibrarySearch.key(name),
            songSearchKey = LibrarySearch.songsKey(songs),
            letter = LibraryAlphabet.section(name),
        )
        val setter = HushModel::class.java.getDeclaredMethod("setLibrary", Library::class.java).apply { isAccessible = true }
        compose.runOnUiThread { setter.invoke(model, library.copy(playlists = listOf(playlist))) }
        waitUntil("the test playlist in the library") { model.library.playlists.any { it.name == name } }
        compose.waitForIdle()
        return playlist
    }

    companion object {
        const val TAG = "HushTest"
        const val SCREENS = "/sdcard/Download/hush-screens"
        const val DEVICE_VIDEOS = "/data/local/tmp/hush-videos"
    }
}
