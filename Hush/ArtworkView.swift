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

/// A soft glow of an album's colors (its cover, heavily blurred) at the top of a screen, fading into
/// Hush's black. It gives Liquid Glass controls something to catch — glass over plain black just
/// looks grey. Purely decorative: it never affects layout or touches.
struct AmbientArtworkGlow: View {
    let item: MPMediaItem?
    let height: CGFloat
    let strength: Double
    /// The glow on screen and which song it belongs to. Made in the background (never while a page
    /// is sliding in), then faded in; when the song changes, the old glow stays until the new one is ready.
    @State private var backdrop: UIImage?
    @State private var backdropID: UInt64?

    init(item: MPMediaItem?, height: CGFloat = 420, strength: Double = 0.5) {
        self.item = item
        self.height = height
        self.strength = strength
        let cached = ArtworkPalette.cachedBackdrop(for: item)
        _backdrop = State(initialValue: cached)
        _backdropID = State(initialValue: cached == nil ? nil : item?.persistentID)
    }

    var body: some View {
        // GeometryReader takes exactly the space it's offered and never grows, so the glow can't
        // widen the page (a square cover filling a tall area used to stretch the whole screen).
        GeometryReader { geometry in
            if let backdrop {
                Image(uiImage: backdrop)
                    .resizable()
                    .scaledToFill()
                    .frame(width: geometry.size.width, height: height)
                    .clipped()
                    .opacity(strength)
                    .mask(
                        LinearGradient(
                            stops: [
                                .init(color: .black, location: 0),
                                .init(color: .black.opacity(0.55), location: 0.55),
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
        .animation(.easeInOut(duration: 0.8), value: backdropID)
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task(id: item?.persistentID) {
            guard let item else {
                backdrop = nil
                backdropID = nil
                return
            }
            guard backdropID != item.persistentID else { return }
            guard let image = await ArtworkPalette.loadBlurredBackdrop(for: item), !Task.isCancelled else { return }
            backdrop = image
            backdropID = item.persistentID
        }
    }
}

// MARK: - Artist photos (from the internet)

/// Finds and caches a real photo for each artist: Apple Music's catalog first (the same photos the
/// Music app shows — this needs Apple's MusicKit service, which may not be available on a free
/// developer account), then Deezer's free public catalog. A photo is only used when the artist's
/// name matches exactly (ignoring case, dots and spaces), so a similarly named artist's face never
/// shows up. Photos are saved on the phone, so each is downloaded once and then works offline.
actor ArtistPhotoService {
    static let shared = ArtistPhotoService()
    /// Posted (object: the artist key) whenever a photo is newly saved, so a circle already on
    /// screen — showing the placeholder or initials — can fade the photo in.
    static let photoSaved = Notification.Name("HushArtistPhotoSaved")

    /// Photos in memory, capped by size (not count) so a big library can't use too much memory.
    private static let memory: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.totalCostLimit = 120 * 1024 * 1024
        return cache
    }()
    /// Photos are stored at the size the circles need (sharp even on the 190pt artist-page circle
    /// at 3×), far smaller and faster to load than full-size catalog images.
    private static let storedPixelSize: CGFloat = 600
    /// How many artists (A–Z) to also load into memory up front — about the first few screens.
    private static let warmInMemoryCount = 60
    private static let maxConcurrentLookups = 3

    private var inFlight: [String: Task<UIImage?, Never>] = [:]
    private var activeLookups = 0
    private var preloadTask: Task<Void, Never>?

    /// Artists whose photo ships inside the app (Assets.xcassets) and is never looked up online.
    /// Photos from Wikimedia Commons (the ones Wikipedia uses), cropped square:
    /// - KK: "KK (124).jpg" by Endeshow1, CC BY-SA 3.0
    /// - A. R. Rahman: "AR Rahman at Premier Futsal Press Meet (cropped).jpg" by Sriram Narasimhan, CC BY-SA 4.0
    private static let builtInPhotos: [String: String] = [
        "kk": "ArtistKK",
        "arrahman": "ArtistARRahman",
    ]

    /// Photo lookups get their own session: short timeouts so a slow or unreachable catalog gives up
    /// quickly (and is retried later) instead of hanging for a minute, no cookies, and no waiting for
    /// a connection while offline. Photos are cached on the phone by this service, so URL caching is off.
    private static let network: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        configuration.waitsForConnectivity = false
        configuration.httpMaximumConnectionsPerHost = 4
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }()

    /// Instant, synchronous check of photos already in memory (no flicker on redraw).
    nonisolated static func cachedPhoto(for key: String) -> UIImage? {
        if let asset = builtInPhotos[key] { return UIImage(named: asset) }
        return memory.object(forKey: key as NSString)
    }

    // MARK: Preloading

    /// Fetches every artist's photo in the background as soon as the library loads, so the Artists
    /// tab is ready before you open it: every photo is downloaded and saved on the phone, and the
    /// first screens' worth are also loaded into memory. Runs a few at a time at low priority;
    /// calling again (library changed) replaces the previous run.
    func preload(_ artists: [(key: String, name: String)]) {
        preloadTask?.cancel()
        preloadTask = Task(priority: .utility) {
            let batchSize = Self.maxConcurrentLookups
            var start = 0
            while start < artists.count, !Task.isCancelled {
                let batch = Array(artists[start..<min(start + batchSize, artists.count)])
                let warm = start < Self.warmInMemoryCount
                await withTaskGroup(of: Void.self) { group in
                    for artist in batch {
                        group.addTask {
                            // Photo saved on the phone; then (first screens) load it into memory too.
                            await self.ensureSaved(key: artist.key, name: artist.name)
                            if warm { _ = await self.photo(for: artist.key, name: artist.name) }
                        }
                    }
                }
                start += batchSize
            }
        }
    }

    // MARK: Loading

    func photo(for key: String, name: String) async -> UIImage? {
        guard !key.isEmpty else { return nil }
        if let asset = Self.builtInPhotos[key] { return UIImage(named: asset) }
        if let image = Self.memory.object(forKey: key as NSString) { return image }
        if let existing = inFlight[key] { return await existing.value }
        let task = Task<UIImage?, Never> { await self.loadPhoto(key: key, name: name) }
        inFlight[key] = task
        let image = await task.value
        inFlight[key] = nil
        return image
    }

    /// Makes sure the photo is saved on the phone (downloading it if needed) without holding it in memory.
    private func ensureSaved(key: String, name: String) async {
        guard !key.isEmpty, inFlight[key] == nil, Self.builtInPhotos[key] == nil else { return }
        let photoSettled = Self.memory.object(forKey: key as NSString) != nil
            || FileManager.default.fileExists(atPath: Self.photoFile(for: key).path)
            || Self.isMarkedMissing(key)
        if photoSettled { return }
        _ = await download(key: key, name: name)
    }

    private func acquireLookupSlot() async {
        while activeLookups >= Self.maxConcurrentLookups {
            try? await Task.sleep(nanoseconds: 120_000_000)
        }
        activeLookups += 1
    }

    private func loadPhoto(key: String, name: String) async -> UIImage? {
        // 1. Saved on the phone from an earlier download.
        if let data = try? Data(contentsOf: Self.photoFile(for: key)), let image = UIImage(data: data) {
            let stored = Self.downsized(image)
            if stored !== image, let smaller = stored.jpegData(compressionQuality: 0.85) {
                // Photo saved at full size by an earlier version of Hush: shrink it once.
                try? smaller.write(to: Self.photoFile(for: key), options: .atomic)
            }
            let prepared = await stored.byPreparingForDisplay() ?? stored
            Self.remember(prepared, for: key)
            return prepared
        }
        // 2. Looked up recently and nothing found: don't ask the internet again yet.
        if Self.isMarkedMissing(key) { return nil }
        // 3. Look it up online.
        guard let image = await download(key: key, name: name) else { return nil }
        let prepared = await image.byPreparingForDisplay() ?? image
        Self.remember(prepared, for: key)
        return prepared
    }

    /// Finds, downloads, shrinks and saves an artist's photo. Returns it (not yet in memory).
    private func download(key: String, name: String) async -> UIImage? {
        await acquireLookupSlot()
        defer { activeLookups -= 1 }

        // Apple Music's photo first; Deezer's as the fallback.
        var photoURL = await Self.appleMusicPhotoURL(name: name, key: key)
        if photoURL == nil {
            guard let deezer = await Self.deezerLookup(name: name, key: key) else {
                // No answer (offline, or "too many requests"): not a real "no photo" — try again
                // next time instead of remembering a miss.
                return nil
            }
            photoURL = deezer.photo
        }
        guard let photoURL else {
            // Both catalogs answered and neither has a photo: remember, and show initials. Pull down
            // to refresh in Hush to look again.
            Self.markMissing(key)
            return nil
        }
        guard let result = try? await Self.network.data(from: photoURL),
              (result.1 as? HTTPURLResponse)?.statusCode == 200,
              let image = UIImage(data: result.0) else {
            return nil // The download itself failed; try again next time.
        }
        let stored = Self.downsized(image)
        if let data = stored.jpegData(compressionQuality: 0.85) { Self.save(data, for: key) }
        return stored
    }

    private static func remember(_ image: UIImage, for key: String) {
        let pixels = image.size.width * image.scale * image.size.height * image.scale
        memory.setObject(image, forKey: key as NSString, cost: max(Int(pixels * 4), 1))
    }

    /// Scales a photo down to `storedPixelSize` (returns the same image if it's already small).
    private static func downsized(_ image: UIImage) -> UIImage {
        let pixelWidth = image.size.width * image.scale
        let pixelHeight = image.size.height * image.scale
        let longest = max(pixelWidth, pixelHeight)
        guard longest > storedPixelSize * 1.05 else { return image }
        let factor = storedPixelSize / longest
        let target = CGSize(width: (pixelWidth * factor).rounded(), height: (pixelHeight * factor).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }

    private static func isMarkedMissing(_ key: String) -> Bool {
        FileManager.default.fileExists(atPath: missingMarker(for: key).path)
    }

    /// Pull-to-refresh: forget "no photo found" for every artist so they're looked up again.
    /// Photos already saved are kept.
    func forgetMisses() {
        let files = (try? FileManager.default.contentsOfDirectory(at: Self.folder, includingPropertiesForKeys: nil)) ?? []
        for file in files where file.pathExtension == "miss" {
            try? FileManager.default.removeItem(at: file)
        }
    }

    // MARK: Sources

    private static func appleMusicPhotoURL(name: String, key: String) async -> URL? {
        guard MusicAuthorization.currentStatus == .authorized else { return nil }
        let terms = lookupTerms(name: name, key: key)
        var request = MusicCatalogSearchRequest(term: terms.search, types: [MusicKit.Artist.self])
        request.limit = 10
        guard let response = try? await request.response() else { return nil }
        let match = response.artists.first { terms.accept.contains(ArtistCredits.key(for: $0.name)) }
        return match?.artwork?.url(width: 600, height: 600)
    }

    private struct DeezerSearch: Decodable {
        struct Artist: Decodable {
            let name: String
            let picture_xl: String?
            let picture_big: String?
            let nb_fan: Int?
        }
        let data: [Artist]
    }

    /// One Deezer search: the artist's fan count (0 if no exact match) and photo, if any.
    /// Returns nil only if the request itself failed (e.g. offline), so it can be retried later.
    private static func deezerLookup(name: String, key: String) async -> (fans: Int, photo: URL?)? {
        let terms = lookupTerms(name: name, key: key)
        var components = URLComponents(string: "https://api.deezer.com/search/artist")
        components?.queryItems = [URLQueryItem(name: "q", value: terms.search), URLQueryItem(name: "limit", value: "10")]
        guard let url = components?.url,
              let result = try? await Self.network.data(from: url),
              (result.1 as? HTTPURLResponse)?.statusCode == 200,
              let search = try? JSONDecoder().decode(DeezerSearch.self, from: result.0) else { return nil }
        guard let match = search.data.first(where: { terms.accept.contains(ArtistCredits.key(for: $0.name)) }) else {
            return (0, nil)
        }
        var photo: URL?
        // Deezer's generic grey silhouette has an empty image id ("/artist//").
        if let address = match.picture_xl ?? match.picture_big, !address.contains("/artist//") {
            photo = URL(string: address)
        }
        return (match.nb_fan ?? 0, photo)
    }

    // MARK: On-phone storage (Application Support — permanent; each photo is downloaded once)

    /// Photos are kept permanently in the app's own storage (Application Support), which iOS never
    /// clears on its own — each photo is downloaded once, then it's part of Hush. (Photos saved by
    /// earlier versions in the clearable Caches folder are moved over once.)
    private static let folder: URL = {
        let fileManager = FileManager.default
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let folder = base.appendingPathComponent("ArtistPhotos", isDirectory: true)
        try? fileManager.createDirectory(at: folder, withIntermediateDirectories: true)

        let oldFolder = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ArtistPhotos", isDirectory: true)
        if let oldFiles = try? fileManager.contentsOfDirectory(at: oldFolder, includingPropertiesForKeys: nil) {
            for file in oldFiles where file.pathExtension == "img" {
                let destination = folder.appendingPathComponent(file.lastPathComponent)
                if !fileManager.fileExists(atPath: destination.path) {
                    try? fileManager.moveItem(at: file, to: destination)
                }
            }
            try? fileManager.removeItem(at: oldFolder)
        }
        return folder
    }()

    private static func photoFile(for key: String) -> URL {
        folder.appendingPathComponent(key).appendingPathExtension("img")
    }

    /// "Looked up, nothing found" marker. (Renamed from ".none" so misses recorded before the
    /// spelling fixes below are ignored and those artists are looked up again.)
    private static func missingMarker(for key: String) -> URL {
        folder.appendingPathComponent(key).appendingPathExtension("miss")
    }

    /// Artists whose name in your library differs from how the photo catalogs spell it, or whose
    /// name is too short to search well. Maps your library's key → the name to search for and
    /// the catalog spellings that count as a match.
    private static let aliases: [String: (search: String, accept: Set<String>)] = [
        "arrahman": ("A. R. Rahman", ["arrahman"]),
        "arrehman": ("A. R. Rahman", ["arrahman"]),
        "allahrakharahman": ("A. R. Rahman", ["arrahman"]),
        "kk": ("KK", ["kk", "krishnakumarkunnath"]),
        "krishnakumarkunnath": ("KK", ["kk", "krishnakumarkunnath"]),
        "vishalshekhar": ("Vishal-Shekhar", ["vishalshekhar", "vishalandshekhar"]),
        "shankarehsaanloy": ("Shankar-Ehsaan-Loy", ["shankarehsaanloy"]),
        "salimsulaiman": ("Salim-Sulaiman", ["salimsulaiman"]),
        "sajidwajid": ("Sajid-Wajid", ["sajidwajid"]),
        "sachinjigar": ("Sachin-Jigar", ["sachinjigar"]),
        "atifaslam": ("Atif Aslam", ["atifaslam"]),
        "sonunigam": ("Sonu Nigam", ["sonunigam"]),
    ]

    /// What to search for, and which catalog names count as this artist.
    private static func lookupTerms(name: String, key: String) -> (search: String, accept: Set<String>) {
        aliases[key] ?? (name, [key])
    }

    private static func save(_ data: Data, for key: String) {
        try? data.write(to: photoFile(for: key), options: .atomic)
        try? FileManager.default.removeItem(at: missingMarker(for: key))
        NotificationCenter.default.post(name: photoSaved, object: key)
    }

    private static func markMissing(_ key: String) {
        try? Data().write(to: missingMarker(for: key), options: .atomic)
    }
}

/// An artist's photo in a circle. Calm loading: while the photo is being looked up, a soft
/// gold-lit disc holds its place; the photo then fades in over it. Only if there's no photo do
/// the initials fade in — they're never shown first and then swapped. Never an album cover.
struct ArtistPhoto: View {
    let artist: MusicArtist
    @State private var image: UIImage?
    /// The lookup has answered (photo or not). Until then, just the placeholder disc.
    @State private var hasSettled = false

    var body: some View {
        let shown = image ?? ArtistPhotoService.cachedPhoto(for: artist.id)
        // A square box sized by its container (it can never stretch the layout), clipped to a circle.
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                ArtistMonogram(name: artist.name, showsInitials: shown == nil && hasSettled)
            }
            .overlay {
                if let shown {
                    Image(uiImage: shown)
                        .resizable()
                        .scaledToFill()
                        .transition(.opacity)
                }
            }
            .clipShape(Circle())
            .overlay(Circle().stroke(HushStyle.ink.opacity(0.08), lineWidth: 0.5))
            .animation(.easeOut(duration: 0.45), value: shown != nil)
            .animation(.easeOut(duration: 0.45), value: hasSettled)
            .task(id: artist.id) { await load() }
            // A photo found later (background download, or "Look for Missing Photos") fades in here too.
            .onReceive(
                NotificationCenter.default.publisher(for: ArtistPhotoService.photoSaved).receive(on: RunLoop.main)
            ) { note in
                guard image == nil, note.object as? String == artist.id else { return }
                Task { await load() }
            }
            .accessibilityHidden(true)
    }

    @MainActor
    private func load() async {
        if ArtistPhotoService.cachedPhoto(for: artist.id) != nil {
            hasSettled = true
            return
        }
        if let photo = await ArtistPhotoService.shared.photo(for: artist.id, name: artist.name) {
            image = photo
        }
        hasSettled = true
    }
}

/// A dark, softly gold-lit disc: the placeholder while a photo loads, and — with the initials —
/// the artist's circle when there's no photo.
private struct ArtistMonogram: View {
    let name: String
    var showsInitials = true

    private var initials: String {
        let words = name.split(whereSeparator: { $0 == " " || $0 == "." || $0 == "-" }).prefix(2)
        let letters = words.compactMap { $0.first.map(String.init) }.joined()
        return letters.isEmpty ? "♪" : letters.uppercased()
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                LinearGradient(
                    colors: [HushStyle.surface.opacity(0.9), HushStyle.paper],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                RadialGradient(
                    colors: [HushStyle.gold.opacity(0.18), .clear],
                    center: .topLeading,
                    startRadius: 0,
                    endRadius: geometry.size.width
                )
                Text(initials)
                    .font(.system(size: geometry.size.width * 0.34, weight: .regular, design: .serif))
                    .foregroundStyle(HushStyle.gold)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .padding(geometry.size.width * 0.12)
                    .opacity(showsInitials ? 1 : 0)
            }
        }
    }
}
