import AppKit
import SwiftUI

/// The main window: sidebar on the left; on the right the toolbar, the section or page you're on,
/// Up Next when it's open, and the player bar along the bottom. Now Playing and the video player
/// cover the whole window.
struct ContentView: View {
    @Environment(LibraryModel.self) private var library
    @Environment(Player.self) private var player
    @Environment(Navigator.self) private var navigator
    @Environment(VideoPlayback.self) private var video
    @Environment(YouTubePlayback.self) private var youtube

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                SidebarView()
                    .frame(width: 240)
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        MainArea()
                        if navigator.showsUpNext {
                            UpNextPanel()
                                .frame(width: 360)
                                .transition(.move(edge: .trailing).combined(with: .opacity))
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    if player.current != nil {
                        PlayerBar()
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
            }

            if navigator.showsNowPlaying, player.current != nil {
                NowPlayingView()
                    .transition(.opacity.combined(with: .scale(scale: 0.985)))
                    .zIndex(1)
            }

            if video.isShowing {
                VideoPlayerView()
                    .transition(.opacity)
                    .zIndex(2)
            }

            if youtube.isShowing {
                YouTubePlayerView()
                    .transition(.opacity)
                    .zIndex(3)
            }
        }
        .overlay(alignment: .bottom) {
            ToastView()
                .padding(.bottom, player.current == nil ? 24 : 96)
        }
        .ignoresSafeArea()
        .background(HushStyle.paper)
        .frame(minWidth: 1000, minHeight: 640)
        .animation(.smooth(duration: 0.35), value: navigator.showsNowPlaying)
        .animation(.smooth(duration: 0.3), value: navigator.showsUpNext)
        .animation(.easeInOut(duration: 0.25), value: video.isShowing)
        .animation(.easeInOut(duration: 0.25), value: youtube.isShowing)
        .animation(.spring(response: 0.4, dampingFraction: 0.86), value: player.current == nil)
        .task { library.loadIfNeeded() }
        .onChange(of: library.revision) {
            player.restoreSessionIfNeeded(from: library)
        }
        .onChange(of: player.current == nil) { _, isEmpty in
            if isEmpty { navigator.showsNowPlaying = false }
        }
    }
}

// MARK: - Main area: toolbar + content

struct MainArea: View {
    @Environment(LibraryModel.self) private var library
    @Environment(Navigator.self) private var navigator
    @Environment(MediaAccess.self) private var access

