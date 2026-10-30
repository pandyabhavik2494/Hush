package com.pandyabhavik.hush.ui

import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.Crossfade
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.tween
import androidx.compose.animation.expandHorizontally
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.scaleOut
import androidx.compose.animation.shrinkHorizontally
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.slideOutVertically
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.windowInsetsTopHeight
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.grid.rememberLazyGridState
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.automirrored.rounded.QueueMusic
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.LibraryMusic
import androidx.compose.material.icons.rounded.Menu
import androidx.compose.material.icons.rounded.Mic
import androidx.compose.material.icons.rounded.MoreHoriz
import androidx.compose.material.icons.rounded.MusicNote
import androidx.compose.material.icons.rounded.Refresh
import androidx.compose.material.icons.rounded.Search
import androidx.compose.material.icons.rounded.Shuffle
import androidx.compose.material.icons.rounded.SmartDisplay
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.minimumInteractiveComponentSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.role
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.pandyabhavik.hush.HushModel
import com.pandyabhavik.hush.data.LibrarySearch
import com.pandyabhavik.hush.data.Playlist
import kotlinx.coroutines.launch

/** The Mac palette and type, used only by the wide (unfolded) layout. */
internal object Wide {
    val paper = Color(0xFF0A0A09)
    val panel = Color(0xFF141311)
    val surface = Color(0xFF161514)
    val ink = Color(0xFFF1EFE7)
    val muted = Color(0xFF9C9A95)
    val faint = Color(0xFF5E5C57)
    val gold = Color(0xFFC9A86B)
    val line = Color(0xFF2E2C28)
    val fill = ink.copy(alpha = 0.07f)
    val fillStroke = ink.copy(alpha = 0.09f)
    val bronze = Color(0xFF8F5724)
    val wine = Color(0xFF5C1F26)
    val ok = Color(0xFF7FB27A)

    val sidebarWidth = 216.dp
    val sideGutter = 28.dp

    /** Height of the large title that sits at the top of each section and shrinks into the toolbar. */
    val largeTitle = 64.dp

    /** Room kept free at the bottom for the floating player bar (without the navigation bar). */
    val barRoom = 72.dp + 12.dp + 16.dp

    fun serif(size: TextUnit, color: Color = ink) =
        TextStyle(fontFamily = FontFamily.Serif, fontSize = size, color = color, fontWeight = FontWeight.Normal)

    fun sans(size: TextUnit, color: Color = ink, weight: FontWeight = FontWeight.Normal) =
        TextStyle(fontSize = size, color = color, fontWeight = weight)

    fun tnum(size: TextUnit, color: Color = muted, weight: FontWeight = FontWeight.Normal) =
        sans(size, color, weight).copy(fontFeatureSettings = "tnum")

    fun micro(color: Color = muted) =
        TextStyle(fontSize = 11.sp, color = color, fontWeight = FontWeight.Bold, letterSpacing = 0.9.sp)
}

/** The library sections in the sidebar. Names match [LibraryTab] so the compact layout shares the saved choice. */
internal enum class WideSection(val title: String, val placeholder: String, val icon: ImageVector) {
    Albums("Albums", "Find an album, artist or song", Icons.Rounded.LibraryMusic),
    Artists("Artists", "Find an artist or song", Icons.Rounded.Mic),
    Songs("Songs", "Find a song, artist or album", Icons.Rounded.MusicNote),
    Playlists("Playlists", "Find a playlist or song", Icons.AutoMirrored.Rounded.QueueMusic),
    Videos("Videos", "Find a video", Icons.Rounded.SmartDisplay),
}

/**
 * The unfolded Fold (600 dp and wider): a sidebar, a toolbar with a large title that shrinks as
 * you scroll, the library or a page, and a floating player bar. Now Playing and videos cover it all.
 */
