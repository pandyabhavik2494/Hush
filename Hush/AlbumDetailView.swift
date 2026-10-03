import MediaPlayer
import SwiftUI

struct AlbumDetailView: View {
    @EnvironmentObject private var library: MusicLibraryStore
    let album: MusicAlbum
    let artworkNamespace: Namespace.ID
    let onPlay: (MPMediaItem, [MPMediaItem], String) -> Void
    let onShuffle: () -> Void
    /// Opens an artist's page (the album artist's name is a link, like Apple Music).
    var onOpenArtist: ((String) -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The playing song is brought into view once, when the page first opens — not every time
    /// you come Back to it.
    @State private var hasRevealedCurrentTrack = false

    var body: some View {
        ZStack {
            HushStyle.paper.ignoresSafeArea()
            // The album's colors light the top of the page, behind the glass controls.
            AmbientArtworkGlow(item: album.artworkItem, height: 540, strength: 0.72)
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        albumHeaderArtwork
                        .shadow(color: .black.opacity(0.12), radius: 20, x: 0, y: 9)
                        .padding(.horizontal, 28)
                        .padding(.top, 10)
                        VStack(alignment: .leading, spacing: 7) {
                            Text(album.title)
                                .font(.system(size: 29, weight: .regular, design: .serif))
                                .tracking(-0.5)
                                .foregroundStyle(HushStyle.ink)
                            HStack(spacing: 7) {
                                albumArtistLink
                                Text("·")
                                Text(albumDetails)
                                    .lineLimit(1)
                            }
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(HushStyle.muted)
                        }
                        .padding(.horizontal, 28)
                        .padding(.top, 22)
                        HStack(spacing: 10) {
                            Button {
                                guard let first = album.items.first else { return }
                                onPlay(first, album.items, PlayerArtworkTransitionID.albumPlayButton(first.persistentID))
                            } label: {
                                HStack(spacing: 9) {
                                    Image(systemName: "play.fill").font(.system(size: 12, weight: .bold))
                                    Text("Play album").font(.system(size: 14, weight: .semibold, design: .rounded))
                                }
                                .foregroundStyle(HushStyle.paper)
                                .padding(.horizontal, 18)
                                .frame(height: 43)
                                .background(HushStyle.gold, in: Capsule())
                            }
                            .buttonStyle(PopButtonStyle())

                            Button(action: onShuffle) {
                                HStack(spacing: 8) {
                                    Image(systemName: "shuffle").font(.system(size: 12, weight: .bold))
                                    Text("Shuffle").font(.system(size: 14, weight: .semibold, design: .rounded))
                                }
                                .foregroundStyle(HushStyle.gold)
                                .padding(.horizontal, 18)
                                .frame(height: 43)
                                .hushGlassBackground(Capsule())
                                .contentShape(Capsule())
                            }
                            // Plain press style: the glass never scales or animates.
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 28)
                        .padding(.top, 18)
                        VStack(spacing: 0) {
                            ForEach(Array(album.items.enumerated()), id: \.element.persistentID) { index, item in
                                HStack(spacing: 8) {
                                    Button {
                                        onPlay(item, album.items, PlayerArtworkTransitionID.albumTrack(item.persistentID))
                                    } label: {
                                        let isCurrent = library.currentItem?.persistentID == item.persistentID
                                        HStack(spacing: 13) {
                                            TrackNumberLabel(number: index + 1, isCurrent: isCurrent)
                                                .frame(width: 24, alignment: .leading)
                                            albumTrackArtwork(item)
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(item.title ?? "Untitled")
                                                    .font(.system(size: 14, weight: .medium, design: .rounded))
                                                    .foregroundStyle(isCurrent ? HushStyle.gold : HushStyle.ink)
                                                    .lineLimit(1)
                                                Text(item.artist ?? album.artist)
                                                    .font(.system(size: 12))
                                                    .foregroundStyle(HushStyle.muted)
                                                    .lineLimit(1)
                                            }
                                            Spacer(minLength: 6)
                                            if item.playCount > 0 {
                                                Text("\(item.playCount)")
                                                    .font(.system(size: 11, design: .rounded).monospacedDigit())
                                                    .foregroundStyle(HushStyle.muted.opacity(0.8))
                                            }
                                        }
                                        .padding(.vertical, 12)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .frame(maxWidth: .infinity)
                                    .queueMenu([item])
                                }
                                .id(item.persistentID)
                                if index < album.items.count - 1 {
                                    Rectangle().fill(HushStyle.line.opacity(0.75)).frame(height: 0.6).padding(.leading, 37)
                                }
                            }
                        }
                        .padding(.horizontal, 28)
                        .padding(.top, 22)
                        .padding(.bottom, 24)
                    }
                }
                .miniPlayerClearance()
                .onAppear { revealCurrentTrack(with: proxy) }
            }
        }
        // System back button (gold chevron, no title) keeps the standard swipe-from-edge to go back.
        // The navigation bar is left transparent, so on iOS 26 the back button floats as Liquid
        // Glass over the cover's glow.
        .toolbarRole(.editor)
    }

    /// Opening the album that's playing brings its current song into view — only when that song
    /// is below the first screen, and only once the page has finished opening.
    private func revealCurrentTrack(with proxy: ScrollViewProxy) {
        guard !hasRevealedCurrentTrack else { return }
        hasRevealedCurrentTrack = true
        guard let currentID = library.currentItem?.persistentID,
              let index = album.items.firstIndex(where: { $0.persistentID == currentID }),
              index >= 4 else { return }
        let animation: Animation? = reduceMotion ? nil : .smooth(duration: 0.6)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 450_000_000)
            withAnimation(animation) {
                proxy.scrollTo(currentID, anchor: .center)
            }
        }
    }

    /// The album artist, in gold when it leads to their page; several artists → a short menu.
    @ViewBuilder
    private var albumArtistLink: some View {
        let credited = onOpenArtist == nil ? [] : library.creditedArtists(in: album.artist)
        if credited.count == 1, let artist = credited.first {
            Button {
                onOpenArtist?(artist.id)
            } label: {
                Text(album.artist)
                    .lineLimit(1)
                    .foregroundStyle(HushStyle.gold)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the artist")
        } else if credited.count > 1 {
            Menu {
                ForEach(credited) { artist in
                    Button(artist.name) {
                        onOpenArtist?(artist.id)
                    }
                }
            } label: {
                Text(album.artist)
                    .lineLimit(1)
                    .foregroundStyle(HushStyle.gold)
            }
            .accessibilityHint("Choose an artist to open")
        } else {
            Text(album.artist)
                .lineLimit(1)
        }
    }

    /// "12 songs · 42 min · 2019" (length and year when known).
    private var albumDetails: String {
        var parts = [album.trackCount == 1 ? "1 song" : "\(album.trackCount) songs"]
        if let length = HushStyle.durationText(album.items.reduce(0) { $0 + $1.playbackDuration }) {
            parts.append(length)
        }
        if let released = album.items.lazy.compactMap(\.releaseDate).first {
            parts.append(String(Calendar.current.component(.year, from: released)))
        }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var albumHeaderArtwork: some View {
        if let firstTrack = album.items.first {
            if #available(iOS 18.0, *) {
                ArtworkView(item: album.artworkItem, cornerRadius: 22, size: CGSize(width: 900, height: 900))
                    .matchedTransitionSource(
                        id: PlayerArtworkTransitionID.albumPlayButton(firstTrack.persistentID),
                        in: artworkNamespace
                    )
            } else {
                ArtworkView(item: album.artworkItem, cornerRadius: 22, size: CGSize(width: 900, height: 900))
            }
        } else {
            ArtworkView(item: album.artworkItem, cornerRadius: 22, size: CGSize(width: 900, height: 900))
        }
    }

    @ViewBuilder
    private func albumTrackArtwork(_ item: MPMediaItem) -> some View {
        // Every track shows the album's cover: one image for the whole page (usually already
        // decoded for the grid tile) instead of a separate fetch per track while the page slides in.
        let artwork = ArtworkView(item: album.artworkItem ?? item, cornerRadius: 8, size: CGSize(width: 120, height: 120))
            .frame(width: 42, height: 42)

        if #available(iOS 18.0, *) {
            artwork.matchedTransitionSource(
                id: PlayerArtworkTransitionID.albumTrack(item.persistentID),
                in: artworkNamespace
            )
        } else {
            artwork
        }
    }
}