    var body: some View {
        ZStack(alignment: .top) {
            HushStyle.paper
            glow
            VStack(spacing: 0) {
                LibraryToolbar()
                if access.folderNeeded != nil {
                    AccessBanner()
                }
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    /// Hush's ambient gold light on sections; the page's own cover glowing on album and playlist pages.
    @ViewBuilder
    private var glow: some View {
        switch navigator.route {
        case .album(let id):
            ArtworkGlow(id: library.album(id: id)?.artworkTrackID, height: 640, strength: 0.5)
        case .playlist(let id):
            ArtworkGlow(id: library.playlist(id: id)?.mosaicTrackIDs.first, height: 640, strength: 0.5)
        case .artist(let id):
            ArtworkGlow(id: library.artist(id: id)?.albums.first?.artworkTrackID, height: 560, strength: 0.45)
        case .youtubePlaylist, nil:
            HushAmbientLight()
                .frame(height: 520)
                .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch library.status {
        case .loading where library.songs.isEmpty:
            LoadingView()
        case .failed(let message) where library.songs.isEmpty:
            LibraryAccessView(message: message)
        default:
            switch navigator.route {
            case .album(let id): AlbumPage(albumID: id).id(id)
            case .artist(let id): ArtistPage(artistID: id).id(id)
            case .playlist(let id): PlaylistPage(playlistID: id).id(id)
            case .youtubePlaylist(let id): YouTubePlaylistPage(playlistID: id).id(id)
            case nil:
                switch navigator.section {
                case .albums: AlbumsGrid()
                case .songs: SongsTable()
                case .playlists: PlaylistsGrid()
                case .artists: ArtistsGrid()
                case .musicVideos: MusicVideosGrid()
                case .movies: MoviesGrid()
                case .youtube: YouTubeSection()
                }
            }
        }
    }
}

// MARK: - Toolbar

struct LibraryToolbar: View {
    @Environment(LibraryModel.self) private var library
    @Environment(Player.self) private var player
    @Environment(Navigator.self) private var navigator
    @Environment(VideoPlayback.self) private var video
    @FocusState private var searchFocused: Bool

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 2) {
                navButton("chevron.left", help: "Back (⌘[)", enabled: navigator.canGoBack) { navigator.back() }
                navButton("chevron.right", help: "Forward (⌘])", enabled: navigator.canGoForward) { navigator.forward() }
            }

            if let route = navigator.route {
                breadcrumb(for: route)
                Spacer(minLength: 20)
            } else {
                let section = navigator.section
                Text(section.title)
                    .font(HushStyle.serif(27))
                    .foregroundStyle(HushStyle.ink)
                    .padding(.leading, 4)
                    .lineLimit(1)
                if let count = count(for: section) {
                    CountCapsule(text: HushStyle.count(count))
                }
                Spacer(minLength: 20)
                primaryAction(for: section)
                searchField(for: section)
                if section.hasTitleToggle {
                    TitlesToggle(section: section)
                }
                if !section.sortOptions.isEmpty {
                    sortMenu(for: section)
                }
                if section == .youtube, YouTubeAccount.shared.isConnected {
                    YouTubeAccountMenu()
                }
            }
        }
        .padding(.leading, 20)
        .padding(.trailing, 28)
        .padding(.vertical, 6)
        .frame(minHeight: 64)
        .background(WindowDragArea())
        .onChange(of: navigator.searchFocusRequest) {
            searchFocused = true
        }
    }

    private func navButton(_ symbol: String, help: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 28, height: 28)
        }
        .buttonStyle(HushIconButtonStyle(idle: enabled ? HushStyle.ink : HushStyle.faint, hover: HushStyle.ink))
        .disabled(!enabled)
        .help(help)
    }

    private func breadcrumb(for route: Route) -> some View {
        HStack(spacing: 6) {
            Button(navigator.section.title) { navigator.select(navigator.section) }
                .buttonStyle(.plain)
                .foregroundStyle(HushStyle.muted)
            Text("/").foregroundStyle(HushStyle.faint)
            Text(title(for: route))
                .foregroundStyle(HushStyle.ink)
                .lineLimit(1)
        }
        .font(.system(size: 13))
        .padding(.leading, 4)
    }

    private func title(for route: Route) -> String {
        switch route {
        case .album(let id): return library.album(id: id)?.title ?? "Album"
        case .artist(let id): return library.artist(id: id)?.name ?? "Artist"
        case .playlist(let id): return library.playlist(id: id)?.name ?? "Playlist"
        case .youtubePlaylist(let id): return YouTubeLibrary.shared.playlists.first { $0.id == id }?.title ?? "Playlist"
        }
    }

    private func count(for section: LibrarySection) -> Int? {
        switch section {
        case .albums: return library.albums.count
        case .songs: return library.songs.count
        case .playlists: return library.playlists.count
        case .artists: return nil
        case .musicVideos: return library.videos.count
        case .movies: return library.movies.count
        case .youtube: return nil
        }
    }

    @ViewBuilder
    private func primaryAction(for section: LibrarySection) -> some View {
        switch section {
        case .songs:
            Button {
                player.shufflePlay(library.songs)
            } label: {
                Label("Shuffle all", systemImage: "shuffle")
            }
            .buttonStyle(HushPrimaryButtonStyle(height: 34))
            .disabled(library.songs.isEmpty)
        case .musicVideos:
            Button {
                if let first = library.videos.first(where: \.canPlayInHush) {
                    video.play(first, in: library.videos)
                }
            } label: {
                Label("Play all", systemImage: "play.fill")
            }
            .buttonStyle(HushPrimaryButtonStyle(height: 34))
            .disabled(library.videos.isEmpty)
        default:
            EmptyView()
        }
    }

    private func searchField(for section: LibrarySection) -> some View {
        let text = navigator.binding(forSearchIn: section)
        return HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
            TextField(section.searchPrompt, text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(HushStyle.ink)
                .focused($searchFocused)
                .onExitCommand { text.wrappedValue = ""; searchFocused = false }
                // YouTube search costs quota: it runs on Enter only.
                .onSubmit { if section == .youtube { YouTubeLibrary.shared.search(text.wrappedValue) } }
                .onChange(of: text.wrappedValue) { _, value in
                    if section == .youtube, value.isEmpty { YouTubeLibrary.shared.clearSearch() }
                }
            if text.wrappedValue.isEmpty {
                Text("⌘F")
                    .font(HushStyle.rounded(10.5, weight: .semibold))
                    .foregroundStyle(HushStyle.muted)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(HushStyle.ink.opacity(0.12), lineWidth: 1))
            } else {
                Button {
                    text.wrappedValue = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 13))
                }
                .buttonStyle(HushIconButtonStyle())
            }
        }
        .foregroundStyle(HushStyle.ink.opacity(0.75))
        .padding(.leading, 12)
        .padding(.trailing, 10)
        .frame(width: 300, height: 34)
        .background(HushStyle.fill, in: Capsule())
        .overlay(Capsule().stroke(searchFocused ? HushStyle.gold.opacity(0.55) : HushStyle.fillStroke, lineWidth: 1))
    }

    private func sortMenu(for section: LibrarySection) -> some View {
        let current = navigator.sort(for: section)
        return Menu {
            ForEach(section.sortOptions) { option in
                Button {
                    navigator.sorts[section] = option
                } label: {
                    if option == current { Label(option.menuTitle, systemImage: "checkmark") } else { Text(option.menuTitle) }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: current == .favorites ? "heart.fill" : (current == .mostPlayed ? "flame.fill" : "arrow.up"))
                    .font(.system(size: 10, weight: .bold))
                Text(current.label)
                    .font(HushStyle.rounded(10.5, weight: .bold))
                    .tracking(0.7)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
            }
            .foregroundStyle(HushStyle.ink.opacity(0.92))
            .padding(.horizontal, 13)
            .frame(height: 34)
            .background(HushStyle.fill, in: Capsule())
            .overlay(Capsule().stroke(HushStyle.fillStroke, lineWidth: 1))
            .contentShape(Capsule())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Sort")
    }
}

