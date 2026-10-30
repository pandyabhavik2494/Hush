package com.pandyabhavik.hush.ui

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.horizontalScroll
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
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Favorite
import androidx.compose.material.icons.rounded.FavoriteBorder
import androidx.compose.material.icons.rounded.MoreHoriz
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material.icons.rounded.Shuffle
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.pandyabhavik.hush.data.Artist
import com.pandyabhavik.hush.data.ArtistAlbum
import com.pandyabhavik.hush.data.ArtistCredits
import com.pandyabhavik.hush.data.Song
import com.pandyabhavik.hush.data.durationText
import com.pandyabhavik.hush.data.timeText

/*
 * Album, playlist and artist pages for the wide layout: Apple Music's structure (big cover beside
 * a large title, Play and Shuffle capsules, a clean track list) in the Mac app's colours, over a
 * blurred glow of the cover.
 */

private val pageGutter = 28.dp

/** Mac page cover shadow: black 0.6, blur 30, 24 down. */
private val pageShadow = CoverShadow(Color.Black.copy(alpha = 0.6f), blur = 30.dp, y = 24.dp)

/** Covers stay at most ~1.3x their 600 px pixels. */
private fun coverSide(width: Dp, density: Float): Dp {
    val cap = (600f * 1.3f / density).dp
    return (width * 0.4f).coerceIn(180.dp, maxOf(180.dp, minOf(300.dp, cap)))
}

@Composable
private fun PageScaffold(
    glow: Song?,
    title: String,
    sectionTitle: String,
    bottomPadding: Dp,
    toggle: WideSidebarToggle,
    onBack: () -> Unit,
    menu: @Composable (dismiss: () -> Unit) -> Unit,
    content: LazyListScope.(width: Dp) -> Unit,
) {
    val state = rememberLazyListState()
    val headerPx = with(LocalDensity.current) { 180.dp.toPx() }
    val scrolled by remember { derivedStateOf { state.firstVisibleItemIndex > 0 || state.firstVisibleItemScrollOffset > headerPx } }
    val shown by animateFloatAsState(if (scrolled) 1f else 0f, tween(200), label = "pageTitle")
    Box(Modifier.fillMaxSize().background(Wide.paper)) {
        if (glow != null) ArtworkGlow(glow, Modifier.fillMaxWidth().height(560.dp))
        Column(Modifier.fillMaxSize()) {
            Row(
                Modifier.fillMaxWidth()
                    .background(Wide.paper.copy(alpha = 0.92f * shown))
                    .statusBarsPadding()
                    .height(60.dp)
                    .padding(start = 8.dp, end = 12.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                WideSidebarButton(toggle)
                WideBackCrumb(sectionTitle, onBack)
                Text(
                    title, style = Wide.serif(18.sp), maxLines = 1, overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f).padding(horizontal = 8.dp).alpha(shown).clearAndSetSemantics { },
                    textAlign = TextAlign.Center,
                )
                Box {
                    var open by remember { mutableStateOf(false) }
                    WideIconButton(Icons.Rounded.MoreHoriz, "More") { open = true }
                    HushMenu(open, { open = false }) { menu { open = false } }
                }
            }
            BoxWithConstraints(Modifier.weight(1f).fillMaxWidth()) {
                val width = maxWidth
                LazyColumn(
                    state = state,
                    contentPadding = PaddingValues(bottom = bottomPadding + 16.dp),
                    modifier = Modifier.fillMaxSize(),
                ) { content(width) }
            }
        }
    }
}

/** The page's own cover, blurred and faded, glowing behind the top of the page. */
@Composable
private fun ArtworkGlow(song: Song, modifier: Modifier) {
    Box(
        modifier
            .graphicsLayer { alpha = 0.5f; compositingStrategy = CompositingStrategy.Offscreen }
            .drawWithContent {
                drawContent()
                drawRect(
                    Brush.verticalGradient(0f to Color.Black, 0.55f to Color.Black.copy(alpha = 0.5f), 1f to Color.Transparent),
                    blendMode = BlendMode.DstIn,
                )
            },
    ) {
        Cover(song, Modifier.fillMaxSize().graphicsLayer { scaleX = 1.15f; scaleY = 1.15f }.blur(56.dp), 0.dp, maxUpscale = 0f)
    }
}

