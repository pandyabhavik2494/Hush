package com.pandyabhavik.hush.ui

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

    val tapTarget = 44.dp
    val tileRadius = 10.dp
    val sideMargin = 20.dp

    val serif = FontFamily.Serif
    val wordmark = FontFamily(Font(R.font.wordmark, FontWeight.SemiBold, FontStyle.Italic))

    fun serif(size: TextUnit, color: Color = ink) =
        TextStyle(fontFamily = serif, fontSize = size, color = color, fontWeight = FontWeight.Normal)

    fun sans(size: TextUnit, color: Color = ink, weight: FontWeight = FontWeight.Normal) =
        TextStyle(fontSize = size, color = color, fontWeight = weight)

    val title16 = sans(16.sp, weight = FontWeight.Medium)
    val sub13 = sans(13.5.sp, muted)
}
