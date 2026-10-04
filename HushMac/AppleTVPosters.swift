import AppKit
import SwiftUI
import Vision

// MARK: - Poster art

/// Portrait art for an Apple TV purchase, and how it's drawn.
enum PosterArt: Sendable {
    /// A real 2:3 movie poster.
    case poster(SendableImage)
    /// A show's square season art (it carries the show's logo), set on a 2:3 card.
    case square(SendableImage)
    /// A 2:3 crop of the library's 16:9 art around its subject; drawn with the name over it.
    case crop(SendableImage)
}

private final class PosterBox {
    let art: PosterArt
    init(_ art: PosterArt) { self.art = art }
}

/// Decoded posters, readable from any thread (NSCache is thread-safe).
private final class PosterMemory: @unchecked Sendable {
    static let shared = PosterMemory()
    let cache: NSCache<NSString, PosterBox> = {
        let cache = NSCache<NSString, PosterBox>()
        cache.totalCostLimit = 120 * 1024 * 1024
        return cache
    }()
}

/// Posters for Apple TV purchases. The library only has 16:9 art for them, so:
/// - Movies: the store ID inside the downloaded file's metadata (read from the metadata atoms only;
///   the protected video is never touched) is looked up in Apple's public iTunes catalog, all
///   movies in one request, for the movie's own 2:3 poster.
/// - Shows: the catalog's season art for a season whose show name matches exactly.
/// - Anything else: a 2:3 crop of the library's art, centred on its subject (Vision saliency).
/// Downloads are kept on this Mac; a title the catalog doesn't have isn't asked about again for a week.
actor PosterStore {
    static let shared = PosterStore()

    private nonisolated static var memory: NSCache<NSString, PosterBox> { PosterMemory.shared.cache }

    private static let folder: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let folder = base.appendingPathComponent("Posters", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }()

    private static let network: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 60
        configuration.waitsForConnectivity = false
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }()

    /// Movies waiting for the next batched catalog lookup: persistent ID → downloaded file.
    private var queuedMovies: [UInt64: URL] = [:]
    private var movieBatch: Task<Void, Never>?
    private var showLookups: [String: Task<Void, Never>] = [:]

    // MARK: Asking for art

    nonisolated static func key(_ subject: PosterView.Subject, pixels: Int) -> String {
        switch subject {
        case .movie(let movie): return "m\(movie.id)-\(pixels)"
        case .show(let show): return "s\(show.id)-\(pixels)"
        }
    }

    /// Instant check — never does any work.
    nonisolated static func cached(_ subject: PosterView.Subject, pixels: Int) -> PosterArt? {
        memory.object(forKey: key(subject, pixels: pixels) as NSString)?.art
    }

    func art(for subject: PosterView.Subject, pixels: Int) async -> PosterArt? {
        let key = Self.key(subject, pixels: pixels)
        if let hit = Self.memory.object(forKey: key as NSString) { return hit.art }
        let art: PosterArt?
        switch subject {
        case .movie(let movie):
            if let file = await moviePosterFile(movie), let image = await Self.decode(file, pixels: pixels) {
                art = .poster(image)
            } else {
                art = await Self.crop(id: movie.id, pixels: pixels)
            }
        case .show(let show):
            if let file = await showPosterFile(show), let image = await Self.decode(file, pixels: pixels) {
                art = .square(image)
            } else {
                art = await show.artworkID.asyncFlatMap { await Self.crop(id: $0, pixels: pixels) }
            }
        }
        if let art {
            Self.memory.setObject(PosterBox(art), forKey: key as NSString, cost: pixels * pixels * 3)
        }
        return art
    }

    // MARK: Movies

    private func moviePosterFile(_ movie: AppleTVMovie) async -> URL? {
        let file = Self.folder.appendingPathComponent("movie-\(movie.id).jpg")
        if FileManager.default.fileExists(atPath: file.path) { return file }
        guard let location = movie.location, !Self.recentlyMissed(file) else { return nil }
        queuedMovies[movie.id] = location
        if movieBatch == nil {
            // Gather every tile that asks in the next moment into one catalog request.
            movieBatch = Task {
                try? await Task.sleep(for: .milliseconds(300))
                await self.runMovieBatch()
            }
        }
        await movieBatch?.value
        return FileManager.default.fileExists(atPath: file.path) ? file : nil
    }

    private func runMovieBatch() async {
        let work = queuedMovies
        queuedMovies = [:]
        movieBatch = nil
        // Store ID → the library's persistent IDs for it.
        let storeIDs: [UInt64: [UInt64]] = await Task.detached(priority: .utility) {
            var found: [UInt64: [UInt64]] = [:]
            for (id, location) in work {
                if let storeID = MP4Metadata.storeID(of: location) { found[storeID, default: []].append(id) }
            }
            return found
        }.value
        for id in work.keys where !storeIDs.values.contains(where: { $0.contains(id) }) {
            Self.markMissed(Self.folder.appendingPathComponent("movie-\(id).jpg"))
        }
        let all = Array(storeIDs.keys)
        for start in stride(from: 0, to: all.count, by: 150) {
            let chunk = all[start..<min(start + 150, all.count)]
            var components = URLComponents(string: "https://itunes.apple.com/lookup")
            components?.queryItems = [URLQueryItem(name: "id", value: chunk.map(String.init).joined(separator: ","))]
            guard let url = components?.url,
                  let (data, response) = try? await Self.network.data(from: url),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let decoded = try? JSONDecoder().decode(CatalogResponse.self, from: data) else {
                continue // offline or refused: try again next time
            }
            var artwork: [UInt64: String] = [:]
            for result in decoded.results where result.kind == "feature-movie" {
                if let trackID = result.trackId, let art = result.artworkUrl100 { artwork[trackID] = art }
            }
            await withTaskGroup(of: Void.self) { group in
                for storeID in chunk {
                    let files = (storeIDs[storeID] ?? []).map { Self.folder.appendingPathComponent("movie-\($0).jpg") }
                    guard let art = artwork[storeID],
                          let posterURL = URL(string: art.replacingOccurrences(of: "100x100bb", with: "1000x1500bb")) else {
                        files.forEach(Self.markMissed)
                        continue
                    }
                    group.addTask {
                        guard let (data, response) = try? await Self.network.data(from: posterURL),
                              (response as? HTTPURLResponse)?.statusCode == 200 else { return }
                        for file in files { try? data.write(to: file, options: .atomic) }
                    }
                }
            }
        }
    }

    // MARK: Shows

    private func showPosterFile(_ show: AppleTVShow) async -> URL? {
        let safeName = show.id.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? String($0) : "-" }.joined()
        let file = Self.folder.appendingPathComponent("show-\(safeName).jpg")
        if FileManager.default.fileExists(atPath: file.path) { return file }
        guard !Self.recentlyMissed(file) else { return nil }
        if let running = showLookups[show.id] {
            await running.value
        } else {
            let task = Task { await Self.downloadSeasonArt(showName: show.name, to: file) }
            showLookups[show.id] = task
            await task.value
            showLookups[show.id] = nil
        }
        return FileManager.default.fileExists(atPath: file.path) ? file : nil
    }

    /// Season art from a season whose show name matches exactly; the earliest numbered season wins.
    private static func downloadSeasonArt(showName: String, to file: URL) async {
        var components = URLComponents(string: "https://itunes.apple.com/search")
        components?.queryItems = [
            URLQueryItem(name: "term", value: showName),
            URLQueryItem(name: "media", value: "tvShow"),
            URLQueryItem(name: "entity", value: "tvSeason"),
            URLQueryItem(name: "limit", value: "50"),
        ]
        guard let url = components?.url,
              let (data, response) = try? await network.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let decoded = try? JSONDecoder().decode(CatalogResponse.self, from: data) else { return }
        let wanted = LibrarySearch.normalizedQuery(showName)
        let seasons = decoded.results.filter {
            LibrarySearch.normalizedQuery($0.artistName ?? "") == wanted && $0.artworkUrl100 != nil
        }
        let numbered = seasons.compactMap { season -> (Int, CatalogResult)? in
            guard let name = season.collectionName,
                  LibrarySearch.normalizedQuery(name).hasPrefix(wanted),
                  let number = AppleTVPurchases.seasonNumber(in: name) else { return nil }
            return (number, season)
        }
        guard let best = numbered.min(by: { $0.0 < $1.0 })?.1 ?? seasons.first,
              let art = best.artworkUrl100,
              let artURL = URL(string: art.replacingOccurrences(of: "100x100bb", with: "1200x1200bb")),
              let (image, imageResponse) = try? await network.data(from: artURL),
              (imageResponse as? HTTPURLResponse)?.statusCode == 200 else {
            markMissed(file)
            return
        }
        try? image.write(to: file, options: .atomic)
    }

    /// A manual refresh: titles the catalog didn't have are asked about again, and the decoded
    /// posters are re-read (so new ones replace crops).
    func forgetMisses() {
        let files = (try? FileManager.default.contentsOfDirectory(at: Self.folder, includingPropertiesForKeys: nil)) ?? []
        for file in files where file.pathExtension == "miss" {
            try? FileManager.default.removeItem(at: file)
        }
        Self.memory.removeAllObjects()
    }

    // MARK: Helpers

    private struct CatalogResponse: Decodable {
        let results: [CatalogResult]
    }

    /// Every field optional: one odd result mustn't spoil the whole answer.
    private struct CatalogResult: Decodable {
        let kind: String?
        let trackId: UInt64?
        let artistName: String?
        let collectionName: String?
        let artworkUrl100: String?
    }

    private static func recentlyMissed(_ file: URL) -> Bool {
        let miss = file.deletingPathExtension().appendingPathExtension("miss")
        guard let date = (try? miss.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate else { return false }
        return Date().timeIntervalSince(date) < 7 * 24 * 3600
    }

    private static func markMissed(_ file: URL) {
        try? Data().write(to: file.deletingPathExtension().appendingPathExtension("miss"), options: .atomic)
    }

    private static func decode(_ file: URL, pixels: Int) async -> SendableImage? {
        guard let data = try? Data(contentsOf: file) else { return nil }
        return await ArtworkStore.decodeOnQueue { ArtworkStore.thumbnail(from: data, pixels: pixels) }.map(SendableImage.init(image:))
    }

    /// The library's 16:9 art, cropped to 2:3 around what Vision finds most eye-catching.
    private static func crop(id: UInt64, pixels: Int) async -> PosterArt? {
        guard let wide = await ArtworkStore.shared.image(for: id, pixels: max(pixels, 900)),
              let cgImage = wide.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let source = SendableImage(image: NSImage(cgImage: cgImage, size: .zero))
        let cropped: NSImage? = await ArtworkStore.decodeOnQueue {
            guard let cgImage = source.image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
            let width = CGFloat(cgImage.width), height = CGFloat(cgImage.height)
            let cropWidth = min(width, height * 2 / 3)
            var centre = 0.5
            let request = VNGenerateAttentionBasedSaliencyImageRequest()
            if (try? VNImageRequestHandler(cgImage: cgImage).perform([request])) != nil,
               let objects = request.results?.first?.salientObjects, !objects.isEmpty {
                let box = objects.reduce(objects[0].boundingBox) { $0.union($1.boundingBox) }
                centre = box.midX
            }
            let originX = min(max(centre * width - cropWidth / 2, 0), width - cropWidth)
            guard let piece = cgImage.cropping(to: CGRect(x: originX, y: 0, width: cropWidth, height: height)) else { return nil }
            return NSImage(cgImage: piece, size: NSSize(width: piece.width, height: piece.height))
        }
        return cropped.map { .crop(SendableImage(image: $0)) }
    }
}

