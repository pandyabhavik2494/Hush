import Foundation
import Observation

struct YouTubeVideo: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let channelID: String
    let channelTitle: String
    let publishedAt: Date?
    let duration: TimeInterval
    let thumbnail: URL?

    var watchURL: URL { URL(string: "https://www.youtube.com/watch?v=\(id)")! }

    /// "Kurzgesagt · 2 hours ago".
    var channelAndAge: String {
        guard let publishedAt else { return channelTitle }
        let age = RelativeDateTimeFormatter().localizedString(for: publishedAt, relativeTo: Date())
        return "\(channelTitle) · \(age)"
    }
}

struct YouTubeChannel: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let thumbnail: URL?
}

struct YouTubePlaylist: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let count: Int
    let thumbnail: URL?
}

/// Your YouTube, from the official Data API: the latest uploads from the channels you subscribe
/// to (music left out — that lives in your library — and Shorts too), your playlists, and search.
@MainActor
@Observable
final class YouTubeLibrary {
    static let shared = YouTubeLibrary()

    enum Status: Equatable {
        case idle
        case loading
        case ready
        case failed(String)
    }

    private(set) var status: Status = .idle
    private(set) var accountName: String?
    private(set) var channels: [YouTubeChannel] = []
    /// Newest first.
    private(set) var latest: [YouTubeVideo] = []
    private(set) var playlists: [YouTubePlaylist] = []
    private(set) var searchResults: [YouTubeVideo]?
    private(set) var isSearching = false
    var selectedChannelID: String?

    @ObservationIgnored private var lastLoad: Date?
    @ObservationIgnored private var playlistItems: [String: [YouTubeVideo]] = [:]
    /// Search costs 100 of the 10,000 daily quota units, so each query is asked once per session.
    @ObservationIgnored private var searchCache: [String: [YouTubeVideo]] = [:]
    /// How many subscribed channels feed "Latest" (each costs one quota unit per refresh).
    private static let channelLimit = 60
    private static let perChannel = 6

    func loadIfNeeded() {
        if let lastLoad, Date().timeIntervalSince(lastLoad) < 15 * 60, status == .ready { return }
        Task { await load() }
    }

    func load() async {
        guard status != .loading else { return }
        status = .loading
        do {
            let api = YouTubeAPI()
            async let me = api.myChannelName()
            let subscriptions = try await api.subscriptions(limit: Self.channelLimit)
            channels = subscriptions
            let uploads = try await api.uploadPlaylists(for: subscriptions.map(\.id))
            var ids: [String] = []
            for channel in subscriptions {
                guard let playlist = uploads[channel.id] else { continue }
                ids += (try? await api.playlistVideoIDs(playlist, limit: Self.perChannel)) ?? []
            }
            latest = try await api.videos(ids)
                .filter { $0.isWatchable }
                .map(\.video)
                .sorted { ($0.publishedAt ?? .distantPast) > ($1.publishedAt ?? .distantPast) }
            playlists = (try? await api.myPlaylists()) ?? []
            accountName = try? await me
            lastLoad = Date()
            status = .ready
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    var visibleLatest: [YouTubeVideo] {
        guard let selectedChannelID else { return latest }
        return latest.filter { $0.channelID == selectedChannelID }
    }

    /// Channels that have something in "Latest", most recent first, for the filter pills.
    var activeChannels: [YouTubeChannel] {
        var seen = Set<String>()
        let order = latest.compactMap { seen.insert($0.channelID).inserted ? $0.channelID : nil }
        let byID = Dictionary(channels.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return order.compactMap { byID[$0] }
    }

    func search(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            searchResults = nil
            return
        }
        // A pasted YouTube link plays straight away (no Data API needed).
        if let id = Self.videoID(fromLink: trimmed) {
            let video = YouTubeVideo(id: id, title: "YouTube video", channelID: "", channelTitle: "YouTube",
                                     publishedAt: nil, duration: 0, thumbnail: URL(string: "https://i.ytimg.com/vi/\(id)/hqdefault.jpg"))
            YouTubePlayback.shared.play(video)
            return
        }
        guard YouTubeAccount.shared.isAuthorized else { return }
        let key = trimmed.lowercased()
        if let cached = searchCache[key] {
            searchResults = cached
            return
        }
        isSearching = true
        Task {
            let api = YouTubeAPI()
            let ids = (try? await api.search(trimmed)) ?? []
            let found = (try? await api.videos(ids)) ?? []
            let results = found.filter { $0.isWatchable }.map(\.video)
            searchCache[key] = results
            searchResults = results
            isSearching = false
        }
    }

    /// The video id in youtube.com/watch?v=…, youtu.be/…, /shorts/… or /live/… links.
    static func videoID(fromLink text: String) -> String? {
        guard let url = URL(string: text), let host = url.host?.lowercased() else { return nil }
        let valid = { (id: String) -> String? in id.count == 11 ? id : nil }
        if host.hasSuffix("youtu.be") { return valid(String(url.path.dropFirst())) }
        guard host.hasSuffix("youtube.com") else { return nil }
        if let v = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "v" })?.value {
            return valid(v)
        }
        let parts = url.path.split(separator: "/")
        if parts.count >= 2, ["shorts", "live", "embed"].contains(parts[0]) { return valid(String(parts[1])) }
        return nil
    }

