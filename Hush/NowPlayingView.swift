import CoreImage
import MediaPlayer
import SwiftUI
import UIKit

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
        GeometryReader { geometry in
            let layout = PlayerArtLayout(
                width: geometry.size.width,
                height: geometry.size.height,
                topInset: geometry.safeAreaInsets.top,
                bottomInset: geometry.safeAreaInsets.bottom
            )

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    topBar
                        .playerGlassGroup()
                        .padding(.horizontal, 24)

                    // The cover is drawn behind everything (NowPlayingBackdrop). This keeps its
                    // place, so the title starts just below it.
                    Color.clear
                        .frame(height: layout.titleGap)

                    trackInformation
                        .playerGlassGroup()
                        .padding(.horizontal, 24)

                    Spacer(minLength: 14)

                    TimelineView(.animation(minimumInterval: 1.0 / 4.0, paused: !playback.isPlaying)) { _ in
                        PlaybackScrubber(
                            duration: duration,
                            position: library.currentPlaybackTime,
                            isPlaying: playback.isPlaying,
                            onSeek: library.seek(to:),
                            tint: HushStyle.accent
                        )
                    }
                    .padding(.horizontal, 24)

                    Spacer(minLength: 10)

                    transportControls
                        .playerGlassGroup()
                        .padding(.horizontal, 24)

                    Spacer(minLength: 14)
                }
                .frame(maxWidth: .infinity, minHeight: max(geometry.size.height, 0))
            }
            // Only scrolls when the content doesn't fit (small phones / large text), so a downward
            // swipe goes to the close gesture instead of rubber-banding the page.
            .scrollBounceBehavior(.basedOnSize)
            .background { NowPlayingBackdrop(item: library.currentItem, layout: layout) }
        }
        .toolbar(.hidden, for: .navigationBar)
        .tint(HushStyle.accent)
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

    private var topBar: some View {
        HStack {
            Button {
                onMinimize()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(HushStyle.accent)
                    .frame(width: 42, height: 42)
                    .playerGlass(in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back to library")

            Spacer(minLength: 10)

            playingFrom

            Spacer(minLength: 10)

            Button {
                showingQueue = true
            } label: {
                Image(systemName: "list.bullet")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(HushStyle.accent)
                    .frame(width: 42, height: 42)
                    .playerGlass(in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Up Next")
            .accessibilityHint("Shows the queue so you can reorder, remove or add songs")
        }
        .frame(height: 48)
        .padding(.top, 4)
    }

    /// Top center: "Playing from" the album, artist or playlist you started — tap to go back there.
    /// Shows "Hush" when the music was started from Songs or search.
    @ViewBuilder
    private var playingFrom: some View {
        if let source = library.playbackSource, let origin = library.title(for: source) {
            Button {
                onGoTo(source)
            } label: {
                VStack(spacing: 2) {
                    Text("PLAYING FROM \(origin.kind.uppercased())")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .tracking(0.8)
                        .foregroundStyle(.white.opacity(0.82))
                        .lineLimit(1)
                    HStack(spacing: 3) {
                        Text(origin.name)
                            .lineLimit(1)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                }
                .shadow(color: .black.opacity(0.45), radius: 5, y: 1)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Playing from \(origin.kind) \(origin.name)")
            .accessibilityHint("Closes the player and opens it")
        } else {
            Text("Hush")
                .font(HushStyle.brandFont(size: 18))
                .foregroundStyle(HushStyle.accent)
                .shadow(color: .black.opacity(0.45), radius: 5, y: 1)
        }
    }

    /// The artist name leads to their page (a short menu when several are credited), like Apple Music.
    @ViewBuilder
    private var artistLine: some View {
        let credit = library.currentItem?.artist
        let text = credit ?? "Your music library"
        let credited = library.creditedArtists(in: credit)
        let label = Text(text)
            .font(.system(size: 15, weight: .medium, design: .rounded))
            .foregroundStyle(HushStyle.ink.opacity(0.72))
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

    private var trackInformation: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(library.currentItem?.title ?? "Choose something to play")
                .font(.system(size: 27, weight: .regular, design: .serif))
                .tracking(-0.4)
                .foregroundStyle(HushStyle.ink)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            artistLine

            if let album = currentAlbum {
                // Tap the album name to go to the album (like Apple Music) — always offered when the
                // song's album is in your library.
                let songAlbumTitle = library.currentItem?.albumTitle ?? ""
                let albumTitle = songAlbumTitle.isEmpty ? album.title : songAlbumTitle
                Button {
                    onGoTo(.album(album.id))
                } label: {
                    HStack(spacing: 4) {
                        Text(albumTitle.isEmpty ? "Go to Album" : albumTitle)
                            .lineLimit(1)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(HushStyle.accent.opacity(0.95))
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Go to album \(albumTitle)")
            } else if let albumTitle = library.currentItem?.albumTitle, !albumTitle.isEmpty {
                Text(albumTitle)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(HushStyle.ink.opacity(0.6))
                    .lineLimit(1)
            }
        }
        // Keeps the words crisp where they sit on the last of the cover's fade.
        .shadow(color: .black.opacity(0.35), radius: 6, y: 1)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var transportControls: some View {
        HStack(spacing: 0) {
            repeatButton
                .frame(maxWidth: .infinity)

            Button { library.skipBack() } label: {
                Image(systemName: "backward.end.fill")
                    .font(.system(size: 21, weight: .regular))
                    .foregroundStyle(HushStyle.accent)
                    .frame(width: 58, height: 58)
                    .playerGlass(in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Previous track")
            .frame(maxWidth: .infinity)

            Button { library.togglePlayback() } label: {
                Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(HushStyle.paper)
                    .popSymbolSwap(isPlaying: playback.isPlaying)
                    .offset(x: playback.isPlaying ? 0 : 2)
                    .frame(width: 76, height: 76)
                    .background(HushStyle.accent, in: Circle())
            }
            .buttonStyle(PopButtonStyle())
            .accessibilityLabel(playback.isPlaying ? "Pause" : "Play")
            .frame(maxWidth: .infinity)

            Button { library.skipForward() } label: {
                Image(systemName: "forward.end.fill")
                    .font(.system(size: 21, weight: .regular))
                    .foregroundStyle(HushStyle.accent)
                    .frame(width: 58, height: 58)
                    .playerGlass(in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Next track")
            .frame(maxWidth: .infinity)

            shuffleButton
                .frame(maxWidth: .infinity)
        }
        .padding(.top, 4)
    }

    private var shuffleButton: some View {
        let isEnabled = playback.shuffleMode == .songs || playback.shuffleMode == .albums

        return Button {
            library.toggleShuffle()
        } label: {
            VStack(spacing: 3) {
                Image(systemName: "shuffle")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(isEnabled ? HushStyle.accent : HushStyle.muted.opacity(0.75))
                    .frame(width: 36, height: 36)
                    .playerGlass(in: Circle())
                Text(isEnabled ? "ON" : "OFF")
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .tracking(0.7)
                    .foregroundStyle(isEnabled ? HushStyle.accent : HushStyle.muted.opacity(0.75))
            }
            .frame(width: 54, height: 64)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Shuffle")
        .accessibilityValue(isEnabled ? "On" : "Off")
        .accessibilityHint("Toggles shuffle for your queued songs")
    }

    private var repeatButton: some View {
        let isEnabled = playback.repeatMode == .all || playback.repeatMode == .one
        let symbol = playback.repeatMode == .one ? "repeat.1" : "repeat"
        let stateLabel = repeatShortLabel

        return Button {
            library.cycleRepeatMode()
        } label: {
            VStack(spacing: 3) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(isEnabled ? HushStyle.accent : HushStyle.muted.opacity(0.75))
                    .frame(width: 36, height: 36)
                    .playerGlass(in: Circle())
                Text(stateLabel)
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .tracking(0.7)
                    .foregroundStyle(isEnabled ? HushStyle.accent : HushStyle.muted.opacity(0.75))
            }
            .frame(width: 54, height: 64)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Repeat")
        .accessibilityValue(repeatAccessibilityValue)
        .accessibilityHint("Cycles between repeat off, repeat all, and repeat one")
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

    private var repeatShortLabel: String {
        switch playback.repeatMode {
        case .all:
            return "ALL"
        case .one:
            return "ONE"
        case .none, .default:
            return "OFF"
        @unknown default:
            return "OFF"
        }
    }
}

private struct PlaybackScrubber: View {
    let duration: TimeInterval
    let position: TimeInterval
    let isPlaying: Bool
    let onSeek: (TimeInterval) -> Void
    var tint: Color = HushStyle.accent

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
        VStack(spacing: 4) {
            Slider(
                value: Binding(
                    get: { sliderValue },
                    set: { scrubPosition = $0 }
                ),
                in: 0...max(duration, 1),
                onEditingChanged: { editing in
                    if editing {
                        scrubPosition = sliderValue
                        isScrubbing = true
                    } else {
                        pendingSeekPosition = scrubPosition
                        pendingSeekDate = .now
                        Haptics.tap()
                        onSeek(scrubPosition)
                        isScrubbing = false
                    }
                }
            )
            .tint(tint)
            .disabled(duration <= 0)

            HStack {
                Text(timestamp(sliderValue))
                Spacer()
                Text("−\(timestamp(max(duration - sliderValue, 0)))")
            }
            .font(.system(size: 11, weight: .medium, design: .rounded).monospacedDigit())
            .foregroundStyle(HushStyle.muted)
        }
    }

    private func timestamp(_ time: TimeInterval) -> String {
        guard duration > 0 else { return "--:--" }
        let totalSeconds = max(Int(time), 0)
        return String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60)
    }
}

// MARK: - Liquid Glass + artwork theming

private extension View {
    /// Liquid Glass on iOS 26; a frosted material on earlier versions. Left untinted so the
    /// accent icons on top keep their exact color on any album background.
    @ViewBuilder
    func playerGlass<S: Shape>(in shape: S, tint: Color? = nil) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(Glass.regular.tint(tint), in: shape)
        } else {
            self
                .background((tint ?? .clear).opacity(0.55), in: shape)
                .background(.ultraThinMaterial, in: shape)
        }
    }

    /// Renders all glass on the player together, as Apple recommends, instead of one pass per button.
    @ViewBuilder
    func playerGlassGroup() -> some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: 0) { self }
        } else {
            self
        }
    }
}

/// Where the cover sits on the player, worked out once from the screen so the cover and the
/// controls agree.
private struct PlayerArtLayout: Equatable {
    /// Top bar height (48) plus its top padding (4).
    private static let topBarHeight: CGFloat = 52
    /// Space between the top bar and the cover, and between the cover and the title.
    private static let coverGap: CGFloat = 14
    /// Room the title, scrubber and buttons need below the cover (two-line title included).
    private static let controlsHeight: CGFloat = 290

    let width: CGFloat
    let screenHeight: CGFloat
    let topInset: CGFloat
    /// From the very top of the screen to the cover's top edge.
    let drop: CGFloat
    /// The cover's side: the full screen width, smaller on short phones so the controls fit.
    let coverSize: CGFloat

    init(width: CGFloat, height: CGFloat, topInset: CGFloat, bottomInset: CGFloat) {
        let width = width.isFinite ? max(width, 0) : 0
        let height = height.isFinite ? max(height, 0) : 0
        self.width = width
        self.topInset = topInset
        screenHeight = height + topInset + bottomInset
        drop = topInset + Self.topBarHeight + Self.coverGap
        let room = screenHeight - bottomInset - Self.controlsHeight - Self.coverGap - drop
        coverSize = max(min(width, room), 0)
    }

    /// The cover's bottom edge, measured from the top of the screen.
    var coverBottom: CGFloat { drop + coverSize }

    /// Space between the top bar and the title, so the title starts just below the cover.
    var titleGap: CGFloat {
        max(coverBottom + Self.coverGap - topInset - Self.topBarHeight, 0)
    }
}

/// Everything behind the player's controls: black, with the cover as large as it fits, a crisp
/// square the full width of the screen.
private struct NowPlayingBackdrop: View {
    let item: MPMediaItem?
    let layout: PlayerArtLayout

    var body: some View {
        ZStack(alignment: .top) {
            HushStyle.paper
            // Crossfades to the next song's cover instead of snapping.
            ZStack {
                ArtworkView(item: item, cornerRadius: 0, size: CGSize(width: 1200, height: 1200))
                    .id(item?.persistentID)
                    .transition(.opacity)
            }
            .animation(.easeInOut(duration: 0.35), value: item?.persistentID)
            .frame(width: layout.coverSize, height: layout.coverSize)
            .clipped()
            .offset(y: layout.drop)
        }
        .frame(width: layout.width, height: layout.screenHeight, alignment: .top)
        .clipped()
        .ignoresSafeArea()
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
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundStyle(HushStyle.muted)
                                .textCase(nil)
                        }
                        Spacer()
                        if !upNext.isEmpty {
                            Button("Clear") {
                                withAnimation { library.clearUpNext() }
                            }
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
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
            ArtworkView(item: item, cornerRadius: 8, size: CGSize(width: 120, height: 120))
                .frame(width: 46, height: 46)
                .overlay(alignment: .bottomTrailing) {
                    if isCurrent {
                        NowPlayingBadge(size: 17)
                            .offset(x: 3, y: 3)
                    }
                }
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title ?? "Untitled")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
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
                .font(.system(size: 13, weight: .semibold, design: .rounded))
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
            Button {
                library.playNext(items())
            } label: {
                Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward")
            }
            Button {
                library.addToQueue(items())
            } label: {
                Label("Add to Queue", systemImage: "text.line.last.and.arrowtriangle.forward")
            }
        }
    }
}

extension View {
    func queueMenu(_ items: @escaping @autoclosure () -> [MPMediaItem]) -> some View {
        modifier(QueueMenuModifier(items: items))
    }
}
