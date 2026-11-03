import CoreImage
import MediaPlayer
import SwiftUI
import UIKit

/// The player, as on Hush for Android: the background drifts slowly in the cover's own colours, the
/// cover sits framed with a soft shadow and sinks a little while paused, the title and artist sit
/// left with a "…" menu, then the scrubber, the transport, and shuffle / Up Next / repeat. The cover
/// gets whatever height the controls leave, so nothing falls off a short phone or at large text
/// sizes. Swipe the cover sideways to change songs, swipe down to close.
struct NowPlayingView: View {
    @EnvironmentObject private var library: MusicLibraryStore
    @EnvironmentObject private var playback: PlaybackStatus
    @State private var showingQueue = false
    let onMinimize: () -> Void
    /// Closes the player and opens this album, artist or playlist.
    let onGoTo: (PlaybackSource) -> Void

    /// The library album the current song belongs to (nil if it can't be found).
    private var currentAlbum: MusicAlbum? {
        library.album(for: library.currentItem)
    }

    private var duration: TimeInterval {
        guard let duration = library.currentItem?.playbackDuration,
              duration.isFinite,
              duration > 0 else { return 0 }
        return duration
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
                .padding(.horizontal, 6)

            // The cover gets the height the controls leave (never the other way round).
            GeometryReader { geometry in
                let side = max(min(geometry.size.width, geometry.size.height), 0)
                PlayerCover(
                    item: library.currentItem,
                    side: side,
                    isPlaying: playback.isPlaying,
                    onNext: library.skipForward,
                    onPrevious: library.skipBack
                )
                .frame(width: geometry.size.width, height: geometry.size.height)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 6)

            trackInformation
                .padding(.leading, 24)
                .padding(.trailing, 12)
                .padding(.top, 18)

            TimelineView(.animation(minimumInterval: 1.0 / 4.0, paused: !playback.isPlaying)) { _ in
                PlaybackScrubber(
                    duration: duration,
                    position: library.currentPlaybackTime,
                    isPlaying: playback.isPlaying,
                    onSeek: library.seek(to:)
                )
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)

            transportControls
                .padding(.top, 8)

            modeControls
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { CoverColorBackdrop(item: library.currentItem).ignoresSafeArea() }
        .toolbar(.hidden, for: .navigationBar)
        .tint(PlayerInk.cream)
        .sheet(isPresented: $showingQueue) {
            UpNextView()
                .environmentObject(library)
                .environmentObject(library.queue)
                .environmentObject(library.playback)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .queueSheetGlass()
        }
    }

