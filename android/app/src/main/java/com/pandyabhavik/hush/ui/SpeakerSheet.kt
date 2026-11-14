package com.pandyabhavik.hush.ui

import android.content.Intent
import android.media.AudioDeviceCallback
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.VolumeDown
import androidx.compose.material.icons.automirrored.rounded.VolumeUp
import androidx.compose.material.icons.rounded.Bluetooth
import androidx.compose.material.icons.rounded.Cable
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.Headphones
import androidx.compose.material.icons.rounded.PhoneAndroid
import androidx.compose.material.icons.rounded.Speaker
import androidx.compose.material.icons.rounded.SpeakerGroup
import androidx.compose.material.icons.rounded.Tv
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.pandyabhavik.hush.playback.PhoneOutputs
import com.pandyabhavik.hush.playback.Speaker
import com.pandyabhavik.hush.playback.Speakers
import com.pandyabhavik.hush.playback.Upnp
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext

/**
 * "Play On": the phone and what's connected to it (Bluetooth headphones and speakers, wired, USB),
 * then Sonos rooms and other speakers found on the Wi-Fi. A sheet on the cover screen, a card in
 * the middle of the unfolded screen.
 */
@Composable
fun SpeakerSheet(onClose: () -> Unit) {
    Dialog(onDismissRequest = onClose, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        BoxWithConstraints(
            Modifier
                .fillMaxSize()
                .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null, onClick = onClose),
        ) {
            val wide = maxWidth >= 600.dp
            val shape = if (wide) RoundedCornerShape(24.dp) else RoundedCornerShape(topStart = 22.dp, topEnd = 22.dp)
            Column(
                Modifier
                    .align(if (wide) Alignment.Center else Alignment.BottomCenter)
                    .then(if (wide) Modifier.width(440.dp) else Modifier.fillMaxWidth())
                    .heightIn(max = maxHeight * 0.85f)
                    .clip(shape)
                    .background(Color(0xFF1C1C1A))
                    .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null) {}
                    .then(if (wide) Modifier else Modifier.navigationBarsPadding()),
            ) {
                if (!wide) {
                    Box(
                        Modifier.align(Alignment.CenterHorizontally).padding(top = 8.dp).size(width = 36.dp, height = 5.dp)
                            .clip(CircleShape).background(Hush.muted.copy(alpha = 0.6f)),
                    )
                }
                Text(
                    "Play On",
                    style = Hush.sans(17.sp, Hush.ink, FontWeight.SemiBold),
                    modifier = Modifier.align(Alignment.CenterHorizontally).padding(top = 14.dp, bottom = 8.dp),
                )
                Column(Modifier.verticalScroll(rememberScrollState()).padding(bottom = 12.dp)) {
                    SpeakerList(onClose)
                }
            }
        }
    }
}

