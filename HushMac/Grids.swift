import AppKit
import SwiftUI

// MARK: - Shared grid

/// A scrolling grid of tiles. With titles hidden the tiles sit edge to edge as a tight mosaic
/// (2 pt gutters); with titles shown it's the roomy grid. An A–Z rail on the right jumps to a letter.
struct TileGrid<Item: Identifiable, Tile: View>: View where Item.ID: Hashable {
    let items: [Item]
    var minimumWidth: CGFloat = 270
    var isMosaic = false
    var spacing: (column: CGFloat, row: CGFloat) = (22, 26)
    /// Section letter for the A–Z rail (nil: no rail).
    var letter: ((Item) -> String)?
    var header: AnyView?
    @ViewBuilder let tile: (Item) -> Tile

    var body: some View {
        let columnSpacing = isMosaic ? 2 : spacing.column
        let rowSpacing = isMosaic ? 2 : spacing.row
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let header { header }
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: minimumWidth, maximum: minimumWidth * 1.9), spacing: columnSpacing, alignment: .top)],
                        alignment: .leading,
                        spacing: rowSpacing
                    ) {
                        ForEach(items) { item in
                            tile(item).id(item.id)
                        }
                    }
                }
                .padding(.leading, isMosaic ? 20 : 28)
                .padding(.trailing, letter == nil ? (isMosaic ? 20 : 28) : 44)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .scrollIndicators(.automatic)
            .overlay(alignment: .trailing) {
                if let letter, items.count > 24 {
                    LetterRail(letters: lettersIndex(letter)) { id in
                        withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(id, anchor: .top) }
                    }
                    .padding(.trailing, 10)
                    .padding(.vertical, 12)
                }
            }
        }
        .animation(.smooth(duration: 0.3), value: isMosaic)
    }

    private func lettersIndex(_ letter: (Item) -> String) -> [(String, Item.ID)] {
        var seen = Set<String>()
        var result: [(String, Item.ID)] = []
        for item in items {
            let key = letter(item)
            if seen.insert(key).inserted { result.append((key, item.id)) }
        }
        return result
    }
}

/// "#ABC…Z" down the right edge; letters with nothing behind them are dimmed.
struct LetterRail<ID: Hashable>: View {
    let letters: [(String, ID)]
    let jump: (ID) -> Void
    private static var alphabet: [String] { ["#"] + (65...90).map { String(UnicodeScalar($0)!) } }

    var body: some View {
        let available = Dictionary(letters.map { ($0.0, $0.1) }, uniquingKeysWith: { first, _ in first })
        VStack(spacing: 0) {
            ForEach(Self.alphabet, id: \.self) { letter in
                let target = available[letter]
                Button {
                    if let target { jump(target) }
                } label: {
                    Text(letter)
                        .font(HushStyle.rounded(10, weight: .bold))
                        .foregroundStyle(target == nil ? HushStyle.faint : HushStyle.muted)
                        .frame(width: 22)
                        .frame(maxHeight: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(HushIconButtonStyle(idle: target == nil ? HushStyle.faint : HushStyle.muted, hover: HushStyle.gold))
                .disabled(target == nil)
                .frame(maxHeight: .infinity)
            }
        }
        .frame(maxHeight: 560)
    }
}

/// A grid tile's caption: a serif title and a quiet line under it.
struct TileCaption: View {
    let title: String
    let subtitle: String?
    var alignment: HorizontalAlignment = .leading

    var body: some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(title)
                .font(HushStyle.serif(14))
                .foregroundStyle(HushStyle.ink)
                .lineLimit(1)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(HushStyle.rounded(11))
                    .foregroundStyle(HushStyle.muted)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .center)
    }
}

/// The playing badge on a cover: gold bars in a dark circle.
struct PlayingBadge: View {
    let isPlaying: Bool