/// Shows or hides the titles under the artwork (Albums, Playlists, Movies). Hidden by default:
/// the artwork already carries the name.
struct TitlesToggle: View {
    let section: LibrarySection
    @AppStorage private var showsTitles: Bool

    init(section: LibrarySection) {
        self.section = section
        _showsTitles = AppStorage(wrappedValue: false, "hush.mac.showTitles.\(section.rawValue)")
    }

    var body: some View {
        Button {
            withAnimation(.smooth(duration: 0.3)) { showsTitles.toggle() }
        } label: {
            Image(systemName: "text.below.photo")
        }
        .buttonStyle(HushCircleButtonStyle(isOn: showsTitles))
        .help(showsTitles ? "Hide Titles" : "Show Titles")
        .accessibilityLabel("Show titles")
        .accessibilityValue(showsTitles ? "On" : "Off")
    }
}

// MARK: - Sidebar

struct SidebarView: View {
    @Environment(LibraryModel.self) private var library
    @Environment(Player.self) private var player
    @Environment(Navigator.self) private var navigator

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Room for the window's traffic lights.
            Color.clear.frame(height: 52)
            Text("Hush")
                .font(HushStyle.brandFont(size: 30))
                .foregroundStyle(HushStyle.gold)
                .padding(.horizontal, 10)
                .padding(.top, 2)
                .padding(.bottom, 18)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header("LISTEN", top: 6)
                    VStack(spacing: 2) {
                        row(.albums, count: library.albums.count)
                        row(.songs, count: library.songs.count)
                        row(.playlists, count: library.playlists.count)
                        row(.artists, count: library.artists.count)
                    }
                    header("WATCH", top: 18)
                    VStack(spacing: 2) {
                        row(.musicVideos, count: library.videos.count)
                        row(.movies, count: library.movies.count)
                        row(.youtube, count: 0)
                    }
                    if !library.playlists.isEmpty {
                        header("PLAYLISTS", top: 18)
                        VStack(spacing: 1) {
                            ForEach(library.playlists) { playlist in
                                PlaylistSidebarRow(playlist: playlist)
                            }
                        }
                    }
                }
                .padding(.bottom, 10)
            }
            .scrollIndicators(.never)

            footer
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 14)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(HushStyle.panel)
        .background(WindowDragArea())
        .overlay(alignment: .trailing) {
            Rectangle().fill(HushStyle.line).frame(width: 1)
        }
    }

    private func header(_ text: String, top: CGFloat) -> some View {
        Text(text)
            .font(HushStyle.rounded(10.5, weight: .bold))
            .tracking(0.85)
            .foregroundStyle(HushStyle.muted)
            .padding(.horizontal, 10)
            .padding(.top, top)
            .padding(.bottom, 6)
    }

    private func row(_ section: LibrarySection, count: Int) -> some View {
        let isOn = navigator.section == section && !isSidebarPlaylistOpen
        return SidebarRow(isOn: isOn, height: 32) {
            navigator.select(section)
        } content: {
            Image(systemName: section.symbol)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(isOn ? HushStyle.gold : HushStyle.ink.opacity(0.55))
                .frame(width: 18)
            Text(section.title)
                .font(.system(size: 13.5, weight: isOn ? .semibold : .medium))
                .foregroundStyle(isOn ? HushStyle.ink : HushStyle.ink.opacity(0.84))
            Spacer(minLength: 4)
            if count > 0 {
                Text(HushStyle.count(count))
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(HushStyle.muted)
            }
        }
        .help("\(section.title) (⌘\(String(section.shortcut.character)))")
    }

    /// A playlist page opened from the sidebar highlights that playlist instead of a section.
    private var isSidebarPlaylistOpen: Bool {
        if case .playlist = navigator.route, navigator.section == .playlists { return true }
        return false
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 7, height: 7)
            Text(statusText)
                .lineLimit(1)
            Spacer(minLength: 4)
            Button {
                library.reload()
                Task { await ArtistPhotoService.shared.forgetMisses() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 26, height: 26)
                    .rotationEffect(.degrees(library.isRefreshing ? 360 : 0))
                    .animation(library.isRefreshing ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: library.isRefreshing)
            }
            .buttonStyle(HushIconButtonStyle(idle: HushStyle.ink.opacity(0.7)))
            .help("Refresh Library (⌘R)")
            .disabled(library.isRefreshing)
        }
        .font(.system(size: 11.5))
        .foregroundStyle(HushStyle.muted)
        .padding(.horizontal, 10)
        .padding(.top, 12)
        .overlay(alignment: .top) {
            Rectangle().fill(HushStyle.line).frame(height: 1)
        }
    }

    private var statusText: String {
        if library.isRefreshing { return "Reading your Music library…" }
        if case .failed = library.status { return "Music library unavailable" }
        return "Music library, up to date"
    }

    private var statusColor: Color {
        if library.isRefreshing { return HushStyle.gold }
        if case .failed = library.status { return Color(red: 0.85, green: 0.42, blue: 0.36) }
        return Color(red: 0.498, green: 0.698, blue: 0.478)
    }
}

