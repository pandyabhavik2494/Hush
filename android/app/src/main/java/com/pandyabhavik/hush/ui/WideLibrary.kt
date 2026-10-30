package com.pandyabhavik.hush.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
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
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyGridScope
import androidx.compose.foundation.lazy.grid.LazyGridState
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Favorite
import androidx.compose.material.icons.rounded.FolderOpen
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.pandyabhavik.hush.HushModel
import com.pandyabhavik.hush.data.Album
import com.pandyabhavik.hush.data.Artist
import com.pandyabhavik.hush.data.LibraryAlphabet
import com.pandyabhavik.hush.data.LibrarySearch
import com.pandyabhavik.hush.data.Playlist
import com.pandyabhavik.hush.data.Song
import com.pandyabhavik.hush.data.timeText
import kotlinx.coroutines.launch
import kotlin.math.roundToInt

/*
 * The wide library sections, after the Mac app's grids and songs table. Tile minimums are
 * smaller than the Mac's so the Fold's inner screen shows 3 album columns beside the sidebar
 * and 4 without it. Each section's first item is its large title (see [WideLargeTitle]).
 */

private const val TITLE_KEY = "__title"

private fun <T> byPlays(items: List<T>, plays: (T) -> Int): List<T> =
    items.withIndex().sortedWith(compareByDescending<IndexedValue<T>> { plays(it.value) }.thenBy { it.index }).map { it.value }

/** Columns that fit [width], each at least [min] wide (Mac's adaptive grid, without a maximum). */
private fun columnsFor(width: Dp, min: Dp, gap: Dp): Int = (((width + gap) / (min + gap)).toInt()).coerceAtLeast(2)

@Composable
private fun WideGrid(
    state: LazyGridState,
    minTile: Dp,
    gap: Dp,
    rowGap: Dp,
    padding: PaddingValues,
    title: String,
    count: Int?,
    targets: List<Pair<String, Int>>,
    content: LazyGridScope.() -> Unit,
) {
    val scope = rememberCoroutineScope()
    BoxWithConstraints(Modifier.fillMaxSize()) {
        val rail = targets.size >= 2
        val start = Wide.sideGutter
        val end = if (rail) 44.dp else Wide.sideGutter
        val columns = columnsFor(maxWidth - start - end, minTile, gap)
        LazyVerticalGrid(
            columns = GridCells.Fixed(columns),
            state = state,
            contentPadding = PaddingValues(start = start, end = end, top = padding.calculateTopPadding(), bottom = padding.calculateBottomPadding() + 12.dp),
            horizontalArrangement = Arrangement.spacedBy(gap),
            verticalArrangement = Arrangement.spacedBy(rowGap),
            modifier = Modifier.fillMaxSize(),
        ) {
            item(key = TITLE_KEY, span = { GridItemSpan(maxLineSpan) }) { WideLargeTitle(title, count) }
            content()
        }
        if (rail) {
            FastScrollIndex(targets, Modifier.align(Alignment.CenterEnd).padding(end = 6.dp, top = Wide.largeTitle, bottom = padding.calculateBottomPadding())) {
                scope.launch { state.scrollToItem(it) }
            }
        }
    }
}

