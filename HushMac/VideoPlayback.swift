import AppKit
import AVFoundation
import AVKit
import Observation
import SwiftUI

/// How a video fills the window. Fill (the default) crops a little so there are never black bands —
/// in full screen a 2.39:1 film fills a 16:10 display, like the UltraWide Safari extension. Zoom
/// crops further, for films with letterboxing burned into the picture.
enum VideoGravity: String, CaseIterable, Identifiable {
    case fit
    case fill
    case zoom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fit: return "Fit"
        case .fill: return "Fill"
        case .zoom: return "Zoom"
        }
    }

    var layerGravity: AVLayerVideoGravity {
        self == .fit ? .resizeAspect : .resizeAspectFill
    }

    /// Extra scale on top of aspect-fill.
    var scale: CGFloat { self == .zoom ? 1.18 : 1 }

    var next: VideoGravity {
        switch self {
        case .fit: return .fill
        case .fill: return .zoom
        case .zoom: return .fit
        }
    }
}

/// Plays music videos and movies in Hush's own full-window player. Music pauses while a video
/// plays; the media keys control the video until it's closed.
@MainActor
@Observable
final class VideoPlayback {
    static let shared = VideoPlayback()

    private(set) var current: Video?
    private(set) var queue: [Video] = []
    private(set) var index = 0
    private(set) var isPlaying = false
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    /// Subtitles and audio languages the current video offers.
    private(set) var legibleOptions: [AVMediaSelectionOption] = []
    private(set) var audibleOptions: [AVMediaSelectionOption] = []
    private(set) var selectedLegible: AVMediaSelectionOption?
    private(set) var selectedAudible: AVMediaSelectionOption?

    var gravity: VideoGravity {
        didSet { UserDefaults.standard.set(gravity.rawValue, forKey: Keys.gravity) }
    }

    var volume: Double {
        didSet {
            player.volume = Float(volume)
            UserDefaults.standard.set(volume, forKey: Keys.volume)
        }
    }

    let player = AVPlayer()
    /// The one view the video draws into (an AVPlayerLayer in a layer-backed NSView). It belongs to the
    /// playback, not the player page, so Picture in Picture keeps going while the page is closed and
    /// comes back to the same view; the page shows it through an NSViewRepresentable.
    let surface = VideoSurfaceView()
    var playerLayer: AVPlayerLayer { surface.playerLayer }
    /// The video is in Apple's floating Picture in Picture window; the player page steps aside.
    private(set) var isInPictureInPicture = false
    /// Whether Picture in Picture can start right now (the video is loaded and showing).
    private(set) var canStartPictureInPicture = false

    @ObservationIgnored private var pictureInPicture: AVPictureInPictureController?
    @ObservationIgnored private var pictureInPictureDelegate: PictureInPictureDelegate?
    @ObservationIgnored private var pictureInPictureObservation: NSKeyValueObservation?
    /// Set while the video comes back from Picture in Picture into the player page.
    @ObservationIgnored private var isRestoringFromPictureInPicture = false

    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []
    @ObservationIgnored private var endObserver: NSObjectProtocol?
    @ObservationIgnored private var isSeeking = false
    /// Whether opening the video put the window in full screen (so closing it leaves full screen too).
    @ObservationIgnored var enteredFullScreen = false

    private enum Keys {
        static let gravity = "hush.mac.videoGravity"
        static let volume = "hush.mac.videoVolume"
    }

    /// The full-window player page is up (not while the video floats in Picture in Picture).
    var isShowing: Bool { current != nil && !isInPictureInPicture }
    var handlesMediaKeys: Bool { current != nil }

    private init() {
        gravity = VideoGravity(rawValue: UserDefaults.standard.string(forKey: Keys.gravity) ?? "") ?? .fill
        volume = UserDefaults.standard.object(forKey: Keys.volume) as? Double ?? 1
        player.volume = Float(volume)
        playerLayer.player = player
        observePlayer()
        setUpPictureInPicture()
    }

    // MARK: Starting and stopping

    /// Plays `video` (and the rest of `list` after it). Copy-protected or cloud-only videos open in
    /// the TV app instead.
    func play(_ video: Video, in list: [Video]? = nil) {
        guard video.canPlayInHush, let url = video.location else {
            Self.openInTVApp()
            return
        }
        let playable = (list ?? [video]).filter(\.canPlayInHush)
        queue = playable.isEmpty ? [video] : playable
        index = queue.firstIndex(of: video) ?? 0
        Player.shared.setPlaying(false)
        start(url: url, video: video)
    }