    /// Close at the left, a grabber in the middle (the player swipes down to close).
    private var topBar: some View {
        ZStack {
            Capsule()
                .fill(PlayerInk.cream.opacity(0.3))
                .frame(width: 36, height: 5)
                .accessibilityHidden(true)

            HStack {
                Button {
                    onMinimize()
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(PlayerInk.cream)
                        .frame(width: HushStyle.tapTarget + 4, height: HushStyle.tapTarget + 4)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back to library")

                Spacer()
            }
        }
        .frame(height: HushStyle.tapTarget + 4)
    }

    /// The artist name leads to their page (a short menu when several are credited), like Apple Music.
    @ViewBuilder
    private var artistLine: some View {
        let credit = library.currentItem?.artist
        let text = credit ?? "Your music library"
        let credited = library.creditedArtists(in: credit)
        let label = Text(text)
            .font(.system(size: 16))
            .foregroundStyle(PlayerInk.secondary)
            .lineLimit(1)
        if credited.count == 1, let artist = credited.first {
            Button {
                onGoTo(.artist(artist.id))
            } label: {
                label.contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the artist")
        } else if credited.count > 1 {
            Menu {
                ForEach(credited) { artist in
                    Button(artist.name) {
                        onGoTo(.artist(artist.id))
                    }
                }
            } label: {
                label.contentShape(Rectangle())
            }
            .accessibilityHint("Choose an artist to open")
        } else {
            label
        }
    }

    /// Title (serif, shrinking a little to fit), "Artist · Album" links beneath, and the "…" menu.
    private var trackInformation: some View {
        HStack(alignment: .center, spacing: 4) {
            VStack(alignment: .leading, spacing: 6) {
                Text(library.currentItem?.title ?? "Choose something to play")
                    .font(.system(size: 29, weight: .regular, design: .serif))
                    .tracking(-0.3)
                    .foregroundStyle(PlayerInk.cream)
                    .lineLimit(2)
                    .minimumScaleFactor(0.76)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // "Artist · Album": the artist opens their page, the album opens the album.
                HStack(spacing: 6) {
                    artistLine
                        .layoutPriority(1)
                    if let album = currentAlbum {
                        let songAlbumTitle = library.currentItem?.albumTitle ?? ""
                        let albumTitle = songAlbumTitle.isEmpty ? album.title : songAlbumTitle
                        separatorDot
                        Button {
                            onGoTo(.album(album.id))
                        } label: {
                            Text(albumTitle)
                                .font(.system(size: 16))
                                .foregroundStyle(PlayerInk.secondary)
                                .lineLimit(1)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Go to album \(albumTitle)")
                    } else if let albumTitle = library.currentItem?.albumTitle, !albumTitle.isEmpty {
                        separatorDot
                        Text(albumTitle)
                            .font(.system(size: 16))
                            .foregroundStyle(PlayerInk.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if library.currentItem != nil {
                moreMenu
            }
        }
    }

    /// "…": Go to Album, and Go to each credited artist.
    private var moreMenu: some View {
        Menu {
            if let album = currentAlbum {
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
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(PlayerInk.cream)
                .frame(width: HushStyle.tapTarget + 4, height: HushStyle.tapTarget + 4)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("More")
    }

    /// The "·" between the artist and the album.
    private var separatorDot: some View {
        Text("·")
            .font(.system(size: 16))
            .foregroundStyle(PlayerInk.secondary)
            .accessibilityHidden(true)
    }

    /// Previous, play/pause and next, centred.
    private var transportControls: some View {
        HStack(spacing: 40) {
            Button { library.skipBack() } label: {
                Image(systemName: "backward.end.fill")
                    .font(.system(size: 32, weight: .regular))
                    .foregroundStyle(PlayerInk.cream)
                    .frame(width: 60, height: 60)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PopButtonStyle())
            .accessibilityLabel("Previous track")

            Button { library.togglePlayback() } label: {
                Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(PlayerInk.glyph)
                    .popSymbolSwap(isPlaying: playback.isPlaying)
                    .offset(x: playback.isPlaying ? 0 : 2)
                    .frame(width: 76, height: 76)
                    .background(PlayerInk.cream, in: Circle())
            }
            .buttonStyle(PopButtonStyle())
            .accessibilityLabel(playback.isPlaying ? "Pause" : "Play")

            Button { library.skipForward() } label: {
                Image(systemName: "forward.end.fill")
                    .font(.system(size: 32, weight: .regular))
                    .foregroundStyle(PlayerInk.cream)
                    .frame(width: 60, height: 60)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PopButtonStyle())
            .accessibilityLabel("Next track")
        }
    }

    /// Shuffle at the left edge, Up Next in the middle, repeat at the right: a soft square behind
    /// each one that's on.
    private var modeControls: some View {
        let shuffleOn = playback.shuffleMode == .songs || playback.shuffleMode == .albums
        let repeatOn = playback.repeatMode == .all || playback.repeatMode == .one
        return HStack {
            PlayerModeToggle(systemName: "shuffle", isOn: shuffleOn) {
                library.toggleShuffle()
            }
            .accessibilityLabel("Shuffle")
            .accessibilityValue(shuffleOn ? "On" : "Off")
            .accessibilityHint("Toggles shuffle for your queued songs")

            Spacer()

            PlayerModeToggle(systemName: "list.bullet", isOn: showingQueue) {
                showingQueue = true
            }
            .accessibilityLabel("Up Next")
            .accessibilityHint("Shows the queue so you can reorder, remove or add songs")

            Spacer()

            PlayerModeToggle(systemName: playback.repeatMode == .one ? "repeat.1" : "repeat", isOn: repeatOn) {
                library.cycleRepeatMode()
            }
            .accessibilityLabel("Repeat")
            .accessibilityValue(repeatAccessibilityValue)
            .accessibilityHint("Cycles between repeat off, repeat all, and repeat one")
        }
    }

    private var repeatAccessibilityValue: String {
        switch playback.repeatMode {
        case .all:
            return "All songs"
        case .one:
            return "One song"
        case .none, .default:
            return "Off"
        @unknown default:
            return "Off"
        }
    }
}

/// A mode button on the player: the symbol bright with a soft cream square behind it when on,
/// dimmed with nothing behind it when off. 48 pt to touch.
private struct PlayerModeToggle: View {
    let systemName: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(isOn ? PlayerInk.cream : PlayerInk.idle)
                .frame(width: 38, height: 38)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(PlayerInk.cream.opacity(isOn ? 0.16 : 0))
                )
                .frame(width: 48, height: 48)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.2), value: isOn)
    }
}

private struct PlaybackScrubber: View {
    let duration: TimeInterval
    let position: TimeInterval
    let isPlaying: Bool
    let onSeek: (TimeInterval) -> Void

    @State private var isScrubbing = false
    @State private var scrubPosition: TimeInterval = 0
    @State private var pendingSeekPosition: TimeInterval?
    @State private var pendingSeekDate: Date?

    private var sliderValue: TimeInterval {
        let value: TimeInterval
        if isScrubbing {
            value = scrubPosition
        } else if let pendingSeekPosition, let pendingSeekDate {
            let elapsed = Date.now.timeIntervalSince(pendingSeekDate)
            let predicted = pendingSeekPosition + (isPlaying ? max(elapsed, 0) : 0)
            if elapsed < 3, abs(position - predicted) > 0.75 {
                value = predicted
            } else {
                value = position
            }
        } else {
            value = position
        }
        return min(max(value, 0), max(duration, 1))
    }

    var body: some View {
        VStack(spacing: 10) {
            // A thin track you can drag anywhere along (a taller invisible area takes the touch).
            GeometryReader { geometry in
                let width = max(geometry.size.width, 1)
                let fraction = duration > 0 ? CGFloat(sliderValue / max(duration, 1)) : 0
                ZStack(alignment: .leading) {
                    Capsule().fill(PlayerInk.track)
                    Capsule().fill(PlayerInk.cream).frame(width: width * min(max(fraction, 0), 1))
                }
                .frame(height: isScrubbing ? 8 : 4)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard duration > 0 else { return }
                            if !isScrubbing {
                                isScrubbing = true
                            }
                            scrubPosition = Double(min(max(value.location.x / width, 0), 1)) * duration
                        }
                        .onEnded { _ in
                            guard isScrubbing else { return }
                            pendingSeekPosition = scrubPosition
                            pendingSeekDate = .now
                            Haptics.tap()
                            onSeek(scrubPosition)
                            isScrubbing = false
                        }
                )
                .animation(.easeOut(duration: 0.15), value: isScrubbing)
            }
            .frame(height: 28)
            .padding(.vertical, -8)
            .accessibilityElement()
            .accessibilityLabel("Position")
            .accessibilityValue(timestamp(sliderValue))
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: onSeek(min(sliderValue + 10, duration))
                case .decrement: onSeek(max(sliderValue - 10, 0))
                @unknown default: break
                }
            }

            HStack {
                Text(timestamp(sliderValue))
                Spacer()
                Text("−\(timestamp(max(duration - sliderValue, 0)))")
            }
            .font(.system(size: 12, weight: .medium).monospacedDigit())
            .foregroundStyle(PlayerInk.secondary)
        }
    }

    private func timestamp(_ time: TimeInterval) -> String {
        guard duration > 0 else { return "--:--" }
        let totalSeconds = max(Int(time), 0)
        return String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60)
    }
}

