import AppKit
import SwiftUI

/// "Bought on Apple TV · plays in the TV app" — the quiet note on the Apple TV sections.
private struct AppleTVNote: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "tv")
            .font(.system(size: 12))
            .foregroundStyle(Color(red: 0.612, green: 0.604, blue: 0.584))
            .labelStyle(.titleAndIcon)
            .fixedSize()
    }
}

// MARK: - Apple TV Movies

/// Movies bought on Apple TV: posters (see PosterStore), genre filters, and a click opens the movie
/// in the TV app.
struct AppleTVMoviesGrid: View {
    @Environment(LibraryModel.self) private var library
    @Environment(Navigator.self) private var navigator
    @AppStorage("hush.mac.showTitles.appleTVMovies") private var showsTitles = false
    @AppStorage("hush.mac.appleTVGenre") private var genre = ""

    var body: some View {
        let query = LibrarySearch.normalizedQuery(navigator.search(for: .appleTVMovies))
        let genres = Self.genres(in: library.appleTVMovies)
        let activeGenre = genres.contains(genre) ? genre : ""
        let movies = library.appleTVMovies.filter {
            LibrarySearch.matches($0.searchKey, query: query) && (activeGenre.isEmpty || $0.genres.contains(activeGenre))
        }
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        GenrePill(title: "All", isOn: activeGenre.isEmpty) { genre = "" }
                        ForEach(genres, id: \.self) { name in
                            GenrePill(title: name, isOn: activeGenre == name) { genre = name }
                        }
                    }
                }
                .scrollIndicators(.never)
                AppleTVNote(text: "Bought on Apple TV · plays in the TV app")
            }
            .padding(.horizontal, 28)
            .padding(.top, 4)
            .padding(.bottom, 16)

            if movies.isEmpty {
                EmptyStateView(symbol: "appletv", title: query.isEmpty ? "No Apple TV movies" : "No matches",
                               message: query.isEmpty ? "Movies you buy or rent on Apple TV show up here." : "Try another title or genre.")
            } else {
                // Posters with room around them, like Movies.
                TileGrid(items: movies, minimumWidth: 200, spacing: (20, 28),
                         letter: query.isEmpty ? { $0.sectionLetter } : nil) { movie in
                    AppleTVMovieTile(movie: movie, showsTitle: showsTitles)
                }
            }
        }
    }

    static func genres(in movies: [AppleTVMovie]) -> [String] {
        var counts: [String: Int] = [:]
        for movie in movies { for genre in movie.genres { counts[genre, default: 0] += 1 } }
        return counts.sorted { $0.value > $1.value || ($0.value == $1.value && $0.key < $1.key) }.map(\.key)
    }
}

struct GenrePill: View {
    let title: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(HushStyle.rounded(12.5, weight: isOn ? .semibold : .medium))
                .foregroundStyle(isOn ? HushStyle.paper : HushStyle.ink.opacity(0.9))
                .padding(.horizontal, 14)
                .frame(height: 30)
                .background(Capsule().fill(isOn ? HushStyle.gold : Color(red: 0.094, green: 0.090, blue: 0.082)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct AppleTVMovieTile: View {
    let movie: AppleTVMovie
    let showsTitle: Bool
    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                AppleTVHandOff.open(movie.id, title: movie.title, isDownloaded: movie.isDownloaded)
            } label: {
                PosterView(subject: .movie(movie), pixels: 900, cornerRadius: 10)
                    .overlay {
                        if isHovering {
                            Image(systemName: "play.fill")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(HushStyle.paper)
                                .frame(width: 46, height: 46)
                                .background(HushStyle.gold, in: Circle())
                                .shadow(color: .black.opacity(0.4), radius: 8, y: 3)
                                .transition(.opacity.combined(with: .scale(scale: 0.85)))
                        }
                    }
                    .shadow(color: .black.opacity(0.42), radius: 12, y: 8)
            }
            .buttonStyle(PressScaleButtonStyle())
            if showsTitle {
                TileCaption(title: movie.title, subtitle: movie.yearAndGenre)
            }
        }
        .onHover { hovering in withAnimation(.easeOut(duration: 0.15)) { isHovering = hovering } }
        .help(showsTitle ? "Plays in the TV app" : "\(movie.title) — plays in the TV app")
        .contextMenu {
            Button("Play in the TV App") { AppleTVHandOff.open(movie.id, title: movie.title, isDownloaded: movie.isDownloaded) }
            Button("Show in the TV App") { AppleTVHandOff.open(movie.id, title: movie.title, isDownloaded: movie.isDownloaded, play: false) }
        }
    }
}

// MARK: - Apple TV Shows

/// One poster per series bought on Apple TV (its season art; see PosterStore). Names are hidden by
/// default, as the art carries the show's logo; the titles toggle shows them.
struct AppleTVShowsGrid: View {
    @Environment(LibraryModel.self) private var library
    @Environment(Navigator.self) private var navigator
    @AppStorage("hush.mac.showTitles.appleTVShows") private var showsTitles = false

    var body: some View {
        let query = LibrarySearch.normalizedQuery(navigator.search(for: .appleTVShows))
        let shows = LibrarySearch.filterByNameThenSongs(library.appleTVShows, query: query,
                                                        nameKey: \.searchKey, songsKey: \.episodeSearchKey)
        let episodes = library.appleTVShows.reduce(0) { $0 + $1.episodes.count }
        return VStack(alignment: .leading, spacing: 0) {
            AppleTVNote(text: "Bought on Apple TV · \(HushStyle.count(episodes)) episodes · episodes play in the TV app")
                .padding(.horizontal, 28)
                .padding(.top, 4)
                .padding(.bottom, 18)
            if shows.isEmpty {
                EmptyStateView(symbol: "tv", title: query.isEmpty ? "No Apple TV shows" : "No matches",
                               message: query.isEmpty ? "Shows you buy on Apple TV show up here." : "Try another show or episode.")
            } else {
                TileGrid(items: shows, minimumWidth: 200, spacing: (20, 28)) { show in
                    AppleTVShowTile(show: show, showsTitle: showsTitles)
                }
            }
        }
    }
}

