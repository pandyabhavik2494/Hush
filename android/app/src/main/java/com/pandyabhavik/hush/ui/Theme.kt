package com.pandyabhavik.hush.ui

import androidx.compose.animation.core.FiniteAnimationSpec
import androidx.compose.animation.core.spring
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.pandyabhavik.hush.R

/** Quiet Gallery: pure black, off-white ink, a serif for names and the system font for the rest. */
object Hush {
    val paper = Color.Black
    val ink = Color(0xFFF1EFE7)
    val muted = Color(0xFF8E8C86)
    val card = Color(0xFF151514)
    val tabIdle = Color(0xFF5F5D59)
    val track = Color(0xFF2A2A28)
    val iconOff = Color(0xFF6B6964)
    val outline = Color(0xFF3A3936)
    val line = Color(0xFF2E2C28)

    /** The tint for marks and capsules: the same off-white as the ink (content on it is black). */
    val accent = ink
    /** Placeholders, the empty playlist cover, video backgrounds. */
    val surface = Color(0xFF161514)
    /** Artist initials and the monogram glow. */
    val gold = Color(0xFFC9A86B)
    /** Menus and the fast-scroll strip: a translucent dark surface standing in for iOS glass. */
    val glass = Color(0xD91C1C1A)
    /** The faint ink edge on glass, artist circles and the mini player. */
    val edge = Color(0x14F1EFE7)

    /** Android's minimum comfortable touch target. */
    val tapTarget = 48.dp
    val tileRadius = 10.dp
    val sideMargin = 20.dp

    /** Below this width the iPhone layout is used (the Fold's cover screen). */
    val compactWidth = 600.dp

    /** Most covers are 600 x 600 px; never draw one more than ~1.3x its pixels. */
    const val coverPixels = 600
    const val maxCoverScale = 1.3f

    val serif = FontFamily.Serif
    val wordmark = FontFamily(Font(R.font.wordmark, FontWeight.SemiBold, FontStyle.Italic))

    fun serif(size: TextUnit, color: Color = ink) =
        TextStyle(fontFamily = serif, fontSize = size, color = color, fontWeight = FontWeight.Normal)

    fun sans(size: TextUnit, color: Color = ink, weight: FontWeight = FontWeight.Normal) =
        TextStyle(fontSize = size, color = color, fontWeight = weight)

    /** Digits of equal width, for track numbers and times. */
    fun mono(size: TextUnit, color: Color = muted, weight: FontWeight = FontWeight.Normal) =
        sans(size, color, weight).copy(fontFeatureSettings = "tnum")

    /** Large serif titles: library tabs and album pages (−0.3 pt), playlist and artist pages (−0.5 pt). */
    fun serifTitle(size: TextUnit, tracking: TextUnit = (-0.3).sp, color: Color = ink) =
        serif(size, color).copy(letterSpacing = tracking)

    val title16 = sans(16.sp, weight = FontWeight.Medium)
    val sub13 = sans(13.5.sp, muted)

    // Springs converted from the iPhone app: spring(response r, damping ζ) = spring(ζ, (2π / r)²).
    /** Tile press, iPhone TilePressStyle (0.26 s, 0.72). */
    val tilePress: FiniteAnimationSpec<Float> get() = spring(dampingRatio = 0.72f, stiffness = 584f)
    /** Play, Shuffle and other pop buttons, iPhone PopButtonStyle (0.25 s, 0.5). */
    val popPress: FiniteAnimationSpec<Float> get() = spring(dampingRatio = 0.5f, stiffness = 632f)
    /** Tab changes and the tab strip centering, iPhone .snappy(0.3). */
    val snappy: FiniteAnimationSpec<Float> get() = spring(dampingRatio = 0.85f, stiffness = 439f)
}