@Composable
fun WideShell(model: HushModel, onAbout: () -> Unit) {
    val actions = LocalActions.current
    val stack = model.pages
    val prefs = model.prefs
    val scope = rememberCoroutineScope()

    // Read from the saved tab each time this layout comes back (not rememberSaveable), so a section
    // chosen on the other screen before folding or unfolding is the one shown here.
    var sectionName by remember {
        mutableStateOf(prefs.getString("tab", WideSection.Albums.name).takeIf { s -> WideSection.entries.any { it.name == s } } ?: WideSection.Albums.name)
    }
    val section = WideSection.valueOf(sectionName)
    var sidebar by rememberSaveable { mutableStateOf(prefs.getBoolean("wideSidebar", true)) }
    var upNextOpen by rememberSaveable { mutableStateOf(false) }
    var searching by rememberSaveable { mutableStateOf(false) }
    var queryText by rememberSaveable { mutableStateOf("") }
    val query = LibrarySearch.query(queryText)

    var sort by remember { mutableStateOf(runCatching { LibrarySort.valueOf(prefs.getString("sort", "Alphabetical")) }.getOrDefault(LibrarySort.Alphabetical)) }
    var artistSort by remember { mutableStateOf(runCatching { LibrarySort.valueOf(prefs.getString("artistSort", "Favorites")) }.getOrDefault(LibrarySort.Favorites)) }
    var showTitles by remember { mutableStateOf(prefs.getBoolean("wideTitles", true)) }

    val albumsState = rememberLazyGridState()
    val artistsState = rememberLazyGridState()
    val playlistsState = rememberLazyGridState()
    val videosState = rememberLazyGridState()
    val songsState = rememberLazyListState()
    val titlePx = with(LocalDensity.current) { Wide.largeTitle.toPx() }

    // How far the large title has scrolled away (0 = all there, 1 = gone into the toolbar).
    val collapsed by remember(section) {
        derivedStateOf {
            val (index, offset) = when (section) {
                WideSection.Albums -> albumsState.firstVisibleItemIndex to albumsState.firstVisibleItemScrollOffset
                WideSection.Artists -> artistsState.firstVisibleItemIndex to artistsState.firstVisibleItemScrollOffset
                WideSection.Playlists -> playlistsState.firstVisibleItemIndex to playlistsState.firstVisibleItemScrollOffset
                WideSection.Videos -> videosState.firstVisibleItemIndex to videosState.firstVisibleItemScrollOffset
                WideSection.Songs -> songsState.firstVisibleItemIndex to songsState.firstVisibleItemScrollOffset
            }
            if (index > 0) 1f else (offset / titlePx).coerceIn(0f, 1f)
        }
    }

    // These run later from clicks, through a memoized function reference (onSection = ::select):
    // read the section from its state when they run, never the `section` captured at composition,
    // or a tap on the section that was showing when the screen first composed is taken for a
    // tap on the current one and only scrolls to the top.
    fun currentSection() = WideSection.valueOf(sectionName)

    fun scrollToTop() = scope.launch {
        when (currentSection()) {
            WideSection.Albums -> albumsState.animateScrollToItem(0)
            WideSection.Artists -> artistsState.animateScrollToItem(0)
            WideSection.Playlists -> playlistsState.animateScrollToItem(0)
            WideSection.Videos -> videosState.animateScrollToItem(0)
            WideSection.Songs -> songsState.animateScrollToItem(0)
        }
    }

    fun closeSearch() {
        searching = false
        queryText = ""
    }

    fun select(target: WideSection) {
        model.playerOpen = false
        // Up Next floats over the content with a tap-to-close scrim: leaving it open would make the
        // next tap on the new section (a video, an album) only close the panel.
        upNextOpen = false
        val current = currentSection()
        if (target == current && stack.isEmpty()) {
            scrollToTop()
            return
        }
        stack.clear()
        if (target != current) closeSearch()
        sectionName = target.name
        prefs.putString("tab", target.name)
    }

    fun openPlaylistFromSidebar(playlist: Playlist) {
        model.playerOpen = false
        upNextOpen = false
        closeSearch()
        sectionName = WideSection.Playlists.name
        prefs.putString("tab", WideSection.Playlists.name)
        stack.clear()
        stack.add(Route.PlaylistPage(playlist.id))
    }

    val playlistsPicker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocumentTree()) { uri ->
        if (uri != null) model.setPlaylistsFolder(uri)
    }
    val videosPicker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocumentTree()) { uri ->
        if (uri != null) model.setVideosFolder(uri)
    }

    val playerOpen = model.playerOpen
    val video = model.video
    val hasSong = model.library.song(model.player.currentId) != null
    val navBottom = WindowInsets.navigationBars.asPaddingValues().calculateBottomPadding()
    val bottomPadding = if (hasSong) Wide.barRoom + navBottom else navBottom + 16.dp

    // Now Playing and the video player handle Back themselves while they are showing.
    BackHandler(enabled = !playerOpen && video == null && (upNextOpen || searching || stack.isNotEmpty())) {
        when {
            upNextOpen -> upNextOpen = false
            stack.isNotEmpty() -> stack.removeAt(stack.lastIndex)
            searching -> closeSearch()
        }
    }
    LaunchedEffect(hasSong) { if (!hasSong) upNextOpen = false }
    // Opening a page (Go to Album from the bar's menu, say) or a video closes the panel too.
    var shownDepth by remember { mutableIntStateOf(stack.size) }
    LaunchedEffect(stack.size, video) {
        if (stack.size != shownDepth || video != null) upNextOpen = false
        shownDepth = stack.size
    }

    Box(Modifier.fillMaxSize().background(Wide.paper)) {
        val covered = (playerOpen && hasSong) || video != null
        Row(if (covered) Modifier.fillMaxSize().clearAndSetSemantics { } else Modifier.fillMaxSize()) {
            AnimatedVisibility(
                visible = sidebar,
                enter = expandHorizontally(tween(260, easing = FastOutSlowInEasing)) + fadeIn(tween(200)),
                exit = shrinkHorizontally(tween(240, easing = FastOutSlowInEasing)) + fadeOut(tween(160)),
            ) {
                Sidebar(
                    model = model,
                    section = section,
                    selectedPlaylist = (stack.lastOrNull() as? Route.PlaylistPage)?.id,
                    bottomPadding = navBottom,
                    onAbout = onAbout,
                    onSection = ::select,
                    onPlaylist = ::openPlaylistFromSidebar,
                )
            }

            Box(Modifier.weight(1f).fillMaxHeight().clipToBounds()) {
                AnimatedContent(
                    targetState = stack.size to stack.lastOrNull(),
                    transitionSpec = {
                        if (targetState.first > initialState.first) {
                            (slideInHorizontally(tween(260)) { it / 6 } + fadeIn(tween(220))) togetherWith fadeOut(tween(140))
                        } else {
                            fadeIn(tween(180)) togetherWith (slideOutHorizontally(tween(240)) { it / 6 } + fadeOut(tween(180)))
                        }
                    },
                    label = "widePages",
                ) { (_, route) ->
                    val back: () -> Unit = { if (stack.isNotEmpty()) stack.removeAt(stack.lastIndex) }
                    val toggle = WideSidebarToggle(sidebar) { sidebar = !sidebar; prefs.putBoolean("wideSidebar", sidebar) }
                    when (route) {
                        null -> SectionArea(
                            model = model,
                            section = section,
                            collapsed = collapsed,
                            toggle = toggle,
                            searching = searching,
                            queryText = queryText,
                            onQuery = { queryText = it },
                            onSearch = { searching = true },
                            onCancelSearch = ::closeSearch,
                            sort = if (section == WideSection.Artists) artistSort else sort,
                            onSort = { option ->
                                if (section == WideSection.Artists) {
                                    artistSort = option; prefs.putString("artistSort", option.name)
                                } else {
                                    sort = option; prefs.putString("sort", option.name)
                                }
                                scrollToTop()
                            },
                            showTitles = showTitles,
                            onShowTitles = { showTitles = !showTitles; prefs.putBoolean("wideTitles", showTitles) },
                            onChoosePlaylists = { playlistsPicker.launch(null) },
                            onChooseVideos = { videosPicker.launch(null) },
                            onAbout = onAbout,
                        ) { shown, padding ->
                            when (shown) {
                                WideSection.Albums -> WideAlbums(model, query, sort, showTitles, albumsState, padding)
                                WideSection.Artists -> WideArtists(model, query, artistSort, artistsState, padding)
                                WideSection.Songs -> WideSongs(model, query, sort, songsState, padding)
                                WideSection.Playlists -> WidePlaylists(model, query, sort, showTitles, playlistsState, padding) {
                                    playlistsPicker.launch(null)
                                }
                                WideSection.Videos -> WideVideos(model, query, videosState, padding) { videosPicker.launch(null) }
                            }
                        }
                        is Route.AlbumPage -> WideAlbumPage(route.key, section.title, bottomPadding, toggle, back)
                        is Route.PlaylistPage -> WidePlaylistPage(route.id, section.title, bottomPadding, toggle, back)
                        is Route.ArtistPage -> WideArtistPage(route.id, section.title, bottomPadding, toggle, back)
                    }
                }

                // Up Next slides over the content from the right; tapping outside closes it.
                if (upNextOpen && hasSong) {
                    Box(
                        Modifier.fillMaxSize().padding(bottom = bottomPadding).background(Color.Black.copy(alpha = 0.25f))
                            .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null) { upNextOpen = false },
                    )
                }
                androidx.compose.animation.AnimatedVisibility(
                    visible = upNextOpen && hasSong,
                    enter = slideInHorizontally(tween(300, easing = FastOutSlowInEasing)) { it } + fadeIn(tween(240)),
                    exit = slideOutHorizontally(tween(260, easing = FastOutSlowInEasing)) { it } + fadeOut(tween(200)),
                    modifier = Modifier.align(Alignment.TopEnd),
                ) {
                    BoxWithConstraints(Modifier.fillMaxHeight().padding(bottom = bottomPadding)) {
                        Column(Modifier.width(minOf(360.dp, maxWidth)).fillMaxHeight()) {
                            // The panel draws its own background; this only carries it under the status bar.
                            Spacer(Modifier.fillMaxWidth().windowInsetsTopHeight(WindowInsets.statusBars).background(Wide.panel.copy(alpha = 0.96f)))
                            UpNextPanel(Modifier.fillMaxWidth().weight(1f), onClose = { upNextOpen = false })
                        }
                    }
                }

                androidx.compose.animation.AnimatedVisibility(
                    visible = hasSong && video == null,
                    enter = slideInVertically(tween(320)) { it } + fadeIn(tween(240)),
                    exit = slideOutVertically(tween(260)) { it } + fadeOut(tween(200)),
                    modifier = Modifier.align(Alignment.BottomCenter),
                ) {
                    Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.BottomCenter) {
                        PlayerBar(
                            upNextOpen = upNextOpen,
                            onToggleUpNext = { upNextOpen = !upNextOpen },
                            modifier = Modifier
                                .navigationBarsPadding()
                                .padding(start = 16.dp, end = 16.dp, bottom = 12.dp)
                                .widthIn(max = 980.dp)
                                .fillMaxWidth(),
                        )
                    }
                }
            }
        }

        AnimatedVisibility(
            visible = playerOpen && hasSong,
            enter = fadeIn(tween(350)) + scaleIn(tween(350, easing = FastOutSlowInEasing), initialScale = 0.985f),
            exit = fadeOut(tween(280)) + scaleOut(tween(280), targetScale = 0.985f),
        ) {
            NowPlaying(onClose = { actions.closePlayer() })
        }

        // The video player is drawn by HushRoot, above both layouts, so a change of width keeps it playing.
    }
}

