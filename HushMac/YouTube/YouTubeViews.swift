import AppKit
import SwiftUI
import WebKit

/// The YouTube section: Connect until you're signed in and Hush is allowed to read your channels,
/// then Home (or search results).
struct YouTubeSection: View {
    @Environment(YouTubeAccount.self) private var account
    @Environment(YouTubeLibrary.self) private var library
    @Environment(Navigator.self) private var navigator

    var body: some View {
        Group {
            if account.isWebSignedIn == nil {
                LoadingView()
            } else if !account.isConnected {
                YouTubeConnectView()
            } else if library.searchResults != nil || library.isSearching {
                YouTubeSearchResults()
            } else {
                YouTubeHome()
            }
        }
        .task {
            if account.isWebSignedIn == nil { await account.refreshWebSignIn() }
        }
        .onChange(of: account.isConnected, initial: true) { _, connected in
            if connected { library.loadIfNeeded() }
        }
    }
}

// MARK: - Connect

struct YouTubeConnectView: View {
    @Environment(YouTubeAccount.self) private var account
    @Environment(Navigator.self) private var navigator
    @State private var showsSignIn = false
    @State private var clientIDDraft = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Image(systemName: "play.rectangle")
                    .font(.system(size: 30, weight: .regular))
                    .foregroundStyle(HushStyle.gold)
                    .frame(width: 72, height: 72)
                    .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(HushStyle.gold.opacity(0.14)))
                    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(HushStyle.gold.opacity(0.35), lineWidth: 1))
                Text("Watch YouTube in Hush")
                    .font(HushStyle.serif(32))
                    .foregroundStyle(HushStyle.ink)
                    .padding(.top, 6)
                Text("New videos from the channels you follow, in Hush's own screens. Music stays in your library.")
                    .font(.system(size: 14.5))
                    .foregroundStyle(Color(red: 0.784, green: 0.773, blue: 0.745))
                    .multilineTextAlignment(.center)

                VStack(spacing: 10) {
                    step(1, done: account.isWebSignedIn == true,
                         title: "Sign in to YouTube",
                         detail: "Google's sign-in opens in Hush. Your Premium Lite comes with it, so videos play without ads.") {
                        if account.isWebSignedIn == true {
                            doneMark
                        } else {
                            Button("Sign in") { showsSignIn = true }
                                .buttonStyle(LightCapsuleButtonStyle())
                        }
                    }
                    step(2, done: account.isAuthorized,
                         title: "Let Hush see your channels",
                         detail: "A one-time Google approval so Hush can list your subscriptions and playlists. Read only.") {
                        if account.isAuthorized {
                            doneMark
                        } else if account.clientID != nil {
                            Button("Allow") { account.authorize() }
                                .buttonStyle(HushSecondaryButtonStyle(height: 34))
                        }
                    }
                    if !account.isAuthorized {
                        clientIDField
                    }
                    if let error = account.authError {
                        Text(error)
                            .font(.system(size: 12))
                            .foregroundStyle(Color(red: 0.90, green: 0.55, blue: 0.45))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.top, 12)

                Button("Not now") { navigator.select(.albums) }
                    .buttonStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(HushStyle.muted)
                    .padding(.top, 6)
                Text("You stay signed in after restarts. Sign out any time from the account menu.")
                    .font(.system(size: 12))
                    .foregroundStyle(HushStyle.muted)
                    .padding(.top, 4)
            }
            .frame(maxWidth: 520)
            .padding(.vertical, 40)
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity)
        }
        .sheet(isPresented: $showsSignIn) {
            YouTubeSignInSheet { showsSignIn = false }
        }
        .onAppear { clientIDDraft = account.clientID ?? "" }
    }

    private var doneMark: some View {
        Label("Done", systemImage: "checkmark.circle.fill")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(HushStyle.gold)
    }

    /// Where you paste the OAuth client ID you created in Google Cloud (it never leaves this Mac).
    private var clientIDField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Your Google OAuth client ID (iOS type, bundle ID com.hush.player.mac)")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(HushStyle.muted)
            HStack(spacing: 8) {
                TextField("…apps.googleusercontent.com", text: $clientIDDraft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5, design: .monospaced))
                    .padding(.horizontal, 10)
                    .frame(height: 30)
                    .background(RoundedRectangle(cornerRadius: 8).fill(HushStyle.fill))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(HushStyle.fillStroke, lineWidth: 1))
                    .onSubmit { account.setClientID(clientIDDraft) }
                Button("Save") { account.setClientID(clientIDDraft) }
                    .buttonStyle(HushSecondaryButtonStyle(height: 30))
                    .disabled(clientIDDraft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(HushStyle.ink.opacity(0.03)))
    }

    private func step<Action: View>(_ number: Int, done: Bool, title: String, detail: String, @ViewBuilder action: () -> Action) -> some View {
        HStack(spacing: 14) {
            Text("\(number)")
                .font(HushStyle.rounded(13, weight: .bold))
                .foregroundStyle(done || number == 1 ? HushStyle.paper : HushStyle.ink)
                .frame(width: 28, height: 28)
                .background(Circle().fill(done || number == 1 ? HushStyle.gold : HushStyle.ink.opacity(0.12)))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(HushStyle.ink)
                Text(detail).font(.system(size: 12.5)).foregroundStyle(Color(red: 0.612, green: 0.604, blue: 0.584))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            action()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(HushStyle.ink.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(HushStyle.ink.opacity(0.10), lineWidth: 1))
    }
}

