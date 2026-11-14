package com.pandyabhavik.hush.playback

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.os.Build

/** The phone's own ways to play sound: its speaker, and Bluetooth, wired and USB outputs. */
object PhoneOutputs {
    val external = setOf(
        AudioDeviceInfo.TYPE_BLUETOOTH_A2DP,
        AudioDeviceInfo.TYPE_BLE_HEADSET,
        AudioDeviceInfo.TYPE_BLE_SPEAKER,
        AudioDeviceInfo.TYPE_WIRED_HEADPHONES,
        AudioDeviceInfo.TYPE_WIRED_HEADSET,
        AudioDeviceInfo.TYPE_USB_HEADSET,
        AudioDeviceInfo.TYPE_USB_DEVICE,
        AudioDeviceInfo.TYPE_HEARING_AID,
        AudioDeviceInfo.TYPE_HDMI,
        AudioDeviceInfo.TYPE_LINE_ANALOG,
        AudioDeviceInfo.TYPE_LINE_DIGITAL,
        AudioDeviceInfo.TYPE_DOCK,
    )

    private val bluetooth = setOf(
        AudioDeviceInfo.TYPE_BLUETOOTH_A2DP,
        AudioDeviceInfo.TYPE_BLE_HEADSET,
        AudioDeviceInfo.TYPE_BLE_SPEAKER,
        AudioDeviceInfo.TYPE_HEARING_AID,
    )

    fun isBluetooth(device: AudioDeviceInfo) = device.type in bluetooth
    fun isSpeaker(device: AudioDeviceInfo) = device.type == AudioDeviceInfo.TYPE_BUILTIN_SPEAKER

    /** The phone's speaker first, then each connected output once. */
    fun list(context: Context): List<AudioDeviceInfo> {
        val audio = context.getSystemService(AudioManager::class.java) ?: return emptyList()
        val all = audio.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
        val speaker = all.firstOrNull { isSpeaker(it) }
        // A Bluetooth device can show up twice (classic and LE Audio): keep the first of each name.
        val others = all.filter { it.type in external }.distinctBy { "${it.productName}" + if (isBluetooth(it)) "" else it.type }
        return listOfNotNull(speaker) + others
    }

    /** Where Android sends music right now, when it says (Android 13 and later). */
    fun active(context: Context): AudioDeviceInfo? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return null
        val audio = context.getSystemService(AudioManager::class.java) ?: return null
        val attributes = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_MEDIA)
            .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
            .build()
        val routed = runCatching { audio.getAudioDevicesForAttributes(attributes) }.getOrNull()?.firstOrNull() ?: return null
        return list(context).firstOrNull { it.type == routed.type && "${it.productName}" == "${routed.productName}" }
            ?: list(context).firstOrNull { it.type == routed.type }
    }

    fun name(device: AudioDeviceInfo): String = when (device.type) {
        AudioDeviceInfo.TYPE_BUILTIN_SPEAKER -> "This Phone"
        AudioDeviceInfo.TYPE_WIRED_HEADPHONES, AudioDeviceInfo.TYPE_WIRED_HEADSET -> "Headphones"
        else -> device.productName?.toString()?.takeIf { it.isNotBlank() } ?: "Bluetooth device"
    }

    fun kind(device: AudioDeviceInfo): String = when (device.type) {
        AudioDeviceInfo.TYPE_BUILTIN_SPEAKER -> "Speaker"
        AudioDeviceInfo.TYPE_WIRED_HEADPHONES, AudioDeviceInfo.TYPE_WIRED_HEADSET -> "Wired"
        AudioDeviceInfo.TYPE_USB_HEADSET, AudioDeviceInfo.TYPE_USB_DEVICE -> "USB"
        AudioDeviceInfo.TYPE_HDMI -> "HDMI"
        in bluetooth -> "Bluetooth"
        else -> "Connected"
    }
}