private extension Optional {
    func asyncFlatMap<U>(_ transform: (Wrapped) async -> U?) async -> U? {
        guard let value = self else { return nil }
        return await transform(value)
    }
}

// MARK: - Reading the store ID from a file's metadata

/// Reads one number from an MPEG-4 file's iTunes metadata (moov › udta › meta › ilst › cnID): the
/// catalog ID. Only the small metadata boxes are read, by seeking past everything else.
enum MP4Metadata {
    static func storeID(of url: URL) -> UInt64? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return nil }
        let path: [String] = ["moov", "udta", "meta", "ilst", "cnID"]
        var start: UInt64 = 0
        var end = size
        for (depth, name) in path.enumerated() {
            guard let box = find(name, in: handle, from: start, to: end) else { return nil }
            start = box.contentStart + (name == "meta" ? 4 : 0) // meta has a version and flags first
            end = box.end
            if depth == path.count - 1 {
                // cnID › data box: 4 size + 4 "data" + 4 type + 4 locale, then the 32-bit number.
                guard (try? handle.seek(toOffset: box.contentStart)) != nil,
                      let bytes = try? handle.read(upToCount: 20), bytes.count == 20,
                      String(decoding: bytes[4..<8], as: UTF8.self) == "data" else { return nil }
                let number = bytes[16..<20].reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
                return number > 0 ? number : nil
            }
        }
        return nil
    }

    private struct Box {
        let contentStart: UInt64
        let end: UInt64
    }

    private static func find(_ name: String, in handle: FileHandle, from start: UInt64, to end: UInt64) -> Box? {
        var offset = start
        while offset + 8 <= end {
            guard (try? handle.seek(toOffset: offset)) != nil,
                  let header = try? handle.read(upToCount: 16), header.count >= 8 else { return nil }
            var size = header[0..<4].reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
            let type = String(decoding: header[4..<8], as: UTF8.self)
            var headerSize: UInt64 = 8
            if size == 1, header.count == 16 {
                size = header[8..<16].reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
                headerSize = 16
            } else if size == 0 {
                size = end - offset
            }
            guard size >= headerSize else { return nil }
            if type == name { return Box(contentStart: offset + headerSize, end: min(offset + size, end)) }
            offset += size
        }
        return nil
    }
}