/** The sidebar button, passed down so every toolbar can show or hide the sidebar. */
internal class WideSidebarToggle(val open: Boolean, val toggle: () -> Unit)

@Composable
internal fun WideSidebarButton(toggle: WideSidebarToggle) {
    WideIconButton(Icons.Rounded.Menu, if (toggle.open) "Hide sidebar" else "Show sidebar", tint = if (toggle.open) Wide.muted else Wide.ink) {
        toggle.toggle()
    }
}

// ---------------------------------------------------------------- Sidebar

@Composable
private fun Sidebar(
    model: HushModel,
    section: WideSection,
    selectedPlaylist: String?,
    bottomPadding: Dp,
    onAbout: () -> Unit,
    onSection: (WideSection) -> Unit,
    onPlaylist: (Playlist) -> Unit,
) {
    val library = model.library
    val player = model.player
    val playingPlaylist = remember(player.queue, library) {
        // The playlist whose songs are playing, in order: the queue started from it.
        val ids = player.queue
        library.playlists.firstOrNull { p -> p.songs.size == ids.size && p.songs.map { it.mediaId } == ids }?.id
    }
    Column(
        Modifier.width(Wide.sidebarWidth).fillMaxHeight()
            .background(Wide.panel)
            .drawBehind { drawRect(Wide.line, topLeft = Offset(size.width - 1.dp.toPx(), 0f), size = size.copy(width = 1.dp.toPx())) }
            .statusBarsPadding()
            .padding(start = 12.dp, end = 12.dp),
    ) {
        Text(
            "Hush",
            style = TextStyle(fontFamily = Hush.wordmark, fontSize = 28.sp, color = Wide.gold),
            modifier = Modifier.padding(top = 14.dp, bottom = 12.dp).clip(RoundedCornerShape(8.dp)).clickableQuiet(onAbout)
                .padding(horizontal = 10.dp, vertical = 6.dp),
        )
        LazyColumn(Modifier.weight(1f)) {
            item { SidebarHeader("LIBRARY", top = 4.dp) }
            items(WideSection.entries, key = { it.name }) { s ->
                val count = when (s) {
                    WideSection.Albums -> library.albums.size
                    WideSection.Artists -> 0
                    WideSection.Songs -> library.songs.size
                    WideSection.Playlists -> library.playlists.size
                    WideSection.Videos -> library.videos.size
                }
                SectionRow(s, selected = s == section && selectedPlaylist == null, count = count) { onSection(s) }
            }
            if (library.playlists.isNotEmpty()) {
                item { SidebarHeader("PLAYLISTS", top = 20.dp) }
                items(library.playlists, key = { "pl-${it.id}" }) { playlist ->
                    PlaylistRow(
                        playlist,
                        selected = playlist.id == selectedPlaylist,
                        playing = playlist.id == playingPlaylist,
                        isPlaying = player.isPlaying,
                    ) { onPlaylist(playlist) }
                }
            }
            item { Spacer(Modifier.height(12.dp)) }
        }
        SidebarFooter(model, Modifier.padding(bottom = bottomPadding))
    }
}

