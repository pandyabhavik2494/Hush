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
/// and swipe-down all come with it).
@MainActor
enum VideoPlayback {
    /// The player keeps only a weak link to its delegate, so this one lives for the whole app.
    private static let delegate = PlayerDelegate()

    /// Opens the player. Returns false when the video can't be played here (no file on this iPhone).
    @discardableResult
    static func present(_ video: LibraryVideo) -> Bool {
        guard let url = video.assetURL, let presenter = topViewController() else { return false }

        // Same category the music uses: sound plays even with the silent switch on.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)

        let item = AVPlayerItem(url: url)
        item.externalMetadata = metadata(for: video)
        let player = AVPlayer(playerItem: item)
        let controller = AVPlayerViewController()
        controller.player = player
        controller.modalPresentationStyle = .fullScreen
        // Picture in Picture would leave a video playing after its screen is gone; keep it simple.
        controller.allowsPictureInPicturePlayback = false
        controller.delegate = delegate
        presenter.present(controller, animated: true) {
            player.play()
        }
        return true
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
                        HushAppDelegate.refreshSupportedOrientations()
                    }
                }
            }
        }
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

// MARK: - Apple TV purchases

/// Opens the TV app, where Apple TV purchases play. (iOS doesn't let other apps open a specific
/// library item there.)
@MainActor
enum AppleTVHandOff {
    static func open(_ title: String, toast: (String) -> Void) {
        Haptics.tap()
        toast("Opening \(title) in the TV app")
        guard let url = URL(string: "videos://") else { return }
        UIApplication.shared.open(url)
    }
}

/// A purchase's artwork, 16:9 (movie key art or an episode still).
struct PurchaseArtwork: View {
    let item: MPMediaItem?
    var cornerRadius: CGFloat = 8
    var symbol = "tv"
    @State private var image: UIImage?

