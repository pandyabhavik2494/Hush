import Foundation
import AVFAudio
// MediaPlayer predates Swift's thread-safety (Sendable) annotations; this tells the compiler so.
@preconcurrency import MediaPlayer
import MusicKit
import os
import SwiftUI
import UIKit

/// Diagnostics for Console.app and sysdiagnose only; nothing is ever sent anywhere.
let hushLog = Logger(subsystem: "com.hush.player", category: "Hush")

struct MusicAlbum: Identifiable {
    let id: UInt64
    let title: String
    let artist: String
    let items: [MPMediaItem]
    let artworkItem: MPMediaItem?
    /// Folded title + artist, precomputed so search doesn't touch MPMediaItem on every keystroke.
    let searchKey: String
    /// Folded titles and artists of the album's songs, so searching a song finds its album.
    let songSearchKey: String
    let sectionLetter: String

    var totalPlayCount: Int { items.reduce(0) { $0 + $1.playCount } }
    var trackCount: Int { items.count }
}

/// One artist, built from every song credited to them (duets and collaborations count for each
/// singer; the album artist — often the composer on soundtracks — counts too).
struct MusicArtist: Identifiable {
    /// Normalized name ("A.R. Rahman" and "A. R. Rahman" share one id), so each artist gets one tile.
    let id: String
    /// The spelling your library uses most.
    let name: String
    /// Albums with songs credited to this artist, newest first.
    let albums: [ArtistAlbum]
    let artworkItem: MPMediaItem?
    let searchKey: String
    let songSearchKey: String
    let sectionLetter: String

    var songCount: Int { albums.reduce(0) { $0 + $1.songs.count } }
    /// All their songs in page order (album by album).
    var allSongs: [MPMediaItem] { albums.flatMap(\.songs) }
    var totalPlayCount: Int { albums.reduce(0) { total, album in total + album.songs.reduce(0) { $0 + $1.playCount } } }
}

/// An album as it appears on an artist's page: only the songs credited to that artist.
struct ArtistAlbum: Identifiable {
    /// Same id as the library album, so it can open the full album page.
    let id: UInt64
    let title: String
    let year: Int?
    let artworkItem: MPMediaItem?
    let songs: [MPMediaItem]
}

/// A music video or a movie kept in the phone's media library.
struct LibraryVideo: Identifiable {
    let id: UInt64
    let title: String
    /// Nil when the video has no artist (or only "Unknown Artist").
    let artist: String?
    let duration: TimeInterval
    /// The file on this iPhone. Nil when the video is only in the cloud, or is copy-protected.
    let assetURL: URL?
    /// The library entry it came from (nil only in previews).
    let item: MPMediaItem?
    let searchKey: String
    let sectionLetter: String
    /// Movies only: shown in the Movies tab, with a 2:3 poster.
    var isMovie = false
    /// The genre tag, e.g. "Drama" (nil when it has none).
    var genre: String?
    /// Year of release, when the file says.
    var year: Int?
}

/// Precomputed per-song data used by search and the A–Z index.
struct SongInfo {
    let searchKey: String
    let sectionLetter: String
}

extension LibrarySearch {
    /// Titles and artists of a set of songs, folded for search.
    static func songsKey(_ items: [MPMediaItem]) -> String {
        key(items.flatMap { [$0.title, $0.artist] })
    }
}

/// Everything read from the media library in one pass, built off the main thread.
private struct LibrarySnapshot: @unchecked Sendable {
    var songs: [MPMediaItem] = []
    var songInfo: [UInt64: SongInfo] = [:]
    var albums: [MusicAlbum] = []
    var playlists: [MusicPlaylist] = []
    var artists: [MusicArtist] = []
    var videos: [LibraryVideo] = []
    var movies: [LibraryVideo] = []
    /// Fingerprint of what the UI shows (songs, albums, playlists and their contents). iOS reports
    /// "library changed" even for play-count updates; if this is unchanged, nothing is redrawn.
    var signature = 0

    static func load() -> LibrarySnapshot {
        var snapshot = LibrarySnapshot()
        // Videos and movies belong only in their own tabs, so they are kept out of songs, albums,
        // artists and playlists.
        let items = (MPMediaQuery.songs().items ?? []).filter { !$0.isVideo }
        var titled: [(item: MPMediaItem, title: String)] = []
        titled.reserveCapacity(items.count)
        snapshot.songInfo.reserveCapacity(items.count)

        for item in items {
            let title = item.title ?? ""
            let id = item.persistentID
            snapshot.songInfo[id] = SongInfo(
                searchKey: LibrarySearch.key([item.title, item.albumTitle, item.artist]),
                sectionLetter: LibraryAlphabet.section(for: title)
            )
            titled.append((item, title))
        }
        titled.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        snapshot.songs = titled.map(\.item)

        let collections = MPMediaQuery.albums().collections ?? []
        var albums: [MusicAlbum] = collections.compactMap { collection in
            let tracks = collection.items.filter { !$0.isVideo }.sorted(by: Self.trackOrder)
            guard let first = tracks.first else { return nil }
            let title = first.albumTitle ?? "Unknown Album"
            let artist = first.albumArtist ?? first.artist ?? "Unknown Artist"
            let albumID = first.albumPersistentID
            return MusicAlbum(
                id: albumID != 0 ? albumID : first.persistentID,
                title: title,
                artist: artist,
                items: tracks,
                artworkItem: tracks.first(where: { $0.artwork != nil }) ?? tracks.first,
                searchKey: LibrarySearch.key([title, artist]),
                songSearchKey: LibrarySearch.songsKey(tracks),
                sectionLetter: LibraryAlphabet.section(for: title)
            )
        }
        albums.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        snapshot.albums = albums
        snapshot.playlists = Self.loadPlaylists()
        snapshot.artists = Self.buildArtists(from: albums)
        snapshot.videos = Self.loadVideos()
        snapshot.movies = Self.loadMovies()
        snapshot.signature = Self.signature(of: snapshot)
        return snapshot
    }

