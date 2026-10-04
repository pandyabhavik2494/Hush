import AppKit
import Observation
import SwiftUI
import WebKit

/// Plays YouTube videos in YouTube's own player (the youtube.com watch page, signed in, so your
/// Premium applies), under Hush's bar: back (Esc), the title, the next video and Open in Browser.
/// Music pauses while a YouTube video plays; the media keys control the video until it's closed.
@MainActor
@Observable
final class YouTubePlayback: NSObject, WKNavigationDelegate, WKUIDelegate {
    static let shared = YouTubePlayback()

    private(set) var current: YouTubeVideo?
    private(set) var queue: [YouTubeVideo] = []
    private(set) var index = 0

    @ObservationIgnored private(set) lazy var webView: WKWebView = {
        let view = WKWebView(frame: .zero, configuration: YouTubeAccount.webConfiguration())
        view.navigationDelegate = self
        view.uiDelegate = self
        view.allowsBackForwardNavigationGestures = false
        view.underPageBackgroundColor = .black
        return view
    }()
    @ObservationIgnored private var endWatcher: Timer?

    var isShowing: Bool { current != nil }
    var next: YouTubeVideo? { index + 1 < queue.count ? queue[index + 1] : nil }

    func play(_ video: YouTubeVideo, in list: [YouTubeVideo]? = nil) {
        queue = list ?? [video]
        index = queue.firstIndex(of: video) ?? 0
        if queue.isEmpty { queue = [video] }
        Player.shared.setPlaying(false)
        VideoPlayback.shared.pauseForMusic()
        show(queue[index])
    }

    func playNext() {
        guard next != nil else { return }
        index += 1
        show(queue[index])
    }

    private func show(_ video: YouTubeVideo) {
        current = video
        webView.load(URLRequest(url: video.watchURL))
        watchForEnd()
    }

    func close() {
        endWatcher?.invalidate()
        webView.evaluateJavaScript("var v=document.querySelector('video'); if (v) v.pause(); 0")
        webView.load(URLRequest(url: URL(string: "about:blank")!))
        current = nil
        queue = []
    }

    func openInBrowser() {
        guard let current else { return }
        webView.evaluateJavaScript("var v=document.querySelector('video'); v ? Math.floor(v.currentTime) : 0") { result, _ in
            let seconds = result as? Int ?? 0
            var components = URLComponents(url: current.watchURL, resolvingAgainstBaseURL: false)!
            if seconds > 5 { components.queryItems?.append(URLQueryItem(name: "t", value: "\(seconds)s")) }
            Task { @MainActor in
                self.togglePlayPause(forcePause: true)
                if let url = components.url { NSWorkspace.shared.open(url) }
            }
        }
    }

    /// Play/pause through the page's own <video> (Space goes to YouTube itself; this is for the
    /// media keys and Control Center).
    func togglePlayPause(forcePause: Bool = false) {
        let script = forcePause
            ? "var v=document.querySelector('video'); if (v) v.pause(); 0"
            : "var v=document.querySelector('video'); if (v) { v.paused ? v.play() : v.pause() }; 0"
        webView.evaluateJavaScript(script)
    }

    func pauseForMusic() {
        guard isShowing else { return }
        togglePlayPause(forcePause: true)
    }

    /// When a video ends, the next one in the list starts (YouTube's own autoplay stays as you set it).
    private func watchForEnd() {
        endWatcher?.invalidate()
        endWatcher = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.current != nil, self.next != nil else { return }
                self.webView.evaluateJavaScript("var v=document.querySelector('video'); !!(v && v.ended)") { result, _ in
                    if (result as? Bool) == true { Task { @MainActor in self.playNext() } }
                }
            }
        }
    }

    // MARK: Web view

    /// Links YouTube opens in a new window (channel pages, descriptions) go to your browser.
    nonisolated func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                             for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url {
            Task { @MainActor in NSWorkspace.shared.open(url) }
        }
        return nil
    }

    /// Clicking another video on the page plays it here; leaving YouTube opens your browser.
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                             decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url, navigationAction.targetFrame?.isMainFrame == true,
              navigationAction.navigationType == .linkActivated else {
            decisionHandler(.allow)
            return
        }
        let host = url.host ?? ""
        if host.hasSuffix("youtube.com") || host.hasSuffix("google.com") || host.hasSuffix("youtu.be") {
            decisionHandler(.allow)
        } else {
            decisionHandler(.cancel)
            NSWorkspace.shared.open(url)
        }
    }
}