struct AppleTVShowTile: View {
    let show: AppleTVShow
    let showsTitle: Bool
    @Environment(Navigator.self) private var navigator

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                navigator.show(.appleTVShow(show.id), in: .appleTVShows)
            } label: {
                PosterView(subject: .show(show), pixels: 900, cornerRadius: 10)
                    .shadow(color: .black.opacity(0.42), radius: 12, y: 8)
            }
            .buttonStyle(PressScaleButtonStyle())
            if showsTitle {
                TileCaption(title: show.name, subtitle: show.episodesText)
            }
        }
        .help(showsTitle ? "" : "\(show.name) — \(show.episodesText)")
    }
}

// MARK: - Show page

/// A show: its poster, its name, seasons and episodes, an Open in the TV app button, season
/// filters, and the episodes (each opens in the TV app).
struct AppleTVShowPage: View {
    let showID: String
    @Environment(LibraryModel.self) private var library
    @State private var season: Int?

    var body: some View {
        if let show = library.appleTVShows.first(where: { $0.id == showID }) {
            let seasons = show.seasons
            let current = season.flatMap { seasons.contains($0) ? $0 : nil } ?? seasons.first ?? 1
            let episodes = show.episodes.filter { $0.season == current }
            CollectionLayout {
                PosterView(subject: .show(show), pixels: 1200, cornerRadius: 16)
                    .shadow(color: .black.opacity(0.6), radius: 30, y: 24)
                Text(show.name)
                    .font(HushStyle.serif(36))
                    .foregroundStyle(HushStyle.ink)
                    .padding(.top, 8)
                Text([show.seasonsText, show.episodesText, show.genre].compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 13))
                    .foregroundStyle(HushStyle.muted)
                    .padding(.top, -6)
                Button {
                    if let first = episodes.first ?? show.episodes.first {
                        AppleTVHandOff.open(first.id, title: show.name, isDownloaded: first.isDownloaded, play: false)
                    } else {
                        AppleTVHandOff.openTVApp()
                    }
                } label: {
                    Label("Open in the TV app", systemImage: "arrow.up.forward.square")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(HushPrimaryButtonStyle(height: 40))
                .padding(.top, 6)
                Text("Bought on Apple TV. Pick an episode and it plays in the TV app, which also remembers where you left off.")
                    .font(.system(size: 12))
                    .foregroundStyle(HushStyle.muted)
                    .fixedSize(horizontal: false, vertical: true)
            } list: {
                VStack(alignment: .leading, spacing: 16) {
                    if seasons.count > 1 {
                        ScrollView(.horizontal) {
                            HStack(spacing: 6) {
                                ForEach(seasons, id: \.self) { number in
                                    GenrePill(title: "Season \(number)", isOn: number == current) { season = number }
                                }
                            }
                        }
                        .scrollIndicators(.never)
                    }
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(episodes) { episode in
                                AppleTVEpisodeRow(episode: episode, showName: show.name)
                            }
                        }
                        .padding(.bottom, 28)
                    }
                }
                .padding(.top, 8)
            }
            .id(show.id)
        } else {
            EmptyStateView(symbol: "tv", title: "Show not found", message: "It may have been removed from your Apple TV library.")
        }
    }
}

struct AppleTVEpisodeRow: View {
    let episode: AppleTVEpisode
    let showName: String
    @State private var isHovering = false

    var body: some View {
        Button {
            AppleTVHandOff.open(episode.id, title: "\(showName) S\(episode.season) E\(episode.number)", isDownloaded: episode.isDownloaded)
        } label: {
            HStack(spacing: 14) {
                Text(episode.number > 0 ? "\(episode.number)" : "")
                    .font(HushStyle.rounded(12))
                    .monospacedDigit()
                    .foregroundStyle(HushStyle.muted)
                    .frame(width: 30)
                CoverView(id: episode.id, pixels: 300, cornerRadius: 6, aspectRatio: 16 / 9, placeholderSymbol: "tv")
                    .frame(width: 112)
                Text(episode.title)
                    .font(HushStyle.rounded(15, weight: .semibold))
                    .foregroundStyle(HushStyle.ink)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(HushStyle.durationText(episode.duration) ?? "")
                    .font(HushStyle.rounded(11.5))
                    .monospacedDigit()
                    .foregroundStyle(HushStyle.muted)
                Image(systemName: "arrow.up.forward.square")
                    .font(.system(size: 13))
                    .foregroundStyle(HushStyle.gold)
                    .opacity(isHovering ? 1 : 0)
            }
            .padding(.leading, 6)
            .padding(.trailing, 12)
            .frame(minHeight: 78)
            .background(RoundedRectangle(cornerRadius: 8).fill(isHovering ? HushStyle.ink.opacity(0.05) : .clear))
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color(red: 0.180, green: 0.173, blue: 0.157).opacity(0.55)).frame(height: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help("Plays in the TV app")
        .contextMenu {
            Button("Play in the TV App") { AppleTVHandOff.open(episode.id, title: showName, isDownloaded: episode.isDownloaded) }
            Button("Show in the TV App") { AppleTVHandOff.open(episode.id, title: showName, isDownloaded: episode.isDownloaded, play: false) }
        }
    }
}