@Composable
private fun SidebarHeader(text: String, top: Dp) {
    Text(
        text,
        style = TextStyle(fontSize = 10.5.sp, color = Wide.muted, fontWeight = FontWeight.Bold, letterSpacing = 0.85.sp),
        modifier = Modifier.padding(start = 10.dp, end = 10.dp, top = top, bottom = 6.dp),
    )
}

@Composable
private fun SectionRow(section: WideSection, selected: Boolean, count: Int, onClick: () -> Unit) {
    Row(
        Modifier.padding(vertical = 1.dp).fillMaxWidth().height(48.dp)
            .clip(RoundedCornerShape(10.dp))
            .background(if (selected) Wide.gold.copy(alpha = 0.16f) else Color.Transparent)
            .clickableQuiet(onClick)
            .padding(horizontal = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(section.icon, contentDescription = null, tint = if (selected) Wide.gold else Wide.ink.copy(alpha = 0.55f), modifier = Modifier.size(20.dp))
        Spacer(Modifier.width(12.dp))
        Text(
            section.title,
            style = Wide.sans(15.sp, if (selected) Wide.ink else Wide.ink.copy(alpha = 0.84f), if (selected) FontWeight.SemiBold else FontWeight.Medium),
            maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f),
        )
        if (count > 0) Text("%,d".format(count), style = Wide.tnum(11.5.sp), maxLines = 1)
    }
}