struct YouTubePlayerView: View {
    @Environment(YouTubePlayback.self) private var playback

    var body: some View {
        VStack(spacing: 0) {
            header
            WebViewHost(webView: playback.webView)
                .background(Color.black)
        }
        .background(Color.black)
        .ignoresSafeArea()
    }

    private var header: some View {
        HStack(spacing: 14) {
            Button {
                playback.close()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left").font(.system(size: 12, weight: .bold))
                    Text("YouTube").font(.system(size: 13))
                    Text("esc")
                        .font(HushStyle.rounded(10, weight: .semibold))
                        .foregroundStyle(HushStyle.muted)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(HushStyle.ink.opacity(0.14), lineWidth: 1))
                }
                .foregroundStyle(HushStyle.ink)
                .padding(.leading, 8)
                .padding(.trailing, 12)
                .frame(height: 32)
                .background(Capsule().fill(HushStyle.ink.opacity(0.08)))
                .overlay(Capsule().stroke(HushStyle.ink.opacity(0.12), lineWidth: 1))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help("Back to YouTube (Esc)")

            if let video = playback.current {
                VStack(alignment: .leading, spacing: 1) {
                    Text(video.title)
                        .font(HushStyle.serif(16))
                        .foregroundStyle(HushStyle.ink)
                        .lineLimit(1)
                    Text(video.channelAndAge)
                        .font(.system(size: 11.5))
                        .foregroundStyle(HushStyle.muted)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let next = playback.next {
                Button {
                    playback.playNext()
                } label: {
                    HStack(spacing: 10) {
                        YouTubeThumbnail(url: next.thumbnail, cornerRadius: 5)
                            .frame(width: 56)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("NEXT")
                                .font(HushStyle.rounded(10, weight: .bold))
                                .tracking(0.8)
                                .foregroundStyle(HushStyle.gold)
                            Text(next.title)
                                .font(.system(size: 12.5))
                                .foregroundStyle(HushStyle.ink)
                                .lineLimit(1)
                        }
                        Image(systemName: "forward.end.fill").font(.system(size: 12))
                            .foregroundStyle(HushStyle.ink)
                    }
                    .padding(.leading, 4)
                    .padding(.trailing, 12)
                    .frame(height: 40)
                    .frame(maxWidth: 340)
                    .background(RoundedRectangle(cornerRadius: 10).fill(HushStyle.ink.opacity(0.06)))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(HushStyle.ink.opacity(0.10), lineWidth: 1))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Play next")
            }

            Button {
                playback.openInBrowser()
            } label: {
                Image(systemName: "arrow.up.forward.square").font(.system(size: 15))
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(HushIconButtonStyle(idle: Color(red: 0.722, green: 0.710, blue: 0.682)))
            .help("Open in your browser")
        }
        .padding(.leading, 86)
        .padding(.trailing, 20)
        .padding(.vertical, 8)
        .frame(minHeight: 56)
        .background(Color(red: 0.071, green: 0.067, blue: 0.063))
        .background(WindowDragArea())
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color(red: 0.165, green: 0.157, blue: 0.141)).frame(height: 1)
        }
    }
}

/// Hosts a WKWebView in SwiftUI.
struct WebViewHost: NSViewRepresentable {
    let webView: WKWebView
    func makeNSView(context: Context) -> WKWebView { webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

/// A video thumbnail from YouTube (16:9), with the Hush placeholder while it loads.
struct YouTubeThumbnail: View {
    let url: URL?
    var cornerRadius: CGFloat = 12

    var body: some View {
        Color.clear
            .aspectRatio(16 / 9, contentMode: .fit)
            .overlay {
                AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.2))) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        CoverPlaceholder(symbol: "play.rectangle")
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}
