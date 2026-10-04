import AppKit
import SwiftUI

// MARK: - Album

/// Cover, title and Play / Shuffle on the left; the songs on the right.
struct AlbumPage: View {
    let albumID: UInt64
    @Environment(LibraryModel.self) private var library
    @Environment(Player.self) private var player
    @Environment(Navigator.self) private var navigator

    var body: some View {
        if let album = library.album(id: albumID) {
            CollectionLayout {
                CoverView(id: album.artworkTrackID, pixels: 700, cornerRadius: 16)
                    .shadow(color: .black.opacity(0.6), radius: 30, y: 24)
                Text(album.title)
                    .font(HushStyle.serif(32))
                    .foregroundStyle(HushStyle.ink)
                    .padding(.top, 6)
                    .textSelection(.enabled)
                ArtistNameLinks(credit: album.artist, font: .system(size: 15, weight: .medium), color: HushStyle.gold)
                    .padding(.top, -6)
                Text(albumDetails(album))
                    .font(.system(size: 12.5))
                    .foregroundStyle(HushStyle.muted)
                    .padding(.top, -6)
                PlayShuffleButtons(
                    playTitle: "Play album",
                    play: { player.play(album.tracks, source: .album(album.id), shuffle: false) },
                    shuffle: { player.shufflePlay(album.tracks, source: .album(album.id)) }
                )
                .padding(.top, 4)
            } list: {
                TrackList(tracks: album.tracks, source: .album(album.id), style: .album(albumArtist: album.artist))
            }
        } else {
            EmptyStateView(symbol: "square.stack", title: "Album not found", message: "It may have been removed from your library.")
        }
    }

    private func albumDetails(_ album: Album) -> String {
        [album.year.map(String.init), album.genre, HushStyle.songCount(album.tracks.count), HushStyle.durationText(album.duration)]
            .compactMap { $0 }
            .joined(separator: " · ")
    }
}

// MARK: - Playlist

struct PlaylistPage: View {
    let playlistID: UInt64
    @Environment(LibraryModel.self) private var library
    @Environment(Player.self) private var player

    var body: some View {
        if let playlist = library.playlist(id: playlistID) {
            CollectionLayout {
                PlaylistCover(playlist: playlist, pixels: 700, cornerRadius: 16)
                    .shadow(color: .black.opacity(0.6), radius: 30, y: 24)
                Text(playlist.name)
                    .font(HushStyle.serif(32))
                    .foregroundStyle(HushStyle.ink)
                    .padding(.top, 6)
                Text([HushStyle.songCount(playlist.tracks.count), HushStyle.durationText(playlist.duration)].compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 12.5))
                    .foregroundStyle(HushStyle.muted)
                    .padding(.top, -6)
                PlayShuffleButtons(
                    playTitle: "Play",
                    play: { player.play(playlist.tracks, source: .playlist(playlist.id), shuffle: false) },
                    shuffle: { player.shufflePlay(playlist.tracks, source: .playlist(playlist.id)) }
                )
                .padding(.top, 4)
                Button {
                    MusicApp.open()
                } label: {
                    Label("Edit in Music", systemImage: "arrow.up.forward.app")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(HushIconButtonStyle(idle: HushStyle.muted, hover: HushStyle.gold))
                .help("Playlists are read-only in Hush. Edit them in the Music app, then refresh.")
            } list: {
                if playlist.tracks.isEmpty {
                    EmptyStateView(symbol: "music.note.list", title: "No songs here yet",
                                   message: "Add songs to this playlist in the Music app. Songs that aren't downloaded on this Mac don't show.")
                } else {
                    TrackList(tracks: playlist.tracks, source: .playlist(playlist.id), style: .playlist)
                }
            }
        } else {
            EmptyStateView(symbol: "music.note.list", title: "Playlist not found", message: "It may have been deleted in the Music app.")
        }
    }
}

/// Left column of fixed width with the cover and actions; the list fills the rest.
struct CollectionLayout<Side: View, List: View>: View {
    @ViewBuilder let side: Side
    @ViewBuilder let list: List

    var body: some View {
        GeometryReader { geometry in
            let sideWidth = min(300, max(220, geometry.size.width * 0.3))
            HStack(alignment: .top, spacing: 40) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) { side }
                        .frame(width: sideWidth, alignment: .leading)
                        .padding(.top, 8)
                        .padding(.bottom, 28)
                }
                .scrollIndicators(.never)
                .frame(width: sideWidth)
                list
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .padding(.leading, 32)
            .padding(.trailing, 28)
        }
    }
}

