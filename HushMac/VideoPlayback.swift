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

    /// Upscale and lightly sharpen the picture (on by default, remembered).
    var enhance: Bool {
        didSet { UserDefaults.standard.set(enhance, forKey: Keys.enhance) }
    }

    var volume: Double {
        didSet {
            player.volume = Float(volume)
            UserDefaults.standard.set(volume, forKey: Keys.volume)
        }
    }

    let player = AVPlayer()

    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []
    @ObservationIgnored private var endObserver: NSObjectProtocol?
    @ObservationIgnored private var isSeeking = false
    /// Whether opening the video put the window in full screen (so closing it leaves full screen too).
    @ObservationIgnored var enteredFullScreen = false

    private enum Keys {
        static let gravity = "hush.mac.videoGravity"
        static let volume = "hush.mac.videoVolume"
        static let enhance = "hush.mac.videoEnhance"
    }

    var isShowing: Bool { current != nil }
    var handlesMediaKeys: Bool { current != nil }

    private init() {
        gravity = VideoGravity(rawValue: UserDefaults.standard.string(forKey: Keys.gravity) ?? "") ?? .fill
        enhance = UserDefaults.standard.object(forKey: Keys.enhance) as? Bool ?? true
        volume = UserDefaults.standard.object(forKey: Keys.volume) as? Double ?? 1
        player.volume = Float(volume)
        observePlayer()
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

// MARK: - The video surface

/// The video picture. Underneath, an AVPlayerLayer that follows Fit / Fill / Zoom (and drives
/// Picture in Picture); with Enhance on, a Metal layer on top shows each frame upscaled and lightly
/// sharpened (VideoEnhancer). If enhancement can't run, the Metal layer simply stays hidden and the
/// plain picture shows.
struct VideoSurface: NSViewRepresentable {
    let player: AVPlayer
    let gravity: VideoGravity
    let enhance: Bool
    @Binding var pictureInPicture: AVPictureInPictureController?

    final class SurfaceView: NSView {
        let playerLayer = AVPlayerLayer()
        private let metalLayer = CAMetalLayer()
        private var renderer: EnhancedRenderer?
        private var enhancerFailed = false
        private var output: AVPlayerItemVideoOutput?
        private weak var outputItem: AVPlayerItem?
        private var itemObservation: NSKeyValueObservation?
        /// The item Enhance gave up on (frames kept running late); it stays plain until the next video.
        private weak var suspendedItem: AVPlayerItem?

        var gravity: VideoGravity = .fill {
            didSet {
                guard gravity != oldValue else { return }
                needsLayout = true
                renderer?.setGravity(gravity)
            }
        }

        var enhance = false {
            didSet { if enhance != oldValue { updateEnhancement() } }
        }

        weak var player: AVPlayer? {
            didSet {
                playerLayer.player = player
                itemObservation = player?.observe(\.currentItem, options: [.initial, .new]) { [weak self] player, _ in
                    DispatchQueue.main.async { self?.itemChanged(player.currentItem) }
                }
            }
        }

        #if HUSH_BENCH
        nonisolated(unsafe) static var benchPresented: ((CFTimeInterval) -> Void)?
        static var benchDrawableSize: CGSize?
        #endif

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            layer = CALayer()
            layer?.backgroundColor = NSColor.black.cgColor
            layer?.masksToBounds = true
            layer?.addSublayer(playerLayer)
            metalLayer.pixelFormat = .bgra8Unorm
            metalLayer.framebufferOnly = true
            metalLayer.isOpaque = true
            metalLayer.isHidden = true
            metalLayer.maximumDrawableCount = 3
            metalLayer.actions = ["bounds": NSNull(), "position": NSNull(), "contents": NSNull(), "hidden": NSNull()]
            layer?.addSublayer(metalLayer)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

        override func layout() {
            super.layout()
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.35)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeInEaseOut))
            playerLayer.frame = bounds
            playerLayer.videoGravity = gravity.layerGravity
            playerLayer.setAffineTransform(CGAffineTransform(scaleX: gravity.scale, y: gravity.scale))
            CATransaction.commit()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            metalLayer.frame = bounds
            // The panel's real pixels.
            let scale = window?.screen?.backingScaleFactor ?? window?.backingScaleFactor ?? 2
            metalLayer.contentsScale = scale
            metalLayer.drawableSize = CGSize(width: max(bounds.width * scale, 1), height: max(bounds.height * scale, 1))
            #if HUSH_BENCH
            if let forced = SurfaceView.benchDrawableSize { metalLayer.drawableSize = forced }
            #endif
            CATransaction.commit()
            renderer?.requestRedraw()
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            updateEnhancement()
        }

        // MARK: Enhancement on and off

        private func updateEnhancement() {
            let item = player?.currentItem
            guard enhance, !enhancerFailed, window != nil, item == nil || item !== suspendedItem else {
                stopRenderer()
                return
            }
            if renderer == nil {
                guard let enhancer = VideoEnhancer() else {
                    enhancerFailed = true
                    hushLog.info("Enhance: not available on this Mac; plain picture")
                    return
                }
                metalLayer.device = enhancer.device
                let renderer = EnhancedRenderer(enhancer: enhancer, layer: metalLayer)
                renderer.setGravity(gravity)
                renderer.onShowing = { [weak self] in
                    guard let self, self.enhance, self.renderer === renderer else { return }
                    self.metalLayer.isHidden = false
                }
                renderer.onGiveUp = { [weak self] reason in
                    guard let self, self.renderer === renderer else { return }
                    hushLog.info("Enhance: \(reason, privacy: .public); plain picture")
                    self.suspendedItem = self.player?.currentItem
                    self.stopRenderer()
                }
                #if HUSH_BENCH
                renderer.benchPresented = SurfaceView.benchPresented
                #endif
                self.renderer = renderer
                renderer.start(link: displayLink(target: renderer, selector: #selector(EnhancedRenderer.tick(_:))))
            }
            attachOutput(to: item)
        }

        private func stopRenderer() {
            renderer?.stop()
            renderer = nil
            metalLayer.isHidden = true
            if let outputItem, let output { outputItem.remove(output) }
            output = nil
            outputItem = nil
        }

        private func itemChanged(_ item: AVPlayerItem?) {
            if item !== suspendedItem { suspendedItem = nil }
            if renderer == nil {
                updateEnhancement()
            } else {
                attachOutput(to: item)
            }
        }

        private func attachOutput(to item: AVPlayerItem?) {
            guard renderer != nil, item !== outputItem else { return }
            if let outputItem, let output { outputItem.remove(output) }
            metalLayer.isHidden = true
            guard let item else {
                renderer?.setSource(nil, presentationSize: .zero)
                output = nil
                outputItem = nil
                return
            }
            let output = AVPlayerItemVideoOutput(pixelBufferAttributes: VideoEnhancer.pixelBufferAttributes)
            item.add(output)
            self.output = output
            outputItem = item
            renderer?.setSource(output, presentationSize: item.presentationSize)
        }

        deinit {
            renderer?.stop()
            if let outputItem, let output { outputItem.remove(output) }
        }
    }

    func makeNSView(context: Context) -> SurfaceView {
        let view = SurfaceView()
        view.player = player
        view.gravity = gravity
        view.enhance = enhance
        if AVPictureInPictureController.isPictureInPictureSupported() {
            let controller = AVPictureInPictureController(playerLayer: view.playerLayer)
            DispatchQueue.main.async { pictureInPicture = controller }
        }
        return view
    }

    func updateNSView(_ view: SurfaceView, context: Context) {
        view.gravity = gravity
        view.enhance = enhance
    }
}

