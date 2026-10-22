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
                        .padding(.horizontal, 8)

                    // The cover is drawn behind everything (NowPlayingBackdrop). This keeps its
                    // place, so the title starts just below it.
                    Color.clear
                        .frame(height: layout.titleGap)

                    trackInformation
                        .padding(.horizontal, 24)

                    Spacer(minLength: 20)

                    TimelineView(.animation(minimumInterval: 1.0 / 4.0, paused: !playback.isPlaying)) { _ in
                        PlaybackScrubber(
                            duration: duration,
                            position: library.currentPlaybackTime,
                            isPlaying: playback.isPlaying,
                            onSeek: library.seek(to:)
                        )
                    }
                    .padding(.horizontal, 24)

                    Spacer(minLength: 16)

                    transportControls

                    Spacer(minLength: 16)

                    modeControls
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
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
                BarIcon(systemName: "chevron.down")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back to library")

            Spacer()

            Button {
                showingQueue = true
            } label: {
                BarIcon(systemName: "list.bullet", size: 18)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Up Next")
            .accessibilityHint("Shows the queue so you can reorder, remove or add songs")
        }
        .frame(height: HushStyle.tapTarget)
    }

    /// The artist name leads to their page (a short menu when several are credited), like Apple Music.
    @ViewBuilder
    private var artistLine: some View {
        let credit = library.currentItem?.artist
        let text = credit ?? "Your music library"
        let credited = library.creditedArtists(in: credit)
        let label = Text(text)
            .font(.system(size: 16))
            .foregroundStyle(HushStyle.muted)
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
                .font(.system(size: 29, weight: .regular, design: .serif))
                .tracking(-0.3)
                .foregroundStyle(HushStyle.ink)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            // "Artist · Album": the artist opens their page, the album opens the album.
            HStack(spacing: 6) {
                artistLine
                    .layoutPriority(1)
                if let album = currentAlbum {
                    let songAlbumTitle = library.currentItem?.albumTitle ?? ""
                    let albumTitle = songAlbumTitle.isEmpty ? album.title : songAlbumTitle
                    Text("·")
                        .font(.system(size: 16))
                        .foregroundStyle(HushStyle.muted)
                        .accessibilityHidden(true)
                    Button {
                        onGoTo(.album(album.id))
                    } label: {
                        Text(albumTitle)
                            .font(.system(size: 16))
                            .foregroundStyle(HushStyle.muted)
                            .lineLimit(1)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Go to album \(albumTitle)")
                } else if let albumTitle = library.currentItem?.albumTitle, !albumTitle.isEmpty {
                    Text("·")
                        .font(.system(size: 16))
                        .foregroundStyle(HushStyle.muted)
                        .accessibilityHidden(true)
                    Text(albumTitle)
                        .font(.system(size: 16))
                        .foregroundStyle(HushStyle.muted)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Previous, play/pause and next, centred.
    private var transportControls: some View {
        HStack(spacing: 48) {
            Button { library.skipBack() } label: {
                Image(systemName: "backward.end.fill")
                    .font(.system(size: 30, weight: .regular))
                    .foregroundStyle(HushStyle.ink)
                    .frame(width: 56, height: 56)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Previous track")

            Button { library.togglePlayback() } label: {
                Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Color.black)
                    .popSymbolSwap(isPlaying: playback.isPlaying)
                    .offset(x: playback.isPlaying ? 0 : 2)
                    .frame(width: 76, height: 76)
                    .background(HushStyle.ink, in: Circle())
            }
            .buttonStyle(PopButtonStyle())
            .accessibilityLabel(playback.isPlaying ? "Pause" : "Play")

            Button { library.skipForward() } label: {
                Image(systemName: "forward.end.fill")
                    .font(.system(size: 30, weight: .regular))
                    .foregroundStyle(HushStyle.ink)
                    .frame(width: 56, height: 56)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Next track")
        }
    }

    /// Shuffle at the left edge, repeat at the right: grey when off, bright when on.
    private var modeControls: some View {
        HStack {
            shuffleButton
            Spacer()
            repeatButton
        }
    }

    private var shuffleButton: some View {
        let isEnabled = playback.shuffleMode == .songs || playback.shuffleMode == .albums

        return Button {
            library.toggleShuffle()
        } label: {
            Image(systemName: "shuffle")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(isEnabled ? HushStyle.ink : HushStyle.iconOff)
                .frame(width: 44, height: 44)
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

        return Button {
            library.cycleRepeatMode()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(isEnabled ? HushStyle.ink : HushStyle.iconOff)
                .frame(width: 44, height: 44)
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
                    Capsule().fill(HushStyle.track)
                    Capsule().fill(HushStyle.ink).frame(width: width * min(max(fraction, 0), 1))
                }
                .frame(height: isScrubbing ? 5 : 3)
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
            .frame(height: 20)
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
            .font(.system(size: 12).monospacedDigit())
            .foregroundStyle(HushStyle.muted)
        }
    }

    private func timestamp(_ time: TimeInterval) -> String {
        guard duration > 0 else { return "--:--" }
        let totalSeconds = max(Int(time), 0)
        return String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60)
    }
}

/// Where the cover sits on the player, worked out once from the screen so the cover and the
/// controls agree.
private struct PlayerArtLayout: Equatable {
    /// The top bar's height.
    private static let topBarHeight: CGFloat = 44
    /// Space between the top bar and the cover.
    private static let coverGap: CGFloat = 2
    /// Space between the cover and the title.
    private static let titleGap: CGFloat = 30
    /// Room the title, scrubber, transport and shuffle/repeat row need below the cover.
    private static let controlsHeight: CGFloat = 318

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
        let room = screenHeight - bottomInset - Self.controlsHeight - Self.titleGap - drop
        coverSize = max(min(width, room), 0)
    }

    /// The cover's bottom edge, measured from the top of the screen.
    var coverBottom: CGFloat { drop + coverSize }

    /// Space between the top bar and the title, so the title starts just below the cover.
    var titleGap: CGFloat {
        max(coverBottom + Self.titleGap - topInset - Self.topBarHeight, 0)
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
