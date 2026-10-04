import AVFoundation
import AVKit
import MediaPlayer
import SwiftUI
import UIKit

// MARK: - Tile

/// One video in the Videos tab: a 16:9 still with its title written across the bottom and its
/// length in the corner, so the tiles can sit right next to each other.
struct VideoTile: View {
    let video: LibraryVideo

    var body: some View {
        VideoThumbnail(video: video)
            .overlay {
                // A soft dark fade at the bottom keeps the white title readable on bright stills.
                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0.78), location: 0),
                        .init(color: .black.opacity(0.35), location: 0.38),
                        .init(color: .clear, location: 0.62),
                    ],
                    startPoint: .bottom,
                    endPoint: .top
                )
                .allowsHitTesting(false)
            }
            .overlay(alignment: .bottomLeading) {
                Text(video.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 6)
            }
            .overlay(alignment: .topTrailing) {
                if let length = Self.lengthText(video.duration) {
                    Text(length)
                        .font(.system(size: 10, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                        .padding(6)
                }
            }
            .overlay(alignment: .topLeading) {
                // Not on this iPhone (still in the cloud) or copy-protected: can't be played here.
                if video.assetURL == nil {
                    Image(systemName: "icloud.and.arrow.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(5)
                        .background(.black.opacity(0.55), in: Circle())
                        .padding(6)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(video.artist.map { "\(video.title), \($0)" } ?? video.title)
            .accessibilityHint(video.assetURL == nil ? "Not downloaded to this iPhone" : "Plays the video")
            .accessibilityAddTraits(.isButton)
    }

    /// "4:41" or "1:02:07"; nil when the length isn't known.
    static func lengthText(_ duration: TimeInterval) -> String? {
        guard duration.isFinite, duration >= 1 else { return nil }
        let total = Int(duration.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Movies

/// One movie in the Movies tab: its poster and, when titles are switched on, the title with the
/// year and genre underneath.
struct MovieTile: View {
    let movie: LibraryVideo
    var showsTitle = true

    var body: some View {
        VStack(alignment: .leading, spacing: showsTitle ? 7 : 0) {
            MoviePoster(movie: movie)
                .overlay(alignment: .topTrailing) {
                    // Not on this iPhone (still in the cloud) or copy-protected: can't be played here.
                    if movie.assetURL == nil {
                        Image(systemName: "icloud.and.arrow.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(5)
                            .background(.black.opacity(0.62), in: Circle())
                            .padding(5)
                    }
                }

            if showsTitle {
                VStack(alignment: .leading, spacing: 2) {
                    Text(movie.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(HushStyle.ink)
                        .lineLimit(2, reservesSpace: true)
                        .multilineTextAlignment(.leading)
                    if let details = Self.details(movie) {
                        Text(details)
                            .font(.system(size: 11))
                            .foregroundStyle(HushStyle.muted)
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([movie.title, Self.details(movie)].compactMap { $0 }.joined(separator: ", "))
        .accessibilityHint(movie.assetURL == nil ? "Not downloaded to this iPhone" : "Plays the movie")
        .accessibilityAddTraits(.isButton)
    }

    /// "2019 · Drama"; nil when neither is known.
    static func details(_ movie: LibraryVideo) -> String? {
        let parts = [movie.year.map(String.init), movie.genre].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// A movie's poster in the usual 2:3 shape: its own artwork, or a placeholder when it has none.
struct MoviePoster: View {
    let movie: LibraryVideo
    @State private var image: UIImage?

    init(movie: LibraryVideo) {
        self.movie = movie
        _image = State(initialValue: VideoThumbnails.cached(movie.id))
    }

    var body: some View {
        Color.clear
            .aspectRatio(2.0 / 3.0, contentMode: .fit)
            .overlay {
                ZStack {
                    HushStyle.surface
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .transition(.opacity)
                    } else {
                        Image(systemName: "film")
                            .font(.system(size: 24, weight: .light))
                            .foregroundStyle(HushStyle.muted.opacity(0.7))
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .animation(.easeOut(duration: 0.2), value: image != nil)
            .task(id: movie.id) {
                guard image == nil else { return }
                let loaded = await VideoThumbnails.image(for: movie)
                guard !Task.isCancelled else { return }
                image = loaded
            }
    }
}

// MARK: - Thumbnails

/// A still for a video: the poster the Music app already has, or else a frame taken from the file.
struct VideoThumbnail: View {
    let video: LibraryVideo
    @State private var image: UIImage?

    init(video: LibraryVideo) {
        self.video = video
        _image = State(initialValue: VideoThumbnails.cached(video.id))
    }

    var body: some View {
        Color.clear
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .overlay {
                ZStack {
                    HushStyle.surface
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .transition(.opacity)
                    } else {
                        Image(systemName: "play.rectangle.fill")
                            .font(.system(size: 26, weight: .light))
                            .foregroundStyle(HushStyle.muted.opacity(0.7))
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .animation(.easeOut(duration: 0.2), value: image != nil)
            .task(id: video.id) {
                guard image == nil else { return }
                let loaded = await VideoThumbnails.image(for: video)
                guard !Task.isCancelled else { return }
                image = loaded
            }
    }
}

/// Makes each video's still once and keeps it, so scrolling back never does the work again.
@MainActor
enum VideoThumbnails {
    private static let cache: NSCache<NSNumber, UIImage> = {
        let cache = NSCache<NSNumber, UIImage>()
        cache.countLimit = 300
        return cache
    }()
    /// Stills being made right now, so a tile that reappears joins the work already under way.
    private static var inFlight: [UInt64: Task<UIImage?, Never>] = [:]

    static func cached(_ id: UInt64) -> UIImage? {
        cache.object(forKey: NSNumber(value: id))
    }

    static func image(for video: LibraryVideo) async -> UIImage? {
        let key = NSNumber(value: video.id)
        if let hit = cache.object(forKey: key) { return hit }
        if let pending = inFlight[video.id] { return await pending.value }

        // MediaPlayer hands out artwork reliably only on the main thread, so ask for it here.
        let posterSize = video.isMovie ? CGSize(width: 400, height: 600) : CGSize(width: 640, height: 360)
        let poster = video.item?.artwork?.image(at: posterSize)
        // A frame from the film would be wide, not poster-shaped: movies without artwork keep the placeholder.
        let url = video.isMovie ? nil : video.assetURL
        let duration = video.duration
        let work = Task<UIImage?, Never> {
            if let poster { return await poster.byPreparingForDisplay() ?? poster }
            guard let url else { return nil }
            return await frame(from: url, duration: duration)
        }
        inFlight[video.id] = work
        let image = await work.value
        inFlight[video.id] = nil
        if let image { cache.setObject(image, forKey: key) }
        return image
    }

    /// A frame from a fifth of the way in (the very start is often black or a logo).
    nonisolated private static func frame(from url: URL, duration: TimeInterval) async -> UIImage? {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 640, height: 640)
        let seconds = duration.isFinite && duration > 0 ? min(duration * 0.2, 30) : 5
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        guard let result = try? await generator.image(at: time) else { return nil }
        return UIImage(cgImage: result.image)
    }
}

// MARK: - Playback

/// Plays a video or movie in the system's full-screen player (scrubbing, AirPlay, subtitles, close button
/// and swipe-down all come with it), with previous and next buttons laid over it that move through the
/// list the video was opened from.
@MainActor
enum VideoPlayback {
    /// The player keeps only a weak link to its delegate, so this one lives for the whole app.
    private static let delegate = PlayerDelegate()
    /// What's showing: the list it came from (only videos on this iPhone) and where in it we are.
    private static var queue: [LibraryVideo] = []
    private static var index = 0
    private static weak var controller: AVPlayerViewController?
    private static var remoteTargets: [(MPRemoteCommand, Any)] = []
    private static var pauseObservation: NSKeyValueObservation?
    static let skipControls = VideoSkipControls()

    /// Opens the player. Returns false when the video can't be played here (no file on this iPhone).
    @discardableResult
    static func present(_ video: LibraryVideo, in list: [LibraryVideo]? = nil) -> Bool {
        guard let url = video.assetURL, let presenter = topViewController() else { return false }

        // Same category the music uses: sound plays even with the silent switch on.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)

        let playable = (list ?? [video]).filter { $0.assetURL != nil }
        queue = playable.isEmpty ? [video] : playable
        index = queue.firstIndex(where: { $0.id == video.id }) ?? 0

        let player = AVPlayer(playerItem: makeItem(url: url, video: video))
        let controller = AVPlayerViewController()
        controller.player = player
        controller.modalPresentationStyle = .fullScreen
        // Picture in Picture would leave a video playing after its screen is gone; keep it simple.
        controller.allowsPictureInPicturePlayback = false
        controller.delegate = delegate
        self.controller = controller
        enableRemoteCommands()
        presenter.present(controller, animated: true) {
            player.play()
            // Added once the player is on screen, so they sit above its own controls layer.
            if queue.count > 1 { addSkipControls(to: controller) }
        }
        return true
    }

    // MARK: Previous and next

    static var hasNext: Bool { index + 1 < queue.count }
    static var hasPrevious: Bool { index > 0 }

    /// The next video in the list.
    static func next() {
        guard hasNext else { return }
        Haptics.tap()
        show(at: index + 1)
    }

    /// Restarts the video if it's more than 3 seconds in; otherwise the previous one in the list.
    static func previous() {
        guard let player = controller?.player else { return }
        Haptics.tap()
        if player.currentTime().seconds > 3 || !hasPrevious {
            player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero) { finished in
                guard finished else { return }
                Task { @MainActor in player.play() }
            }
        } else {
            show(at: index - 1)
        }
    }

    private static func show(at newIndex: Int) {
        guard queue.indices.contains(newIndex), let player = controller?.player,
              let url = queue[newIndex].assetURL else { return }
        index = newIndex
        player.replaceCurrentItem(with: makeItem(url: url, video: queue[newIndex]))
        player.play()
        skipControls.update(hasPrevious: hasPrevious, hasNext: hasNext)
    }

    private static func makeItem(url: URL, video: LibraryVideo) -> AVPlayerItem {
        let item = AVPlayerItem(url: url)
        item.externalMetadata = metadata(for: video)
        return item
    }

    /// The buttons sit over the system player, either side of its own controls, and come and go
    /// with them (a tap, a pause or a new video shows them; they fade a few seconds later).
    private static func addSkipControls(to controller: AVPlayerViewController) {
        // UIKit buttons: unlike SwiftUI ones, they win taps over the player's own tap gesture.
        let previous = SkipButton(symbol: "backward.end.fill", label: "Previous") { VideoPlayback.previous() }
        let next = SkipButton(symbol: "forward.end.fill", label: "Next") { VideoPlayback.next() }
        skipControls.attach(previous: previous, next: next)
        skipControls.update(hasPrevious: hasPrevious, hasNext: hasNext)
        // The system's skip-back / play / skip-forward cluster is centred; these sit in a row just
        // under it, so they never cover it whatever the phone's size or orientation.
        for (button, offset) in [(previous, -44.0), (next, 44.0)] {
            controller.view.addSubview(button)
            NSLayoutConstraint.activate([
                button.widthAnchor.constraint(equalToConstant: 48),
                button.heightAnchor.constraint(equalToConstant: 48),
                button.centerXAnchor.constraint(equalTo: controller.view.centerXAnchor, constant: offset),
                button.centerYAnchor.constraint(equalTo: controller.view.centerYAnchor, constant: 92),
            ])
        }
        let tap = UITapGestureRecognizer(target: skipControls, action: #selector(VideoSkipControls.screenTapped))
        tap.cancelsTouchesInView = false
        tap.delegate = skipControls
        controller.view.addGestureRecognizer(tap)
        // Pausing brings the system controls up: these follow.
        if let player = controller.player {
            pauseObservation = player.observe(\.timeControlStatus, options: [.new]) { player, _ in
                let paused = player.timeControlStatus == .paused
                Task { @MainActor in skipControls.setPaused(paused) }
            }
        }
        skipControls.show()
    }

    /// Lock screen and Control Center next/previous move through the videos while one is open.
    private static func enableRemoteCommands() {
        disableRemoteCommands()
        let center = MPRemoteCommandCenter.shared()
        let nextTarget = center.nextTrackCommand.addTarget { _ in
            MainActor.assumeIsolated { next() }
            return .success
        }
        let previousTarget = center.previousTrackCommand.addTarget { _ in
            MainActor.assumeIsolated { previous() }
            return .success
        }
        remoteTargets = [(center.nextTrackCommand, nextTarget), (center.previousTrackCommand, previousTarget)]
    }

    private static func disableRemoteCommands() {
        for (command, target) in remoteTargets { command.removeTarget(target) }
        remoteTargets = []
    }

    /// The player has closed.
    fileprivate static func didClose() {
        disableRemoteCommands()
        pauseObservation = nil
        queue = []
    }

    /// Title and artist for the player's own title area.
    private static func metadata(for video: LibraryVideo) -> [AVMetadataItem] {
        func entry(_ identifier: AVMetadataIdentifier, _ value: String) -> AVMetadataItem {
            let item = AVMutableMetadataItem()
            item.identifier = identifier
            item.value = value as NSString
            item.extendedLanguageTag = "und"
            return item
        }
        var items = [entry(.commonIdentifierTitle, video.title)]
        if let artist = video.artist { items.append(entry(.commonIdentifierArtist, artist)) }
        return items
    }

    /// The screen that's showing right now (the library, or whatever is presented over it).
    private static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap(\.windows).first(where: \.isKeyWindow) ?? scenes.flatMap(\.windows).first
        var top = window?.rootViewController
        while let next = top?.presentedViewController, !next.isBeingDismissed { top = next }
        return top
    }

    private final class PlayerDelegate: NSObject, AVPlayerViewControllerDelegate {
        /// The player is closing: make sure the sound stops with it, and turn the app back upright.
        func playerViewController(
            _ playerViewController: AVPlayerViewController,
            willEndFullScreenPresentationWithAnimationCoordinator coordinator: UIViewControllerTransitionCoordinator
        ) {
            // UIKit always calls this on the main thread.
            MainActor.assumeIsolated {
                _ = coordinator.animate(alongsideTransition: nil) { context in
                    // A swipe-down that was let go and sprang back: the video is still on screen.
                    guard !context.isCancelled else { return }
                    MainActor.assumeIsolated {
                        playerViewController.player?.pause()
                        VideoPlayback.didClose()
                        HushAppDelegate.refreshSupportedOrientations()
                    }
                }
            }
        }
    }
}

/// Shows and hides the previous/next buttons and keeps them enabled only where there's somewhere to go.
@MainActor
final class VideoSkipControls: NSObject, UIGestureRecognizerDelegate {
    private weak var previous: SkipButton?
    private weak var next: SkipButton?
    private var hideTask: Task<Void, Never>?

    func attach(previous: SkipButton, next: SkipButton) {
        self.previous = previous
        self.next = next
        previous.onPress = { [weak self] in self?.show() }
        next.onPress = { [weak self] in self?.show() }
    }

    func update(hasPrevious: Bool, hasNext: Bool) {
        // Previous always works: it restarts the first video.
        previous?.isEnabled = true
        next?.isEnabled = hasNext
    }

    /// Pausing (or reaching the end) brings the system controls up for a moment: these too.
    func setPaused(_ paused: Bool) {
        if paused { show() }
    }

    /// Shows the buttons, then fades them out with the system controls (about 3 seconds).
    func show() {
        for button in [previous, next].compactMap({ $0 }) {
            button.superview?.bringSubviewToFront(button)
            button.isHidden = false
        }
        UIView.animate(withDuration: 0.2) { self.setAlpha(1) }
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_200_000_000)
            guard !Task.isCancelled, let self else { return }
            UIView.animate(withDuration: 0.3, animations: { self.setAlpha(0) }) { _ in
                if self.hideTask == nil || self.hideTask?.isCancelled == false {
                    for button in [self.previous, self.next].compactMap({ $0 }) where button.alpha == 0 { button.isHidden = true }
                }
            }
        }
    }

    private func setAlpha(_ alpha: CGFloat) {
        previous?.alpha = alpha
        next?.alpha = alpha
    }

    /// A tap on the video brings the system controls up (or hides them): these show for a few
    /// seconds either way, so they're always there when the controls are.
    @objc func screenTapped() {
        show()
    }

    nonisolated func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }
}

/// A round frosted button with a white symbol, in the style of the system player's own controls.
final class SkipButton: UIButton {
    private let action: () -> Void
    var onPress: (() -> Void)?

    init(symbol: String, label: String, action: @escaping () -> Void) {
        self.action = action
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
        blur.isUserInteractionEnabled = false
        blur.translatesAutoresizingMaskIntoConstraints = false
        blur.layer.cornerRadius = 24
        blur.clipsToBounds = true
        insertSubview(blur, at: 0)
        NSLayoutConstraint.activate([
            blur.leadingAnchor.constraint(equalTo: leadingAnchor),
            blur.trailingAnchor.constraint(equalTo: trailingAnchor),
            blur.topAnchor.constraint(equalTo: topAnchor),
            blur.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        setImage(UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 19, weight: .semibold)), for: .normal)
        tintColor = .white
        if let imageView { bringSubviewToFront(imageView) }
        accessibilityLabel = label
        addTarget(self, action: #selector(pressed), for: .touchUpInside)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isEnabled: Bool {
        didSet { imageView?.alpha = isEnabled ? 1 : 0.35 }
    }

    override var isHighlighted: Bool {
        didSet { transform = isHighlighted ? CGAffineTransform(scaleX: 0.9, y: 0.9) : .identity }
    }

    @objc private func pressed() {
        onPress?()
        action()
    }
}

// MARK: - Rotation

/// Hush is an upright-only app, except while a video is on screen: then the phone can be turned
/// sideways to fill the screen with it.
final class HushAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        var top = window?.rootViewController
        while let next = top?.presentedViewController { top = next }
        if let top, top is AVPlayerViewController, !top.isBeingDismissed {
            return .allButUpsideDown
        }
        return .portrait
    }

    /// Asks the system to look again at which ways the app may be turned (after a video closes).
    @MainActor
    static func refreshSupportedOrientations() {
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            for window in scene.windows {
                window.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
            }
        }
    }
}