/// A sidebar row: a rounded highlight when selected or hovered.
struct SidebarRow<Content: View>: View {
    let isOn: Bool
    var height: CGFloat = 32
    let action: () -> Void
    @ViewBuilder let content: Content
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) { content }
                .padding(.horizontal, 10)
                .frame(height: height)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isOn ? HushStyle.gold.opacity(0.16) : (isHovering ? HushStyle.ink.opacity(0.05) : .clear))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

struct PlaylistSidebarRow: View {
    let playlist: Playlist
    @Environment(Player.self) private var player
    @Environment(Navigator.self) private var navigator

    var body: some View {
        let isOn = navigator.route == .playlist(playlist.id) && navigator.section == .playlists
        SidebarRow(isOn: isOn, height: 28) {
            navigator.show(.playlist(playlist.id), in: .playlists)
        } content: {
            PlaylistCover(playlist: playlist, pixels: 60, cornerRadius: 4)
                .frame(width: 18, height: 18)
            Text(playlist.name)
                .font(.system(size: 13))
                .foregroundStyle(isOn ? HushStyle.ink : HushStyle.ink.opacity(0.78))
                .lineLimit(1)
            Spacer(minLength: 0)
            if player.source == .playlist(playlist.id), player.current != nil {
                NowPlayingBars(isPlaying: player.isPlaying, barWidth: 2, height: 9)
            }
        }
        .contextMenu {
            CollectionMenu(tracks: playlist.tracks, source: .playlist(playlist.id))
            Divider()
            Button("Edit in Music") { MusicApp.open() }
        }
    }
}

