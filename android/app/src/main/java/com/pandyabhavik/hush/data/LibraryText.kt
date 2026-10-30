package com.pandyabhavik.hush.data

import java.text.Normalizer

/** Splitting and merging artist credits — the same rules as the iPhone and Mac apps. */
object ArtistCredits {
    private val separators = listOf(" featuring ", " feat. ", " feat ", " ft. ", " ft ", " Feat. ", " Feat ", " Ft. ", " FEAT. ")

    /** Splits a credit like "Arijit Singh & Shreya Ghoshal feat. X" into individual names. */
    fun names(credit: String?): List<String> {
        if (credit.isNullOrBlank()) return emptyList()
        var text = keepingGroupsTogether(credit)
        for (separator in separators) text = text.replace(separator, ",")
        return text.split(',', '&', ';', '/')
            .map { it.trim().trim('(', ')', '[', ']').trim() }
            .filter { it.isNotEmpty() && !isPlaceholder(it) }
    }

    /** Composer duos and trios that must stay one artist even when written with "&", "and" or ",". */
    private val groups: List<Pair<Regex, String>> = listOf(
        """\bVishal\s*(?:&|\band\b|-|–|,|\+)\s*Shekhar\b""" to "Vishal–Shekhar",
        """\bShankar\s*(?:&|\band\b|-|–|,)\s*Ehsaan\s*(?:&|\band\b|-|–|,)\s*Loy\b""" to "Shankar–Ehsaan–Loy",
        """\bSalim\s*(?:&|\band\b|-|–|,)\s*Sulaiman\b""" to "Salim–Sulaiman",
        """\bSajid\s*(?:&|\band\b|-|–|,)\s*Wajid\b""" to "Sajid–Wajid",
        """\bSachin\s*(?:&|\band\b|-|–|,)\s*Jigar\b""" to "Sachin–Jigar",
        """\bJatin\s*(?:&|\band\b|-|–|,)\s*Lalit\b""" to "Jatin–Lalit",
        """\bNadeem\s*(?:&|\band\b|-|–|,)\s*Shravan\b""" to "Nadeem–Shravan",
        """\bLaxmikant\s*(?:&|\band\b|-|–|,)\s*Pyarelal\b""" to "Laxmikant–Pyarelal",
        """\bKalyanji\s*(?:&|\band\b|-|–|,)\s*Anandji\b""" to "Kalyanji–Anandji",
        """\bShankar\s*(?:&|\band\b|-|–|,)\s*Jaikishan\b""" to "Shankar–Jaikishan",
        """\bAnand\s*(?:&|\band\b|-|–|,)\s*Milind\b""" to "Anand–Milind",
        """\bMeet\s+Bros\.?(?:\s+Anjjan)?""" to "Meet Bros",
    ).map { (pattern, name) -> Regex(pattern, RegexOption.IGNORE_CASE) to name }

    private fun keepingGroupsTogether(credit: String): String =
        groups.fold(credit) { text, (regex, name) -> regex.replace(text, name) }

    /** Different spellings of the same artist, merged into one. */
    private val sameArtist = mapOf(
        "arrehman" to "arrahman",
        "allahrakharahman" to "arrahman",
        "krishnakumarkunnath" to "kk",
        "vishalandshekhar" to "vishalshekhar",
        "vishalshekar" to "vishalshekhar",
        "vishalandshekar" to "vishalshekhar",
        "vishal" to "vishalshekhar",
        "shekhar" to "vishalshekhar",
        "shekar" to "vishalshekhar",
        "vishaldadlani" to "vishalshekhar",
        "shekharravjiani" to "vishalshekhar",
        "shekarravjiani" to "vishalshekhar",
        "shankarehsaanandloy" to "shankarehsaanloy",
    )

    private val preferredNames = mapOf("vishalshekhar" to "Vishal–Shekhar")

    /** Case, accents, dots and spaces don't matter: "A.R. Rahman" == "a r rahman". */
    fun key(name: String): String {
        val folded = LibrarySearch.fold(name)
        val key = folded.filter { it.isLetterOrDigit() }
        return sameArtist[key] ?: key
    }

    fun displayName(key: String): String? = preferredNames[key]

    private fun isPlaceholder(name: String): Boolean {
        val k = key(name)
        return k.isEmpty() || k == "variousartists" || k == "unknownartist" || k == "various" || k == "unknown"
    }
}

object LibraryAlphabet {
    fun section(title: String): String {
        val first = LibrarySearch.fold(title).trimStart().firstOrNull()?.uppercaseChar() ?: return "#"
        return if (first in 'A'..'Z') first.toString() else "#"
    }

    /** A–Z order, with "#" (numbers and other scripts) last, like the iPhone app. */
    val comparator: Comparator<String> = Comparator { a, b ->
        val sa = section(a)
        val sb = section(b)
        when {
            sa == "#" && sb != "#" -> 1
            sb == "#" && sa != "#" -> -1
            else -> LibrarySearch.fold(a).compareTo(LibrarySearch.fold(b))
        }
    }
}

object LibrarySearch {
    private val marks = Regex("\\p{Mn}+")

    /** Lower case, no accents: "Señorita" -> "senorita". */
    fun fold(text: String): String =
        marks.replace(Normalizer.normalize(text, Normalizer.Form.NFD), "").lowercase()

    fun key(vararg fields: String?): String = fold(fields.filterNotNull().joinToString("\n"))

    fun songsKey(songs: List<Song>): String = songs.joinToString("\n") { it.searchKey }

    fun query(text: String): String = fold(text.trim())

    /** Items matching by their own name first, then those that match only through a song. */
    fun <T> filterByNameThenSongs(items: List<T>, query: String, nameKey: (T) -> String, songsKey: (T) -> String): List<T> {
        if (query.isEmpty()) return items
        val byName = ArrayList<T>()
        val bySong = ArrayList<T>()
        for (item in items) {
            if (nameKey(item).contains(query)) byName.add(item)
            else if (songsKey(item).contains(query)) bySong.add(item)
        }
        return byName + bySong
    }
}

fun durationText(ms: Long): String? {
    val minutes = Math.round(ms / 60000.0).toInt()
    if (minutes <= 0) return null
    if (minutes < 60) return "$minutes min"
    val hours = minutes / 60
    val rest = minutes % 60
    return if (rest == 0) "$hours hr" else "$hours hr $rest min"
}

fun timeText(ms: Long): String {
    val total = (ms.coerceAtLeast(0) / 1000).toInt()
    return "%d:%02d".format(total / 60, total % 60)
}
