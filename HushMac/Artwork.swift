import AppKit
import AVFoundation
import CoreImage
import ImageIO
import iTunesLibrary
import MusicKit
import SwiftUI

/// An image that can be handed between threads (NSImage is immutable once made).
struct SendableImage: @unchecked Sendable {
    let image: NSImage
}

/// Album covers, posters and video stills from the Music and TV libraries, decoded in the
/// background at the size they're shown and cached. Several views asking for the same image share
/// one decode.
final class ArtworkStore: @unchecked Sendable {
    static let shared = ArtworkStore()

    enum Kind: Sendable {
        /// The library's artwork, else the art inside the file.
        case cover
        /// A frame from the video (music video tiles are 16:9 stills), else its artwork.
        case videoStill
    }

    private let lock = NSLock()
    private var library: ITLibrary?
    private var items: [UInt64: ITLibMediaItem] = [:]
    private var locations: [UInt64: URL] = [:]
    private var albumsByTrack: [UInt64: AlbumArtInfo] = [:]
    private var inFlight: [String: Task<SendableImage?, Never>] = [:]
    private let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.totalCostLimit = 260 * 1024 * 1024
        return cache
    }()
    private let blurCache: NSCache<NSNumber, NSImage> = {
        let cache = NSCache<NSNumber, NSImage>()
        cache.countLimit = 60
        return cache
    }()
    private let colorCache: NSCache<NSNumber, CoverColors> = {
        let cache = NSCache<NSNumber, CoverColors>()
        cache.countLimit = 120
        return cache
    }()
    private let blurContext = CIContext()

    /// Called by the library loader. Keeps the library object alive so artwork can be read later.
    func register(library: ITLibrary, items: [UInt64: ITLibMediaItem], locations: [UInt64: URL], albums: [Album]) {
        var byTrack: [UInt64: AlbumArtInfo] = [:]
        for album in albums {
            let info = AlbumArtInfo(id: album.id, title: album.title, artist: album.artist,
                                    trackIDs: album.tracks.map(\.id), firstSongTitle: album.tracks.first?.title)
            for track in album.tracks { byTrack[track.id] = info }
        }
        lock.withLock {
            self.library = library
            self.items = items
            self.locations = locations
            self.albumsByTrack = byTrack
        }
    }

    static func key(_ id: UInt64, _ pixels: Int, _ kind: Kind = .cover) -> String {
        "\(id)-\(pixels)-\(kind == .cover ? "c" : "v")"
    }

    /// Instant check — never does any work.
    func cached(_ id: UInt64, pixels: Int, kind: Kind = .cover) -> NSImage? {
        cache.object(forKey: Self.key(id, pixels, kind) as NSString)
    }

    func image(for id: UInt64, pixels: Int, kind: Kind = .cover) async -> NSImage? {
        let key = Self.key(id, pixels, kind)
        if let hit = cache.object(forKey: key as NSString) { return hit }
        let task: Task<SendableImage?, Never> = lock.withLock {
            if let existing = inFlight[key] { return existing }
            let task = Task.detached(priority: .utility) { [self] () -> SendableImage? in
                await self.decode(id: id, pixels: pixels, kind: kind)
            }
            inFlight[key] = task
            return task
        }
        let result = await task.value
        lock.withLock { inFlight[key] = nil }
        guard let image = result?.image else { return nil }
        cache.setObject(image, forKey: key as NSString, cost: max(pixels * pixels * 4, 1))
        return image
    }

    /// The library's artwork for this track; else another track of the same album that has some;
    /// else art embedded in the file; else (songs only) the album's cover from Apple's catalog.
    private func decode(id: UInt64, pixels: Int, kind: Kind) async -> SendableImage? {
        let (item, location, album) = lock.withLock { (items[id], locations[id], albumsByTrack[id]) }
        if kind == .videoStill, let location, let still = await Self.videoFrame(from: location, pixels: pixels) {
            return SendableImage(image: still)
        }
        var data = Self.libraryArtwork(item)
        if data == nil, let album {
            let siblings = lock.withLock { album.trackIDs.filter { $0 != id }.compactMap { items[$0] } }
            data = siblings.lazy.compactMap(Self.libraryArtwork).first
        }
        if data == nil, let location {
            data = await Self.embeddedArtwork(in: location)
        }
        if data == nil, let album {
            data = await CatalogArtwork.shared.cover(albumID: album.id, title: album.title, artist: album.artist, songTitle: album.firstSongTitle)
        }
        guard let data, let image = await Self.decodeOnQueue({ Self.thumbnail(from: data, pixels: pixels) }) else { return nil }
        return SendableImage(image: image)
    }

    private static func libraryArtwork(_ item: ITLibMediaItem?) -> Data? {
        guard let item, item.hasArtworkAvailable, let artwork = item.artwork else { return nil }
        return artwork.imageData ?? artwork.image?.tiffRepresentation
    }

    /// Cover art stored inside the file itself (used when the library has none).
    private static func embeddedArtwork(in url: URL) async -> Data? {
        let asset = AVURLAsset(url: url)
        guard let metadata = try? await asset.load(.commonMetadata) else { return nil }
        let artworkItems = AVMetadataItem.metadataItems(from: metadata, filteredByIdentifier: .commonIdentifierArtwork)
        guard let first = artworkItems.first else { return nil }
        return try? await first.load(.dataValue)
    }

    /// A frame from a fifth of the way in (the very start is often black or a logo).
    private static func videoFrame(from url: URL, pixels: Int) async -> NSImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: pixels, height: pixels)
        let duration = (try? await asset.load(.duration))?.seconds ?? 0
        let seconds = duration.isFinite && duration > 0 ? min(duration * 0.2, 30) : 5
        guard let result = try? await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600)) else { return nil }
        return NSImage(cgImage: result.image, size: NSSize(width: result.image.width, height: result.image.height))
    }

    /// Decodes straight to the needed size (fast, and light on memory).
    /// All ImageIO decoding runs here: one quality-of-service class (utility, so a higher-priority
    /// thread never waits on ImageIO's own lower-priority work) and at most four at a time (the Apple
    /// TV sections alone ask for hundreds of stills). Callers wait asynchronously, never blocking.
    private static let decodeQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "Hush artwork decoding"
        queue.qualityOfService = .utility
        queue.maxConcurrentOperationCount = 4
        return queue
    }()

    static func decodeOnQueue(_ work: @escaping @Sendable () -> NSImage?) async -> NSImage? {
        let result: SendableImage? = await withCheckedContinuation { continuation in
            decodeQueue.addOperation {
                continuation.resume(returning: work().map(SendableImage.init(image:)))
            }
        }
        return result?.image
    }

    static func thumbnail(from data: Data, pixels: Int) -> NSImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(pixels, 16),
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    // MARK: Blurred glows

    func cachedBlur(for id: UInt64) -> NSImage? {
        blurCache.object(forKey: NSNumber(value: id))
    }

    /// The cover heavily blurred and a little richer, for page glows. Made once per cover.
    func blurred(for id: UInt64) async -> NSImage? {
        if let hit = cachedBlur(for: id) { return hit }
        guard let small = await image(for: id, pixels: 240) else { return nil }
        let source = SendableImage(image: small)
        let result = await Task.detached(priority: .utility) { [self] () -> SendableImage? in
            guard let cgImage = source.image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
            let input = CIImage(cgImage: cgImage)
            let output = input
                .clampedToExtent()
                .applyingGaussianBlur(sigma: 24)
                .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 1.3])
                .cropped(to: input.extent)
            guard let blurredImage = self.blurContext.createCGImage(output, from: input.extent) else { return nil }
            return SendableImage(image: NSImage(cgImage: blurredImage, size: NSSize(width: blurredImage.width, height: blurredImage.height)))
        }.value
        guard let image = result?.image else { return nil }
        blurCache.setObject(image, forKey: NSNumber(value: id))
        return image
    }

    // MARK: Now Playing colours

    func cachedColors(for id: UInt64) -> CoverColors? {
        colorCache.object(forKey: NSNumber(value: id))
    }

    /// The cover's top and bottom edge colours (the phone's sampling, Shared/ArtworkColors.swift).
    func colors(for id: UInt64) async -> CoverColors? {
        if let hit = cachedColors(for: id) { return hit }
        guard let small = await image(for: id, pixels: 240) else { return nil }
        let source = SendableImage(image: small)
        let made = await Task.detached(priority: .utility) { () -> CoverColors? in
            guard let cgImage = source.image.cgImage(forProposedRect: nil, context: nil, hints: nil),
                  let edges = ArtworkColors.edgeColors(of: CIImage(cgImage: cgImage)) else { return nil }
            return CoverColors(top: edges.top, bottom: edges.bottom)
        }.value
        if let made { colorCache.setObject(made, forKey: NSNumber(value: id)) }
        return made
    }
}

