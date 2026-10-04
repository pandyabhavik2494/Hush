import MediaPlayer
import MusicKit
import SwiftUI
import UIKit

/// Tab order (left to right, and the swipe order): Albums, Songs, Playlists, Artists, Videos, Movies.
private enum LibraryTab: String, CaseIterable {
    case albums = "Albums"
    case songs = "Songs"
    case playlists = "Playlists"
    case artists = "Artists"
    case videos = "Videos"
    case movies = "Movies"
}

private enum LibrarySort: String, CaseIterable {
    case favorites = "Favorites"
    case mostSongs = "Most songs"
    case alphabetical = "Alphabetical"
    case mostPlayed = "Most played"

    /// "Most songs" only applies to artists.
    static func options(for tab: LibraryTab) -> [LibrarySort] {
        tab == .artists ? [.favorites, .mostSongs, .alphabetical, .mostPlayed] : [.alphabetical, .mostPlayed]
    }

    var symbol: String {
        switch self {
        case .favorites: return "heart.fill"
        case .mostSongs: return "music.note.list"
        case .alphabetical: return "arrow.up"
        case .mostPlayed: return "chart.bar.fill"
        }
    }

    var shortLabel: String {
        switch self {
        case .favorites: return "FAVORITES"
        case .mostSongs: return "SONGS"
        case .alphabetical: return "A–Z"
        case .mostPlayed: return "PLAYED"
        }
    }
}

/// "Scroll back to the top" for one tab — sent by tapping the tab you're already on.
private struct ScrollToTopRequest: Equatable {
    var tab: LibraryTab?
    var count = 0

    func signal(for tab: LibraryTab) -> Int? {
        self.tab == tab ? count : nil
    }
}

/// Tiles sink a touch under your finger and spring back, so a tap feels answered right away.
private struct TilePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.965 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.spring(response: 0.26, dampingFraction: 0.72), value: configuration.isPressed)
    }
}

private enum HushRoute: Hashable {
    case album(UInt64)
    case playlist(UInt64)
    case artist(String)

    init(_ source: PlaybackSource) {
        switch source {
        case .album(let id): self = .album(id)
        case .playlist(let id): self = .playlist(id)
        case .artist(let id): self = .artist(id)
        }
    }
}

enum PlayerArtworkTransitionID {
    static func librarySong(_ persistentID: UInt64) -> String {
        "library-song-artwork-\(persistentID)"
    }

    static func albumTrack(_ persistentID: UInt64) -> String {
        "album-track-artwork-\(persistentID)"
    }

    static func albumPlayButton(_ persistentID: UInt64) -> String {
        "album-detail-play-artwork-\(persistentID)"
    }

    static func playlistTrack(_ persistentID: UInt64) -> String {
        "playlist-track-artwork-\(persistentID)"
    }

    static let miniPlayer = "mini-player-artwork"

    static func albumTile(_ id: UInt64) -> String { "album-tile-\(id)" }

    // Covers that open a page: the page zooms out of the cover, and back into it on Back.
    static func albumGridTile(_ id: UInt64) -> String { "page-album-grid-\(id)" }
    static func playlistGridTile(_ id: UInt64) -> String { "page-playlist-grid-\(id)" }
    static func artistGridTile(_ id: String) -> String { "page-artist-grid-\(id)" }
    static func artistPageAlbum(artistID: String, albumID: UInt64) -> String {
        "page-artist-\(artistID)-album-\(albumID)"
    }
    static func playlistTile(_ id: UInt64) -> String { "playlist-tile-\(id)" }
    static func artistHeader(_ id: String) -> String { "artist-header-\(id)" }
}

extension View {
    /// Marks a view as the place a zoom transition grows from / shrinks back into (iOS 18+).
    @ViewBuilder
    func zoomSource(_ id: String, in namespace: Namespace.ID) -> some View {
        if #available(iOS 18.0, *) {
            matchedTransitionSource(id: id, in: namespace)
        } else {
            self
        }
    }

    /// Marks a cover as the place a page zooms out of and back into (iOS 18+), with the cover's
    /// own corner radius so the zoom starts from exactly what you tapped (half the width = circle).
    @ViewBuilder
    func pageZoomSource(_ id: String, in namespace: Namespace.ID, cornerRadius: CGFloat) -> some View {
        if #available(iOS 18.0, *) {
            matchedTransitionSource(id: id, in: namespace) { source in
                source.clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            }
        } else {
            self
        }
    }

    /// Zooms this screen in from (and back out to) the matching `zoomSource` (iOS 18+).
    /// Zoom transitions also support the interactive swipe to dismiss.
    @ViewBuilder
    func zoomTransition(from id: String?, in namespace: Namespace.ID) -> some View {
        if let id {
            if #available(iOS 18.0, *) {
                navigationTransition(.zoom(sourceID: id, in: namespace))
            } else {
                self
            }
        } else {
            self
        }
    }
}

enum HushStyle {
    static let paper = Color(red: 0.040, green: 0.039, blue: 0.037)
    static let surface = Color(red: 0.085, green: 0.083, blue: 0.078)
    static let ink = Color(red: 0.945, green: 0.936, blue: 0.906)
    static let muted = Color(red: 0.610, green: 0.604, blue: 0.584)
    static let gold = Color(red: 0.790, green: 0.660, blue: 0.420)
    static let line = Color(red: 0.180, green: 0.173, blue: 0.155)

    static func brandFont(size: CGFloat) -> Font {
        .custom("Baskerville-SemiBoldItalic", size: size, relativeTo: .largeTitle)
    }

    /// "42 min" / "1 hr 5 min" for a total length in seconds.
    static func durationText(_ seconds: TimeInterval) -> String? {
        let minutes = Int((seconds / 60).rounded())
        guard minutes > 0 else { return nil }
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "\(hours) hr" : "\(hours) hr \(rest) min"
    }
}

/// Hush's own backdrop for the Liquid Glass header: soft pools of gold, bronze and deep wine light
/// at the top of the library, melting into black. Liquid Glass needs something to bend — over plain
/// black it just looks grey — and this gives it that without ever following the playing album.
/// Fixed and static (glass must never animate), purely decorative.
struct HushAmbientLight: View {
    private static let bronze = Color(red: 0.56, green: 0.34, blue: 0.14)
    private static let wine = Color(red: 0.36, green: 0.12, blue: 0.15)

    var body: some View {
        GeometryReader { geometry in
            let width = max(geometry.size.width, 1)
            ZStack {
                // Gold, top left.
                RadialGradient(
                    colors: [HushStyle.gold.opacity(0.34), HushStyle.gold.opacity(0.10), .clear],
                    center: UnitPoint(x: 0.12, y: -0.02),
                    startRadius: 0,
                    endRadius: width * 0.85
                )
                // Bronze, top right.
                RadialGradient(
                    colors: [Self.bronze.opacity(0.38), Self.bronze.opacity(0.10), .clear],
                    center: UnitPoint(x: 0.92, y: 0.06),
                    startRadius: 0,
                    endRadius: width * 0.8
                )
                // A little deep wine lower down, for depth.
                RadialGradient(
                    colors: [Self.wine.opacity(0.30), .clear],
                    center: UnitPoint(x: 0.5, y: 0.42),
                    startRadius: 0,
                    endRadius: width * 0.7
                )
            }
            .frame(width: geometry.size.width, height: 520)
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black.opacity(0.6), location: 0.55),
                        .init(color: .clear, location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Room for the mini player

/// Where the mini player's top edge is on screen (global coordinates), or infinity when it's hidden.
struct MiniPlayerTopKey: EnvironmentKey {
    static let defaultValue: CGFloat = .infinity
}

extension EnvironmentValues {
    var miniPlayerTop: CGFloat {
        get { self[MiniPlayerTopKey.self] }
        set { self[MiniPlayerTopKey.self] = newValue }
    }
}

// MARK: - Room for the floating library header

/// Where the floating library header's bottom edge is on screen (global coordinates); 0 until measured.
struct LibraryHeaderBottomKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    var libraryHeaderBottom: CGFloat {
        get { self[LibraryHeaderBottomKey.self] }
        set { self[LibraryHeaderBottomKey.self] = newValue }
    }
}

/// Makes a library page start below the floating header while still scrolling *under* it, the way
/// the App Store's lists pass under its search bar.
///
/// The swipeable tabs (a paging TabView) clip their pages to their own frame, so the pages are
/// stretched up to the top of the screen and each one gets an invisible bar exactly as tall as the
/// header. To the system that is an ordinary top bar: lists rest below it, slide underneath it,
/// pull-to-refresh appears below it, and iOS 26 adds its soft edge effect at the very top.
/// The height is measured, never guessed: (header's bottom) − (where this bar starts).
private struct UnderLibraryHeader: ViewModifier {
    @Environment(\.libraryHeaderBottom) private var headerBottom
    @State private var barTop: CGFloat = 0

    func body(content: Content) -> some View {
        let spacer = Color.clear
            .frame(height: max(headerBottom - barTop, 0))
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { top in
                if abs(top - barTop) > 0.5 { barTop = top }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        if #available(iOS 26.0, *) {
            content.safeAreaBar(edge: .top, spacing: 0) { spacer }
        } else {
            content.safeAreaInset(edge: .top, spacing: 0) { spacer }
        }
    }
}

/// A light, real blur for whatever slides under the floating header, so the title, search and
/// tabs on top stay easy to read while every cover stays recognisable.
///
/// Each cover or row blurs *itself* by how much of it is hidden under the header: untouched while
/// it is below the tab pills, softening as it slides under them, and at full (still light)
/// strength once it is completely underneath. A system material can't do this — even the thinnest
/// one is a heavy frosted blur with no adjustable strength — and nothing is drawn over the list,
/// so there is no edge or line anywhere. Runs on the render thread from the item's position;
/// the list never redraws for it.
private struct UnderHeaderBlur: ViewModifier {
    @Environment(\.libraryHeaderBottom) private var headerBottom

    /// Blur radius (points) of an item that is fully under the header. System materials are ~30.
    static let maxRadius: CGFloat = 4
    /// How much a fully hidden item is dimmed (0 = not at all).
    static let maxDim: Double = 0.12

    func body(content: Content) -> some View {
        // Plain copies for the effect closure: it runs on the render thread, so it may only use
        // values captured here, not properties of this (main-thread) view.
        let bottom = headerBottom
        let maxRadius = Self.maxRadius
        let maxDim = Self.maxDim
        content.visualEffect { effect, proxy in
            let frame = proxy.frame(in: .global)
            // Share of the item that has passed above the header's bottom edge (0…1).
            let hidden = bottom > 0 && frame.height > 0 ? (bottom - frame.minY) / frame.height : 0
            let depth = min(max(hidden, 0), 1)
            // Squared: it starts as soon as the item goes under the tab pills, but stays faint
            // while part of the item still shows below them.
            let strength = depth * depth
            return effect
                .blur(radius: strength * maxRadius)
                .opacity(1 - Double(strength) * maxDim)
        }
    }
}

private extension View {
    /// See `UnderHeaderBlur`.
    func underHeaderBlur() -> some View {
        modifier(UnderHeaderBlur())
    }

    /// See `UnderLibraryHeader`.
    func underLibraryHeader() -> some View {
        modifier(UnderLibraryHeader())
    }

    /// The glass behind each control of the library header. The header has no panel of its own:
    /// like the App Store's search bar, each control floats on its own Liquid Glass and the library
    /// stays visible through and around it. A light smoke tint keeps gold and white readable over
    /// bright covers. Static background layer (glass never animates); frosted material before iOS 26.
    func hushHeaderGlass<S: Shape>(_ shape: S) -> some View {
        background {
            if #available(iOS 26.0, *) {
                Color.clear.glassEffect(Glass.regular.tint(HushStyle.paper.opacity(0.3)), in: shape)
            } else {
                shape.fill(.ultraThinMaterial)
            }
        }
    }
}

/// Extra space at the end of a scroll view so its last rows can scroll up clear of the floating
/// mini player. Measured, not guessed: where the system already leaves room (the scroll view ends
/// above the mini player) it adds nothing; where it doesn't (the swipeable library tabs), it adds
/// exactly what's covered plus a little breathing room.
struct MiniPlayerClearance: ViewModifier {
    @Environment(\.miniPlayerTop) private var miniPlayerTop
    @State private var bottomEdge: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .contentMargins(.bottom, Self.margin(bottomEdge: bottomEdge, miniPlayerTop: miniPlayerTop), for: .scrollContent)
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).maxY } action: { edge in
                if abs(edge - bottomEdge) > 0.5 { bottomEdge = edge }
            }
    }

    static func margin(bottomEdge: CGFloat, miniPlayerTop: CGFloat) -> CGFloat {
        guard miniPlayerTop.isFinite, bottomEdge.isFinite, bottomEdge > 0 else { return 0 }
        let covered = bottomEdge - miniPlayerTop
        return covered > 1 ? covered + 12 : 0
    }
}

