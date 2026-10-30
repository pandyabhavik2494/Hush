package com.pandyabhavik.hush.ui

import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.LinearOutSlowInEasing
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.animation.expandVertically
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.shrinkVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.border
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
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyGridState
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.itemsIndexed
import androidx.compose.foundation.lazy.grid.rememberLazyGridState
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.PagerState
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.PlaylistAdd
import androidx.compose.material.icons.automirrored.rounded.PlaylistPlay
import androidx.compose.material.icons.automirrored.rounded.QueueMusic
import androidx.compose.material.icons.rounded.BarChart
import androidx.compose.material.icons.rounded.Cancel
import androidx.compose.material.icons.rounded.Favorite
import androidx.compose.material.icons.rounded.FavoriteBorder
import androidx.compose.material.icons.rounded.FilterList
import androidx.compose.material.icons.rounded.Folder
import androidx.compose.material.icons.rounded.GraphicEq
import androidx.compose.material.icons.rounded.HeartBroken
import androidx.compose.material.icons.rounded.Refresh
import androidx.compose.material.icons.rounded.Search
import androidx.compose.material.icons.rounded.SortByAlpha
import androidx.compose.material.icons.rounded.Title
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.material3.pulltorefresh.PullToRefreshDefaults
import androidx.compose.material3.pulltorefresh.rememberPullToRefreshState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.lerp
import androidx.compose.ui.unit.max
import androidx.compose.ui.unit.sp
import com.pandyabhavik.hush.HushModel
import com.pandyabhavik.hush.data.Album
import com.pandyabhavik.hush.data.Artist
import com.pandyabhavik.hush.data.LibraryAlphabet
import com.pandyabhavik.hush.data.LibrarySearch
import com.pandyabhavik.hush.data.Playlist
import com.pandyabhavik.hush.data.Song
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch

enum class LibraryTab(val title: String, val placeholder: String) {
    Albums("Albums", "Find an album, artist or song"),
    Songs("Songs", "Find a song, artist or album"),
    Playlists("Playlists", "Find a playlist or song"),
    Artists("Artists", "Find an artist or song"),
    Videos("Videos", "Find a video"),
}

enum class LibrarySort(val label: String) {
    Favorites("Favorites"), MostSongs("Most songs"), Alphabetical("Alphabetical"), MostPlayed("Most played");

    val icon: ImageVector
        get() = when (this) {
            Favorites -> Icons.Rounded.Favorite
            MostSongs -> Icons.AutoMirrored.Rounded.QueueMusic
            Alphabetical -> Icons.Rounded.SortByAlpha
            MostPlayed -> Icons.Rounded.BarChart
        }

    companion object {
        /** Playlists are always A–Z and videos keep their own order, as on the iPhone. */
        fun options(tab: LibraryTab) =
            when (tab) {
                LibraryTab.Artists -> listOf(Favorites, MostSongs, Alphabetical, MostPlayed)
                LibraryTab.Videos, LibraryTab.Playlists -> emptyList()
                else -> listOf(Alphabetical, MostPlayed)
            }
    }
}

/** How many covers across: two on the cover screen, more on the big inner screen. */
fun gridColumns(width: Dp, artists: Boolean = false): Int = when {
    width < 600.dp -> if (artists) 3 else 2
    width < 900.dp -> if (artists) 5 else 4
    else -> if (artists) 6 else 5
}

/**
 * The space the library header covers at the top (and the mini player at the bottom). Library
 * pages scroll under the header, so empty states and scrollers read this to stay clear of it.
 */