/// What the artwork loader needs to know about a song's album to find a cover for it.
struct AlbumArtInfo: Sendable {
    let id: UInt64
    let title: String
    let artist: String
    let trackIDs: [UInt64]
    let firstSongTitle: String?
}

/// A cover's edge colours and how bright each is (0 = black … 1 = white).
final class CoverColors: @unchecked Sendable {
    let top: Color
    let bottom: Color
    let topBrightness: CGFloat
    let bottomBrightness: CGFloat

    init(top: ArtworkColors.RGB, bottom: ArtworkColors.RGB) {
        self.top = Color(red: top.red, green: top.green, blue: top.blue)
        self.bottom = Color(red: bottom.red, green: bottom.green, blue: bottom.blue)
        topBrightness = top.brightness
        bottomBrightness = bottom.brightness
    }
}

// MARK: - Views

/// A cover for a song or album (square), or a movie poster (2:3), or a video still (16:9).
/// Shows instantly when cached; otherwise fades in over a warm placeholder.
struct CoverView: View {
    let id: UInt64?
    var pixels = 400
    var cornerRadius: CGFloat = 8
    var aspectRatio: CGFloat = 1
    var kind: ArtworkStore.Kind = .cover
    var placeholderSymbol = "waveform"

    @State private var image: NSImage?
    @State private var loadedKey: String?