extension View {
    /// See `MiniPlayerClearance`.
    func miniPlayerClearance() -> some View {
        modifier(MiniPlayerClearance())
    }
}

extension View {
    /// Liquid Glass behind a control (iOS 26); frosted material on earlier versions.
    /// The glass is a separate, static background layer: it never animates, only what's drawn on
    /// top of it does (animated glass is what caused glitches before).
    func hushGlassBackground<S: Shape>(_ shape: S) -> some View {
        background {
            if #available(iOS 26.0, *) {
                Color.clear.glassEffect(.regular, in: shape)
            } else {
                shape.fill(.ultraThinMaterial)
            }
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var library: MusicLibraryStore
    @Namespace private var artworkNamespace
    @State private var path: [HushRoute] = []
    /// The player is presented full screen over everything (Apple Music–style), not pushed like a page.
    @State private var isPlayerPresented = false
    @State private var playerArtworkTransitionID: String?
    /// The About sheet (version, privacy policy, photo credits), opened from the Hush wordmark.
    @State private var isAboutPresented = false
    /// Pages opened from a cover remember which cover, so they zoom out of it and back into it.
    /// Pages opened any other way (e.g. "Playing from" in the player) slide in as usual.
    @State private var pageZoomSources: [HushRoute: String] = [:]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Top edge of the mini player on screen (infinity when it's hidden); lists use it to keep their
    /// last rows reachable above it.
    @State private var miniPlayerTop: CGFloat = .infinity
    @Namespace private var tabNamespace
    @State private var selectedTab: LibraryTab = .albums
    @State private var scrollToTop = ScrollToTopRequest()
    @State private var sort: LibrarySort = .alphabetical
    /// The Artists tab has its own sort: artists with the most songs first by default (remembered).
    /// Favorites first by default (new key, so everyone starts there once).
    @AppStorage("hush.artistSort.v2") private var artistSort: LibrarySort = .favorites

    /// The sort for whichever tab is showing.
    private var currentSort: Binding<LibrarySort> {
        selectedTab == .artists ? $artistSort : $sort
    }
    @State private var searchText = ""
    /// Bottom edge of the floating header on screen; the pages leave exactly that much room.
    @State private var libraryHeaderBottom: CGFloat = 0
    /// Whether album/playlist names appear under the artwork in the grids. Off by default; remembered between launches.
    @AppStorage("hush.showGridTitles") private var showGridTitles = false
    /// The same for movie names under the posters. Off by default, remembered on its own.
    @AppStorage("hush.showMovieTitles") private var showMovieTitles = false

    /// The titles toggle in the header: movies have their own, albums and playlists share one.
    private var gridTitles: Binding<Bool> {
        selectedTab == .movies ? $showMovieTitles : $showGridTitles
    }

    // Filtered + sorted lists are cached and rebuilt only when search, sort, or the library changes,
    // instead of re-sorting the whole library on every redraw (e.g. each play/pause).
    @State private var visibleAlbums: [MusicAlbum] = []
    @State private var visibleAlbumIDs: [UInt64] = []
    @State private var visibleAlbumLetters: [String] = []
    @State private var visibleSongs: [MPMediaItem] = []
    @State private var visibleSongIDs: [UInt64] = []
    @State private var visibleSongLetters: [String] = []
    @State private var visiblePlaylists: [MusicPlaylist] = []
    @State private var visibleArtists: [MusicArtist] = []
    @State private var visibleArtistIDs: [String] = []
    @State private var visibleArtistLetters: [String] = []
    @State private var visibleVideos: [LibraryVideo] = []
    @State private var visibleVideoIDs: [UInt64] = []
    @State private var visibleVideoLetters: [String] = []
    @State private var visibleMovies: [LibraryVideo] = []
    @State private var visibleMovieIDs: [UInt64] = []
    @State private var visibleMovieLetters: [String] = []
    /// Every genre tag among the movies, A–Z, for the filter above the posters.
    @State private var movieGenres: [String] = []
    /// The genre the Movies tab is narrowed to; nil shows every movie.
    @State private var movieGenre: String?
    /// A tapped video or movie that can't be played here (not on this iPhone); shows a short note.
    @State private var unavailableVideo: LibraryVideo?

    private func rebuildVisibleLibrary() {
        let query = LibrarySearch.normalizedQuery(searchText)
        let songInfo = library.songInfo

        // Albums and playlists also match by the songs in them (name matches are listed first).
        var albums = LibrarySearch.filterByNameThenSongs(
            library.albums, query: query, nameKey: \.searchKey, songsKey: \.songSearchKey
        )
        var songs = library.songs.filter { LibrarySearch.matches(songInfo[$0.persistentID]?.searchKey, query: query) }

        if sort == .mostPlayed {
            albums = Self.sortedByPlayCount(albums) { $0.totalPlayCount }
            songs = Self.sortedByPlayCount(songs) { $0.playCount }
        }

        let songIDs = songs.map(\.persistentID)
        visibleAlbums = albums
        visibleAlbumIDs = albums.map(\.id)
        visibleAlbumLetters = sort == .alphabetical ? albums.map(\.sectionLetter) : []
        visibleSongs = songs
        visibleSongIDs = songIDs
        visibleSongLetters = sort == .alphabetical ? songIDs.map { songInfo[$0]?.sectionLetter ?? "#" } : []
        var videos = library.videos.filter { LibrarySearch.matches($0.searchKey, query: query) }
        if sort == .mostPlayed {
            videos = Self.sortedByPlayCount(videos) { $0.item?.playCount ?? 0 }
        }
        visibleVideos = videos
        visibleVideoIDs = videos.map(\.id)
        visibleVideoLetters = sort == .alphabetical ? videos.map(\.sectionLetter) : []

        movieGenres = Array(Set(library.movies.compactMap(\.genre)))
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        if let genre = movieGenre, !movieGenres.contains(genre) { movieGenre = nil }
        var movies = library.movies.filter { movie in
            (movieGenre == nil || movie.genre == movieGenre) && LibrarySearch.matches(movie.searchKey, query: query)
        }
        if sort == .mostPlayed {
            movies = Self.sortedByPlayCount(movies) { $0.item?.playCount ?? 0 }
        }
        visibleMovies = movies
        visibleMovieIDs = movies.map(\.id)
        visibleMovieLetters = sort == .alphabetical ? movies.map(\.sectionLetter) : []

        var artists = LibrarySearch.filterByNameThenSongs(
            library.artists, query: query, nameKey: \.searchKey, songsKey: \.songSearchKey
        )
        switch artistSort {
        case .favorites:
            // Only your favorites, most songs first (ties A–Z). While searching, every match shows
            // (favorites first) so you can still find anyone to add.
            let favorites = library.favoriteArtistIDs
            if query.isEmpty {
                artists = artists.filter { favorites.contains($0.id) }
            }
            artists = artists.enumerated()
                .map { (offset: $0.offset, artist: $0.element, songs: $0.element.songCount, isFavorite: favorites.contains($0.element.id)) }
                .sorted { lhs, rhs in
                    if lhs.isFavorite != rhs.isFavorite { return lhs.isFavorite }
                    return lhs.songs != rhs.songs ? lhs.songs > rhs.songs : lhs.offset < rhs.offset
                }
                .map { $0.artist }
        case .mostSongs:
            // Most songs in your library first; ties stay A–Z.
            artists = artists.enumerated()
                .map { (offset: $0.offset, artist: $0.element, songs: $0.element.songCount) }
                .sorted { $0.songs != $1.songs ? $0.songs > $1.songs : $0.offset < $1.offset }
                .map { $0.artist }
        case .mostPlayed:
            artists = Self.sortedByPlayCount(artists) { $0.totalPlayCount }
        case .alphabetical:
            break
        }
        visibleArtists = artists
        visibleArtistIDs = artists.map(\.id)
        visibleArtistLetters = artistSort == .alphabetical ? artists.map(\.sectionLetter) : []
        visiblePlaylists = LibrarySearch.filterByNameThenSongs(
            library.playlists, query: query, nameKey: \.searchKey, songsKey: \.songSearchKey
        )
    }

    /// Most-played first; ties keep their existing (alphabetical) order. Reads each play count once.
    private static func sortedByPlayCount<Element>(_ items: [Element], playCount: (Element) -> Int) -> [Element] {
        items.enumerated()
            .map { (offset: $0.offset, element: $0.element, plays: playCount($0.element)) }
            .sorted { $0.plays != $1.plays ? $0.plays > $1.plays : $0.offset < $1.offset }
            .map { $0.element }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                HushStyle.paper.ignoresSafeArea()
                // Hush's own soft light at the top (the same whatever is playing), so the glass
                // header has something to catch without the library changing color with every song.
                HushAmbientLight()
                // The header floats over the library with no panel behind it (App Store style):
                // each control sits on its own Liquid Glass, and the lists scroll underneath and
                // stay visible. The pages get the header's measured height as their top inset.
                libraryContent
                    .environment(\.libraryHeaderBottom, libraryHeaderBottom)
                    .overlay(alignment: .top) {
                        VStack(spacing: 0) {
                            // The whole header — title, search and tabs — stays put while you scroll.
                            header
                            searchField
                            tabPicker
                        }
                        .background {
                            // What shows through the header is behind glass, not a button: a tap that
                            // just misses a control must not open the album underneath it.
                            Color.clear
                                .contentShape(Rectangle())
                                .onTapGesture {}
                                .ignoresSafeArea(edges: .top)
                                .accessibilityHidden(true)
                        }
                        .background { LegacyHeaderShade() }
                        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).maxY } action: { bottom in
                            if abs(bottom - libraryHeaderBottom) > 0.5 { libraryHeaderBottom = bottom }
                        }
                    }
            }
            .toolbar(.hidden, for: .navigationBar)
            .alert(
                unavailableVideo?.isMovie == true ? "This movie isn't on your iPhone" : "This video isn't on your iPhone",
                isPresented: Binding(
                    get: { unavailableVideo != nil },
                    set: { if !$0 { unavailableVideo = nil } }
                ),
                presenting: unavailableVideo
            ) { _ in
                Button("OK", role: .cancel) {}
            } message: { video in
                if video.isMovie {
                    Text("“\(video.title)” is still in the cloud or is copy-protected (movies bought from the iTunes Store can only play in the TV app). Sync your own copy from the Mac, then pull down here to refresh.")
                } else {
                    Text("“\(video.title)” is still in the cloud or is copy-protected. Download it in the Music app, then pull down here to refresh.")
                }
            }
            .task { library.requestAccess() }
            .onAppear(perform: rebuildVisibleLibrary)
            .onChange(of: searchText) { rebuildVisibleLibrary() }
            .onChange(of: movieGenre) { rebuildVisibleLibrary() }
            .onChange(of: sort) {
                rebuildVisibleLibrary()
            }
            .onChange(of: library.libraryRevision) { rebuildVisibleLibrary() }
            .onChange(of: library.favoriteArtistIDs) { rebuildVisibleLibrary() }
            .onChange(of: artistSort) {
                rebuildVisibleLibrary()
            }