/// Colours used over the cover-coloured Now Playing background (the same as Hush for Android).
enum PlayerInk {
    static let cream = Color(red: 0.969, green: 0.945, blue: 0.894)
    static let secondary = cream.opacity(0.72)
    /// Shuffle and repeat while they're off.
    static let idle = cream.opacity(0.55)
    /// The scrubber's track.
    static let track = Color.white.opacity(0.2)
    /// The play/pause symbol on its cream disc.
    static let glyph = Color(red: 0.227, green: 0.071, blue: 0.059)
}

/// The player's cover: framed, with rounded corners and a soft shadow. It crossfades when the song
/// changes, sinks a little while paused and springs back when playing (held still with Reduce
/// Motion), and follows a sideways swipe: left for the next song, right for the previous one.
private struct PlayerCover: View {
    let item: MPMediaItem?
    let side: CGFloat
    let isPlaying: Bool
    let onNext: () -> Void
    let onPrevious: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dragOffset: CGFloat = 0
    @State private var isPastSkipThreshold = false

    private static let skipDistance: CGFloat = 80

    var body: some View {
        ZStack {
            // Crossfades to the next song's cover instead of snapping.
            ArtworkView(item: item, cornerRadius: 10, size: CGSize(width: 1200, height: 1200))
                .id(item?.persistentID)
                .transition(.opacity)
        }
        .animation(.easeInOut(duration: 0.35), value: item?.persistentID)
        .frame(width: side, height: side)
        .shadow(color: .black.opacity(0.5), radius: 17, x: 0, y: 18)
        .scaleEffect(isPlaying || reduceMotion ? 1 : 0.84)
        .animation(.spring(response: 0.45, dampingFraction: 0.66), value: isPlaying)
        .offset(x: dragOffset * 0.5)
        // A UIKit pan that only starts on a sideways swipe, so a downward swipe still closes the player.
        .overlay {
            SidewaysSwipe(
                onChange: { translation in
                    dragOffset = translation
                    let isPast = abs(translation) > Self.skipDistance
                    if isPast != isPastSkipThreshold {
                        isPastSkipThreshold = isPast
                        if isPast { Haptics.selection() }
                    }
                },
                onEnd: { translation, velocity in
                    isPastSkipThreshold = false
                    let flick = velocity * 0.2
                    if abs(translation) > Self.skipDistance || abs(flick) > 240 {
                        if translation + flick < 0 { onNext() } else { onPrevious() }
                    }
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { dragOffset = 0 }
                }
            )
            .frame(width: side, height: side)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: "Next song") { onNext() }
        .accessibilityAction(named: "Previous song") { onPrevious() }
    }
}

