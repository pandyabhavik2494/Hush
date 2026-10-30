package com.pandyabhavik.hush.ui

import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyGridState
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.itemsIndexed
import androidx.compose.foundation.lazy.grid.rememberLazyGridState
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.Sort
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.FilterList
import androidx.compose.material.icons.rounded.Search
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.pandyabhavik.hush.HushModel
import com.pandyabhavik.hush.data.Album
import com.pandyabhavik.hush.data.Artist
import com.pandyabhavik.hush.data.LibrarySearch
import com.pandyabhavik.hush.data.Playlist
import com.pandyabhavik.hush.data.Song
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

    companion object {
        fun options(tab: LibraryTab) =
            when (tab) {
                LibraryTab.Artists -> listOf(Favorites, MostSongs, Alphabetical, MostPlayed)
                LibraryTab.Videos -> emptyList()
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

    var sort by remember { mutableStateOf(LibrarySort.valueOf(model.prefs.getString("sort", "Alphabetical"))) }
    var artistSort by remember { mutableStateOf(LibrarySort.valueOf(model.prefs.getString("artistSort", "Favorites"))) }
    var showTitles by remember { mutableStateOf(model.prefs.getBoolean("showTitles", false)) }
    var searching by rememberSaveable { mutableStateOf(false) }
    var queryText by rememberSaveable { mutableStateOf("") }
    val query = LibrarySearch.query(queryText)

    val gridStates = mapOf(
        LibraryTab.Albums to rememberLazyGridState(),
        LibraryTab.Playlists to rememberLazyGridState(),
        LibraryTab.Artists to rememberLazyGridState(),
        LibraryTab.Videos to rememberLazyGridState(),
    )
    val songsState = rememberLazyListState()
    val scrolled by remember {
        derivedStateOf {
            val t = tabs[pager.currentPage]
            if (t == LibraryTab.Songs) songsState.firstVisibleItemIndex > 0 || songsState.firstVisibleItemScrollOffset > 0
            else gridStates.getValue(t).let { it.firstVisibleItemIndex > 0 || it.firstVisibleItemScrollOffset > 0 }
        }
    }

    fun scrollToTop(t: LibraryTab) = scope.launch {
        if (t == LibraryTab.Songs) songsState.animateScrollToItem(0) else gridStates.getValue(t).animateScrollToItem(0)
    }

    val folderPicker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocumentTree()) { uri ->
        if (uri != null) model.setPlaylistsFolder(uri)
    }

    BackHandler(enabled = searching) {
        searching = false
        queryText = ""
    }

    Column(Modifier.fillMaxSize().background(Hush.paper)) {
        // Header: solid black, nothing shows through.
        Column(Modifier.background(Hush.paper).statusBarsPadding()) {
            Row(
                Modifier.fillMaxWidth().height(Hush.tapTarget).padding(start = Hush.sideMargin, end = 8.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    "Hush",
                    style = androidx.compose.ui.text.TextStyle(fontFamily = Hush.wordmark, fontSize = 22.sp, color = Hush.ink),
                    modifier = Modifier.clickableQuiet(onAbout),
                )
                Spacer(Modifier.weight(1f))
                PlainIconButton(Icons.Rounded.Search, "Search") { searching = true }
                Box {
                    var options by remember { mutableStateOf(false) }
                    PlainIconButton(Icons.Rounded.FilterList, "Options") { options = true }
                    DropdownMenu(options, { options = false }, containerColor = Hush.card) {
                        val current = if (tab == LibraryTab.Artists) artistSort else sort
                        for (option in LibrarySort.options(tab)) {
                            DropdownMenuItem(
                                text = { Text(option.label) },
                                leadingIcon = { if (option == current) Icon(Icons.Rounded.Check, null) else Spacer(Modifier.size(24.dp)) },
                                onClick = {
                                    if (tab == LibraryTab.Artists) {
                                        artistSort = option; model.prefs.putString("artistSort", option.name)
                                    } else {
                                        sort = option; model.prefs.putString("sort", option.name)
                                    }
                                    options = false
                                    scrollToTop(tab)
                                },
                            )
                        }
                        if (tab == LibraryTab.Albums || tab == LibraryTab.Playlists) {
                            HorizontalDivider(color = Hush.line)
                            DropdownMenuItem(
                                text = { Text("Show Titles") },
                                leadingIcon = { if (showTitles) Icon(Icons.Rounded.Check, null) else Spacer(Modifier.size(24.dp)) },
                                onClick = {
                                    showTitles = !showTitles
                                    model.prefs.putBoolean("showTitles", showTitles)
                                    options = false
                                },
                            )
                        }
                        if (tab == LibraryTab.Playlists) {
                            HorizontalDivider(color = Hush.line)
                            DropdownMenuItem(
                                text = { Text("Choose Playlists Folder…") },
                                onClick = { options = false; folderPicker.launch(null) },
                            )
                        }
                    }
                }
            }
            AnimatedVisibility(searching) {
                SearchField(queryText, tab.placeholder, onChange = { queryText = it }, onCancel = {
                    searching = false
                    queryText = ""
                })
            }
            TabsRow(tabs, pager.currentPage) { index ->
                if (index == pager.currentPage) scrollToTop(tabs[index]) else scope.launch { pager.animateScrollToPage(index) }
            }
            HorizontalDivider(color = if (scrolled) Hush.line else Hush.paper, thickness = 1.dp)
        }

        PullToRefreshBox(isRefreshing = model.refreshing, onRefresh = { model.refresh() }, modifier = Modifier.weight(1f)) {
            HorizontalPager(pager, Modifier.fillMaxSize(), beyondViewportPageCount = 1) { page ->
                val padding = PaddingValues(top = 8.dp, bottom = bottomPadding + 16.dp)
                when (tabs[page]) {
                    LibraryTab.Albums -> AlbumsTab(model, query, sort, showTitles, gridStates.getValue(LibraryTab.Albums), padding)
                    LibraryTab.Songs -> SongsTab(model, query, sort, songsState, padding)
                    LibraryTab.Playlists -> PlaylistsTab(model, query, sort, showTitles, gridStates.getValue(LibraryTab.Playlists), padding) {
                        folderPicker.launch(null)
                    }
                    LibraryTab.Artists -> ArtistsTab(model, query, artistSort, gridStates.getValue(LibraryTab.Artists), padding)
                    LibraryTab.Videos -> VideosTab(model, query, gridStates.getValue(LibraryTab.Videos), padding)
                }
            }
        }
    }
}

