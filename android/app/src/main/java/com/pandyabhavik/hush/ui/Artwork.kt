package com.pandyabhavik.hush.ui

import android.content.Context
import android.graphics.Bitmap
import android.graphics.ColorMatrix
import android.graphics.ColorMatrixColorFilter
import android.graphics.ImageDecoder
import android.media.MediaMetadataRetriever
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
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.GraphicEq
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.FilterQuality
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.Paint
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.drawscope.drawIntoCanvas
import androidx.compose.ui.graphics.toArgb
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
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withPermit
import kotlinx.coroutines.withContext
import java.nio.ByteBuffer
import java.util.concurrent.ConcurrentHashMap
import kotlin.math.max
import kotlin.math.roundToInt

/**
 * Covers decoded from the songs' embedded artwork, kept in memory while Hush runs.
 *
 * A cover is decoded at a size bucket, but never above its own pixels: a 300 px cover asked for
 * at 1200 stays 300 px, so [Cover] can tell how big it may be drawn without looking soft.
 */
object Covers {
    private val cache = object : LruCache<String, Bitmap>(96 * 1024 * 1024) {
        override fun sizeOf(key: String, value: Bitmap) = value.allocationByteCount
    }
    private val missing = HashSet<String>()
    private val frames = Semaphore(2)
    private val reads = Semaphore(4)

    /** The long side, in pixels, of each cover as it is in the file. */
    private val sources = ConcurrentHashMap<String, Int>()

    private val buckets = intArrayOf(160, 320, 480, 720, 1200)

    /** Sizes are bucketed so a cover is decoded at most a few times. */
    fun bucket(px: Int): Int = buckets.firstOrNull { px <= it } ?: buckets.last()

    fun cached(key: String): Bitmap? = cache.get(key)

    /** The cover's real long side in pixels, once it has been read. */
    fun sourcePx(uri: Uri): Int? = sources[uri.toString()]

    suspend fun load(context: Context, uri: Uri, px: Int, videoFrame: Boolean = false): Bitmap? {
        val size = bucket(px)
        val key = "$uri@$size"
        cache.get(key)?.let { return it }
        synchronized(missing) { if (key in missing) return null }
        if (videoFrame) {
            // Video decoders are few: read two frames at a time, and don't remember a failure,
            // which may only mean the decoders were busy.
            val frame = frames.withPermit { withContext(Dispatchers.IO) { runCatching { frame(context, uri, size) }.getOrNull() } }
            frame?.let { cache.put(key, it) }
            return frame
        }
        val bitmap = reads.withPermit {
            withContext(Dispatchers.IO) { runCatching { decode(context, uri, size) }.getOrNull() }
        }
        if (bitmap == null) synchronized(missing) { missing += key } else cache.put(key, bitmap)
        return bitmap
    }

    private fun decode(context: Context, uri: Uri, size: Int): Bitmap? {
        if (uri.authority == "media") {
            // A song: read its embedded picture ourselves, so it is only ever shrunk.
            embeddedPicture(context, uri)?.let { bytes ->
                runCatching { shrink(ImageDecoder.createSource(ByteBuffer.wrap(bytes)), uri, size) }.getOrNull()?.let { return it }
            }
            // No embedded picture (folder art, say): MediaStore's thumbnail, at most the size asked.
            val thumb = context.contentResolver.loadThumbnail(uri, Size(size, size), null)
            sources.putIfAbsent(uri.toString(), max(thumb.width, thumb.height))
            return thumb
        }
        return shrink(ImageDecoder.createSource(context.contentResolver, uri), uri, size)
    }

    /** Decodes [source] to fit [size], scaling down only. */
    private fun shrink(source: ImageDecoder.Source, uri: Uri, size: Int): Bitmap =
        ImageDecoder.decodeBitmap(source) { decoder, info, _ ->
            val long = max(info.size.width, info.size.height)
            sources[uri.toString()] = long
            val scale = size.toFloat() / long
            if (scale < 1f) {
                decoder.setTargetSize(
                    (info.size.width * scale).roundToInt().coerceAtLeast(1),
                    (info.size.height * scale).roundToInt().coerceAtLeast(1),
                )
            }
        }

    private fun embeddedPicture(context: Context, uri: Uri): ByteArray? {
        val retriever = MediaMetadataRetriever()
        return try {
            retriever.setDataSource(context, uri)
            retriever.embeddedPicture
        } catch (_: Exception) {
            null
        } finally {
            runCatching { retriever.release() }
        }
    }

    /** A frame a little way in (music videos often open on black), scaled to fit [size]. */
    private fun frame(context: Context, uri: Uri, size: Int): Bitmap? {
        val retriever = MediaMetadataRetriever()
        return try {
            retriever.setDataSource(context, uri)
            val duration = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0L
            val atUs = minOf(duration / 4, 30_000L) * 1000
            retriever.getScaledFrameAtTime(atUs, MediaMetadataRetriever.OPTION_CLOSEST_SYNC, size, size)
                ?: retriever.embeddedPicture?.let { android.graphics.BitmapFactory.decodeByteArray(it, 0, it.size) }
        } finally {
            runCatching { retriever.release() }
        }
    }