    var body: some View {
        NowPlayingBars(isPlaying: isPlaying, height: 11)
            .frame(width: 28, height: 28)
            .background(Circle().fill(HushStyle.paper.opacity(0.6)))
            .padding(8)
    }
}

/// A gold play button that appears on a cover under the pointer.
struct HoverPlayButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "play.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(HushStyle.paper)
                .offset(x: 1)
                .frame(width: 34, height: 34)
                .background(HushStyle.gold, in: Circle())
                .shadow(color: .black.opacity(0.4), radius: 6, y: 2)
        }
        .buttonStyle(PressScaleButtonStyle())
        .padding(10)
        .transition(.opacity.combined(with: .scale(scale: 0.85)))
        .help("Play")
    }
}

// MARK: - Albums

struct AlbumsGrid: View {
    @Environment(LibraryModel.self) private var library
    @Environment(Navigator.self) private var navigator
    @AppStorage("hush.mac.showTitles.albums") private var showsTitles = false

    var body: some View {
        let sort = navigator.sort(for: .albums)
        let query = LibrarySearch.normalizedQuery(navigator.search(for: .albums))
        var albums = LibrarySearch.filterByNameThenSongs(library.albums, query: query, nameKey: \.searchKey, songsKey: \.songSearchKey)
        if sort == .mostPlayed { albums.sort { $0.totalPlayCount > $1.totalPlayCount } }
        return Group {
            if albums.isEmpty {
                EmptyStateView(symbol: "square.stack", title: query.isEmpty ? "No albums yet" : "No matches",
                               message: query.isEmpty ? "Albums you download in the Music app show up here." : "Try another name.")
            } else {
                TileGrid(items: albums, spacing: (20, 28),
                         letter: sort == .alphabetical && query.isEmpty ? { $0.sectionLetter } : nil) { album in
                    AlbumTile(album: album, showsTitle: showsTitles)
                }
            }
        }
    }
}

struct AlbumTile: View {
    let album: Album
    let showsTitle: Bool
    @Environment(Player.self) private var player
    @Environment(Navigator.self) private var navigator
    @State private var isHovering = false

    var body: some View {
        let isCurrent = player.current?.albumID == album.id
        VStack(alignment: .leading, spacing: 8) {
            Button {
                navigator.show(.album(album.id))
            } label: {
                CoverView(id: album.artworkTrackID, pixels: 600, cornerRadius: 10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.white.opacity(0.05), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.42), radius: 12, y: 8)
            }
            .buttonStyle(PressScaleButtonStyle())
            .overlay(alignment: .topTrailing) {
                if isCurrent { PlayingBadge(isPlaying: player.isPlaying) }
            }
            .overlay(alignment: .bottomLeading) {
                if isHovering {
                    HoverPlayButton { player.play(album.tracks, source: .album(album.id), shuffle: false) }
                }
            }
            if showsTitle {
                TileCaption(title: album.title, subtitle: [album.artist, album.year.map(String.init)].compactMap { $0 }.joined(separator: " · "))
            }
        }
        .onHover { hovering in withAnimation(.easeOut(duration: 0.15)) { isHovering = hovering } }
        .help(showsTitle ? "" : "\(album.title) — \(album.artist)")
        .contextMenu {
            CollectionMenu(tracks: album.tracks, source: .album(album.id))
            Divider()
            ArtistLinks(credit: album.artist)
        }
    }
}

// MARK: - Playlists

struct PlaylistsGrid: View {
    @Environment(LibraryModel.self) private var library
    @Environment(Navigator.self) private var navigator
    @AppStorage("hush.mac.showTitles.playlists") private var showsTitles = false