@Composable
private fun PlaylistRow(playlist: Playlist, selected: Boolean, playing: Boolean, isPlaying: Boolean, onClick: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().height(48.dp)
            .clip(RoundedCornerShape(10.dp))
            .background(if (selected) Wide.gold.copy(alpha = 0.16f) else Color.Transparent)
            .clickableQuiet(onClick)
            .padding(horizontal = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        PlaylistCover(playlist, Modifier.size(28.dp), 5.dp)
        Spacer(Modifier.width(10.dp))
        Text(
            playlist.name,
            style = Wide.sans(14.sp, if (selected) Wide.ink else Wide.ink.copy(alpha = 0.78f)),
            maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f),
        )
        if (playing) {
            Spacer(Modifier.width(6.dp))
            Equalizer(isPlaying, Modifier.size(width = 10.dp, height = 10.dp), color = Wide.gold)
        }
    }
}

@Composable
private fun SidebarFooter(model: HushModel, modifier: Modifier) {
    val busy = model.refreshing || !model.loaded
    Row(
        modifier.fillMaxWidth()
            .drawBehind { drawRect(Wide.line, size = size.copy(height = 1.dp.toPx())) }
            .padding(start = 10.dp, top = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(Modifier.size(7.dp).background(if (busy) Wide.gold else Wide.ok, CircleShape))
        Spacer(Modifier.width(8.dp))
        Text(
            if (busy) "Reading your music…" else "Library up to date",
            style = Wide.sans(12.sp, Wide.muted), maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f),
        )
        WideIconButton(Icons.Rounded.Refresh, "Refresh", tint = Wide.ink.copy(alpha = 0.7f), size = 18.dp) { model.refresh() }
    }
}

// ---------------------------------------------------------------- Section area (toolbar + content)

