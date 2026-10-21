import MediaPlayer
import SwiftUI

struct PlayerBar: View {
    @EnvironmentObject private var library: MusicLibraryStore
    @EnvironmentObject private var playback: PlaybackStatus
    let artworkNamespace: Namespace.ID
    let onOpen: () -> Void
    /// Opens the playing song's album or artist (long-press menu).
    let onGoTo: (PlaybackSource) -> Void
    /// How far the bar is being swiped sideways right now. Springs back by itself when the finger
    /// lifts or the swipe is interrupted, so the bar can never get stuck half-way.
    @GestureState(resetTransaction: Transaction(animation: .spring(response: 0.35, dampingFraction: 0.8)))
    private var dragOffset: CGFloat = 0
    /// True while a finger is dragging the bar at all (any direction).
    @GestureState private var isSwiping = false
    /// Whether the current swipe has gone far enough to skip on release (for the light haptic).
    @State private var isPastSkipThreshold = false
    /// Lifting your finger at the end of a swipe also counts as a tap on whatever is under it. Taps
    /// that arrive this soon after a swipe are ignored, so a swipe never opens the player or pauses.
    @State private var ignoreTapsUntil = Date.distantPast

    private static let skipDistance: CGFloat = 64

    /// Runs a button's action only if it's a real tap — not the tail end of a swipe.
    private func tap(_ action: () -> Void) {
        guard !isSwiping, Date() >= ignoreTapsUntil else { return }
        action()
    }

    var body: some View {
        HStack(spacing: 12) {
            Button {
                tap(onOpen)
            } label: {
                HStack(spacing: 12) {
                    ArtworkView(item: library.currentItem, cornerRadius: 7, size: CGSize(width: 120, height: 120))
                        .frame(width: 44, height: 44)
                        .zoomSource(PlayerArtworkTransitionID.miniPlayer, in: artworkNamespace)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(library.currentItem?.title ?? "Not playing")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(HushStyle.ink)
                            .lineLimit(1)
                        Text(library.currentItem?.artist ?? "Choose something to listen to")
                            .font(.system(size: 13))
                            .foregroundStyle(HushStyle.muted)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open full-screen player for \(library.currentItem?.title ?? "current song")")
            .accessibilityHint("Shows the full artwork and playback controls")

            Button { tap { library.togglePlayback() } } label: {
                Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(HushStyle.ink)
                    .popSymbolSwap(isPlaying: playback.isPlaying)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PopButtonStyle())
            .accessibilityLabel(playback.isPlaying ? "Pause" : "Play")
        }
        .padding(.leading, 10)
        .padding(.trailing, 6)
        .frame(height: 64)
        .miniPlayerBackground()
        // Progress along the bottom edge.
        .overlay(alignment: .bottom) {
            MiniPlayerProgress()
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        // Follows a sideways swipe a little, then springs back.
        .offset(x: dragOffset * 0.35)

        // Swipe left for the next song, right for the previous one, up to open the full player.
        .simultaneousGesture(
            DragGesture(minimumDistance: 14)
                .updating($dragOffset) { value, offset, _ in
                    let horizontal = value.translation.width
                    offset = abs(horizontal) > abs(value.translation.height) ? horizontal : 0
                }
                .updating($isSwiping) { _, swiping, _ in
                    swiping = true
                }
                .onChanged { value in
                    let horizontal = value.translation.width
                    let isPast = abs(horizontal) > abs(value.translation.height) && abs(horizontal) > Self.skipDistance
                    if isPast != isPastSkipThreshold {
                        isPastSkipThreshold = isPast
                        if isPast { Haptics.tap() }
                    }
                }
                .onEnded { value in
                    // Whatever this swipe does, the finger lifting at its end is not a tap.
                    ignoreTapsUntil = Date().addingTimeInterval(0.4)
                    isPastSkipThreshold = false
                    let horizontal = value.translation.width
                    let vertical = value.translation.height
                    let flick = value.predictedEndTranslation.width
                    if abs(vertical) > abs(horizontal), vertical < -30 {
                        onOpen()
                    } else if abs(horizontal) > abs(vertical), abs(horizontal) > Self.skipDistance || abs(flick) > 240 {
                        if horizontal + flick < 0 {
                            library.skipForward()
                        } else {
                            library.skipBack()
                        }
                    }
                }
        )
        .onChange(of: isSwiping) { _, swiping in
            // A swipe interrupted by the system (e.g. the long-press menu) leaves no stale state.
            if !swiping { isPastSkipThreshold = false }
        }
        .contextMenu { miniPlayerMenu }
        .accessibilityAction(named: "Next song") { library.skipForward() }
        .accessibilityAction(named: "Previous song") { library.skipBack() }
        .accessibilityAction(named: "Close player") { library.closePlayer() }
    }

    /// Long-press menu: jump to the song's album or artist, or stop and close the player.
    @ViewBuilder
    private var miniPlayerMenu: some View {
        if let album = library.album(for: library.currentItem) {
            Button {
                onGoTo(.album(album.id))
            } label: {
                Label("Go to Album", systemImage: "square.stack")
            }
        }
        ForEach(library.creditedArtists(in: library.currentItem?.artist)) { artist in
            Button {
                onGoTo(.artist(artist.id))
            } label: {
                Label("Go to \(artist.name)", systemImage: "music.mic")
            }
        }
        Divider()
        Button(role: .destructive) {
            library.closePlayer()
        } label: {
            Label("Stop and Close Player", systemImage: "xmark.circle")
        }
    }
}

private extension View {
    /// A solid dark card with a faint edge: no glass, nothing shows through.
    func miniPlayerBackground() -> some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        return self
            .background(HushStyle.card, in: shape)
            .overlay(shape.strokeBorder(HushStyle.ink.opacity(0.06), lineWidth: 1))
    }
}

/// How far into the song you are, as a 2 pt line along the bottom edge of the mini player.
/// Updates once a second while playing, and stops updating while paused.
private struct MiniPlayerProgress: View {
    @EnvironmentObject private var library: MusicLibraryStore
    @EnvironmentObject private var playback: PlaybackStatus

    var body: some View {
        TimelineView(.animation(minimumInterval: 1, paused: !playback.isPlaying)) { _ in
            GeometryReader { geometry in
                // Just the progress — no track line along the bottom of the bar.
                Rectangle()
                    .fill(HushStyle.ink)
                    .frame(width: geometry.size.width * progress)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(height: 2)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var progress: CGFloat {
        let duration = library.currentItem?.playbackDuration ?? 0
        guard duration.isFinite, duration > 0 else { return 0 }
        return CGFloat(min(max(library.currentPlaybackTime / duration, 0), 1))
    }
}