    fun forgetMisses() = synchronized(missing) { missing.clear() }
}

/**
 * The colours of a cover's top and bottom edges (port of Shared/ArtworkColors.swift), which the
 * Now Playing screen paints its background with.
 */
object ArtworkColors {
    @Immutable
    data class Edges(val top: Color, val bottom: Color)

    private val cache = LruCache<String, Edges>(120)

    fun cached(uri: Uri): Edges? = cache.get(uri.toString())

    /** The edge colours of the cover at [uri], or null when there is no cover. */
    suspend fun edges(context: Context, uri: Uri): Edges? {
        cache.get(uri.toString())?.let { return it }
        val bitmap = Covers.load(context, uri, 240) ?: return null
        val edges = withContext(Dispatchers.Default) { runCatching { edgeColors(bitmap) }.getOrNull() } ?: return null
        cache.put(uri.toString(), edges)
        return edges
    }

    /**
     * Reads the cover's colour along its top edge and along its bottom edge (a strip a tenth of
     * the cover high each), a touch more saturated so it stays lively once shaded.
     */
    fun edgeColors(source: Bitmap): Edges {
        val soft = if (source.config == Bitmap.Config.HARDWARE) source.copy(Bitmap.Config.ARGB_8888, false) else source
        val width = 240
        val height = (soft.height * width.toFloat() / soft.width.coerceAtLeast(1)).roundToInt().coerceAtLeast(1)
        val saturated = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val paint = android.graphics.Paint(android.graphics.Paint.FILTER_BITMAP_FLAG).apply {
            colorFilter = ColorMatrixColorFilter(ColorMatrix().apply { setSaturation(1.3f) })
        }
        android.graphics.Canvas(saturated).drawBitmap(soft, null, android.graphics.Rect(0, 0, width, height), paint)
        val strip = (height * 0.1f).roundToInt().coerceIn(1, height)
        val top = dominantColor(Bitmap.createBitmap(saturated, 0, 0, width, strip))
        val bottom = dominantColor(Bitmap.createBitmap(saturated, 0, height - strip, width, strip))
        return Edges(top, bottom)
    }

    /**
     * The most common colour in a strip. A plain average turns a mixed edge into grey; this finds
     * the biggest group of similar pixels and averages only those.
     */
    private fun dominantColor(strip: Bitmap): Color {
        val columns = 48
        val rows = (strip.height * columns.toFloat() / strip.width.coerceAtLeast(1)).roundToInt().coerceAtLeast(1)
        val small = Bitmap.createScaledBitmap(strip, columns, rows, true)
        val pixels = IntArray(columns * rows)
        small.getPixels(pixels, 0, columns, 0, 0, columns, rows)
        val counts = IntArray(64)
        val reds = IntArray(64)
        val greens = IntArray(64)
        val blues = IntArray(64)
        for (pixel in pixels) {
            val red = (pixel shr 16) and 0xFF
            val green = (pixel shr 8) and 0xFF
            val blue = pixel and 0xFF
            val group = ((red shr 6) shl 4) or ((green shr 6) shl 2) or (blue shr 6)
            counts[group]++
            reds[group] += red
            greens[group] += green
            blues[group] += blue
        }
        var biggest = 0
        for (i in counts.indices) if (counts[i] > counts[biggest]) biggest = i
        if (counts[biggest] == 0) return Color.Black
        val total = counts[biggest] * 255f
        return Color(reds[biggest] / total, greens[biggest] / total, blues[biggest] / total)
    }
}

fun Color.brightness(): Float = 0.299f * red + 0.587f * green + 0.114f * blue

/** A soft drop shadow, like SwiftUI's: [blur] is the Gaussian radius, [y] the downward offset. */
@Immutable
data class CoverShadow(val color: Color = Color.Black.copy(alpha = 0.45f), val blur: Dp = 24.dp, val y: Dp = 14.dp)

/** Draws [shadow] behind a rounded rectangle the size of the element. */
fun Modifier.softShadow(shadow: CoverShadow, radius: Dp): Modifier = drawBehind {
    val paint = Paint()
    paint.asFrameworkPaint().apply {
        isAntiAlias = true
        color = android.graphics.Color.BLACK
        setShadowLayer(shadow.blur.toPx(), 0f, shadow.y.toPx(), shadow.color.toArgb())
    }
    drawIntoCanvas { it.drawRoundRect(0f, 0f, size.width, size.height, radius.toPx(), radius.toPx(), paint) }
}

/** The artwork placeholder: a warm gradient with a waveform. */
private val placeholderBrush = Brush.linearGradient(listOf(Color(0xFF876426), Color(0xFF332914)))

