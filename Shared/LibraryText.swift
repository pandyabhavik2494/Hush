import Foundation

/// Where the current music was started from — shown as "Playing from …" in the player, which
/// takes you back there.
enum PlaybackSource: Hashable, Codable {
    case album(UInt64)
    case artist(String)
    case playlist(UInt64)
}

enum ArtistCredits {
    /// Splits a credit like "Arijit Singh & Shreya Ghoshal feat. X" into individual names.
    /// Deliberately doesn't split on "and" (band names like "Simon and Garfunkel").
    static func names(in credit: String?) -> [String] {
        guard let credit, !credit.isEmpty else { return [] }
        var text = keepingGroupsTogether(credit)
        for separator in [" featuring ", " feat. ", " feat ", " ft. ", " ft ", " Feat. ", " Feat ", " Ft. ", " FEAT. "] {
            text = text.replacingOccurrences(of: separator, with: ",")
        }
        return text
            .components(separatedBy: CharacterSet(charactersIn: ",&;/"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "()[]")) }
            .filter { !$0.isEmpty && !isPlaceholder($0) }
    }

    /// Composer duos and trios that must stay one artist even when written with "&", "and" or ",".
    /// Each is rewritten with en dashes (which aren't split on) before a credit is split.
    private static let groups: [(pattern: String, name: String)] = [
        (#"\bVishal\s*(?:&|\band\b|-|–|,|\+)\s*Shekhar\b"#, "Vishal–Shekhar"),
        (#"\bShankar\s*(?:&|\band\b|-|–|,)\s*Ehsaan\s*(?:&|\band\b|-|–|,)\s*Loy\b"#, "Shankar–Ehsaan–Loy"),
        (#"\bSalim\s*(?:&|\band\b|-|–|,)\s*Sulaiman\b"#, "Salim–Sulaiman"),
        (#"\bSajid\s*(?:&|\band\b|-|–|,)\s*Wajid\b"#, "Sajid–Wajid"),
        (#"\bSachin\s*(?:&|\band\b|-|–|,)\s*Jigar\b"#, "Sachin–Jigar"),
        (#"\bJatin\s*(?:&|\band\b|-|–|,)\s*Lalit\b"#, "Jatin–Lalit"),
        (#"\bNadeem\s*(?:&|\band\b|-|–|,)\s*Shravan\b"#, "Nadeem–Shravan"),
        (#"\bLaxmikant\s*(?:&|\band\b|-|–|,)\s*Pyarelal\b"#, "Laxmikant–Pyarelal"),
        (#"\bKalyanji\s*(?:&|\band\b|-|–|,)\s*Anandji\b"#, "Kalyanji–Anandji"),
        (#"\bShankar\s*(?:&|\band\b|-|–|,)\s*Jaikishan\b"#, "Shankar–Jaikishan"),
        (#"\bAnand\s*(?:&|\band\b|-|–|,)\s*Milind\b"#, "Anand–Milind"),
        (#"\bMeet\s+Bros\.?(?:\s+Anjjan)?"#, "Meet Bros"),
    ]

    private static func keepingGroupsTogether(_ credit: String) -> String {
        var text = credit
        for group in groups {
            text = text.replacingOccurrences(
                of: group.pattern,
                with: group.name,
                options: [.regularExpression, .caseInsensitive]
            )
        }
        return text
    }

    /// Case, accents, dots and spaces don't matter: "A.R. Rahman" == "a r rahman".
    static func key(for name: String) -> String {
        let folded = name.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
        let key = String(folded.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(Character.init))
        return sameArtist[key] ?? key
    }

    /// Different spellings of the same artist, merged into one tile.
    private static let sameArtist: [String: String] = [
        "arrehman": "arrahman",
        "allahrakharahman": "arrahman",
        "krishnakumarkunnath": "kk",
        "vishalandshekhar": "vishalshekhar",
        "vishalshekar": "vishalshekhar",
        "vishalandshekar": "vishalshekhar",
        // Credited on their own (e.g. "Vishal Dadlani, Shekhar Ravjiani") — still one duo tile.
        "vishal": "vishalshekhar",
        "shekhar": "vishalshekhar",
        "shekar": "vishalshekhar",
        "vishaldadlani": "vishalshekhar",
        "shekharravjiani": "vishalshekhar",
        "shekarravjiani": "vishalshekhar",
        "shankarehsaanandloy": "shankarehsaanloy",
    ]

    /// The name shown for an artist merged from several spellings; otherwise the most common spelling wins.
    static func displayName(forKey key: String) -> String? {
        preferredNames[key]
    }

    private static let preferredNames: [String: String] = [
        "vishalshekhar": "Vishal–Shekhar",
    ]

    private static func isPlaceholder(_ name: String) -> Bool {
        let normalized = key(for: name)
        return normalized.isEmpty || normalized == "variousartists" || normalized == "unknownartist" || normalized == "various"
    }
}

enum LibraryAlphabet {
    static func section(for title: String) -> String {
        let normalized = title
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .uppercased()
        guard let first = normalized.unicodeScalars.first, (65...90).contains(first.value) else {
            return "#"
        }
        return String(first)
    }
}

enum LibrarySearch {
    static func key(_ fields: [String?]) -> String {
        normalize(fields.compactMap { $0 }.joined(separator: "\n"))
    }

    /// Items matching `query` — by their own name first, then those that match only through one of
    /// their songs (each group keeps its A–Z order).
    static func filterByNameThenSongs<T>(
        _ items: [T],
        query: String,
        nameKey: (T) -> String,
        songsKey: (T) -> String
    ) -> [T] {
        guard !query.isEmpty else { return items }
        var byName: [T] = []
        var bySong: [T] = []
        for item in items {
            if matches(nameKey(item), query: query) {
                byName.append(item)
            } else if matches(songsKey(item), query: query) {
                bySong.append(item)
            }
        }
        return byName + bySong
    }

    static func normalizedQuery(_ text: String) -> String {
        normalize(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    static func matches(_ key: String?, query: String) -> Bool {
        guard !query.isEmpty else { return true }
        guard let key else { return false }
        return key.range(of: query) != nil
    }

    private static func normalize(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }
}

