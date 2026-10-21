import Combine
import MediaPlayer
import MusicKit
import SwiftUI

/// Album art for a song. Images are decoded off the main thread (so grids scroll smoothly) and cached.
/// While a new size is loading, any size already decoded for that song is shown instantly, so a cover
/// never flashes blank when it grows (grid tile → album page → player).
struct ArtworkView: View {
    let item: MPMediaItem?
    var cornerRadius: CGFloat = 18
    var size: CGSize = CGSize(width: 400, height: 400)

    @State private var loadedImage: UIImage?
    @State private var loadedKey: String?
    /// Covers being decoded right now, so several views asking for the same one (e.g. every track
    /// row on an album page) share a single fetch instead of each doing it.
    @MainActor private static var inFlight: [String: Task<UIImage, Never>] = [:]

    private var cacheKey: String? {
        guard let item else { return nil }
        return ArtworkCache.key(for: item.persistentID, size: size)
    }

    private var displayImage: UIImage? {
        guard let item, let key = cacheKey else { return nil }
        if loadedKey == key, let loadedImage { return loadedImage }
        return ArtworkCache.image(forKey: key) ?? ArtworkCache.bestImage(for: item.persistentID)
    }

    var body: some View {
        Group {
            if let displayImage {
                Image(uiImage: displayImage)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    LinearGradient(
                        colors: [Color(red: 0.53, green: 0.39, blue: 0.15), Color(red: 0.20, green: 0.16, blue: 0.08)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    Image(systemName: "waveform")
                        .font(.system(size: 31, weight: .light))
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .accessibilityLabel(item?.albumTitle ?? item?.title ?? "Music artwork")
        .task(id: cacheKey) { await loadImage() }
    }

    @MainActor
    private func loadImage() async {
        guard let item, let key = cacheKey else { return }
        if let cached = ArtworkCache.image(forKey: key) {
            loadedImage = cached
            loadedKey = key
            return
        }
        // MediaPlayer only hands out artwork reliably on the main thread, so fetch it here (cheap:
        // it returns the still-compressed image). The expensive part — decoding — happens off the
        // main thread below, so scrolling stays smooth.
        if let pending = Self.inFlight[key] {
            let image = await pending.value
            guard !Task.isCancelled else { return }
            loadedImage = image
            loadedKey = key
            return
        }
        guard let raw = item.artwork?.image(at: size) else { return }
        let itemID = item.persistentID
        let decode = Task<UIImage, Never> {
            let image = await raw.byPreparingForDisplay() ?? raw
            // Cache even if this view scrolled away meanwhile, so the work isn't wasted.
            ArtworkCache.store(image, forKey: key, itemID: itemID)
            return image
        }
        Self.inFlight[key] = decode
        let image = await decode.value
        Self.inFlight[key] = nil
        guard !Task.isCancelled else { return }
        loadedImage = image
        loadedKey = key
    }
}

enum ArtworkCache {
    private static let images: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.totalCostLimit = 96 * 1024 * 1024 // ~96 MB of decoded artwork
        return cache
    }()
    /// The largest image decoded so far for each song, used as an instant stand-in for other sizes.
    private static let bestBySong: NSCache<NSNumber, UIImage> = {
        let cache = NSCache<NSNumber, UIImage>()
        cache.countLimit = 400
        return cache
    }()

    static func key(for itemID: UInt64, size: CGSize) -> String {
        "\(itemID)-\(Int(size.width.rounded()))x\(Int(size.height.rounded()))"
    }

    static func image(forKey key: String) -> UIImage? {
        images.object(forKey: key as NSString)
    }

    static func bestImage(for itemID: UInt64) -> UIImage? {
        bestBySong.object(forKey: NSNumber(value: itemID))
    }

    static func store(_ image: UIImage, forKey key: String, itemID: UInt64) {
        let pixels = image.size.width * image.scale * image.size.height * image.scale
        images.setObject(image, forKey: key as NSString, cost: max(Int(pixels * 4), 1))
        let songKey = NSNumber(value: itemID)
        if let existing = bestBySong.object(forKey: songKey),
           existing.size.width * existing.scale >= image.size.width * image.scale {
            return
        }
        bestBySong.setObject(image, forKey: songKey)
    }
}

extension ArtistPhoto {
    init(artist: MusicArtist) {
        self.init(artistID: artist.id, name: artist.name)
    }
}