    private func start(url: URL, video: Video) {
        current = video
        currentTime = 0
        duration = video.duration
        let item = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: item)
        player.play()
        isPlaying = true
        loadMediaOptions(for: item)
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.advance() }
        }
    }

    /// The video ended: the next one in the list, or close at the end.
    private func advance() {
        if hasNext { next() } else { close() }
    }

    var hasNext: Bool { index + 1 < queue.count }
    /// Previous is available if there's an earlier video, or to restart this one once it's a few seconds in.
    var canGoBack: Bool { index > 0 || currentTime > 3 }

    /// The next playable video in the list it was opened from.
    func next() {
        guard hasNext else { return }
        index += 1
        let video = queue[index]
        if let url = video.location { start(url: url, video: video) }
    }

    /// Restarts the video if it's more than 3 seconds in; otherwise the previous one in the list.
    func previous() {
        if currentTime > 3 || index == 0 {
            seek(to: 0)
            return
        }
        index -= 1
        let video = queue[index]
        if let url = video.location { start(url: url, video: video) }
    }

    func close() {
        if isInPictureInPicture { pictureInPicture?.stopPictureInPicture() }
        isInPictureInPicture = false
        player.pause()
        player.replaceCurrentItem(with: nil)
        isPlaying = false
        current = nil
        queue = []
        legibleOptions = []
        audibleOptions = []
        if enteredFullScreen, let window = NSApp.windows.first(where: { $0.styleMask.contains(.fullScreen) }) {
            window.toggleFullScreen(nil)
        }
        enteredFullScreen = false
    }

    static func openInTVApp() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.TV") else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    // MARK: Transport

    func togglePlayPause() {
        setPlaying(!isPlaying)
    }

    func setPlaying(_ playing: Bool) {
        guard current != nil else { return }
        if playing {
            Player.shared.setPlaying(false)
            if duration > 0, currentTime >= duration - 0.5 { seek(to: 0) }
            player.play()
        } else {
            player.pause()
        }
        isPlaying = playing
    }

    /// Music started: a video that's showing pauses.
    func pauseForMusic() {
        if isPlaying { setPlaying(false) }
    }

    func seek(to seconds: TimeInterval) {
        let target = min(max(seconds, 0), max(duration, 0))
        isSeeking = true
        currentTime = target
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            Task { @MainActor in self?.isSeeking = false }
        }
    }

    func skip(by seconds: TimeInterval) {
        seek(to: currentTime + seconds)
    }

    func cycleGravity() {
        gravity = gravity.next
    }

    // MARK: Picture in Picture

    private func setUpPictureInPicture() {
        guard AVPictureInPictureController.isPictureInPictureSupported(),
              let controller = AVPictureInPictureController(playerLayer: playerLayer) else { return }
        let delegate = PictureInPictureDelegate()
        controller.delegate = delegate
        pictureInPicture = controller
        pictureInPictureDelegate = delegate
        pictureInPictureObservation = controller.observe(\.isPictureInPicturePossible, options: [.initial, .new]) { controller, _ in
            let possible = controller.isPictureInPicturePossible
            Task { @MainActor in VideoPlayback.shared.canStartPictureInPicture = possible }
        }
    }

    /// Pops the video into Apple's floating window. It stays on top while Hush is minimised, hidden
    /// or behind other apps; its restore button brings the video back into Hush.
    func startPictureInPicture() {
        guard let pictureInPicture, pictureInPicture.isPictureInPicturePossible else { return }
        pictureInPicture.startPictureInPicture()
    }

    fileprivate func pictureInPictureWillStart() {
        isInPictureInPicture = true
        // Back to the library in a normal window, like the TV app.
        if enteredFullScreen, let window = NSApp.windows.first(where: { $0.styleMask.contains(.fullScreen) }) {
            window.toggleFullScreen(nil)
        }
        enteredFullScreen = false
    }

    fileprivate func restoreFromPictureInPicture(_ completion: @escaping (Bool) -> Void) {
        isRestoringFromPictureInPicture = true
        isInPictureInPicture = false
        // Back into Hush even when it was hidden or its window minimised.
        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue.contains("main") == true }) {
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
        }
        // Let the player page put the layer back in the window before the video flies home.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { completion(true) }
    }

    fileprivate func pictureInPictureDidStop() {
        defer { isRestoringFromPictureInPicture = false }
        guard !isRestoringFromPictureInPicture else { return }
        // Closed from the floating window: the video ends there, like the TV app.
        isInPictureInPicture = false
        if current != nil { close() }
    }

    fileprivate func pictureInPictureFailed(_ message: String) {
        hushLog.error("Picture in Picture failed: \(message, privacy: .public)")
        isInPictureInPicture = false
    }

    // MARK: Subtitles and audio

    private func loadMediaOptions(for item: AVPlayerItem) {
        legibleOptions = []
        audibleOptions = []
        let asset = item.asset
        Task {
            let legible = try? await asset.loadMediaSelectionGroup(for: .legible)
            let audible = try? await asset.loadMediaSelectionGroup(for: .audible)
            guard player.currentItem === item else { return }
            legibleOptions = legible?.options.filter { $0.isPlayable } ?? []
            audibleOptions = audible?.options ?? []
            selectedLegible = legible.flatMap { item.currentMediaSelection.selectedMediaOption(in: $0) }
            selectedAudible = audible.flatMap { item.currentMediaSelection.selectedMediaOption(in: $0) }
        }
    }

    /// nil turns subtitles off.
    func selectSubtitles(_ option: AVMediaSelectionOption?) {
        guard let item = player.currentItem else { return }
        Task {
            guard let group = try? await item.asset.loadMediaSelectionGroup(for: .legible) else { return }
            item.select(option, in: group)
            selectedLegible = option
        }
    }

    func selectAudio(_ option: AVMediaSelectionOption) {
        guard let item = player.currentItem else { return }
        Task {
            guard let group = try? await item.asset.loadMediaSelectionGroup(for: .audible) else { return }
            item.select(option, in: group)
            selectedAudible = option
        }
    }

    // MARK: Observing

    private func observePlayer() {
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            let seconds = time.seconds
            MainActor.assumeIsolated {
                guard let self, !self.isSeeking, seconds.isFinite else { return }
                self.currentTime = seconds
                if let itemDuration = self.player.currentItem?.duration.seconds, itemDuration.isFinite, itemDuration > 0 {
                    self.duration = itemDuration
                }
            }
        }
        observations.append(player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            let playing = player.timeControlStatus != .paused
            Task { @MainActor in
                guard let self, self.current != nil else { return }
                self.isPlaying = playing
            }
        })
    }
}