            .navigationDestination(for: HushRoute.self) { route in
                Group {
                    switch route {
                    case .album(let albumID):
                        if let album = library.albums.first(where: { $0.id == albumID }) {
                            AlbumDetailView(
                                album: album,
                                artworkNamespace: artworkNamespace,
                                onPlay: { item, queue, transitionID in
                                    library.play(item, from: queue, source: .album(album.id))
                                    openPlayer(from: transitionID)
                                },
                                onShuffle: {
                                    library.playShuffled(album.items, source: .album(album.id))
                                    if let first = album.items.first {
                                        openPlayer(from: PlayerArtworkTransitionID.albumPlayButton(first.persistentID))
                                    }
                                },
                                onOpenArtist: { artistID in
                                    show(.artist(artistID))
                                }
                            )
                        }
                    case .artist(let artistID):
                        if let artist = library.artists.first(where: { $0.id == artistID }) {
                            ArtistDetailView(
                                artist: artist,
                                artworkNamespace: artworkNamespace,
                                onPlay: { item, queue, transitionID in
                                    library.play(item, from: queue, source: .artist(artistID))
                                    openPlayer(from: transitionID)
                                },
                                onShuffle: {
                                    library.playShuffled(artist.allSongs, source: .artist(artistID))
                                    openPlayer(from: PlayerArtworkTransitionID.artistHeader(artistID))
                                },
                                onOpenAlbum: { albumID in
                                    // Back returns to this artist; an album already open further back
                                    // is returned to rather than stacked twice.
                                    show(
                                        .album(albumID),
                                        zoomingFrom: PlayerArtworkTransitionID.artistPageAlbum(artistID: artistID, albumID: albumID)
                                    )
                                }
                            )
                        }
                    case .playlist(let playlistID):
                        if let playlist = library.playlists.first(where: { $0.id == playlistID }) {
                            PlaylistDetailView(
                                playlist: playlist,
                                artworkNamespace: artworkNamespace,
                                onPlay: { item, queue, transitionID in
                                    library.play(item, from: queue, playlistID: playlistID)
                                    openPlayer(from: transitionID)
                                },
                                onShuffle: {
                                    library.playShuffled(playlist.items, playlistID: playlistID)
                                    openPlayer(from: PlayerArtworkTransitionID.playlistTile(playlistID))
                                }
                            )
                        }
                    }
                }
                // Opened from a cover: zoom out of it (and back into it on Back). Reduce Motion: slide.
                .zoomTransition(from: reduceMotion ? nil : pageZoomSources[route], in: artworkNamespace)
            }
        }
        .environment(\.miniPlayerTop, miniPlayerTop)
        // Mini player floats (on glass) at the bottom of every screen — library, album and playlist pages —
        // so playback is always one tap away and closing the full player always has somewhere to land.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 8) {
                // "Playing Next" / "Added to Queue" confirmation, just above the mini player.
                QueueToast()
                if library.currentItem != nil {
                    PlayerBar(
                        artworkNamespace: artworkNamespace,
                        onOpen: {
                            openPlayer(from: PlayerArtworkTransitionID.miniPlayer)
                        },
                        onGoTo: { source in
                            show(HushRoute(source))
                        }
                    )
                    .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { top in
                        if abs(top - miniPlayerTop) > 0.5 { miniPlayerTop = top }
                    }
                    .onDisappear { miniPlayerTop = .infinity }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 4)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.86), value: library.currentItem == nil)
        // When the music runs out, close the full player instead of leaving an empty screen.
        .onChange(of: library.currentItem == nil) { _, isEmpty in
            if isEmpty { isPlayerPresented = false }
        }
        // Full-screen player: zooms out of the tapped artwork, and back into the mini player on close.
        // Swipe down to close interactively.
        .fullScreenCover(isPresented: $isPlayerPresented) {
            NowPlayingView(
                onMinimize: { isPlayerPresented = false },
                onGoTo: { source in
                    // Close the player, then open the album / artist / playlist once the close
                    // animation has finished.
                    isPlayerPresented = false
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 350_000_000)
                        show(HushRoute(source))
                    }
                }
            )
                .environmentObject(library)
                .environmentObject(library.playback)
                .environmentObject(library.queue)
                .zoomTransition(from: playerArtworkTransitionID, in: artworkNamespace)
                .onAppear {
                    // Once it's open, aim the closing zoom at the mini player (which always shows the
                    // current song), like Apple Music.
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 600_000_000)
                        playerArtworkTransitionID = PlayerArtworkTransitionID.miniPlayer
                    }
                }
        }
        .sheet(isPresented: $isAboutPresented) {
            AboutView()
        }
        .tint(HushStyle.gold)
    }

    /// Opens a page on top of where you are, so Back returns there. If that page is already open
    /// somewhere in the stack, goes back to it instead of opening it twice.
    /// `sourceID`: the cover it was opened from, if any — the page then zooms out of that cover.
    private func show(_ route: HushRoute, zoomingFrom sourceID: String? = nil) {
        if let index = path.lastIndex(of: route) {
            path.removeLast(path.count - index - 1)
        } else {
            pageZoomSources[route] = sourceID
            path.append(route)
        }
    }

    /// The artist whose page the music was started from (their tile shows the now-playing mark).
    private var playingArtistID: String? {
        if case .artist(let id)? = library.playbackSource { return id }
        return nil
    }

    private func openPlayer(from transitionID: String) {
        playerArtworkTransitionID = transitionID
        isPlayerPresented = true
    }

    private var header: some View {
        HStack(alignment: .center) {
            Button {
                isAboutPresented = true
            } label: {
                // On glass like every other header control, so the wordmark reads over any cover.
                Text("Hush")
                    .font(HushStyle.brandFont(size: 28))
                    .foregroundStyle(HushStyle.gold)
                    .padding(.horizontal, 15)
                    .padding(.vertical, 3)
                    .frame(minHeight: 42)
                    .hushHeaderGlass(Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("About Hush")
            Spacer()
            // How many are showing, on its own small glass so it reads over artwork too.
            Text(tabCount)
                .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(HushStyle.ink.opacity(0.92))
                .padding(.horizontal, 12)
                .frame(minWidth: 44)
                .frame(height: 38)
                .hushHeaderGlass(Capsule())
                // The glass itself never animates.
                .animation(nil, value: selectedTab)
                .accessibilityLabel("\(tabCount) \(selectedTab.rawValue.lowercased())")
            if selectedTab == .playlists || selectedTab == .albums || selectedTab == .movies {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        gridTitles.wrappedValue.toggle()
                    }
                } label: {
                    Image(systemName: "text.below.photo")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(gridTitles.wrappedValue ? HushStyle.gold : HushStyle.ink.opacity(0.9))
                        .frame(width: 38, height: 38)
                        .hushHeaderGlass(Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Show titles")
                .accessibilityValue(gridTitles.wrappedValue ? "On" : "Off")
            }
            // Playlists are listed A–Z like the Music app; sorting only applies to Albums and Songs.
            if selectedTab != .playlists {
                Menu {
                    Picker("Sort", selection: currentSort) {
                        ForEach(LibrarySort.options(for: selectedTab), id: \.self) { option in
                            Label(option.rawValue, systemImage: option.symbol).tag(option)
                        }
                    }
                    // Same as pulling down on the Artists tab, where few would think to look: asks the
                    // catalogs again for artists still showing initials. New photos fade in as they arrive.
                    if selectedTab == .artists {
                        Section {
                            Button {
                                Task { await library.refreshLibrary() }
                            } label: {
                                Label("Look for Missing Photos", systemImage: "arrow.clockwise")
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: currentSort.wrappedValue.symbol)
                            .font(.system(size: 10, weight: .semibold))
                        Text(currentSort.wrappedValue.shortLabel)
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .tracking(0.7)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .bold))
                    }
                    .foregroundStyle(HushStyle.ink.opacity(0.92))
                    .padding(.horizontal, 13)
                    .frame(height: 38)
                    .hushHeaderGlass(Capsule())
                    .contentShape(Capsule())
                }
                .accessibilityLabel("Sort by \(currentSort.wrappedValue.rawValue)")
            }
        }
        .frame(minHeight: 36)
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 12)
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(HushStyle.ink.opacity(0.75))
            QuietTextField(
                text: $searchText,
                placeholder: searchPlaceholder,
                capitalization: .none,
                returnKeyType: .search,
                fontSize: 15,
                // Brighter than the usual muted grey: it now sits on glass over artwork.
                placeholderColor: UIColor(HushStyle.ink.opacity(0.72))
            )
            .accessibilityLabel("Search music library")
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(HushStyle.ink.opacity(0.7))
                        .frame(width: 32, height: 40)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 15)
        .frame(height: 46)
        .hushHeaderGlass(Capsule())
        .padding(.horizontal, 18)
        .padding(.bottom, 12)
    }

    private var searchPlaceholder: String {
        switch selectedTab {
        case .albums: return "Find an album, artist or song"
        case .artists: return "Find an artist or song"
        case .songs: return "Find a song, artist or album"
        case .playlists: return "Find a playlist or song"
        case .videos: return "Find a video"
        case .movies: return "Find a movie or genre"
        }
    }

    private var tabPicker: some View {
        HStack(spacing: 12) {
            HStack(spacing: 2) {
                ForEach(LibraryTab.allCases, id: \.self) { tab in
                    Button {
                        if selectedTab == tab {
                            // Already here: back to the top, like tapping a tab in Apple's apps.
                            scrollToTop = ScrollToTopRequest(tab: tab, count: scrollToTop.count + 1)
                        } else {
                            withAnimation(.snappy(duration: 0.3)) { selectedTab = tab }
                        }
                    } label: {
                        Text(tab.rawValue)
                            .font(.system(size: 14, weight: selectedTab == tab ? .semibold : .medium, design: .rounded))
                            .foregroundStyle(selectedTab == tab ? HushStyle.paper : HushStyle.ink.opacity(0.92))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .padding(.horizontal, 3)
                            // Six tabs share the full width equally (the count sits in the title row).
                            .frame(maxWidth: .infinity)
                            .frame(height: 32)
                            .background {
                                if selectedTab == tab {
                                    Capsule()
                                        .fill(HushStyle.gold)
                                        .matchedGeometryEffect(id: "tab-selection", in: tabNamespace)
                                }
                            }
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
                }
            }
            .padding(3)
            // Static glass track; only the gold pill on top of it moves.
            .hushHeaderGlass(Capsule())
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 10)
        // Scoped to the tab bar only, so the library content itself switches instantly.
        .animation(.spring(response: 0.34, dampingFraction: 0.82), value: selectedTab)
    }

    private var tabCount: String {
        switch selectedTab {
        case .albums: return "\(visibleAlbums.count)"
        case .artists: return "\(visibleArtists.count)"
        case .songs: return "\(visibleSongs.count)"
        case .playlists: return "\(visiblePlaylists.count)"
        case .videos: return "\(visibleVideos.count)"
        case .movies: return "\(visibleMovies.count)"
        }
    }

    @ViewBuilder
    private var libraryContent: some View {
        if library.authorizationStatus == .denied || library.authorizationStatus == .restricted {
            accessMessage
                .underLibraryHeader()
        } else if library.authorizationStatus == .notDetermined || library.isLoading {
            VStack(spacing: 12) {
                ProgressView().tint(HushStyle.gold)
                Text("Gathering your music")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(HushStyle.muted)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .underLibraryHeader()
        } else {
            // Swipe left/right to move between tabs; the pages follow your finger.
            TabView(selection: $selectedTab) {
                albumsPage
                    .underLibraryHeader()
                    .tag(LibraryTab.albums)
                songsPage
                    .underLibraryHeader()
                    .tag(LibraryTab.songs)
                playlistList
                    .underLibraryHeader()
                    .tag(LibraryTab.playlists)
                artistsPage
                    .underLibraryHeader()
                    .tag(LibraryTab.artists)
                videosPage
                    .underLibraryHeader()
                    .tag(LibraryTab.videos)
                moviesPage
                    .underLibraryHeader()
                    .tag(LibraryTab.movies)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            // A paging TabView clips its pages to its own frame. Stretch it up to the top of the
            // screen so the lists really pass under the header and status bar (each page keeps
            // its content below the header with `underLibraryHeader`).
            .ignoresSafeArea(.container, edges: .top)
        }
    }

    @ViewBuilder
    private var albumsPage: some View {
        if library.songs.isEmpty || visibleAlbums.isEmpty {
            emptyLibraryMessage
        } else {
            albumGrid
        }
    }

    @ViewBuilder
    private var artistsPage: some View {
        if !library.songs.isEmpty, visibleArtists.isEmpty, artistSort == .favorites, searchText.isEmpty {
            favoritesEmptyMessage
        } else if library.songs.isEmpty || visibleArtists.isEmpty {
            emptyLibraryMessage
        } else {
            artistGrid
        }
    }

    /// Favorites view with no favorites yet: how to add some, and a way to see everyone.
    private var favoritesEmptyMessage: some View {
        VStack(spacing: 12) {
            Image(systemName: "heart")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(HushStyle.gold.opacity(0.85))
            Text("No favorite artists yet")
                .font(.system(size: 21, weight: .regular, design: .serif))
                .foregroundStyle(HushStyle.ink)
            Text("Open an artist and tap the heart, or press and hold their picture.")
                .font(.system(size: 14))
                .foregroundStyle(HushStyle.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
            Button {
                artistSort = .mostSongs
            } label: {
                Text("Show All Artists")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(HushStyle.paper)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 11)
                    .background(HushStyle.gold, in: Capsule())
            }
            .buttonStyle(PopButtonStyle())
            .padding(.top, 4)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// One circular tile per artist (collaborations and spelling variants merged).
    private var artistGrid: some View {
        FastScrollContainer(
            itemIDs: visibleArtistIDs,
            itemLetters: visibleArtistLetters,
            isAlphabetical: artistSort == .alphabetical,
            itemsPerRow: 3,
            estimatedRowHeight: 168,
            estimatedPadding: 36,
            onRefresh: { await library.refreshLibrary() },
            scrollToTopSignal: scrollToTop.signal(for: .artists)
        ) {
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 3),
                alignment: .center,
                spacing: 20
            ) {
                // The artist the music was started from gets the now-playing mark.
                let startedFromArtistID = playingArtistID
                ForEach(visibleArtists) { artist in
                    let isFavorite = library.favoriteArtistIDs.contains(artist.id)
                    Button {
                        show(.artist(artist.id), zoomingFrom: PlayerArtworkTransitionID.artistGridTile(artist.id))
                    } label: {
                        ArtistTile(
                            artist: artist,
                            isFavorite: isFavorite,
                            isPlaying: startedFromArtistID == artist.id,
                            zoomNamespace: artworkNamespace
                        )
                    }
                    .buttonStyle(TilePressStyle())
                    .contextMenu { artistMenu(artist, isFavorite: isFavorite) }
                    .underHeaderBlur()
                    .id(artist.id)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 20)
            .padding(.bottom, 16)
        }
    }

    /// Long-press menu on an artist: favorite, plus the usual Play Next / Add to Queue.
    @ViewBuilder
    private func artistMenu(_ artist: MusicArtist, isFavorite: Bool) -> some View {
        Button {
            library.toggleFavorite(artistID: artist.id)
        } label: {
            if isFavorite {
                Label("Remove from Favorites", systemImage: "heart.slash")
            } else {
                Label("Add to Favorites", systemImage: "heart")
            }
        }
        Button {
            library.playNext(artist.allSongs)
        } label: {
            Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward")
        }
        Button {
            library.addToQueue(artist.allSongs)
        } label: {
            Label("Add to Queue", systemImage: "text.line.last.and.arrowtriangle.forward")
        }
    }

    /// Music videos from the Music app. Tap one to watch it full screen.
    @ViewBuilder
    private var videosPage: some View {
        if visibleVideos.isEmpty {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    Image(systemName: searchText.isEmpty ? "play.rectangle" : "magnifyingglass")
                        .font(.system(size: 31, weight: .light))
                        .foregroundStyle(HushStyle.gold.opacity(0.85))
                    Text(searchText.isEmpty ? "No videos yet" : "No videos found")
                        .font(.system(size: 21, weight: .regular, design: .serif))
                        .foregroundStyle(HushStyle.ink)
                    Text(searchText.isEmpty
                         ? "Music videos in the Music app appear here once they're on this iPhone. Pull down to check again."
                         : "Try another video name.")
                        .font(.system(size: 14))
                        .foregroundStyle(HushStyle.muted)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 290)
                }
                .padding(28)
                .frame(maxWidth: .infinity, minHeight: 250)
            }
            .scrollDismissesKeyboard(.immediately)
            .refreshable { await library.refreshLibrary() }
        } else {
            videoGrid
        }
    }

    private var videoGrid: some View {
        FastScrollContainer(
            itemIDs: visibleVideoIDs,
            itemLetters: visibleVideoLetters,
            isAlphabetical: sort == .alphabetical,
            itemsPerRow: 2,
            estimatedRowHeight: 106,
            estimatedPadding: 36,
            onRefresh: { await library.refreshLibrary() },
            scrollToTopSignal: scrollToTop.signal(for: .videos)
        ) {
            // Titles sit on the stills, so the tiles pack close together like the Albums grid.
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 2),
                alignment: .leading,
                spacing: 5
            ) {
                ForEach(visibleVideos) { video in
                    Button {
                        play(video)
                    } label: {
                        VideoTile(video: video)
                    }
                    .buttonStyle(TilePressStyle())
                    .underHeaderBlur()
                    .id(video.id)
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 20)
            .padding(.bottom, 16)
        }
    }

    /// Movies from the phone's library, as posters, with a genre filter on top. Tap one to watch it
    /// full screen in the same player as the music videos.
    @ViewBuilder
    private var moviesPage: some View {
        if visibleMovies.isEmpty {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    if !movieGenres.isEmpty {
                        genreFilter
                            .padding(.top, 20)
                    }
                    VStack(spacing: 12) {
                        let filtered = !searchText.isEmpty || movieGenre != nil
                        Image(systemName: filtered ? "magnifyingglass" : "film")
                            .font(.system(size: 31, weight: .light))
                            .foregroundStyle(HushStyle.gold.opacity(0.85))
                        Text(filtered ? "No movies found" : "No movies yet")
                            .font(.system(size: 21, weight: .regular, design: .serif))
                            .foregroundStyle(HushStyle.ink)
                        Text(filtered
                             ? "Try another name or genre."
                             : "Movies synced to this iPhone from the TV app on your Mac appear here. Pull down to check again.")
                            .font(.system(size: 14))
                            .foregroundStyle(HushStyle.muted)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 290)
                    }
                    .padding(28)
                    .frame(maxWidth: .infinity, minHeight: 250)
                }
            }
            .scrollDismissesKeyboard(.immediately)
            .refreshable { await library.refreshLibrary() }
        } else {
            movieGrid
        }
    }

    private var movieGrid: some View {
        FastScrollContainer(
            itemIDs: visibleMovieIDs,
            itemLetters: visibleMovieLetters,
            isAlphabetical: sort == .alphabetical,
            itemsPerRow: 3,
            estimatedRowHeight: showMovieTitles ? 236 : 186,
            estimatedPadding: movieGenres.isEmpty ? 36 : 82,
            onRefresh: { await library.refreshLibrary() },
            scrollToTopSignal: scrollToTop.signal(for: .movies)
        ) {
            VStack(alignment: .leading, spacing: 16) {
                if !movieGenres.isEmpty {
                    genreFilter
                        .underHeaderBlur()
                }
                // Like the Albums grid: posters close together, names only when the titles toggle is on.
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: showMovieTitles ? 10 : 6), count: 3),
                    alignment: .leading,
                    spacing: showMovieTitles ? 18 : 6
                ) {
                    ForEach(visibleMovies) { movie in
                        Button {
                            play(movie)
                        } label: {
                            MovieTile(movie: movie, showsTitle: showMovieTitles)
                        }
                        .buttonStyle(TilePressStyle())
                        .underHeaderBlur()
                        .id(movie.id)
                    }
                }
                .padding(.horizontal, 8)
            }
            .padding(.top, 20)
            .padding(.bottom, 16)
        }
    }

    /// "All" plus one pill per genre; tapping a pill shows only that genre (tap again for all).
    private var genreFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                genrePill("All", isSelected: movieGenre == nil) { movieGenre = nil }
                ForEach(movieGenres, id: \.self) { genre in
                    genrePill(genre, isSelected: movieGenre == genre) {
                        movieGenre = movieGenre == genre ? nil : genre
                    }
                }
            }
            .padding(.horizontal, 12)
        }
        .scrollClipDisabled()
    }

    private func genrePill(_ title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            withAnimation(.snappy(duration: 0.25)) { action() }
        } label: {
            Text(title)
                .font(.system(size: 13, weight: isSelected ? .semibold : .medium, design: .rounded))
                .foregroundStyle(isSelected ? HushStyle.paper : HushStyle.ink.opacity(0.9))
                .padding(.horizontal, 14)
                .frame(height: 32)
                .background(isSelected ? HushStyle.gold : HushStyle.surface, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// Stops the music and opens the video full screen; says why when it can't be played here.
    private func play(_ video: LibraryVideo) {
        guard video.assetURL != nil else {
            unavailableVideo = video
            return
        }
        Haptics.play()
        library.pauseForVideo()
        VideoPlayback.present(video)
    }

    @ViewBuilder
    private var songsPage: some View {
        if library.songs.isEmpty || visibleSongs.isEmpty {
            emptyLibraryMessage
        } else {
            songList
        }
    }

    private var albumGrid: some View {
        FastScrollContainer(
            itemIDs: visibleAlbumIDs,
            itemLetters: visibleAlbumLetters,
            isAlphabetical: sort == .alphabetical,
            itemsPerRow: 3,
            estimatedRowHeight: showGridTitles ? 177 : 131,
            estimatedPadding: 36,
            onRefresh: { await library.refreshLibrary() },
            scrollToTopSignal: scrollToTop.signal(for: .albums)
        ) {
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: showGridTitles ? 10 : 6), count: 3),
                alignment: .leading,
                spacing: showGridTitles ? 18 : 6
            ) {
                // The album of the song that's playing gets the now-playing mark.
                let playingAlbumID = library.currentItem?.albumPersistentID
                ForEach(visibleAlbums) { album in
                    Button {
                        show(.album(album.id), zoomingFrom: PlayerArtworkTransitionID.albumGridTile(album.id))
                    } label: {
                        AlbumTile(
                            album: album,
                            showsTitle: showGridTitles,
                            isPlaying: playingAlbumID == album.id,
                            zoomNamespace: artworkNamespace
                        )
                    }
                    .buttonStyle(TilePressStyle())
                    .queueMenu(album.items)
                    .underHeaderBlur()
                    .id(album.id)
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 20)
            .padding(.bottom, 16)
        }
    }

    private var songList: some View {
        FastScrollContainer(
            itemIDs: visibleSongIDs,
            itemLetters: visibleSongLetters,
            isAlphabetical: sort == .alphabetical,
            itemsPerRow: 1,
            estimatedRowHeight: 72,
            estimatedPadding: 25,
            onRefresh: { await library.refreshLibrary() },
            scrollToTopSignal: scrollToTop.signal(for: .songs)
        ) {
            LazyVStack(spacing: 0) {
                // No enumerated() copy of the whole list: this body re-runs on every navigation.
                let lastSongID = visibleSongIDs.last
                ForEach(visibleSongs, id: \.persistentID) { song in
                    HStack(spacing: 8) {
                        Button {
                            library.play(song, from: visibleSongs)
                            openPlayer(from: PlayerArtworkTransitionID.librarySong(song.persistentID))
                        } label: {
                            SongRow(
                                item: song,
                                isCurrent: library.currentItem?.persistentID == song.persistentID,
                                artworkNamespace: artworkNamespace
                            )
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity)
                        .queueMenu([song])
                    }
                    .underHeaderBlur()
                    .id(song.persistentID)
                    if song.persistentID != lastSongID {
                        Rectangle().fill(HushStyle.line.opacity(0.34)).frame(height: 0.5).padding(.leading, 76)
                            .underHeaderBlur()
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 9)
            .padding(.bottom, 16)
        }
    }

    /// Playlists come from the Music app. Edit them there, then pull down here to refresh.
    @ViewBuilder
    private var playlistList: some View {
        let playlists = visiblePlaylists
        if playlists.isEmpty {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    Image(systemName: searchText.isEmpty ? "music.note.list" : "magnifyingglass")
                        .font(.system(size: 31, weight: .light))
                        .foregroundStyle(HushStyle.gold.opacity(0.85))
                    Text(searchText.isEmpty ? "No playlists yet" : "No playlists found")
                        .font(.system(size: 21, weight: .regular, design: .serif))
                        .foregroundStyle(HushStyle.ink)
                    Text(searchText.isEmpty
                         ? "Make playlists in the Music app, then pull down here to bring them in."
                         : "Try another playlist or song name.")
                        .font(.system(size: 14))
                        .foregroundStyle(HushStyle.muted)
                        .multilineTextAlignment(.center)
                }
                .padding(28)
                .frame(maxWidth: .infinity, minHeight: 250)
            }
            .scrollDismissesKeyboard(.immediately)
            .refreshable { await library.refreshLibrary() }
        } else {
            // Same cover grid, A–Z index, and spacing as the Albums tab.
            FastScrollContainer(
                itemIDs: playlists.map(\.id),
                itemLetters: playlists.map(\.sectionLetter),
                isAlphabetical: true,
                itemsPerRow: 3,
                estimatedRowHeight: showGridTitles ? 177 : 131,
                estimatedPadding: 36,
                onRefresh: { await library.refreshLibrary() },
                scrollToTopSignal: scrollToTop.signal(for: .playlists)
            ) {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: showGridTitles ? 10 : 6), count: 3),
                    alignment: .leading,
                    spacing: showGridTitles ? 18 : 6
                ) {
                    let playingPlaylistID = library.nowPlayingPlaylistID
                    ForEach(playlists) { playlist in
                        Button {
                            show(.playlist(playlist.id), zoomingFrom: PlayerArtworkTransitionID.playlistGridTile(playlist.id))
                        } label: {
                            PlaylistTile(
                                playlist: playlist,
                                artwork: library.artwork(for: playlist),
                                showsTitle: showGridTitles,
                                isPlaying: playingPlaylistID == playlist.id,
                                zoomNamespace: artworkNamespace
                            )
                        }
                        .buttonStyle(TilePressStyle())
                        .queueMenu(playlist.items)
                        .underHeaderBlur()
                        .id(playlist.id)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.top, 20)
                .padding(.bottom, 16)
            }
        }
    }

    private var accessMessage: some View {
        VStack(spacing: 13) {
            Image(systemName: "music.note.list")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(HushStyle.muted)
            Text("Let your music in")
                .font(.system(size: 21, weight: .regular, design: .serif))
                .foregroundStyle(HushStyle.ink)
            (
                Text("Hush")
                    .font(HushStyle.brandFont(size: 14))
                    .foregroundColor(HushStyle.gold)
                + Text(" needs library access to show your downloaded music and its artwork.")
                    .font(.system(size: 14))
                    .foregroundColor(HushStyle.muted)
            )
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
            Button("Open Settings") {
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                UIApplication.shared.open(url)
            }
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .foregroundStyle(HushStyle.paper)
            .padding(.horizontal, 18)
            .padding(.vertical, 11)
            .background(HushStyle.gold, in: Capsule())
            .padding(.top, 4)
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyLibraryMessage: some View {
        let isLibraryEmpty = searchText.isEmpty && library.songs.isEmpty
        return VStack(spacing: 12) {
            Image(systemName: searchText.isEmpty ? "waveform" : "magnifyingglass")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(HushStyle.gold.opacity(0.8))
            Text(searchText.isEmpty ? "A quiet start" : "Nothing found")
                .font(.system(size: 21, weight: .regular, design: .serif))
                .foregroundStyle(HushStyle.ink)
            Text(isLibraryEmpty
                 ? "Songs you buy or add in the Music app appear here once they're downloaded to this iPhone."
                 : searchText.isEmpty ? "Nothing here yet." : "Try another song, album, or artist.")
                .font(.system(size: 14))
                .foregroundStyle(HushStyle.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 290)
            if isLibraryEmpty {
                Button("Open Music") {
                    guard let url = URL(string: "music://") else { return }
                    UIApplication.shared.open(url)
                }
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(HushStyle.paper)
                .padding(.horizontal, 18)
                .padding(.vertical, 11)
                .background(HushStyle.gold, in: Capsule())
                .padding(.top, 4)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Before iOS 26 there is no Liquid Glass or scroll-edge effect, so the floating header gets a
/// soft dark shade behind it (fading out below the tabs) to stay readable. On iOS 26 and later
/// this draws nothing.
private struct LegacyHeaderShade: View {
    var body: some View {
        if #available(iOS 26.0, *) {
            EmptyView()
        } else {
            LinearGradient(
                stops: [
                    .init(color: HushStyle.paper.opacity(0.9), location: 0),
                    .init(color: HushStyle.paper.opacity(0.7), location: 0.7),
                    .init(color: HushStyle.paper.opacity(0), location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .padding(.bottom, -18)
            .ignoresSafeArea(edges: .top)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

private struct PlaylistTile: View {
    let playlist: MusicPlaylist
    let artwork: Artwork?
    let showsTitle: Bool
    var isPlaying = false
    let zoomNamespace: Namespace.ID

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Square cell sized by the grid column, matching album tiles.
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    GeometryReader { geometry in
                        PlaylistArtwork(
                            items: playlist.artworkItems,
                            size: geometry.size.width,
                            artwork: artwork,
                            cornerRadius: 9
                        )
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if isPlaying { NowPlayingBadge(size: 22).padding(6) }
                }
                .pageZoomSource(PlayerArtworkTransitionID.playlistGridTile(playlist.id), in: zoomNamespace, cornerRadius: 9)
            if showsTitle {
                Text(playlist.name)
                    .font(.system(size: 13, weight: .medium, design: .serif))
                    .foregroundStyle(HushStyle.ink)
                    .lineLimit(1)
                Text("\(playlist.trackCount) songs")
                    .font(.system(size: 10, weight: .regular, design: .rounded))
                    .foregroundStyle(HushStyle.muted)
                    .lineLimit(1)
            }
        }
        // VoiceOver still reads the name when titles are hidden.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(playlist.name), \(playlist.trackCount) songs\(isPlaying ? ", now playing" : "")")
    }
}

private struct ArtistTile: View {
    let artist: MusicArtist
    var isFavorite = false
    var isPlaying = false
    let zoomNamespace: Namespace.ID
    /// The photo circle's width, so the page zooms out of a circle (radius = half of it).
    @State private var photoDiameter: CGFloat = 110

    var body: some View {
        VStack(spacing: 7) {
            // The artist's photo from the internet (or their initials) — never an album cover.
            ArtistPhoto(artist: artist)
                .overlay(alignment: .bottomTrailing) {
                    if isFavorite {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(HushStyle.gold)
                            .frame(width: 24, height: 24)
                            .background(HushStyle.paper, in: Circle())
                            .overlay(Circle().stroke(HushStyle.gold.opacity(0.35), lineWidth: 0.6))
                            .offset(x: -2, y: -2)
                    }
                }
                .overlay(alignment: .bottomLeading) {
                    if isPlaying { NowPlayingBadge(size: 24).offset(x: 2, y: -2) }
                }
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
                    if abs(width - photoDiameter) > 0.5 { photoDiameter = width }
                }
                .pageZoomSource(PlayerArtworkTransitionID.artistGridTile(artist.id), in: zoomNamespace, cornerRadius: photoDiameter / 2)
            Text(artist.name)
                .font(.system(size: 12.5, weight: .medium, design: .serif))
                .foregroundStyle(HushStyle.ink)
                .lineLimit(1)
            Text(artist.songCount == 1 ? "1 song" : "\(artist.songCount) songs")
                .font(.system(size: 10, weight: .regular, design: .rounded))
                .foregroundStyle(HushStyle.muted)
                .lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(artist.name), \(artist.songCount) songs\(isFavorite ? ", favorite" : "")\(isPlaying ? ", now playing" : "")")
    }
}

private struct AlbumTile: View {
    let album: MusicAlbum
    let showsTitle: Bool
    var isPlaying = false
    let zoomNamespace: Namespace.ID

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ArtworkView(item: album.artworkItem, cornerRadius: 9)
                .overlay(alignment: .bottomTrailing) {
                    if isPlaying { NowPlayingBadge(size: 22).padding(6) }
                }
                .pageZoomSource(PlayerArtworkTransitionID.albumGridTile(album.id), in: zoomNamespace, cornerRadius: 9)
            if showsTitle {
                Text(album.title)
                    .font(.system(size: 13, weight: .medium, design: .serif))
                    .foregroundStyle(HushStyle.ink)
                    .lineLimit(1)
                Text(album.artist)
                    .font(.system(size: 10, weight: .regular, design: .rounded))
                    .foregroundStyle(HushStyle.muted)
                    .lineLimit(1)
            }
        }
        // VoiceOver still reads the name when titles are hidden.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(album.title), \(album.artist)\(isPlaying ? ", now playing" : "")")
    }
}

private struct SongRow: View {
    let item: MPMediaItem
    let isCurrent: Bool
    let artworkNamespace: Namespace.ID

    var body: some View {
        HStack(spacing: 13) {
            songArtwork
                .overlay(alignment: .bottomTrailing) {
                    if isCurrent {
                        NowPlayingBadge(size: 18)
                            .offset(x: 3, y: 3)
                    }
                }
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title ?? "Untitled")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(isCurrent ? HushStyle.gold : HushStyle.ink)
                    .lineLimit(1)
                Text([item.artist, item.albumTitle].compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 12))
                    .foregroundStyle(HushStyle.muted)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if item.playCount > 0 {
                Text("\(item.playCount)")
                    .font(.system(size: 11, weight: .medium, design: .rounded).monospacedDigit())
                    .foregroundStyle(HushStyle.muted.opacity(0.8))
                    .accessibilityLabel("Played \(item.playCount) times")
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var songArtwork: some View {
        let artwork = ArtworkView(item: item, cornerRadius: 10, size: CGSize(width: 120, height: 120))
            .frame(width: 54, height: 54)

        if #available(iOS 18.0, *) {
            artwork.matchedTransitionSource(
                id: PlayerArtworkTransitionID.librarySong(item.persistentID),
                in: artworkNamespace
            )
        } else {
            artwork
        }
    }
}

private struct FastScrollContainer<ItemID: Hashable, Content: View>: View {
    let itemIDs: [ItemID]
    let itemLetters: [String]
    let isAlphabetical: Bool
    private let letterTargets: [AlphabeticalLetterTarget<ItemID>]
    let itemsPerRow: Int
    let estimatedRowHeight: CGFloat
    let estimatedPadding: CGFloat
    let onRefresh: () async -> Void
    let onScrollOffsetChange: ((CGFloat, CGFloat) -> Void)?
    /// Changes when you tap the tab you're already on: scrolls back to the top (like Apple's apps).
    let scrollToTopSignal: Int?
    let content: Content

    @Environment(\.miniPlayerTop) private var miniPlayerTop
    /// Bottom edge of this list on screen, to work out how much of it the mini player covers.
    @State private var viewportBottom: CGFloat = 0
    @State private var metrics = FastScrollMetrics()
    @State private var lastDragTarget: Int?
    @State private var dragProgressFallback: CGFloat?
    @State private var underlyingScrollView: UIScrollView?
    /// The A–Z index / scroll bar floats over the artwork only while the list is moving (or you're
    /// touching it), then fades away.
    @State private var isIndexShown = false
    @State private var isTouchingIndex = false
    @State private var indexHideGeneration = 0
    private let scrollCoordinateSpace = UUID()

    /// Scroll activity is only reported on iOS 18+; before that the index simply stays visible.
    private var showsIndex: Bool {
        if #available(iOS 18.0, *) { return isIndexShown || isTouchingIndex }
        return true
    }

    init(
        itemIDs: [ItemID],
        itemLetters: [String],
        isAlphabetical: Bool,
        itemsPerRow: Int,
        estimatedRowHeight: CGFloat,
        estimatedPadding: CGFloat,
        onRefresh: @escaping () async -> Void,
        onScrollOffsetChange: ((CGFloat, CGFloat) -> Void)? = nil,
        scrollToTopSignal: Int? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.scrollToTopSignal = scrollToTopSignal
        self.itemIDs = itemIDs
        self.itemLetters = itemLetters
        self.isAlphabetical = isAlphabetical
        if isAlphabetical {
            var seen = Set<String>()
            self.letterTargets = zip(itemLetters, itemIDs).compactMap { letter, itemID in
                guard seen.insert(letter).inserted else { return nil }
                return AlphabeticalLetterTarget(letter: letter, itemID: itemID)
            }
        } else {
            self.letterTargets = []
        }
        self.itemsPerRow = max(itemsPerRow, 1)
        self.estimatedRowHeight = estimatedRowHeight
        self.estimatedPadding = estimatedPadding
        self.onRefresh = onRefresh
        self.onScrollOffsetChange = onScrollOffsetChange
        self.content = content()
    }

    var body: some View {
        ScrollViewReader { scrollProxy in
            GeometryReader { viewport in
                let rowCount = (itemIDs.count + itemsPerRow - 1) / itemsPerRow
                let viewportHeight = viewport.size.height.isFinite ? max(viewport.size.height, 0) : 0
                let measuredContentHeight = metrics.contentHeight.isFinite ? max(metrics.contentHeight, 0) : 0
                let measuredContentMinY = metrics.contentMinY.isFinite ? metrics.contentMinY : 0
                let rowHeight = estimatedRowHeight.isFinite ? max(estimatedRowHeight, 0) : 0
                let paddingHeight = estimatedPadding.isFinite ? max(estimatedPadding, 0) : 0
                let estimatedContentHeight = CGFloat(rowCount) * rowHeight + paddingHeight
                let contentHeight = max(measuredContentHeight, estimatedContentHeight)
                let maxOffset = max(contentHeight - viewportHeight, 0)
                let measuredProgress = measuredContentHeight > viewportHeight && maxOffset > 0
                    ? min(max(-measuredContentMinY / max(measuredContentHeight - viewportHeight, 1), 0), 1)
                    : 0
                let progress = dragProgressFallback ?? measuredProgress
                let visibleFraction = contentHeight > 0
                    ? min(viewportHeight / contentHeight, 1)
                    : 1
                // The swipeable library tabs don't get room for the mini player from the system,
                // so the last rows used to hide behind it. Leave exactly the covered space.
                let bottomClearance = MiniPlayerClearance.margin(bottomEdge: viewportBottom, miniPlayerTop: miniPlayerTop)
                // The A–Z index / scroll bar stops well above the mini player: right next to it, the
                // glass picked it up as a grey line along its right side.
                let indexBottomInset = miniPlayerTop.isFinite && viewportBottom > 0
                    ? max(viewportBottom - miniPlayerTop + 28, 0)
                    : 0

                ScrollView(showsIndicators: false) {
                    content
                        .background {
                            GeometryReader { contentGeometry in
                                Color.clear.preference(
                                    key: FastScrollMetricsPreferenceKey.self,
                                    value: FastScrollMetrics(
                                        contentHeight: contentGeometry.size.height,
                                        contentMinY: contentGeometry.frame(in: .named(scrollCoordinateSpace)).minY
                                    )
                                )
                            }
                    }
                    .background {
                        ScrollViewAccess { resolvedScrollView in
                            if underlyingScrollView !== resolvedScrollView {
                                underlyingScrollView = resolvedScrollView
                            }
                        }
                        .frame(width: 0, height: 0)
                    }
                }
                .contentMargins(.bottom, bottomClearance, for: .scrollContent)
                .scrollDismissesKeyboard(.immediately)
                .refreshable { await onRefresh() }
                .modifier(ScrollOffsetReporter(action: onScrollOffsetChange))
                .modifier(ScrollTickHaptics(
                    // One tick per grid row (Playlists, Albums); song rows are shorter, so every
                    // second row — giving all three tabs the same rhythm.
                    stepHeight: (measuredContentHeight > 0 && rowCount > 0
                        ? max((measuredContentHeight - paddingHeight) / CGFloat(rowCount), 1)
                        : rowHeight) * (itemsPerRow == 1 ? 2 : 1)
                ))
                .coordinateSpace(name: scrollCoordinateSpace)
                .modifier(ScrollActivityReporter { isMoving in
                    if isMoving { revealIndex() } else { hideIndexSoon() }
                })
                .overlay(alignment: .trailing) {
                    if itemIDs.count > itemsPerRow, contentHeight > viewportHeight + 1 {
                        // A narrow frosted strip floating over the artwork's right edge.
                        Group {
                            if isAlphabetical {
                                if letterTargets.count > 1 {
                                    AlphabeticalLetterIndex(targets: letterTargets) { targetID, isScrubbing in
                                        if isScrubbing {
                                            scrollProxy.scrollTo(targetID, anchor: .top)
                                        } else {
                                            jumpToLetter(targetID, using: scrollProxy)
                                        }
                                    }
                                    .frame(width: 17)
                                    .padding(.vertical, 6)
                                    .background(FastScrollBackdrop())
                                }
                            } else {
                                FastScrollRail(progress: progress, visibleFraction: visibleFraction) { newProgress in
                                    dragProgressFallback = newProgress
                                    let target = Int((newProgress * CGFloat(itemIDs.count - 1)).rounded())
                                    guard target != lastDragTarget else { return }
                                    lastDragTarget = target
                                    scrollProxy.scrollTo(itemIDs[target], anchor: .top)
                                } onDragEnded: {
                                    lastDragTarget = nil
                                }
                                .frame(width: 13)
                                .background(FastScrollBackdrop())
                            }
                        }
                        .padding(.top, 8)
                        .padding(.trailing, 3)
                        .padding(.bottom, indexBottomInset)
                        .opacity(showsIndex ? 1 : 0)
                        .allowsHitTesting(showsIndex)
                        // Touching it keeps it up while you scrub, then it fades after you let go.
                        .simultaneousGesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { _ in
                                    guard !isTouchingIndex else { return }
                                    isTouchingIndex = true
                                    revealIndex()
                                }
                                .onEnded { _ in
                                    isTouchingIndex = false
                                    hideIndexSoon()
                                }
                        )
                    }
                }
                .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).maxY } action: { edge in
                    if abs(edge - viewportBottom) > 0.5 { viewportBottom = edge }
                }
                .onChange(of: scrollToTopSignal) { _, signal in
                    guard signal != nil else { return }
                    scrollToTop(using: scrollProxy)
                }
                .onPreferenceChange(FastScrollMetricsPreferenceKey.self) { newMetrics in
                    let safeContentHeight = newMetrics.contentHeight.isFinite ? max(newMetrics.contentHeight, 0) : 0
                    let safeContentMinY = newMetrics.contentMinY.isFinite ? newMetrics.contentMinY : 0
                    if isAlphabetical {
                        guard metrics.contentHeight != safeContentHeight else { return }
                        metrics = FastScrollMetrics(contentHeight: safeContentHeight)
                    } else {
                        metrics = FastScrollMetrics(contentHeight: safeContentHeight, contentMinY: safeContentMinY)
                        dragProgressFallback = nil
                    }
                }
            }
        }
    }

    private func revealIndex() {
        indexHideGeneration += 1
        guard !isIndexShown else { return }
        withAnimation(.easeOut(duration: 0.18)) { isIndexShown = true }
    }

    /// Fades the index out shortly after the list stops (unless it's being touched by then).
    private func hideIndexSoon() {
        indexHideGeneration += 1
        let generation = indexHideGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            guard generation == indexHideGeneration, !isTouchingIndex, isIndexShown else { return }
            withAnimation(.easeInOut(duration: 0.18)) { isIndexShown = false }
        }
    }

    private func scrollToTop(using scrollProxy: ScrollViewProxy) {
        if let scrollView = underlyingScrollView {
            // The true top, including the space above the first row.
            let top = CGPoint(x: scrollView.contentOffset.x, y: -scrollView.adjustedContentInset.top)
            scrollView.setContentOffset(top, animated: true)
        } else if let first = itemIDs.first {
            withAnimation(.smooth(duration: 0.35)) {
                scrollProxy.scrollTo(first, anchor: .top)
            }
        }
    }

    private func jumpToLetter(_ targetID: ItemID, using scrollProxy: ScrollViewProxy) {
        stopScrollMotion()
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.22)) {
                scrollProxy.scrollTo(targetID, anchor: .top)
            }
        }
    }

    private func stopScrollMotion() {
        guard let underlyingScrollView else { return }
        underlyingScrollView.setContentOffset(underlyingScrollView.contentOffset, animated: false)
        underlyingScrollView.panGestureRecognizer.isEnabled = false
        underlyingScrollView.panGestureRecognizer.isEnabled = true
    }

}

