import MediaPlayer
import SwiftUI

struct PlayerBar: View {
    @EnvironmentObject private var library: MusicLibraryStore
    @EnvironmentObject private var playback: PlaybackStatus
    let artworkNamespace: Namespace.ID
    let onOpen: () -> Void
    /// Opens the playing song's album or artist (long-press menu).
    let onGoTo: (PlaybackSource) -> Void
    /// How far the bar is being swiped sideways right now. Resets by itself (springing back) when
    /// the finger lifts or the swipe is interrupted, so the bar can never get stuck half-way.
    @GestureState(resetTransaction: Transaction(animation: .spring(response: 0.35, dampingFraction: 0.8)))
    private var dragOffset: CGFloat = 0
    /// True while a finger is dragging the bar at all (any direction).
    @GestureState private var isSwiping = false
    /// Where the bar flies off to once a swipe closes it.
    @State private var flyAwayOffset: CGFloat = 0
    @State private var isClosing = false
    /// Whether the current swipe has gone far enough to close on release (for the "click" haptic).
    @State private var isPastCloseThreshold = false
    /// Lifting your finger at the end of a swipe also counts as a tap on whatever is under it. Taps
    /// that arrive this soon after a swipe are ignored, so a swipe never opens the player, skips,
    /// or pauses.
    @State private var ignoreTapsUntil = Date.distantPast

    private static let closeDistance: CGFloat = 110

    /// Fades the bar as it's swiped away (down to half at most).
    private var swipeOpacity: Double {
        let distance = Double(abs(isClosing ? flyAwayOffset : dragOffset))
        return 1 - min(distance / 380, 0.5)
    }

    /// Runs a button's action only if it's a real tap — not the tail end of a swipe.
    private func tap(_ action: () -> Void) {
        guard !isSwiping, !isClosing, Date() >= ignoreTapsUntil else { return }
        action()
    }

    var body: some View {
        HStack(spacing: 11) {
            Button {
                tap(onOpen)
            } label: {
                HStack(spacing: 11) {
                    ArtworkView(item: library.currentItem, cornerRadius: 10, size: CGSize(width: 120, height: 120))
                        .frame(width: 46, height: 46)
                        .zoomSource(PlayerArtworkTransitionID.miniPlayer, in: artworkNamespace)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(library.currentItem?.title ?? "Not playing")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(HushStyle.ink)
                            .lineLimit(1)
                        Text(library.currentItem?.artist ?? "Choose something to listen to")
                            .font(.system(size: 11))
                            .foregroundStyle(HushStyle.muted)
                            .lineLimit(1)
                    }
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(HushStyle.muted)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open full-screen player for \(library.currentItem?.title ?? "current song")")
            .accessibilityHint("Shows the full artwork and playback controls")

            Spacer(minLength: 0)
            // 40pt-wide hit areas (the icons alone were ~13pt and easy to miss).
            Button { tap { library.skipBack() } } label: {
                Image(systemName: "backward.end.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(HushStyle.muted)
                    .frame(width: 40, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Previous track")
            Button { tap { library.togglePlayback() } } label: {
                Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(HushStyle.paper)
                    .popSymbolSwap(isPlaying: playback.isPlaying)
                    .frame(width: 37, height: 37)
                    .background(HushStyle.gold, in: Circle())
            }
            .buttonStyle(PopButtonStyle())
            .accessibilityLabel(playback.isPlaying ? "Pause" : "Play")
            Button { tap { library.skipForward() } } label: {
                Image(systemName: "forward.end.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(HushStyle.muted)
                    .frame(width: 40, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Next track")
        }
        .padding(.leading, 11)
        .padding(.trailing, 6)
        .padding(.vertical, 7)
        .miniPlayerBackground()
        // Thin gold progress line along the bottom edge — drawn over the glass, not part of it.
        .overlay(alignment: .bottom) {
            MiniPlayerProgress()
                .padding(.horizontal, 18)
                .padding(.bottom, 3)
        }
        // Swiped sideways, the bar follows your finger and fades as it goes; far enough, a light
        // click says "let go to close". Let go and it flies off that way and the music stops.
        .offset(x: isClosing ? flyAwayOffset : dragOffset)
        .opacity(swipeOpacity)

        // Swipe up to open the full player (like Apple Music); swipe left or right to put it away.
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
                    guard !isClosing else { return }
                    let horizontal = value.translation.width
                    let isPast = abs(horizontal) > abs(value.translation.height) && abs(horizontal) > Self.closeDistance
                    if isPast != isPastCloseThreshold {
                        isPastCloseThreshold = isPast
                        Haptics.selection()
                    }
                }
                .onEnded { value in
                    // Whatever this swipe does, the finger lifting at its end is not a tap.
                    ignoreTapsUntil = Date().addingTimeInterval(0.4)
                    isPastCloseThreshold = false
                    guard !isClosing else { return }
                    let horizontal = value.translation.width
                    let vertical = value.translation.height
                    let flick = value.predictedEndTranslation.width
                    if abs(vertical) > abs(horizontal), vertical < -30 {
                        onOpen()
                    } else if abs(horizontal) > abs(vertical), abs(horizontal) > Self.closeDistance || abs(flick) > 280 {
                        // Off the screen the way you swiped (from right where your finger left it),
                        // then the music stops.
                        flyAwayOffset = horizontal
                        isClosing = true
                        let direction: CGFloat = (horizontal + flick) >= 0 ? 1 : -1
                        withAnimation(.easeOut(duration: 0.22)) { flyAwayOffset = direction * 520 }
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 220_000_000)
                            library.closePlayer()
                        }
                    }
                    // Otherwise the bar springs back by itself (dragOffset resets).
                }
        )
        .onChange(of: isSwiping) { _, swiping in
            // A swipe interrupted by the system (e.g. the long-press menu) leaves no stale state.
            if !swiping { isPastCloseThreshold = false }
        }
        .contextMenu { miniPlayerMenu }
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
    /// A smooth, dark frosted bar: the library blurs softly beneath it. Deliberately not Liquid
    /// Glass — the glass rim and edge refraction showed up as stray lines along the bottom and right
    /// edges (bending the grid's tile edges beneath it). Frosted has clean edges everywhere.
    func miniPlayerBackground() -> some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        return self
            .background {
                ZStack {
                    shape.fill(.ultraThinMaterial)
                    shape.fill(HushStyle.surface.opacity(0.78))
                }
            }
            .shadow(color: .black.opacity(0.35), radius: 16, x: 0, y: 6)
    }
}

/// How far into the song you are, as a hairline along the bottom of the mini player.
/// Updates once a second while playing, and stops updating while paused.
private struct MiniPlayerProgress: View {
    @EnvironmentObject private var library: MusicLibraryStore
    @EnvironmentObject private var playback: PlaybackStatus

    var body: some View {
        TimelineView(.animation(minimumInterval: 1, paused: !playback.isPlaying)) { _ in
            GeometryReader { geometry in
                // Just the gold progress — no grey track line along the bottom of the bar.
                Capsule()
                    .fill(HushStyle.gold)
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