/// Track number, or the gold now-playing bars when that song is the one playing.
struct TrackNumberLabel: View {
    let number: Int
    let isCurrent: Bool

    var body: some View {
        if isCurrent {
            NowPlayingBars(height: 11)
        } else {
            Text(String(format: "%02d", number))
                .font(.system(size: 11, weight: .medium, design: .rounded).monospacedDigit())
                .foregroundStyle(HushStyle.muted.opacity(0.8))
        }
    }
}

/// Hush's now-playing mark: three slim bars that sway while music plays and settle, still, when
/// it's paused. Holds still with Reduce Motion. Only ever on screen for the one playing song, so
/// the per-frame redraw is tiny.
struct NowPlayingBars: View {
    @EnvironmentObject private var playback: PlaybackStatus
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var color: Color = HushStyle.gold
    var height: CGFloat = 11

    /// Each bar's own tempo and phase (so they never move in lockstep) and its height at rest.
    private static let speeds: [Double] = [8.2, 10.6, 7.1]
    private static let phases: [Double] = [0.0, 1.9, 3.4]
    private static let resting: [CGFloat] = [0.45, 0.85, 0.6]

    var body: some View {
        let isMoving = playback.isPlaying && !reduceMotion
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !isMoving)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            HStack(alignment: .bottom, spacing: max(1.5, height * 0.14)) {
                ForEach(0..<3, id: \.self) { index in
                    Capsule()
                        .fill(color)
                        .frame(width: max(2, height * 0.2), height: height * level(index, time: time, isMoving: isMoving))
                }
            }
            .frame(height: height, alignment: .bottom)
        }
        .animation(.easeInOut(duration: 0.3), value: isMoving)
        .accessibilityElement()
        .accessibilityLabel(playback.isPlaying ? "Now playing" : "Paused")
    }

    private func level(_ index: Int, time: TimeInterval, isMoving: Bool) -> CGFloat {
        guard isMoving else { return Self.resting[index] }
        let speed = Self.speeds[index]
        let phase = Self.phases[index]
        // Two slow waves per bar: organic, never a mechanical bounce.
        let wave = sin(time * speed + phase) * 0.6 + sin(time * speed * 0.53 + phase * 2) * 0.4
        return 0.3 + 0.7 * CGFloat((wave + 1) / 2)
    }
}