    var body: some View {
        let sort = navigator.sort(for: .playlists)
        let query = LibrarySearch.normalizedQuery(navigator.search(for: .playlists))
        var playlists = LibrarySearch.filterByNameThenSongs(library.playlists, query: query, nameKey: \.searchKey, songsKey: \.songSearchKey)
        if sort == .mostPlayed { playlists.sort { $0.totalPlayCount > $1.totalPlayCount } }
        return Group {
            if playlists.isEmpty {
                EmptyStateView(symbol: "music.note.list", title: query.isEmpty ? "No playlists yet" : "No matches",
                               message: query.isEmpty ? "Playlists you make in the Music app show up here. Hush keeps them read-only." : "Try another name.")
            } else {
                TileGrid(items: playlists, spacing: (20, 28),
                         letter: sort == .alphabetical && query.isEmpty ? { $0.sectionLetter } : nil) { playlist in
                    PlaylistTile(playlist: playlist, showsTitle: showsTitles)
                }
            }
        }
    }
}

struct PlaylistTile: View {
    let playlist: Playlist
    let showsTitle: Bool
    @Environment(LibraryModel.self) private var library
    @Environment(Player.self) private var player
    @Environment(Navigator.self) private var navigator
    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                navigator.show(.playlist(playlist.id))
            } label: {
                PlaylistCover(playlist: playlist, pixels: 600, cornerRadius: 10)
                    .overlay(alignment: .bottomLeading) {
                        if !showsTitle && !PlaylistCover.hasOwnArtwork(playlist, in: library) {
                            // The mosaic doesn't carry the playlist's name the way album art does.
                            Text(playlist.name)
                                .font(HushStyle.serif(15))
                                .foregroundStyle(.white)
                                .lineLimit(2)
                                .shadow(color: .black.opacity(0.7), radius: 6)
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    LinearGradient(colors: [.black.opacity(0.55), .clear], startPoint: .bottom, endPoint: .top)
                                )
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .shadow(color: .black.opacity(0.42), radius: 12, y: 8)
            }
            .buttonStyle(PressScaleButtonStyle())
            .overlay(alignment: .topTrailing) {
                if player.source == .playlist(playlist.id), player.current != nil { PlayingBadge(isPlaying: player.isPlaying) }
            }
            .overlay(alignment: .bottomTrailing) {
                if isHovering {
                    HoverPlayButton { player.play(playlist.tracks, source: .playlist(playlist.id), shuffle: false) }
                }
            }
            if showsTitle {
                TileCaption(title: playlist.name, subtitle: HushStyle.songCount(playlist.tracks.count))
            }
        }
        .onHover { hovering in withAnimation(.easeOut(duration: 0.15)) { isHovering = hovering } }
        .contextMenu {
            CollectionMenu(tracks: playlist.tracks, source: .playlist(playlist.id))
            Divider()
            Button("Edit in Music") { MusicApp.open() }
        }
    }
}

// MARK: - Artists

struct ArtistsGrid: View {
    @Environment(LibraryModel.self) private var library
    @Environment(Navigator.self) private var navigator

    var body: some View {
        let sort = navigator.sort(for: .artists)
        let query = LibrarySearch.normalizedQuery(navigator.search(for: .artists))
        var artists = LibrarySearch.filterByNameThenSongs(library.artists, query: query, nameKey: \.searchKey, songsKey: \.songSearchKey)
        if sort == .mostPlayed { artists.sort { $0.totalPlayCount > $1.totalPlayCount } }
        let favorites = sort == .favorites ? artists.filter { library.isFavorite($0.id) } : []
        let others = sort == .favorites ? artists.filter { !library.isFavorite($0.id) } : artists
        return Group {
            if artists.isEmpty {
                EmptyStateView(symbol: "music.mic", title: query.isEmpty ? "No artists yet" : "No matches",
                               message: query.isEmpty ? "Artists appear as your songs download." : "Try another name.")
            } else {
                TileGrid(
                    items: others,
                    minimumWidth: 220,
                    spacing: (30, 26),
                    letter: sort != .mostPlayed && query.isEmpty ? { $0.sectionLetter } : nil,
                    header: favorites.isEmpty ? nil : AnyView(favoritesRow(favorites))
                ) { artist in
                    ArtistTile(artist: artist)
                }
            }
        }
    }

