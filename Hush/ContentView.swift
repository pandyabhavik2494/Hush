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

    static func albumPlayButton(_ persistentID: UInt64) -> String {
        "album-detail-play-artwork-\(persistentID)"
    }

    static func playlistTrack(_ persistentID: UInt64) -> String {
        "playlist-track-artwork-\(persistentID)"
    }

    static let miniPlayer = "mini-player-artwork"

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
/// pull-to-refresh appears below it.
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
        // A plain inset, not a bar: the header is opaque, so no scroll-edge effect is wanted.
        content.safeAreaInset(edge: .top, spacing: 0) { spacer }
    }
}

private extension View {
    /// See `UnderLibraryHeader`.
    func underLibraryHeader() -> some View {
        modifier(UnderLibraryHeader())
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
    @State private var selectedTab: LibraryTab = .albums
    /// The search field shows under the title row while this is on.
    @State private var isSearching = false
    /// Tabs whose list is scrolled away from the top (the header shows its hairline).
    @State private var scrolledTabs: Set<LibraryTab> = []
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
    @State private var visibleAlbumLetterTargets: [AlphabeticalLetterTarget<UInt64>] = []
    @State private var visibleSongs: [MPMediaItem] = []
    @State private var visibleSongIDs: [UInt64] = []
    @State private var visibleSongLetterTargets: [AlphabeticalLetterTarget<UInt64>] = []
    /// In A–Z order: the first song of each letter, and its letter (for the section letters).
    @State private var songSectionStarts: [UInt64: String] = [:]
    @State private var visiblePlaylists: [MusicPlaylist] = []
    @State private var visiblePlaylistIDs: [UInt64] = []
    @State private var visiblePlaylistLetterTargets: [AlphabeticalLetterTarget<UInt64>] = []
    @State private var visibleArtists: [MusicArtist] = []
    @State private var visibleArtistIDs: [String] = []
    @State private var visibleArtistLetterTargets: [AlphabeticalLetterTarget<String>] = []
    @State private var visibleVideos: [LibraryVideo] = []
    @State private var visibleVideoIDs: [UInt64] = []
    @State private var visibleVideoLetterTargets: [AlphabeticalLetterTarget<UInt64>] = []
    @State private var visibleMovies: [LibraryVideo] = []
    @State private var visibleMovieIDs: [UInt64] = []
    @State private var visibleMovieLetterTargets: [AlphabeticalLetterTarget<UInt64>] = []
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
        visibleAlbumLetterTargets = sort == .alphabetical
            ? AlphabeticalLetterTarget.firstOfEachLetter(ids: visibleAlbumIDs, letters: albums.map(\.sectionLetter))
            : []
        visibleSongs = songs
        visibleSongIDs = songIDs
        let songLetters = sort == .alphabetical ? songIDs.map { songInfo[$0]?.sectionLetter ?? "#" } : []
        visibleSongLetterTargets = AlphabeticalLetterTarget.firstOfEachLetter(ids: songIDs, letters: songLetters)
        var starts: [UInt64: String] = [:]
        var lastLetter: String?
        for (id, letter) in zip(songIDs, songLetters) where letter != lastLetter {
            starts[id] = letter
            lastLetter = letter
        }
        songSectionStarts = starts
        var videos = library.videos.filter { LibrarySearch.matches($0.searchKey, query: query) }
        if sort == .mostPlayed {
            videos = Self.sortedByPlayCount(videos) { $0.item?.playCount ?? 0 }
        }
        visibleVideos = videos
        visibleVideoIDs = videos.map(\.id)
        visibleVideoLetterTargets = sort == .alphabetical
            ? AlphabeticalLetterTarget.firstOfEachLetter(ids: visibleVideoIDs, letters: videos.map(\.sectionLetter))
            : []

        movieGenres = Array(Set(library.movies.compactMap(\.genre)))
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        var movies = library.movies.filter { movie in
            (movieGenre == nil || movie.genre == movieGenre) && LibrarySearch.matches(movie.searchKey, query: query)
        }
        if sort == .mostPlayed {
            movies = Self.sortedByPlayCount(movies) { $0.item?.playCount ?? 0 }
        }
        visibleMovies = movies
        visibleMovieIDs = movies.map(\.id)
        visibleMovieLetterTargets = sort == .alphabetical
            ? AlphabeticalLetterTarget.firstOfEachLetter(ids: visibleMovieIDs, letters: movies.map(\.sectionLetter))
            : []

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
        visibleArtistLetterTargets = artistSort == .alphabetical
            ? AlphabeticalLetterTarget.firstOfEachLetter(ids: visibleArtistIDs, letters: artists.map(\.sectionLetter))
            : []
        let playlists = LibrarySearch.filterByNameThenSongs(
            library.playlists, query: query, nameKey: \.searchKey, songsKey: \.songSearchKey
        )
        visiblePlaylists = playlists
        visiblePlaylistIDs = playlists.map(\.id)
        // Playlists are always A–Z, so they always have letters.
        visiblePlaylistLetterTargets = AlphabeticalLetterTarget.firstOfEachLetter(
            ids: visiblePlaylistIDs, letters: playlists.map(\.sectionLetter)
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
                // An opaque black header over the library: the lists scroll under it and nothing
                // shows through. The pages get the header's measured height as their top inset.
                libraryContent
                    .environment(\.libraryHeaderBottom, libraryHeaderBottom)
                    .overlay(alignment: .top) {
                        VStack(spacing: 0) {
                            header
                            if isSearching { searchField }
                            tabPicker
                        }
                        .background(HushStyle.paper.ignoresSafeArea(edges: .top))
                        .contentShape(Rectangle())
                        // A hairline under the header only once the list has scrolled beneath it.
                        .overlay(alignment: .bottom) {
                            if scrolledTabs.contains(selectedTab) {
                                Rectangle().fill(HushStyle.line).frame(height: 1)
                            }
                        }
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
            .onChange(of: sort) { rebuildVisibleLibrary() }
            .onChange(of: library.libraryRevision) {
                // The chosen genre has left the library: clearing it rebuilds the lists (see the
                // movieGenre onChange), so they aren't rebuilt twice.
                if let genre = movieGenre, !library.movies.contains(where: { $0.genre == genre }) {
                    movieGenre = nil
                } else {
                    rebuildVisibleLibrary()
                }
            }
            .onChange(of: library.favoriteArtistIDs) { rebuildVisibleLibrary() }
            .onChange(of: artistSort) { rebuildVisibleLibrary() }
            .navigationDestination(for: HushRoute.self) { route in
                page(for: route)
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
        .tint(HushStyle.accent)
    }

    /// The album, artist or playlist page a route opens (nothing if it's left the library).
    @ViewBuilder
    private func page(for route: HushRoute) -> some View {
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
        HStack(spacing: 0) {
            Button {
                isAboutPresented = true
            } label: {
                Text("Hush")
                    .font(HushStyle.brandFont(size: 22))
                    .foregroundStyle(HushStyle.ink)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("About Hush")
            Spacer()
            Button {
                withAnimation(.easeOut(duration: 0.2)) { isSearching = true }
            } label: {
                BarIcon(systemName: "magnifyingglass", weight: .regular)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Search")
            optionsMenu
        }
        .frame(height: 44)
        .padding(.leading, 20)
        .padding(.trailing, 10)
    }

    /// Sort, titles and (on Artists) a fresh look for photos, in one menu.
    private var optionsMenu: some View {
        Menu {
            // Playlists are listed A–Z like the Music app, so they have no sort.
            if selectedTab != .playlists {
                Picker("Sort", selection: currentSort) {
                    ForEach(LibrarySort.options(for: selectedTab), id: \.self) { option in
                        Label(option.rawValue, systemImage: option.symbol).tag(option)
                    }
                }
            }
            if selectedTab == .playlists || selectedTab == .albums || selectedTab == .movies {
                Section {
                    Toggle(isOn: Binding(
                        get: { gridTitles.wrappedValue },
                        set: { value in withAnimation(.easeInOut(duration: 0.2)) { gridTitles.wrappedValue = value } }
                    )) {
                        Label("Show Titles", systemImage: "text.below.photo")
                    }
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
            BarIcon(systemName: "line.3.horizontal.decrease", weight: .regular)
        }
        .accessibilityLabel("Sort and view options")
    }

    private var searchField: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(HushStyle.muted)
                QuietTextField(
                    text: $searchText,
                    placeholder: searchPlaceholder,
                    capitalization: .none,
                    returnKeyType: .search,
                    fontSize: 16,
                    placeholderColor: UIColor(HushStyle.muted),
                    focusOnAppear: true
                )
                .accessibilityLabel("Search music library")
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(HushStyle.muted)
                            .frame(width: 28, height: 40)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 40)
            .background(HushStyle.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            Button("Cancel") {
                searchText = ""
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                withAnimation(.easeOut(duration: 0.2)) { isSearching = false }
            }
            .font(.system(size: 16))
            .foregroundStyle(HushStyle.ink)
        }
        .padding(.horizontal, 20)
        .padding(.top, 2)
        .padding(.bottom, 4)
        .transition(.opacity)
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

    /// The six tabs as words in the serif, the one you're on bright. Scrolls sideways; the
    /// current one is kept in view.
    private var tabPicker: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 24) {
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
                                .font(.system(size: 31, weight: .regular, design: .serif))
                                .tracking(-0.3)
                                .foregroundStyle(selectedTab == tab ? HushStyle.ink : HushStyle.tabIdle)
                                .lineLimit(1)
                                .fixedSize()
                                .frame(height: 58)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .id(tab)
                        .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
                    }
                }
                .padding(.horizontal, 20)
            }
            .frame(height: 58)
            .onChange(of: selectedTab) { _, tab in
                withAnimation(.snappy(duration: 0.3)) { proxy.scrollTo(tab, anchor: .center) }
            }
            .onAppear { proxy.scrollTo(selectedTab, anchor: .center) }
        }
        .animation(.easeInOut(duration: 0.2), value: selectedTab)
    }

    /// Reports whether a tab's list has scrolled away from the top (for the header's hairline).
    private func scrollTracker(_ tab: LibraryTab) -> (CGFloat, CGFloat) -> Void {
        { _, offset in
            let scrolled = offset > 1
            guard scrolledTabs.contains(tab) != scrolled else { return }
            if scrolled { scrolledTabs.insert(tab) } else { scrolledTabs.remove(tab) }
        }
    }

    @ViewBuilder
    private var libraryContent: some View {
        if library.authorizationStatus == .denied || library.authorizationStatus == .restricted {
            accessMessage
                .underLibraryHeader()
        } else if library.authorizationStatus == .notDetermined || library.isLoading {
            VStack(spacing: 12) {
                ProgressView().tint(HushStyle.accent)
                Text("Gathering your music")
                    .font(.system(size: 13))
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
        EmptyStateMessage(
            symbol: "heart",
            symbolSize: 30,
            title: "No favorite artists yet",
            message: "Open an artist and tap the heart, or press and hold their picture.",
            messageWidth: 280
        ) {
            Button {
                artistSort = .mostSongs
            } label: {
                Text("Show All Artists")
                    .accentCapsule()
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
            letterTargets: visibleArtistLetterTargets,
            isAlphabetical: artistSort == .alphabetical,
            itemsPerRow: 3,
            estimatedRowHeight: 168,
            estimatedPadding: 36,
            onRefresh: { await library.refreshLibrary() },
            onScrollOffsetChange: scrollTracker(.artists),
            scrollToTopSignal: scrollToTop.signal(for: .artists)
        ) {
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 3),
                alignment: .center,
                spacing: 24
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
                    .contextMenu { artistMenu(artist) }
                    .id(artist.id)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 16)
        }
    }

    /// Long-press menu on an artist: favorite, plus the usual Play Next / Add to Queue.
    @ViewBuilder
    private func artistMenu(_ artist: MusicArtist) -> some View {
        FavoriteArtistButton(library: library, artistID: artist.id)
        QueueActionButtons(library: library) { artist.allSongs }
    }

    /// Music videos from the Music app. Tap one to watch it full screen.
    @ViewBuilder
    private var videosPage: some View {
        if visibleVideos.isEmpty {
            ScrollView(showsIndicators: false) {
                EmptyStateMessage(
                    symbol: searchText.isEmpty ? "play.rectangle" : "magnifyingglass",
                    title: searchText.isEmpty ? "No videos yet" : "No videos found",
                    message: searchText.isEmpty
                        ? "Music videos in the Music app appear here once they're on this iPhone. Pull down to check again."
                        : "Try another video name."
                )
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
            letterTargets: visibleVideoLetterTargets,
            isAlphabetical: sort == .alphabetical,
            itemsPerRow: 2,
            estimatedRowHeight: 106,
            estimatedPadding: 36,
            onRefresh: { await library.refreshLibrary() },
            onScrollOffsetChange: scrollTracker(.videos),
            scrollToTopSignal: scrollToTop.signal(for: .videos)
        ) {
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 2),
                alignment: .leading,
                spacing: 12
            ) {
                ForEach(visibleVideos) { video in
                    Button {
                        play(video)
                    } label: {
                        VideoTile(video: video)
                    }
                    .buttonStyle(TilePressStyle())
                    .id(video.id)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
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
                    let filtered = !searchText.isEmpty || movieGenre != nil
                    EmptyStateMessage(
                        symbol: filtered ? "magnifyingglass" : "film",
                        title: filtered ? "No movies found" : "No movies yet",
                        message: filtered
                            ? "Try another name or genre."
                            : "Movies synced to this iPhone from the TV app on your Mac appear here. Pull down to check again."
                    )
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
            letterTargets: visibleMovieLetterTargets,
            isAlphabetical: sort == .alphabetical,
            itemsPerRow: 3,
            estimatedRowHeight: showMovieTitles ? 236 : 186,
            estimatedPadding: movieGenres.isEmpty ? 36 : 82,
            onRefresh: { await library.refreshLibrary() },
            onScrollOffsetChange: scrollTracker(.movies),
            scrollToTopSignal: scrollToTop.signal(for: .movies)
        ) {
            VStack(alignment: .leading, spacing: 16) {
                if !movieGenres.isEmpty {
                    genreFilter
                }
                // Like the Albums grid: posters close together, names only when the titles toggle is on.
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3),
                    alignment: .leading,
                    spacing: showMovieTitles ? 22 : 12
                ) {
                    ForEach(visibleMovies) { movie in
                        Button {
                            play(movie)
                        } label: {
                            MovieTile(movie: movie, showsTitle: showMovieTitles)
                        }
                        .buttonStyle(TilePressStyle())
                        .id(movie.id)
                    }
                }
                .padding(.horizontal, 20)
            }
            .padding(.top, 12)
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
            .padding(.horizontal, 20)
        }
        .scrollClipDisabled()
    }

    private func genrePill(_ title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            withAnimation(.snappy(duration: 0.25)) { action() }
        } label: {
            Text(title)
                .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? HushStyle.paper : HushStyle.ink.opacity(0.9))
                .padding(.horizontal, 14)
                .frame(height: 32)
                .background(isSelected ? HushStyle.accent : HushStyle.surface, in: Capsule())
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
            letterTargets: visibleAlbumLetterTargets,
            isAlphabetical: sort == .alphabetical,
            itemsPerRow: 2,
            estimatedRowHeight: showGridTitles ? 236 : 188,
            estimatedPadding: 36,
            onRefresh: { await library.refreshLibrary() },
            onScrollOffsetChange: scrollTracker(.albums),
            scrollToTopSignal: scrollToTop.signal(for: .albums)
        ) {
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 2),
                alignment: .leading,
                spacing: showGridTitles ? 22 : 14
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
                    .id(album.id)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 16)
        }
    }

    private var songList: some View {
        FastScrollContainer(
            itemIDs: visibleSongIDs,
            letterTargets: visibleSongLetterTargets,
            isAlphabetical: sort == .alphabetical,
            itemsPerRow: 1,
            estimatedRowHeight: 66,
            estimatedPadding: 25,
            onRefresh: { await library.refreshLibrary() },
            onScrollOffsetChange: scrollTracker(.songs),
            scrollToTopSignal: scrollToTop.signal(for: .songs)
        ) {
            LazyVStack(alignment: .leading, spacing: 0) {
                let currentID = library.currentItem?.persistentID
                ForEach(visibleSongs, id: \.persistentID) { song in
                    VStack(alignment: .leading, spacing: 0) {
                        // In A–Z order, a quiet letter where each new letter starts.
                        if let letter = songSectionStarts[song.persistentID] {
                            Text(letter)
                                .font(.system(size: 15, weight: .regular, design: .serif))
                                .foregroundStyle(HushStyle.muted)
                                .padding(.top, 12)
                                .padding(.bottom, 4)
                                .accessibilityAddTraits(.isHeader)
                        }
                        Button {
                            library.play(song, from: visibleSongs)
                            openPlayer(from: PlayerArtworkTransitionID.librarySong(song.persistentID))
                        } label: {
                            SongRow(
                                item: song,
                                isCurrent: currentID == song.persistentID,
                                artworkNamespace: artworkNamespace
                            )
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity)
                        .queueMenu([song])
                    }
                    .id(song.persistentID)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)
            .padding(.bottom, 16)
        }
    }

    /// Playlists come from the Music app. Edit them there, then pull down here to refresh.
    @ViewBuilder
    private var playlistList: some View {
        let playlists = visiblePlaylists
        if playlists.isEmpty {
            ScrollView(showsIndicators: false) {
                EmptyStateMessage(
                    symbol: searchText.isEmpty ? "music.note.list" : "magnifyingglass",
                    title: searchText.isEmpty ? "No playlists yet" : "No playlists found",
                    message: searchText.isEmpty
                        ? "Make playlists in the Music app, then pull down here to bring them in."
                        : "Try another playlist or song name.",
                    messageWidth: nil
                )
                .padding(28)
                .frame(maxWidth: .infinity, minHeight: 250)
            }
            .scrollDismissesKeyboard(.immediately)
            .refreshable { await library.refreshLibrary() }
        } else {
            // Same cover grid, A–Z index, and spacing as the Albums tab.
            FastScrollContainer(
                itemIDs: visiblePlaylistIDs,
                letterTargets: visiblePlaylistLetterTargets,
                isAlphabetical: true,
                itemsPerRow: 2,
                estimatedRowHeight: showGridTitles ? 236 : 188,
                estimatedPadding: 36,
                onRefresh: { await library.refreshLibrary() },
                onScrollOffsetChange: scrollTracker(.playlists),
                scrollToTopSignal: scrollToTop.signal(for: .playlists)
            ) {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 2),
                    alignment: .leading,
                    spacing: showGridTitles ? 22 : 14
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
                        .id(playlist.id)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
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
                    .foregroundColor(HushStyle.accent)
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
            .accentCapsule()
            .padding(.top, 4)
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyLibraryMessage: some View {
        let isLibraryEmpty = searchText.isEmpty && library.songs.isEmpty
        return EmptyStateMessage(
            symbol: searchText.isEmpty ? "waveform" : "magnifyingglass",
            symbolSize: 32,
            symbolOpacity: 0.8,
            title: searchText.isEmpty ? "A quiet start" : "Nothing found",
            message: isLibraryEmpty
                ? "Songs you buy or add in the Music app appear here once they're downloaded to this iPhone."
                : searchText.isEmpty ? "Nothing here yet." : "Try another song, album, or artist."
        ) {
            if isLibraryEmpty {
                Button("Open Music") {
                    guard let url = URL(string: "music://") else { return }
                    UIApplication.shared.open(url)
                }
                .accentCapsule()
                .padding(.top, 4)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A quiet note in place of an empty list: a light symbol, a line in the serif, a short
/// explanation and, sometimes, a button.
private struct EmptyStateMessage<Action: View>: View {
    let symbol: String
    var symbolSize: CGFloat = 31
    var symbolOpacity: Double = 0.85
    let title: String
    let message: String
    /// Wraps the explanation at this width; nil lets it run the full width.
    var messageWidth: CGFloat? = 290
    let action: Action

    init(
        symbol: String,
        symbolSize: CGFloat = 31,
        symbolOpacity: Double = 0.85,
        title: String,
        message: String,
        messageWidth: CGFloat? = 290,
        @ViewBuilder action: () -> Action = { EmptyView() }
    ) {
        self.symbol = symbol
        self.symbolSize = symbolSize
        self.symbolOpacity = symbolOpacity
        self.title = title
        self.message = message
        self.messageWidth = messageWidth
        self.action = action()
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: symbolSize, weight: .light))
                .foregroundStyle(HushStyle.accent.opacity(symbolOpacity))
            Text(title)
                .font(.system(size: 21, weight: .regular, design: .serif))
                .foregroundStyle(HushStyle.ink)
            if let messageWidth {
                messageText.frame(maxWidth: messageWidth)
            } else {
                messageText
            }
            action
        }
    }

    private var messageText: some View {
        Text(message)
            .font(.system(size: 14))
            .foregroundStyle(HushStyle.muted)
            .multilineTextAlignment(.center)
    }
}

private extension View {
    /// The small filled accent capsule used for the one button in an empty or access message.
    func accentCapsule() -> some View {
        font(.system(size: 14, weight: .semibold))
            .foregroundStyle(HushStyle.paper)
            .padding(.horizontal, 18)
            .padding(.vertical, 11)
            .background(HushStyle.accent, in: Capsule())
    }
}

#Preview {
    let store = MusicLibraryStore()
    ContentView()
        .environmentObject(store)
        .environmentObject(store.playback)
        .environmentObject(store.queue)
}
