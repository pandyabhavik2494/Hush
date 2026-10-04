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
    /// Downloaded to this Mac (the TV app can play it straight away); otherwise it streams.
    let isDownloaded: Bool
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
    /// Downloaded to this Mac (the TV app can play it straight away); otherwise it streams.
    let isDownloaded: Bool
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
            isDownloaded: item.location != nil,
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

    static func showName(series: String?, album: String?) -> String {
        AppleTVPurchases.showName(LibraryLoader.nonEmpty(series) ?? LibraryLoader.nonEmpty(album) ?? "TV Show")
    }

    /// Season and episode from "Season 1, Episode 19: The One Where…", else from the season name and
    /// the episode order.
    private static func parseEpisode(_ item: ITLibMediaItem, id: UInt64, album: String?) -> AppleTVEpisode {
        let rawTitle: String = item.title
        let title = LibraryLoader.nonEmpty(rawTitle) ?? "Episode"
        let duration = TimeInterval(item.totalTime) / 1000
        if let parsed = AppleTVPurchases.parseEpisodeTitle(title) {
            return AppleTVEpisode(id: id, title: parsed.title, season: parsed.season, number: parsed.number,
                                  duration: duration, isDownloaded: item.location != nil)
        }
        let season = AppleTVPurchases.seasonNumber(in: album) ?? Int(item.videoInfo?.season ?? 0)
        let order = Int(item.videoInfo?.episodeOrder ?? 0)
        let number = order > 0 ? order : Int(item.trackNumber)
        return AppleTVEpisode(id: id, title: title, season: max(season, 1), number: number,
                              duration: duration, isDownloaded: item.location != nil)
    }
}

// MARK: - Handing off to the TV app

/// Opens a purchase in the TV app (the TV app and the library share persistent IDs, so Hush asks
/// the TV app, through its scripting interface, for that exact item). The TV app has to be in front
/// before its player will start, so it's brought forward first. A downloaded purchase plays straight
/// away, full screen, and Hush comes back to the front when you're done (see AppleTVWatcher). A
/// purchase that's only in the cloud can't be started by another app (the TV app streams store
/// purchases only from its own Play button), so the TV app shows that title, ready for you to press
/// Play. Hush's own playback pauses first and isn't resumed. The first time, macOS asks whether Hush
/// may control TV; if that isn't allowed, or anything fails, the TV app simply opens.
enum AppleTVHandOff {
    @MainActor
    static func open(_ id: UInt64, title: String, isDownloaded: Bool, play: Bool = true) {
        Player.shared.setPlaying(false)
        VideoPlayback.shared.pauseForMusic()
        let playsHere = play && isDownloaded
        Player.shared.showToast(playsHere ? "Opening \(title) in the TV app" : "\(title) is ready in the TV app: press Play to stream it")
        let persistentID = String(format: "%016llX", id)
        let action = playsHere
            ? "play (item 1 of found)\n        delay 1\n        try\n            set full screen of window 1 to true\n        end try"
            : "reveal (item 1 of found)"
        let source = """
        tell application id "com.apple.TV"
            activate
            delay 1
            set found to (every track of library playlist 1 whose persistent ID is "\(persistentID)")
            if (count of found) is 0 then error "not found"
            \(action)
        end tell
        """
        AppleTVWatcher.shared.stop()
        DispatchQueue.global(qos: .userInitiated).async {
            var error: NSDictionary?
            NSAppleScript(source: source)?.executeAndReturnError(&error)
            DispatchQueue.main.async {
                if let error {
                    hushLog.info("TV hand-off fell back to opening the TV app: \(error.description, privacy: .public)")
                    if (error[NSAppleScript.errorNumber] as? Int) == -1743 {
                        // macOS hasn't let Hush control TV (or the permission was turned off).
                        Player.shared.showToast("Allow Hush in System Settings › Privacy & Security › Automation")
                    }
                    openTVApp()
                } else if playsHere {
                    AppleTVWatcher.shared.start()
                }
            }
        }
    }

    @MainActor
    static func openTVApp() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.TV") else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
}

/// Watches the TV app after a hand-off and brings Hush back when you're done watching: playback
/// stops, full screen ends, or the TV app quits. Gives up if you switch to Hush yourself (or after
/// six hours). Reads the TV app's player state every couple of seconds while watching.
@MainActor
final class AppleTVWatcher {
    static let shared = AppleTVWatcher()

    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var started = Date.distantPast
    private var sawPlaying = false
    private var sawFullScreen = false
    private var polling = false
    private let queue = DispatchQueue(label: "Hush TV watcher")

    func start() {
        stop()
        started = Date()
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard app?.bundleIdentifier == "com.apple.TV" else { return }
            MainActor.assumeIsolated { AppleTVWatcher.shared.finish(reason: "TV app quit") }
        })
        observers.append(center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard app?.processIdentifier == ProcessInfo.processInfo.processIdentifier else { return }
            // You came back to Hush yourself: nothing more to do.
            MainActor.assumeIsolated { AppleTVWatcher.shared.stop() }
        })
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            MainActor.assumeIsolated { AppleTVWatcher.shared.poll() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observers = []
        sawPlaying = false
        sawFullScreen = false
    }

    private func poll() {
        guard !polling else { return }
        if Date().timeIntervalSince(started) > 6 * 3600 { stop(); return }
        // Never launch the TV app just to ask about it.
        guard NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.TV").first != nil else {
            finish(reason: "TV app not running")
            return
        }
        polling = true
        queue.async {
            var error: NSDictionary?
            let answer = NSAppleScript(source: """
            tell application id "com.apple.TV"
                set ps to player state
                if (count of windows) is 0 then return (ps as text) & "|closed"
                set fs to full screen of window 1
                return (ps as text) & "|" & (fs as text)
            end tell
            """)?.executeAndReturnError(&error).stringValue
            DispatchQueue.main.async {
                AppleTVWatcher.shared.polling = false
                AppleTVWatcher.shared.handle(answer)
            }
        }
    }

    private func handle(_ answer: String?) {
        guard timer != nil, let parts = answer?.split(separator: "|"), parts.count == 2 else { return }
        let state = parts[0].trimmingCharacters(in: .whitespaces)
        let window = parts[1].trimmingCharacters(in: .whitespaces)
        let fullScreen = window == "true"
        if state == "playing" { sawPlaying = true }
        if fullScreen { sawFullScreen = true }
        // Give the player a few seconds to start before reading anything into "stopped".
        guard Date().timeIntervalSince(started) > 6 else { return }
        if window == "closed" {
            finish(reason: "TV window closed")
        } else if sawPlaying, state == "stopped" {
            finish(reason: "playback stopped")
        } else if sawFullScreen, !fullScreen {
            finish(reason: "full screen ended")
        }
    }

    /// Brings Hush forward again, on the page you left.
    private func finish(reason: String) {
        guard timer != nil || !observers.isEmpty else { return }
        hushLog.info("TV hand-off finished (\(reason, privacy: .public)); back to Hush")
        stop()
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first { $0.identifier?.rawValue.contains("main") == true }?.makeKeyAndOrderFront(nil)
    }
}