/// The now-playing mark on a cover: the bars on a small gold disc.
struct NowPlayingBadge: View {
    var size: CGFloat = 20

    var body: some View {
        NowPlayingBars(color: HushStyle.paper, height: size * 0.46)
            .frame(width: size, height: size)
            .background(HushStyle.gold, in: Circle())
            .shadow(color: .black.opacity(0.3), radius: 3, x: 0, y: 1)
    }
}

// MARK: - Artist page

/// Everything by one artist: their albums (newest first), and under each album only the songs
/// credited to them. Play / Shuffle cover all their songs; tapping a song plays on through the rest.
struct ArtistDetailView: View {
    @EnvironmentObject private var library: MusicLibraryStore
    let artist: MusicArtist
    let artworkNamespace: Namespace.ID
    let onPlay: (MPMediaItem, [MPMediaItem], String) -> Void
    let onShuffle: () -> Void
    let onOpenAlbum: (UInt64) -> Void

    private var transitionID: String { PlayerArtworkTransitionID.artistHeader(artist.id) }

    var body: some View {
        let allSongs = artist.allSongs
        ZStack {
            HushStyle.paper.ignoresSafeArea()
            // The artist's featured cover lights the top of the page, behind the glass controls.
            AmbientArtworkGlow(item: artist.artworkItem, height: 520, strength: 0.72)
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    ArtistPhoto(artist: artist)
                        .frame(width: 190, height: 190)
                        .zoomSource(transitionID, in: artworkNamespace)
                        .shadow(color: .black.opacity(0.22), radius: 18, x: 0, y: 9)
                        .padding(.top, 8)

                    Text(artist.name)
                        .font(.system(size: 29, weight: .regular, design: .serif))
                        .tracking(-0.5)
                        .foregroundStyle(HushStyle.ink)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 26)
                        .padding(.top, 20)

                    Text(details)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(HushStyle.muted)
                        .padding(.top, 7)

                    HStack(spacing: 10) {
                        Button {
                            guard let first = allSongs.first else { return }
                            onPlay(first, allSongs, transitionID)
                        } label: {
                            Label("Play", systemImage: "play.fill")
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundStyle(HushStyle.paper)
                                .padding(.horizontal, 20)
                                .frame(height: 44)
                                .background(HushStyle.gold, in: Capsule())
                        }
                        .buttonStyle(PopButtonStyle())

                        Button(action: onShuffle) {
                            Label("Shuffle", systemImage: "shuffle")
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundStyle(HushStyle.gold)
                                .padding(.horizontal, 20)
                                .frame(height: 44)
                                .hushGlassBackground(Capsule())
                                .contentShape(Capsule())
                        }
                        // Plain press style: the glass never scales or animates.
                        .buttonStyle(.plain)

                        // Favorite: favorites come first on the Artists tab.
                        let isFavorite = library.isFavorite(artistID: artist.id)
                        Button {
                            library.toggleFavorite(artistID: artist.id)
                        } label: {
                            Image(systemName: isFavorite ? "heart.fill" : "heart")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(HushStyle.gold)
                                .contentTransition(.symbolEffect(.replace))
                                .frame(width: 44, height: 44)
                                .hushGlassBackground(Circle())
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(isFavorite ? "Remove from Favorites" : "Add to Favorites")
                    }
                    .padding(.top, 19)

                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(artist.albums) { album in
                            albumHeader(album)
                            ForEach(Array(album.songs.enumerated()), id: \.element.persistentID) { index, item in
                                songRow(item, fallbackNumber: index + 1, queue: allSongs)
                                if index < album.songs.count - 1 {
                                    Rectangle()
                                        .fill(HushStyle.line.opacity(0.55))
                                        .frame(height: 0.6)
                                        .padding(.leading, 36)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 18)
                }
                .padding(.bottom, 28)
            }
            .miniPlayerClearance()
        }
        // System back button (gold chevron, no title); transparent bar so it floats as glass.
        .toolbarRole(.editor)
    }