    private func favoritesRow(_ favorites: [Artist]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionLabel("FAVOURITES", color: HushStyle.gold)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220, maximum: 400), spacing: 30, alignment: .top)], alignment: .leading, spacing: 26) {
                ForEach(favorites) { ArtistTile(artist: $0) }
            }
            sectionLabel("EVERYONE ELSE", color: HushStyle.muted)
                .padding(.top, 16)
        }
        .padding(.bottom, 14)
    }

    private func sectionLabel(_ text: String, color: Color) -> some View {
        Text(text)
            .font(HushStyle.rounded(11, weight: .bold))
            .tracking(0.9)
            .foregroundStyle(color)
    }
}

struct ArtistTile: View {
    let artist: Artist
    @Environment(LibraryModel.self) private var library
    @Environment(Player.self) private var player
    @Environment(Navigator.self) private var navigator
    @State private var isHovering = false

    var body: some View {
        let isFavorite = library.isFavorite(artist.id)
        VStack(spacing: 9) {
            Button {
                navigator.show(.artist(artist.id))
            } label: {
                ArtistPhoto(artistID: artist.id, name: artist.name)
                    .shadow(color: .black.opacity(0.4), radius: 10, y: 6)
            }
            .buttonStyle(PressScaleButtonStyle())
            .overlay(alignment: .topTrailing) {
                if isHovering || isFavorite {
                    Button {
                        library.toggleFavorite(artist.id)
                    } label: {
                        Image(systemName: isFavorite ? "heart.fill" : "heart")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(isFavorite ? HushStyle.gold : HushStyle.ink)
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(HushStyle.paper.opacity(0.7)))
                    }
                    .buttonStyle(PressScaleButtonStyle())
                    .help(isFavorite ? "Remove from Favourites" : "Add to Favourites")
                    .transition(.opacity)
                }
            }
            .overlay(alignment: .bottomLeading) {
                if player.source == .artist(artist.id), player.current != nil {
                    NowPlayingBars(isPlaying: player.isPlaying, height: 11)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(HushStyle.paper.opacity(0.7)))
                }
            }
            TileCaption(title: artist.name, subtitle: HushStyle.songCount(artist.songCount), alignment: .center)
        }
        .onHover { hovering in withAnimation(.easeOut(duration: 0.15)) { isHovering = hovering } }
        .contextMenu {
            CollectionMenu(tracks: artist.allSongs, source: .artist(artist.id))
            Divider()
            Button(isFavorite ? "Remove from Favourites" : "Add to Favourites") { library.toggleFavorite(artist.id) }
        }
    }
}

// MARK: - Music videos

struct MusicVideosGrid: View {
    @Environment(LibraryModel.self) private var library
    @Environment(Navigator.self) private var navigator
    @Environment(VideoPlayback.self) private var playback

    var body: some View {
        let sort = navigator.sort(for: .musicVideos)
        let query = LibrarySearch.normalizedQuery(navigator.search(for: .musicVideos))
        var videos = library.videos.filter { LibrarySearch.matches($0.searchKey, query: query) }
        if sort == .mostPlayed { videos.sort { $0.playCount > $1.playCount } }
        return Group {
            if videos.isEmpty {
                EmptyStateView(symbol: "play.rectangle", title: query.isEmpty ? "No music videos" : "No matches",
                               message: query.isEmpty ? "Music videos in your Music library show up here." : "Try another name.")
            } else {
                TileGrid(items: videos, minimumWidth: 340, spacing: (20, 26),
                         letter: sort == .alphabetical && query.isEmpty ? { $0.sectionLetter } : nil) { video in
                    VideoTile(video: video) { playback.play(video, in: videos) }
                }
            }
        }
    }
}