    func clearSearch() {
        searchResults = nil
    }

    func items(in playlist: YouTubePlaylist) async -> [YouTubeVideo] {
        if let cached = playlistItems[playlist.id] { return cached }
        let api = YouTubeAPI()
        let ids = (try? await api.playlistVideoIDs(playlist.id, limit: 200)) ?? []
        // Order as in the playlist; private or deleted videos drop out.
        let found = Dictionary(((try? await api.videos(ids)) ?? []).map { ($0.video.id, $0.video) }, uniquingKeysWith: { first, _ in first })
        let videos = ids.compactMap { found[$0] }
        playlistItems[playlist.id] = videos
        return videos
    }

    func reset() {
        channels = []
        latest = []
        playlists = []
        searchResults = nil
        accountName = nil
        playlistItems = [:]
        searchCache = [:]
        lastLoad = nil
        status = .idle
    }
}

// MARK: - The YouTube Data API v3

struct YouTubeAPIError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

struct YouTubeAPI {
    private static let base = "https://www.googleapis.com/youtube/v3/"

    struct DetailedVideo {
        let video: YouTubeVideo
        let categoryID: String?
        let isLive: Bool

        /// Not music (category 10, or a "Topic"/"VEVO" channel — that's what your library is for),
        /// not a Short, not a live stream.
        var isWatchable: Bool {
            let channel = video.channelTitle.lowercased()
            let musicChannel = channel.hasSuffix(" - topic") || channel.hasSuffix("topic") || channel.hasSuffix("vevo")
            return categoryID != "10" && !musicChannel && video.duration > 60 && !isLive
        }
    }