val LocalLibraryInsets = compositionLocalOf { PaddingValues(0.dp) }

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LibraryScreen(model: HushModel, bottomPadding: Dp, onAbout: () -> Unit) {
    val scope = rememberCoroutineScope()
    val tabs = LibraryTab.entries
    val pager = rememberPagerState(initialPage = model.prefs.getString("tab", "Albums").let { saved ->
        tabs.indexOfFirst { it.name == saved }.coerceAtLeast(0)
    }) { tabs.size }
    val tab = tabs[pager.currentPage]
    LaunchedEffect(tab) { model.prefs.putString("tab", tab.name) }

    var sort by remember { mutableStateOf(runCatching { LibrarySort.valueOf(model.prefs.getString("sort", "Alphabetical")) }.getOrDefault(LibrarySort.Alphabetical)) }
    var artistSort by remember { mutableStateOf(runCatching { LibrarySort.valueOf(model.prefs.getString("artistSort", "Favorites")) }.getOrDefault(LibrarySort.Favorites)) }
    var showTitles by remember { mutableStateOf(model.prefs.getBoolean("showTitles", false)) }
    var searching by rememberSaveable { mutableStateOf(false) }
    var queryText by rememberSaveable { mutableStateOf("") }
    val query = LibrarySearch.query(queryText)

    val albumsState = rememberLazyGridState()
    val playlistsState = rememberLazyGridState()
    val artistsState = rememberLazyGridState()
    val videosState = rememberLazyGridState()
    val gridStates = remember(albumsState, playlistsState, artistsState, videosState) {
        mapOf(
            LibraryTab.Albums to albumsState,
            LibraryTab.Playlists to playlistsState,
            LibraryTab.Artists to artistsState,
            LibraryTab.Videos to videosState,
        )
    }
    val songsState = rememberLazyListState()

    // Where the selected tab's list is: drives the hairline and the collapsing tab titles. Read
    // only inside derived states and the small header pieces, so scrolling never recomposes the
    // whole screen (and with it every page of the pager).
    val density = LocalDensity.current
    val position: (LibraryTab) -> Pair<Int, Int> = remember(gridStates, songsState) {
        { t ->
            if (t == LibraryTab.Songs) songsState.firstVisibleItemIndex to songsState.firstVisibleItemScrollOffset
            else gridStates.getValue(t).let { it.firstVisibleItemIndex to it.firstVisibleItemScrollOffset }
        }
    }
    val listScrolling = remember(gridStates, songsState) {
        derivedStateOf {
            val t = tabs[pager.currentPage]
            if (t == LibraryTab.Songs) songsState.isScrollInProgress else gridStates.getValue(t).isScrollInProgress
        }
    }

    fun scrollToTop(t: LibraryTab) = scope.launch {
        if (t == LibraryTab.Songs) songsState.animateScrollToItem(0) else gridStates.getValue(t).animateScrollToItem(0)
    }

    val folderPicker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocumentTree()) { uri ->
        if (uri != null) model.setPlaylistsFolder(uri)
    }

    val videosPicker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocumentTree()) { uri ->
        if (uri != null) model.setVideosFolder(uri)
    }

    val focusManager = LocalFocusManager.current
    val keyboard = LocalSoftwareKeyboardController.current
    fun endSearch() {
        keyboard?.hide()
        focusManager.clearFocus()
        searching = false
        queryText = ""
    }
    // Only when the library is what's on screen: with a page, the player or a video on top, back
    // belongs to them (this handler is registered after the page stack's, so it would win).
    BackHandler(enabled = searching && model.pages.isEmpty() && !model.playerOpen && model.video == null) { endSearch() }
    // Lists put the keyboard away as soon as they move.
    LaunchedEffect(searching) {
        if (!searching) return@LaunchedEffect
        snapshotFlow { listScrolling.value }.collect { moving ->
            if (moving) {
                keyboard?.hide()
                focusManager.clearFocus()
            }
        }
    }
    // Tapping Search again (after a scroll put the keyboard away) brings the keyboard back.
    var focusTick by remember { mutableIntStateOf(0) }

    // The header's height is worked out, not fixed, so larger text never gets cut off.
    val statusTop = WindowInsets.statusBars.asPaddingValues().calculateTopPadding()
    val titleRow = max(48.dp, with(density) { (22.sp * 1.6f).toDp() })
    val searchRow = max(46.dp, with(density) { (16.sp * 1.45f).toDp() } + 22.dp)
    val stripFull = max(58.dp, with(density) { (31.sp * 1.45f).toDp() })
    val stripSmall = max(46.dp, with(density) { (24.sp * 1.45f).toDp() })
    val headerFull = statusTop + titleRow + (if (searching) searchRow else 0.dp) + stripFull

    CompositionLocalProvider(LocalLibraryInsets provides PaddingValues(top = headerFull, bottom = bottomPadding)) {
        Box(Modifier.fillMaxSize().background(Hush.paper)) {
            val pull = rememberPullToRefreshState()
            PullToRefreshBox(
                isRefreshing = model.refreshing,
                onRefresh = { model.refresh() },
                modifier = Modifier.fillMaxSize(),
                state = pull,
                indicator = {
                    PullToRefreshDefaults.Indicator(
                        state = pull,
                        isRefreshing = model.refreshing,
                        modifier = Modifier.align(Alignment.TopCenter).padding(top = headerFull),
                        containerColor = Hush.card,
                        color = Hush.ink,
                    )
                },
            ) {
                // The pages reach the top of the screen and scroll under the header.
                HorizontalPager(pager, Modifier.fillMaxSize(), beyondViewportPageCount = 1) { page ->
                    val padding = PaddingValues(top = headerFull + 12.dp, bottom = bottomPadding + 16.dp)
                    when (tabs[page]) {
                        LibraryTab.Albums -> AlbumsTab(model, query, sort, showTitles, gridStates.getValue(LibraryTab.Albums), padding)
                        LibraryTab.Songs -> SongsTab(
                            model, query, sort, songsState,
                            PaddingValues(top = headerFull + 4.dp, bottom = bottomPadding + 16.dp),
                        )
                        LibraryTab.Playlists -> PlaylistsTab(model, query, showTitles, gridStates.getValue(LibraryTab.Playlists), padding) {
                            folderPicker.launch(null)
                        }
                        LibraryTab.Artists -> ArtistsTab(model, query, artistSort, gridStates.getValue(LibraryTab.Artists), padding) {
                            artistSort = LibrarySort.MostSongs
                            model.prefs.putString("artistSort", LibrarySort.MostSongs.name)
                        }
                        LibraryTab.Videos -> VideosTab(model, query, gridStates.getValue(LibraryTab.Videos), padding) {
                            videosPicker.launch(null)
                        }
                    }
                }
            }

            // Header: opaque black, nothing shows through; a hairline once the list has moved.
            Column(Modifier.fillMaxWidth().background(Hush.paper).blockTouches()) {
                Spacer(Modifier.height(statusTop))
                Row(
                    Modifier.fillMaxWidth().height(titleRow).padding(start = Hush.sideMargin, end = 4.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Box(Modifier.heightIn(min = 48.dp).clickableQuiet(onAbout), contentAlignment = Alignment.CenterStart) {
                        Text("Hush", style = TextStyle(fontFamily = Hush.wordmark, fontSize = 22.sp, color = Hush.ink))
                    }
                    Spacer(Modifier.weight(1f))
                    PlainIconButton(Icons.Rounded.Search, "Search", size = 23.dp) {
                        searching = true
                        focusTick++
                    }
                    Box {
                        var options by remember { mutableStateOf(false) }
                        PlainIconButton(Icons.Rounded.FilterList, "Options", size = 23.dp) { options = true }
                        OptionsMenu(
                            expanded = options,
                            onDismiss = { options = false },
                            tab = tab,
                            current = if (tab == LibraryTab.Artists) artistSort else sort,
                            showTitles = showTitles,
                            onSort = { option ->
                                if (tab == LibraryTab.Artists) {
                                    artistSort = option; model.prefs.putString("artistSort", option.name)
                                } else {
                                    sort = option; model.prefs.putString("sort", option.name)
                                }
                                scrollToTop(tab)
                            },
                            onShowTitles = {
                                showTitles = !showTitles
                                model.prefs.putBoolean("showTitles", showTitles)
                            },
                            onRefresh = { model.refresh() },
                            onPlaylistsFolder = { folderPicker.launch(null) },
                            onVideosFolder = { videosPicker.launch(null) },
                        )
                    }
                }
                AnimatedVisibility(
                    searching,
                    enter = fadeIn(tween(200, easing = LinearOutSlowInEasing)) + expandVertically(tween(200, easing = LinearOutSlowInEasing)),
                    exit = fadeOut(tween(200, easing = LinearOutSlowInEasing)) + shrinkVertically(tween(200, easing = LinearOutSlowInEasing)),
                ) {
                    SearchField(queryText, tab.placeholder, searchRow, focusTick, onChange = { queryText = it }, onCancel = { endSearch() })
                }
                CollapsingTabs(tabs, pager, position, stripFull, stripSmall) { index ->
                    if (index == pager.currentPage) scrollToTop(tabs[index])
                    else scope.launch { pager.animateScrollToPage(index, animationSpec = Hush.snappy) }
                }
            }
        }
    }
}