    /// Music videos (and home videos) kept in the Music app, A–Z. The songs, albums and playlists
    /// above filter videos out, so they only ever show up here.
    private static func loadVideos() -> [LibraryVideo] {
        var seen = Set<UInt64>()
        var videos: [LibraryVideo] = []
        for type in [MPMediaType.musicVideo, MPMediaType.homeVideo] {
            let query = MPMediaQuery()
            query.addFilterPredicate(
                MPMediaPropertyPredicate(value: type.rawValue, forProperty: MPMediaItemPropertyMediaType)
            )
            // Movies have a tab of their own.
            for item in query.items ?? []
            where !item.mediaType.contains(.movie) && seen.insert(item.persistentID).inserted {
                let rawTitle = (item.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let title = rawTitle.isEmpty ? "Untitled Video" : rawTitle
                let rawArtist = (item.artist ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let artist = rawArtist.isEmpty || rawArtist.caseInsensitiveCompare("Unknown Artist") == .orderedSame
                    ? nil : rawArtist
                videos.append(LibraryVideo(
                    id: item.persistentID,
                    title: title,
                    artist: artist,
                    duration: item.playbackDuration,
                    assetURL: item.assetURL,
                    item: item,
                    searchKey: LibrarySearch.key([title, artist]),
                    sectionLetter: LibraryAlphabet.section(for: title)
                ))
            }
        }
        videos.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        return videos
    }

    /// Movies in the phone's library (synced from the Mac's TV app), A–Z. Only the Movies tab shows them.
    private static func loadMovies() -> [LibraryVideo] {
        let query = MPMediaQuery()
        query.addFilterPredicate(
            MPMediaPropertyPredicate(value: MPMediaType.movie.rawValue, forProperty: MPMediaItemPropertyMediaType)
        )
        var movies: [LibraryVideo] = (query.items ?? []).map { item in
            let rawTitle = (item.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let title = rawTitle.isEmpty ? "Untitled Movie" : rawTitle
            let rawGenre = (item.genre ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let genre = rawGenre.isEmpty ? nil : rawGenre
            let year = item.releaseDate.map { Calendar.current.component(.year, from: $0) }
            return LibraryVideo(
                id: item.persistentID,
                title: title,
                artist: nil,
                duration: item.playbackDuration,
                assetURL: item.assetURL,
                item: item,
                searchKey: LibrarySearch.key([title, genre]),
                sectionLetter: LibraryAlphabet.section(for: title),
                isMovie: true,
                genre: genre,
                year: year
            )
        }
        movies.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        return movies
    }

    private static func signature(of snapshot: LibrarySnapshot) -> Int {
        var hasher = Hasher()
        hasher.combine(snapshot.songs.count)
        for item in snapshot.songs { hasher.combine(item.persistentID) }
        for album in snapshot.albums {
            hasher.combine(album.id)
            hasher.combine(album.title)
            hasher.combine(album.items.count)
        }
        for playlist in snapshot.playlists {
            hasher.combine(playlist.id)
            hasher.combine(playlist.name)
            for item in playlist.items { hasher.combine(item.persistentID) }
        }
        for video in snapshot.videos + snapshot.movies {
            hasher.combine(video.id)
            hasher.combine(video.title)
            // A video that has just finished downloading becomes playable: redraw for that too.
            hasher.combine(video.assetURL != nil)
            hasher.combine(video.genre)
        }
        return hasher.finalize()
    }

    /// One entry per artist across the whole library, from each song's artist credit plus its album
    /// artist, with collaborations split into individual names.
    private static func buildArtists(from albums: [MusicAlbum]) -> [MusicArtist] {
        struct Builder {
            var spellings: [String: Int] = [:]
            var albumSongs: [UInt64: [MPMediaItem]] = [:]
            var albumOrder: [UInt64] = []
        }
        var builders: [String: Builder] = [:]
        let albumsByID = Dictionary(albums.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        for album in albums {
            for item in album.items {
                var credited = ArtistCredits.names(in: item.artist)
                credited += ArtistCredits.names(in: item.albumArtist)
                var seenForSong = Set<String>()
                for name in credited {
                    let key = ArtistCredits.key(for: name)
                    guard seenForSong.insert(key).inserted else { continue }
                    var builder = builders[key] ?? Builder()
                    builder.spellings[name, default: 0] += 1
                    if builder.albumSongs[album.id] == nil { builder.albumOrder.append(album.id) }
                    builder.albumSongs[album.id, default: []].append(item)
                    builders[key] = builder
                }
            }
        }

        var artists: [MusicArtist] = builders.compactMap { key, builder in
            guard let name = ArtistCredits.displayName(forKey: key) ?? builder.spellings.max(by: { $0.value < $1.value || ($0.value == $1.value && $0.key > $1.key) })?.key
            else { return nil }
            var artistAlbums: [ArtistAlbum] = builder.albumOrder.compactMap { albumID in
                guard let album = albumsByID[albumID], let songs = builder.albumSongs[albumID] else { return nil }
                let year = album.items.lazy.compactMap(\.releaseDate).first.map { Calendar.current.component(.year, from: $0) }
                return ArtistAlbum(id: albumID, title: album.title, year: year, artworkItem: album.artworkItem, songs: songs)
            }
            // Newest first; albums without a year go last, A–Z.
            artistAlbums.sort { lhs, rhs in
                switch (lhs.year, rhs.year) {
                case let (l?, r?) where l != r: return l > r
                case (_?, nil): return true
                case (nil, _?): return false
                default: return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
                }
            }
            // Tile picture: the cover of the album with the most of their songs.
            let featured = artistAlbums.max { $0.songs.count < $1.songs.count }
            let songs = artistAlbums.flatMap(\.songs)
            return MusicArtist(
                id: key,
                name: name,
                albums: artistAlbums,
                artworkItem: featured?.artworkItem,
                searchKey: LibrarySearch.key([name]),
                songSearchKey: LibrarySearch.songsKey(songs),
                sectionLetter: LibraryAlphabet.section(for: name)
            )
        }
        artists.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return artists
    }

    private static func loadPlaylists() -> [MusicPlaylist] {
        let collections = MPMediaQuery.playlists().collections ?? []
        var playlists: [MusicPlaylist] = collections.compactMap { collection in
            guard let playlist = collection as? MPMediaPlaylist else { return nil }
            // Folders show up as playlists containing every child playlist's songs; skip them.
            if (playlist.value(forProperty: "isFolder") as? NSNumber)?.boolValue == true { return nil }
            let name = playlist.name ?? "Untitled Playlist"
            let songs = playlist.items.filter { !$0.isVideo }
            return MusicPlaylist(
                id: playlist.persistentID,
                name: name,
                items: songs,
                artworkItems: Self.coverItems(from: songs),
                searchKey: LibrarySearch.key([name]),
                songSearchKey: LibrarySearch.songsKey(songs),
                sectionLetter: LibraryAlphabet.section(for: name)
            )
        }
        playlists.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return playlists
    }

    private static func coverItems(from items: [MPMediaItem]) -> [MPMediaItem] {
        var seenAlbums = Set<UInt64>()
        var picked: [MPMediaItem] = []
        for item in items where item.artwork != nil {
            guard seenAlbums.insert(item.albumPersistentID).inserted else { continue }
            picked.append(item)
            if picked.count == 4 { return picked }
        }
        // Fewer than four distinct covers: a single cover looks better than a partial grid.
        return picked.isEmpty ? Array(items.prefix(1)) : Array(picked.prefix(1))
    }

    private static func trackOrder(_ lhs: MPMediaItem, _ rhs: MPMediaItem) -> Bool {
        if lhs.discNumber != rhs.discNumber { return lhs.discNumber < rhs.discNumber }
        return lhs.albumTrackNumber < rhs.albumTrackNumber
    }
}

/// A playlist from the Music app. Read-only in Hush: edit playlists in Apple Music, then pull to refresh.
struct MusicPlaylist: Identifiable {
    let id: UInt64
    let name: String
    let items: [MPMediaItem]
    /// Up to four songs from different albums, for the cover mosaic.
    let artworkItems: [MPMediaItem]
    let searchKey: String
    /// Folded titles and artists of the playlist's songs, so searching a song finds the playlist.
    let songSearchKey: String
    let sectionLetter: String

    var trackCount: Int { items.count }
}

/// Hush's haptic vocabulary. A click always means something happened to what you hear or keep:
/// starting music, play/pause, skips, seeking, favorites, queue edits, shuffle/repeat, closing
/// the player (and the swipe-to-close threshold), plus the ticks while scrolling or scrubbing the
/// A–Z index. Navigation — opening pages or the player, switching tabs, sorting, search — stays
/// silent, so the clicks keep their meaning.
@MainActor
enum Haptics {
    // "Rigid" is the sharpest, shortest click the Taptic Engine makes — crisp rather than thuddy.
    // One generator per strength so each stays warmed up independently.
    private static let playClick = UIImpactFeedbackGenerator(style: .rigid)
    private static let tapClick = UIImpactFeedbackGenerator(style: .rigid)
    private static let tickClick = UIImpactFeedbackGenerator(style: .rigid)

    /// Play/pause and starting music: the strongest click.
    static func play() {
        playClick.impactOccurred(intensity: 0.65)
        playClick.prepare()
    }
    /// Skip, seek, favorites, closing the player.
    static func tap() {
        tapClick.impactOccurred(intensity: 0.55)
        tapClick.prepare()
    }
    /// Shuffle/repeat, queue edits, and the ticks while scrolling or scrubbing the A–Z index.
    static func selection() {
        tickClick.impactOccurred(intensity: 0.45)
        tickClick.prepare()
    }

    /// Wakes the Taptic Engine just before a haptic is likely (finger down on a button, scroll
    /// starting), so the click lands with no delay.
    static func prepare() {
        playClick.prepare()
        tapClick.prepare()
        tickClick.prepare()
    }
}

/// One slot in the play queue. Has its own identity so the same song can appear twice and so
/// list animations (move / remove) track the right row.
struct QueueEntry: Identifiable {
    let id = UUID()
    let item: MPMediaItem
    /// Position in the album/playlist/list it came from; nil for songs you added yourself.
    let sourceIndex: Int?
}

/// The play queue as shown in Up Next. Its own object (like PlaybackStatus) so queue edits only
/// redraw the queue screen, never the library.
@MainActor
final class QueueModel: ObservableObject {
    @Published fileprivate(set) var entries: [QueueEntry] = []
    @Published fileprivate(set) var currentIndex = 0
    /// Short confirmation ("Playing Next", "Added to Queue") shown briefly after adding songs.
    @Published fileprivate(set) var toast: String?
    private var toastTask: Task<Void, Never>?

    var nowPlaying: QueueEntry? {
        entries.indices.contains(currentIndex) ? entries[currentIndex] : nil
    }

    var upNext: [QueueEntry] {
        guard currentIndex + 1 < entries.count else { return [] }
        return Array(entries[(currentIndex + 1)...])
    }

    fileprivate func showToast(_ message: String) {
        toastTask?.cancel()
        AccessibilityNotification.Announcement(message).post()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { toast = message }
        toastTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.25)) { self?.toast = nil }
        }
    }
}

/// Play/pause, shuffle and repeat live in their own tiny object so tapping play only redraws the
/// player controls — not every screen that shows the library.
@MainActor
final class PlaybackStatus: ObservableObject {
    @Published fileprivate(set) var isPlaying = false
    @Published fileprivate(set) var shuffleMode = MPMusicShuffleMode.default
    @Published fileprivate(set) var repeatMode = MPMusicRepeatMode.default
}

@MainActor
final class MusicLibraryStore: ObservableObject {
    /// All songs, sorted A–Z by title.
    @Published private(set) var songs: [MPMediaItem] = []
    /// All albums, sorted A–Z by title.
    @Published private(set) var albums: [MusicAlbum] = []
    /// Bumped whenever a new library snapshot is applied, so views can rebuild cached lists.
    @Published private(set) var libraryRevision = 0
    private(set) var songInfo: [UInt64: SongInfo] = [:]
    /// Playlists mirrored from the Music app, sorted A–Z.
    @Published private(set) var playlists: [MusicPlaylist] = []
    /// One entry per artist, sorted A–Z.
    @Published private(set) var artists: [MusicArtist] = []
    /// Music videos from the Music app, A–Z.
    @Published private(set) var videos: [LibraryVideo] = []
    /// Movies from the phone's library, A–Z.
    @Published private(set) var movies: [LibraryVideo] = []
    /// Artists you've marked as favorites (their normalized ids), remembered between launches.
    @Published private(set) var favoriteArtistIDs: Set<String> = FavoriteArtists.load()

    func isFavorite(artistID: String) -> Bool {
        favoriteArtistIDs.contains(artistID)
    }

    /// Adds or removes an artist from your favorites (shown first on the Artists tab).
    func toggleFavorite(artistID: String) {
        if favoriteArtistIDs.contains(artistID) {
            favoriteArtistIDs.remove(artistID)
        } else {
            favoriteArtistIDs.insert(artistID)
        }
        FavoriteArtists.save(favoriteArtistIDs)
        Haptics.tap()
    }
    /// Playlist cover art from the Music app (custom or generated), keyed by normalized playlist name.
    /// MediaPlayer doesn't expose playlist artwork, so this comes from MusicKit.
    @Published private(set) var playlistArtwork: [String: Artwork] = [:]
    @Published private(set) var authorizationStatus = MPMediaLibrary.authorizationStatus()
    @Published private(set) var currentItem: MPMediaItem?
    let playback = PlaybackStatus()
    let queue = QueueModel()
    /// Mirrors `playback`; setting only publishes when the value actually changes.
    private(set) var isPlaying: Bool {
        get { playback.isPlaying }
        set { if playback.isPlaying != newValue { playback.isPlaying = newValue } }
    }
    @Published private(set) var isLoading = false
    private(set) var shuffleMode: MPMusicShuffleMode {
        get { playback.shuffleMode }
        set { if playback.shuffleMode != newValue { playback.shuffleMode = newValue } }
    }
    private(set) var repeatMode: MPMusicRepeatMode {
        get { playback.repeatMode }
        set { if playback.repeatMode != newValue { playback.repeatMode = newValue } }
    }
    @Published private(set) var nowPlayingPlaylistID: UInt64?
    /// The album, artist or playlist the queue was started from (nil: Songs tab or search).
    @Published private(set) var playbackSource: PlaybackSource?

    /// The library's artists named in a credit like "Arijit Singh & Shreya Ghoshal", in credit order
    /// (spelling variants and duos resolve the same way as the Artists tab).
    func creditedArtists(in credit: String?) -> [MusicArtist] {
        var seen = Set<String>()
        return ArtistCredits.names(in: credit).compactMap { name -> MusicArtist? in
            let key = ArtistCredits.key(for: name)
            guard seen.insert(key).inserted else { return nil }
            return artists.first { $0.id == key }
        }
    }

    /// The library album a song belongs to (by album id, then by the album's songs, then by name).
    func album(for item: MPMediaItem?) -> MusicAlbum? {
        guard let item else { return nil }
        let albumID = item.albumPersistentID
        if albumID != 0, let album = albums.first(where: { $0.id == albumID }) { return album }
        if let album = albums.first(where: { album in album.items.contains { $0.persistentID == item.persistentID } }) {
            return album
        }
        guard let title = item.albumTitle, !title.isEmpty else { return nil }
        let artist = item.albumArtist ?? item.artist
        return albums.first { $0.title == title && (artist == nil || $0.artist == artist) }
            ?? albums.first { $0.title == title }
    }

    /// Stops the music and puts the mini player away (swipe it down). The queue is forgotten, so a
    /// relaunch starts fresh too. Playing anything — here, or from the Lock Screen — brings it back.
    func closePlayer() {
        Haptics.tap()
        isSessionClosed = true
        playbackStartGeneration += 1 // cancels a start that's still waiting for the audio session
        pendingItem = nil
        pendingIsPlaying = nil
        isPlaying = false
        currentItem = nil
        nowPlayingPlaylistID = nil
        playbackSource = nil
        queue.entries = []
        queue.currentIndex = 0
        UserDefaults.standard.removeObject(forKey: Self.sessionDefaultsKey)
        // stop() is a blocking call: run it a frame later so the mini player slides away first.
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 16_000_000)
            self?.player.stop()
        }
    }

