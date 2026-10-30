package com.pandyabhavik.hush.ui

import android.content.Context
import android.graphics.Bitmap
import android.graphics.ImageDecoder
import android.net.Uri
import android.util.LruCache
import android.util.Size
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.MusicNote
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.produceState
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.pandyabhavik.hush.data.Artist
import com.pandyabhavik.hush.data.ArtistPhotos
import com.pandyabhavik.hush.data.Playlist
import com.pandyabhavik.hush.data.Song
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/** Covers decoded from the songs' embedded artwork, kept in memory while Hush runs. */
object Covers {
    private val cache = object : LruCache<String, Bitmap>(96 * 1024 * 1024) {
        override fun sizeOf(key: String, value: Bitmap) = value.allocationByteCount
    }
    private val missing = HashSet<String>()

    /** Sizes are bucketed so a cover is decoded at most a few times. */
    fun bucket(px: Int) = when {
        px <= 160 -> 160
        px <= 480 -> 480
        else -> 1200
    }

    fun cached(key: String): Bitmap? = cache.get(key)

    suspend fun load(context: Context, uri: Uri, px: Int): Bitmap? {
        val size = bucket(px)
        val key = "$uri@$size"
        cache.get(key)?.let { return it }
        synchronized(missing) { if (key in missing) return null }
        val bitmap = withContext(Dispatchers.IO) {
            runCatching {
                if (uri.authority == "media") {
                    context.contentResolver.loadThumbnail(uri, Size(size, size), null)
                } else {
                    ImageDecoder.decodeBitmap(ImageDecoder.createSource(context.contentResolver, uri)) { decoder, info, _ ->
                        val scale = size.toFloat() / maxOf(info.size.width, info.size.height)
                        if (scale < 1f) decoder.setTargetSize((info.size.width * scale).toInt(), (info.size.height * scale).toInt())
                    }
                }
            }.getOrNull()
        }
        if (bitmap == null) synchronized(missing) { missing += key } else cache.put(key, bitmap)
        return bitmap
    }

    fun forgetMisses() = synchronized(missing) { missing.clear() }
}

@Composable
private fun rememberCover(uri: Uri?, px: Int): ImageBitmap? {
    val context = LocalContext.current
    val initial = uri?.let { Covers.cached("$it@${Covers.bucket(px)}") }?.asImageBitmap()
    val bitmap by produceState(initial, uri, px) {
        if (uri != null && value == null) value = Covers.load(context, uri, px)?.asImageBitmap()
    }
    return bitmap
}

/** A square cover with rounded corners, or a quiet placeholder when there's none. */
@Composable
fun Cover(song: Song?, modifier: Modifier = Modifier, radius: Dp = 6.dp, uri: Uri? = song?.uri, aspect: Float = 1f) {
    BoxWithConstraints(
        modifier
            .aspectRatio(aspect)
            .clip(RoundedCornerShape(radius))
            .background(Hush.card),
    ) {
        val px = with(LocalDensity.current) { maxWidth.roundToPx() }
        val bitmap = rememberCover(uri, px)
        if (bitmap != null) {
            Image(bitmap, contentDescription = null, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize())
        } else {
            Icon(
                Icons.Rounded.MusicNote, contentDescription = null, tint = Hush.tabIdle,
                modifier = Modifier.align(Alignment.Center).size(maxWidth * 0.3f),
            )
        }
    }
}

/** A playlist's own cover image, or four of its albums as a mosaic. */
@Composable
fun PlaylistCover(playlist: Playlist, modifier: Modifier = Modifier, radius: Dp = Hush.tileRadius) {
    when {
        playlist.coverUri != null -> Cover(null, modifier, radius, uri = playlist.coverUri)
        playlist.coverSongs.size == 4 -> Column(modifier.aspectRatio(1f).clip(RoundedCornerShape(radius))) {
            for (row in 0..1) Row(Modifier.weight(1f)) {
                for (col in 0..1) Cover(playlist.coverSongs[row * 2 + col], Modifier.weight(1f), 0.dp)
            }
        }
        else -> Cover(playlist.coverSongs.firstOrNull(), modifier, radius)
    }
}

/** An artist's photo in a circle: Deezer's photo, else the cover of their biggest album. */
@Composable
fun ArtistPhoto(artist: Artist, modifier: Modifier = Modifier) {
    val context = LocalContext.current
    val photo by produceState<ImageBitmap?>(null, artist.id) {
        value = ArtistPhotos.photo(context, artist)?.asImageBitmap()
    }
    Box(modifier.aspectRatio(1f).clip(CircleShape).background(Hush.card)) {
        val image = photo
        if (image != null) {
            Image(image, contentDescription = null, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize())
        } else if (artist.cover != null) {
            Cover(artist.cover, Modifier.fillMaxSize(), 0.dp)
        } else {
            Text(
                artist.name.split(' ').mapNotNull { it.firstOrNull()?.uppercaseChar() }.take(2).joinToString(""),
                style = Hush.serif(22.sp, Hush.muted),
                textAlign = TextAlign.Center,
                modifier = Modifier.align(Alignment.Center).fillMaxWidth(),
            )
        }
    }
}
