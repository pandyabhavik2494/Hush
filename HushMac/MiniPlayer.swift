import AppKit
import SwiftUI

/// A small floating player (⇧⌘M): the cover, the song, the transport, and a thin progress line,
/// on the cover's own colours. Stays above other windows.
struct MiniPlayerView: View {
    @Environment(Player.self) private var player
    @Environment(Navigator.self) private var navigator
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    private static let cream = Color(red: 0.969, green: 0.945, blue: 0.894)
    private static let accent = Color(red: 0.902, green: 0.784, blue: 0.557)

    var body: some View {
        ZStack(alignment: .bottom) {
            CoverColorBackdrop(id: player.current?.id)
            HStack(spacing: 14) {
                Button {
                    showMainWindow(nowPlaying: true)
                } label: {
                    CoverView(id: player.current?.id, pixels: 240, cornerRadius: 10)
                        .frame(width: 96, height: 96)
                        .shadow(color: .black.opacity(0.45), radius: 10, y: 8)
                }
                .buttonStyle(PressScaleButtonStyle())
                .help("Open Now Playing")

                VStack(alignment: .leading, spacing: 2) {
                    Text(player.current?.title ?? "Nothing playing")
                        .font(HushStyle.rounded(14, weight: .semibold))
                        .lineLimit(1)
                    Text(player.current?.artist ?? "Choose something in Hush")
                        .font(.system(size: 12))
                        .foregroundStyle(Self.cream.opacity(0.7))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    HStack {
                        Button { player.previous() } label: {
                            Image(systemName: "backward.end.fill").font(.system(size: 16)).frame(width: 34, height: 34)
                        }
                        .buttonStyle(HushIconButtonStyle(idle: Self.cream, hover: .white))
                        Spacer()
                        PlayPauseButton(diameter: 38, fill: Self.cream, symbolColor: Color(red: 0.227, green: 0.071, blue: 0.059))
                        Spacer()
                        Button { player.next() } label: {
                            Image(systemName: "forward.end.fill").font(.system(size: 16)).frame(width: 34, height: 34)
                        }
                        .buttonStyle(HushIconButtonStyle(idle: Self.cream, hover: .white))
                        Spacer()
                        Button { showMainWindow(nowPlaying: false) } label: {
                            Image(systemName: "arrow.up.left.and.arrow.down.right").font(.system(size: 13, weight: .semibold)).frame(width: 34, height: 34)
                        }
                        .buttonStyle(HushIconButtonStyle(idle: Self.cream.opacity(0.75), hover: .white))
                        .help("Back to the full window")
                    }
                    .disabled(player.current == nil)
                }
                .frame(maxHeight: .infinity)
            }
            .padding(16)

            GeometryReader { geometry in
                let fraction = player.duration > 0 ? min(player.currentTime / player.duration, 1) : 0
                ZStack(alignment: .leading) {
                    Rectangle().fill(.white.opacity(0.12))
                    Rectangle().fill(Self.accent).frame(width: geometry.size.width * fraction)
                }
            }
            .frame(height: 3)
        }
        .foregroundStyle(Self.cream)
        .frame(width: 400, height: 132)
        .background(WindowDragArea())
        .background(FloatingWindow())
        .ignoresSafeArea()
    }

    private func showMainWindow(nowPlaying: Bool) {
        openWindow(id: "main")
        navigator.showsNowPlaying = nowPlaying && player.current != nil
        dismissWindow(id: "mini")
    }
}

/// Keeps the window it's in above other apps' windows and on every Space.
struct FloatingWindow: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.level = .floating
            window.collectionBehavior.insert(.canJoinAllSpaces)
            window.isMovableByWindowBackground = true
            window.standardWindowButton(.miniaturizeButton)?.isHidden = true
            window.standardWindowButton(.zoomButton)?.isHidden = true
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