@Composable
private fun SpeakerList(onClose: () -> Unit) {
    val context = LocalContext.current

    // The phone's outputs, read again whenever something connects or disconnects.
    var outputsVersion by remember { mutableIntStateOf(0) }
    DisposableEffect(Unit) {
        val audio = context.getSystemService(AudioManager::class.java)
        val callback = object : AudioDeviceCallback() {
            override fun onAudioDevicesAdded(addedDevices: Array<out AudioDeviceInfo>) { outputsVersion++ }
            override fun onAudioDevicesRemoved(removedDevices: Array<out AudioDeviceInfo>) { outputsVersion++ }
        }
        audio?.registerAudioDeviceCallback(callback, Handler(Looper.getMainLooper()))
        onDispose { audio?.unregisterAudioDeviceCallback(callback) }
    }
    val outputs = remember(outputsVersion) { PhoneOutputs.list(context) }
    val routed = remember(outputsVersion, Speakers.phoneOutput, Speakers.current) { PhoneOutputs.active(context) }

    // Look for Wi-Fi speakers while the sheet is open.
    var searchedOnce by remember { mutableStateOf(Speakers.found.isNotEmpty()) }
    LaunchedEffect(Unit) {
        while (true) {
            Speakers.searching = true
            val found = withContext(Dispatchers.IO) { runCatching { Upnp.search(context) }.getOrDefault(emptyList()) }
            // Keep the speaker playing listed even if it missed this round.
            val playing = Speakers.current
            Speakers.found = if (playing != null && found.none { it.id == playing.id }) (found + playing).sortedBy { it.name.lowercase() } else found
            Speakers.searching = false
            searchedOnce = true
            delay(10_000)
        }
    }
    DisposableEffect(Unit) { onDispose { Speakers.searching = false } }

    val onSpeaker = Speakers.current == null && Speakers.connecting == null
    SectionLabel("This Phone")
    for (device in outputs) {
        val selected = onSpeaker && when {
            Speakers.phoneOutput != null -> Speakers.phoneOutput == device.id
            routed != null -> routed.id == device.id
            else -> device == outputs.lastOrNull()
        }
        OutputRow(
            icon = when {
                PhoneOutputs.isSpeaker(device) -> Icons.Rounded.PhoneAndroid
                PhoneOutputs.isBluetooth(device) -> Icons.Rounded.Bluetooth
                device.type == AudioDeviceInfo.TYPE_HDMI -> Icons.Rounded.Tv
                device.type == AudioDeviceInfo.TYPE_WIRED_HEADPHONES || device.type == AudioDeviceInfo.TYPE_WIRED_HEADSET -> Icons.Rounded.Headphones
                else -> Icons.Rounded.Cable
            },
            title = PhoneOutputs.name(device),
            detail = PhoneOutputs.kind(device),
            selected = selected,
        ) {
            // The phone's speaker with nothing else connected: just let Android choose.
            val only = PhoneOutputs.isSpeaker(device) && outputs.size == 1
            Speakers.playOnPhone(if (only) null else device)
            onClose()
        }
    }
    OutputRow(Icons.Rounded.Bluetooth, "Connect a Bluetooth device", "Opens Bluetooth settings", selected = false, quiet = true) {
        runCatching { context.startActivity(Intent(Settings.ACTION_BLUETOOTH_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) }
    }

    Spacer(Modifier.height(10.dp))
    Row(Modifier.fillMaxWidth().padding(end = 24.dp), verticalAlignment = Alignment.CenterVertically) {
        SectionLabel("On Wi-Fi", Modifier.weight(1f))
        if (Speakers.searching) CircularProgressIndicator(Modifier.size(14.dp), color = Hush.muted, strokeWidth = 1.5.dp)
    }
    if (Speakers.found.isEmpty()) {
        Text(
            if (searchedOnce && !Speakers.searching) {
                "No speakers found. Check that the phone is on the same Wi-Fi as your Sonos."
            } else {
                "Looking for Sonos and other speakers…"
            },
            style = Hush.sans(14.sp, Hush.muted),
            modifier = Modifier.padding(horizontal = 24.dp, vertical = 10.dp),
        )
    }
    for (speaker in Speakers.found) {
        val current = Speakers.current?.id == speaker.id
        OutputRow(
            icon = if (speaker.detail.contains("rooms")) Icons.Rounded.SpeakerGroup else Icons.Rounded.Speaker,
            title = speaker.name,
            detail = speaker.detail,
            selected = current,
            busy = Speakers.connecting?.id == speaker.id,
        ) {
            if (!current) Speakers.playOn(speaker)
        }
        if (current) SpeakerVolume(speaker)
    }

    Speakers.problem?.let { problem ->
        Text(problem, style = Hush.sans(14.sp, Hush.gold), modifier = Modifier.padding(horizontal = 24.dp, vertical = 10.dp))
    }
}

@Composable
private fun SectionLabel(text: String, modifier: Modifier = Modifier) {
    Text(
        text.uppercase(),
        style = Hush.sans(12.sp, Hush.muted, FontWeight.SemiBold).copy(letterSpacing = 0.8.sp),
        modifier = modifier.padding(start = 24.dp, top = 10.dp, bottom = 6.dp),
    )
}

@Composable
private fun OutputRow(
    icon: ImageVector, title: String, detail: String, selected: Boolean,
    busy: Boolean = false, quiet: Boolean = false, onClick: () -> Unit,
) {
    Row(
        Modifier
            .fillMaxWidth()
            .heightIn(min = 60.dp)
            .clickable(role = Role.Button, onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            Modifier.size(40.dp).clip(CircleShape)
                .background(if (selected) Hush.gold.copy(alpha = 0.18f) else Color.White.copy(alpha = 0.07f)),
            contentAlignment = Alignment.Center,
        ) {
            Icon(icon, contentDescription = null, tint = if (selected) Hush.gold else if (quiet) Hush.muted else Hush.ink, modifier = Modifier.size(22.dp))
        }
        Spacer(Modifier.width(14.dp))
        Column(Modifier.weight(1f)) {
            Text(
                title, style = Hush.sans(16.sp, if (quiet) Hush.muted else Hush.ink, if (selected) FontWeight.SemiBold else FontWeight.Normal),
                maxLines = 1, overflow = TextOverflow.Ellipsis,
            )
            Text(detail, style = Hush.sans(13.sp, Hush.muted), maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        when {
            busy -> CircularProgressIndicator(Modifier.size(20.dp), color = Hush.gold, strokeWidth = 2.dp)
            selected -> Icon(Icons.Rounded.Check, contentDescription = "Playing here", tint = Hush.gold, modifier = Modifier.size(22.dp))
        }
    }
}

/** The Wi-Fi speaker's volume (the whole group's, for Sonos). The phone's volume keys work too. */
@Composable
private fun SpeakerVolume(speaker: Speaker) {
    var dragging by remember { mutableStateOf(false) }
    var value by remember { mutableFloatStateOf(Speakers.volume / 100f) }
    LaunchedEffect(Speakers.volume) { if (!dragging) value = Speakers.volume / 100f }
    Row(
        Modifier.fillMaxWidth().padding(start = 70.dp, end = 20.dp, bottom = 6.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Icon(Icons.AutoMirrored.Rounded.VolumeDown, contentDescription = null, tint = Hush.muted, modifier = Modifier.size(20.dp))
        Slider(
            value = value,
            onValueChange = {
                dragging = true
                value = it
                Speakers.setVolume((it * 100).toInt())
            },
            onValueChangeFinished = { dragging = false },
            colors = SliderDefaults.colors(
                thumbColor = Hush.ink,
                activeTrackColor = Hush.gold,
                inactiveTrackColor = Color.White.copy(alpha = 0.15f),
            ),
            modifier = Modifier.weight(1f),
        )
        Icon(Icons.AutoMirrored.Rounded.VolumeUp, contentDescription = "${speaker.name} volume", tint = Hush.muted, modifier = Modifier.size(20.dp))
    }
}
