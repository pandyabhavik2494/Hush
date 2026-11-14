package com.pandyabhavik.hush.playback

import android.media.AudioDeviceInfo
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue

/**
 * Where music plays, shared by the player screen and [PlaybackService] (they run in the same
 * process): the phone and what's plugged into or paired with it, or a speaker on the Wi-Fi.
 */
object Speakers {
    /** Speakers found on the Wi-Fi the last time the picker looked. */
    var found by mutableStateOf<List<Speaker>>(emptyList())
    var searching by mutableStateOf(false)

    /** The Wi-Fi speaker playing now; null when the phone plays (through whatever output). */
    var current by mutableStateOf<Speaker?>(null); internal set
    /** Set while Hush is handing the music to a speaker. */
    var connecting by mutableStateOf<Speaker?>(null); internal set
    /** The Wi-Fi speaker's volume, 0 to 100. */
    var volume by mutableIntStateOf(0); internal set
    /** The phone output Hush was told to use; null for Android's own choice. */
    var phoneOutput by mutableStateOf<Int?>(null); internal set
    /** Something that went wrong with a speaker, for the picker to show once. */
    var problem by mutableStateOf<String?>(null)

    internal var service: PlaybackService? = null

    fun playOn(speaker: Speaker) {
        service?.useSpeaker(speaker)
    }

    /** Back to the phone; [device] picks one of its outputs (null: Android's choice). */
    fun playOnPhone(device: AudioDeviceInfo?) {
        service?.usePhone(device)
    }

    fun setVolume(value: Int) {
        service?.setSpeakerVolume(value)
    }
}