/// Reports whether the list is moving (dragged, gliding or animating) — iOS 18+.
private struct ScrollActivityReporter: ViewModifier {
    let onChange: (Bool) -> Void

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.onScrollPhaseChange { oldPhase, newPhase in
                let wasMoving = oldPhase != .idle
                let isMoving = newPhase != .idle
                if wasMoving != isMoving { onChange(isMoving) }
            }
        } else {
            content
        }
    }
}

/// The narrow frosted strip behind the floating A–Z index / scroll bar, so it reads over artwork.
private struct FastScrollBackdrop: View {
    var body: some View {
        Capsule(style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(Capsule(style: .continuous).fill(HushStyle.paper.opacity(0.35)))
            .overlay(Capsule(style: .continuous).stroke(HushStyle.ink.opacity(0.08), lineWidth: 0.5))
    }
}

/// A ratchet-like tick for each row that passes while you scroll (same rhythm on every tab).
/// Only while your finger is scrolling or the list is gliding — not for jumps made with the A–Z
/// index, which tick on their own. Needs iOS 18.
private struct ScrollTickHaptics: ViewModifier {
    let stepHeight: CGFloat

    @State private var isUserScrolling = false

    func body(content: Content) -> some View {
        if stepHeight > 0 {
            if #available(iOS 18.0, *) {
                content
                    .onScrollPhaseChange { _, phase in
                        isUserScrolling = phase == .interacting || phase == .decelerating
                        // Warm up as soon as a scroll starts so the first row tick isn't late.
                        if phase == .interacting { Haptics.prepare() }
                    }
                    .onScrollGeometryChange(for: Int.self) { geometry in
                        let scrolled = geometry.contentOffset.y + geometry.contentInsets.top
                        return Int((max(scrolled, 0) / stepHeight).rounded(.down))
                    } action: { oldStep, newStep in
                        if isUserScrolling, oldStep != newStep { Haptics.selection() }
                    }
            } else {
                content
            }
        } else {
            content
        }
    }
}