/// Draws enhanced frames on its own thread, paced by the display: on every refresh it takes the frame
/// due on screen at that refresh, and if the GPU is still busy the frame waits for the next refresh
/// instead of being dropped. Nothing here waits for the GPU. If frames keep running late for a few
/// seconds, it gives up and the plain picture takes over.
final class EnhancedRenderer: NSObject, @unchecked Sendable {
    private let enhancer: VideoEnhancer
    private let layer: CAMetalLayer
    private let lock = NSLock()
    private var thread: Thread?
    private var link: CADisplayLink?
    private var running = true

    // Shared with the main thread (under `lock`).
    private var output: AVPlayerItemVideoOutput?
    private var presentationSize = CGSize.zero
    private var gravity: VideoGravity = .fill
    private var redraw = false
    private var inFlight = 0
    private var gpuTimes: [Double] = []

    // Render thread only.
    private var pending: CVPixelBuffer?
    private var current: CVPixelBuffer?
    private var superResolution: AnyObject?
    private var superResolutionBusy = false
    private var superResolutionResult: HandedOffPixelBuffer?
    private var showing = false
    private var ticks = 0
    private var lateTicks = 0
    private var deferred = 0
    private var logged = Date()

    /// Called on the main thread when the first enhanced frame is on screen.
    var onShowing: (() -> Void)?
    /// Called on the main thread when enhancement gives up.
    var onGiveUp: ((String) -> Void)?
    #if HUSH_BENCH
    var benchPresented: ((CFTimeInterval) -> Void)?
    #endif

    init(enhancer: VideoEnhancer, layer: CAMetalLayer) {
        self.enhancer = enhancer
        self.layer = layer
    }

