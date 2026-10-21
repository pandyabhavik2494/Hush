import MediaPlayer
import SwiftUI
import UIKit

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
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        albumHeaderArtwork
                            .padding(.horizontal, 52)
                            .padding(.top, 10)
                        VStack(spacing: 6) {
                            Text(album.title)
                                .font(.system(size: 31, weight: .regular, design: .serif))
                                .tracking(-0.3)
                                .foregroundStyle(HushStyle.ink)
                                .multilineTextAlignment(.center)
                            albumArtistLink
                                .font(.system(size: 16, weight: .medium))
                            Text(albumDetails)
                                .font(.system(size: 13))
                                .foregroundStyle(HushStyle.muted)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 20)
                        .padding(.top, 26)
                        PlayShuffleButtons(
                            onPlay: {
                                guard let first = album.items.first else { return }
                                onPlay(first, album.items, PlayerArtworkTransitionID.albumPlayButton(first.persistentID))
                            },
                            onShuffle: onShuffle
                        )
                        .padding(.horizontal, 20)
                        .padding(.top, 24)
                        LazyVStack(spacing: 0) {
                            let currentID = library.currentItem?.persistentID
                            ForEach(Array(album.items.enumerated()), id: \.element.persistentID) { index, item in
                                let isCurrent = currentID == item.persistentID
                                Button {
                                    // The player grows out of the album cover.
                                    onPlay(item, album.items, PlayerArtworkTransitionID.albumPlayButton(album.items.first?.persistentID ?? item.persistentID))
                                } label: {
                                    HStack(spacing: 16) {
                                        TrackNumberLabel(number: index + 1, isCurrent: isCurrent)
                                            .frame(width: 22, alignment: .trailing)
                                        Text(item.title ?? "Untitled")
                                            .font(.system(size: 16, weight: isCurrent ? .semibold : .regular))
                                            .foregroundStyle(HushStyle.ink)
                                            .lineLimit(1)
                                        Spacer(minLength: 0)
                                    }
                                    .frame(height: 52)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .queueMenu([item])
                                .id(item.persistentID)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                        .padding(.bottom, 24)
                    }
                }
                .miniPlayerClearance()
                .onAppear { revealCurrentTrack(with: proxy) }
            }
        }
        .plainPageHeader {
            Button {
                library.playNext(album.items)
            } label: {
                Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward")
            }
            Button {
                library.addToQueue(album.items)
            } label: {
                Label("Add to Queue", systemImage: "text.line.last.and.arrowtriangle.forward")
            }
        }
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

    /// The album artist, which leads to their page; several artists → a short menu.
    @ViewBuilder
    private var albumArtistLink: some View {
        let credited = onOpenArtist == nil ? [] : library.creditedArtists(in: album.artist)
        if credited.count == 1, let artist = credited.first {
            Button {
                onOpenArtist?(artist.id)
            } label: {
                Text(album.artist)
                    .lineLimit(1)
                    .foregroundStyle(HushStyle.ink)
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
                    .foregroundStyle(HushStyle.ink)
            }
            .accessibilityHint("Choose an artist to open")
        } else {
            Text(album.artist)
                .lineLimit(1)
                .foregroundStyle(HushStyle.ink)
        }
    }

    /// "2019 · 12 songs" (the year when known).
    private var albumDetails: String {
        var parts: [String] = []
        if let released = album.items.lazy.compactMap(\.releaseDate).first {
            parts.append(String(Calendar.current.component(.year, from: released)))
        }
        parts.append(album.trackCount == 1 ? "1 song" : "\(album.trackCount) songs")
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var albumHeaderArtwork: some View {
        if let firstTrack = album.items.first {
            if #available(iOS 18.0, *) {
                ArtworkView(item: album.artworkItem, cornerRadius: 12, size: CGSize(width: 900, height: 900))
                    .matchedTransitionSource(
                        id: PlayerArtworkTransitionID.albumPlayButton(firstTrack.persistentID),
                        in: artworkNamespace
                    )
            } else {
                ArtworkView(item: album.artworkItem, cornerRadius: 12, size: CGSize(width: 900, height: 900))
            }
        } else {
            ArtworkView(item: album.artworkItem, cornerRadius: 12, size: CGSize(width: 900, height: 900))
        }
    }
}