/// Reports how far a scroll view is scrolled from its top. Needs iOS 18; on older versions the header just stays put.
private struct ScrollOffsetReporter: ViewModifier {
    let action: ((CGFloat, CGFloat) -> Void)?

    func body(content: Content) -> some View {
        if let action {
            if #available(iOS 18.0, *) {
                content.onScrollGeometryChange(for: CGFloat.self) { geometry in
                    geometry.contentOffset.y + geometry.contentInsets.top
                } action: { oldValue, newValue in
                    action(oldValue, newValue)
                }
            } else {
                content
            }
        } else {
            content
        }
    }
}

private struct ScrollViewAccess: UIViewRepresentable {
    let onResolve: (UIScrollView) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        context.coordinator.resolveScrollView(from: view, onResolve: onResolve)
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        context.coordinator.resolveScrollView(from: view, onResolve: onResolve)
    }

    final class Coordinator {
        weak var resolvedScrollView: UIScrollView?

        func resolveScrollView(from view: UIView, onResolve: @escaping (UIScrollView) -> Void) {
            DispatchQueue.main.async { [weak self, weak view] in
                guard let self, let view else { return }
                var ancestor = view.superview
                while let current = ancestor {
                    if let scrollView = current as? UIScrollView {
                        guard self.resolvedScrollView !== scrollView else { return }
                        self.resolvedScrollView = scrollView
                        onResolve(scrollView)
                        return
                    }
                    ancestor = current.superview
                }
            }
        }
    }
}