    /// "Album" / "Artist" / "Playlist" and its name, or nil if it's no longer in the library.
    func title(for source: PlaybackSource) -> (kind: String, name: String)? {
        switch source {
        case .album(let id):
            return albums.first { $0.id == id }.map { (kind: "Album", name: $0.title) }
        case .artist(let id):
            return artists.first { $0.id == id }.map { (kind: "Artist", name: $0.name) }
        case .playlist(let id):
            return playlists.first { $0.id == id }.map { (kind: "Playlist", name: $0.name) }
        }
    }

    var nowPlayingPlaylist: MusicPlaylist? {
        guard let nowPlayingPlaylistID else { return nil }
        return playlists.first { $0.id == nowPlayingPlaylistID }
    }

    var currentPlaybackTime: TimeInterval {
        let time = player.currentPlaybackTime
        return time.isFinite ? max(time, 0) : 0
    }

    // Keep playback owned by Hush, so system controls return to Hush and stop with the app.
    private let player = MPMusicPlayerController.applicationQueuePlayer
    private let mediaLibrary = MPMediaLibrary.default()
    private var libraryChangeObserver: NSObjectProtocol?
    private var libraryRefreshTask: Task<Void, Never>?
    private var playbackStartGeneration = 0
    private var libraryLoadGeneration = 0
    private var libraryLoadTask: Task<Void, Never>?
    private var isAudioSessionCategoryConfigured = false
    // The system player reports changes a moment late. After a tap, Hush shows the expected
    // song / play state right away and ignores stale reports until the player catches up.
    private var pendingItem: (id: UInt64, until: Date)?
    private var pendingIsPlaying: (value: Bool, until: Date)?
    private var pendingResyncTask: Task<Void, Never>?
    private var librarySignature: Int?
    private static let shuffleDefaultsKey = "hush.shuffleEnabled"
    private static let sessionDefaultsKey = "hush.lastSession.v1"
    private var hasAttemptedSessionRestore = false
    /// True after you swipe the mini player away: Hush has stopped and forgotten the queue, and
    /// ignores the (stopped) system player until music plays again.
    private var isSessionClosed = false