/// A clear view that reports sideways drags. Its pan only begins when the finger moves more across
/// than up or down, so vertical swipes go on to whatever else is listening (closing the player).
private struct SidewaysSwipe: UIViewRepresentable {
    let onChange: @MainActor (CGFloat) -> Void
    let onEnd: @MainActor (_ translation: CGFloat, _ velocity: CGFloat) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pan(_:)))
        pan.delegate = context.coordinator
        view.addGestureRecognizer(pan)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.parent = self
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: SidewaysSwipe

        init(_ parent: SidewaysSwipe) {
            self.parent = parent
        }

        @objc func pan(_ recognizer: UIPanGestureRecognizer) {
            switch recognizer.state {
            case .changed:
                parent.onChange(recognizer.translation(in: recognizer.view).x)
            case .ended:
                parent.onEnd(recognizer.translation(in: recognizer.view).x, recognizer.velocity(in: recognizer.view).x)
            case .cancelled, .failed:
                parent.onEnd(0, 0)
            default:
                break
            }
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
            let velocity = pan.velocity(in: pan.view)
            return abs(velocity.x) > abs(velocity.y)
        }
    }
}

// MARK: - Cover-coloured background

/// A cover's edge colours, ready to paint, with how bright each is (0 = black … 1 = white).
struct PlayerColors: Sendable {
    let top: Color
    let bottom: Color
    /// Halfway between the two.
    let middle: Color
    let topBrightness: Double
    let bottomBrightness: Double

    init(top: ArtworkColors.RGB, bottom: ArtworkColors.RGB) {
        self.top = Color(red: top.red, green: top.green, blue: top.blue)
        self.bottom = Color(red: bottom.red, green: bottom.green, blue: bottom.blue)
        middle = Color(
            red: (top.red + bottom.red) / 2,
            green: (top.green + bottom.green) / 2,
            blue: (top.blue + bottom.blue) / 2
        )
        topBrightness = Double(top.brightness)
        bottomBrightness = Double(bottom.brightness)
    }

    /// Warm browns, for a song with no cover.
    static let fallback = PlayerColors(
        top: ArtworkColors.RGB(red: 0.227, green: 0.173, blue: 0.094),
        bottom: ArtworkColors.RGB(red: 0.078, green: 0.067, blue: 0.047)
    )
}

/// Each song's cover colours, worked out once from a small copy of the cover.
@MainActor
enum PlayerColorCache {
    private static var colors: [UInt64: PlayerColors] = [:]
    private static var order: [UInt64] = []
    private static let limit = 300

    static func cached(_ id: UInt64) -> PlayerColors? {
        colors[id]
    }