// MARK: - States

struct LoadingView: View {
    var message = "Reading your Music library"

    var body: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.small)
                .tint(HushStyle.gold)
            Text(message)
                .font(HushStyle.rounded(13))
                .foregroundStyle(HushStyle.muted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Shown if macOS hasn't let Hush read the Music library.
struct LibraryAccessView: View {
    let message: String
    @Environment(LibraryModel.self) private var library

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "music.note.list")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(HushStyle.gold)
            Text("Let your music in")
                .font(HushStyle.serif(26))
                .foregroundStyle(HushStyle.ink)
            Text("Hush needs permission to read your Music library. Turn on Hush in System Settings › Privacy & Security › Media & Apple Music, then try again.")
                .font(.system(size: 13))
                .foregroundStyle(HushStyle.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            HStack(spacing: 10) {
                Button("Open Privacy Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Media") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(HushPrimaryButtonStyle(height: 34))
                Button("Try Again") { library.reload() }
                    .buttonStyle(HushSecondaryButtonStyle(height: 34))
            }
            .padding(.top, 6)
            Text(message)
                .font(.system(size: 10))
                .foregroundStyle(HushStyle.muted.opacity(0.6))
                .padding(.top, 10)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The library lives somewhere the sandbox can't reach (an external drive): one click to allow it.
struct AccessBanner: View {
    @Environment(MediaAccess.self) private var access

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "externaldrive.fill")
                .font(.system(size: 15))
                .foregroundStyle(HushStyle.gold)
            VStack(alignment: .leading, spacing: 2) {
                Text("Allow Hush to play your files")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(HushStyle.ink)
                Text("Your library is in “\(access.folderNeeded?.path ?? "")”. Choose Allow once and Hush remembers it.")
                    .font(.system(size: 12))
                    .foregroundStyle(HushStyle.muted)
                    .lineLimit(2)
            }
            Spacer(minLength: 12)
            Button("Allow Access…") { access.requestAccess() }
                .buttonStyle(HushPrimaryButtonStyle(height: 30))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(HushStyle.gold.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(HushStyle.gold.opacity(0.25), lineWidth: 1))
        .padding(.horizontal, 28)
        .padding(.bottom, 12)
    }
}

struct EmptyStateView: View {
    let symbol: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(HushStyle.gold.opacity(0.85))
            Text(title)
                .font(HushStyle.serif(22))
                .foregroundStyle(HushStyle.ink)
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(HushStyle.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .padding(40)
        .frame(maxWidth: .infinity, minHeight: 320)
    }
}

/// "Playing Next" / "Added to Up Next", floating just above the player bar.
struct ToastView: View {
    @Environment(Player.self) private var player

    var body: some View {
        if let message = player.toast {
            Label(message, systemImage: "checkmark.circle.fill")
                .font(HushStyle.rounded(13, weight: .semibold))
                .foregroundStyle(HushStyle.ink)
                .symbolRenderingMode(.hierarchical)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .hushGlass(Capsule())
                .transition(.opacity.combined(with: .move(edge: .bottom)))
                .allowsHitTesting(false)
        }
    }
}

/// Opens the Music app (playlists are edited there).
enum MusicApp {
    static func open() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Music") else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
}