@Composable
private fun OptionsMenu(
    expanded: Boolean,
    onDismiss: () -> Unit,
    tab: LibraryTab,
    current: LibrarySort,
    showTitles: Boolean,
    onSort: (LibrarySort) -> Unit,
    onShowTitles: () -> Unit,
    onRefresh: () -> Unit,
    onPlaylistsFolder: () -> Unit,
    onVideosFolder: () -> Unit,
) {
    HushMenu(expanded, onDismiss) {
        val options = LibrarySort.options(tab)
        if (options.isNotEmpty()) {
            Text(
                "Sort", style = Hush.sans(13.sp, Hush.muted),
                modifier = Modifier.padding(start = 16.dp, end = 16.dp, top = 6.dp, bottom = 2.dp),
            )
            for (option in options) {
                HushMenuItem(option.label, option.icon, checked = option == current) {
                    onDismiss()
                    if (option != current) onSort(option)
                }
            }
        }
        if (tab == LibraryTab.Albums || tab == LibraryTab.Playlists) {
            if (options.isNotEmpty()) HushMenuDivider()
            HushMenuItem("Show Titles", Icons.Rounded.Title, checked = showTitles) { onShowTitles(); onDismiss() }
        }
        if (tab == LibraryTab.Artists) {
            HushMenuDivider()
            HushMenuItem("Look for Missing Photos", Icons.Rounded.Refresh) { onDismiss(); onRefresh() }
        }
        if (tab == LibraryTab.Playlists) {
            HushMenuItem("Choose Playlists Folder…", Icons.Rounded.Folder) { onDismiss(); onPlaylistsFolder() }
        }
        if (tab == LibraryTab.Videos) {
            HushMenuItem("Choose Videos Folder…", Icons.Rounded.Folder) { onDismiss(); onVideosFolder() }
        }
    }
}