    /// "4 albums · 37 songs".
    private var details: String {
        let albums = artist.albums.count == 1 ? "1 album" : "\(artist.albums.count) albums"
        let songs = artist.songCount == 1 ? "1 song" : "\(artist.songCount) songs"
        return "\(albums) · \(songs)"
    }

    /// Album cover, title and year; tapping opens the full album.
    private func albumHeader(_ album: ArtistAlbum) -> some View {
        Button {
            onOpenAlbum(album.id)
        } label: {
            HStack(spacing: 12) {
                ArtworkView(item: album.artworkItem, cornerRadius: 8, size: CGSize(width: 150, height: 150))
                    .frame(width: 56, height: 56)
                    // The album page zooms out of this cover.
                    .pageZoomSource(
                        PlayerArtworkTransitionID.artistPageAlbum(artistID: artist.id, albumID: album.id),
                        in: artworkNamespace,
                        cornerRadius: 8
                    )
                VStack(alignment: .leading, spacing: 3) {
                    Text(album.title)
                        .font(.system(size: 16, weight: .regular, design: .serif))
                        .foregroundStyle(HushStyle.ink)
                        .lineLimit(1)
                    Text(albumSubtitle(album))
                        .font(.system(size: 12))
                        .foregroundStyle(HushStyle.muted)
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(HushStyle.muted.opacity(0.8))
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .queueMenu(album.songs)
        .accessibilityLabel("Album \(album.title)")
        .accessibilityHint("Opens the full album")
        .padding(.top, 14)
    }

    private func albumSubtitle(_ album: ArtistAlbum) -> String {
        var parts: [String] = []
        if let year = album.year { parts.append(String(year)) }
        parts.append(album.songs.count == 1 ? "1 song" : "\(album.songs.count) songs")
        return parts.joined(separator: " · ")
    }

    private func songRow(_ item: MPMediaItem, fallbackNumber: Int, queue: [MPMediaItem]) -> some View {
        let isCurrent = library.currentItem?.persistentID == item.persistentID
        let number = item.albumTrackNumber > 0 ? item.albumTrackNumber : fallbackNumber
        // Show the full credit when others are on the song too (e.g. a duet).
        let credit: String? = item.artist.flatMap { full -> String? in
            ArtistCredits.key(for: full) == artist.id ? nil : full
        }
        return Button {
            onPlay(item, queue, transitionID)
        } label: {
            HStack(spacing: 12) {
                TrackNumberLabel(number: number, isCurrent: isCurrent)
                    .frame(width: 24, alignment: .leading)
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title ?? "Untitled")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(isCurrent ? HushStyle.gold : HushStyle.ink)
                        .lineLimit(1)
                    if let credit {
                        Text(credit)
                            .font(.system(size: 11))
                            .foregroundStyle(HushStyle.muted)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 6)
                if item.playCount > 0 {
                    Text("\(item.playCount)")
                        .font(.system(size: 11, design: .rounded).monospacedDigit())
                        .foregroundStyle(HushStyle.muted.opacity(0.8))
                }
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .queueMenu([item])
    }
}