/// Forwards Picture in Picture events to the playback (on the main thread, wherever AVKit calls from).
private final class PictureInPictureDelegate: NSObject, AVPictureInPictureControllerDelegate {
    private func onMain(_ work: @escaping @MainActor @Sendable () -> Void) {
        if Thread.isMainThread {
            MainActor.assumeIsolated(work)
        } else {
            DispatchQueue.main.async { MainActor.assumeIsolated(work) }
        }
    }

    func pictureInPictureControllerWillStartPictureInPicture(_ controller: AVPictureInPictureController) {
        onMain { VideoPlayback.shared.pictureInPictureWillStart() }
    }

    func pictureInPictureController(
        _ controller: AVPictureInPictureController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
    ) {
        nonisolated(unsafe) let completion = completionHandler
        onMain { VideoPlayback.shared.restoreFromPictureInPicture(completion) }
    }

    func pictureInPictureControllerDidStopPictureInPicture(_ controller: AVPictureInPictureController) {
        onMain { VideoPlayback.shared.pictureInPictureDidStop() }
    }

    func pictureInPictureController(_ controller: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) {
        let message = error.localizedDescription
        onMain { VideoPlayback.shared.pictureInPictureFailed(message) }
    }
}

// MARK: - The video surface

/// The video picture: an AVPlayerLayer that follows the Fit / Fill / Zoom setting. Layer-backed (the view
/// is its layer's delegate), so Picture in Picture finds this view and puts its placeholder inside it,
/// not in SwiftUI's hosting view.
final class VideoSurfaceView: NSView {
    let playerLayer = AVPlayerLayer()

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.masksToBounds = true
        layer?.addSublayer(playerLayer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func makeBackingLayer() -> CALayer { CALayer() }

    var zoom: CGFloat = 1 {
        didSet { needsLayout = true }
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.35)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeInEaseOut))
        playerLayer.frame = bounds
        playerLayer.setAffineTransform(CGAffineTransform(scaleX: zoom, y: zoom))
        CATransaction.commit()
    }
}

/// Puts the playback's video view into the player page.
struct VideoSurface: NSViewRepresentable {
    let surface: VideoSurfaceView
    let gravity: VideoGravity

