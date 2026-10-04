import AppKit
import AVFoundation
import Foundation
import iTunesLibrary
import MusicKit
import Observation
import os

/// Diagnostics for Console.app only; nothing is ever sent anywhere.
let hushLog = Logger(subsystem: "com.hush.player.mac", category: "Hush")

// MARK: - Models

/// One song file from the Music library that's downloaded on this Mac (so Hush can play it).
struct Track: Identifiable, Hashable, Sendable {
    let id: UInt64
    let title: String
    let artist: String
    let albumTitle: String
    let albumArtist: String
    let albumID: UInt64
    let trackNumber: Int
    let discNumber: Int
    let duration: TimeInterval
    let year: Int?
    let genre: String?
    let playCount: Int
    let dateAdded: Date?
    let location: URL
    let searchKey: String
    let sectionLetter: String

    static func == (lhs: Track, rhs: Track) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct Album: Identifiable, Sendable {
    let id: UInt64
    let title: String
    let artist: String
    let year: Int?
    let genre: String?
    let tracks: [Track]
    let dateAdded: Date?
    let totalPlayCount: Int
    let duration: TimeInterval
    let searchKey: String
    let songSearchKey: String
    let sectionLetter: String

    var artworkTrackID: UInt64 { tracks.first?.id ?? 0 }
}

/// An album as it appears on an artist's page: only the songs credited to that artist.
struct ArtistAlbum: Identifiable, Sendable {
    let id: UInt64
    let title: String
    let year: Int?
    let artworkTrackID: UInt64
    let tracks: [Track]
}

/// One artist, built from every song credited to them — duets count for each singer, the album
/// artist counts too, and spelling variants and composer duos are merged exactly like the iPhone app.
struct Artist: Identifiable, Sendable {
    let id: String
    let name: String
    /// Newest first.
    let albums: [ArtistAlbum]
    let songCount: Int
    let totalPlayCount: Int
    let searchKey: String
    let songSearchKey: String
    let sectionLetter: String

    var allSongs: [Track] { albums.flatMap(\.tracks) }
}

/// A playlist you made in the Music app. Read-only in Hush.
struct Playlist: Identifiable, Sendable {
    let id: UInt64
    let name: String
    let tracks: [Track]
    /// Up to four songs from different albums, for the cover mosaic.
    let mosaicTrackIDs: [UInt64]
    let searchKey: String
    let songSearchKey: String
    let sectionLetter: String

    var duration: TimeInterval { tracks.reduce(0) { $0 + $1.duration } }
    var totalPlayCount: Int { tracks.reduce(0) { $0 + $1.playCount } }
}

/// A music video or a movie.
struct Video: Identifiable, Hashable, Sendable {
    let id: UInt64
    let title: String
    /// Nil when the video has no artist (or only "Unknown Artist").
    let artist: String?
    let duration: TimeInterval
    /// The file on this Mac. Nil when it's only in the cloud.
    let location: URL?
    let isMovie: Bool
    /// The genre tag as written, e.g. "Comedy, Drama".
    let genre: String?
    /// Each genre on its own ("Comedy", "Drama"), for the genre pills.
    let genres: [String]
    let year: Int?
    let playCount: Int
    let dateAdded: Date?
    /// Copy-protected (or not downloaded): opens in the TV app instead of playing in Hush.
    var isProtected: Bool
    let searchKey: String
    let sectionLetter: String

    var canPlayInHush: Bool { location != nil && !isProtected }

    /// "2008 · Thriller, Crime, Drama".
    var yearAndGenre: String {
        [year.map(String.init), genre].compactMap { $0 }.joined(separator: " · ")
    }

