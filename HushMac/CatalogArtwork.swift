import Foundation

/// Covers for albums whose artwork isn't in the library or the files. The Music app shows these from
/// its own private cache, which Hush can't read; Apple's public iTunes catalog has the same covers.
/// Only the album title and artist are sent. A cover is used only when the catalog's album title and
/// artist both match (so a different album's art never shows), and each is downloaded once and kept
/// on this Mac.
actor CatalogArtwork {
    static let shared = CatalogArtwork()

    private var inFlight: [UInt64: Task<Data?, Never>] = [:]
    private var activeLookups = 0

    private static let network: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        configuration.waitsForConnectivity = false
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }()

    private static let folder: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let folder = base.appendingPathComponent("AlbumArtwork", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }()

    /// The cover's image data, from this Mac if it was downloaded before, else from the catalog.
    func cover(albumID: UInt64, title: String, artist: String, songTitle: String?) async -> Data? {
        let file = Self.folder.appendingPathComponent("\(albumID).jpg")
        if let data = try? Data(contentsOf: file) { return data }
        // Looked up in the last week and not found: don't ask again yet.
        let miss = Self.folder.appendingPathComponent("\(albumID).miss")
        if let date = (try? miss.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
           Date().timeIntervalSince(date) < 7 * 24 * 3600 {
            return nil
        }
        if let existing = inFlight[albumID] { return await existing.value }
        let task = Task<Data?, Never> { await self.download(title: title, artist: artist, songTitle: songTitle, file: file, miss: miss) }
        inFlight[albumID] = task
        let data = await task.value
        inFlight[albumID] = nil
        return data
    }

    private func download(title: String, artist: String, songTitle: String?, file: URL, miss: URL) async -> Data? {
        while activeLookups >= 3 { try? await Task.sleep(nanoseconds: 100_000_000) }
        activeLookups += 1
        defer { activeLookups -= 1 }

        guard let results = await Self.search(title: title, artist: artist, songTitle: songTitle) else { return nil } // offline: retry later
        guard let match = CatalogMatch.best(in: results, title: title, artist: artist),
              let url = URL(string: match.artworkURL.replacingOccurrences(of: "100x100bb", with: "1000x1000bb")),
              let (data, response) = try? await Self.network.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200 else {
            try? Data().write(to: miss, options: .atomic)
            return nil
        }
        try? data.write(to: file, options: .atomic)
        return data
    }

    /// Nil only if the request itself failed.
    static func search(title: String, artist: String, songTitle: String?) async -> [CatalogMatch.Album]? {
        var results: [CatalogMatch.Album] = []
        // Album title with the artist first; then the core title alone (soundtracks are often
        // credited differently in the catalog); then one of its songs, which names its album.
        var searches = [("\(CatalogMatch.coreTitle(title)) \(artist)", "album"), (CatalogMatch.coreTitle(title), "album")]
        if let songTitle { searches.append(("\(songTitle) \(artist)", "song")) }
        for (term, entity) in searches {
            var components = URLComponents(string: "https://itunes.apple.com/search")
            components?.queryItems = [
                URLQueryItem(name: "term", value: term),
                URLQueryItem(name: "entity", value: entity),
                URLQueryItem(name: "limit", value: "15"),
            ]
            guard let url = components?.url,
                  let (data, response) = try? await network.data(from: url),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let decoded = try? JSONDecoder().decode(CatalogMatch.Response.self, from: data) else { return nil }
            results += decoded.results
            if CatalogMatch.best(in: results, title: title, artist: artist) != nil { break }
        }
        return results
    }
}

/// Deciding whether a catalog album is the album in your library.
enum CatalogMatch {
    struct Response: Decodable {
        let results: [Album]
    }

    /// Every field optional: one odd result mustn't spoil the whole answer.
    struct Album: Decodable {
        let collectionName: String?
        let artistName: String?
        let artworkUrl100: String?

        var name: String { collectionName ?? "" }
        var artist: String { artistName ?? "" }
        var artworkURL: String { artworkUrl100 ?? "" }
    }

    /// Other editions of an album that have different covers.
    private static let otherEditionWords = ["remix", "live", "karaoke", "instrumental", "acoustic", "cover", "tribute", "lofi", "slowed", "reverb"]

    static func best(in results: [Album], title: String, artist: String) -> Album? {
        let wanted = key(coreTitle(title))
        let wantedArtists = artistKeys(artist)
        var bestAlbum: Album?
        var bestScore = 0.0
        let wantedFolded = key(title)
        for album in results where album.artworkUrl100 != nil && album.collectionName != nil {
            let candidateFolded = key(album.name)
            if otherEditionWords.contains(where: { candidateFolded.contains($0) && !wantedFolded.contains($0) }) { continue }
            let candidate = key(coreTitle(album.name))
            let score = similarity(wanted, candidate)
            guard score >= 0.85 else { continue }
            // Artists must overlap ("Various Artists" soundtracks: the title alone, but it must be exact).
            let artistsMatch = !wantedArtists.isDisjoint(with: artistKeys(album.artist))
            let isVarious = wantedArtists.isEmpty
            guard artistsMatch || (isVarious && score == 1) else { continue }
            // Prefer the exact edition ("Deluxe" vs not) when both are there.
            let exact = wantedFolded == candidateFolded ? 0.01 : 0
            if score + exact > bestScore {
                bestScore = score + exact
                bestAlbum = album
            }
        }
        return bestAlbum
    }

    /// "Starboy (Deluxe) - Single" → "Starboy".
    static func coreTitle(_ title: String) -> String {
        var text = title
        for suffix in [" - Single", " - EP"] where text.hasSuffix(suffix) {
            text = String(text.dropLast(suffix.count))
        }
        text = text.replacingOccurrences(of: #"\s*[\(\[][^\)\]]*[\)\]]"#, with: "", options: .regularExpression)
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? title : trimmed
    }

    static func key(_ text: String) -> String {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
        return String(folded.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(Character.init))
    }

    /// Each credited name, folded ("Arijit Singh & Pritam" → ["arijitsingh", "pritam"]).
    static func artistKeys(_ credit: String) -> Set<String> {
        let names = credit
            .replacingOccurrences(of: " feat. ", with: ",")
            .replacingOccurrences(of: " and ", with: ",")
            .components(separatedBy: CharacterSet(charactersIn: ",&;/"))
        let keys = names.map(key).filter { !$0.isEmpty && $0 != "variousartists" && $0 != "various" }
        return Set(keys)
    }

    /// 1 − (edit distance ÷ longer length).
    static func similarity(_ a: String, _ b: String) -> Double {
        if a == b { return 1 }
        let a = Array(a), b = Array(b)
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        var previous = Array(0...b.count)
        for i in 1...a.count {
            var current = [i] + Array(repeating: 0, count: b.count)
            for j in 1...b.count {
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            previous = current
        }
        return 1 - Double(previous[b.count]) / Double(max(a.count, b.count))
    }
}
