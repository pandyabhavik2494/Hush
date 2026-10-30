package com.pandyabhavik.hush.ui

import androidx.compose.foundation.background
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
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.PlaylistAdd
import androidx.compose.material.icons.automirrored.rounded.PlaylistPlay
import androidx.compose.material.icons.rounded.ArrowBackIosNew
import androidx.compose.material.icons.rounded.ChevronRight
import androidx.compose.material.icons.rounded.FavoriteBorder
import androidx.compose.material.icons.rounded.HeartBroken
import androidx.compose.material.icons.rounded.Mic
import androidx.compose.material.icons.rounded.MoreHoriz
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.positionInWindow
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.min
import androidx.compose.ui.unit.sp
import com.pandyabhavik.hush.data.Artist
import com.pandyabhavik.hush.data.ArtistCredits
import com.pandyabhavik.hush.data.Song
import com.pandyabhavik.hush.data.durationText
import kotlinx.coroutines.delay

/**
 * Back on the left, "…" on the right, on plain black. The page's name fades into the middle
 * once its big title has scrolled under the bar (Apple Music's collapsing large title).
 */
@Composable
private fun PageBar(
    onBack: () -> Unit,
    title: String = "",
    titleAlpha: () -> Float = { 0f },
    onBottom: (Float) -> Unit = {},
    menu: @Composable (dismiss: () -> Unit) -> Unit,
) {
    var open by remember { mutableStateOf(false) }
    Column(
        Modifier
            .fillMaxWidth()
            .background(Hush.paper)
            .statusBarsPadding()
            .onGloballyPositioned { onBottom(it.positionInWindow().y + it.size.height) },
    ) {
        Row(
            Modifier.fillMaxWidth().heightIn(min = 48.dp).padding(horizontal = 4.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            PlainIconButton(Icons.Rounded.ArrowBackIosNew, "Back", size = 20.dp, onClick = onBack)
            Text(
                title,
                style = Hush.sans(16.sp, weight = FontWeight.SemiBold),
                textAlign = TextAlign.Center,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.weight(1f).padding(horizontal = 4.dp).graphicsLayer { alpha = titleAlpha() },
            )
            Box {
                PlainIconButton(Icons.Rounded.MoreHoriz, "More", size = 24.dp) { open = true }
                HushMenu(open, { open = false }) { menu { open = false } }
            }
        }
        Box(Modifier.fillMaxWidth().height(0.5.dp).graphicsLayer { alpha = titleAlpha() }.background(Hush.line))
    }
}

/** Big centred serif title (album pages 31, playlist and artist pages 29). */
@Composable
private fun PageTitle(title: String, size: Float, tracking: Float, modifier: Modifier = Modifier) {
    Text(
        title,
        style = Hush.serifTitle(size.sp, tracking.sp),
        textAlign = TextAlign.Center,
        maxLines = 4,
        overflow = TextOverflow.Ellipsis,
        modifier = modifier.fillMaxWidth(),
    )
}

/** Where the page's big title is, so the bar can fade its small one in as it scrolls away. */
private class TitleTracker {
    var barBottom by mutableFloatStateOf(0f)
    var titleTop by mutableFloatStateOf(Float.MAX_VALUE)
    var titleHeight by mutableFloatStateOf(1f)

    val anchor: Modifier = Modifier.onGloballyPositioned {
        titleTop = it.positionInWindow().y
        titleHeight = it.size.height.toFloat().coerceAtLeast(1f)
    }

    fun alpha(state: LazyListState): Float =
        if (state.firstVisibleItemIndex > 0) 1f
        else ((barBottom - titleTop) / titleHeight).coerceIn(0f, 1f)
}

/**
 * A page with a cover and names on top and a list below. On the Fold's wide inner screen the
 * cover and names sit on the left and the list scrolls on the right.
 *
 * [reveal] is the list index (counting the header as 0) of the playing song: when it is far
 * enough down, the page glides it to the middle shortly after opening, once.
 */
@Composable
private fun DetailLayout(
    bottomPadding: Dp,
    title: String,
    onBack: () -> Unit,
    menu: @Composable (dismiss: () -> Unit) -> Unit,
    reveal: Int? = null,
    header: @Composable (wide: Boolean, titleAnchor: Modifier) -> Unit,
    list: LazyListScope.() -> Unit,
) {
    val tracker = remember { TitleTracker() }
    val listState = rememberLazyListState()
    val headerState = rememberLazyListState()
    BoxWithConstraints(Modifier.fillMaxSize().background(Hush.paper).blockTouches()) {
        val wide = maxWidth >= 700.dp
        LaunchedEffect(Unit) {
            val target = reveal ?: return@LaunchedEffect
            if (target < 5) return@LaunchedEffect // the header plus four rows
            delay(450)
            // On the wide screen the header has its own column, so the list starts with the songs.
            listState.centerItem(if (wide) target - 1 else target, animate = true, spec = androidx.compose.animation.core.tween(600))
        }
        Column(Modifier.fillMaxSize()) {
            PageBar(
                onBack, title,
                titleAlpha = { tracker.alpha(if (wide) headerState else listState) },
                onBottom = { tracker.barBottom = it },
                menu = menu,
            )
            if (wide) {
                Row(Modifier.fillMaxSize()) {
                    LazyColumn(
                        Modifier.weight(0.42f).fillMaxSize(),
                        state = headerState,
                        contentPadding = PaddingValues(top = 12.dp, bottom = bottomPadding + 16.dp),
                    ) { item { Column { header(true, tracker.anchor) } } }
                    LazyColumn(
                        Modifier.weight(0.58f).fillMaxSize(),
                        state = listState,
                        contentPadding = PaddingValues(top = 4.dp, bottom = bottomPadding + 16.dp),
                        content = list,
                    )
                }
            } else {
                LazyColumn(
                    Modifier.fillMaxSize(),
                    state = listState,
                    contentPadding = PaddingValues(bottom = bottomPadding + 16.dp),
                ) {
                    item(key = "header") { Column(horizontalAlignment = Alignment.CenterHorizontally) { header(false, tracker.anchor) } }
                    list()
                }
            }
        }
    }
}

/**
 * A square cover, centred: [inset] in from each side on the cover screen, never wider than
 * [limit], and never more than ~1.3x the cover's pixels (so it is never blown up soft).
 */
@Composable
private fun HeaderCover(wide: Boolean, inset: Dp, top: Dp, limit: Dp = Dp.Infinity, cover: @Composable (Modifier) -> Unit) {
    val cap = maxCoverSize()
    BoxWithConstraints(Modifier.fillMaxWidth().padding(top = top), contentAlignment = Alignment.Center) {
        val room = maxWidth - (if (wide) 32.dp else inset) * 2
        val size = min(min(room, limit), cap).coerceAtLeast(0.dp)
        cover(Modifier.size(size))
    }
}

@Composable
fun AlbumPage(key: String, bottomPadding: Dp, onBack: () -> Unit) {
    val actions = LocalActions.current
    val model = actions.model
    val album = model.library.albumsByKey[key] ?: return MissingPage(onBack)
    val player = model.player
    val currentIndex = album.songs.indexOfFirst { it.mediaId == player.currentId }
    val multiDisc = remember(album) { album.songs.map { it.disc }.distinct().size > 1 }
    // The album artist: one artist opens their page, several offer a choice.
    val artists = remember(album, model.library) {
        ArtistCredits.names(album.artist).map { ArtistCredits.key(it) }.distinct()
            .mapNotNull { model.library.artistsById[it] }
            .ifEmpty { model.library.creditedArtists(album.cover) }
    }
    DetailLayout(
        bottomPadding,
        title = album.title,
        onBack = onBack,
        menu = { dismiss ->
            HushMenuItem("Play Next", Icons.AutoMirrored.Rounded.PlaylistPlay) { player.playNext(album.songs); dismiss() }
            HushMenuItem("Add to Queue", Icons.AutoMirrored.Rounded.PlaylistAdd) { player.addToQueue(album.songs); dismiss() }
            if (artists.isNotEmpty()) {
                HushMenuDivider()
                for (artist in artists) {
                    HushMenuItem("Go to ${artist.name}", Icons.Rounded.Mic) { dismiss(); actions.open(Route.ArtistPage(artist.id)) }
                }
            }
        },
        reveal = if (currentIndex >= 4) currentIndex + 1 else null,
        header = { wide, anchor ->
            HeaderCover(wide, inset = 52.dp, top = 10.dp) { Cover(album.cover, it, 12.dp) }
            Column(
                Modifier.fillMaxWidth().padding(start = Hush.sideMargin, end = Hush.sideMargin, top = 26.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                PageTitle(album.title, 31f, -0.3f, anchor)
                ArtistLink(album.artist, artists)
                val detail = listOfNotNull(album.year?.toString(), songCount(album.songs.size)).joinToString(" · ")
                Text(detail, style = Hush.sans(13.sp, Hush.muted), maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
            PlayShuffleButtons(album.songs, Modifier.padding(start = Hush.sideMargin, end = Hush.sideMargin, top = 24.dp, bottom = 16.dp))
        },
    ) {
        itemsIndexed(album.songs, key = { _, s -> s.id }) { index, song ->
            Column {
                val newDisc = multiDisc && (index == 0 || album.songs[index - 1].disc != song.disc)
                if (newDisc) {
                    Text(
                        "Disc ${song.disc}", style = Hush.serif(15.sp, Hush.muted),
                        modifier = Modifier.padding(start = Hush.sideMargin, top = if (index == 0) 4.dp else 18.dp, bottom = 6.dp),
                    )
                } else if (index > 0) {
                    TrackDivider(start = Hush.sideMargin + 22.dp + 16.dp, end = Hush.sideMargin)
                }
                TrackRow(song, index == currentIndex, player.isPlaying) { player.play(album.songs, index) }
            }
        }
        item(key = "footer") {
            val parts = listOfNotNull(songCount(album.songs.size), longDurationText(album.songs.sumOf { it.durationMs }))
            Column(
                Modifier.fillMaxWidth().padding(start = Hush.sideMargin, end = Hush.sideMargin, top = 18.dp, bottom = 8.dp),
                verticalArrangement = Arrangement.spacedBy(2.dp),
            ) {
                album.year?.let { Text(it.toString(), style = Hush.sans(13.sp, Hush.muted)) }
                Text(parts.joinToString(", "), style = Hush.sans(13.sp, Hush.muted))
            }
        }
    }
}

/** The album artist in ink: taps open the artist, or a menu when the album credits several. */
@Composable
private fun ArtistLink(name: String, artists: List<Artist>) {
    val actions = LocalActions.current
    var menu by remember { mutableStateOf(false) }
    Box {
        Text(
            name,
            style = Hush.sans(16.sp, Hush.accent, FontWeight.Medium),
            textAlign = TextAlign.Center,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = if (artists.isEmpty()) Modifier else Modifier.clickableQuiet {
                if (artists.size == 1) actions.open(Route.ArtistPage(artists.first().id)) else menu = true
            },
        )
        if (artists.size > 1) {
            HushMenu(menu, { menu = false }) {
                for (artist in artists) {
                    HushMenuItem(artist.name, Icons.Rounded.Mic) { menu = false; actions.open(Route.ArtistPage(artist.id)) }
                }
            }
        }
    }
}

/** An album track: number (or bars while playing) and title. No cover, no duration. */
@Composable
private fun TrackRow(song: Song, isCurrent: Boolean, isPlaying: Boolean, onClick: () -> Unit) {
    var menu by remember { mutableStateOf(false) }
    Box {
        Row(
            Modifier.fillMaxWidth().heightIn(min = 52.dp)
                .pressable(scale = 1f, dim = 0.6f, onLongClick = { menu = true }, onClick = onClick)
                .padding(horizontal = Hush.sideMargin, vertical = 6.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            TrackNumberLabel(song.track, isCurrent, isPlaying, Modifier.widthIn(min = 22.dp), Alignment.CenterEnd)
            Text(
                song.title.ifBlank { "Untitled" },
                style = Hush.sans(16.sp, weight = if (isCurrent) FontWeight.SemiBold else FontWeight.Normal),
                maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f),
            )
        }
        SongMenu(listOf(song), menu, { menu = false }, song = song)
    }
}

@Composable
fun PlaylistPage(id: String, bottomPadding: Dp, onBack: () -> Unit) {
    val actions = LocalActions.current
    val model = actions.model
    val playlist = model.library.playlistsById[id] ?: return MissingPage(onBack)
    val player = model.player
    val currentIndex = playlist.songs.indexOfFirst { it.mediaId == player.currentId }
    DetailLayout(
        bottomPadding,
        title = playlist.name,
        onBack = onBack,
        menu = { dismiss ->
            HushMenuItem("Play Next", Icons.AutoMirrored.Rounded.PlaylistPlay) { player.playNext(playlist.songs); dismiss() }
            HushMenuItem("Add to Queue", Icons.AutoMirrored.Rounded.PlaylistAdd) { player.addToQueue(playlist.songs); dismiss() }
        },
        reveal = if (currentIndex >= 4) currentIndex + 1 else null,
        header = { wide, anchor ->
            HeaderCover(wide, inset = 36.dp, top = 8.dp, limit = 310.dp) { PlaylistCover(playlist, it, Hush.tileRadius, shadow = CoverShadow(Color.Black.copy(alpha = 0.16f), 14.dp, 7.dp)) }
            PageTitle(playlist.name, 29f, -0.5f, Modifier.padding(start = 26.dp, end = 26.dp, top = 20.dp).then(anchor))
            val detail = listOfNotNull(songCount(playlist.songs.size), durationText(playlist.durationMs)).joinToString(" · ")
            Text(
                detail, style = Hush.sans(13.sp, Hush.muted, FontWeight.Medium), textAlign = TextAlign.Center,
                modifier = Modifier.padding(start = 26.dp, end = 26.dp, top = 7.dp),
            )
            PlayShuffleButtons(playlist.songs, Modifier.padding(start = Hush.sideMargin, end = Hush.sideMargin, top = 24.dp, bottom = 14.dp))
            if (playlist.songs.isEmpty()) {
                Column(
                    Modifier.fillMaxWidth().padding(start = 28.dp, end = 28.dp, top = 34.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(9.dp),
                ) {
                    Text("Nothing here yet", style = Hush.serif(20.sp))
                    Text(
                        "Add songs to this playlist on your Mac, copy it over again, then pull down in the library to refresh.",
                        style = Hush.sans(13.sp, Hush.muted), textAlign = TextAlign.Center,
                    )
                }
            }
        },
    ) {
        // Keyed by position: a song can appear twice.
        itemsIndexed(playlist.songs, key = { i, s -> "$i-${s.id}" }) { index, song ->
            Column {
                if (index > 0) TrackDivider(start = 24.dp + 26.dp + 12.dp + 48.dp + 12.dp, end = 24.dp)
                PlaylistTrackRow(song, index + 1, index == currentIndex, player.isPlaying) { player.play(playlist.songs, index) }
            }
        }
    }
}

/** A playlist song: number (or bars), a small cover, title and "Artist · Album". */
@Composable
private fun PlaylistTrackRow(song: Song, number: Int, isCurrent: Boolean, isPlaying: Boolean, onClick: () -> Unit) {
    var menu by remember { mutableStateOf(false) }
    Box {
        Row(
            Modifier.fillMaxWidth().heightIn(min = 64.dp)
                .pressable(scale = 1f, dim = 0.6f, onLongClick = { menu = true }, onClick = onClick)
                .padding(horizontal = 24.dp, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            TrackNumberLabel(number, isCurrent, isPlaying, Modifier.widthIn(min = 26.dp), Alignment.CenterStart)
            Cover(song, Modifier.size(48.dp), 8.dp)
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(
                    song.title.ifBlank { "Untitled" },
                    style = Hush.sans(14.sp, weight = if (isCurrent) FontWeight.SemiBold else FontWeight.Medium),
                    maxLines = 1, overflow = TextOverflow.Ellipsis,
                )
                Text(
                    listOf(song.artist, song.album).filter { it.isNotBlank() }.joinToString(" · "),
                    style = Hush.sans(12.sp, Hush.muted), maxLines = 1, overflow = TextOverflow.Ellipsis,
                )
            }
        }
        SongMenu(listOf(song), menu, { menu = false }, song = song)
    }
}

@Composable
fun ArtistPage(id: String, bottomPadding: Dp, onBack: () -> Unit) {
    val actions = LocalActions.current
    val model = actions.model
    val artist = model.library.artistsById[id] ?: return MissingPage(onBack)
    val player = model.player
    val favorite = model.isFavorite(id)
    // Newest albums first.
    val albums = remember(artist) {
        artist.albums.withIndex()
            .sortedWith(compareByDescending<IndexedValue<com.pandyabhavik.hush.data.ArtistAlbum>> { it.value.year ?: Int.MIN_VALUE }.thenBy { it.index })
            .map { it.value }
    }
    DetailLayout(
        bottomPadding,
        title = artist.name,
        onBack = onBack,
        menu = { dismiss ->
            HushMenuItem(
                if (favorite) "Remove from Favorites" else "Add to Favorites",
                if (favorite) Icons.Rounded.HeartBroken else Icons.Rounded.FavoriteBorder,
            ) { model.toggleFavorite(id); dismiss() }
            HushMenuDivider()
            HushMenuItem("Play Next", Icons.AutoMirrored.Rounded.PlaylistPlay) { player.playNext(artist.songs); dismiss() }
            HushMenuItem("Add to Queue", Icons.AutoMirrored.Rounded.PlaylistAdd) { player.addToQueue(artist.songs); dismiss() }
        },
        header = { wide, anchor ->
            Box(Modifier.fillMaxWidth().padding(top = 8.dp), contentAlignment = Alignment.Center) {
                ArtistPhoto(
                    artist, Modifier.size(if (wide) 220.dp else 190.dp),
                    shadow = CoverShadow(Color.Black.copy(alpha = 0.22f), 18.dp, 9.dp),
                )
            }
            PageTitle(artist.name, 29f, -0.5f, Modifier.padding(start = 26.dp, end = 26.dp, top = 20.dp).then(anchor))
            val detail = listOfNotNull(
                when (artist.albums.size) { 0 -> null; 1 -> "1 album"; else -> "${artist.albums.size} albums" },
                songCount(artist.songs.size),
            ).joinToString(" · ")
            Text(
                detail, style = Hush.sans(13.sp, Hush.muted, FontWeight.Medium), textAlign = TextAlign.Center,
                modifier = Modifier.padding(start = 26.dp, end = 26.dp, top = 7.dp),
            )
            PlayShuffleButtons(artist.songs, Modifier.padding(start = Hush.sideMargin, end = Hush.sideMargin, top = 24.dp, bottom = 18.dp))
        },
    ) {
        for (album in albums) {
            item(key = "album-${album.albumKey}") {
                ArtistAlbumHeader(album)
            }
            itemsIndexed(album.songs, key = { _, s -> "${album.albumKey}-${s.id}" }) { index, song ->
                Column {
                    if (index > 0) TrackDivider(start = 22.dp + 36.dp, end = 22.dp)
                    val isCurrent = player.currentId == song.mediaId
                    ArtistSongRow(
                        song, artist, if (song.track > 0) song.track else index + 1, isCurrent, player.isPlaying,
                        plays = model.playCounts[song.id] ?: 0,
                    ) { player.play(artist.songs, artist.songs.indexOf(song).coerceAtLeast(0)) }
                }
            }
        }
    }
}

/** An album on an artist's page: small cover, serif title, year and count; opens the album. */
@Composable
private fun ArtistAlbumHeader(album: com.pandyabhavik.hush.data.ArtistAlbum) {
    val actions = LocalActions.current
    var menu by remember { mutableStateOf(false) }
    Box(Modifier.padding(top = 14.dp)) {
        Row(
            Modifier.fillMaxWidth()
                .pressable(scale = 0.98f, dim = 0.75f, onLongClick = { menu = true }) { actions.open(Route.AlbumPage(album.albumKey)) }
                .padding(horizontal = 22.dp, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Cover(album.cover, Modifier.size(56.dp), 8.dp)
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                Text(album.title, style = Hush.serif(16.sp), maxLines = 1, overflow = TextOverflow.Ellipsis)
                Text(
                    listOfNotNull(album.year?.toString(), songCount(album.songs.size)).joinToString(" · "),
                    style = Hush.sans(12.sp, Hush.muted), maxLines = 1, overflow = TextOverflow.Ellipsis,
                )
            }
            Icon(Icons.Rounded.ChevronRight, null, tint = Hush.muted.copy(alpha = 0.8f), modifier = Modifier.size(18.dp))
        }
        SongMenu(album.songs, menu, { menu = false })
    }
}

/** A song on an artist's page: number, title, the full credit when it is a duet, and plays. */
@Composable
private fun ArtistSongRow(song: Song, artist: Artist, number: Int, isCurrent: Boolean, isPlaying: Boolean, plays: Int, onClick: () -> Unit) {
    var menu by remember { mutableStateOf(false) }
    val duet = ArtistCredits.key(song.artist) != artist.id && song.artist.isNotBlank()
    Box {
        Row(
            Modifier.fillMaxWidth().heightIn(min = 48.dp)
                .pressable(scale = 1f, dim = 0.6f, onLongClick = { menu = true }, onClick = onClick)
                .padding(horizontal = 22.dp, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            TrackNumberLabel(number, isCurrent, isPlaying, Modifier.widthIn(min = 24.dp), Alignment.CenterStart)
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                Text(
                    song.title.ifBlank { "Untitled" },
                    style = Hush.sans(14.sp, weight = if (isCurrent) FontWeight.SemiBold else FontWeight.Medium),
                    maxLines = 1, overflow = TextOverflow.Ellipsis,
                )
                if (duet) Text(song.artist, style = Hush.sans(11.sp, Hush.muted), maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
            if (plays > 0) Text(plays.toString(), style = Hush.mono(11.sp, Hush.muted.copy(alpha = 0.8f)))
        }
        SongMenu(listOf(song), menu, { menu = false }, song = song)
    }
}

@Composable
private fun MissingPage(onBack: () -> Unit) {
    Column(Modifier.fillMaxSize().background(Hush.paper).blockTouches()) {
        PageBar(onBack) { }
        Spacer(Modifier.height(24.dp))
        Text(
            "This is no longer on your phone.", style = Hush.sans(16.sp, Hush.muted),
            modifier = Modifier.fillMaxWidth().padding(40.dp), textAlign = TextAlign.Center,
        )
    }
}