    init() {
        let savedShuffle = UserDefaults.standard.object(forKey: Self.shuffleDefaultsKey) as? Bool ?? true
        // Hush shuffles the queue itself so Up Next always shows the real upcoming order
        // (iOS doesn't let apps see its own shuffled order). The system player stays unshuffled.
        player.shuffleMode = .off
        shuffleMode = savedShuffle ? .songs : .off
        observePlayer()
        syncPlayback()
        if player.nowPlayingItem != nil { refreshQueueFromSystem() }
        if authorizationStatus == .authorized {
            observeLibraryChanges()
            loadLibrary()
        }
    }

    /// Called whenever the app comes back to the foreground.
    func handleBecameActive() {
        // Pick up a permission change made in Settings (no relaunch needed).
        let status = MPMediaLibrary.authorizationStatus()
        if status != authorizationStatus {
            authorizationStatus = status
            if status == .authorized {
                observeLibraryChanges()
                loadLibrary()
            }
        }
        // Catch up with anything changed from the Lock Screen / Control Center while away.
        syncPlayback()
        if !isSessionClosed, queue.entries.isEmpty, player.nowPlayingItem != nil { refreshQueueFromSystem() }
        Haptics.prepare()
    }

    func requestAccess() {
        guard authorizationStatus == .notDetermined else {
            if authorizationStatus == .authorized && songs.isEmpty && !isLoading { loadLibrary() }
            return
        }
        MPMediaLibrary.requestAuthorization { [weak self] status in
            Task { @MainActor in
                guard let self else { return }
                self.authorizationStatus = status
                if status == .authorized {
                    self.observeLibraryChanges()
                    self.loadLibrary()
                }
            }
        }
    }

    /// Reads the media library on a background thread so large libraries don't freeze the UI.
    func loadLibrary() {
        guard authorizationStatus == .authorized else { return }
        libraryLoadGeneration += 1
        let generation = libraryLoadGeneration
        if songs.isEmpty { isLoading = true }
        libraryLoadTask = Task { [weak self] in
            // Read the library and the playlist covers at the same time, then show them together,
            // so playlists never flash their album-mosaic fallback before the real cover arrives.
            async let snapshotResult = Task.detached(priority: .userInitiated) {
                LibrarySnapshot.load()
            }.value
            async let artworkResult = MusicLibraryStore.fetchPlaylistArtwork()
            let (snapshot, artwork) = await (snapshotResult, artworkResult)
            guard let self, generation == self.libraryLoadGeneration else { return }
            self.apply(snapshot, playlistArtwork: artwork)
        }
    }

    /// Pull to refresh: re-reads the library, and looks again for any artist photos still missing
    /// (saved photos are kept; new artists get theirs fetched and saved).
    func refreshLibrary() async {
        guard authorizationStatus == .authorized else { return }
        await ArtistPhotoService.shared.forgetMisses()
        loadLibrary()
        await libraryLoadTask?.value
        let photoRequests = artists.map { (key: $0.id, name: $0.name) }
        await ArtistPhotoService.shared.preload(photoRequests)
    }

    private func apply(_ snapshot: LibrarySnapshot, playlistArtwork artwork: [String: Artwork]?) {
        // Keep the previous covers if this fetch failed, rather than falling back to mosaics.
        if let artwork, artwork != playlistArtwork { playlistArtwork = artwork }
        // Nothing the UI shows has changed (e.g. only play counts moved): don't redraw the library.
        if snapshot.signature == librarySignature, !songs.isEmpty || snapshot.songs.isEmpty {
            if isLoading { isLoading = false }
            return
        }
        librarySignature = snapshot.signature
        songInfo = snapshot.songInfo
        songs = snapshot.songs
        albums = snapshot.albums
        playlists = snapshot.playlists
        artists = snapshot.artists
        videos = snapshot.videos
        movies = snapshot.movies
        // Start fetching artist photos now, in the background, so the Artists tab is ready.
        let photoRequests = snapshot.artists.map { (key: $0.id, name: $0.name) }
        Task.detached(priority: .utility) {
            await ArtistPhotoService.shared.preload(photoRequests)
        }
        if let nowPlayingPlaylistID, !playlists.contains(where: { $0.id == nowPlayingPlaylistID }) {
            self.nowPlayingPlaylistID = nil
        }
        if let playbackSource, title(for: playbackSource) == nil {
            self.playbackSource = nil
        }
        libraryRevision &+= 1
        isLoading = false
        restoreSessionIfNeeded()
    }