    var body: some View {
        let key = id.map { ArtworkStore.key($0, pixels, kind) }
        let shown = (loadedKey == key ? image : nil) ?? id.flatMap { ArtworkStore.shared.cached($0, pixels: pixels, kind: kind) }
        Color.clear
            .aspectRatio(aspectRatio, contentMode: .fit)
            .overlay {
                if let shown {
                    Image(nsImage: shown)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFill()
                        .transition(.opacity)
                } else {
                    CoverPlaceholder(symbol: placeholderSymbol)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .animation(.easeOut(duration: 0.2), value: shown != nil)
            .task(id: key) {
                guard let id, let key else { return }
                guard ArtworkStore.shared.cached(id, pixels: pixels, kind: kind) == nil else { return }
                let loaded = await ArtworkStore.shared.image(for: id, pixels: pixels, kind: kind)
                guard !Task.isCancelled, let loaded else { return }
                image = loaded
                loadedKey = key
            }
            .accessibilityHidden(true)
    }
}

/// Warm brass gradient with a symbol, for things without art.
struct CoverPlaceholder: View {
    var symbol = "waveform"

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                LinearGradient(
                    colors: [Color(red: 0.42, green: 0.31, blue: 0.13), Color(red: 0.16, green: 0.13, blue: 0.07)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Image(systemName: symbol)
                    .font(.system(size: max(min(geometry.size.width, geometry.size.height) * 0.28, 8), weight: .light))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
    }
}

/// Four covers in a square, for playlists (one cover when there aren't four different albums).
struct MosaicCover: View {
    let trackIDs: [UInt64]
    var pixels = 400
    var cornerRadius: CGFloat = 8

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if trackIDs.count >= 4 {
                    Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                        GridRow {
                            CoverView(id: trackIDs[0], pixels: pixels / 2, cornerRadius: 0)
                            CoverView(id: trackIDs[1], pixels: pixels / 2, cornerRadius: 0)
                        }
                        GridRow {
                            CoverView(id: trackIDs[2], pixels: pixels / 2, cornerRadius: 0)
                            CoverView(id: trackIDs[3], pixels: pixels / 2, cornerRadius: 0)
                        }
                    }
                } else if let first = trackIDs.first {
                    CoverView(id: first, pixels: pixels, cornerRadius: 0)
                } else {
                    ZStack {
                        HushStyle.surface
                        Image(systemName: "music.note.list")
                            .font(.system(size: 34, weight: .light))
                            .foregroundStyle(HushStyle.gold.opacity(0.8))
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

/// A playlist's cover: its own artwork from the Music app when there is one, else the mosaic.
struct PlaylistCover: View {
    let playlist: Playlist
    var pixels = 400
    var cornerRadius: CGFloat = 8
    @Environment(LibraryModel.self) private var library

    var body: some View {
        if let artwork = library.playlistArtwork(for: playlist) {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    GeometryReader { geometry in
                        ArtworkImage(artwork, width: geometry.size.width, height: geometry.size.height)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            MosaicCover(trackIDs: playlist.mosaicTrackIDs, pixels: pixels, cornerRadius: cornerRadius)
        }
    }

    /// Whether the cover carries the playlist's name (its own artwork does; a mosaic doesn't).
    static func hasOwnArtwork(_ playlist: Playlist, in library: LibraryModel) -> Bool {
        library.playlistArtwork(for: playlist) != nil
    }
}

/// The page's own cover, blurred into a soft glow at the top, fading into black.
struct ArtworkGlow: View {
    let id: UInt64?
    var height: CGFloat = 560
    var strength: Double = 0.55

    @State private var backdrop: NSImage?
    @State private var backdropID: UInt64?

    var body: some View {
        GeometryReader { geometry in
            if let backdrop {
                Image(nsImage: backdrop)
                    .resizable()
                    .scaledToFill()
                    .frame(width: geometry.size.width, height: height)
                    .clipped()
                    .opacity(strength)
                    .mask(
                        LinearGradient(
                            stops: [
                                .init(color: .black, location: 0),
                                .init(color: .black.opacity(0.5), location: 0.55),
                                .init(color: .clear, location: 1),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .id(backdropID)
                    .transition(.opacity)
            }
        }
        .frame(height: height)
        .frame(maxHeight: .infinity, alignment: .top)
        .animation(.easeInOut(duration: 0.6), value: backdropID)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task(id: id) {
            guard let id else {
                backdrop = nil
                backdropID = nil
                return
            }
            if let cached = ArtworkStore.shared.cachedBlur(for: id) {
                backdrop = cached
                backdropID = id
                return
            }
            guard let image = await ArtworkStore.shared.blurred(for: id), !Task.isCancelled else { return }
            backdrop = image
            backdropID = id
        }
    }
}

/// The Now Playing background: the cover's top colour flowing into its bottom colour, shaded
/// darker toward the bottom so text stays readable (the phone's look, spread across the window).
/// Keeps the old song's colours until the new ones are ready, then crossfades.
struct CoverColorBackdrop: View {
    let id: UInt64?

    @State private var colors: CoverColors?
    @State private var colorsID: UInt64?

    var body: some View {
        ZStack {
            HushStyle.paper
            if let colors {
                LinearGradient(colors: [colors.top, colors.bottom], startPoint: .top, endPoint: .bottom)
                    .id(colorsID)
                    .transition(.opacity)
                let shade = 0.30 + 0.40 * Double(colors.bottomBrightness)
                let topShade = 0.18 + 0.30 * Double(colors.topBrightness)
                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(topShade), location: 0),
                        .init(color: .black.opacity(topShade + 0.08), location: 0.45),
                        .init(color: .black.opacity(shade + 0.25), location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
        .animation(.easeInOut(duration: 0.7), value: colorsID)
        .accessibilityHidden(true)
        .task(id: id) {
            guard let id, colorsID != id else { return }
            if let cached = ArtworkStore.shared.cachedColors(for: id) {
                colors = cached
                colorsID = id
                return
            }
            guard let loaded = await ArtworkStore.shared.colors(for: id), !Task.isCancelled else { return }
            colors = loaded
            colorsID = id
        }
    }
}