private struct AlphabeticalLetterTarget<ItemID: Hashable>: Identifiable {
    let letter: String
    let itemID: ItemID

    var id: String { letter }
}

private struct AlphabeticalLetterIndex<ItemID: Hashable>: View {
    let targets: [AlphabeticalLetterTarget<ItemID>]
    let onSelect: (ItemID, Bool) -> Void

    @State private var activeIndex: Int?
    @State private var lastDraggedIndex: Int?
    @State private var isScrubbing = false
    @State private var focusGeneration = 0

    var body: some View {
        GeometryReader { geometry in
            let availableHeight = geometry.size.height.isFinite ? max(geometry.size.height, 0) : 0
            let cellHeight = availableHeight / CGFloat(max(targets.count, 1))
            VStack(spacing: 0) {
                ForEach(Array(targets.enumerated()), id: \.element.letter) { index, target in
                    let isActive = activeIndex == index
                    let regularSize = min(12, max(9, cellHeight * 0.52))
                    let activeSize = min(15, max(regularSize + 3, cellHeight * 0.76))
                    Button {
                        isScrubbing = false
                        lastDraggedIndex = nil
                        setActiveIndex(index, isDragging: false)
                        onSelect(target.itemID, false)
                        scheduleFocusReset(for: index)
                    } label: {
                        Text(target.letter)
                            .font(.system(size: isActive ? activeSize : regularSize, weight: .semibold, design: .rounded))
                            .foregroundStyle(isActive ? HushStyle.gold : HushStyle.muted)
                            .frame(maxWidth: .infinity)
                            .frame(height: cellHeight)
                            .background {
                                if isActive {
                                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                                        .fill(HushStyle.gold.opacity(0.20))
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                                .stroke(HushStyle.gold.opacity(0.55), lineWidth: 0.7)
                                        }
                                        .frame(width: 15, height: min(26, max(0, cellHeight - 2)))
                                }
                            }
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Scroll to \(target.letter)")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .simultaneousGesture(
                DragGesture(minimumDistance: 12, coordinateSpace: .local)
                    .onChanged { value in
                        guard !targets.isEmpty, availableHeight > 0 else { return }
                        let position = min(max(value.location.y / availableHeight, 0), 0.999)
                        let index = min(Int(position * CGFloat(targets.count)), targets.count - 1)
                        isScrubbing = true
                        guard index != lastDraggedIndex else { return }
                        lastDraggedIndex = index
                        setActiveIndex(index, isDragging: true)
                        onSelect(targets[index].itemID, true)
                    }
                    .onEnded { _ in
                        isScrubbing = false
                        lastDraggedIndex = nil
                        if let activeIndex { scheduleFocusReset(for: activeIndex) }
                    }
            )
        }
        .accessibilityElement(children: .contain)
        .onChange(of: activeIndex) { _, newValue in
            if newValue != nil { Haptics.selection() }
        }
    }

    private func setActiveIndex(_ index: Int, isDragging: Bool) {
        if isDragging {
            withAnimation(.easeOut(duration: 0.07)) {
                activeIndex = index
            }
        } else {
            withAnimation(.spring(response: 0.20, dampingFraction: 0.72)) {
                activeIndex = index
            }
        }
    }

    private func scheduleFocusReset(for index: Int) {
        focusGeneration += 1
        let generation = focusGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
            guard !isScrubbing, activeIndex == index, focusGeneration == generation else { return }
            withAnimation(.spring(response: 0.32, dampingFraction: 0.76)) {
                activeIndex = nil
            }
        }
    }
}