    // MARK: - Resume where you left off

    private struct SavedSession: Codable {
        var songIDs: [UInt64]
        /// Original list positions (-1 = added by you), so un-shuffling still works after relaunch.
        var sourceIndexes: [Int]
        var currentIndex: Int
        var playbackTime: TimeInterval
        var playlistID: UInt64?
        /// Added later; older saved sessions simply don't have it.
        var source: PlaybackSource?
    }

    /// Saves the queue and position (called when Hush goes to the background).
    func saveSession() {
        guard !queue.entries.isEmpty, currentItem != nil else {
            UserDefaults.standard.removeObject(forKey: Self.sessionDefaultsKey)
            return
        }
        let session = SavedSession(
            songIDs: queue.entries.map(\.item.persistentID),
            sourceIndexes: queue.entries.map { $0.sourceIndex ?? -1 },
            currentIndex: queue.currentIndex,
            playbackTime: currentPlaybackTime,
            playlistID: nowPlayingPlaylistID,
            source: playbackSource
        )
        if let data = try? JSONEncoder().encode(session) {
            UserDefaults.standard.set(data, forKey: Self.sessionDefaultsKey)
        }
    }

    /// After a relaunch, puts the last queue back in the player — paused, at the same spot — so the
    /// mini player shows your song and one tap resumes it.
    private func restoreSessionIfNeeded() {
        guard !hasAttemptedSessionRestore else { return }
        hasAttemptedSessionRestore = true
        guard player.nowPlayingItem == nil, currentItem == nil,
              let data = UserDefaults.standard.data(forKey: Self.sessionDefaultsKey),
              let session = try? JSONDecoder().decode(SavedSession.self, from: data) else { return }

        let itemsByID = Dictionary(songs.map { ($0.persistentID, $0) }, uniquingKeysWith: { first, _ in first })
        var entries: [QueueEntry] = []
        var currentIndex = 0
        for (offset, id) in session.songIDs.enumerated() {
            guard let item = itemsByID[id] else { continue } // song removed from the library since
            if offset == session.currentIndex { currentIndex = entries.count }
            let source = offset < session.sourceIndexes.count ? session.sourceIndexes[offset] : -1
            entries.append(QueueEntry(item: item, sourceIndex: source >= 0 ? source : nil))
        }
        guard entries.indices.contains(currentIndex) else { return }
        let item = entries[currentIndex].item
        if let playlistID = session.playlistID, playlists.contains(where: { $0.id == playlistID }) {
            nowPlayingPlaylistID = playlistID
        }
        if let source = session.source ?? session.playlistID.map(PlaybackSource.playlist),
           title(for: source) != nil {
            playbackSource = source
        }
        queue.entries = entries
        queue.currentIndex = currentIndex
        currentItem = item
        isPlaying = false
        player.setQueue(with: MPMediaItemCollection(items: entries.map(\.item)))
        player.nowPlayingItem = item
        let resumeTime = session.playbackTime
        let resumeItemID = item.persistentID // pass the ID (a plain number), not the song object, across threads
        player.prepareToPlay { [weak self] _ in
            Task { @MainActor in
                guard let self, self.currentItem?.persistentID == resumeItemID, resumeTime > 1 else { return }
                self.player.currentPlaybackTime = resumeTime
            }
        }
    }

    func artwork(for playlist: MusicPlaylist) -> Artwork? {
        playlistArtwork[LibrarySearch.normalizedQuery(playlist.name)]
    }