@Composable
private fun SectionArea(
    model: HushModel,
    section: WideSection,
    collapsed: Float,
    toggle: WideSidebarToggle,
    searching: Boolean,
    queryText: String,
    onQuery: (String) -> Unit,
    onSearch: () -> Unit,
    onCancelSearch: () -> Unit,
    sort: LibrarySort,
    onSort: (LibrarySort) -> Unit,
    showTitles: Boolean,
    onShowTitles: () -> Unit,
    onChoosePlaylists: () -> Unit,
    onChooseVideos: () -> Unit,
    onAbout: () -> Unit,
    content: @Composable (WideSection, PaddingValues) -> Unit,
) {
    val navBottom = WindowInsets.navigationBars.asPaddingValues().calculateBottomPadding()
    val hasSong = model.library.song(model.player.currentId) != null
    val bottom = if (hasSong) Wide.barRoom + navBottom else navBottom + 16.dp
    Box(Modifier.fillMaxSize().ambientLight()) {
        Column(Modifier.fillMaxSize()) {
            Row(
                Modifier.fillMaxWidth()
                    .drawBehind {
                        if (collapsed > 0f) {
                            drawRect(Wide.paper.copy(alpha = 0.9f * collapsed))
                            drawRect(Wide.line.copy(alpha = collapsed), topLeft = Offset(0f, size.height - 1.dp.toPx()), size = size.copy(height = 1.dp.toPx()))
                        }
                    }
                    .statusBarsPadding()
                    .height(60.dp)
                    .padding(start = 8.dp, end = 12.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                WideSidebarButton(toggle)
                // The small title appears as the large one scrolls away. Only the sidebar carries
                // the section names as text, so each name is on screen once.
                Text(
                    section.title,
                    style = Wide.serif(20.sp),
                    maxLines = 1, overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.padding(start = 6.dp).alpha(if (searching) 0f else collapsed)
                        .weight(1f, fill = false).clearAndSetSemantics { },
                )
                Spacer(Modifier.weight(1f).widthIn(min = 8.dp))
                if (section == WideSection.Songs && !searching) {
                    val songs = model.library.songs
                    if (songs.isNotEmpty()) {
                        WideCapsule("Shuffle All", Icons.Rounded.Shuffle, primary = true, height = 40.dp) { model.player.playShuffled(songs) }
                        Spacer(Modifier.width(8.dp))
                    }
                }
                if (searching) {
                    ToolbarSearch(queryText, section.placeholder, onQuery, onCancelSearch, Modifier.weight(3f, fill = false).widthIn(min = 160.dp, max = 320.dp))
                } else {
                    WideIconButton(Icons.Rounded.Search, "Search", onClick = onSearch)
                }
                Box {
                    var open by remember { mutableStateOf(false) }
                    WideIconButton(Icons.Rounded.MoreHoriz, "Options") { open = true }
                    HushMenu(open, { open = false }) {
                        val options = when (section) {
                            WideSection.Artists -> listOf(LibrarySort.Favorites, LibrarySort.MostSongs, LibrarySort.Alphabetical, LibrarySort.MostPlayed)
                            WideSection.Videos -> emptyList()
                            else -> listOf(LibrarySort.Alphabetical, LibrarySort.MostPlayed)
                        }
                        for (option in options) {
                            HushMenuItem(option.label, checked = option == sort) { open = false; onSort(option) }
                        }
                        if (section == WideSection.Albums || section == WideSection.Playlists) {
                            HushMenuItem("Show Titles", checked = showTitles) { open = false; onShowTitles() }
                        }
                        if (options.isNotEmpty()) HushMenuDivider()
                        HushMenuItem("Choose Playlists Folder…") { open = false; onChoosePlaylists() }
                        HushMenuItem("Choose Videos Folder…") { open = false; onChooseVideos() }
                        HushMenuDivider()
                        HushMenuItem("Refresh Library") { open = false; model.refresh() }
                        HushMenuItem("About Hush") { open = false; onAbout() }
                    }
                }
            }
            Box(Modifier.weight(1f).fillMaxWidth().clipToBounds()) {
                if (!model.loaded) {
                    Loading()
                } else {
                    Crossfade(section, label = "section") { shown ->
                        content(shown, PaddingValues(top = 0.dp, bottom = bottom))
                    }
                }
            }
        }
    }
}

/** The quiet gold, bronze and wine light at the top of every section (Mac's ambient light). */
private fun Modifier.ambientLight(): Modifier = drawBehind {
    val w = size.width
    val h = minOf(520.dp.toPx(), size.height)
    fun glow(color: Color, x: Float, y: Float, a: Float, radius: Float) {
        drawRect(
            Brush.radialGradient(
                0f to color.copy(alpha = a), 0.5f to color.copy(alpha = a * 0.3f), 1f to Color.Transparent,
                center = Offset(w * x, h * y), radius = radius,
            ),
            size = size.copy(height = h),
        )
    }
    glow(Wide.gold, 0.12f, -0.02f, 0.20f, w * 0.85f)
    glow(Wide.bronze, 0.92f, 0.06f, 0.24f, w * 0.8f)
    glow(Wide.wine, 0.5f, 0.42f, 0.18f, w * 0.7f)
    // Fade the light into the paper below.
    drawRect(
        Brush.verticalGradient(0f to Color.Transparent, 0.55f to Wide.paper.copy(alpha = 0.4f), 1f to Wide.paper, startY = 0f, endY = h),
        size = size.copy(height = h),
    )
}

@Composable
private fun Loading() {
    Column(Modifier.fillMaxSize().padding(top = 120.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        CircularProgressIndicator(color = Wide.gold, strokeWidth = 2.dp, modifier = Modifier.size(24.dp))
        Spacer(Modifier.height(14.dp))
        Text("Reading your music", style = Wide.sans(14.sp, Wide.muted))
    }
}

@Composable
private fun ToolbarSearch(text: String, placeholder: String, onChange: (String) -> Unit, onCancel: () -> Unit, modifier: Modifier) {
    val focus = remember { FocusRequester() }
    val focusManager = LocalFocusManager.current
    LaunchedEffect(Unit) { focus.requestFocus() }
    var focused by remember { mutableStateOf(false) }
    Row(verticalAlignment = Alignment.CenterVertically, modifier = modifier) {
        Row(
            Modifier.weight(1f).height(40.dp)
                .background(Wide.fill, RoundedCornerShape(20.dp))
                .border(1.dp, if (focused) Wide.gold.copy(alpha = 0.55f) else Wide.fillStroke, RoundedCornerShape(20.dp))
                .padding(start = 12.dp, end = 2.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(Icons.Rounded.Search, contentDescription = null, tint = Wide.ink.copy(alpha = 0.75f), modifier = Modifier.size(18.dp))
            Spacer(Modifier.width(8.dp))
            Box(Modifier.weight(1f), contentAlignment = Alignment.CenterStart) {
                if (text.isEmpty()) Text(placeholder, style = Wide.sans(14.sp, Wide.muted), maxLines = 1, overflow = TextOverflow.Ellipsis)
                BasicTextField(
                    text, onChange,
                    singleLine = true,
                    textStyle = Wide.sans(14.sp),
                    cursorBrush = SolidColor(Wide.gold),
                    modifier = Modifier.fillMaxWidth().focusRequester(focus)
                        .onFocusChanged { focused = it.isFocused },
                )
            }
            if (text.isNotEmpty()) {
                Box(
                    Modifier.size(36.dp).clip(CircleShape).clickableQuiet { onChange("") },
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(Icons.Rounded.Close, contentDescription = "Clear search", tint = Wide.muted, modifier = Modifier.size(16.dp))
                }
            }
        }
        Text(
            "Cancel",
            style = Wide.sans(15.sp, Wide.ink),
            maxLines = 1,
            modifier = Modifier.padding(start = 4.dp).clip(RoundedCornerShape(24.dp)).clickableQuiet {
                focusManager.clearFocus()
                onCancel()
            }.padding(horizontal = 10.dp, vertical = 14.dp),
        )
    }
}

// ---------------------------------------------------------------- Shared pieces

/**
 * The big serif section title with its count, the first item of every section's list. It
 * scrolls with the content, and the toolbar's small title fades in as it goes.
 */
@Composable
internal fun WideLargeTitle(title: String, count: Int?, modifier: Modifier = Modifier) {
    Row(
        modifier.fillMaxWidth().height(Wide.largeTitle).clearAndSetSemantics { heading(); contentDescription = title },
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(title, style = Wide.serif(34.sp).copy(letterSpacing = (-0.3).sp), maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, fill = false))
        if (count != null && count > 0) {
            Spacer(Modifier.width(12.dp))
            WideCount(count)
        }
    }
}

@Composable
internal fun WideCount(count: Int) {
    Text(
        "%,d".format(count),
        style = Wide.tnum(12.sp, Wide.ink.copy(alpha = 0.9f), FontWeight.SemiBold),
        modifier = Modifier
            .background(Wide.fill, RoundedCornerShape(50))
            .border(1.dp, Wide.ink.copy(alpha = 0.08f), RoundedCornerShape(50))
            .padding(horizontal = 10.dp, vertical = 4.dp),
    )
}

/** Gold (primary) or quiet (secondary) capsule button with an icon and a label. */
@Composable
internal fun WideCapsule(
    label: String,
    icon: ImageVector,
    primary: Boolean,
    modifier: Modifier = Modifier,
    height: Dp = 48.dp,
    onClick: () -> Unit,
) {
    val shape = RoundedCornerShape(50)
    Row(
        modifier
            .minimumInteractiveComponentSize()
            .height(height)
            .clip(shape)
            .then(
                if (primary) Modifier.background(Wide.gold)
                else Modifier.background(Wide.ink.copy(alpha = 0.08f)).border(1.dp, Wide.ink.copy(alpha = 0.12f), shape),
            )
            .clickableQuiet(onClick)
            .padding(horizontal = 20.dp),
        horizontalArrangement = Arrangement.Center,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        val color = if (primary) Wide.paper else Wide.ink
        Icon(icon, contentDescription = null, tint = color, modifier = Modifier.size(18.dp))
        Spacer(Modifier.width(7.dp))
        Text(label, style = Wide.sans(15.sp, color, FontWeight.SemiBold), maxLines = 1)
    }
}

/** An icon button with a 48 dp touch target. */
@Composable
internal fun WideIconButton(
    icon: ImageVector,
    description: String,
    tint: Color = Wide.ink,
    size: Dp = 22.dp,
    onClick: () -> Unit,
) {
    Box(
        Modifier.size(48.dp).clip(CircleShape).clickableQuiet(onClick),
        contentAlignment = Alignment.Center,
    ) {
        Icon(icon, contentDescription = description, tint = tint, modifier = Modifier.size(size))
    }
}

/** A round button (34–44 dp visual) with a fill; gold when on. */
@Composable
internal fun WideCircleButton(icon: ImageVector, description: String, on: Boolean = false, diameter: Dp = 44.dp, onClick: () -> Unit) {
    Box(Modifier.size(maxOf(diameter, 48.dp)).clip(CircleShape).clickableQuiet(onClick), contentAlignment = Alignment.Center) {
        Box(
            Modifier.size(diameter)
                .background(if (on) Wide.gold.copy(alpha = 0.16f) else Wide.fill, CircleShape)
                .border(1.dp, Wide.fillStroke, CircleShape),
            contentAlignment = Alignment.Center,
        ) {
            Icon(icon, contentDescription = description, tint = if (on) Wide.gold else Wide.ink.copy(alpha = 0.85f), modifier = Modifier.size(diameter * 0.44f))
        }
    }
}

/** Equalizer bars in a small dark circle, for a cover whose music is playing. */
@Composable
internal fun WidePlayingBadge(isPlaying: Boolean, modifier: Modifier = Modifier) {
    Box(modifier.size(28.dp).background(Wide.paper.copy(alpha = 0.6f), CircleShape), contentAlignment = Alignment.Center) {
        Equalizer(isPlaying, Modifier.size(12.dp), color = Wide.gold)
    }
}

/** A tappable label with a back chevron: the section name the page was opened from. */
@Composable
internal fun WideBackCrumb(section: String, onBack: () -> Unit) {
    Row(
        Modifier.height(48.dp).clip(RoundedCornerShape(24.dp))
            .clearAndSetSemantics {
                contentDescription = "Back"
                role = Role.Button
                onClick { onBack(); true }
            }
            .clickableQuiet(onBack)
            .padding(start = 6.dp, end = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(Icons.AutoMirrored.Rounded.ArrowBack, contentDescription = null, tint = Wide.gold, modifier = Modifier.size(22.dp))
        Spacer(Modifier.width(6.dp))
        Text(section, style = Wide.sans(15.sp, Wide.gold, FontWeight.Medium), maxLines = 1)
    }
}

/** Offsets content up by [px] pixels; used to scroll an overlaid title with a list it does not belong to. */
internal fun Modifier.wideScrollUp(px: () -> Int): Modifier = this.offset { IntOffset(0, -px()) }