    static func colors(for item: MPMediaItem) async -> PlayerColors? {
        let id = item.persistentID
        if let hit = colors[id] { return hit }
        // MediaPlayer hands out artwork reliably only on the main thread; the sampling runs off it.
        guard let raw = item.artwork?.image(at: CGSize(width: 240, height: 240)) else { return nil }
        let made = await Task.detached(priority: .userInitiated) { () -> PlayerColors? in
            guard let source = CIImage(image: raw),
                  let edges = ArtworkColors.edgeColors(of: source) else { return nil }
            return PlayerColors(top: edges.top, bottom: edges.bottom)
        }.value
        if let made {
            if colors[id] == nil { order.append(id) }
            colors[id] = made
            if order.count > limit { colors[order.removeFirst()] = nil }
        }
        return made
    }
}

/// The Now Playing background: the cover's edge colours as a softly drifting gradient, shaded so
/// cream text always reads. Keeps the old colours until the new ones are ready, then blends over
/// 0.7 s. Holds still with Reduce Motion.
private struct CoverColorBackdrop: View {
    let item: MPMediaItem?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var colors: PlayerColors
    @State private var colorsID: UInt64

    init(item: MPMediaItem?) {
        self.item = item
        if let item, let cached = PlayerColorCache.cached(item.persistentID) {
            _colors = State(initialValue: cached)
            _colorsID = State(initialValue: item.persistentID)
        } else {
            _colors = State(initialValue: .fallback)
            _colorsID = State(initialValue: 0)
        }
    }

    var body: some View {
        ZStack {
            Color.black
            DriftingColors(colors: colors, drifts: !reduceMotion)
                .id(colorsID)
                .transition(.opacity)
        }
        .animation(.easeInOut(duration: 0.7), value: colorsID)
        .accessibilityHidden(true)
        .allowsHitTesting(false)
        .task(id: item?.persistentID) {
            guard let item else { return }
            let id = item.persistentID
            guard id != colorsID else { return }
            if let cached = PlayerColorCache.cached(id) {
                colors = cached
                colorsID = id
                return
            }
            guard let loaded = await PlayerColorCache.colors(for: item), !Task.isCancelled else { return }
            colors = loaded
            colorsID = id
        }
    }
}

/// Three soft pools of the cover's colours that wander slowly over its top-to-bottom gradient.
private struct DriftingColors: View {
    let colors: PlayerColors
    let drifts: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: !drifts)) { context in
            let time = drifts ? context.date.timeIntervalSinceReferenceDate : 0
            let t = Self.wave(time, period: 19)
            let u = Self.wave(time, period: 27)
            GeometryReader { geometry in
                let reach = max(geometry.size.width, geometry.size.height)
                let topShade = min(0.18 + 0.30 * colors.topBrightness, 0.9)
                let bottomShade = min(0.30 + 0.40 * colors.bottomBrightness + 0.25, 0.92)
                ZStack {
                    LinearGradient(colors: [colors.top, colors.bottom], startPoint: .top, endPoint: .bottom)
                    RadialGradient(
                        colors: [colors.top.opacity(0.75), .clear],
                        center: UnitPoint(x: 0.1 + 0.8 * t, y: 0.08 + 0.18 * u),
                        startRadius: 0,
                        endRadius: reach * 0.7
                    )
                    RadialGradient(
                        colors: [colors.bottom.opacity(0.75), .clear],
                        center: UnitPoint(x: 0.9 - 0.8 * u, y: 0.92 - 0.2 * t),
                        startRadius: 0,
                        endRadius: reach * 0.75
                    )
                    RadialGradient(
                        colors: [colors.middle.opacity(0.5), .clear],
                        center: UnitPoint(x: 0.3 + 0.4 * u, y: 0.4 + 0.2 * t),
                        startRadius: 0,
                        endRadius: reach * 0.5
                    )
                    // Darken for legibility, a little more toward the bottom (the Mac's shade).
                    LinearGradient(
                        stops: [
                            .init(color: .black.opacity(topShade), location: 0),
                            .init(color: .black.opacity(min(topShade + 0.08, 0.9)), location: 0.45),
                            .init(color: .black.opacity(bottomShade), location: 1),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
            }
        }
    }

    /// 0 → 1 → 0 at an even pace, taking `period` seconds each way.
    private static func wave(_ time: TimeInterval, period: Double) -> CGFloat {
        let phase = time.truncatingRemainder(dividingBy: period * 2) / period
        return CGFloat(phase <= 1 ? phase : 2 - phase)
    }
}

// MARK: - Apple Music–style play/pause pop

extension View {
    /// Old symbol shrinks out, new one pops in with a little overshoot (SF Symbols replace effect).
    func popSymbolSwap(isPlaying: Bool) -> some View {
        self
            .contentTransition(.symbolEffect(.replace.downUp))
            .animation(.spring(response: 0.3, dampingFraction: 0.55), value: isPlaying)
    }
}

/// Squeezes the button while pressed and springs back on release, like Apple Music's transport buttons.
struct PopButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.86 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.5), value: configuration.isPressed)
            // Warm up the haptic as the finger touches down, so the click on release is instant.
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed { Haptics.prepare() }
            }
    }
}