@Composable
private fun rememberCover(uri: Uri?, px: Int, videoFrame: Boolean): ImageBitmap? {
    val context = LocalContext.current
    val size = Covers.bucket(px)
    // Keyed on the cover itself: when the song changes, the old picture must not stay behind.
    val bitmap = remember(uri, size) { mutableStateOf(uri?.let { Covers.cached("$it@$size") }?.asImageBitmap()) }
    LaunchedEffect(uri, size) {
        if (uri != null && bitmap.value == null) bitmap.value = Covers.load(context, uri, px, videoFrame)?.asImageBitmap()
    }
    return bitmap.value
}

/**
 * A square cover with rounded corners, or a quiet placeholder when there's none.
 *
 * The picture is never stretched: it is drawn at most [maxUpscale] times its own pixel size, and
 * when the space given is bigger than that the cover is drawn smaller, placed by [alignment].
 * [shadow] draws a soft shadow under the (possibly smaller) cover.
 */
@Composable
fun Cover(
    song: Song?, modifier: Modifier = Modifier, radius: Dp = 6.dp, uri: Uri? = song?.uri, aspect: Float = 1f, videoFrame: Boolean = false,
    maxUpscale: Float = 1.3f, shadow: CoverShadow? = null, alignment: Alignment = Alignment.Center,
) {
    BoxWithConstraints(modifier.aspectRatio(aspect), contentAlignment = alignment) {
        val density = LocalDensity.current
        val boxWidth = if (maxWidth == Dp.Infinity) 480.dp else maxWidth
        val px = with(density) { boxWidth.roundToPx() }
        val bitmap = rememberCover(uri, px, videoFrame)
        val cap = if (bitmap != null && !videoFrame && maxUpscale > 0f) with(density) { (bitmap.width * maxUpscale).toDp() } else Dp.Infinity
        val shape = RoundedCornerShape(radius)
        Box(
            Modifier
                .widthIn(max = cap)
                .fillMaxWidth()
                .aspectRatio(aspect)
                .then(if (shadow != null) Modifier.softShadow(shadow, radius) else Modifier)
                .clip(shape)
                .then(if (bitmap != null) Modifier.background(Hush.card) else Modifier.background(placeholderBrush)),
        ) {
            if (bitmap != null) {
                Image(
                    bitmap, contentDescription = null, contentScale = ContentScale.Crop,
                    filterQuality = FilterQuality.High, modifier = Modifier.fillMaxSize(),
                )
            } else {
                Icon(
                    Icons.Rounded.GraphicEq, contentDescription = null, tint = Color.White.copy(alpha = 0.75f),
                    modifier = Modifier.align(Alignment.Center).size(minOf(boxWidth, cap) * 0.28f),
                )
            }
        }
    }
}

/** A playlist's own cover image, or four of its albums as a mosaic. */
@Composable
fun PlaylistCover(playlist: Playlist, modifier: Modifier = Modifier, radius: Dp = Hush.tileRadius, shadow: CoverShadow? = null) {
    when {
        playlist.coverUri != null -> Cover(null, modifier, radius, uri = playlist.coverUri, shadow = shadow)
        playlist.coverSongs.size == 4 -> Column(
            modifier
                .aspectRatio(1f)
                .then(if (shadow != null) Modifier.softShadow(shadow, radius) else Modifier)
                .clip(RoundedCornerShape(radius)),
        ) {
            for (row in 0..1) Row(Modifier.weight(1f)) {
                // Each quarter fills its cell exactly, so the mosaic has no gaps.
                for (col in 0..1) Cover(playlist.coverSongs[row * 2 + col], Modifier.weight(1f), 0.dp, maxUpscale = 0f)
            }
        }
        else -> Cover(playlist.coverSongs.firstOrNull(), modifier, radius, shadow = shadow)
    }
}

/** An artist's photo in a circle: Deezer's photo, else the cover of their biggest album. */
@Composable
fun ArtistPhoto(artist: Artist, modifier: Modifier = Modifier, shadow: CoverShadow? = null) {
    val context = LocalContext.current
    val photo = remember(artist.id) { mutableStateOf<ImageBitmap?>(null) }
    LaunchedEffect(artist.id) { photo.value = ArtistPhotos.photo(context, artist)?.asImageBitmap() }
    val shape: Shape = CircleShape
    BoxWithConstraints(modifier.aspectRatio(1f), contentAlignment = Alignment.Center) {
        val image = photo.value
        val cap = if (image != null) with(LocalDensity.current) { (minOf(image.width, image.height) * 1.3f).toDp() } else Dp.Infinity
        Box(
            Modifier
                .widthIn(max = cap)
                .fillMaxWidth()
                .aspectRatio(1f)
                .then(if (shadow != null) Modifier.softShadow(shadow, 1000.dp) else Modifier)
                .clip(shape)
                .background(Hush.card),
        ) {
            if (image != null) {
                Image(
                    image, contentDescription = null, contentScale = ContentScale.Crop,
                    filterQuality = FilterQuality.High, modifier = Modifier.fillMaxSize(),
                )
            } else if (artist.cover != null) {
                Cover(artist.cover, Modifier.fillMaxSize(), 0.dp, maxUpscale = 0f)
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
}