    func makeNSView(context: Context) -> VideoSurfaceView {
        surface.removeFromSuperview()
        surface.playerLayer.videoGravity = gravity.layerGravity
        surface.zoom = gravity.scale
        return surface
    }

    func updateNSView(_ view: VideoSurfaceView, context: Context) {
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.35)
        view.playerLayer.videoGravity = gravity.layerGravity
        CATransaction.commit()
        view.zoom = gravity.scale
    }
}

// MARK: - The full-window player

struct VideoPlayerView: View {
    @Environment(VideoPlayback.self) private var playback
    @State private var controlsVisible = true
    @State private var hideTask: Task<Void, Never>?
    @State private var isOverControls = false

    var body: some View {
        @Bindable var playback = playback
        ZStack {
            Color.black
            VideoSurface(surface: playback.surface, gravity: playback.gravity)
                .onTapGesture(count: 2) { toggleFullScreen() }
                .onTapGesture { playback.togglePlayPause() }

            Group {
                LinearGradient(colors: [.black.opacity(0.6), .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: 160)
                    .frame(maxHeight: .infinity, alignment: .top)
                LinearGradient(colors: [.black.opacity(0.75), .clear], startPoint: .bottom, endPoint: .top)
                    .frame(height: 240)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
            .allowsHitTesting(false)
            .opacity(controlsVisible ? 1 : 0)

            VStack(spacing: 0) {
                header
                Spacer()
                controls
                    .onHover { isOverControls = $0; showControls() }
            }
            .opacity(controlsVisible ? 1 : 0)
        }
        .ignoresSafeArea()
        .onContinuousHover { _ in showControls() }
        .onAppear { showControls() }
        .onDisappear {
            hideTask?.cancel()
            NSCursor.setHiddenUntilMouseMoves(false)
        }
        .animation(.easeInOut(duration: 0.25), value: controlsVisible)
    }

    private var header: some View {
        HStack(spacing: 14) {
            Button {
                playback.close()
            } label: {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(HushCircleButtonStyle(diameter: 36, onLight: true))
            .help("Close (Esc)")

            if let video = playback.current {
                VStack(alignment: .leading, spacing: 1) {
                    Text(video.title)
                        .font(HushStyle.serif(20))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    let detail = video.isMovie ? video.yearAndGenre : (video.artist ?? "")
                    if !detail.isEmpty {
                        Text(detail)
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.72))
                            .lineLimit(1)
                    }
                }
            }
            Spacer()
        }
        .padding(.leading, 86)
        .padding(.trailing, 22)
        .padding(.top, 12)
        .frame(height: 64)
        .background(WindowDragArea())
    }

    private var controls: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Text(HushStyle.timestamp(playback.currentTime))
                    .frame(minWidth: 52, alignment: .trailing)
                HushSlider(
                    value: playback.duration > 0 ? playback.currentTime / playback.duration : 0,
                    track: .white.opacity(0.2),
                    height: 5,
                    alwaysShowsKnob: true,
                    onChange: { fraction in playback.seek(to: fraction * playback.duration) }
                )
                Text("−" + HushStyle.timestamp(max(playback.duration - playback.currentTime, 0)))
                    .frame(minWidth: 52, alignment: .leading)
            }
            .font(HushStyle.rounded(11.5, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(.white.opacity(0.85))

            HStack(spacing: 18) {
                HStack(spacing: 8) {
                    Image(systemName: playback.volume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.8))
                        .frame(width: 18)
                    HushSlider(
                        value: playback.volume,
                        tint: .white.opacity(0.9),
                        track: .white.opacity(0.2),
                        knobColor: .white,
                        onChange: { playback.volume = $0 }
                    )
                    .frame(width: 96)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 22) {
                    Button { playback.previous() } label: {
                        Image(systemName: "backward.end.fill").font(.system(size: 17))
                    }
                    .buttonStyle(HushIconButtonStyle(idle: .white.opacity(0.9), hover: .white))
                    .disabled(!playback.canGoBack)
                    .opacity(playback.canGoBack ? 1 : 0.35)
                    .help("Previous (⌘←)")
                    Button { playback.skip(by: -10) } label: {
                        Image(systemName: "gobackward.10").font(.system(size: 20, weight: .medium))
                    }
                    .buttonStyle(HushIconButtonStyle(idle: .white.opacity(0.9), hover: .white))
                    .help("Back 10 seconds (←)")
                    Button { playback.togglePlayPause() } label: {
                        Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(HushStyle.paper)
                            .contentTransition(.symbolEffect(.replace.downUp))
                            .frame(width: 44, height: 44)
                            .background(HushStyle.gold, in: Circle())
                    }
                    .buttonStyle(PressScaleButtonStyle())
                    .help(playback.isPlaying ? "Pause (Space)" : "Play (Space)")
                    Button { playback.skip(by: 10) } label: {
                        Image(systemName: "goforward.10").font(.system(size: 20, weight: .medium))
                    }
                    .buttonStyle(HushIconButtonStyle(idle: .white.opacity(0.9), hover: .white))
                    .help("Forward 10 seconds (→)")
                    Button { playback.next() } label: {
                        Image(systemName: "forward.end.fill").font(.system(size: 17))
                    }
                    .buttonStyle(HushIconButtonStyle(idle: .white.opacity(0.9), hover: .white))
                    .disabled(!playback.hasNext)
                    .opacity(playback.hasNext ? 1 : 0.35)
                    .help("Next (⌘→)")
                }

                HStack(spacing: 14) {
                    mediaOptionsMenu
                    gravityPicker
                    if AVPictureInPictureController.isPictureInPictureSupported() {
                        Button { playback.startPictureInPicture() } label: {
                            Image(systemName: "pip.enter").font(.system(size: 15, weight: .medium))
                        }
                        .buttonStyle(HushIconButtonStyle(idle: .white.opacity(0.85), hover: .white))
                        .disabled(!playback.canStartPictureInPicture)
                        .opacity(playback.canStartPictureInPicture ? 1 : 0.35)
                        .help("Picture in Picture (P)")
                    }
                    Button { toggleFullScreen() } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right").font(.system(size: 14, weight: .semibold))
                    }
                    .buttonStyle(HushIconButtonStyle(idle: .white.opacity(0.85), hover: .white))
                    .help("Full Screen (F)")
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .frame(maxWidth: 1000)
        .hushGlass(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.5), radius: 25, y: 10)
        .padding(.horizontal, 20)
        .padding(.bottom, 28)
    }