    func start(link: CADisplayLink) {
        self.link = link
        let thread = Thread { [self] in
            link.add(to: .current, forMode: .default)
            // Keeps the run loop alive until stop().
            RunLoop.current.add(NSMachPort(), forMode: .default)
            while lock.withLock({ running }) {
                _ = RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.5))
            }
            link.invalidate()
        }
        thread.name = "Hush video enhance"
        thread.qualityOfService = .userInteractive
        self.thread = thread
        thread.start()
    }

    func stop() {
        lock.withLock { running = false }
        link?.isPaused = true
    }

    func setSource(_ output: AVPlayerItemVideoOutput?, presentationSize: CGSize) {
        lock.withLock {
            self.output = output
            self.presentationSize = presentationSize
            redraw = false
        }
    }

    func setGravity(_ gravity: VideoGravity) {
        lock.withLock {
            self.gravity = gravity
            redraw = true
        }
    }

    func requestRedraw() {
        lock.withLock { redraw = true }
    }

    // MARK: Each refresh (render thread)

    @objc func tick(_ link: CADisplayLink) {
        let (output, needsRedraw, busy) = lock.withLock { (self.output, redraw, inFlight >= 2) }
        guard let output else {
            pending = nil
            current = nil
            return
        }

        // A finished super-resolution frame is shown at the refresh it was asked for.
        if let finished = superResolutionResult {
            superResolutionResult = nil
            if let buffer = finished.buffer { pending = buffer }
        }

        // The frame due on screen at the next refresh (one refresh further ahead while super
        // resolution is in the loop, since it takes a refresh to come back).
        let lookahead = superResolution != nil ? link.duration : 0
        let itemTime = output.itemTime(forHostTime: link.targetTimestamp + lookahead)
        if output.hasNewPixelBuffer(forItemTime: itemTime),
           let buffer = output.copyPixelBuffer(forItemTime: itemTime, itemTimeForDisplay: nil) {
            if #available(macOS 26.0, *), let upscaler = upscaler(for: buffer), upscaler.isReady {
                if !superResolutionBusy {
                    superResolutionBusy = true
                    let source = HandedOffPixelBuffer(buffer: buffer)
                    upscaler.process(buffer, time: itemTime) { [weak self] upscaled in
                        guard let self, let thread = self.thread else { return }
                        let result = HandedOffPixelBuffer(buffer: upscaled.buffer ?? source.buffer)
                        self.perform(#selector(self.superResolutionFinished(_:)), on: thread, with: Box(result), waitUntilDone: false)
                    }
                }
            } else {
                pending = buffer
            }
        }

        ticks += 1
        if let frame = pending {
            if busy {
                // The GPU hasn't caught up: keep the frame for the next refresh instead of dropping it.
                deferred += 1
                lateTicks += 1
            } else {
                pending = nil
                current = frame
                render(frame, link: link)
            }
        } else if needsRedraw, let frame = current, !busy {
            render(frame, link: link)
        }
        checkPace()
    }

    private final class Box: NSObject {
        let value: HandedOffPixelBuffer
        init(_ value: HandedOffPixelBuffer) { self.value = value }
    }

    @objc private func superResolutionFinished(_ box: Box) {
        superResolutionBusy = false
        superResolutionResult = box.value
    }

    @available(macOS 26.0, *)
    private func upscaler(for buffer: CVPixelBuffer) -> RealTimeSuperResolution? {
        let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
        if let existing = superResolution as? RealTimeSuperResolution {
            if existing.inputWidth == width && existing.inputHeight == height { return existing }
            superResolution = nil
        }
        guard width <= 960, height <= 960, RealTimeSuperResolution.supports(width: width, height: height) else { return nil }
        let made = RealTimeSuperResolution(width: width, height: height)
        superResolution = made
        return made
    }

    private func render(_ frame: CVPixelBuffer, link: CADisplayLink) {
        guard let drawable = layer.nextDrawable(), let commandBuffer = enhancer.queue.makeCommandBuffer() else { return }
        let target = drawable.texture
        let (gravity, presentation) = lock.withLock { () -> (VideoGravity, CGSize) in
            redraw = false
            inFlight += 1
            return (self.gravity, presentationSize)
        }
        let rect = Self.displayRect(for: frame, presentation: presentation, gravity: gravity,
                                    in: CGSize(width: target.width, height: target.height))
        guard enhancer.encode(source: frame, into: target, displayRect: rect, enhance: true, commandBuffer: commandBuffer) else {
            lock.withLock { inFlight -= 1 }
            giveUp("frame couldn't be drawn")
            return
        }
        #if HUSH_BENCH
        if let benchPresented { drawable.addPresentedHandler { benchPresented($0.presentedTime) } }
        #endif
        let refresh = link.duration
        commandBuffer.addCompletedHandler { [weak self] buffer in
            guard let self else { return }
            let ms = (buffer.gpuEndTime - buffer.gpuStartTime) * 1000
            let failed = buffer.status == .error
            self.lock.withLock {
                self.inFlight -= 1
                self.gpuTimes.append(ms)
            }
            if failed { self.giveUp("GPU error") }
            // A frame that took longer than a refresh on the GPU counts as late.
            if ms > refresh * 1000 { self.lock.withLock { self.slowFrames += 1 } }
        }
        commandBuffer.present(drawable)
        commandBuffer.commit()
        if !showing {
            showing = true
            DispatchQueue.main.async { [weak self] in self?.onShowing?() }
        }
    }

    private var slowFrames = 0

    /// Gives up if, over the last few seconds, a quarter of refreshes with a frame due were late.
    private func checkPace() {
        guard Date().timeIntervalSince(logged) >= 4 else { return }
        let (times, slow) = lock.withLock { () -> ([Double], Int) in
            defer { gpuTimes.removeAll(keepingCapacity: true); slowFrames = 0 }
            return (gpuTimes, slowFrames)
        }
        let frames = times.count
        if frames > 0 {
            let average = times.reduce(0, +) / Double(frames)
            let worst = times.max() ?? 0
            let size = layer.drawableSize
            hushLog.info("Enhance: \(frames, privacy: .public) frames, GPU \(String(format: "%.2f", average), privacy: .public) ms avg / \(String(format: "%.2f", worst), privacy: .public) ms max at \(Int(size.width), privacy: .public)x\(Int(size.height), privacy: .public); waited a refresh \(self.deferred, privacy: .public), slow \(slow, privacy: .public); super resolution \(self.superResolution != nil, privacy: .public)")
            let late = deferred + slow
            if frames >= 30, Double(late) / Double(frames + deferred) > 0.25 {
                giveUp("frames kept running late (\(late) of \(frames + deferred))")
            }
        }
        deferred = 0
        lateTicks = 0
        ticks = 0
        logged = Date()
    }

    private func giveUp(_ reason: String) {
        stop()
        DispatchQueue.main.async { [weak self] in self?.onGiveUp?(reason) }
    }

    /// Where the picture goes in the drawable (pixels, top-left origin) for Fit / Fill / Zoom,
    /// using the item's display aspect (so anamorphic video is right too).
    static func displayRect(for frame: CVPixelBuffer, presentation: CGSize, gravity: VideoGravity, in size: CGSize) -> CGRect {
        var aspect = CGSize(width: CVPixelBufferGetWidth(frame), height: CVPixelBufferGetHeight(frame))
        if presentation.width > 0, presentation.height > 0 { aspect = presentation }
        let fit = min(size.width / aspect.width, size.height / aspect.height)
        let fill = max(size.width / aspect.width, size.height / aspect.height)
        let scale: CGFloat
        switch gravity {
        case .fit: scale = fit
        case .fill: scale = fill
        case .zoom: scale = fill * gravity.scale
        }
        let width = aspect.width * scale, height = aspect.height * scale
        return CGRect(x: (size.width - width) / 2, y: (size.height - height) / 2, width: width, height: height)
    }
}