// MARK: - Up Next (queue)

/// The play queue on Liquid Glass: what's playing and what's next. Every Up Next row has a
/// reorder handle (≡) you can drag right away, a remove button, and tapping a row plays it.
/// "Add Songs" searches the library.
struct UpNextView: View {
    @EnvironmentObject private var library: MusicLibraryStore
    @EnvironmentObject private var queue: QueueModel
    /// Always in reorder mode, so the native drag handles are always showing.
    @State private var editMode: EditMode = .active
    @State private var showingAddSongs = false

    var body: some View {
        let upNext = queue.upNext
        NavigationStack {
            List {
                if let nowPlaying = queue.nowPlaying {
                    Section {
                        QueueRow(item: nowPlaying.item, isCurrent: true)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .moveDisabled(true)
                            .deleteDisabled(true)
                    } header: {
                        sectionHeader("Now Playing")
                    }
                }

                Section {
                    if upNext.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "text.line.last.and.arrowtriangle.forward")
                                .font(.system(size: 26, weight: .light))
                                .foregroundStyle(HushStyle.accent.opacity(0.85))
                            Text("Nothing up next")
                                .font(.system(size: 17, weight: .regular, design: .serif))
                                .foregroundStyle(HushStyle.ink)
                            Text("Tap Add Songs, or press and hold any song, album or playlist and choose Play Next or Add to Queue.")
                                .font(.system(size: 13))
                                .foregroundStyle(HushStyle.muted)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 28)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .moveDisabled(true)
                        .deleteDisabled(true)
                    } else {
                        ForEach(Array(upNext.enumerated()), id: \.element.id) { offset, entry in
                            HStack(spacing: 6) {
                                Button {
                                    library.jumpToUpNext(offset: offset)
                                } label: {
                                    QueueRow(item: entry.item, isCurrent: false)
                                }
                                .buttonStyle(.borderless)
                                .accessibilityHint("Plays this song now")

                                Button {
                                    withAnimation(.snappy(duration: 0.25)) {
                                        library.removeFromUpNext(atOffsets: IndexSet(integer: offset))
                                    }
                                } label: {
                                    Image(systemName: "minus.circle")
                                        .font(.system(size: 17, weight: .regular))
                                        .foregroundStyle(HushStyle.muted)
                                        .frame(width: 34, height: 40)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("Remove \(entry.item.title ?? "song") from queue")
                            }
                            .listRowBackground(Color.clear)
                            .listRowSeparatorTint(HushStyle.line.opacity(0.6))
                            .deleteDisabled(true)
                            // No long-press menu here: it competed with dragging the ≡ handle.
                        }
                        .onMove { source, destination in
                            library.moveInUpNext(fromOffsets: source, toOffset: destination)
                        }
                    }
                } header: {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            sectionHeader("Up Next")
                            Text(upNextSubtitle(count: upNext.count))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(HushStyle.muted)
                                .textCase(nil)
                        }
                        Spacer()
                        if !upNext.isEmpty {
                            Button("Clear") {
                                withAnimation { library.clearUpNext() }
                            }
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(HushStyle.accent)
                            .textCase(nil)
                        }
                    }
                }
            }
            .listStyle(.plain)
            // Transparent list so the sheet's Liquid Glass shows through.
            .scrollContentBackground(.hidden)
            .environment(\.editMode, $editMode)
            .navigationTitle("Up Next")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingAddSongs = true
                    } label: {
                        Label("Add Songs", systemImage: "plus")
                    }
                }
            }
            .overlay(alignment: .bottom) { QueueToast().padding(.bottom, 16) }
            .sheet(isPresented: $showingAddSongs) {
                AddToQueueView()
                    .environmentObject(library)
                    .environmentObject(queue)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                    .queueSheetGlass()
            }
        }
        .tint(HushStyle.accent)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 15, weight: .semibold, design: .serif))
            .foregroundStyle(HushStyle.ink)
            .textCase(nil)
    }

    private func upNextSubtitle(count: Int) -> String {
        let songs = count == 1 ? "1 song" : "\(count) songs"
        if let source = library.playbackSource, let origin = library.title(for: source) {
            return "\(songs) · Playing from \(origin.name)"
        }
        return songs
    }
}