    static func == (lhs: Video, rhs: Video) -> Bool { lhs.id == rhs.id && lhs.isProtected == rhs.isProtected }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct LibrarySnapshot: Sendable {
    var songs: [Track] = []
    var albums: [Album] = []
    var artists: [Artist] = []
    var playlists: [Playlist] = []
    var videos: [Video] = []
    var movies: [Video] = []
    var appleTVMovies: [AppleTVMovie] = []
    var appleTVShows: [AppleTVShow] = []
    var signature = 0
}

// MARK: - The library, as the app sees it

@MainActor
@Observable
final class LibraryModel {
    static let shared = LibraryModel()

    enum Status: Equatable {
        case loading
        case ready
        case failed(String)
    }

    private(set) var status: Status = .loading
    private(set) var isRefreshing = false
    private(set) var songs: [Track] = []
    private(set) var albums: [Album] = []
    private(set) var artists: [Artist] = []
    private(set) var playlists: [Playlist] = []
    private(set) var videos: [Video] = []
    private(set) var movies: [Video] = []
    /// Bought or rented on Apple TV: shown in their own sections, played in the TV app.
    private(set) var appleTVMovies: [AppleTVMovie] = []
    private(set) var appleTVShows: [AppleTVShow] = []
    /// Bumped whenever a new snapshot is applied.
    private(set) var revision = 0
    private(set) var lastLoad: Date?
    /// Artists you've marked as favourites (shared with the iPhone app's storage format).
    private(set) var favoriteArtistIDs: Set<String> = FavoriteArtists.load()
    /// Playlist covers from the Music app (via MusicKit), by folded name. Playlists without one
    /// show a mosaic of their album covers.
    private(set) var playlistArtwork: [String: MusicKit.Artwork] = [:]
    /// Songs you've hearted in the player bar (kept by Hush; the Music library is read-only).
    private(set) var favoriteSongIDs: Set<UInt64>

    @ObservationIgnored private var tracksByID: [UInt64: Track] = [:]
    @ObservationIgnored private var albumsByID: [UInt64: Album] = [:]
    @ObservationIgnored private var artistsByID: [String: Artist] = [:]
    @ObservationIgnored private var playlistsByID: [UInt64: Playlist] = [:]
    @ObservationIgnored private var signature: Int?

    private static let favoriteSongsKey = "hush.mac.favoriteSongs"

    private init() {
        let stored = UserDefaults.standard.array(forKey: Self.favoriteSongsKey) as? [String] ?? []
        favoriteSongIDs = Set(stored.compactMap { UInt64($0) })
    }

    // MARK: Loading

    func loadIfNeeded() {
        if lastLoad == nil { reload() }
    }

    /// Picks up changes made in the Music app while Hush was in the background.
    func reloadIfStale() {
        guard let lastLoad, Date().timeIntervalSince(lastLoad) > 60 else { return }
        reload()
    }

    /// Reads the whole Music library in the background.
    func reload() {
        guard !isRefreshing else { return }
        isRefreshing = true
        if songs.isEmpty { status = .loading }
        Task {
            let result = await Task.detached(priority: .userInitiated) { () -> Result<LibrarySnapshot, Error> in
                do { return .success(try await LibraryLoader.load()) } catch { return .failure(error) }
            }.value
            self.isRefreshing = false
            self.lastLoad = Date()
            switch result {
            case .success(let snapshot):
                self.apply(snapshot)
            case .failure(let error):
                hushLog.error("Library load failed: \(error.localizedDescription, privacy: .public)")
                if self.songs.isEmpty { self.status = .failed(error.localizedDescription) }
            }
        }
    }