struct LightCapsuleButtonStyle: ButtonStyle {
    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Color(red: 0.102, green: 0.098, blue: 0.090))
            .padding(.horizontal, 16)
            .frame(height: 34)
            .background(Capsule().fill(HushStyle.ink))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

/// Google's own sign-in page in a sheet. When it lands back on youtube.com, you're signed in.
struct YouTubeSignInSheet: View {
    let done: () -> Void
    @State private var coordinator = SignInCoordinator()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Sign in to YouTube")
                    .font(HushStyle.serif(18))
                Spacer()
                Button("Cancel", action: done)
            }
            .padding(14)
            WebViewHost(webView: coordinator.webView)
        }
        .frame(width: 520, height: 680)
        .onAppear {
            coordinator.onSignedIn = {
                YouTubeAccount.shared.webSignInFinished()
                done()
            }
            coordinator.start()
        }
    }

    @MainActor
    final class SignInCoordinator: NSObject, WKNavigationDelegate {
        let webView = WKWebView(frame: .zero, configuration: YouTubeAccount.webConfiguration())
        var onSignedIn: (() -> Void)?

        func start() {
            webView.navigationDelegate = self
            webView.load(URLRequest(url: YouTubeAccount.signInURL))
        }

        nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Task { @MainActor in
                guard webView.url?.host == "www.youtube.com" || webView.url?.host == "m.youtube.com" else { return }
                self.onSignedIn?()
                self.onSignedIn = nil
            }
        }
    }
}

// MARK: - Home

struct YouTubeHome: View {
    @Environment(YouTubeLibrary.self) private var library
    @Environment(YouTubePlayback.self) private var playback
    @Environment(Navigator.self) private var navigator

    var body: some View {
        switch library.status {
        case .idle, .loading where library.latest.isEmpty:
            LoadingView(message: "Finding new videos from your channels")
        case .failed(let message) where library.latest.isEmpty:
            EmptyStateView(symbol: "exclamationmark.triangle", title: "YouTube didn't answer", message: message)
        default:
            content
        }
    }