private struct QueueRow: View {
    let item: MPMediaItem
    let isCurrent: Bool

    var body: some View {
        HStack(spacing: 12) {
            ArtworkView(item: item, cornerRadius: 8, size: HushStyle.smallArtworkSize)
                .frame(width: 46, height: 46)
                .overlay(alignment: .bottomTrailing) {
                    if isCurrent {
                        NowPlayingBadge(size: 17)
                            .offset(x: 3, y: 3)
                    }
                }
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title ?? "Untitled")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isCurrent ? HushStyle.accent : HushStyle.ink)
                    .lineLimit(1)
                Text([item.artist, item.albumTitle].compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 12))
                    .foregroundStyle(HushStyle.muted)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

/// Search your library and add songs to the queue without leaving Up Next.
private struct AddToQueueView: View {
    @EnvironmentObject private var library: MusicLibraryStore
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var results: [MPMediaItem] = []

    var body: some View {
        NavigationStack {
            List(results, id: \.persistentID) { item in
                HStack(spacing: 10) {
                    QueueRow(item: item, isCurrent: false)
                    Button {
                        library.playNext([item])
                    } label: {
                        Image(systemName: "text.line.first.and.arrowtriangle.forward")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(HushStyle.accent)
                            .frame(width: 40, height: 40)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Play \(item.title ?? "song") next")
                    Button {
                        library.addToQueue([item])
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(HushStyle.accent)
                            .frame(width: 40, height: 40)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Add \(item.title ?? "song") to queue")
                }
                .listRowBackground(Color.clear)
                .listRowSeparatorTint(HushStyle.line)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.immediately)
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Find a song, album or artist")
            .onAppear(perform: rebuildResults)
            .onChange(of: searchText) { rebuildResults() }
            .navigationTitle("Add Songs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.fontWeight(.semibold)
                }
            }
            .overlay(alignment: .bottom) { QueueToast().padding(.bottom, 16) }
        }
        .tint(HushStyle.accent)
    }

    private func rebuildResults() {
        let query = LibrarySearch.normalizedQuery(searchText)
        let info = library.songInfo
        results = library.songs.filter { LibrarySearch.matches(info[$0.persistentID]?.searchKey, query: query) }
    }
}

private extension View {
    /// iOS 26: the system's Liquid Glass sheet (nothing painted over it). Earlier: frosted material.
    @ViewBuilder
    func queueSheetGlass() -> some View {
        if #available(iOS 26.0, *) {
            self
        } else {
            self.presentationBackground(.ultraThinMaterial)
        }
    }
}

/// Brief confirmation after adding songs ("Playing Next", "Added to Queue").
struct QueueToast: View {
    @EnvironmentObject private var queue: QueueModel

    var body: some View {
        if let message = queue.toast {
            Label(message, systemImage: "checkmark.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(HushStyle.ink)
                .symbolRenderingMode(.hierarchical)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .hushGlassBackground(Capsule())
                .transition(.opacity)
                .accessibilityAddTraits(.updatesFrequently)
        }
    }
}

/// Long-press menu for any song / album / playlist: Play Next and Add to Queue.
private struct QueueMenuModifier: ViewModifier {
    @EnvironmentObject private var library: MusicLibraryStore
    let items: () -> [MPMediaItem]

    func body(content: Content) -> some View {
        content.contextMenu {
            QueueActionButtons(library: library, items: items)
        }
    }
}

extension View {
    func queueMenu(_ items: @escaping @autoclosure () -> [MPMediaItem]) -> some View {
        modifier(QueueMenuModifier(items: items))
    }
}