    private var gravityPicker: some View {
        HStack(spacing: 2) {
            ForEach(VideoGravity.allCases) { option in
                Button {
                    playback.gravity = option
                } label: {
                    Text(option.title)
                        .font(HushStyle.rounded(11.5, weight: .semibold))
                        .foregroundStyle(playback.gravity == option ? HushStyle.paper : .white.opacity(0.85))
                        .padding(.horizontal, 10)
                        .frame(height: 24)
                        .background(Capsule().fill(playback.gravity == option ? HushStyle.gold : .clear))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Capsule().fill(.white.opacity(0.10)))
        .help("Fit, Fill or Zoom (Z)")
        .animation(.easeOut(duration: 0.15), value: playback.gravity)
    }

    private var mediaOptionsMenu: some View {
        Menu {
            Section("Subtitles") {
                Button {
                    playback.selectSubtitles(nil)
                } label: {
                    if playback.selectedLegible == nil { Label("Off", systemImage: "checkmark") } else { Text("Off") }
                }
                ForEach(playback.legibleOptions, id: \.self) { option in
                    Button {
                        playback.selectSubtitles(option)
                    } label: {
                        if playback.selectedLegible == option {
                            Label(option.displayName, systemImage: "checkmark")
                        } else {
                            Text(option.displayName)
                        }
                    }
                }
            }
            if playback.audibleOptions.count > 1 {
                Section("Audio") {
                    ForEach(playback.audibleOptions, id: \.self) { option in
                        Button {
                            playback.selectAudio(option)
                        } label: {
                            if playback.selectedAudible == option {
                                Label(option.displayName, systemImage: "checkmark")
                            } else {
                                Text(option.displayName)
                            }
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "captions.bubble").font(.system(size: 15, weight: .medium))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .tint(.white)
        .foregroundStyle(.white.opacity(0.85))
        .help("Subtitles and Audio")
    }

    private func showControls() {
        controlsVisible = true
        NSCursor.setHiddenUntilMouseMoves(false)
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(nanoseconds: 2_800_000_000)
            guard !Task.isCancelled, playback.isPlaying, !isOverControls else { return }
            controlsVisible = false
            NSCursor.setHiddenUntilMouseMoves(true)
        }
    }

    private func toggleFullScreen() {
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow else { return }
        let isFull = window.styleMask.contains(.fullScreen)
        playback.enteredFullScreen = !isFull
        window.toggleFullScreen(nil)
    }
}