@Composable
private fun WideEmpty(title: String, count: Int?, heading: String, detail: String, padding: PaddingValues, action: Pair<String, () -> Unit>? = null) {
    Column(Modifier.fillMaxSize().padding(start = Wide.sideGutter, end = Wide.sideGutter, top = padding.calculateTopPadding())) {
        WideLargeTitle(title, count)
        Column(
            Modifier.fillMaxWidth().padding(top = 64.dp, start = 12.dp, end = 12.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Text(heading, style = Wide.serif(24.sp), textAlign = TextAlign.Center)
            Spacer(Modifier.height(10.dp))
            Text(detail, style = Wide.sans(14.sp, Wide.muted), textAlign = TextAlign.Center, modifier = Modifier.widthIn(max = 380.dp))
            if (action != null) {
                Spacer(Modifier.height(24.dp))
                WideCapsule(action.first, Icons.Rounded.FolderOpen, primary = true, onClick = action.second)
            }
        }
    }
}

/** A long-press menu for a group of songs: play, shuffle, queue, plus [more]. */
@Composable
private fun GroupMenu(songs: List<Song>, expanded: Boolean, onDismiss: () -> Unit, more: @Composable ((dismiss: () -> Unit) -> Unit)? = null) {
    val player = LocalActions.current.model.player
    SongMenu(songs, expanded, onDismiss, extra = {
        HushMenuItem("Play") { onDismiss(); player.play(songs) }
        HushMenuItem("Shuffle") { onDismiss(); player.playShuffled(songs) }
        more?.invoke(onDismiss)
    })
}

/** Mac tile shadow: black 0.42, blur 12, 8 down. */
private val tileShadow = CoverShadow(Color.Black.copy(alpha = 0.42f), blur = 12.dp, y = 8.dp)

private fun List<Song>.holds(mediaId: String?): Boolean = mediaId != null && any { it.mediaId == mediaId }

// ---------------------------------------------------------------- Albums

@Composable
internal fun WideAlbums(model: HushModel, query: String, sort: LibrarySort, showTitles: Boolean, state: LazyGridState, padding: PaddingValues) {
    val library = model.library
    val albums = remember(library, query, sort, model.playCounts) {
        val found = LibrarySearch.filterByNameThenSongs(library.albums, query, Album::searchKey, Album::songSearchKey)
        if (sort == LibrarySort.MostPlayed) byPlays(found) { a -> a.songs.sumOf { model.playCounts[it.id] ?: 0 } } else found
    }
    if (library.songs.isEmpty()) {
        WideEmpty("Albums", null, "No music yet", "Hush plays the songs saved on this phone. Copy your music over, and it appears here.", padding)
        return
    }
    if (albums.isEmpty()) {
        WideEmpty("Albums", null, "No matches", "Try another name.", padding)
        return
    }
    val actions = LocalActions.current
    val player = model.player
    val targets = if (sort == LibrarySort.Alphabetical && query.isEmpty() && albums.size > 24) letterTargets(albums, Album::letter, offset = 1) else emptyList()
    WideGrid(state, minTile = 170.dp, gap = 20.dp, rowGap = if (showTitles) 26.dp else 20.dp, padding, "Albums", albums.size, targets) {
        items(albums, key = { it.key }) { album ->
            CoverTile(
                onClick = { actions.open(Route.AlbumPage(album.key)) },
                songs = album.songs,
                title = album.title.takeIf { showTitles },
                subtitle = listOfNotNull(album.artist.takeIf { it.isNotBlank() }, album.year?.toString()).joinToString(" · "),
                playing = album.songs.holds(player.currentId),
                isPlaying = player.isPlaying,
                more = { dismiss ->
                    HushMenuItem("Go to Artist") { dismiss(); actions.openArtistOf(album.cover) }
                },
            ) { Cover(album.cover, Modifier.fillMaxWidth(), Hush.tileRadius, shadow = tileShadow) }
        }
    }
}

/** A square cover with a soft shadow; serif title and quiet subtitle underneath when titles are on. */
@Composable
private fun CoverTile(
    onClick: () -> Unit,
    songs: List<Song>,
    title: String?,
    subtitle: String,
    playing: Boolean,
    isPlaying: Boolean,
    overlay: @Composable (BoxScope.() -> Unit)? = null,
    more: @Composable ((dismiss: () -> Unit) -> Unit)? = null,
    cover: @Composable () -> Unit,
) {
    var menu by remember { mutableStateOf(false) }
    Box {
        Column(Modifier.tilePressable(onLongClick = { menu = true }, onClick = onClick)) {
            Box(Modifier.fillMaxWidth()) {
                cover()
                overlay?.invoke(this)
                if (playing) WidePlayingBadge(isPlaying, Modifier.align(Alignment.TopEnd).padding(8.dp))
            }
            if (title != null) {
                Spacer(Modifier.height(9.dp))
                Text(title, style = Wide.serif(15.sp), maxLines = 1, overflow = TextOverflow.Ellipsis)
                if (subtitle.isNotEmpty()) {
                    Spacer(Modifier.height(2.dp))
                    Text(subtitle, style = Wide.sans(12.5.sp, Wide.muted), maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
            }
        }
        GroupMenu(songs, menu, { menu = false }, more = more)
    }
}

// ---------------------------------------------------------------- Playlists

@Composable
internal fun WidePlaylists(
    model: HushModel, query: String, sort: LibrarySort, showTitles: Boolean,
    state: LazyGridState, padding: PaddingValues, chooseFolder: () -> Unit,
) {
    val library = model.library
    val playlists = remember(library, query, sort, model.playCounts) {
        val found = LibrarySearch.filterByNameThenSongs(library.playlists, query, Playlist::searchKey, Playlist::songSearchKey)
        if (sort == LibrarySort.MostPlayed) byPlays(found) { p -> p.songs.sumOf { model.playCounts[it.id] ?: 0 } } else found
    }
    if (library.playlists.isEmpty()) {
        if (model.playlistsFolder == null) {
            WideEmpty(
                "Playlists", null, "Your playlists",
                "Copy the Playlists folder from your Mac onto the phone, then choose it here. Hush reads the playlist files in it.",
                padding, "Choose Playlists Folder" to chooseFolder,
            )
        } else {
            WideEmpty(
                "Playlists", null, "No playlists found",
                "Hush found no playlist files (.m3u8) with songs from this phone in that folder.",
                padding, "Choose Another Folder" to chooseFolder,
            )
        }
        return
    }
    if (playlists.isEmpty()) {
        WideEmpty("Playlists", null, "No matches", "Try another name.", padding)
        return
    }
    val actions = LocalActions.current
    val player = model.player
    val targets = if (sort == LibrarySort.Alphabetical && query.isEmpty() && playlists.size > 24) letterTargets(playlists, Playlist::letter, offset = 1) else emptyList()
    WideGrid(state, minTile = 170.dp, gap = 20.dp, rowGap = if (showTitles) 26.dp else 20.dp, padding, "Playlists", playlists.size, targets) {
        items(playlists, key = { it.id }) { playlist ->
            val mosaic = playlist.coverUri == null
            CoverTile(
                onClick = { actions.open(Route.PlaylistPage(playlist.id)) },
                songs = playlist.songs,
                title = playlist.name.takeIf { showTitles },
                subtitle = wideSongCount(playlist.songs.size),
                playing = player.queue.size == playlist.songs.size && playlist.songs.holds(player.currentId),
                isPlaying = player.isPlaying,
                overlay = {
                    // A mosaic has no name of its own: write it on the cover.
                    if (!showTitles && mosaic) {
                        Box(
                            Modifier.matchParentSize()
                                .background(Brush.verticalGradient(0.45f to Color.Transparent, 1f to Color.Black.copy(alpha = 0.6f)), RoundedCornerShape(Hush.tileRadius)),
                            contentAlignment = Alignment.BottomStart,
                        ) {
                            Text(
                                playlist.name, style = Wide.serif(15.sp, Color.White), maxLines = 2, overflow = TextOverflow.Ellipsis,
                                modifier = Modifier.padding(10.dp),
                            )
                        }
                    }
                },
            ) { PlaylistCover(playlist, Modifier.fillMaxWidth(), Hush.tileRadius, shadow = tileShadow) }
        }
    }
}

internal fun wideSongCount(n: Int) = if (n == 1) "1 song" else "$n songs"

// ---------------------------------------------------------------- Artists

@Composable
internal fun WideArtists(model: HushModel, query: String, sort: LibrarySort, state: LazyGridState, padding: PaddingValues) {
    val library = model.library
    val favorites = model.favoriteArtists
    val found = remember(library, query, sort, model.playCounts) {
        val f = LibrarySearch.filterByNameThenSongs(library.artists, query, Artist::searchKey, Artist::songSearchKey)
        when (sort) {
            LibrarySort.MostSongs, LibrarySort.Favorites ->
                f.withIndex().sortedWith(compareByDescending<IndexedValue<Artist>> { it.value.songs.size }.thenBy { it.index }).map { it.value }
            LibrarySort.MostPlayed -> byPlays(f) { a -> a.songs.sumOf { model.playCounts[it.id] ?: 0 } }
            LibrarySort.Alphabetical -> f
        }
    }
    if (library.artists.isEmpty()) {
        WideEmpty("Artists", null, "No artists yet", "Artists appear as your songs arrive.", padding)
        return
    }
    if (found.isEmpty()) {
        WideEmpty("Artists", null, "No matches", "Try another name.", padding)
        return
    }
    // Favourites first, under their own label, then everyone else (as on the Mac).
    val split = sort == LibrarySort.Favorites && query.isEmpty() && found.any { it.id in favorites }
    val favs = if (split) found.filter { it.id in favorites } else emptyList()
    val rest = if (split) found.filter { it.id !in favorites } else found
    val targets = if (sort == LibrarySort.Alphabetical && query.isEmpty() && found.size > 24) letterTargets(found, Artist::letter, offset = 1) else emptyList()
    WideGrid(state, minTile = 132.dp, gap = 24.dp, rowGap = 24.dp, padding, "Artists", null, targets) {
        if (split) {
            item(key = "__favs", span = { GridItemSpan(maxLineSpan) }) {
                Text("FAVOURITES", style = Wide.micro(Wide.gold), modifier = Modifier.padding(top = 4.dp))
            }
            items(favs, key = { "fav-${it.id}" }) { ArtistTile(model, it) }
            if (rest.isNotEmpty()) item(key = "__rest", span = { GridItemSpan(maxLineSpan) }) {
                Text("EVERYONE ELSE", style = Wide.micro(), modifier = Modifier.padding(top = 12.dp))
            }
        }
        items(rest, key = { it.id }) { ArtistTile(model, it) }
    }
}

@Composable
private fun ArtistTile(model: HushModel, artist: Artist) {
    val actions = LocalActions.current
    val player = model.player
    val favorite = artist.id in model.favoriteArtists
    var menu by remember { mutableStateOf(false) }
    Box {
        Column(
            Modifier.tilePressable(onLongClick = { menu = true }) { actions.open(Route.ArtistPage(artist.id)) },
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Box(Modifier.fillMaxWidth()) {
                ArtistPhoto(artist, Modifier.fillMaxWidth(), shadow = CoverShadow(Color.Black.copy(alpha = 0.4f), blur = 10.dp, y = 6.dp))
                if (favorite) {
                    Box(
                        Modifier.align(Alignment.TopEnd).size(28.dp).background(Wide.paper.copy(alpha = 0.7f), CircleShape),
                        contentAlignment = Alignment.Center,
                    ) { Icon(Icons.Rounded.Favorite, contentDescription = "Favourite", tint = Wide.gold, modifier = Modifier.size(14.dp)) }
                }
                if (artist.songs.holds(player.currentId)) WidePlayingBadge(player.isPlaying, Modifier.align(Alignment.BottomStart))
            }
            Spacer(Modifier.height(9.dp))
            Text(artist.name, style = Wide.serif(15.sp), maxLines = 1, overflow = TextOverflow.Ellipsis, textAlign = TextAlign.Center)
            Text(wideSongCount(artist.songs.size), style = Wide.sans(12.5.sp, Wide.muted), maxLines = 1, textAlign = TextAlign.Center)
        }
        GroupMenu(artist.songs, menu, { menu = false }) { dismiss ->
            HushMenuItem(if (favorite) "Remove from Favourites" else "Add to Favourites") { dismiss(); model.toggleFavorite(artist.id) }
        }
    }
}

// ---------------------------------------------------------------- Songs

@Composable
internal fun WideSongs(model: HushModel, query: String, sort: LibrarySort, state: LazyListState, padding: PaddingValues) {
    val library = model.library
    val songs = remember(library, query, sort, model.playCounts) {
        val found = if (query.isEmpty()) library.songs else library.songs.filter { it.searchKey.contains(query) }
        if (sort == LibrarySort.MostPlayed) byPlays(found) { model.playCounts[it.id] ?: 0 } else found
    }
    if (library.songs.isEmpty()) {
        WideEmpty("Songs", null, "No songs yet", "Songs saved on this phone show up here.", padding)
        return
    }
    val player = model.player
    val scope = rememberCoroutineScope()
    val targets = remember(songs, sort, query) {
        if (sort == LibrarySort.Alphabetical && query.isEmpty() && songs.size > 24) letterTargets(songs, { LibraryAlphabet.section(it.title) }, offset = 2) else emptyList()
    }
    BoxWithConstraints(Modifier.fillMaxSize()) {
        val showAlbum = maxWidth >= 560.dp
        val end = if (targets.size >= 2) 36.dp else 16.dp
        LazyColumn(
            state = state,
            contentPadding = PaddingValues(start = 16.dp, end = end, top = padding.calculateTopPadding(), bottom = padding.calculateBottomPadding() + 12.dp),
            modifier = Modifier.fillMaxSize(),
        ) {
            item(key = TITLE_KEY) { WideLargeTitle("Songs", songs.size, Modifier.padding(start = 12.dp)) }
            item(key = "__columns") { SongColumns(showAlbum) }
            if (songs.isEmpty()) item(key = "__none") {
                Text(
                    "No matches. Try another title, artist or album.", style = Wide.sans(14.sp, Wide.muted),
                    modifier = Modifier.padding(horizontal = 12.dp, vertical = 24.dp),
                )
            }
            items(songs, key = { it.id }) { song ->
                val isCurrent = player.currentId == song.mediaId
                SongTableRow(song, isCurrent, player.isPlaying, showAlbum) { player.play(songs, songs.indexOf(song)) }
            }
        }
        if (targets.size >= 2) {
            FastScrollIndex(targets, Modifier.align(Alignment.CenterEnd).padding(end = 2.dp, top = Wide.largeTitle, bottom = padding.calculateBottomPadding())) {
                scope.launch { state.scrollToItem(it) }
            }
        }
    }
}

@Composable
private fun SongColumns(showAlbum: Boolean) {
    val style = Wide.sans(12.sp, Wide.muted, FontWeight.Medium)
    Row(
        Modifier.fillMaxWidth().height(32.dp).padding(horizontal = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Spacer(Modifier.width(28.dp + 14.dp + 48.dp))
        Text("Title", style = style, modifier = Modifier.weight(1f))
        if (showAlbum) Text("Album", style = style, modifier = Modifier.weight(0.6f).padding(start = 16.dp))
        Text("Time", style = style, textAlign = TextAlign.End, modifier = Modifier.width(52.dp))
    }
    Box(Modifier.fillMaxWidth().padding(horizontal = 12.dp).height(1.dp).background(Wide.line))
}

/** A row of the songs table: playing mark, cover, title and artist, album, time. Tap plays. */
@Composable
private fun SongTableRow(song: Song, isCurrent: Boolean, isPlaying: Boolean, showAlbum: Boolean, onClick: () -> Unit) {
    var menu by remember { mutableStateOf(false) }
    Box {
        Row(
            Modifier.fillMaxWidth().height(68.dp)
                .background(if (isCurrent) Wide.gold.copy(alpha = 0.08f) else Color.Transparent, RoundedCornerShape(8.dp))
                .pressable(scale = 1f, dim = 0.7f, onLongClick = { menu = true }, onClick = onClick)
                .padding(horizontal = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Box(Modifier.width(28.dp), contentAlignment = Alignment.Center) {
                if (isCurrent) Equalizer(isPlaying, Modifier.size(13.dp), color = Wide.gold)
            }
            Cover(song, Modifier.size(48.dp), 8.dp, shadow = CoverShadow(Color.Black.copy(alpha = 0.35f), blur = 5.dp, y = 2.dp))
            Spacer(Modifier.width(14.dp))
            Column(Modifier.weight(1f)) {
                Text(
                    song.title,
                    style = Wide.sans(15.5.sp, if (isCurrent) Wide.gold else Wide.ink, FontWeight.SemiBold),
                    maxLines = 1, overflow = TextOverflow.Ellipsis,
                )
                Spacer(Modifier.height(3.dp))
                Text(song.artist, style = Wide.sans(12.5.sp, Wide.muted), maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
            if (showAlbum) {
                Text(
                    song.album, style = Wide.sans(12.5.sp, Wide.muted.copy(alpha = 0.8f)), maxLines = 1, overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(0.6f).padding(start = 16.dp),
                )
            }
            Text(timeText(song.durationMs), style = Wide.tnum(12.sp, Wide.muted.copy(alpha = 0.75f)), textAlign = TextAlign.End, modifier = Modifier.width(52.dp))
        }
        SongMenu(listOf(song), menu, { menu = false }, song = song)
    }
}

// ---------------------------------------------------------------- Videos

/**
 * The videos grid comes from [VideosTab]; the large title sits over it and scrolls away with the
 * grid's first row.
 */
@Composable
internal fun WideVideos(model: HushModel, query: String, state: LazyGridState, padding: PaddingValues, chooseFolder: () -> Unit) {
    val titlePx = with(LocalDensity.current) { Wide.largeTitle.toPx() }
    Box(Modifier.fillMaxSize()) {
        Box(Modifier.padding(start = 8.dp, end = 8.dp)) {
            VideosTab(
                model, query, state,
                PaddingValues(top = padding.calculateTopPadding() + Wide.largeTitle + 8.dp, bottom = padding.calculateBottomPadding() + 12.dp),
                chooseFolder,
            )
        }
        WideLargeTitle(
            "Videos", model.library.videos.size.takeIf { model.videosFolder != null },
            Modifier.padding(start = Wide.sideGutter, end = Wide.sideGutter, top = padding.calculateTopPadding())
                .wideScrollUp {
                    if (state.firstVisibleItemIndex > 0) titlePx.roundToInt() * 2
                    else state.firstVisibleItemScrollOffset.coerceAtMost((titlePx * 2).roundToInt())
                },
        )
    }
}
