import MediaPlayer
import MusicKit
import SwiftUI

// The tiles and rows of the library tabs (see ContentView).

struct PlaylistTile: View {
    let playlist: MusicPlaylist
    let artwork: Artwork?
    let showsTitle: Bool
    var isPlaying = false
    let zoomNamespace: Namespace.ID

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Square cell sized by the grid column, matching album tiles.
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    GeometryReader { geometry in
                        PlaylistArtwork(
                            items: playlist.artworkItems,
                            size: geometry.size.width,
                            artwork: artwork,
                            cornerRadius: HushStyle.tileCornerRadius
                        )
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if isPlaying { NowPlayingBadge(size: 24).padding(8) }
                }
                .pageZoomSource(PlayerArtworkTransitionID.playlistGridTile(playlist.id), in: zoomNamespace, cornerRadius: HushStyle.tileCornerRadius)
            if showsTitle {
                VStack(alignment: .leading, spacing: 2) {
                    Text(playlist.name)
                        .font(.system(size: 15, weight: .regular, design: .serif))
                        .foregroundStyle(HushStyle.ink)
                        .lineLimit(1)
                    Text("\(playlist.trackCount) songs")
                        .font(.system(size: 12.5))
                        .foregroundStyle(HushStyle.muted)
                        .lineLimit(1)
                }
            }
        }
        // VoiceOver still reads the name when titles are hidden.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(playlist.name), \(playlist.trackCount) songs\(isPlaying ? ", now playing" : "")")
    }
}

struct ArtistTile: View {
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
                            .foregroundStyle(HushStyle.accent)
                            .frame(width: 24, height: 24)
                            .background(HushStyle.paper, in: Circle())
                            .overlay(Circle().stroke(HushStyle.accent.opacity(0.35), lineWidth: 0.6))
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
                .font(.system(size: 14, weight: .regular, design: .serif))
                .foregroundStyle(HushStyle.ink)
                .lineLimit(1)
            Text(artist.songCount == 1 ? "1 song" : "\(artist.songCount) songs")
                .font(.system(size: 12))
                .foregroundStyle(HushStyle.muted)
                .lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(artist.name), \(artist.songCount) songs\(isFavorite ? ", favorite" : "")\(isPlaying ? ", now playing" : "")")
    }
}

struct AlbumTile: View {
    let album: MusicAlbum
    let showsTitle: Bool
    var isPlaying = false
    let zoomNamespace: Namespace.ID

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ArtworkView(item: album.artworkItem, cornerRadius: HushStyle.tileCornerRadius)
                .overlay(alignment: .bottomTrailing) {
                    if isPlaying { NowPlayingBadge(size: 24).padding(8) }
                }
                .pageZoomSource(PlayerArtworkTransitionID.albumGridTile(album.id), in: zoomNamespace, cornerRadius: HushStyle.tileCornerRadius)
            if showsTitle {
                VStack(alignment: .leading, spacing: 2) {
                    Text(album.title)
                        .font(.system(size: 15, weight: .regular, design: .serif))
                        .foregroundStyle(HushStyle.ink)
                        .lineLimit(1)
                    Text(album.artist)
                        .font(.system(size: 12.5))
                        .foregroundStyle(HushStyle.muted)
                        .lineLimit(1)
                }
            }
        }
        // VoiceOver still reads the name when titles are hidden.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(album.title), \(album.artist)\(isPlaying ? ", now playing" : "")")
    }
}

struct SongRow: View {
    let item: MPMediaItem
    let isCurrent: Bool
    let artworkNamespace: Namespace.ID

    var body: some View {
        HStack(spacing: 14) {
            songArtwork
                .overlay(alignment: .bottomTrailing) {
                    if isCurrent {
                        NowPlayingBadge(size: 18)
                            .offset(x: 3, y: 3)
                    }
                }
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title ?? "Untitled")
                    .font(.system(size: 16, weight: isCurrent ? .semibold : .medium))
                    .foregroundStyle(HushStyle.ink)
                    .lineLimit(1)
                Text(item.artist ?? "Unknown Artist")
                    .font(.system(size: 13.5))
                    .foregroundStyle(HushStyle.muted)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .frame(height: 64)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var songArtwork: some View {
        let artwork = ArtworkView(item: item, cornerRadius: 6, size: HushStyle.smallArtworkSize)
            .frame(width: 48, height: 48)

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