/**
 * The tab strip and the hairline under it. The titles shrink as the list scrolls; that animation
 * is read here only, so it recomposes this strip and nothing else.
 */
@Composable
private fun CollapsingTabs(
    tabs: List<LibraryTab>,
    pager: PagerState,
    position: (LibraryTab) -> Pair<Int, Int>,
    stripFull: Dp,
    stripSmall: Dp,
    onSelect: (Int) -> Unit,
) {
    val collapseRange = with(LocalDensity.current) { 32.dp.toPx() }
    val scrolled by remember(position) {
        derivedStateOf { position(tabs[pager.currentPage]).let { (i, o) -> i > 0 || o > 1 } }
    }
    val collapseTarget by remember(position, collapseRange) {
        derivedStateOf {
            val (i, o) = position(tabs[pager.currentPage])
            if (i > 0) 1f else (o / collapseRange).coerceIn(0f, 1f)
        }
    }
    val collapse by animateFloatAsState(collapseTarget, spring(dampingRatio = 1f, stiffness = 1500f), label = "collapse")
    TabsRow(
        tabs, pager.currentPage,
        height = lerp(stripFull, stripSmall, collapse),
        fontSize = 31f + (24f - 31f) * collapse,
        onSelect = onSelect,
    )
    Box(Modifier.fillMaxWidth().height(1.dp).background(if (scrolled) Hush.line else Color.Transparent))
}

/** Serif words for the sections; the chosen one in ink, the rest dim. No underline. */
@Composable
private fun TabsRow(tabs: List<LibraryTab>, selected: Int, height: Dp, fontSize: Float, onSelect: (Int) -> Unit) {
    val state = rememberLazyListState()
    var placed by remember { mutableStateOf(false) }
    // Keep the chosen tab in the middle: at once the first time, then with a snappy glide.
    LaunchedEffect(selected) {
        snapshotFlow { state.layoutInfo.visibleItemsInfo.isNotEmpty() }.first { it }
        state.centerItem(selected, animate = placed)
        placed = true
    }
    LazyRow(
        state = state,
        modifier = Modifier.fillMaxWidth().height(height).testTag("tabs"),
        contentPadding = PaddingValues(horizontal = Hush.sideMargin),
        horizontalArrangement = Arrangement.spacedBy(24.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        itemsIndexed(tabs) { index, tab ->
            val color by animateColorAsState(
                if (index == selected) Hush.ink else Hush.tabIdle,
                tween(200, easing = FastOutSlowInEasing),
                label = "tab",
            )
            Box(
                Modifier.fillMaxHeight().heightIn(min = 48.dp).pressable(scale = 1f, dim = 0.6f) { onSelect(index) },
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    tab.title,
                    style = Hush.serifTitle(fontSize.sp, color = color),
                    maxLines = 1,
                    softWrap = false,
                )
            }
        }
    }
}

