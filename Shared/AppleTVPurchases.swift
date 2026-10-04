import Foundation

/// Telling Apple TV purchases (movies and shows bought or rented from Apple) apart from your own
/// video files. Purchases belong to the TV app: they're copy-protected or live only in the cloud, so
/// Hush can't play them, and the Movies tab shows only your own files.
enum AppleTVPurchases {
    /// - Parameters:
    ///   - kind: The library's file kind ("Purchased MPEG-4 video file", "Protected MPEG-4 video
    ///     file"…) where the platform offers it (the Mac's iTunes library; nil on the iPhone).
    ///   - isProtected: Copy-protected (FairPlay).
    ///   - hasLocalFile: There's a file on this device Hush could open.
    ///   - isCloud: The item lives in the cloud (not downloaded).
    static func isPurchase(kind: String?, isProtected: Bool, hasLocalFile: Bool, isCloud: Bool) -> Bool {
        if isProtected || isCloud || !hasLocalFile { return true }
        guard let kind = kind?.lowercased() else { return false }
        return kind.contains("purchased") || kind.contains("protected")
    }

    /// "Friends: The Complete Series" → "Friends"; "Young Sheldon, Season 7" → "Young Sheldon".
    static func showName(_ raw: String) -> String {
        let cleaned = raw
            .replacingOccurrences(of: #"[:,]?\s*(The\s+)?Complete\s+Series$"#, with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #",?\s*Season\s+\d+$"#, with: "", options: [.regularExpression, .caseInsensitive])
            .trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? raw : cleaned
    }

    /// "Season 1, Episode 19: The One Where…" → (1, 19, "The One Where…"); nil for other titles.
    static func parseEpisodeTitle(_ title: String) -> (season: Int, number: Int, title: String)? {
        guard let match = title.firstMatch(of: #/^Season\s+(\d+),\s*Episode\s+(\d+)\s*[:\-–]\s*(.+)$/#) else { return nil }
        return (Int(match.1) ?? 1, Int(match.2) ?? 0, String(match.3))
    }

    /// The season number in a season name like "Young Sheldon, Season 7".
    static func seasonNumber(in name: String?) -> Int? {
        guard let name, let match = name.firstMatch(of: #/Season\s+(\d+)/#) else { return nil }
        return Int(match.1)
    }
}