    private func apply(_ snapshot: LibrarySnapshot) {
        MediaAccess.shared.check(locations: snapshot.songs.prefix(400).map(\.location)
            + snapshot.videos.compactMap(\.location) + snapshot.movies.compactMap(\.location))
        if snapshot.signature == signature, !songs.isEmpty {
            status = .ready
            return
        }
        signature = snapshot.signature
        songs = snapshot.songs
        albums = snapshot.albums
        artists = snapshot.artists
        playlists = snapshot.playlists
        videos = snapshot.videos
        movies = snapshot.movies
        appleTVMovies = snapshot.appleTVMovies
        appleTVShows = snapshot.appleTVShows
        tracksByID = Dictionary(snapshot.songs.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        albumsByID = Dictionary(snapshot.albums.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        artistsByID = Dictionary(snapshot.artists.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        playlistsByID = Dictionary(snapshot.playlists.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        revision &+= 1
        status = .ready
        hushLog.info("Library: \(snapshot.songs.count) songs, \(snapshot.albums.count) albums, \(snapshot.playlists.count) playlists, \(snapshot.videos.count) videos, \(snapshot.movies.count) movies")

        // Artist photos download in the background, so the Artists page is ready before you open it.
        let requests = snapshot.artists.map { (key: $0.id, name: $0.name) }
        Task.detached(priority: .utility) {
            await ArtistPhotoService.shared.preload(requests)
        }
        checkProtection()
        Task {
            if let artwork = await Self.fetchPlaylistArtwork(), artwork != playlistArtwork { playlistArtwork = artwork }
        }
    }

    func playlistArtwork(for playlist: Playlist) -> MusicKit.Artwork? {
        playlistArtwork[LibrarySearch.normalizedQuery(playlist.name)]
    }

    /// The phone's lookup: MusicKit and the iTunes library use different playlist ids, so covers are
    /// matched by name; names shared by more than one playlist are skipped. Nil if MusicKit isn't
    /// available or the request fails.
    private nonisolated static func fetchPlaylistArtwork() async -> [String: MusicKit.Artwork]? {
        guard await MusicAuthorization.request() == .authorized else { return nil }
        do {
            var batch: MusicItemCollection<MusicKit.Playlist>? = try await MusicLibraryRequest<MusicKit.Playlist>().response().items
            var artworkByName: [String: MusicKit.Artwork] = [:]
            var nameCounts: [String: Int] = [:]
            while let current = batch {
                for playlist in current {
                    let key = LibrarySearch.normalizedQuery(playlist.name)
                    nameCounts[key, default: 0] += 1
                    if let artwork = playlist.artwork { artworkByName[key] = artwork }
                }
                batch = current.hasNextBatch ? try await current.nextBatch() : nil
            }
            return artworkByName.filter { nameCounts[$0.key] == 1 }
        } catch {
            hushLog.error("Couldn't load playlist artwork: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    /// Copy-protected videos can't play in Hush. ITLibrary flags most; AVFoundation has the final word.
    private func checkProtection() {
        // Movies are only your own files; a protected one found here is dropped rather than badged.
        let candidates = (videos + movies).filter { $0.location != nil && !$0.isProtected }
        guard !candidates.isEmpty else { return }
        let revisionAtStart = revision
        Task {
            var protected = Set<UInt64>()
            for video in candidates {
                guard let url = video.location else { continue }
                let asset = AVURLAsset(url: url)
                if (try? await asset.load(.hasProtectedContent)) == true { protected.insert(video.id) }
            }
            guard !protected.isEmpty, revision == revisionAtStart else { return }
            videos = videos.map { var v = $0; if protected.contains(v.id) { v.isProtected = true }; return v }
            movies = movies.filter { !protected.contains($0.id) }
        }
    }

    // MARK: Lookups

    func track(id: UInt64) -> Track? { tracksByID[id] }
    func album(id: UInt64) -> Album? { albumsByID[id] }
    func artist(id: String) -> Artist? { artistsByID[id] }
    func playlist(id: UInt64) -> Playlist? { playlistsByID[id] }
    func album(for track: Track?) -> Album? { track.flatMap { albumsByID[$0.albumID] } }

    /// The library's artists named in a credit like "Arijit Singh & Shreya Ghoshal", in credit order.
    func creditedArtists(in credit: String?) -> [Artist] {
        var seen = Set<String>()
        return ArtistCredits.names(in: credit).compactMap { name -> Artist? in
            let key = ArtistCredits.key(for: name)
            guard seen.insert(key).inserted else { return nil }
            return artistsByID[key]
        }
    }

    // MARK: Favourites

    func isFavorite(_ artistID: String) -> Bool {
        favoriteArtistIDs.contains(artistID)
    }

    func toggleFavorite(_ artistID: String) {
        if favoriteArtistIDs.contains(artistID) {
            favoriteArtistIDs.remove(artistID)
        } else {
            favoriteArtistIDs.insert(artistID)
        }
        FavoriteArtists.save(favoriteArtistIDs)
    }

    func isFavoriteSong(_ trackID: UInt64) -> Bool {
        favoriteSongIDs.contains(trackID)
    }

    func toggleFavoriteSong(_ trackID: UInt64) {
        if favoriteSongIDs.contains(trackID) {
            favoriteSongIDs.remove(trackID)
        } else {
            favoriteSongIDs.insert(trackID)
        }
        UserDefaults.standard.set(favoriteSongIDs.map(String.init), forKey: Self.favoriteSongsKey)
    }
}

// MARK: - Reading the Music library

enum LibraryLoader {
    // ITLibMediaItemMediaKind raw values.
    private static let songKind: UInt = 2
    private static let movieKind: UInt = 3
    private static let musicVideoKind: UInt = 7
    private static let homeVideoKind: UInt = 12
    private static let tvShowKind: UInt = 8
    // ITLibPlaylistKind / ITLibDistinguishedPlaylistKind raw values.
    private static let regularPlaylist: UInt = 0
    private static let notDistinguished: UInt = 0

    /// Reads every downloaded song, video, movie and playlist from the Music and TV libraries.
    /// Runs off the main thread.
    static func load() async throws -> LibrarySnapshot {
        let library = try ITLibrary(apiVersion: "1.1")

        var tracks: [Track] = []
        var videos: [Video] = []
        var movies: [Video] = []
        var appleTVMovies: [AppleTVMovie] = []
        var episodes: [(item: ITLibMediaItem, id: UInt64)] = []
        var artworkSources: [UInt64: ITLibMediaItem] = [:]
        var locations: [UInt64: URL] = [:]

        for item in library.allMediaItems {
            let kind = UInt(item.mediaKind.rawValue)
            let id = item.persistentID.uint64Value
            switch kind {
            case songKind:
                // Only songs downloaded on this Mac can be played.
                guard let location = item.location, location.isFileURL else { continue }
                tracks.append(makeTrack(item, id: id, location: location))
                artworkSources[id] = item
                locations[id] = location
            case musicVideoKind, homeVideoKind:
                videos.append(makeVideo(item, id: id, isMovie: false))
                artworkSources[id] = item
                if let location = item.location { locations[id] = location }
            case movieKind:
                // Your own movie files go in Movies; Apple TV purchases get their own section.
                if AppleTVPurchases.isPurchase(kind: item.kind, isProtected: item.isDRMProtected,
                                               hasLocalFile: item.location?.isFileURL == true,
                                               isCloud: item.isCloud) {
                    appleTVMovies.append(AppleTVLibrary.movie(from: item, id: id))
                    artworkSources[id] = item
                    continue
                }
                movies.append(makeVideo(item, id: id, isMovie: true))
                artworkSources[id] = item
                if let location = item.location { locations[id] = location }
            case tvShowKind:
                episodes.append((item, id))
                artworkSources[id] = item
            default:
                continue
            }
        }

        // Movies the TV app keeps in its media folder that ITLibrary doesn't list.
        let knownPaths = Set(movies.compactMap { $0.location?.standardizedFileURL.path })
        for movie in await TVFolderScanner.scan(excluding: knownPaths) where !movie.isProtected {
            movies.append(movie)
            if let location = movie.location { locations[movie.id] = location }
        }

        let songs = tracks.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        let albums = buildAlbums(from: tracks)
        ArtworkStore.shared.register(library: library, items: artworkSources, locations: locations, albums: albums)
        let artists = buildArtists(from: albums)
        let tracksByID = Dictionary(tracks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let playlists = buildPlaylists(from: library, tracksByID: tracksByID)
        videos.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        movies.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }

        var hasher = Hasher()
        for track in songs {
            hasher.combine(track.id)
            hasher.combine(track.playCount)
            hasher.combine(track.title)
        }
        for playlist in playlists {
            hasher.combine(playlist.id)
            hasher.combine(playlist.name)
            for track in playlist.tracks { hasher.combine(track.id) }
        }
        for movie in appleTVMovies { hasher.combine(movie.id) }
        hasher.combine(episodes.count)
        for video in videos + movies {
            hasher.combine(video.id)
            hasher.combine(video.title)
            hasher.combine(video.location != nil)
        }

        return LibrarySnapshot(
            songs: songs,
            albums: albums,
            artists: artists,
            playlists: playlists,
            videos: videos,
            movies: movies,
            appleTVMovies: appleTVMovies.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending },
            appleTVShows: AppleTVLibrary.shows(from: episodes),
            signature: hasher.finalize()
        )
    }

    private static func makeTrack(_ item: ITLibMediaItem, id: UInt64, location: URL) -> Track {
        let album: ITLibAlbum = item.album
        let rawTitle: String = item.title
        let title = nonEmpty(rawTitle) ?? location.deletingPathExtension().lastPathComponent
        let artist = nonEmpty(item.artist?.name) ?? "Unknown Artist"
        let albumTitle = nonEmpty(album.title) ?? "Unknown Album"
        let albumArtist = nonEmpty(album.albumArtist) ?? artist
        let year = Int(item.year)
        let albumPersistentID = album.persistentID.uint64Value
        return Track(
            id: id,
            title: title,
            artist: artist,
            albumTitle: albumTitle,
            albumArtist: albumArtist,
            albumID: albumPersistentID != 0
                ? albumPersistentID
                : stableID(LibrarySearch.normalizedQuery(albumTitle) + "|" + LibrarySearch.normalizedQuery(albumArtist)),
            trackNumber: Int(item.trackNumber),
            discNumber: Int(album.discNumber),
            duration: TimeInterval(item.totalTime) / 1000,
            year: year > 0 ? year : nil,
            genre: nonEmpty(item.genre),
            playCount: Int(item.playCount),
            dateAdded: item.addedDate,
            location: location,
            searchKey: LibrarySearch.key([title, albumTitle, artist]),
            sectionLetter: LibraryAlphabet.section(for: title)
        )
    }

    private static func makeVideo(_ item: ITLibMediaItem, id: UInt64, isMovie: Bool) -> Video {
        let rawTitle: String = item.title
        let title = nonEmpty(rawTitle) ?? (isMovie ? "Untitled Movie" : "Untitled Video")
        let rawArtist = nonEmpty(item.artist?.name)
        let artist = rawArtist.flatMap { $0.caseInsensitiveCompare("Unknown Artist") == .orderedSame ? nil : $0 }
        let genre = nonEmpty(item.genre)
        let year = Int(item.year)
        let location = item.location.flatMap { $0.isFileURL ? $0 : nil }
        return Video(
            id: id,
            title: title,
            artist: isMovie ? nil : artist,
            duration: TimeInterval(item.totalTime) / 1000,
            location: location,
            isMovie: isMovie,
            genre: genre,
            genres: splitGenres(genre),
            year: year > 0 ? year : nil,
            playCount: Int(item.playCount),
            dateAdded: item.addedDate,
            isProtected: item.isDRMProtected || location == nil,
            searchKey: LibrarySearch.key([title, isMovie ? genre : artist]),
            sectionLetter: LibraryAlphabet.section(for: title)
        )
    }

    /// "Comedy, Drama" → ["Comedy", "Drama"].
    static func splitGenres(_ genre: String?) -> [String] {
        guard let genre else { return [] }
        return genre
            .components(separatedBy: CharacterSet(charactersIn: ",/&"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    static func nonEmpty(_ text: String?) -> String? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// A stable 64-bit id (FNV-1a) — the same across launches, unlike Swift's Hasher.
    static func stableID(_ text: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return hash
    }

    private static func buildAlbums(from tracks: [Track]) -> [Album] {
        var grouped: [UInt64: [Track]] = [:]
        for track in tracks { grouped[track.albumID, default: []].append(track) }

        let albums: [Album] = grouped.compactMap { id, albumTracks -> Album? in
            let ordered = albumTracks.sorted { lhs, rhs in
                if lhs.discNumber != rhs.discNumber { return lhs.discNumber < rhs.discNumber }
                if lhs.trackNumber != rhs.trackNumber { return lhs.trackNumber < rhs.trackNumber }
                return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
            }
            guard let first = ordered.first else { return nil }
            return Album(
                id: id,
                title: first.albumTitle,
                artist: first.albumArtist,
                year: albumTracks.compactMap(\.year).max(),
                genre: first.genre,
                tracks: ordered,
                dateAdded: albumTracks.compactMap(\.dateAdded).max(),
                totalPlayCount: albumTracks.reduce(0) { $0 + $1.playCount },
                duration: albumTracks.reduce(0) { $0 + $1.duration },
                searchKey: LibrarySearch.key([first.albumTitle, first.albumArtist]),
                songSearchKey: LibrarySearch.key(ordered.flatMap { [$0.title, $0.artist] }),
                sectionLetter: LibraryAlphabet.section(for: first.albumTitle)
            )
        }
        return albums.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    /// One entry per artist across the whole library, from each song's artist credit plus its album
    /// artist, with collaborations split into individual names (the iPhone app's rules).
    private static func buildArtists(from albums: [Album]) -> [Artist] {
        struct Builder {
            var spellings: [String: Int] = [:]
            var albumTracks: [UInt64: [Track]] = [:]
            var albumOrder: [UInt64] = []
        }
        var builders: [String: Builder] = [:]
        let albumsByID = Dictionary(albums.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        for album in albums {
            for track in album.tracks {
                var credited = ArtistCredits.names(in: track.artist)
                credited += ArtistCredits.names(in: track.albumArtist)
                var seenForTrack = Set<String>()
                for name in credited {
                    let key = ArtistCredits.key(for: name)
                    guard !key.isEmpty, seenForTrack.insert(key).inserted else { continue }
                    var builder = builders[key] ?? Builder()
                    builder.spellings[name, default: 0] += 1
                    if builder.albumTracks[album.id] == nil { builder.albumOrder.append(album.id) }
                    builder.albumTracks[album.id, default: []].append(track)
                    builders[key] = builder
                }
            }
        }

        let artists: [Artist] = builders.compactMap { key, builder -> Artist? in
            let mostCommon = builder.spellings.max { lhs, rhs in
                lhs.value < rhs.value || (lhs.value == rhs.value && lhs.key > rhs.key)
            }?.key
            guard let name = ArtistCredits.displayName(forKey: key) ?? mostCommon else { return nil }
            var artistAlbums: [ArtistAlbum] = builder.albumOrder.compactMap { albumID -> ArtistAlbum? in
                guard let album = albumsByID[albumID], let tracks = builder.albumTracks[albumID] else { return nil }
                return ArtistAlbum(id: albumID, title: album.title, year: album.year, artworkTrackID: album.artworkTrackID, tracks: tracks)
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
            let allTracks = artistAlbums.flatMap(\.tracks)
            return Artist(
                id: key,
                name: name,
                albums: artistAlbums,
                songCount: allTracks.count,
                totalPlayCount: allTracks.reduce(0) { $0 + $1.playCount },
                searchKey: LibrarySearch.key([name]),
                songSearchKey: LibrarySearch.key(allTracks.flatMap { [$0.title, $0.artist] }),
                sectionLetter: LibraryAlphabet.section(for: name)
            )
        }
        return artists.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Your own playlists, like the phone shows them: not the whole library, not the built-in
    /// lists (Music, Movies, Purchased…), not smart playlists, not folders.
    private static func buildPlaylists(from library: ITLibrary, tracksByID: [UInt64: Track]) -> [Playlist] {
        var playlists: [Playlist] = []
        for playlist in library.allPlaylists {
            guard !playlist.isPrimary,
                  playlist.isVisible,
                  UInt(playlist.distinguishedKind.rawValue) == notDistinguished,
                  UInt(playlist.kind.rawValue) == regularPlaylist else { continue }
            // Videos stay in their own sections; only downloaded songs are kept.
            let tracks = playlist.items.compactMap { tracksByID[$0.persistentID.uint64Value] }
            var mosaic: [UInt64] = []
            var usedAlbums = Set<UInt64>()
            for track in tracks where mosaic.count < 4 {
                if usedAlbums.insert(track.albumID).inserted { mosaic.append(track.id) }
            }
            // Fewer than four distinct covers: a single cover looks better than a partial grid.
            if mosaic.count < 4 { mosaic = Array(mosaic.prefix(1)) }
            let name = nonEmpty(playlist.name) ?? "Untitled Playlist"
            playlists.append(Playlist(
                id: playlist.persistentID.uint64Value,
                name: name,
                tracks: tracks,
                mosaicTrackIDs: mosaic,
                searchKey: LibrarySearch.key([name]),
                songSearchKey: LibrarySearch.key(tracks.flatMap { [$0.title, $0.artist] }),
                sectionLetter: LibraryAlphabet.section(for: name)
            ))
        }
        return playlists.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

// MARK: - The TV app's media folder

/// Movies sitting in the TV app's media folder (~/Movies/TV/Media.localized) that the library
/// doesn't list. Title, year, genre and poster come from the files' own metadata.
enum TVFolderScanner {
    private static let movieExtensions: Set<String> = ["m4v", "mp4", "mov"]

    static func scan(excluding knownPaths: Set<String>) async -> [Video] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let root = home.appendingPathComponent("Movies/TV/Media.localized/Movies", isDirectory: true)
        let files = (FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .addedToDirectoryDateKey],
            options: [.skipsHiddenFiles]
        )?.allObjects as? [URL]) ?? []
        var movies: [Video] = []
        for url in files where movieExtensions.contains(url.pathExtension.lowercased()) {
            guard !knownPaths.contains(url.standardizedFileURL.path) else { continue }
            movies.append(await movie(at: url))
        }
        return movies
    }

    private static func movie(at url: URL) async -> Video {
        let asset = AVURLAsset(url: url)
        var title: String?
        var genre: String?
        var year: Int?
        let common = (try? await asset.load(.commonMetadata)) ?? []
        let all = (try? await asset.load(.metadata)) ?? []
        for item in AVMetadataItem.metadataItems(from: common, filteredByIdentifier: .commonIdentifierTitle) {
            title = try? await item.load(.stringValue)
        }
        for item in all where item.identifier == .iTunesMetadataUserGenre || item.identifier == .quickTimeMetadataGenre {
            genre = try? await item.load(.stringValue)
        }
        for item in all where item.identifier == .iTunesMetadataReleaseDate || item.identifier == .commonIdentifierCreationDate {
            if let text = try? await item.load(.stringValue), let parsed = Int(text.prefix(4)) { year = parsed }
        }
        let duration = (try? await asset.load(.duration))?.seconds ?? 0
        let isProtected = (try? await asset.load(.hasProtectedContent)) ?? false
        let shown = LibraryLoader.nonEmpty(title) ?? url.deletingPathExtension().lastPathComponent
        let added = (try? url.resourceValues(forKeys: [.addedToDirectoryDateKey]))?.addedToDirectoryDate
        return Video(
            id: LibraryLoader.stableID(url.standardizedFileURL.path),
            title: shown,
            artist: nil,
            duration: duration.isFinite ? duration : 0,
            location: url,
            isMovie: true,
            genre: LibraryLoader.nonEmpty(genre),
            genres: LibraryLoader.splitGenres(genre),
            year: year,
            playCount: 0,
            dateAdded: added,
            isProtected: isProtected,
            searchKey: LibrarySearch.key([shown, genre]),
            sectionLetter: LibraryAlphabet.section(for: shown)
        )
    }
}

// MARK: - Reading media files under the sandbox

/// The sandbox lets Hush read the Music and Movies folders in your home folder. A library kept
/// elsewhere (an external drive, say) needs a one-time "Allow" in an Open panel; Hush keeps a
/// bookmark to that folder so it never asks again.
@MainActor
@Observable
final class MediaAccess {
    static let shared = MediaAccess()

    /// Set when some media files can't be read yet: the folder to ask for.
    private(set) var folderNeeded: URL?

    @ObservationIgnored private var activeURLs: [URL] = []
    private static let bookmarksKey = "hush.mac.mediaBookmarks"

    private init() {
        restoreBookmarks()
    }

    private func restoreBookmarks() {
        let stored = UserDefaults.standard.array(forKey: Self.bookmarksKey) as? [Data] ?? []
        var refreshed: [Data] = []
        for data in stored {
            var stale = false
            guard let url = try? URL(resolvingBookmarkData: data, options: [.withSecurityScope], bookmarkDataIsStale: &stale) else { continue }
            if url.startAccessingSecurityScopedResource() { activeURLs.append(url) }
            if stale, let fresh = try? url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess]) {
                refreshed.append(fresh)
            } else {
                refreshed.append(data)
            }
        }
        UserDefaults.standard.set(refreshed, forKey: Self.bookmarksKey)
    }

    /// Looks for media files Hush can't open, and if there are some, which folder to ask for.
    func check(locations: [URL]) {
        let unreadable = locations.filter { !FileManager.default.isReadableFile(atPath: $0.path) }
        guard !unreadable.isEmpty else {
            folderNeeded = nil
            return
        }
        hushLog.info("\(unreadable.count) media files are outside the sandbox's reach")
        folderNeeded = Self.commonFolder(of: unreadable)
    }

    /// The deepest folder containing all the files (on an external drive, usually the drive itself
    /// or its media folder).
    private static func commonFolder(of urls: [URL]) -> URL {
        var common = urls[0].deletingLastPathComponent().standardizedFileURL.pathComponents
        for url in urls.dropFirst() {
            let parts = url.deletingLastPathComponent().standardizedFileURL.pathComponents
            var shared = 0
            while shared < min(common.count, parts.count), common[shared] == parts[shared] { shared += 1 }
            common = Array(common.prefix(shared))
        }
        // Never ask for "/" or "/Volumes": at least the volume itself.
        if common.count < 3, let first = urls.first {
            common = Array(first.standardizedFileURL.pathComponents.prefix(3))
        }
        return URL(fileURLWithPath: NSString.path(withComponents: common), isDirectory: true)
    }

    /// Shows the Open panel at the folder Hush needs; on "Allow", remembers it and re-reads the library.
    func requestAccess() {
        guard let folder = folderNeeded else { return }
        let panel = NSOpenPanel()
        panel.message = "Hush needs to read your music and movies in this folder to play them. Choose Allow to let it."
        panel.prompt = "Allow"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.directoryURL = folder
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let bookmark = try? url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess]) else { return }
        var stored = UserDefaults.standard.array(forKey: Self.bookmarksKey) as? [Data] ?? []
        stored.append(bookmark)
        UserDefaults.standard.set(stored, forKey: Self.bookmarksKey)
        if url.startAccessingSecurityScopedResource() { activeURLs.append(url) }
        folderNeeded = nil
        LibraryModel.shared.reload()
    }
}