// MARK: - The full-window player

struct VideoPlayerView: View {
    @Environment(VideoPlayback.self) private var playback
    @State private var controlsVisible = true
    @State private var hideTask: Task<Void, Never>?
    @State private var pictureInPicture: AVPictureInPictureController?
    @State private var isOverControls = false

    var body: some View {
        @Bindable var playback = playback
        ZStack {
            Color.black
            VideoSurface(player: playback.player, gravity: playback.gravity, enhance: playback.enhance, pictureInPicture: $pictureInPicture)
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
                    enhanceToggle
                    gravityPicker
                    if let pictureInPicture {
                        Button { pictureInPicture.startPictureInPicture() } label: {
                            Image(systemName: "pip.enter").font(.system(size: 15, weight: .medium))
                        }
                        .buttonStyle(HushIconButtonStyle(idle: .white.opacity(0.85), hover: .white))
                        .help("Picture in Picture")
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

    private var enhanceToggle: some View {
        Button {
            playback.enhance.toggle()
        } label: {
            Label("Enhance", systemImage: "sparkles")
                .font(HushStyle.rounded(11.5, weight: .semibold))
                .foregroundStyle(playback.enhance ? HushStyle.paper : .white.opacity(0.85))
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(Capsule().fill(playback.enhance ? HushStyle.gold : .white.opacity(0.10)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(playback.enhance ? "Enhance is on: sharper upscaling (E)" : "Enhance is off (E)")
        .animation(.easeOut(duration: 0.15), value: playback.enhance)
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