    var body: some View {
        Color.clear
            .aspectRatio(16 / 9, contentMode: .fit)
            .overlay {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    ZStack {
                        LinearGradient(
                            colors: [Color(red: 0.53, green: 0.39, blue: 0.15), Color(red: 0.20, green: 0.16, blue: 0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        Image(systemName: symbol)
                            .font(.system(size: 24, weight: .light))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .task(id: item?.persistentID) {
                guard let item else { return }
                // Purchases still in the cloud often have no artwork until the library has fetched it,
                // so a miss gets one more try a little later.
                var raw = Self.artwork(of: item)
                if raw == nil {
                    try? await Task.sleep(for: .seconds(2))
                    guard !Task.isCancelled else { return }
                    raw = Self.artwork(of: item)
                }
                guard let raw else {
                    hushLog.debug("No artwork for purchase \(item.title ?? "?", privacy: .public) (cloud: \(item.isCloudItem, privacy: .public))")
                    return
                }
                image = await raw.byPreparingForDisplay() ?? raw
            }
            .accessibilityHidden(true)
    }
}

/// An Apple TV movie: 16:9 key art; the title only when titles are on.
extension PurchaseArtwork {
    /// The item's art at its own shape (16:9 for movies and stills), at most 640 points wide; a fixed
    /// 16:9 size when the art doesn't report one. MediaPlayer hands out artwork reliably only on the
    /// main thread; the decode happens off it.
    @MainActor
    static func artwork(of item: MPMediaItem) -> UIImage? {
        guard let artwork = item.artwork else { return nil }
        let bounds = artwork.bounds.size
        let size = bounds.width > 0 && bounds.height > 0
            ? CGSize(width: min(bounds.width, 640), height: min(bounds.width, 640) * bounds.height / bounds.width)
            : CGSize(width: 640, height: 360)
        return artwork.image(at: size) ?? artwork.image(at: CGSize(width: 640, height: 360))
    }
}

struct AppleTVMovieTile: View {
    let movie: LibraryVideo
    let showsTitle: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            PurchaseArtwork(item: movie.item, cornerRadius: 8, symbol: "appletv")
            if showsTitle {
                VStack(alignment: .leading, spacing: 2) {
                    Text(movie.title)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(HushStyle.ink)
                        .lineLimit(1)
                    Text([movie.year.map(String.init), movie.genre].compactMap { $0 }.joined(separator: " · "))
                        .font(.system(size: 11.5, design: .rounded))
                        .foregroundStyle(HushStyle.muted)
                        .lineLimit(1)
                }
                .padding(.horizontal, 2)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(movie.title), opens in the TV app")
    }
}

/// An Apple TV show: its first episode's still with the name over a dark fade.
struct AppleTVShowTile: View {
    let show: AppleTVShowItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            PurchaseArtwork(item: show.artworkItem, cornerRadius: 10)
                .overlay(alignment: .bottomLeading) {
                    Text(show.name)
                        .font(.system(size: 19, weight: .regular, design: .serif))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(LinearGradient(colors: [.black.opacity(0.72), .clear], startPoint: .bottom, endPoint: .top))
                }
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            Text(show.episodesText)
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(HushStyle.muted)
                .padding(.horizontal, 2)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(show.name), \(show.episodesText)")
    }
}

/// A show page: a wide still, the name, seasons and episodes, Open in the TV app, season filters
/// and the episodes (each opens the TV app).
struct AppleTVShowPage: View {
    let show: AppleTVShowItem
    let toast: (String) -> Void
    @State private var season: Int?

    var body: some View {
        let seasons = show.seasons
        let current = season.flatMap { seasons.contains($0) ? $0 : nil } ?? seasons.first ?? 1
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                PurchaseArtwork(item: show.artworkItem, cornerRadius: 14)
                    .shadow(color: .black.opacity(0.5), radius: 20, y: 14)
                Text(show.name)
                    .font(.system(size: 30, weight: .regular, design: .serif))
                    .foregroundStyle(HushStyle.ink)
                    .padding(.top, 6)
                Text("\(show.seasonsText) · \(show.episodesText)")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(HushStyle.muted)
                Button {
                    AppleTVHandOff.open(show.name, toast: toast)
                } label: {
                    Label("Open in the TV app", systemImage: "arrow.up.forward.app")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(HushStyle.paper)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(HushStyle.gold, in: Capsule())
                }
                .buttonStyle(PopButtonStyle())
                if seasons.count > 1 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(seasons, id: \.self) { number in
                                Button {
                                    Haptics.tap()
                                    withAnimation(.snappy(duration: 0.25)) { season = number }
                                } label: {
                                    Text("Season \(number)")
                                        .font(.system(size: 13, weight: number == current ? .semibold : .medium, design: .rounded))
                                        .foregroundStyle(number == current ? HushStyle.paper : HushStyle.ink.opacity(0.9))
                                        .padding(.horizontal, 14)
                                        .frame(height: 32)
                                        .background(number == current ? HushStyle.gold : HushStyle.surface, in: Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .scrollClipDisabled()
                    .padding(.top, 6)
                }
                LazyVStack(spacing: 0) {
                    ForEach(show.episodes.filter { $0.season == current }) { episode in
                        Button {
                            AppleTVHandOff.open("\(show.name) S\(episode.season) E\(episode.number)", toast: toast)
                        } label: {
                            HStack(spacing: 12) {
                                PurchaseArtwork(item: episode.item, cornerRadius: 6)
                                    .frame(width: 112)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(episode.number > 0 ? "Episode \(episode.number)" : "Episode")
                                        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                                        .foregroundStyle(HushStyle.muted)
                                    Text(episode.title)
                                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                                        .foregroundStyle(HushStyle.ink)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                Text(HushStyle.durationText(episode.duration) ?? "")
                                    .font(.system(size: 12, design: .rounded))
                                    .foregroundStyle(HushStyle.muted)
                            }
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Season \(episode.season) episode \(episode.number), \(episode.title), opens in the TV app")
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(HushStyle.paper.ignoresSafeArea())
        .navigationTitle(show.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
