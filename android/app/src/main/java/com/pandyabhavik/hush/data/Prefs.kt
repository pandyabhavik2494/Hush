package com.pandyabhavik.hush.data

import android.content.Context
import android.content.SharedPreferences
import org.json.JSONObject

/** Small settings kept between launches. */
class Prefs(context: Context) {
    private val prefs: SharedPreferences = context.getSharedPreferences("hush", Context.MODE_PRIVATE)

    var favoriteArtists: Set<String>
        get() = prefs.getStringSet("favoriteArtists", emptySet())!!.toSet()
        set(value) = prefs.edit().putStringSet("favoriteArtists", value).apply()

    var playlistsFolder: String?
        get() = prefs.getString("playlistsFolder", null)
        set(value) = prefs.edit().putString("playlistsFolder", value).apply()

    var videosFolder: String?
        get() = prefs.getString("videosFolder", null)
        set(value) = prefs.edit().putString("videosFolder", value).apply()

    fun getString(key: String, default: String): String = prefs.getString(key, default) ?: default
    fun putString(key: String, value: String) = prefs.edit().putString(key, value).apply()
    fun getBoolean(key: String, default: Boolean): Boolean = prefs.getBoolean(key, default)
    fun putBoolean(key: String, value: Boolean) = prefs.edit().putBoolean(key, value).apply()

    /** Plays counted by Hush itself (Android keeps no play counts). */
    fun playCounts(): Map<Long, Int> {
        val json = JSONObject(prefs.getString("playCounts", "{}") ?: "{}")
        return json.keys().asSequence().associate { it.toLong() to json.getInt(it) }
    }

    fun countPlay(songId: Long) {
        val json = JSONObject(prefs.getString("playCounts", "{}") ?: "{}")
        json.put(songId.toString(), json.optInt(songId.toString()) + 1)
        prefs.edit().putString("playCounts", json.toString()).apply()
    }

    /** The queue as it was, so it comes back after Hush is closed. */
    fun saveSession(ids: List<String>, index: Int, positionMs: Long) {
        prefs.edit()
            .putString("session.ids", ids.joinToString(","))
            .putInt("session.index", index)
            .putLong("session.position", positionMs)
            .apply()
    }

    fun saveSessionPlace(index: Int, positionMs: Long) {
        prefs.edit().putInt("session.index", index).putLong("session.position", positionMs).apply()
    }

    fun savePosition(positionMs: Long) = prefs.edit().putLong("session.position", positionMs).apply()

    fun session(): Triple<List<String>, Int, Long>? {
        val ids = prefs.getString("session.ids", null)?.split(",")?.filter { it.isNotBlank() } ?: return null
        if (ids.isEmpty()) return null
        return Triple(ids, prefs.getInt("session.index", 0), prefs.getLong("session.position", 0))
    }
}