struct PlayShuffleButtons: View {
    var playTitle = "Play"
    let play: () -> Void
    let shuffle: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: play) {
                Label(playTitle, systemImage: "play.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(HushPrimaryButtonStyle())
            Button(action: shuffle) {
                Label("Shuffle", systemImage: "shuffle").frame(maxWidth: .infinity)
            }
            .buttonStyle(HushSecondaryButtonStyle())
        }
    }
}

/// Artist names in a credit, each a link to that artist's page.
struct ArtistNameLinks: View {
    let credit: String
    var font: Font = .system(size: 15, weight: .medium)
    var color: Color = HushStyle.gold
    @Environment(LibraryModel.self) private var library
    @Environment(Navigator.self) private var navigator

    var body: some View {
        let artists = library.creditedArtists(in: credit)
        if artists.isEmpty {
            Text(credit).font(font).foregroundStyle(color)
        } else {
            HStack(spacing: 0) {
                ForEach(Array(artists.enumerated()), id: \.element.id) { index, artist in
                    Button(artist.name) { navigator.show(.artist(artist.id)) }
                        .buttonStyle(.plain)
                        .pointingHandCursor()
                    if index < artists.count - 1 { Text(", ") }
                }
            }
            .font(font)
            .foregroundStyle(color)
            .lineLimit(1)
        }
    }
}

// MARK: - Track list

/// The songs on an album, playlist or artist page. Click a row to play from it.
struct TrackList: View {
    enum Style {
        /// Track numbers; the artist only when it differs from the album's.
        case album(albumArtist: String)
        /// Small covers, artist and album.
        case playlist
    }

    let tracks: [Track]
    let source: PlaybackSource
    let style: Style
    @Environment(Navigator.self) private var navigator

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                        TrackRow(track: track, index: index, tracks: tracks, source: source, style: style)
                            .id(track.id)
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .onAppear { reveal(proxy) }
            .onChange(of: navigator.revealRequest) { reveal(proxy) }
        }
    }

    private func reveal(_ proxy: ScrollViewProxy) {
        guard let id = navigator.revealTrackID, tracks.contains(where: { $0.id == id }) else { return }
        withAnimation(.easeOut(duration: 0.3)) { proxy.scrollTo(id, anchor: .center) }
    }
}

struct TrackRow: View {
    let track: Track
    let index: Int
    let tracks: [Track]
    let source: PlaybackSource
    let style: TrackList.Style
    @Environment(LibraryModel.self) private var library
    @Environment(Player.self) private var player
    @Environment(Navigator.self) private var navigator
    @State private var isHovering = false

    var body: some View {
        let isCurrent = player.current?.id == track.id
        let isRevealed = navigator.revealTrackID == track.id && isCurrent
        Button {
            player.play(tracks, startingAt: track, source: source)
        } label: {
            HStack(spacing: 12) {
                leading(isCurrent: isCurrent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title)
                        .font(.system(size: 13.5, weight: isCurrent ? .semibold : .regular))
                        .foregroundStyle(isCurrent ? HushStyle.gold : HushStyle.ink)
                        .lineLimit(1)
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 11.5))
                            .foregroundStyle(HushStyle.muted)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 12)
                if library.isFavoriteSong(track.id) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(HushStyle.gold.opacity(0.8))
                }
                Text(HushStyle.timestamp(track.duration))
                    .font(.system(size: 12))
                    .monospacedDigit()
                    .foregroundStyle(HushStyle.muted)
            }
            .padding(.horizontal, 12)
            .frame(height: subtitle == nil ? 42 : 50)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isCurrent ? HushStyle.gold.opacity(isRevealed ? 0.14 : 0.08) : (isHovering ? HushStyle.ink.opacity(0.05) : .clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .contextMenu { SongMenu(track: track, list: tracks, source: source) }
    }

    @ViewBuilder
    private func leading(isCurrent: Bool) -> some View {
        switch style {
        case .album:
            ZStack {
                if isCurrent {
                    NowPlayingBars(isPlaying: player.isPlaying, barWidth: 2.5, height: 12)
                } else if isHovering {
                    Image(systemName: "play.fill").font(.system(size: 11)).foregroundStyle(HushStyle.ink)
                } else {
                    Text(track.trackNumber > 0 ? "\(track.trackNumber)" : "\(index + 1)")
                        .font(.system(size: 12.5))
                        .monospacedDigit()
                        .foregroundStyle(HushStyle.muted)
                }
            }
            .frame(width: 24)
        case .playlist:
            CoverView(id: track.id, pixels: 90, cornerRadius: 5)
                .frame(width: 36, height: 36)
                .overlay {
                    if isCurrent {
                        NowPlayingBars(isPlaying: player.isPlaying, barWidth: 2.5, height: 12)
                            .frame(width: 36, height: 36)
                            .background(RoundedRectangle(cornerRadius: 5).fill(.black.opacity(0.5)))
                    }
                }
        }
    }

    private var subtitle: String? {
        switch style {
        case .album(let albumArtist):
            return track.artist == albumArtist ? nil : track.artist
        case .playlist:
            return "\(track.artist) · \(track.albumTitle)"
        }
    }
}

