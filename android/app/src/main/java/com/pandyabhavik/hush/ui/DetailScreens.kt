package com.pandyabhavik.hush.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
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
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.rounded.MoreHoriz
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.pandyabhavik.hush.data.Song
import com.pandyabhavik.hush.data.durationText

/** Back on the left, "…" on the right, on plain black. */
@Composable
private fun PageBar(onBack: () -> Unit, menu: @Composable (dismiss: () -> Unit) -> Unit) {
    var open by remember { mutableStateOf(false) }
    Row(
        Modifier.fillMaxWidth().background(Hush.paper).statusBarsPadding().padding(horizontal = 6.dp).height(52.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        PlainIconButton(Icons.AutoMirrored.Rounded.ArrowBack, "Back", onClick = onBack)
        Spacer(Modifier.weight(1f))
        Box {
            PlainIconButton(Icons.Rounded.MoreHoriz, "More") { open = true }
            androidx.compose.material3.DropdownMenu(open, { open = false }, containerColor = Hush.card) {
                menu { open = false }
            }
        }
    }
}

/** Big centred names under a cover: title, a tappable line, and a quiet detail line. */
@Composable
private fun PageTitle(title: String, subtitle: String?, detail: String, onSubtitle: (() -> Unit)?) {
    Column(Modifier.fillMaxWidth().padding(horizontal = Hush.sideMargin), horizontalAlignment = Alignment.CenterHorizontally) {
        Text(title, style = Hush.serif(31.sp), textAlign = TextAlign.Center, maxLines = 3, overflow = TextOverflow.Ellipsis)
        if (subtitle != null) {
            Spacer(Modifier.height(6.dp))
            Text(
                subtitle, style = Hush.sans(16.sp, weight = FontWeight.Medium), textAlign = TextAlign.Center,
                modifier = if (onSubtitle != null) Modifier.clickableQuiet(onSubtitle) else Modifier,
            )
        }
        Spacer(Modifier.height(4.dp))
        Text(detail, style = Hush.sans(13.sp, Hush.muted), textAlign = TextAlign.Center)
    }
}

/**
 * A page with a cover and names on top and a list below. On the Fold's wide inner screen the
 * cover and names sit on the left and the list scrolls on the right.
 */
@Composable
private fun DetailLayout(
    bottomPadding: Dp,
    bar: @Composable () -> Unit,
    header: @Composable (wide: Boolean) -> Unit,
    list: LazyListScope.() -> Unit,
) {
    BoxWithConstraints(Modifier.fillMaxSize().background(Hush.paper).blockTouches()) {
        val wide = maxWidth >= 700.dp
        Column(Modifier.fillMaxSize()) {
            bar()
            if (wide) {
                Row(Modifier.fillMaxSize()) {
                    LazyColumn(
                        Modifier.weight(0.42f).fillMaxSize(),
                        contentPadding = PaddingValues(top = 12.dp, bottom = bottomPadding + 16.dp),
                    ) { item { Column { header(true) } } }
                    LazyColumn(
                        Modifier.weight(0.58f).fillMaxSize(),
                        contentPadding = PaddingValues(top = 4.dp, bottom = bottomPadding + 16.dp),
                        content = list,
                    )
                }
            } else {
                LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(top = 8.dp, bottom = bottomPadding + 16.dp)) {
                    item { Column { header(false) } }
                    list()
                }
            }
        }
    }
}

@Composable
private fun HeaderCover(wide: Boolean, cover: @Composable (Modifier) -> Unit) {
    Box(Modifier.fillMaxWidth().padding(horizontal = if (wide) 32.dp else 52.dp), contentAlignment = Alignment.Center) {
        cover(Modifier.widthIn(max = 420.dp).fillMaxWidth())
    }
    Spacer(Modifier.height(20.dp))
}