@Composable
private fun SearchField(text: String, placeholder: String, rowHeight: Dp, focusTick: Int, onChange: (String) -> Unit, onCancel: () -> Unit) {
    val focus = remember { FocusRequester() }
    val keyboard = LocalSoftwareKeyboardController.current
    LaunchedEffect(focusTick) {
        runCatching { focus.requestFocus() }
        keyboard?.show()
    }
    Row(
        Modifier.fillMaxWidth().heightIn(min = rowHeight).padding(start = Hush.sideMargin, end = 8.dp, top = 2.dp, bottom = 4.dp),
        horizontalArrangement = Arrangement.spacedBy(4.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Row(
            Modifier.weight(1f).heightIn(min = 40.dp).background(Hush.card, RoundedCornerShape(12.dp)).padding(start = 12.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(Icons.Rounded.Search, null, tint = Hush.muted, modifier = Modifier.size(18.dp))
            Box(Modifier.weight(1f).padding(vertical = 8.dp), contentAlignment = Alignment.CenterStart) {
                if (text.isEmpty()) Text(placeholder, style = Hush.sans(16.sp, Hush.muted), maxLines = 1, overflow = TextOverflow.Ellipsis)
                BasicTextField(
                    text, onChange,
                    singleLine = true,
                    textStyle = Hush.sans(16.sp),
                    cursorBrush = SolidColor(Hush.ink),
                    keyboardOptions = KeyboardOptions(
                        capitalization = KeyboardCapitalization.None,
                        autoCorrectEnabled = false,
                        imeAction = ImeAction.Search,
                    ),
                    keyboardActions = KeyboardActions(onSearch = { keyboard?.hide() }),
                    modifier = Modifier.fillMaxWidth().focusRequester(focus),
                )
            }
            if (text.isNotEmpty()) {
                Box(Modifier.size(36.dp, 40.dp).clickableQuiet { onChange("") }, contentAlignment = Alignment.Center) {
                    Icon(Icons.Rounded.Cancel, "Clear", tint = Hush.muted, modifier = Modifier.size(18.dp))
                }
            } else {
                Spacer(Modifier.size(4.dp))
            }
        }
        Box(Modifier.heightIn(min = 48.dp).clickableQuiet(onCancel).padding(horizontal = 12.dp), contentAlignment = Alignment.Center) {
            Text("Cancel", style = Hush.sans(16.sp), maxLines = 1)
        }
    }
}

private fun <T> byPlays(items: List<T>, plays: (T) -> Int): List<T> =
    items.withIndex().sortedWith(compareByDescending<IndexedValue<T>> { plays(it.value) }.thenBy { it.index }).map { it.value }

/**
 * A quiet centred message: a light icon, a serif title, a few muted words and maybe a capsule
 * button. It scrolls, so pull-to-refresh works on it, and stays clear of the library header.
 */
@Composable
fun EmptyMessage(title: String, detail: String, action: Pair<String, () -> Unit>? = null, icon: ImageVector? = null) {
    val insets = LocalLibraryInsets.current
    BoxWithConstraints(Modifier.fillMaxSize()) {
        val minHeight = maxHeight
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState())) {
            Column(
                Modifier.fillMaxWidth().heightIn(min = minHeight).padding(insets).padding(28.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(12.dp, Alignment.CenterVertically),
            ) {
                if (icon != null) Icon(icon, null, tint = Hush.accent.copy(alpha = 0.82f), modifier = Modifier.size(34.dp))
                Text(title, style = Hush.serif(21.sp), textAlign = TextAlign.Center)
                Text(detail, style = Hush.sans(14.sp, Hush.muted), textAlign = TextAlign.Center, modifier = Modifier.widthIn(max = 290.dp))
                if (action != null) AccentCapsule(action.first, Modifier.padding(top = 4.dp), action.second)
            }
        }
    }
}

/** While the library is first read. */
@Composable
private fun LoadingMessage() {
    val insets = LocalLibraryInsets.current
    Column(
        Modifier.fillMaxSize().padding(insets),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(12.dp, Alignment.CenterVertically),
    ) {
        CircularProgressIndicator(color = Hush.accent, strokeWidth = 2.dp, modifier = Modifier.size(26.dp))
        Text("Gathering your music", style = Hush.sans(13.sp, Hush.muted))
    }
}

/** A grid of covers with the fast-scroll strip on its right edge. */
@Composable
fun LibraryGrid(
    state: LazyGridState,
    columns: Int,
    padding: PaddingValues,
    targets: List<Pair<String, Int>>,
    spacing: Dp = 14.dp,
    rowSpacing: Dp = 14.dp,
    // Keep the right column clear of the A–Z strip. Off by default under the compact library
    // header (its look is the iPhone's); on by default elsewhere (the wide screen's videos).
    reserveScroller: Boolean = LocalLibraryInsets.current.calculateTopPadding() == 0.dp,
    content: androidx.compose.foundation.lazy.grid.LazyGridScope.() -> Unit,
) {
    val insets = LocalLibraryInsets.current
    // Without the compact header's insets, the strip starts where the grid's content does, so it
    // never runs over a title drawn above the grid.
    val scrollerTop = if (insets.calculateTopPadding() == 0.dp) padding.calculateTopPadding() else insets.calculateTopPadding()
    val scrollerBottom = if (insets.calculateBottomPadding() == 0.dp) padding.calculateBottomPadding() else insets.calculateBottomPadding()
    val end = if (reserveScroller && targets.size >= 2) max(Hush.sideMargin, 36.dp) else Hush.sideMargin
    Box(Modifier.fillMaxSize()) {
        LazyVerticalGrid(
            columns = GridCells.Fixed(columns),
            state = state,
            contentPadding = PaddingValues(
                start = Hush.sideMargin, end = end,
                top = padding.calculateTopPadding(), bottom = padding.calculateBottomPadding(),
            ),
            horizontalArrangement = Arrangement.spacedBy(spacing),
            verticalArrangement = Arrangement.spacedBy(rowSpacing),
            modifier = Modifier.fillMaxSize(),
            content = content,
        )
        FastScroller(state, targets, top = scrollerTop, bottom = scrollerBottom, columns = columns)
    }
}

@Composable
private fun AlbumsTab(model: HushModel, query: String, sort: LibrarySort, showTitles: Boolean, state: LazyGridState, padding: PaddingValues) {
    val library = model.library
    val albums = remember(library, query, sort, model.playCounts) {
        val found = LibrarySearch.filterByNameThenSongs(library.albums, query, Album::searchKey, Album::songSearchKey)
        if (sort == LibrarySort.MostPlayed) byPlays(found) { a -> a.songs.sumOf { model.playCounts[it.id] ?: 0 } } else found
    }
    when {
        !model.loaded -> return LoadingMessage()
        library.songs.isEmpty() -> return EmptyMessage(
            "A quiet start", "Hush plays the songs saved on this phone. Copy your music over, and it appears here.",
            icon = Icons.Rounded.GraphicEq,
        )
        albums.isEmpty() -> return EmptyMessage("Nothing found", "Try another song, album, or artist.", icon = Icons.Rounded.Search)
    }
    val actions = LocalActions.current
    val player = model.player
    val currentAlbum = library.song(player.currentId)?.albumKey
    val rowSpacing by animateDpAsState(if (showTitles) 22.dp else 14.dp, tween(200, easing = FastOutSlowInEasing), label = "rows")
    BoxWithConstraints {
        val targets = if (sort == LibrarySort.Alphabetical && query.isEmpty()) letterTargets(albums, Album::letter) else emptyList()
        LibraryGrid(state, gridColumns(maxWidth), padding, targets, rowSpacing = rowSpacing) {
            itemsIndexed(albums, key = { _, a -> a.key }) { _, album ->
                CoverTile(
                    onClick = { actions.open(Route.AlbumPage(album.key)) }, menuSongs = album.songs,
                    title = album.title, subtitle = album.artist, showTitle = showTitles,
                    playing = if (album.key == currentAlbum) player.isPlaying else null,
                ) {
                    Cover(album.cover, Modifier.fillMaxWidth(), Hush.tileRadius)
                }
            }
        }
    }
}

@Composable
private fun PlaylistsTab(
    model: HushModel, query: String, showTitles: Boolean,
    state: LazyGridState, padding: PaddingValues, chooseFolder: () -> Unit,
) {
    val library = model.library
    val playlists = remember(library, query) {
        LibrarySearch.filterByNameThenSongs(library.playlists, query, Playlist::searchKey, Playlist::songSearchKey)
    }
    when {
        !model.loaded -> return LoadingMessage()
        library.playlists.isEmpty() && model.playlistsFolder == null -> return EmptyMessage(
            "Your playlists",
            "Copy the Playlists folder from your Mac onto the phone, then choose it here. Hush reads the playlist files in it.",
            "Choose Playlists Folder" to chooseFolder,
            icon = Icons.AutoMirrored.Rounded.QueueMusic,
        )
        library.playlists.isEmpty() -> return EmptyMessage(
            "No playlists yet",
            "Hush found no playlist files (.m3u8) with songs from this phone in that folder. Pull down to check again.",
            "Choose Another Folder" to chooseFolder,
            icon = Icons.AutoMirrored.Rounded.QueueMusic,
        )
        playlists.isEmpty() -> return EmptyMessage("No playlists found", "Try another playlist or song name.", icon = Icons.Rounded.Search)
    }
    val actions = LocalActions.current
    val rowSpacing by animateDpAsState(if (showTitles) 22.dp else 14.dp, tween(200, easing = FastOutSlowInEasing), label = "rows")
    BoxWithConstraints {
        val targets = if (query.isEmpty()) letterTargets(playlists, Playlist::letter) else emptyList()
        LibraryGrid(state, gridColumns(maxWidth), padding, targets, rowSpacing = rowSpacing) {
            itemsIndexed(playlists, key = { _, p -> p.id }) { _, playlist ->
                CoverTile(
                    onClick = { actions.open(Route.PlaylistPage(playlist.id)) }, menuSongs = playlist.songs,
                    title = playlist.name, subtitle = songCount(playlist.songs.size), showTitle = showTitles, playing = null,
                ) {
                    PlaylistCover(playlist, Modifier.fillMaxWidth())
                }
            }
        }
    }
}

@Composable
private fun ArtistsTab(
    model: HushModel, query: String, sort: LibrarySort, state: LazyGridState, padding: PaddingValues,
    showAll: () -> Unit,
) {
    val library = model.library
    val favorites = model.favoriteArtists
    val artists = remember(library, query, sort, favorites, model.playCounts) {
        var found = LibrarySearch.filterByNameThenSongs(library.artists, query, Artist::searchKey, Artist::songSearchKey)
        found = when (sort) {
            LibrarySort.Favorites -> {
                // Only favourites, most songs first. While searching, or before any favourites are
                // chosen, every artist shows (favourites first).
                val pool = if (query.isEmpty() && found.any { it.id in favorites }) found.filter { it.id in favorites } else found
                pool.withIndex().sortedWith(
                    compareBy<IndexedValue<Artist>> { it.value.id !in favorites }
                        .thenByDescending { it.value.songs.size }
                        .thenBy { it.index },
                ).map { it.value }
            }
            LibrarySort.MostSongs -> found.withIndex().sortedWith(compareByDescending<IndexedValue<Artist>> { it.value.songs.size }.thenBy { it.index }).map { it.value }
            LibrarySort.MostPlayed -> byPlays(found) { a -> a.songs.sumOf { model.playCounts[it.id] ?: 0 } }
            LibrarySort.Alphabetical -> found
        }
        found
    }
    when {
        !model.loaded -> return LoadingMessage()
        library.artists.isEmpty() -> return EmptyMessage("A quiet start", "Nothing here yet.", icon = Icons.Rounded.GraphicEq)
        artists.isEmpty() && query.isNotEmpty() -> return EmptyMessage("Nothing found", "Try another song, album, or artist.", icon = Icons.Rounded.Search)
        artists.isEmpty() -> return EmptyMessage(
            "No favorite artists yet", "Open an artist and add them to Favorites, or press and hold their picture.",
            "Show All Artists" to showAll, icon = Icons.Rounded.FavoriteBorder,
        )
    }
    val actions = LocalActions.current
    val player = model.player
    val current = library.song(player.currentId)
    val currentArtists = remember(current, library) { current?.let { s -> library.creditedArtists(s).map { it.id }.toSet() } ?: emptySet() }
    BoxWithConstraints {
        val targets = if (sort == LibrarySort.Alphabetical && query.isEmpty()) letterTargets(artists, Artist::letter) else emptyList()
        LibraryGrid(state, gridColumns(maxWidth, artists = true), padding, targets, spacing = 16.dp, rowSpacing = 24.dp) {
            itemsIndexed(artists, key = { _, a -> a.id }) { _, artist ->
                ArtistTile(
                    artist,
                    favorite = artist.id in favorites,
                    playing = if (artist.id in currentArtists) player.isPlaying else null,
                ) { actions.open(Route.ArtistPage(artist.id)) }
            }
        }
    }
}

/** A round photo with the name under it; a small heart for favourites. */
@Composable
private fun ArtistTile(artist: Artist, favorite: Boolean, playing: Boolean?, onClick: () -> Unit) {
    val actions = LocalActions.current
    val model = actions.model
    var menu by remember { mutableStateOf(false) }
    Box {
        Column(
            Modifier.fillMaxWidth().tilePressable(onLongClick = { menu = true }, onClick = onClick),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(7.dp),
        ) {
            Box(Modifier.fillMaxWidth()) {
                ArtistPhoto(artist, Modifier.fillMaxWidth())
                if (favorite) {
                    Box(
                        Modifier.align(Alignment.BottomEnd).offset((-2).dp, (-2).dp).size(24.dp)
                            .background(Color.Black, CircleShape)
                            .border(0.6.dp, Hush.accent.copy(alpha = 0.35f), CircleShape),
                        contentAlignment = Alignment.Center,
                    ) {
                        Icon(Icons.Rounded.Favorite, "Favorite", tint = Hush.accent, modifier = Modifier.size(12.dp))
                    }
                }
                if (playing != null) {
                    NowPlayingBadge(playing, 24.dp, Modifier.align(Alignment.BottomStart).offset(2.dp, (-2).dp))
                }
            }
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Text(artist.name, style = Hush.serif(14.sp), maxLines = 1, overflow = TextOverflow.Ellipsis, textAlign = TextAlign.Center)
                Text(songCount(artist.songs.size), style = Hush.sans(12.sp, Hush.muted), maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
        }
        HushMenu(menu, { menu = false }) {
            val isFavorite = model.isFavorite(artist.id)
            HushMenuItem(
                if (isFavorite) "Remove from Favorites" else "Add to Favorites",
                if (isFavorite) Icons.Rounded.HeartBroken else Icons.Rounded.FavoriteBorder,
            ) { model.toggleFavorite(artist.id); menu = false }
            HushMenuDivider()
            HushMenuItem("Play Next", Icons.AutoMirrored.Rounded.PlaylistPlay) { model.player.playNext(artist.songs); menu = false }
            HushMenuItem("Add to Queue", Icons.AutoMirrored.Rounded.PlaylistAdd) { model.player.addToQueue(artist.songs); menu = false }
        }
    }
}

@Composable
private fun SongsTab(model: HushModel, query: String, sort: LibrarySort, state: LazyListState, padding: PaddingValues) {
    val library = model.library
    val songs = remember(library, query, sort, model.playCounts) {
        val found = if (query.isEmpty()) library.songs else library.songs.filter { it.searchKey.contains(query) }
        if (sort == LibrarySort.MostPlayed) byPlays(found) { model.playCounts[it.id] ?: 0 } else found
    }
    when {
        !model.loaded -> return LoadingMessage()
        library.songs.isEmpty() -> return EmptyMessage(
            "A quiet start", "Hush plays the songs saved on this phone. Copy your music over, and it appears here.",
            icon = Icons.Rounded.GraphicEq,
        )
        songs.isEmpty() -> return EmptyMessage("Nothing found", "Try another song, album, or artist.", icon = Icons.Rounded.Search)
    }
    val alphabetical = sort == LibrarySort.Alphabetical && query.isEmpty()
    // Rows with quiet section letters between them in A–Z order.
    val rows: List<Any> = remember(songs, alphabetical) {
        if (!alphabetical) songs else buildList {
            var last: String? = null
            for (song in songs) {
                val letter = LibraryAlphabet.section(song.title)
                if (letter != last) { add(letter); last = letter }
                add(song)
            }
        }
    }
    val targets = remember(rows) {
        rows.withIndex().filter { it.value is String }.map { (it.value as String) to it.index }
    }
    val indexOf = remember(songs) { songs.withIndex().associate { it.value.id to it.index } }
    val player = model.player
    val insets = LocalLibraryInsets.current
    Box(Modifier.fillMaxSize()) {
        LazyColumn(state = state, contentPadding = padding, modifier = Modifier.fillMaxSize()) {
            itemsIndexed(rows, key = { _, row -> if (row is Song) row.id else "letter-$row" }) { _, row ->
                if (row is Song) {
                    val isCurrent = player.currentId == row.mediaId
                    SongRow(row, isCurrent, isCurrent && player.isPlaying) { player.play(songs, indexOf[row.id] ?: 0) }
                } else {
                    Text(
                        row as String, style = Hush.serif(15.sp, Hush.muted),
                        modifier = Modifier.padding(start = Hush.sideMargin, top = 12.dp, bottom = 4.dp),
                    )
                }
            }
        }
        FastScroller(state, targets, top = insets.calculateTopPadding(), bottom = insets.calculateBottomPadding(), tickEvery = 2)
    }
}

/** An album or playlist tile: the cover, with the title under it only when titles are on. */
@Composable
private fun CoverTile(
    onClick: () -> Unit,
    menuSongs: List<Song>,
    title: String,
    subtitle: String,
    showTitle: Boolean,
    playing: Boolean?,
    cover: @Composable () -> Unit,
) {
    var menu by remember { mutableStateOf(false) }
    Box {
        Column(
            Modifier.tilePressable(onLongClick = { menu = true }, onClick = onClick),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Box {
                cover()
                if (playing != null) NowPlayingBadge(playing, 24.dp, Modifier.align(Alignment.BottomEnd).padding(8.dp))
            }
            AnimatedVisibility(
                showTitle,
                enter = fadeIn(tween(200)) + expandVertically(tween(200)),
                exit = fadeOut(tween(200)) + shrinkVertically(tween(200)),
            ) {
                Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text(title, style = Hush.serif(15.sp), maxLines = 1, overflow = TextOverflow.Ellipsis)
                    Text(subtitle, style = Hush.sans(12.5.sp, Hush.muted), maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
            }
        }
        SongMenu(menuSongs, menu, { menu = false })
    }
}
