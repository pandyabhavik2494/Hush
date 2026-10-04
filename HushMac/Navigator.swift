import Observation
import SwiftUI

/// The sidebar's sections. Cmd-1 … Cmd-6 in this order.
enum LibrarySection: String, CaseIterable, Identifiable, Hashable {
    case albums
    case songs
    case playlists
    case artists
    case musicVideos
    case movies

    var id: String { rawValue }

    var title: String {
        switch self {
        case .albums: return "Albums"
        case .songs: return "Songs"
        case .playlists: return "Playlists"
        case .artists: return "Artists"
        case .musicVideos: return "Music Videos"
        case .movies: return "Movies"
        }
    }

    var symbol: String {
        switch self {
        case .albums: return "square.stack"
        case .songs: return "music.note"
        case .playlists: return "music.note.list"
        case .artists: return "music.mic"
        case .musicVideos: return "play.rectangle"
        case .movies: return "film"
        }
    }

    var searchPrompt: String {
        switch self {
        case .albums: return "Find an album, artist or song"
        case .songs: return "Find a song, artist or album"
        case .playlists: return "Find a playlist or song"
        case .artists: return "Find an artist or song"
        case .musicVideos: return "Find a video"
        case .movies: return "Find a movie or genre"
        }
    }

    /// Sections whose artwork already carries the name: titles are hidden by default and the
    /// covers sit edge to edge as a mosaic. The toolbar toggle shows them.
    var hasTitleToggle: Bool {
        self == .albums || self == .playlists || self == .movies
    }

    var sortOptions: [LibrarySort] {
        switch self {
        case .artists: return [.alphabetical, .mostPlayed, .favorites]
        default: return [.alphabetical, .mostPlayed]
        }
    }

    var shortcut: KeyEquivalent {
        KeyEquivalent(Character(String((LibrarySection.allCases.firstIndex(of: self) ?? 0) + 1)))
    }
}

enum LibrarySort: String, CaseIterable, Identifiable {
    case alphabetical
    case mostPlayed
    case favorites

    var id: String { rawValue }

    var label: String {
        switch self {
        case .alphabetical: return "A–Z"
        case .mostPlayed: return "MOST PLAYED"
        case .favorites: return "FAVORITES"
        }
    }

    var menuTitle: String {
        switch self {
        case .alphabetical: return "A to Z"
        case .mostPlayed: return "Most Played"
        case .favorites: return "Favourites First"
        }
    }
}

/// A page opened on top of a section.
enum Route: Hashable {
    case album(UInt64)
    case artist(String)
    case playlist(UInt64)

    init(_ source: PlaybackSource) {
        switch source {
        case .album(let id): self = .album(id)
        case .artist(let id): self = .artist(id)
        case .playlist(let id): self = .playlist(id)
        }
    }
}

/// Where you are: a section, and maybe a page on top of it.
struct Location: Hashable {
    var section: LibrarySection
    var route: Route?
}

/// Where you are in the app, shared by the window, the menus and the mini player so any of them
/// can take you somewhere. Back and Forward work like a browser's.
@MainActor
@Observable
final class Navigator {
    static let shared = Navigator()

    private(set) var history: [Location] = [Location(section: .albums)]
    private(set) var position = 0
    var searchText: [LibrarySection: String] = [:]
    var showsUpNext = false
    var showsNowPlaying = false
    /// Bumped to ask the toolbar's search field to take focus (Cmd-F).
    private(set) var searchFocusRequest = 0
    /// Bumped to ask the songs list or a page to scroll to the playing song (Cmd-L).
    private(set) var revealRequest = 0
    private(set) var revealTrackID: UInt64?

    var sorts: [LibrarySection: LibrarySort] {
        didSet { saveSorts() }
    }

    private init() {
        var stored: [LibrarySection: LibrarySort] = [:]
        for section in LibrarySection.allCases {
            if let raw = UserDefaults.standard.string(forKey: "hush.mac.sort.\(section.rawValue)"),
               let sort = LibrarySort(rawValue: raw) {
                stored[section] = sort
            }
        }
        sorts = stored
        if let raw = UserDefaults.standard.string(forKey: "hush.mac.section"), let section = LibrarySection(rawValue: raw) {
            history = [Location(section: section)]
        }
    }

    var location: Location { history[position] }
    var section: LibrarySection { location.section }
    var route: Route? { location.route }
    var canGoBack: Bool { position > 0 }
    var canGoForward: Bool { position + 1 < history.count }

    func sort(for section: LibrarySection) -> LibrarySort {
        if let sort = sorts[section], section.sortOptions.contains(sort) { return sort }
        return section == .artists ? .favorites : .alphabetical
    }

    func search(for section: LibrarySection) -> String {
        searchText[section] ?? ""
    }

    func binding(forSearchIn section: LibrarySection) -> Binding<String> {
        Binding(get: { self.searchText[section] ?? "" }, set: { self.searchText[section] = $0 })
    }

    // MARK: Moving around

    func select(_ section: LibrarySection) {
        showsNowPlaying = false
        VideoPlayback.shared.pauseForMusic()
        if VideoPlayback.shared.isShowing { VideoPlayback.shared.close() }
        guard location != Location(section: section) else { return }
        push(Location(section: section))
        UserDefaults.standard.set(section.rawValue, forKey: "hush.mac.section")
    }

    /// Opens a page on top of the current section (a playlist page from the sidebar opens in
    /// Playlists).
    func show(_ route: Route, in section: LibrarySection? = nil) {
        showsNowPlaying = false
        let target = Location(section: section ?? defaultSection(for: route), route: route)
        guard target != location else { return }
        push(target)
    }

    func show(_ source: PlaybackSource) {
        show(Route(source))
    }

    func back() {
        guard canGoBack else { return }
        showsNowPlaying = false
        position -= 1
    }

    func forward() {
        guard canGoForward else { return }
        showsNowPlaying = false
        position += 1
    }

    func focusSearch() {
        showsNowPlaying = false
        searchFocusRequest &+= 1
    }

    /// Go to the playing song: its album page, scrolled to the song.
    func revealCurrentSong(player: Player, library: LibraryModel) {
        guard let track = player.current, let album = library.album(for: track) else { return }
        show(.album(album.id), in: section)
        revealTrackID = track.id
        revealRequest &+= 1
    }

    private func push(_ next: Location) {
        history.removeSubrange((position + 1)...)
        history.append(next)
        if history.count > 100 { history.removeFirst(history.count - 100) }
        position = history.count - 1
    }

    /// Opening a page keeps you in the section you're in, unless that would be odd (an album page
    /// "in" Movies): then it opens in the section it belongs to.
    private func defaultSection(for route: Route) -> LibrarySection {
        switch (route, section) {
        case (_, .albums), (_, .songs), (_, .artists), (_, .playlists): return section
        case (.album, _): return .albums
        case (.artist, _): return .artists
        case (.playlist, _): return .playlists
        }
    }

    private func saveSorts() {
        for (section, sort) in sorts {
            UserDefaults.standard.set(sort.rawValue, forKey: "hush.mac.sort.\(section.rawValue)")
        }
    }
}