@Composable
fun AlbumPage(key: String, bottomPadding: Dp, onBack: () -> Unit) {
    val actions = LocalActions.current
    val model = actions.model
    val album = model.library.albumsByKey[key] ?: return MissingPage(onBack)
    val player = model.player
    DetailLayout(
        bottomPadding,
        bar = {
            PageBar(onBack) { dismiss ->
                DropdownMenuItem(text = { Text("Play Next") }, onClick = { player.playNext(album.songs); dismiss() })
                DropdownMenuItem(text = { Text("Add to Queue") }, onClick = { player.addToQueue(album.songs); dismiss() })
                DropdownMenuItem(text = { Text("Go to Artist") }, onClick = { dismiss(); actions.openArtistOf(album.cover) })
            }
        },
        header = { wide ->
            HeaderCover(wide) { Cover(album.cover, it, 12.dp) }
            val detail = listOfNotNull(album.year?.toString(), "${album.songs.size} songs", durationText(album.songs.sumOf { it.durationMs })).joinToString(" · ")
            PageTitle(album.title, album.artist, detail) { actions.openArtistOf(album.cover) }
            Spacer(Modifier.height(20.dp))
            PlayShuffleButtons(album.songs, Modifier.padding(horizontal = Hush.sideMargin))
            Spacer(Modifier.height(16.dp))
        },
    ) {
        val multiDisc = album.songs.map { it.disc }.distinct().size > 1
        itemsIndexed(album.songs, key = { _, s -> s.id }) { index, song ->
            if (multiDisc && (index == 0 || album.songs[index - 1].disc != song.disc)) {
                Text("Disc ${song.disc}", style = Hush.serif(15.sp, Hush.muted), modifier = Modifier.padding(start = Hush.sideMargin, top = 12.dp, bottom = 4.dp))
            }
            TrackRow(song, player.currentId == song.mediaId, player.isPlaying) { player.play(album.songs, index) }
        }
    }
}

/** An album track: number (or bars while playing) and title. No cover, no duration. */
@OptIn(androidx.compose.foundation.ExperimentalFoundationApi::class)
@Composable
private fun TrackRow(song: Song, isCurrent: Boolean, isPlaying: Boolean, onClick: () -> Unit) {
    var menu by remember { mutableStateOf(false) }
    Box {
        Row(
            Modifier.fillMaxWidth().height(52.dp)
                .then(Modifier.combinedClickableTrack(onClick) { menu = true })
                .padding(horizontal = Hush.sideMargin),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Box(Modifier.width(22.dp), contentAlignment = Alignment.CenterEnd) {
                if (isCurrent) Equalizer(isPlaying, Modifier.size(16.dp))
                else Text(
                    if (song.track > 0) song.track.toString() else "·",
                    style = Hush.sans(15.sp, Hush.muted).copy(fontFeatureSettings = "tnum"),
                )
            }
            Spacer(Modifier.width(16.dp))
            Text(
                song.title,
                style = Hush.sans(16.sp, weight = if (isCurrent) FontWeight.SemiBold else FontWeight.Normal),
                maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f),
            )
        }
        SongMenu(listOf(song), menu, { menu = false }, song = song)
    }
}

@OptIn(androidx.compose.foundation.ExperimentalFoundationApi::class)
private fun Modifier.combinedClickableTrack(onClick: () -> Unit, onLongClick: () -> Unit): Modifier =
    combinedClickable(onClick = onClick, onLongClick = onLongClick)