struct VideoTile: View {
    let video: Video
    let play: () -> Void
    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: play) {
                CoverView(id: video.id, pixels: 800, cornerRadius: 9, aspectRatio: 16 / 9, kind: .videoStill, placeholderSymbol: "play.rectangle")
                    .overlay(alignment: .bottomTrailing) {
                        Text(HushStyle.timestamp(video.duration))
                            .font(HushStyle.rounded(10.5, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(.black.opacity(0.62)))
                            .padding(8)
                    }
                    .overlay {
                        if isHovering {
                            Image(systemName: video.canPlayInHush ? "play.fill" : "tv")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(HushStyle.paper)
                                .frame(width: 46, height: 46)
                                .background(HushStyle.gold, in: Circle())
                                .shadow(color: .black.opacity(0.4), radius: 8, y: 3)
                                .transition(.opacity.combined(with: .scale(scale: 0.85)))
                        }
                    }
                    .overlay(alignment: .topLeading) {
                        if !video.canPlayInHush { TVAppBadge().padding(8) }
                    }
                    .shadow(color: .black.opacity(0.4), radius: 12, y: 8)
            }
            .buttonStyle(PressScaleButtonStyle())
            TileCaption(title: video.title, subtitle: video.artist)
        }
        .onHover { hovering in withAnimation(.easeOut(duration: 0.15)) { isHovering = hovering } }
        .contextMenu {
            Button(video.canPlayInHush ? "Play" : "Open in TV App", action: play)
            if let location = video.location {
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([location]) }
            }
        }
    }
}

/// Marks a copy-protected video: it opens in the TV app.
struct TVAppBadge: View {
    var body: some View {
        Label("TV app", systemImage: "tv")
            .font(HushStyle.rounded(10, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(.black.opacity(0.65)))
            .overlay(Capsule().stroke(.white.opacity(0.18), lineWidth: 1))
            .help("Copy-protected: plays in the TV app")
    }
}

// MARK: - Movies

struct MoviesGrid: View {
    @Environment(LibraryModel.self) private var library
    @Environment(Navigator.self) private var navigator
    @Environment(VideoPlayback.self) private var playback
    @AppStorage("hush.mac.showTitles.movies") private var showsTitles = false
    @AppStorage("hush.mac.movieGenre") private var genre = ""