    private func get(_ path: String, _ query: [String: String]) async throws -> [String: Any] {
        guard let token = await YouTubeAccount.shared.validAccessToken() else {
            throw YouTubeAPIError(message: "Hush needs your Google approval again.")
        }
        var components = URLComponents(string: Self.base + path)!
        components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            let message = ((json["error"] as? [String: Any])?["message"] as? String) ?? "YouTube didn't answer."
            throw YouTubeAPIError(message: message)
        }
        return json
    }

    private static func items(_ json: [String: Any]) -> [[String: Any]] {
        json["items"] as? [[String: Any]] ?? []
    }

    private static func thumbnail(_ snippet: [String: Any]?) -> URL? {
        let thumbnails = snippet?["thumbnails"] as? [String: Any]
        for size in ["maxres", "standard", "high", "medium", "default"] {
            if let url = (thumbnails?[size] as? [String: Any])?["url"] as? String { return URL(string: url) }
        }
        return nil
    }

    func myChannelName() async throws -> String? {
        let json = try await get("channels", ["part": "snippet", "mine": "true"])
        return (Self.items(json).first?["snippet"] as? [String: Any])?["title"] as? String
    }

    func subscriptions(limit: Int) async throws -> [YouTubeChannel] {
        var channels: [YouTubeChannel] = []
        var pageToken: String?
        repeat {
            var query = ["part": "snippet", "mine": "true", "maxResults": "50", "order": "relevance"]
            if let pageToken { query["pageToken"] = pageToken }
            let json = try await get("subscriptions", query)
            for item in Self.items(json) {
                let snippet = item["snippet"] as? [String: Any]
                guard let id = (snippet?["resourceId"] as? [String: Any])?["channelId"] as? String else { continue }
                channels.append(YouTubeChannel(id: id, title: snippet?["title"] as? String ?? "", thumbnail: Self.thumbnail(snippet)))
            }
            pageToken = json["nextPageToken"] as? String
        } while pageToken != nil && channels.count < limit
        return Array(channels.prefix(limit))
    }

    /// Each channel's "uploads" playlist.
    func uploadPlaylists(for channelIDs: [String]) async throws -> [String: String] {
        var result: [String: String] = [:]
        for chunk in stride(from: 0, to: channelIDs.count, by: 50).map({ Array(channelIDs[$0..<min($0 + 50, channelIDs.count)]) }) {
            let json = try await get("channels", ["part": "contentDetails", "id": chunk.joined(separator: ","), "maxResults": "50"])
            for item in Self.items(json) {
                guard let id = item["id"] as? String,
                      let uploads = ((item["contentDetails"] as? [String: Any])?["relatedPlaylists"] as? [String: Any])?["uploads"] as? String
                else { continue }
                result[id] = uploads
            }
        }
        return result
    }

    func playlistVideoIDs(_ playlistID: String, limit: Int) async throws -> [String] {
        var ids: [String] = []
        var pageToken: String?
        repeat {
            var query = ["part": "contentDetails", "playlistId": playlistID, "maxResults": String(min(limit, 50))]
            if let pageToken { query["pageToken"] = pageToken }
            let json = try await get("playlistItems", query)
            ids += Self.items(json).compactMap { ($0["contentDetails"] as? [String: Any])?["videoId"] as? String }
            pageToken = json["nextPageToken"] as? String
        } while pageToken != nil && ids.count < limit
        return Array(ids.prefix(limit))
    }

    func videos(_ ids: [String]) async throws -> [DetailedVideo] {
        var videos: [DetailedVideo] = []
        let iso = ISO8601DateFormatter()
        for chunk in stride(from: 0, to: ids.count, by: 50).map({ Array(ids[$0..<min($0 + 50, ids.count)]) }) {
            let json = try await get("videos", ["part": "snippet,contentDetails", "id": chunk.joined(separator: ","), "maxResults": "50"])
            for item in Self.items(json) {
                guard let id = item["id"] as? String else { continue }
                let snippet = item["snippet"] as? [String: Any]
                let details = item["contentDetails"] as? [String: Any]
                let video = YouTubeVideo(
                    id: id,
                    title: snippet?["title"] as? String ?? "",
                    channelID: snippet?["channelId"] as? String ?? "",
                    channelTitle: snippet?["channelTitle"] as? String ?? "",
                    publishedAt: (snippet?["publishedAt"] as? String).flatMap { iso.date(from: $0) },
                    duration: Self.seconds(fromISO8601: details?["duration"] as? String),
                    thumbnail: Self.thumbnail(snippet)
                )
                let live = (snippet?["liveBroadcastContent"] as? String).map { $0 != "none" } ?? false
                videos.append(DetailedVideo(video: video, categoryID: snippet?["categoryId"] as? String, isLive: live))
            }
        }
        return videos
    }

    func myPlaylists() async throws -> [YouTubePlaylist] {
        let json = try await get("playlists", ["part": "snippet,contentDetails", "mine": "true", "maxResults": "50"])
        return Self.items(json).compactMap { item in
            guard let id = item["id"] as? String else { return nil }
            let snippet = item["snippet"] as? [String: Any]
            let count = (item["contentDetails"] as? [String: Any])?["itemCount"] as? Int ?? 0
            return YouTubePlaylist(id: id, title: snippet?["title"] as? String ?? "Playlist", count: count, thumbnail: Self.thumbnail(snippet))
        }
    }

    func search(_ query: String) async throws -> [String] {
        let json = try await get("search", ["part": "snippet", "q": query, "type": "video", "maxResults": "25", "safeSearch": "none"])
        return Self.items(json).compactMap { ($0["id"] as? [String: Any])?["videoId"] as? String }
    }

    /// "PT1H2M10S" → 3730.
    static func seconds(fromISO8601 text: String?) -> TimeInterval {
        guard let text else { return 0 }
        var total: TimeInterval = 0
        var number = ""
        for character in text {
            if character.isNumber {
                number.append(character)
            } else {
                let value = TimeInterval(number) ?? 0
                switch character {
                case "H": total += value * 3600
                case "M": total += value * 60
                case "S": total += value
                case "D": total += value * 86400
                default: break
                }
                number = ""
            }
        }
        return total
    }
}