private struct FastScrollRail: View {
    let progress: CGFloat
    let visibleFraction: CGFloat
    let onDrag: (CGFloat) -> Void
    let onDragEnded: () -> Void

    var body: some View {
        GeometryReader { geometry in
            let safeWidth = geometry.size.width.isFinite ? max(geometry.size.width, 0) : 0
            let safeHeight = geometry.size.height.isFinite ? max(geometry.size.height, 0) : 0
            let safeProgress = progress.isFinite ? min(max(progress, 0), 1) : 0
            let safeVisibleFraction = visibleFraction.isFinite ? min(max(visibleFraction, 0), 1) : 1
            let verticalInset = min(10, safeHeight / 2)
            let trackHeight = max(safeHeight - verticalInset * 2, 1)
            let thumbHeight = min(trackHeight, max(38, trackHeight * safeVisibleFraction))
            let travel = max(trackHeight - thumbHeight, 0)

            ZStack(alignment: .top) {
                Capsule()
                    .fill(HushStyle.line.opacity(0.65))
                    .frame(width: 2, height: trackHeight)

                Capsule()
                    .fill(HushStyle.gold.opacity(0.9))
                    .frame(width: 5, height: thumbHeight)
                    .offset(y: safeProgress * travel)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.vertical, verticalInset)
            .frame(width: safeWidth, height: safeHeight)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard travel > 0 else { return }
                        let position = (value.location.y - verticalInset - thumbHeight / 2) / travel
                        onDrag(min(max(position, 0), 1))
                    }
                    .onEnded { _ in onDragEnded() }
            )
            .accessibilityElement()
            .accessibilityLabel("Fast scroll")
            .accessibilityValue("\(Int((safeProgress * 100).rounded())) percent")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment:
                    onDrag(min(safeProgress + 0.1, 1))
                case .decrement:
                    onDrag(max(safeProgress - 0.1, 0))
                @unknown default:
                    break
                }
            }
        }
    }
}

private struct FastScrollMetrics: Equatable {
    var contentHeight: CGFloat = 0
    var contentMinY: CGFloat = 0
}

private struct FastScrollMetricsPreferenceKey: PreferenceKey {
    static var defaultValue = FastScrollMetrics()

    static func reduce(value: inout FastScrollMetrics, nextValue: () -> FastScrollMetrics) {
        value = nextValue()
    }
}

#Preview {
    let store = MusicLibraryStore()
    ContentView()
        .environmentObject(store)
        .environmentObject(store.playback)
        .environmentObject(store.queue)
}