// MARK: - The poster view

/// A 2:3 poster for an Apple TV movie or show (see PosterStore for where the art comes from).
struct PosterView: View {
    enum Subject: Sendable {
        case movie(AppleTVMovie)
        case show(AppleTVShow)

        var name: String {
            switch self {
            case .movie(let movie): return movie.title
            case .show(let show): return show.name
            }
        }
    }

    let subject: Subject
    var pixels = 900
    var cornerRadius: CGFloat = 10

    @State private var art: PosterArt?
    @State private var loadedKey: String?

    var body: some View {
        let key = PosterStore.key(subject, pixels: pixels)
        // What's on screen stays up while a refresh looks again.
        let shown = PosterStore.cached(subject, pixels: pixels) ?? art
        Color.clear
            .aspectRatio(2 / 3, contentMode: .fit)
            .overlay {
                switch shown {
                case .poster(let image):
                    Image(nsImage: image.image).resizable().interpolation(.high).scaledToFill()
                case .square(let image):
                    squareCard(image.image)
                case .crop(let image):
                    Image(nsImage: image.image).resizable().interpolation(.high).scaledToFill()
                        .overlay(alignment: .bottomLeading) { nameOverWide }
                case nil:
                    CoverPlaceholder(symbol: subject.placeholderSymbol)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .animation(.easeOut(duration: 0.2), value: loadedKey)
            .task(id: "\(key)-\(LibraryModel.shared.artworkGeneration)") {
                guard PosterStore.cached(subject, pixels: pixels) == nil else { return }
                let loaded = await PosterStore.shared.art(for: subject, pixels: pixels)
                guard !Task.isCancelled, let loaded else { return }
                art = loaded
                loadedKey = key
            }
            .accessibilityHidden(true)
    }

    /// Season art (it carries the show's logo) at the top of the card, over a blurred, dimmed copy of
    /// itself; seasons and episodes underneath.
    private func squareCard(_ image: NSImage) -> some View {
        GeometryReader { geometry in
            ZStack {
                Image(nsImage: image).resizable().scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .blur(radius: 28)
                    .overlay(Color.black.opacity(0.45))
                    .clipped()
                VStack(spacing: 0) {
                    Image(nsImage: image).resizable().interpolation(.high).scaledToFit()
                        .frame(width: geometry.size.width)
                    Spacer(minLength: 0)
                    if case .show(let show) = subject {
                        VStack(spacing: 4) {
                            Text(show.seasonsText.uppercased())
                                .font(HushStyle.rounded(max(geometry.size.width * 0.045, 9), weight: .bold))
                                .tracking(0.8)
                                .foregroundStyle(.white.opacity(0.85))
                            Text(show.episodesText)
                                .font(.system(size: max(geometry.size.width * 0.05, 10)))
                                .foregroundStyle(.white.opacity(0.65))
                        }
                        .lineLimit(1)
                        .padding(.horizontal, 10)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    /// The 16:9 art carries no name once it's cropped, so the name goes over it.
    private var nameOverWide: some View {
        Text(subject.name)
            .font(HushStyle.serif(22))
            .foregroundStyle(.white)
            .lineLimit(3)
            .minimumScaleFactor(0.7)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(colors: [.black.opacity(0.8), .black.opacity(0.3), .clear], startPoint: .bottom, endPoint: .top)
            )
    }
}

private extension PosterView.Subject {
    var placeholderSymbol: String {
        switch self {
        case .movie: return "appletv"
        case .show: return "tv"
        }
    }
}