/** Big cover beside (or above, when narrow) a large title, names, details and Play / Shuffle. */
@Composable
private fun CollectionHeader(
    width: Dp,
    title: String,
    detail: String,
    songs: List<Song>,
    cover: @Composable (Modifier) -> Unit,
    names: (@Composable () -> Unit)? = null,
    extraButton: (@Composable () -> Unit)? = null,
) {
    val density = LocalDensity.current.density
    val player = LocalActions.current.model.player
    val side = coverSide(width - pageGutter * 2, density)
    val wide = width >= 560.dp
    val text: @Composable (Alignment.Horizontal, TextAlign) -> Unit = { align, textAlign ->
        Column(horizontalAlignment = align) {
            Text(title, style = Wide.serif(if (wide) 34.sp else 30.sp).copy(letterSpacing = (-0.3).sp), maxLines = 3, overflow = TextOverflow.Ellipsis, textAlign = textAlign)
            if (names != null) {
                Spacer(Modifier.height(4.dp))
                names()
            }
            Spacer(Modifier.height(4.dp))
            Text(detail, style = Wide.sans(13.sp, Wide.muted), textAlign = textAlign)
            Spacer(Modifier.height(18.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
                WideCapsule("Play", Icons.Rounded.PlayArrow, primary = true, Modifier.widthIn(min = 116.dp)) { player.play(songs) }
                WideCapsule("Shuffle", Icons.Rounded.Shuffle, primary = false, Modifier.widthIn(min = 116.dp)) { player.playShuffled(songs) }
                extraButton?.invoke()
            }
        }
    }
    if (wide) {
        Row(Modifier.fillMaxWidth().padding(start = pageGutter, end = pageGutter, top = 8.dp, bottom = 24.dp), verticalAlignment = Alignment.Bottom) {
            Box(Modifier.size(side)) { cover(Modifier.fillMaxSize()) }
            Spacer(Modifier.width(28.dp))
            Box(Modifier.weight(1f)) { text(Alignment.Start, TextAlign.Start) }
        }
    } else {
        Column(
            Modifier.fillMaxWidth().padding(start = pageGutter, end = pageGutter, top = 8.dp, bottom = 20.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Box(Modifier.size(minOf(side, 240.dp))) { cover(Modifier.fillMaxSize()) }
            Spacer(Modifier.height(20.dp))
            text(Alignment.CenterHorizontally, TextAlign.Center)
        }
    }
}

@Composable
private fun Missing(sectionTitle: String, bottomPadding: Dp, toggle: WideSidebarToggle, onBack: () -> Unit) {
    PageScaffold(null, "", sectionTitle, bottomPadding, toggle, onBack, menu = { }) {
        item {
            Text(
                "This is no longer on your phone.", style = Wide.sans(16.sp, Wide.muted), textAlign = TextAlign.Center,
                modifier = Modifier.fillMaxWidth().padding(48.dp),
            )
        }
    }
}

// ---------------------------------------------------------------- Album

@Composable
internal fun WideAlbumPage(key: String, sectionTitle: String, bottomPadding: Dp, toggle: WideSidebarToggle, onBack: () -> Unit) {
    val actions = LocalActions.current
    val model = actions.model
    val library = model.library
    val album = library.albumsByKey[key] ?: return Missing(sectionTitle, bottomPadding, toggle, onBack)
    val player = model.player
    val credited = remember(album, library) {
        ArtistCredits.names(album.artist).map { ArtistCredits.key(it) }.distinct().mapNotNull { library.artistsById[it] }
            .ifEmpty { library.creditedArtists(album.cover) }
    }
    val detail = listOfNotNull(album.year?.toString(), wideSongCount(album.songs.size), durationText(album.songs.sumOf { it.durationMs })).joinToString(" · ")
    PageScaffold(
        glow = album.cover, title = album.title, sectionTitle = sectionTitle, bottomPadding = bottomPadding, toggle = toggle, onBack = onBack,
        menu = { dismiss ->
            HushMenuItem("Play Next") { player.playNext(album.songs); dismiss() }
            HushMenuItem("Add to Queue") { player.addToQueue(album.songs); dismiss() }
            HushMenuItem("Go to Artist") { dismiss(); actions.openArtistOf(album.cover) }
        },
    ) { width ->
        item(key = "__header") {
            CollectionHeader(
                width, album.title, detail, album.songs,
                cover = { Cover(album.cover, it, 14.dp, shadow = pageShadow, alignment = Alignment.BottomStart) },
                names = { ArtistLinks(credited, album.artist, centered = width < 560.dp) },
            )
        }
        val multiDisc = album.songs.map { it.disc }.distinct().size > 1
        itemsIndexed(album.songs, key = { _, s -> s.id }) { index, song ->
            if (multiDisc && (index == 0 || album.songs[index - 1].disc != song.disc)) {
                Text(
                    "Disc ${song.disc}", style = Wide.micro(),
                    modifier = Modifier.padding(start = pageGutter + 12.dp, top = if (index == 0) 0.dp else 16.dp, bottom = 6.dp),
                )
            }
            WideTrackRow(
                song = song,
                isCurrent = player.currentId == song.mediaId,
                isPlaying = player.isPlaying,
                leading = WideTrackLeading.Number(if (song.track > 0) song.track else index + 1),
                subtitle = song.artist.takeIf { it.isNotBlank() && it != album.artist },
            ) { player.play(album.songs, index) }
        }
    }
}

/** Each credited artist as its own gold link, separated by commas. */
@Composable
private fun ArtistLinks(artists: List<Artist>, fallback: String, centered: Boolean) {
    val actions = LocalActions.current
    val style = Wide.sans(17.sp, Wide.gold, FontWeight.Medium)
    if (artists.isEmpty()) {
        if (fallback.isNotBlank()) Text(fallback, style = style, maxLines = 1, overflow = TextOverflow.Ellipsis)
        return
    }
    Row(
        Modifier.horizontalScroll(rememberScrollState()),
        horizontalArrangement = if (centered) Arrangement.Center else Arrangement.Start,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        artists.forEachIndexed { i, artist ->
            if (i > 0) Text(", ", style = style.copy(color = Wide.muted))
            Text(
                artist.name, style = style, maxLines = 1,
                modifier = Modifier.clickableQuiet { actions.open(Route.ArtistPage(artist.id)) }.padding(vertical = 12.dp),
            )
        }
    }
}

// ---------------------------------------------------------------- Track rows

private sealed interface WideTrackLeading {
    data class Number(val n: Int) : WideTrackLeading
    data object Artwork : WideTrackLeading
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun WideTrackRow(
    song: Song,
    isCurrent: Boolean,
    isPlaying: Boolean,
    leading: WideTrackLeading,
    subtitle: String?,
    modifier: Modifier = Modifier.padding(horizontal = pageGutter - 12.dp),
    onClick: () -> Unit,
) {
    var menu by remember { mutableStateOf(false) }
    Box(modifier) {
        Row(
            Modifier.fillMaxWidth()
                .height(if (leading is WideTrackLeading.Artwork) 64.dp else if (subtitle != null) 58.dp else 52.dp)
                .background(if (isCurrent) Wide.gold.copy(alpha = 0.08f) else Color.Transparent, RoundedCornerShape(8.dp))
                .pressable(scale = 1f, dim = 0.7f, onLongClick = { menu = true }, onClick = onClick)
                .padding(horizontal = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            when (leading) {
                is WideTrackLeading.Number -> Box(Modifier.width(28.dp), contentAlignment = Alignment.CenterStart) {
                    if (isCurrent) Equalizer(isPlaying, Modifier.size(13.dp), color = Wide.gold)
                    else Text(leading.n.toString(), style = Wide.tnum(13.sp))
                }
                WideTrackLeading.Artwork -> Box(Modifier.size(44.dp)) {
                    Cover(song, Modifier.size(44.dp), 6.dp)
                    if (isCurrent) Box(Modifier.size(44.dp).background(Color.Black.copy(alpha = 0.5f), RoundedCornerShape(6.dp)), contentAlignment = Alignment.Center) {
                        Equalizer(isPlaying, Modifier.size(13.dp), color = Wide.gold)
                    }
                }
            }
            Spacer(Modifier.width(14.dp))
            Column(Modifier.weight(1f)) {
                Text(
                    song.title,
                    style = Wide.sans(15.sp, if (isCurrent) Wide.gold else Wide.ink, if (isCurrent) FontWeight.SemiBold else FontWeight.Normal),
                    maxLines = 1, overflow = TextOverflow.Ellipsis,
                )
                if (subtitle != null) {
                    Spacer(Modifier.height(2.dp))
                    Text(subtitle, style = Wide.sans(12.5.sp, Wide.muted), maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
            }
            Spacer(Modifier.width(12.dp))
            Text(timeText(song.durationMs), style = Wide.tnum(13.sp))
        }
        SongMenu(listOf(song), menu, { menu = false }, song = song)
    }
}

// ---------------------------------------------------------------- Playlist

@Composable
internal fun WidePlaylistPage(id: String, sectionTitle: String, bottomPadding: Dp, toggle: WideSidebarToggle, onBack: () -> Unit) {
    val actions = LocalActions.current
    val model = actions.model
    val playlist = model.library.playlistsById[id] ?: return Missing(sectionTitle, bottomPadding, toggle, onBack)
    val player = model.player
    val detail = listOfNotNull(wideSongCount(playlist.songs.size), durationText(playlist.durationMs)).joinToString(" · ")
    PageScaffold(
        glow = playlist.coverSongs.firstOrNull() ?: playlist.songs.firstOrNull(),
        title = playlist.name, sectionTitle = sectionTitle, bottomPadding = bottomPadding, toggle = toggle, onBack = onBack,
        menu = { dismiss ->
            HushMenuItem("Play Next") { player.playNext(playlist.songs); dismiss() }
            HushMenuItem("Add to Queue") { player.addToQueue(playlist.songs); dismiss() }
        },
    ) { width ->
        item(key = "__header") {
            CollectionHeader(width, playlist.name, detail, playlist.songs, cover = { PlaylistCover(playlist, it, 14.dp, shadow = pageShadow) })
        }
        if (playlist.songs.isEmpty()) item(key = "__empty") {
            Text(
                "No songs here yet.", style = Wide.sans(15.sp, Wide.muted), textAlign = TextAlign.Center,
                modifier = Modifier.fillMaxWidth().padding(32.dp),
            )
        }
        itemsIndexed(playlist.songs, key = { i, s -> "$i-${s.id}" }) { index, song ->
            WideTrackRow(
                song = song,
                isCurrent = player.currentId == song.mediaId,
                isPlaying = player.isPlaying,
                leading = WideTrackLeading.Artwork,
                subtitle = listOf(song.artist, song.album).filter { it.isNotBlank() }.joinToString(" · ").ifEmpty { null },
            ) { player.play(playlist.songs, index) }
        }
    }
}

// ---------------------------------------------------------------- Artist

@Composable
internal fun WideArtistPage(id: String, sectionTitle: String, bottomPadding: Dp, toggle: WideSidebarToggle, onBack: () -> Unit) {
    val actions = LocalActions.current
    val model = actions.model
    val artist = model.library.artistsById[id] ?: return Missing(sectionTitle, bottomPadding, toggle, onBack)
    val player = model.player
    val favorite = model.isFavorite(id)
    val top = remember(artist, model.playCounts) {
        artist.songs.withIndex()
            .sortedWith(compareByDescending<IndexedValue<Song>> { model.playCounts[it.value.id] ?: 0 }.thenBy { it.index })
            .take(10).map { it.value }
    }
    val albumsText = if (artist.albums.size == 1) "1 album" else "${artist.albums.size} albums"
    PageScaffold(
        glow = artist.albums.firstOrNull()?.cover ?: artist.cover,
        title = artist.name, sectionTitle = sectionTitle, bottomPadding = bottomPadding, toggle = toggle, onBack = onBack,
        menu = { dismiss ->
            HushMenuItem(if (favorite) "Remove from Favourites" else "Add to Favourites") { model.toggleFavorite(id); dismiss() }
            HushMenuItem("Play Next") { player.playNext(artist.songs); dismiss() }
            HushMenuItem("Add to Queue") { player.addToQueue(artist.songs); dismiss() }
        },
    ) { width ->
        item(key = "__header") {
            val wide = width >= 560.dp
            val photo = if (wide) 190.dp else 150.dp
            val heart: @Composable () -> Unit = {
                WideCircleButton(
                    if (favorite) Icons.Rounded.Favorite else Icons.Rounded.FavoriteBorder,
                    if (favorite) "Remove from Favourites" else "Add to Favourites",
                    on = favorite,
                ) { model.toggleFavorite(id) }
            }
            val names: @Composable (Alignment.Horizontal, TextAlign) -> Unit = { align, textAlign ->
                Column(horizontalAlignment = align) {
                    Text(artist.name, style = Wide.serif(if (wide) 40.sp else 32.sp).copy(letterSpacing = (-0.3).sp), maxLines = 2, overflow = TextOverflow.Ellipsis, textAlign = textAlign)
                    Spacer(Modifier.height(6.dp))
                    Text("${wideSongCount(artist.songs.size)} · $albumsText", style = Wide.sans(14.sp, Wide.muted), textAlign = textAlign)
                    Spacer(Modifier.height(16.dp))
                    Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
                        WideCapsule("Play", Icons.Rounded.PlayArrow, primary = true, Modifier.widthIn(min = 116.dp)) { player.play(artist.songs) }
                        WideCapsule("Shuffle", Icons.Rounded.Shuffle, primary = false, Modifier.widthIn(min = 116.dp)) { player.playShuffled(artist.songs) }
                        heart()
                    }
                }
            }
            if (wide) {
                Row(Modifier.fillMaxWidth().padding(start = pageGutter + 4.dp, end = pageGutter, top = 8.dp, bottom = 28.dp), verticalAlignment = Alignment.CenterVertically) {
                    ArtistPhoto(artist, Modifier.size(photo), shadow = CoverShadow(Color.Black.copy(alpha = 0.6f), blur = 25.dp, y = 20.dp))
                    Spacer(Modifier.width(30.dp))
                    Box(Modifier.weight(1f)) { names(Alignment.Start, TextAlign.Start) }
                }
            } else {
                Column(Modifier.fillMaxWidth().padding(horizontal = pageGutter, vertical = 12.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                    ArtistPhoto(artist, Modifier.size(photo), shadow = CoverShadow(Color.Black.copy(alpha = 0.6f), blur = 25.dp, y = 20.dp))
                    Spacer(Modifier.height(18.dp))
                    names(Alignment.CenterHorizontally, TextAlign.Center)
                }
            }
        }

        if (top.isNotEmpty()) {
            item(key = "__mostPlayed") { SubTitle("Most played") }
            val columns = if (width >= 640.dp) 2 else 1
            val rows = top.chunked(columns)
            items(rows.size, key = { "top-$it" }) { r ->
                Row(Modifier.fillMaxWidth().padding(horizontal = pageGutter - 12.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    for (song in rows[r]) {
                        WideTrackRow(
                            song = song,
                            isCurrent = player.currentId == song.mediaId,
                            isPlaying = player.isPlaying,
                            leading = WideTrackLeading.Artwork,
                            subtitle = song.album.ifBlank { null },
                            modifier = Modifier.weight(1f),
                        ) { player.play(top, top.indexOf(song)) }
                    }
                    if (rows[r].size < columns) Spacer(Modifier.weight(1f))
                }
            }
        }

        if (artist.albums.isNotEmpty()) {
            item(key = "__albums") {
                Column {
                    SubTitle("Albums")
                    LazyRow(
                        contentPadding = PaddingValues(horizontal = pageGutter),
                        horizontalArrangement = Arrangement.spacedBy(20.dp),
                    ) {
                        items(artist.albums, key = { it.albumKey }) { album -> ArtistAlbumCard(album) }
                    }
                }
            }
        }
    }
}

@Composable
private fun SubTitle(text: String) {
    Text(text, style = Wide.serif(22.sp), modifier = Modifier.padding(start = pageGutter, end = pageGutter, top = 18.dp, bottom = 10.dp))
}

@Composable
private fun ArtistAlbumCard(album: ArtistAlbum) {
    val actions = LocalActions.current
    Column(Modifier.width(180.dp).clickableQuiet { actions.open(Route.AlbumPage(album.albumKey)) }) {
        Cover(album.cover, Modifier.size(180.dp), Hush.tileRadius, shadow = CoverShadow(Color.Black.copy(alpha = 0.42f), blur = 12.dp, y = 8.dp))
        Spacer(Modifier.height(9.dp))
        Text(album.title, style = Wide.serif(15.sp), maxLines = 1, overflow = TextOverflow.Ellipsis)
        Text(
            listOfNotNull(album.year?.toString(), wideSongCount(album.songs.size)).joinToString(" · "),
            style = Wide.sans(12.5.sp, Wide.muted), maxLines = 1,
        )
        Spacer(Modifier.height(16.dp))
    }
}
