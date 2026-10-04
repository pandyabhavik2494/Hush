import AppKit
import Foundation
import iTunesLibrary

// MARK: - Models

/// A movie bought or rented on Apple TV. It plays in the TV app, never in Hush.
struct AppleTVMovie: Identifiable, Hashable, Sendable {
    let id: UInt64
    let title: String
    let year: Int?
    let genre: String?
    let genres: [String]
    let duration: TimeInterval
    let searchKey: String
    let sectionLetter: String

    /// "2014 · Action".
    var yearAndGenre: String {
        [year.map(String.init), genre].compactMap { $0 }.joined(separator: " · ")
    }
}

/// One episode of an Apple TV show.
struct AppleTVEpisode: Identifiable, Hashable, Sendable {
    let id: UInt64
    /// The episode's own title, without the "Season 1, Episode 19:" prefix.
    let title: String
    let season: Int
    let number: Int
    let duration: TimeInterval
}

/// A series bought on Apple TV, with every episode in the library.
struct AppleTVShow: Identifiable, Hashable, Sendable {
    /// The cleaned show name, folded (stable across launches).
    let id: String
    let name: String
    let genre: String?
    /// Season by season, in order.
    let episodes: [AppleTVEpisode]
    let searchKey: String
    let episodeSearchKey: String
    let sectionLetter: String

    var seasons: [Int] { Array(Set(episodes.map(\.season))).sorted() }
    /// The first episode's still stands in for show art (the library has none).
    var artworkID: UInt64? { episodes.first?.id }

    var seasonsText: String {
        let count = seasons.count
        return count == 1 ? (seasons.first.map { "Season \($0)" } ?? "1 season") : "\(count) seasons"
    }

    var episodesText: String { episodes.count == 1 ? "1 episode" : "\(episodes.count) episodes" }
}

// MARK: - Reading purchases from the library

enum AppleTVLibrary {
    /// Purchased movies from the library's movie items.
    static func movie(from item: ITLibMediaItem, id: UInt64) -> AppleTVMovie {
        let rawTitle: String = item.title
        let title = LibraryLoader.nonEmpty(rawTitle) ?? "Untitled Movie"
        let genre = LibraryLoader.nonEmpty(item.genre)
        let year = Int(item.year)
        return AppleTVMovie(
            id: id,
            title: title,
            year: year > 0 ? year : nil,
            genre: genre,
            genres: LibraryLoader.splitGenres(genre),
            duration: TimeInterval(item.totalTime) / 1000,
            searchKey: LibrarySearch.key([title, genre]),
            sectionLetter: LibraryAlphabet.section(for: title)
        )
    }

    /// Groups TV episodes into shows.
    static func shows(from items: [(item: ITLibMediaItem, id: UInt64)]) -> [AppleTVShow] {
        var grouped: [String: (name: String, genre: String?, episodes: [AppleTVEpisode])] = [:]
        for (item, id) in items {
            let album: ITLibAlbum = item.album
            let name = showName(series: item.videoInfo?.series, album: album.title)
            let key = LibrarySearch.normalizedQuery(name)
            let episode = parseEpisode(item, id: id, album: album.title)
            var entry = grouped[key] ?? (name, LibraryLoader.nonEmpty(item.genre), [])
            entry.episodes.append(episode)
            grouped[key] = entry
        }
        let shows: [AppleTVShow] = grouped.map { key, entry in
            let episodes = entry.episodes.sorted { ($0.season, $0.number, $0.title) < ($1.season, $1.number, $1.title) }
            return AppleTVShow(
                id: key,
                name: entry.name,
                genre: entry.genre,
                episodes: episodes,
                searchKey: LibrarySearch.key([entry.name]),
                episodeSearchKey: LibrarySearch.key(episodes.map(\.title)),
                sectionLetter: LibraryAlphabet.section(for: entry.name)
            )
        }
        return shows.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// "Friends: The Complete Series" → "Friends"; "Young Sheldon, Season 7" → "Young Sheldon".
    static func showName(series: String?, album: String?) -> String {
        let raw = LibraryLoader.nonEmpty(series) ?? LibraryLoader.nonEmpty(album) ?? "TV Show"
        let cleaned = raw
            .replacingOccurrences(of: #"[:,]?\s*(The\s+)?Complete\s+Series$"#, with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #",?\s*Season\s+\d+$"#, with: "", options: [.regularExpression, .caseInsensitive])
            .trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? raw : cleaned
    }

    /// Season and episode from "Season 1, Episode 19: The One Where…", else from the season name and
    /// the episode order.
    private static func parseEpisode(_ item: ITLibMediaItem, id: UInt64, album: String?) -> AppleTVEpisode {
        let rawTitle: String = item.title
        let title = LibraryLoader.nonEmpty(rawTitle) ?? "Episode"
        let duration = TimeInterval(item.totalTime) / 1000
        if let match = title.firstMatch(of: #/^Season\s+(\d+),\s*Episode\s+(\d+)\s*[:\-–]\s*(.+)$/#) {
            return AppleTVEpisode(id: id, title: String(match.3), season: Int(match.1) ?? 1, number: Int(match.2) ?? 0, duration: duration)
        }
        var season = Int(item.videoInfo?.season ?? 0)
        if let album, let match = album.firstMatch(of: #/Season\s+(\d+)/#) { season = Int(match.1) ?? season }
        let order = Int(item.videoInfo?.episodeOrder ?? 0)
        let number = order > 0 ? order : Int(item.trackNumber)
        return AppleTVEpisode(id: id, title: title, season: max(season, 1), number: number, duration: duration)
    }
}

// MARK: - Handing off to the TV app

/// Opens a purchase in the TV app: the exact movie or episode (the TV app and the library share
/// persistent IDs, so Hush asks the TV app, through its scripting interface, to play that item).
/// The first time, macOS asks whether Hush may control TV. If that isn't allowed, or anything
/// fails, the TV app simply opens.
enum AppleTVHandOff {
    @MainActor
    static func open(_ id: UInt64, title: String, play: Bool = true) {
        Player.shared.setPlaying(false)
        Player.shared.showToast("Opening \(title) in the TV app")
        let persistentID = String(format: "%016llX", id)
        let verb = play ? "play" : "reveal"
        let source = """
        tell application id "com.apple.TV"
            set found to (every track of library playlist 1 whose persistent ID is "\(persistentID)")
            if (count of found) is 0 then error "not found"
            \(verb) (item 1 of found)
            activate
        end tell
        """
        DispatchQueue.global(qos: .userInitiated).async {
            var error: NSDictionary?
            NSAppleScript(source: source)?.executeAndReturnError(&error)
            if let error {
                hushLog.info("TV hand-off fell back to opening the TV app: \(error.description, privacy: .public)")
                DispatchQueue.main.async { openTVApp() }
            }
        }
    }

    @MainActor
    static func openTVApp() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.TV") else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
}