    var body: some View {
        let sort = navigator.sort(for: .movies)
        let query = LibrarySearch.normalizedQuery(navigator.search(for: .movies))
        let genres = Self.genres(in: library.movies)
        let activeGenre = genres.contains(genre) ? genre : ""
        var movies = library.movies.filter {
            LibrarySearch.matches($0.searchKey, query: query) && (activeGenre.isEmpty || $0.genres.contains(activeGenre))
        }
        if sort == .mostPlayed { movies.sort { $0.playCount > $1.playCount } }
        return VStack(alignment: .leading, spacing: 0) {
            if !genres.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        genrePill("All", isOn: activeGenre.isEmpty) { genre = "" }
                        ForEach(genres, id: \.self) { name in
                            genrePill(name, isOn: activeGenre == name) { genre = name }
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.top, 4)
                    .padding(.bottom, 16)
                }
                .scrollIndicators(.never)
            }
            if movies.isEmpty {
                EmptyStateView(symbol: "film", title: query.isEmpty ? "No movies" : "No matches",
                               message: query.isEmpty ? "Movies from your TV app library show up here." : "Try another title or genre.")
            } else {
                // Posters always get room around them (no edge-to-edge mosaic here).
                TileGrid(items: movies, minimumWidth: 200, spacing: (20, 28),
                         letter: sort == .alphabetical && query.isEmpty ? { $0.sectionLetter } : nil) { movie in
                    MovieTile(movie: movie, showsTitle: showsTitles) { playback.play(movie, in: movies) }
                }
            }
        }
    }

    /// Every genre, most common first.
    static func genres(in movies: [Video]) -> [String] {
        var counts: [String: Int] = [:]
        for movie in movies { for genre in movie.genres { counts[genre, default: 0] += 1 } }
        return counts.sorted { $0.value > $1.value || ($0.value == $1.value && $0.key < $1.key) }.map(\.key)
    }

    private func genrePill(_ title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(HushStyle.rounded(12.5, weight: isOn ? .semibold : .medium))
                .foregroundStyle(isOn ? HushStyle.paper : HushStyle.ink.opacity(0.85))
                .padding(.horizontal, 14)
                .frame(height: 30)
                .background(Capsule().fill(isOn ? HushStyle.gold : HushStyle.fill))
                .overlay(Capsule().stroke(isOn ? .clear : HushStyle.fillStroke, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct MovieTile: View {
    let movie: Video
    let showsTitle: Bool
    let play: () -> Void
    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: play) {
                CoverView(id: movie.id, pixels: 600, cornerRadius: 10, aspectRatio: 2 / 3, placeholderSymbol: "film")
                    .overlay {
                        if isHovering {
                            Image(systemName: "play.fill")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(HushStyle.paper)
                                .frame(width: 46, height: 46)
                                .background(HushStyle.gold, in: Circle())
                                .shadow(color: .black.opacity(0.4), radius: 8, y: 3)
                                .transition(.opacity.combined(with: .scale(scale: 0.85)))
                        }
                    }
                    .shadow(color: .black.opacity(0.42), radius: 12, y: 8)
            }
            .buttonStyle(PressScaleButtonStyle())
            if showsTitle {
                TileCaption(title: movie.title, subtitle: movie.yearAndGenre)
            }
        }
        .onHover { hovering in withAnimation(.easeOut(duration: 0.15)) { isHovering = hovering } }
        .help(showsTitle ? "" : [movie.title, movie.yearAndGenre].filter { !$0.isEmpty }.joined(separator: " — "))
        .contextMenu {
            Button("Play", action: play)
            if let location = movie.location {
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([location]) }
            }
        }
    }
}

// MARK: - Menus

/// Play / Shuffle / Play Next / Add to Up Next for an album, playlist or artist.
struct CollectionMenu: View {
    let tracks: [Track]
    let source: PlaybackSource
    @Environment(Player.self) private var player

    var body: some View {
        Button("Play") { player.play(tracks, source: source, shuffle: false) }
        Button("Shuffle") { player.shufflePlay(tracks, source: source) }
        Divider()
        Button("Play Next") { player.playNext(tracks) }
        Button("Add to Up Next") { player.addToQueue(tracks) }
    }
}

/// "Go to Artist" — one item, or a submenu when several artists are credited.
struct ArtistLinks: View {
    let credit: String
    var extraCredit: String?
    @Environment(LibraryModel.self) private var library
    @Environment(Navigator.self) private var navigator

    var body: some View {
        let artists = uniqueArtists
        if artists.count == 1, let artist = artists.first {
            Button("Go to Artist") { navigator.show(.artist(artist.id)) }
        } else if artists.count > 1 {
            Menu("Go to Artist") {
                ForEach(artists) { artist in
                    Button(artist.name) { navigator.show(.artist(artist.id)) }
                }
            }
        }
    }

    private var uniqueArtists: [Artist] {
        var seen = Set<String>()
        return (library.creditedArtists(in: credit) + library.creditedArtists(in: extraCredit)).filter { seen.insert($0.id).inserted }
    }
}

/// The right-click menu for a song.
struct SongMenu: View {
    let track: Track
    /// The list it's shown in, so Play continues through it.
    let list: [Track]
    var source: PlaybackSource?
    @Environment(Player.self) private var player
    @Environment(Navigator.self) private var navigator

    var body: some View {
        Button("Play") { player.play(list, startingAt: track, source: source) }
        Button("Play Next") { player.playNext([track]) }
        Button("Add to Up Next") { player.addToQueue([track]) }
        Divider()
        Button("Go to Album") { navigator.show(.album(track.albumID)) }
        ArtistLinks(credit: track.artist)
        Divider()
        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([track.location]) }
    }
}