/// Play (filled) and Shuffle (outlined), side by side and equally wide: the album, playlist and
/// artist pages all use these.
struct PlayShuffleButtons: View {
    let onPlay: () -> Void
    let onShuffle: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onPlay) {
                HStack(spacing: 8) {
                    Image(systemName: "play.fill").font(.system(size: 14, weight: .bold))
                    Text("Play").font(.system(size: 16, weight: .semibold))
                }
                .foregroundStyle(Color.black)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(HushStyle.ink, in: Capsule())
            }
            .buttonStyle(PopButtonStyle())

            Button(action: onShuffle) {
                HStack(spacing: 8) {
                    Image(systemName: "shuffle").font(.system(size: 15, weight: .semibold))
                    Text("Shuffle").font(.system(size: 16, weight: .semibold))
                }
                .foregroundStyle(HushStyle.ink)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .overlay(Capsule().strokeBorder(HushStyle.outline, lineWidth: 1))
                .contentShape(Capsule())
            }
            .buttonStyle(PopButtonStyle())
        }
    }
}

/// A plain black bar at the top of a page: back on the left, a "more" menu on the right. The page
/// scrolls under it. Replaces the system bar (and its glass back button).
private struct PlainPageHeader<MenuContent: View>: ViewModifier {
    @Environment(\.dismiss) private var dismiss
    let menu: MenuContent

    func body(content: Content) -> some View {
        content
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) {
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(HushStyle.ink)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Back")
                    Spacer()
                    Menu {
                        menu
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 19, weight: .medium))
                            .foregroundStyle(HushStyle.ink)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("More")
                }
                .padding(.horizontal, 8)
                .frame(height: 44)
                .background(HushStyle.paper)
            }
    }
}

/// The pages hide the system bar for their plain header; this keeps the swipe from the left edge
/// going back.
extension UINavigationController: @retroactive UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        viewControllers.count > 1
    }
}

extension View {
    /// See `PlainPageHeader`.
    func plainPageHeader<MenuContent: View>(@ViewBuilder menu: () -> MenuContent) -> some View {
        modifier(PlainPageHeader(menu: menu()))
    }
}

/// Track number, or the accent now-playing bars when that song is the one playing.
struct TrackNumberLabel: View {
    let number: Int
    let isCurrent: Bool

    var body: some View {
        if isCurrent {
            NowPlayingBars(height: 13)
        } else {
            Text("\(number)")
                .font(.system(size: 15).monospacedDigit())
                .foregroundStyle(HushStyle.muted)
        }
    }
}

/// Hush's now-playing mark: three slim bars that sway while music plays and settle, still, when
/// it's paused. Holds still with Reduce Motion. Only ever on screen for the one playing song, so
/// the per-frame redraw is tiny.
struct NowPlayingBars: View {
    @EnvironmentObject private var playback: PlaybackStatus
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var color: Color = HushStyle.accent
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

/// The now-playing mark on a cover: the bars on a small accent disc.
struct NowPlayingBadge: View {
    var size: CGFloat = 20

    var body: some View {
        NowPlayingBars(color: HushStyle.paper, height: size * 0.46)
            .frame(width: size, height: size)
            .background(HushStyle.accent, in: Circle())
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

                    PlayShuffleButtons(
                        onPlay: {
                            guard let first = allSongs.first else { return }
                            onPlay(first, allSongs, transitionID)
                        },
                        onShuffle: onShuffle
                    )
                    .padding(.horizontal, 20)
                    .padding(.top, 24)

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
        .plainPageHeader {
            // Favorites come first on the Artists tab.
            let isFavorite = library.isFavorite(artistID: artist.id)
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
                library.playNext(allSongs)
            } label: {
                Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward")
            }
            Button {
                library.addToQueue(allSongs)
            } label: {
                Label("Add to Queue", systemImage: "text.line.last.and.arrowtriangle.forward")
            }
        }
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
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(HushStyle.ink)
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
                        .font(.system(size: 11).monospacedDigit())
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