@Composable
fun PlaylistPage(id: String, bottomPadding: Dp, onBack: () -> Unit) {
    val actions = LocalActions.current
    val model = actions.model
    val playlist = model.library.playlistsById[id] ?: return MissingPage(onBack)
    val player = model.player
    DetailLayout(
        bottomPadding,
        bar = {
            PageBar(onBack) { dismiss ->
                DropdownMenuItem(text = { Text("Play Next") }, onClick = { player.playNext(playlist.songs); dismiss() })
                DropdownMenuItem(text = { Text("Add to Queue") }, onClick = { player.addToQueue(playlist.songs); dismiss() })
            }
        },
        header = { wide ->
            HeaderCover(wide) { PlaylistCover(playlist, it, 12.dp) }
            val detail = listOfNotNull("${playlist.songs.size} songs", durationText(playlist.durationMs)).joinToString(" · ")
            PageTitle(playlist.name, null, detail, null)
            Spacer(Modifier.height(20.dp))
            PlayShuffleButtons(playlist.songs, Modifier.padding(horizontal = Hush.sideMargin))
            Spacer(Modifier.height(12.dp))
        },
    ) {
        itemsIndexed(playlist.songs, key = { i, s -> "$i-${s.id}" }) { index, song ->
            val isCurrent = player.currentId == song.mediaId
            SongRow(song, isCurrent, isCurrent && player.isPlaying) { player.play(playlist.songs, index) }
        }
    }
}

@Composable
fun ArtistPage(id: String, bottomPadding: Dp, onBack: () -> Unit) {
    val actions = LocalActions.current
    val model = actions.model
    val artist = model.library.artistsById[id] ?: return MissingPage(onBack)
    val player = model.player
    val favorite = model.isFavorite(id)
    DetailLayout(
        bottomPadding,
        bar = {
            PageBar(onBack) { dismiss ->
                DropdownMenuItem(
                    text = { Text(if (favorite) "Remove from Favorites" else "Add to Favorites") },
                    onClick = { model.toggleFavorite(id); dismiss() },
                )
                DropdownMenuItem(text = { Text("Play Next") }, onClick = { player.playNext(artist.songs); dismiss() })
                DropdownMenuItem(text = { Text("Add to Queue") }, onClick = { player.addToQueue(artist.songs); dismiss() })
            }
        },
        header = { wide ->
            Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
                ArtistPhoto(artist, Modifier.width(if (wide) 220.dp else 180.dp))
            }
            Spacer(Modifier.height(20.dp))
            val detail = listOfNotNull(
                "${artist.songs.size} songs",
                "${artist.albums.size} albums".takeIf { artist.albums.size > 1 },
                "Favourite".takeIf { favorite },
            ).joinToString(" · ")
            PageTitle(artist.name, null, detail, null)
            Spacer(Modifier.height(20.dp))
            PlayShuffleButtons(artist.songs, Modifier.padding(horizontal = Hush.sideMargin))
            Spacer(Modifier.height(12.dp))
        },
    ) {
        for (album in artist.albums) {
            item(key = "album-${album.albumKey}") {
                Row(
                    Modifier.fillMaxWidth().clickableQuiet { actions.open(Route.AlbumPage(album.albumKey)) }
                        .padding(horizontal = Hush.sideMargin, vertical = 12.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Cover(album.cover, Modifier.size(56.dp), 6.dp)
                    Column(Modifier.padding(start = 14.dp).weight(1f)) {
                        Text(album.title, style = Hush.serif(19.sp), maxLines = 2, overflow = TextOverflow.Ellipsis)
                        album.year?.let { Text(it.toString(), style = Hush.sub13) }
                    }
                }
            }
            items(album.songs, key = { "${album.albumKey}-${it.id}" }) { song ->
                val isCurrent = player.currentId == song.mediaId
                TrackRow(song, isCurrent, isCurrent && player.isPlaying) { player.play(artist.songs, artist.songs.indexOf(song)) }
            }
        }
    }
}

@Composable
private fun MissingPage(onBack: () -> Unit) {
    Column(Modifier.fillMaxSize().background(Hush.paper).blockTouches()) {
        PageBar(onBack) { }
        Text(
            "This is no longer on your phone.", style = Hush.sans(16.sp, Hush.muted),
            modifier = Modifier.fillMaxWidth().padding(40.dp), textAlign = TextAlign.Center,
        )
    }
}