// MARK: - Artist

/// A big circle, Play / Shuffle / favourite, their most played songs in two columns, and their albums.
struct ArtistPage: View {
    let artistID: String
    @Environment(LibraryModel.self) private var library
    @Environment(Player.self) private var player
    @Environment(Navigator.self) private var navigator

    var body: some View {
        if let artist = library.artist(id: artistID) {
            ScrollView {
                VStack(alignment: .leading, spacing: 30) {
                    header(artist)
                    mostPlayed(artist)
                    albums(artist)
                }
                .padding(.leading, 32)
                .padding(.trailing, 36)
                .padding(.top, 6)
                .padding(.bottom, 28)
            }
        } else {
            EmptyStateView(symbol: "music.mic", title: "Artist not found", message: "Their songs may have been removed.")
        }
    }

    private func header(_ artist: Artist) -> some View {
        let isFavorite = library.isFavorite(artist.id)
        return HStack(spacing: 30) {
            ArtistPhoto(artistID: artist.id, name: artist.name)
                .frame(width: 176, height: 176)
                .shadow(color: .black.opacity(0.6), radius: 25, y: 20)
            VStack(alignment: .leading, spacing: 10) {
                Text(artist.name)
                    .font(HushStyle.serif(44))
                    .foregroundStyle(HushStyle.ink)
                    .lineLimit(2)
                Text("\(HushStyle.songCount(artist.songCount)) · \(artist.albums.count == 1 ? "1 album" : "\(artist.albums.count) albums")")
                    .font(.system(size: 13))
                    .foregroundStyle(HushStyle.muted)
                HStack(spacing: 10) {
                    Button { player.play(artist.allSongs, source: .artist(artist.id), shuffle: false) } label: {
                        Label("Play", systemImage: "play.fill")
                    }
                    .buttonStyle(HushPrimaryButtonStyle())
                    Button { player.shufflePlay(artist.allSongs, source: .artist(artist.id)) } label: {
                        Label("Shuffle", systemImage: "shuffle")
                    }
                    .buttonStyle(HushSecondaryButtonStyle())
                    Button { library.toggleFavorite(artist.id) } label: {
                        Image(systemName: isFavorite ? "heart.fill" : "heart")
                    }
                    .buttonStyle(HushCircleButtonStyle(diameter: 38, isOn: isFavorite))
                    .help(isFavorite ? "Remove from Favourites" : "Add to Favourites")
                }
                .padding(.top, 6)
            }
        }
    }

    @ViewBuilder
    private func mostPlayed(_ artist: Artist) -> some View {
        let top = Array(artist.allSongs.sorted { $0.playCount > $1.playCount }.prefix(10))
        if !top.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("Most played")
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 24), GridItem(.flexible(), spacing: 24)], alignment: .leading, spacing: 0) {
                    ForEach(Array(top.enumerated()), id: \.element.id) { index, track in
                        TrackRow(track: track, index: index, tracks: top, source: .artist(artist.id), style: .playlist)
                    }
                }
            }
        }
    }

    private func albums(_ artist: Artist) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Albums")
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 20) {
                    ForEach(artist.albums) { album in
                        Button {
                            navigator.show(.album(album.id))
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                CoverView(id: album.artworkTrackID, pixels: 400, cornerRadius: 9)
                                    .frame(width: 220, height: 220)
                                    .shadow(color: .black.opacity(0.42), radius: 12, y: 8)
                                TileCaption(title: album.title, subtitle: [album.year.map(String.init), HushStyle.songCount(album.tracks.count)].compactMap { $0 }.joined(separator: " · "))
                                    .frame(width: 220)
                            }
                        }
                        .buttonStyle(PressScaleButtonStyle())
                        .contextMenu {
                            if let full = library.album(id: album.id) {
                                CollectionMenu(tracks: full.tracks, source: .album(album.id))
                            }
                        }
                    }
                }
                .padding(.bottom, 16)
            }
            .scrollIndicators(.never)
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(HushStyle.serif(22))
            .foregroundStyle(HushStyle.ink)
    }
}