    /// MusicKit and MediaPlayer use different playlist IDs, so artwork is matched by name.
    /// Names shared by more than one playlist are skipped (they fall back to the album mosaic).
    /// Returns nil if MusicKit isn't available or the request fails.
    private nonisolated static func fetchPlaylistArtwork() async -> [String: Artwork]? {
        guard await MusicAuthorization.request() == .authorized else { return nil }
        do {
            var batch: MusicItemCollection<MusicKit.Playlist>? = try await MusicLibraryRequest<MusicKit.Playlist>().response().items
            var artworkByName: [String: Artwork] = [:]
            var nameCounts: [String: Int] = [:]
            while let current = batch {
                for playlist in current {
                    let key = LibrarySearch.normalizedQuery(playlist.name)
                    nameCounts[key, default: 0] += 1
                    if let artwork = playlist.artwork { artworkByName[key] = artwork }
                }
                if current.hasNextBatch {
                    batch = try await current.nextBatch()
                } else {
                    batch = nil
                }
            }
            return artworkByName.filter { nameCounts[$0.key] == 1 }
        } catch {
            hushLog.error("Couldn't load playlist artwork: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    /// Turns shuffle on and starts from a random song, like Apple Music's Shuffle button.
    func playShuffled(_ items: [MPMediaItem], playlistID: UInt64? = nil, source playingFrom: PlaybackSource? = nil) {
        guard let start = items.randomElement() else { return }
        setShuffleFlag(true)
        play(start, from: items, playlistID: playlistID, source: playingFrom)
    }

    func play(
        _ item: MPMediaItem,
        from items: [MPMediaItem]? = nil,
        playlistID: UInt64? = nil,
        source playingFrom: PlaybackSource? = nil
    ) {
        let source = items ?? songs
        guard !source.isEmpty else { return }
        Haptics.play()
        isSessionClosed = false
        if nowPlayingPlaylistID != playlistID { nowPlayingPlaylistID = playlistID }
        let newSource = playingFrom ?? playlistID.map(PlaybackSource.playlist)
        if playbackSource != newSource { playbackSource = newSource }
        // Show the tapped song immediately, before the system player confirms it.
        currentItem = item
        isPlaying = true
        expect(itemID: item.persistentID, isPlaying: true)

        // Build the queue: list order, or (shuffle on) the tapped song first and the rest shuffled.
        let sourceEntries = source.enumerated().map { QueueEntry(item: $0.element, sourceIndex: $0.offset) }
        let tappedIndex = source.firstIndex { $0.persistentID == item.persistentID } ?? 0
        let ordered: [QueueEntry]
        let startIndex: Int
        if shuffleMode == .songs {
            var rest = sourceEntries
            let first = rest.remove(at: tappedIndex)
            ordered = [first] + rest.shuffled()
            startIndex = 0
        } else {
            ordered = sourceEntries
            startIndex = tappedIndex
        }
        queue.entries = ordered
        queue.currentIndex = startIndex

        player.setQueue(with: MPMediaItemCollection(items: ordered.map(\.item)))
        player.nowPlayingItem = item
        syncPlayback()
        startPlaybackWhenAudioSessionIsReady()
    }

    /// Stops the music before a video starts, so the two never play over each other.
    func pauseForVideo() {
        guard isPlaying else { return }
        isPlaying = false
        expect(isPlaying: false)
        playbackStartGeneration += 1
        player.pause()
    }

    func togglePlayback() {
        // Decide from what's on screen (it's updated instantly), so the button flips on tap.
        Haptics.play()
        if isPlaying {
            isPlaying = false
            expect(isPlaying: false)
            playbackStartGeneration += 1
            let generation = playbackStartGeneration
            // The system player's pause() is a blocking call. Run it one frame later so the
            // button redraws first; skip it if the user tapped play again in the meantime.
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 16_000_000)
                guard let self, generation == self.playbackStartGeneration else { return }
                self.player.pause()
            }
        } else if currentItem != nil || player.nowPlayingItem != nil {
            isPlaying = true
            expect(isPlaying: true)
            startPlaybackWhenAudioSessionIsReady()
        } else if let first = songs.first {
            play(first)
        }
        // No immediate re-read of the player here: that's another blocking call, and the
        // player's change notifications keep everything in sync right after.
    }

    /// Remember what the UI is already showing, so late reports from the player don't flip it back.
    private func expect(itemID: UInt64? = nil, isPlaying expectedPlaying: Bool) {
        let deadline = Date().addingTimeInterval(2)
        if let itemID { pendingItem = (id: itemID, until: deadline) }
        pendingIsPlaying = (value: expectedPlaying, until: deadline)
        // Once the grace period ends, re-read the real state (in case playback failed to start).
        pendingResyncTask?.cancel()
        pendingResyncTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_100_000_000)
            guard !Task.isCancelled else { return }
            self?.syncPlayback()
        }
    }

    func toggleShuffle() {
        Haptics.selection()
        let enabled = shuffleMode != .songs
        setShuffleFlag(enabled)
        reorderUpNext(shuffled: enabled)
    }

    private func setShuffleFlag(_ enabled: Bool) {
        shuffleMode = enabled ? .songs : .off
        UserDefaults.standard.set(enabled, forKey: Self.shuffleDefaultsKey)
    }

    // MARK: - Queue editing (Up Next)
    //
    // Every edit updates the on-screen queue instantly, then is applied to the system player's
    // queue in one transaction (so the current song never stops), then reconciled against what
    // the player reports back.

    /// Shuffle on: randomize Up Next. Shuffle off: restore the original order, keeping songs you
    /// added yourself at the front (like Apple Music).
    private func reorderUpNext(shuffled: Bool) {
        let upNext = queue.upNext
        guard upNext.count > 1, let anchor = currentSlot() else { return }
        let reordered: [QueueEntry]
        if shuffled {
            reordered = upNext.shuffled()
        } else {
            reordered = upNext.enumerated()
                .sorted { lhs, rhs in
                    let l = lhs.element.sourceIndex ?? -1
                    let r = rhs.element.sourceIndex ?? -1
                    return l != r ? l < r : lhs.offset < rhs.offset
                }
                .map(\.element)
        }
        let removals = upNextSlots()
        queue.entries = Array(queue.entries[...queue.currentIndex]) + reordered
        let descriptor = Self.descriptor(reordered.map(\.item))
        performQueueEdit { mutableQueue, items in
            Self.remove(removals, from: mutableQueue, items: items)
            Self.insert(descriptor, after: anchor, in: mutableQueue, items: items)
        }
    }

    /// Insert songs right after the current one.
    func playNext(_ items: [MPMediaItem]) {
        guard !items.isEmpty else { return }
        guard let anchor = currentSlot() else {
            play(items[0], from: items)
            return
        }
        Haptics.selection()
        queue.entries.insert(contentsOf: items.map { QueueEntry(item: $0, sourceIndex: nil) }, at: queue.currentIndex + 1)
        let descriptor = Self.descriptor(items)
        performQueueEdit { mutableQueue, items in
            Self.insert(descriptor, after: anchor, in: mutableQueue, items: items)
        }
        queue.showToast(items.count == 1 ? "Playing Next" : "\(items.count) songs playing next")
    }

    /// Add songs to the end of the queue.
    func addToQueue(_ items: [MPMediaItem]) {
        guard !items.isEmpty else { return }
        guard currentSlot() != nil else {
            play(items[0], from: items)
            return
        }
        Haptics.selection()
        queue.entries.append(contentsOf: items.map { QueueEntry(item: $0, sourceIndex: nil) })
        let descriptor = Self.descriptor(items)
        performQueueEdit { mutableQueue, items in
            guard let last = items.last else { return }
            mutableQueue.insert(descriptor, after: last)
        }
        queue.showToast(items.count == 1 ? "Added to Queue" : "\(items.count) songs added to queue")
    }

    /// Remove Up Next rows (offsets are positions within Up Next).
    func removeFromUpNext(atOffsets offsets: IndexSet) {
        let base = queue.currentIndex + 1
        let slots = offsets.map { $0 + base }
            .filter { queue.entries.indices.contains($0) }
            .map { QueueSlot(index: $0, id: queue.entries[$0].item.persistentID) }
        guard !slots.isEmpty else { return }
        Haptics.selection()
        for slot in slots.sorted(by: { $0.index > $1.index }) { queue.entries.remove(at: slot.index) }
        performQueueEdit { mutableQueue, items in
            Self.remove(slots, from: mutableQueue, items: items)
        }
    }

    /// Reorder Up Next rows (offsets and destination are positions within Up Next).
    func moveInUpNext(fromOffsets source: IndexSet, toOffset destination: Int) {
        let base = queue.currentIndex + 1
        let before = queue.upNext
        guard !source.isEmpty, source.allSatisfy({ before.indices.contains($0) }) else { return }
        var after = before
        after.move(fromOffsets: source, toOffset: destination)
        guard after.map(\.id) != before.map(\.id) else { return }
        let moving = source.map { before[$0] }
        guard let newStart = after.firstIndex(where: { $0.id == moving[0].id }) else { return }
        Haptics.selection()

        let removals = source.map { QueueSlot(index: base + $0, id: before[$0].item.persistentID) }
        // The song that will sit just before the moved block (the current song if moved to the top),
        // addressed by where it is *now*, since the edit reads the queue as it is before the change.
        let anchor: QueueSlot
        if newStart == 0 {
            anchor = QueueSlot(index: queue.currentIndex, id: queue.entries[queue.currentIndex].item.persistentID)
        } else {
            let anchorEntry = after[newStart - 1]
            guard let currentPosition = before.firstIndex(where: { $0.id == anchorEntry.id }) else { return }
            anchor = QueueSlot(index: base + currentPosition, id: anchorEntry.item.persistentID)
        }

        queue.entries = Array(queue.entries[..<base]) + after
        let descriptor = Self.descriptor(moving.map(\.item))
        performQueueEdit { mutableQueue, items in
            Self.remove(removals, from: mutableQueue, items: items)
            Self.insert(descriptor, after: anchor, in: mutableQueue, items: items)
        }
    }

    /// Remove everything after the current song.
    func clearUpNext() {
        let slots = upNextSlots()
        guard !slots.isEmpty else { return }
        Haptics.selection()
        queue.entries.removeSubrange((queue.currentIndex + 1)...)
        performQueueEdit { mutableQueue, items in
            Self.remove(slots, from: mutableQueue, items: items)
        }
    }

    // MARK: Queue edit helpers

    /// A song at a position in the queue. Positions don't shift when the player simply moves on to
    /// the next song, so edits target position + song and are double-checked inside the transaction.
    private struct QueueSlot {
        let index: Int
        let id: UInt64
    }

    private func currentSlot() -> QueueSlot? {
        guard currentItem != nil, let entry = queue.nowPlaying else { return nil }
        return QueueSlot(index: queue.currentIndex, id: entry.item.persistentID)
    }

    private func upNextSlots() -> [QueueSlot] {
        queue.entries.indices.dropFirst(queue.currentIndex + 1).map {
            QueueSlot(index: $0, id: queue.entries[$0].item.persistentID)
        }
    }

    /// Finds `slot` in a queue snapshot: at its expected position, or the nearest other copy of that
    /// song not already `taken`.
    private nonisolated static func locate(_ slot: QueueSlot, in items: [MPMediaItem], excluding taken: Set<Int> = []) -> Int? {
        if items.indices.contains(slot.index), !taken.contains(slot.index),
           items[slot.index].persistentID == slot.id {
            return slot.index
        }
        var best: Int?
        for index in items.indices where items[index].persistentID == slot.id && !taken.contains(index) {
            if best == nil || abs(index - slot.index) < abs(best! - slot.index) { best = index }
        }
        return best
    }

    /// Removes songs. Everything is looked up in the single snapshot first, then removed, so the
    /// queue is read once no matter how many songs are involved.
    private nonisolated static func remove(
        _ slots: [QueueSlot],
        from mutableQueue: MPMusicPlayerControllerMutableQueue,
        items: [MPMediaItem]
    ) {
        var taken = Set<Int>()
        var targets: [MPMediaItem] = []
        for slot in slots {
            guard let index = locate(slot, in: items, excluding: taken) else { continue }
            taken.insert(index)
            targets.append(items[index])
        }
        for item in targets { mutableQueue.remove(item) }
    }

    private nonisolated static func insert(
        _ descriptor: MPMusicPlayerQueueDescriptor,
        after anchor: QueueSlot,
        in mutableQueue: MPMusicPlayerControllerMutableQueue,
        items: [MPMediaItem]
    ) {
        guard let index = locate(anchor, in: items) else { return }
        mutableQueue.insert(descriptor, after: items[index])
    }

    /// Play a song from Up Next now: it moves up to play immediately, and every song that was ahead
    /// of it stays in Up Next (nothing is skipped). `offset` is its position within Up Next.
    func jumpToUpNext(offset: Int) {
        let index = queue.currentIndex + 1 + offset
        guard queue.entries.indices.contains(index), let anchor = currentSlot() else { return }
        let entry = queue.entries[index]
        Haptics.play()

        // On screen: pull the song to the front of Up Next and make it the current song.
        queue.entries.remove(at: index)
        queue.entries.insert(entry, at: queue.currentIndex + 1)
        queue.currentIndex += 1
        currentItem = entry.item
        isPlaying = true
        expect(itemID: entry.item.persistentID, isPlaying: true)

        guard offset > 0 else {
            // Already next in line: just move on to it.
            player.skipToNextItem()
            startPlaybackWhenAudioSessionIsReady()
            return
        }
        // In the player: move it right after the current song, then skip to it.
        let slot = QueueSlot(index: index, id: entry.item.persistentID)
        let descriptor = Self.descriptor([entry.item])
        performQueueEdit({ mutableQueue, items in
            Self.remove([slot], from: mutableQueue, items: items)
            Self.insert(descriptor, after: anchor, in: mutableQueue, items: items)
        }, then: { [weak self] in
            self?.player.skipToNextItem()
            self?.startPlaybackWhenAudioSessionIsReady()
        })
    }

    private nonisolated static func descriptor(_ items: [MPMediaItem]) -> MPMusicPlayerMediaItemQueueDescriptor {
        MPMusicPlayerMediaItemQueueDescriptor(itemCollection: MPMediaItemCollection(items: items))
    }

    private typealias QueueEdit = (MPMusicPlayerControllerMutableQueue, [MPMediaItem]) -> Void
    private var waitingQueueEdits: [(edit: QueueEdit, then: (@MainActor () -> Void)?)] = []
    private var isQueueEditRunning = false
    private var lastQueueRefresh = Date.distantPast

    /// Applies `edit` to the system player's queue (the current song keeps playing). Hush's own queue
    /// has already been updated on screen, so this runs quietly behind it:
    /// - edits run strictly one after another (quick drags never overlap or fight each other);
    /// - edits that pile up while one is running are applied together in the next transaction;
    /// - the whole queue is not re-read afterwards (that was slow with big queues) — only if the
    ///   player reports an error, or later can't find the playing song, does Hush re-sync.
    /// `then` runs on the main thread once the player has applied the edit.
    private func performQueueEdit(_ edit: @escaping QueueEdit, then: (@MainActor () -> Void)? = nil) {
        waitingQueueEdits.append((edit, then))
        runNextQueueEdits()
    }

    private func runNextQueueEdits() {
        guard !isQueueEditRunning, !waitingQueueEdits.isEmpty else { return }
        let batch = waitingQueueEdits
        waitingQueueEdits.removeAll()
        isQueueEditRunning = true
        let edits = batch.map { $0.edit }
        player.perform(queueTransaction: { mutableQueue in
            for edit in edits {
                // One snapshot per edit: each edit's positions assume the edits before it are done.
                edit(mutableQueue, mutableQueue.items)
            }
        }, completionHandler: { [weak self] _, error in
            Task { @MainActor in
                guard let self else { return }
                self.isQueueEditRunning = false
                for step in batch { step.then?() }
                if let error {
                    hushLog.error("Queue edit failed: \(String(describing: error), privacy: .public)")
                    self.refreshQueueFromSystem()
                }
                self.runNextQueueEdits()
            }
        })
    }

    /// Reads the system player's queue (e.g. after relaunch, or if Hush's copy drifted).
    private func refreshQueueFromSystem() {
        player.perform(queueTransaction: { _ in }, completionHandler: { [weak self] systemQueue, _ in
            let items = systemQueue.items
            Task { @MainActor in self?.reconcileQueue(with: items) }
        })
    }

    /// Makes Hush's queue match the player's real queue, reusing existing rows where possible so
    /// nothing visibly jumps.
    private func reconcileQueue(with systemItems: [MPMediaItem]) {
        let systemIDs = systemItems.map(\.persistentID)
        if systemIDs != queue.entries.map(\.item.persistentID) {
            var available: [UInt64: [QueueEntry]] = [:]
            for entry in queue.entries { available[entry.item.persistentID, default: []].append(entry) }
            queue.entries = systemItems.map { item in
                if var matches = available[item.persistentID], !matches.isEmpty {
                    let entry = matches.removeFirst()
                    available[item.persistentID] = matches
                    return entry
                }
                return QueueEntry(item: item, sourceIndex: nil)
            }
        }
        syncQueuePosition()
    }

    /// Points the queue at the playing song.
    private func syncQueuePosition() {
        guard let playingID = currentItem?.persistentID, !queue.entries.isEmpty else { return }
        let reported = player.indexOfNowPlayingItem
        if reported != NSNotFound, queue.entries.indices.contains(reported),
           queue.entries[reported].item.persistentID == playingID {
            if queue.currentIndex != reported { queue.currentIndex = reported }
            return
        }
        if queue.entries.indices.contains(queue.currentIndex),
           queue.entries[queue.currentIndex].item.persistentID == playingID {
            return
        }
        // Prefer the next matching slot after the old position (normal forward playback).
        let after = queue.entries.indices.dropFirst(queue.currentIndex + 1)
        if let found = after.first(where: { queue.entries[$0].item.persistentID == playingID })
            ?? queue.entries.firstIndex(where: { $0.item.persistentID == playingID }) {
            queue.currentIndex = found
        } else if !isQueueEditRunning, Date().timeIntervalSince(lastQueueRefresh) > 5 {
            // Hush's copy has drifted from the player: fetch the real queue once.
            lastQueueRefresh = Date()
            refreshQueueFromSystem()
        }
    }

    func cycleRepeatMode() {
        Haptics.selection()
        switch player.repeatMode {
        case .none:
            player.repeatMode = .all
        case .all:
            player.repeatMode = .one
        case .one:
            player.repeatMode = .none
        case .default:
            player.repeatMode = .all
        @unknown default:
            player.repeatMode = .none
        }
        repeatMode = player.repeatMode
    }

    func skipForward() {
        Haptics.tap()
        let count = queue.entries.count
        var next = queue.currentIndex + 1
        if next >= count, repeatMode == .all { next = 0 }
        if count > 0, queue.entries.indices.contains(next) {
            showOptimistically(queueIndex: next)
        }
        afterRedraw { $0.player.skipToNextItem() }
    }

    func skipBack() {
        Haptics.tap()
        // Apple's convention: more than 3 seconds in, "previous" restarts the song.
        if currentPlaybackTime > 3 {
            afterRedraw { $0.player.skipToBeginning() }
            return
        }
        let count = queue.entries.count
        var previous = queue.currentIndex - 1
        if previous < 0, repeatMode == .all { previous = count - 1 }
        if count > 0, queue.entries.indices.contains(previous) {
            showOptimistically(queueIndex: previous)
        }
        afterRedraw { $0.player.skipToPreviousItem() }
    }

    /// Shows a queue position as current right away (artwork, title, Up Next), before the player confirms.
    private func showOptimistically(queueIndex index: Int) {
        let item = queue.entries[index].item
        queue.currentIndex = index
        currentItem = item
        expect(itemID: item.persistentID, isPlaying: isPlaying)
    }

    /// Runs a blocking player call one frame later, so the tap's on-screen change appears first.
    private func afterRedraw(_ action: @escaping @MainActor (MusicLibraryStore) -> Void) {
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 16_000_000)
            guard let self else { return }
            action(self)
            self.syncPlayback()
        }
    }

    func seek(to time: TimeInterval) {
        guard time.isFinite else { return }
        let duration = player.nowPlayingItem?.playbackDuration ?? 0
        let target = duration.isFinite && duration > 0 ? min(max(time, 0), duration) : max(time, 0)
        player.currentPlaybackTime = target
    }

    private func observePlayer() {
        player.beginGeneratingPlaybackNotifications()
        NotificationCenter.default.addObserver(
            forName: .MPMusicPlayerControllerNowPlayingItemDidChange,
            object: player,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.syncPlayback() }
        }
        NotificationCenter.default.addObserver(
            forName: .MPMusicPlayerControllerPlaybackStateDidChange,
            object: player,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.syncPlayback() }
        }
    }

    private func observeLibraryChanges() {
        guard libraryChangeObserver == nil else { return }

        libraryChangeObserver = NotificationCenter.default.addObserver(
            forName: .MPMediaLibraryDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.scheduleLibraryRefresh()
            }
        }
        mediaLibrary.beginGeneratingLibraryChangeNotifications()
    }

    private func scheduleLibraryRefresh() {
        libraryRefreshTask?.cancel()
        libraryRefreshTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: 1_000_000_000)
            } catch {
                return
            }

            guard let self, self.authorizationStatus == .authorized else { return }
            self.loadLibrary()
        }
    }

    private func syncPlayback() {
        if isSessionClosed {
            // Closed: stay hidden unless music starts again from elsewhere (Lock Screen,
            // Control Center, headphones), then pick that queue back up.
            guard player.playbackState == .playing, player.nowPlayingItem != nil else { return }
            isSessionClosed = false
            refreshQueueFromSystem()
        }
        let now = Date()
        let reportedItem = player.nowPlayingItem
        if let pending = pendingItem, now < pending.until, reportedItem?.persistentID != pending.id {
            // Stale report: the player hasn't switched to the tapped song yet.
        } else {
            pendingItem = nil
            if currentItem?.persistentID != reportedItem?.persistentID || (currentItem == nil) != (reportedItem == nil) {
                currentItem = reportedItem
            }
            syncQueuePosition()
        }

        let reportedPlaying = player.playbackState == .playing
        if let pending = pendingIsPlaying, now < pending.until, reportedPlaying != pending.value {
            // Stale report: keep the play/pause state the user just chose.
        } else {
            pendingIsPlaying = nil
            if isPlaying != reportedPlaying { isPlaying = reportedPlaying }
        }

        // Shuffle is Hush's own setting (the system player always stays unshuffled), so only
        // repeat is read back from the player.
        repeatMode = player.repeatMode
    }

    private func startPlaybackWhenAudioSessionIsReady() {
        playbackStartGeneration += 1
        let generation = playbackStartGeneration

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                guard try await self.activatePlaybackAudioSession() else { return }
                guard generation == self.playbackStartGeneration else { return }
                self.player.play()
                self.syncPlayback()
            } catch {
                hushLog.error("Couldn't activate the playback audio session: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func activatePlaybackAudioSession() async throws -> Bool {
        let session = AVAudioSession.sharedInstance()

        // Audio-session configuration can block while the system negotiates a route.
        // Keep that synchronous setup off the UI actor as well as legacy activation.
        // The category only needs setting once per launch; skipping it makes later taps start faster.
        if !isAudioSessionCategoryConfigured {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        try session.setCategory(.playback, mode: .default)
                        continuation.resume()
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
            isAudioSessionCategoryConfigured = true
        }

        if #available(iOS 27.0, *) {
            return try await session.activate()
        }

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try session.setActive(true)
                    continuation.resume(returning: true)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

extension MPMediaItem {
    /// True for music videos, home videos, movies and any other video entry in the library.
    var isVideo: Bool { !mediaType.intersection(.anyVideo).isEmpty }
}