    private var content: some View {
        let videos = library.visibleLatest
        return ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                channelPills
                if let hero = videos.first {
                    heroCard(hero, list: videos)
                }
                if videos.count > 1 {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Latest from your channels")
                            .font(HushStyle.serif(21))
                            .foregroundStyle(HushStyle.ink)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 260, maximum: 420), spacing: 20, alignment: .top)], alignment: .leading, spacing: 24) {
                            ForEach(videos.dropFirst()) { video in
                                YouTubeVideoTile(video: video) { playback.play(video, in: videos) }
                            }
                        }
                    }
                }
                if !library.playlists.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Your playlists")
                            .font(HushStyle.serif(21))
                            .foregroundStyle(HushStyle.ink)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 260, maximum: 420), spacing: 20, alignment: .top)], alignment: .leading, spacing: 24) {
                            ForEach(library.playlists) { playlist in
                                Button {
                                    navigator.show(.youtubePlaylist(playlist.id), in: .youtube)
                                } label: {
                                    VStack(alignment: .leading, spacing: 9) {
                                        YouTubeThumbnail(url: playlist.thumbnail)
                                            .shadow(color: .black.opacity(0.42), radius: 12, y: 8)
                                        TileCaption(title: playlist.title, subtitle: playlist.count == 1 ? "1 video" : "\(playlist.count) videos")
                                    }
                                }
                                .buttonStyle(PressScaleButtonStyle())
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 2)
            .padding(.bottom, 28)
        }
    }

    private var channelPills: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    pill("All channels", isOn: library.selectedChannelID == nil) { library.selectedChannelID = nil }
                    ForEach(library.activeChannels.prefix(20)) { channel in
                        pill(channel.title, isOn: library.selectedChannelID == channel.id) { library.selectedChannelID = channel.id }
                    }
                }
            }
            .scrollIndicators(.never)
            Text("Music is left out here. It lives in your library.")
                .font(.system(size: 12))
                .foregroundStyle(HushStyle.muted)
                .fixedSize()
        }
    }

    private func pill(_ title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
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

    private func heroCard(_ video: YouTubeVideo, list: [YouTubeVideo]) -> some View {
        Button {
            playback.play(video, in: list)
        } label: {
            HStack(alignment: .center, spacing: 32) {
                YouTubeThumbnail(url: video.thumbnail, cornerRadius: 16)
                    .overlay(alignment: .bottomTrailing) { DurationBadge(seconds: video.duration).padding(10) }
                    .frame(maxWidth: 600)
                    .shadow(color: .black.opacity(0.55), radius: 30, y: 26)
                VStack(alignment: .leading, spacing: 12) {
                    Text("NEWEST FROM YOUR CHANNELS")
                        .font(HushStyle.rounded(11, weight: .bold))
                        .tracking(0.9)
                        .foregroundStyle(HushStyle.gold)
                    Text(video.title)
                        .font(HushStyle.serif(34))
                        .foregroundStyle(HushStyle.ink)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                    Text(video.channelAndAge)
                        .font(.system(size: 13.5))
                        .foregroundStyle(Color(red: 0.784, green: 0.773, blue: 0.745))
                    Label("Watch", systemImage: "play.fill")
                        .font(HushStyle.rounded(14, weight: .semibold))
                        .foregroundStyle(HushStyle.paper)
                        .padding(.horizontal, 22)
                        .frame(height: 40)
                        .background(Capsule().fill(HushStyle.gold))
                        .padding(.top, 6)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(PressScaleButtonStyle())
    }
}

struct DurationBadge: View {
    let seconds: TimeInterval

    var body: some View {
        Text(HushStyle.timestamp(seconds))
            .font(HushStyle.rounded(11, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 6).fill(.black.opacity(0.65)))
    }
}

struct YouTubeVideoTile: View {
    let video: YouTubeVideo
    let play: () -> Void

    var body: some View {
        Button(action: play) {
            VStack(alignment: .leading, spacing: 9) {
                YouTubeThumbnail(url: video.thumbnail)
                    .overlay(alignment: .bottomTrailing) { DurationBadge(seconds: video.duration).padding(7) }
                    .shadow(color: .black.opacity(0.42), radius: 12, y: 8)
                VStack(alignment: .leading, spacing: 3) {
                    Text(video.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(HushStyle.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(video.channelAndAge)
                        .font(.system(size: 12))
                        .foregroundStyle(HushStyle.muted)
                        .lineLimit(1)
                }
            }
        }
        .buttonStyle(PressScaleButtonStyle())
        .contextMenu {
            Button("Play", action: play)
            Button("Open in Browser") { NSWorkspace.shared.open(video.watchURL) }
            Button("Copy Link") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(video.watchURL.absoluteString, forType: .string)
            }
        }
    }
}

// MARK: - Search

struct YouTubeSearchResults: View {
    @Environment(YouTubeLibrary.self) private var library
    @Environment(YouTubePlayback.self) private var playback

    var body: some View {
        if library.isSearching {
            LoadingView(message: "Searching YouTube")
        } else if let results = library.searchResults, !results.isEmpty {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 260, maximum: 420), spacing: 20, alignment: .top)], alignment: .leading, spacing: 24) {
                    ForEach(results) { video in
                        YouTubeVideoTile(video: video) { playback.play(video, in: results) }
                    }
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 8)
            }
        } else {
            EmptyStateView(symbol: "magnifyingglass", title: "Nothing found", message: "Music is left out of YouTube in Hush. Try another search.")
        }
    }
}

// MARK: - Playlist page

struct YouTubePlaylistPage: View {
    let playlistID: String
    @Environment(YouTubeLibrary.self) private var library
    @Environment(YouTubePlayback.self) private var playback
    @State private var videos: [YouTubeVideo]?