@Composable
private fun TabsRow(tabs: List<LibraryTab>, selected: Int, onSelect: (Int) -> Unit) {
    val state = rememberLazyListState()
    LaunchedEffect(selected) { state.animateScrollToItem((selected - 1).coerceAtLeast(0)) }
    LazyRow(
        state = state,
        modifier = Modifier.fillMaxWidth().height(58.dp).testTag("tabs"),
        contentPadding = PaddingValues(horizontal = Hush.sideMargin),
        horizontalArrangement = Arrangement.spacedBy(24.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        itemsIndexed(tabs) { index, tab ->
            Text(
                tab.title,
                style = Hush.serif(31.sp, if (index == selected) Hush.ink else Hush.tabIdle).copy(letterSpacing = (-0.3).sp),
                modifier = Modifier.clickableQuiet { onSelect(index) },
            )
        }
    }
}

@Composable
private fun SearchField(text: String, placeholder: String, onChange: (String) -> Unit, onCancel: () -> Unit) {
    val focus = remember { FocusRequester() }
    val focusManager = LocalFocusManager.current
    LaunchedEffect(Unit) { focus.requestFocus() }
    Row(
        Modifier.fillMaxWidth().padding(start = Hush.sideMargin, end = 8.dp, top = 4.dp, bottom = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            Modifier.weight(1f).height(40.dp).background(Hush.card, RoundedCornerShape(12.dp)).padding(horizontal = 12.dp),
            contentAlignment = Alignment.CenterStart,
        ) {
            if (text.isEmpty()) Text(placeholder, style = Hush.sans(16.sp, Hush.muted), maxLines = 1, overflow = TextOverflow.Ellipsis)
            BasicTextField(
                text, onChange,
                singleLine = true,
                textStyle = Hush.sans(16.sp),
                cursorBrush = SolidColor(Hush.ink),
                modifier = Modifier.fillMaxWidth().focusRequester(focus),
            )
        }
        Text(
            "Cancel",
            style = Hush.sans(16.sp),
            modifier = Modifier.padding(start = 4.dp).clickableQuiet {
                focusManager.clearFocus()
                onCancel()
            }.padding(horizontal = 10.dp, vertical = 10.dp),
        )
    }
}

private fun <T> byPlays(items: List<T>, plays: (T) -> Int): List<T> =
    items.withIndex().sortedWith(compareByDescending<IndexedValue<T>> { plays(it.value) }.thenBy { it.index }).map { it.value }

@Composable
private fun EmptyMessage(title: String, detail: String, action: Pair<String, () -> Unit>? = null) {
    Column(
        Modifier.fillMaxSize().padding(horizontal = 40.dp, vertical = 80.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text(title, style = Hush.serif(24.sp), textAlign = TextAlign.Center)
        Spacer(Modifier.height(10.dp))
        Text(detail, style = Hush.sans(15.sp, Hush.muted), textAlign = TextAlign.Center)
        if (action != null) {
            Spacer(Modifier.height(24.dp))
            PillButton(action.first, Icons.AutoMirrored.Rounded.Sort, filled = true, Modifier.width(260.dp), action.second)
        }
    }
}

@Composable
fun LibraryGrid(
    state: LazyGridState,
    columns: Int,
    padding: PaddingValues,
    targets: List<Pair<String, Int>>,
    spacing: Dp = 14.dp,
    rowSpacing: Dp = 14.dp,
    content: androidx.compose.foundation.lazy.grid.LazyGridScope.() -> Unit,
) {
    val scope = rememberCoroutineScope()
    Box(Modifier.fillMaxSize()) {
        LazyVerticalGrid(
            columns = GridCells.Fixed(columns),
            state = state,
            contentPadding = PaddingValues(
                start = Hush.sideMargin, end = Hush.sideMargin,
                top = padding.calculateTopPadding(), bottom = padding.calculateBottomPadding(),
            ),
            horizontalArrangement = Arrangement.spacedBy(spacing),
            verticalArrangement = Arrangement.spacedBy(rowSpacing),
            modifier = Modifier.fillMaxSize(),
            content = content,
        )
        FastScrollIndex(targets, Modifier.align(Alignment.CenterEnd).padding(bottom = padding.calculateBottomPadding())) {
            scope.launch { state.scrollToItem(it) }
        }
    }
}

@Composable
private fun AlbumsTab(model: HushModel, query: String, sort: LibrarySort, showTitles: Boolean, state: LazyGridState, padding: PaddingValues) {
    val library = model.library
    val albums = remember(library, query, sort, model.playCounts) {
        val found = LibrarySearch.filterByNameThenSongs(library.albums, query, Album::searchKey, Album::songSearchKey)
        if (sort == LibrarySort.MostPlayed) byPlays(found) { a -> a.songs.sumOf { model.playCounts[it.id] ?: 0 } } else found
    }
    if (model.loaded && library.songs.isEmpty()) {
        EmptyMessage("No music yet", "Hush plays the songs saved on this phone. Copy your music over, and it appears here.")
        return
    }
    val actions = LocalActions.current
    BoxWithConstraints {
        val targets = if (sort == LibrarySort.Alphabetical && query.isEmpty()) letterTargets(albums, Album::letter) else emptyList()
        LibraryGrid(state, gridColumns(maxWidth), padding, targets, rowSpacing = if (showTitles) 22.dp else 14.dp) {
            itemsIndexed(albums, key = { _, a -> a.key }) { _, album ->
                Tile(onClick = { actions.open(Route.AlbumPage(album.key)) }, menuSongs = album.songs,
                    title = album.title.takeIf { showTitles }, subtitle = album.artist) {
                    Cover(album.cover, Modifier.fillMaxWidth(), Hush.tileRadius)
                }
            }
        }
    }
}

@Composable
private fun PlaylistsTab(
    model: HushModel, query: String, sort: LibrarySort, showTitles: Boolean,
    state: LazyGridState, padding: PaddingValues, chooseFolder: () -> Unit,
) {
    val library = model.library
    val playlists = remember(library, query, sort, model.playCounts) {
        val found = LibrarySearch.filterByNameThenSongs(library.playlists, query, Playlist::searchKey, Playlist::songSearchKey)
        if (sort == LibrarySort.MostPlayed) byPlays(found) { p -> p.songs.sumOf { model.playCounts[it.id] ?: 0 } } else found
    }
    if (model.loaded && library.playlists.isEmpty()) {
        if (model.playlistsFolder == null) {
            EmptyMessage(
                "Your playlists",
                "Copy the Playlists folder from your Mac onto the phone, then choose it here. Hush reads the playlist files in it.",
                "Choose Playlists Folder" to chooseFolder,
            )
        } else {
            EmptyMessage(
                "No playlists found",
                "Hush found no playlist files (.m3u8) with songs from this phone in that folder.",
                "Choose Another Folder" to chooseFolder,
            )
        }
        return
    }
    val actions = LocalActions.current
    BoxWithConstraints {
        val targets = if (sort == LibrarySort.Alphabetical && query.isEmpty()) letterTargets(playlists, Playlist::letter) else emptyList()
        LibraryGrid(state, gridColumns(maxWidth), padding, targets, rowSpacing = if (showTitles) 22.dp else 14.dp) {
            itemsIndexed(playlists, key = { _, p -> p.id }) { _, playlist ->
                Tile(onClick = { actions.open(Route.PlaylistPage(playlist.id)) }, menuSongs = playlist.songs,
                    title = playlist.name.takeIf { showTitles }, subtitle = "${playlist.songs.size} songs") {
                    PlaylistCover(playlist, Modifier.fillMaxWidth())
                }
            }
        }
    }
}

@Composable
private fun ArtistsTab(model: HushModel, query: String, sort: LibrarySort, state: LazyGridState, padding: PaddingValues) {
    val library = model.library
    val favorites = model.favoriteArtists
    val artists = remember(library, query, sort, favorites, model.playCounts) {
        var found = LibrarySearch.filterByNameThenSongs(library.artists, query, Artist::searchKey, Artist::songSearchKey)
        found = when (sort) {
            LibrarySort.Favorites -> {
                // Only favourites, most songs first. While searching, every match shows (favourites first).
                val pool = if (query.isEmpty()) found.filter { it.id in favorites } else found
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
    if (model.loaded && artists.isEmpty() && sort == LibrarySort.Favorites && query.isEmpty()) {
        EmptyMessage("No favourites yet", "Open an artist and choose Add to Favorites from the … menu, or pick another sort in Options.")
        return
    }
    val actions = LocalActions.current
    BoxWithConstraints {
        val targets = if (sort == LibrarySort.Alphabetical && query.isEmpty()) letterTargets(artists, Artist::letter) else emptyList()
        LibraryGrid(state, gridColumns(maxWidth, artists = true), padding, targets, spacing = 16.dp, rowSpacing = 20.dp) {
            itemsIndexed(artists, key = { _, a -> a.id }) { _, artist ->
                Column(
                    Modifier.clickableQuiet { actions.open(Route.ArtistPage(artist.id)) },
                    horizontalAlignment = Alignment.CenterHorizontally,
                ) {
                    ArtistPhoto(artist, Modifier.fillMaxWidth())
                    Spacer(Modifier.height(8.dp))
                    Text(
                        artist.name, style = Hush.sans(13.sp), maxLines = 2, overflow = TextOverflow.Ellipsis,
                        textAlign = TextAlign.Center,
                    )
                }
            }
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
    val alphabetical = sort == LibrarySort.Alphabetical && query.isEmpty()
    // Rows with quiet section letters between them in A–Z order.
    val rows: List<Any> = remember(songs, alphabetical) {
        if (!alphabetical) songs else buildList {
            var last: String? = null
            for (song in songs) {
                val letter = com.pandyabhavik.hush.data.LibraryAlphabet.section(song.title)
                if (letter != last) { add(letter); last = letter }
                add(song)
            }
        }
    }
    val targets = remember(rows) {
        rows.withIndex().filter { it.value is String }.map { (it.value as String) to it.index }
    }
    val player = model.player
    val scope = rememberCoroutineScope()
    Box(Modifier.fillMaxSize()) {
        LazyColumn(state = state, contentPadding = padding, modifier = Modifier.fillMaxSize()) {
            itemsIndexed(rows, key = { _, row -> if (row is Song) row.id else "letter-$row" }) { _, row ->
                if (row is Song) {
                    val isCurrent = player.currentId == row.mediaId
                    SongRow(row, isCurrent, isCurrent && player.isPlaying) { player.play(songs, songs.indexOf(row)) }
                } else {
                    Text(
                        row as String, style = Hush.serif(15.sp, Hush.muted),
                        modifier = Modifier.padding(start = Hush.sideMargin, top = 14.dp, bottom = 4.dp),
                    )
                }
            }
        }
        FastScrollIndex(targets, Modifier.align(Alignment.CenterEnd).padding(bottom = padding.calculateBottomPadding())) {
            scope.launch { state.scrollToItem(it) }
        }
    }
}

/** An album or playlist tile: the cover, with the title under it only when titles are on. */
@OptIn(androidx.compose.foundation.ExperimentalFoundationApi::class)
@Composable
private fun Tile(onClick: () -> Unit, menuSongs: List<Song>, title: String?, subtitle: String, cover: @Composable () -> Unit) {
    var menu by remember { mutableStateOf(false) }
    Box {
        Column(Modifier.androidx_combinedClickable(onClick) { menu = true }) {
            cover()
            if (title != null) {
                Spacer(Modifier.height(8.dp))
                Text(title, style = Hush.serif(15.sp), maxLines = 1, overflow = TextOverflow.Ellipsis)
                Text(subtitle, style = Hush.sans(12.5.sp, Hush.muted), maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
        }
        SongMenu(menuSongs, menu, { menu = false })
    }
}

@OptIn(androidx.compose.foundation.ExperimentalFoundationApi::class)
private fun Modifier.androidx_combinedClickable(onClick: () -> Unit, onLongClick: () -> Unit): Modifier =
    this.then(Modifier.combinedClickable(onClick = onClick, onLongClick = onLongClick))
