import AppKit
import SwiftUI

/// Now Playing, filling the window: painted in the cover's own colours, the big cover on the left,
/// and on the right where it's playing from, the title, scrubber, transport, volume and the next
/// song. Up Next opens as a panel on the right.
struct NowPlayingView: View {
    @Environment(LibraryModel.self) private var library
    @Environment(Player.self) private var player
    @Environment(Navigator.self) private var navigator
    @Environment(\.openWindow) private var openWindow

    private static let cream = Color(red: 0.969, green: 0.945, blue: 0.894)
    private static let accent = Color(red: 0.902, green: 0.784, blue: 0.557)

    var body: some View {
        if let track = player.current {
            ZStack {
                CoverColorBackdrop(id: track.id)
                HStack(spacing: 0) {
                    VStack(spacing: 0) {
                        header
                        GeometryReader { geometry in
                            let coverSize = min(520, geometry.size.height - 40, max(geometry.size.width - 460 - 72 - 128, 240))
                            HStack(spacing: 72) {
                                CoverView(id: track.id, pixels: 1100, cornerRadius: 22)
                                    .frame(width: coverSize, height: coverSize)
                                    .shadow(color: .black.opacity(0.55), radius: 45, y: 40)
                                    .id(track.id)
                                    .transition(.opacity)
                                details(track)
                                    .frame(minWidth: 300, maxWidth: 460)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding(.horizontal, 64)
                            .padding(.bottom, 40)
                            .animation(.easeInOut(duration: 0.35), value: track.id)
                        }
                    }
                    if navigator.showsUpNext {
                        UpNextPanel(onColor: true)
                            .frame(width: 360)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
            }
            .foregroundStyle(Self.cream)
            .onExitCommand { navigator.showsNowPlaying = false }
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Button {
                navigator.showsNowPlaying = false
            } label: {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(HushCircleButtonStyle(diameter: 36, onLight: true))
            .help("Close Now Playing (Esc)")
            Spacer()
            Text("Hush")
                .font(HushStyle.brandFont(size: 20))
                .foregroundStyle(Self.cream.opacity(0.65))
            Spacer()
            Button {
                navigator.showsNowPlaying = false
                openWindow(id: "mini")
            } label: {
                Image(systemName: "pip")
            }
            .buttonStyle(HushCircleButtonStyle(diameter: 36, onLight: true))
            .help("Mini Player (⇧⌘M)")
            Button {
                navigator.showsUpNext.toggle()
            } label: {
                Image(systemName: "list.bullet")
            }
            .buttonStyle(HushCircleButtonStyle(diameter: 36, isOn: navigator.showsUpNext, onLight: true))
            .help("Up Next (⌘U)")
        }
        .padding(.leading, 86)
        .padding(.trailing, 22)
        .padding(.top, 12)
        .frame(height: 64)
        .background(WindowDragArea())
    }

    private func details(_ track: Track) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if let source = player.source, let name = sourceName(source) {
                Button {
                    navigator.show(source)
                } label: {
                    HStack(spacing: 6) {
                        Text("PLAYING FROM")
                            .foregroundStyle(Self.cream.opacity(0.7))
                        Text(name.uppercased())
                            .foregroundStyle(Self.accent)
                            .lineLimit(1)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8, weight: .heavy))
                            .foregroundStyle(Self.cream.opacity(0.7))
                    }
                    .font(HushStyle.rounded(11, weight: .bold))
                    .tracking(0.9)
                }
                .buttonStyle(.plain)
                .pointingHandCursor()
            }

            Text(track.title)
                .font(HushStyle.serif(46))
                .lineLimit(3)
                .minimumScaleFactor(0.6)
                .fixedSize(horizontal: false, vertical: true)
            ArtistNameLinks(credit: track.artist, font: .system(size: 16), color: Self.cream.opacity(0.78))
                .padding(.top, -4)

            Scrubber(tint: Self.accent, textColor: Self.cream.opacity(0.7), track: .white.opacity(0.18))
                .padding(.top, 22)

            HStack {
                Button { player.toggleShuffle() } label: {
                    Image(systemName: "shuffle").font(.system(size: 18, weight: .semibold)).frame(width: 40, height: 40)
                }
                .buttonStyle(HushIconButtonStyle(isActive: player.shuffleEnabled, idle: Self.cream.opacity(0.6), hover: Self.cream))
                Spacer()
                Button { player.previous() } label: {
                    Image(systemName: "backward.end.fill").font(.system(size: 26)).frame(width: 52, height: 52)
                }
                .buttonStyle(HushIconButtonStyle(idle: Self.cream, hover: .white))
                Spacer()
                PlayPauseButton(diameter: 72, fill: Self.cream, symbolColor: Color(red: 0.227, green: 0.071, blue: 0.059))
                    .shadow(color: .black.opacity(0.35), radius: 15, y: 12)
                Spacer()
                Button { player.next() } label: {
                    Image(systemName: "forward.end.fill").font(.system(size: 26)).frame(width: 52, height: 52)
                }
                .buttonStyle(HushIconButtonStyle(idle: Self.cream, hover: .white))
                Spacer()
                Button { player.cycleRepeat() } label: {
                    Image(systemName: player.repeatMode == .one ? "repeat.1" : "repeat")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 40, height: 40)
                }
                .buttonStyle(HushIconButtonStyle(isActive: player.repeatMode != .off, idle: Self.cream.opacity(0.6), hover: Self.cream))
            }
            .padding(.top, 8)

            VolumeControl(tint: Self.cream.opacity(0.85), iconColor: Self.cream.opacity(0.7), showsLoudIcon: true)
                .padding(.top, 16)

            if let next = player.upNext.first {
                HStack(spacing: 12) {
                    Text("NEXT")
                        .font(HushStyle.rounded(11, weight: .bold))
                        .tracking(0.9)
                        .foregroundStyle(Self.cream.opacity(0.6))
                    CoverView(id: next.track.id, pixels: 80, cornerRadius: 5)
                        .frame(width: 28, height: 28)
                    Text("\(next.track.title) · \(next.track.artist)")
                        .font(.system(size: 13))
                        .foregroundStyle(Self.cream.opacity(0.85))
                        .lineLimit(1)
                }
                .padding(.top, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .top) {
                    Rectangle().fill(Self.cream.opacity(0.14)).frame(height: 1)
                }
                .padding(.top, 8)
            }
        }
    }

    private func sourceName(_ source: PlaybackSource) -> String? {
        switch source {
        case .album(let id): return library.album(id: id)?.title
        case .artist(let id): return library.artist(id: id)?.name
        case .playlist(let id): return library.playlist(id: id)?.name
        }
    }
}