    var body: some View {
        if let playlist = library.playlists.first(where: { $0.id == playlistID }) {
            CollectionLayout {
                YouTubeThumbnail(url: playlist.thumbnail, cornerRadius: 14)
                    .shadow(color: .black.opacity(0.6), radius: 30, y: 24)
                Text(playlist.title)
                    .font(HushStyle.serif(32))
                    .foregroundStyle(HushStyle.ink)
                    .padding(.top, 6)
                Text("YouTube playlist · \(playlist.count == 1 ? "1 video" : "\(playlist.count) videos")")
                    .font(.system(size: 12.5))
                    .foregroundStyle(HushStyle.muted)
                    .padding(.top, -6)
                PlayShuffleButtons(
                    playTitle: "Play all",
                    play: { if let first = videos?.first, let videos { playback.play(first, in: videos) } },
                    shuffle: { if let shuffled = videos?.shuffled(), let first = shuffled.first { playback.play(first, in: shuffled) } }
                )
                .disabled(videos?.isEmpty ?? true)
                .padding(.top, 4)
                Button {
                    NSWorkspace.shared.open(URL(string: "https://www.youtube.com/playlist?list=\(playlist.id)")!)
                } label: {
                    Label("Open on YouTube", systemImage: "arrow.up.forward.square").font(.system(size: 12.5))
                }
                .buttonStyle(HushIconButtonStyle(idle: Color(red: 0.784, green: 0.773, blue: 0.745), hover: HushStyle.gold))
            } list: {
                if let videos {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(videos.enumerated()), id: \.element.id) { index, video in
                                YouTubePlaylistRow(number: index + 1, video: video) { playback.play(video, in: videos) }
                            }
                        }
                        .padding(.vertical, 8)
                    }
                } else {
                    LoadingView(message: "Loading the playlist")
                }
            }
            .task(id: playlistID) { videos = await library.items(in: playlist) }
        } else {
            EmptyStateView(symbol: "list.bullet.rectangle", title: "Playlist not found", message: "It may have been deleted on YouTube.")
        }
    }
}

struct YouTubePlaylistRow: View {
    let number: Int
    let video: YouTubeVideo
    let play: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: play) {
            HStack(spacing: 14) {
                Text("\(number)")
                    .font(HushStyle.rounded(11.5))
                    .monospacedDigit()
                    .foregroundStyle(HushStyle.muted)
                    .frame(width: 30)
                YouTubeThumbnail(url: video.thumbnail, cornerRadius: 8)
                    .frame(width: 140)
                VStack(alignment: .leading, spacing: 3) {
                    Text(video.title)
                        .font(HushStyle.rounded(15, weight: .semibold))
                        .foregroundStyle(HushStyle.ink)
                        .lineLimit(1)
                    Text(video.channelTitle)
                        .font(.system(size: 12.5))
                        .foregroundStyle(HushStyle.muted)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text(HushStyle.timestamp(video.duration))
                    .font(HushStyle.rounded(11.5))
                    .monospacedDigit()
                    .foregroundStyle(HushStyle.muted)
            }
            .padding(.leading, 4)
            .padding(.trailing, 12)
            .frame(minHeight: 92)
            .background(RoundedRectangle(cornerRadius: 10).fill(isHovering ? HushStyle.ink.opacity(0.05) : .clear))
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color(red: 0.180, green: 0.173, blue: 0.157).opacity(0.55)).frame(height: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

// MARK: - Account menu (toolbar)

struct YouTubeAccountMenu: View {
    @Environment(YouTubeAccount.self) private var account
    @Environment(YouTubeLibrary.self) private var library

    var body: some View {
        Menu {
            Button("Refresh") { Task { await library.load() } }
            Divider()
            Button("Sign Out of YouTube") {
                Task {
                    await account.signOut()
                    library.reset()
                }
            }
        } label: {
            HStack(spacing: 8) {
                Text(String((library.accountName ?? "Y").prefix(1)).uppercased())
                    .font(HushStyle.serif(13))
                    .foregroundStyle(HushStyle.ink)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Color(red: 0.173, green: 0.278, blue: 0.400)))
                Text(library.accountName ?? "YouTube")
                    .font(.system(size: 12.5))
                    .lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
            }
            .foregroundStyle(HushStyle.ink.opacity(0.9))
            .padding(.leading, 4)
            .padding(.trailing, 12)
            .frame(height: 34)
            .background(HushStyle.fill, in: Capsule())
            .overlay(Capsule().stroke(HushStyle.fillStroke, lineWidth: 1))
            .contentShape(Capsule())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("YouTube account")
    }
}
