import SwiftUI

/// The bar along the bottom of the window: what's playing, the transport and scrubber, Up Next,
/// volume, and the button that opens Now Playing.
struct PlayerBar: View {
    @Environment(LibraryModel.self) private var library
    @Environment(Player.self) private var player
    @Environment(Navigator.self) private var navigator

    var body: some View {
        if let track = player.current {
            HStack(spacing: 20) {
                nowPlaying(track)
                    .frame(maxWidth: .infinity, alignment: .leading)
                transport
                    .frame(maxWidth: .infinity)
                    .layoutPriority(1.25)
                trailing
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.leading, 14)
            .padding(.trailing, 22)
            .frame(height: 76)
            .background(Color(red: 0.094, green: 0.090, blue: 0.082).opacity(0.96))
            .overlay(alignment: .top) {
                Rectangle().fill(Color(red: 0.165, green: 0.157, blue: 0.141)).frame(height: 1)
            }
        }
    }

    private func nowPlaying(_ track: Track) -> some View {
        HStack(spacing: 12) {
            Button {
                navigator.showsNowPlaying = true
            } label: {
                CoverView(id: track.id, pixels: 140, cornerRadius: 9)
                    .frame(width: 52, height: 52)
                    .shadow(color: .black.opacity(0.45), radius: 7, y: 4)
            }
            .buttonStyle(PressScaleButtonStyle())
            .help("Now Playing (⇧⌘F)")

            VStack(alignment: .leading, spacing: 3) {
                Text(track.title)
                    .font(HushStyle.rounded(13.5, weight: .semibold))
                    .foregroundStyle(HushStyle.ink)
                    .lineLimit(1)
                HStack(spacing: 0) {
                    ArtistNameLinks(credit: track.artist, font: .system(size: 11.5), color: Color(red: 0.663, green: 0.651, blue: 0.624))
                    Text(" · ")
                        .font(.system(size: 11.5))
                        .foregroundStyle(HushStyle.muted)
                    Button(track.albumTitle) { navigator.show(.album(track.albumID)) }
                        .buttonStyle(.plain)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Color(red: 0.663, green: 0.651, blue: 0.624))
                        .lineLimit(1)
                        .pointingHandCursor()
                }
                .lineLimit(1)
            }
            .layoutPriority(1)

            let isFavorite = library.isFavoriteSong(track.id)
            Button {
                library.toggleFavoriteSong(track.id)
            } label: {
                Image(systemName: isFavorite ? "heart.fill" : "heart")
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 30, height: 30)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(HushIconButtonStyle(isActive: isFavorite))
            .help(isFavorite ? "Unfavourite" : "Favourite")
        }
    }

    private var transport: some View {
        VStack(spacing: 6) {
            HStack(spacing: 18) {
                Button { player.toggleShuffle() } label: {
                    Image(systemName: "shuffle").font(.system(size: 14, weight: .semibold)).frame(width: 30, height: 30)
                }
                .buttonStyle(HushIconButtonStyle(isActive: player.shuffleEnabled))
                .help(player.shuffleEnabled ? "Turn Shuffle Off" : "Shuffle")

                Button { player.previous() } label: {
                    Image(systemName: "backward.end.fill").font(.system(size: 16)).frame(width: 32, height: 32)
                }
                .buttonStyle(HushIconButtonStyle(idle: HushStyle.ink))
                .help("Previous (⌘←)")

                PlayPauseButton(diameter: 38)

                Button { player.next() } label: {
                    Image(systemName: "forward.end.fill").font(.system(size: 16)).frame(width: 32, height: 32)
                }
                .buttonStyle(HushIconButtonStyle(idle: HushStyle.ink))
                .help("Next (⌘→)")

                Button { player.cycleRepeat() } label: {
                    Image(systemName: player.repeatMode == .one ? "repeat.1" : "repeat")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(HushIconButtonStyle(isActive: player.repeatMode != .off))
                .help(repeatHelp)
            }
            Scrubber(compact: true)
                .frame(maxWidth: 520)
        }
    }

    private var repeatHelp: String {
        switch player.repeatMode {
        case .off: return "Repeat"
        case .all: return "Repeat One"
        case .one: return "Turn Repeat Off"
        }
    }

    private var trailing: some View {
        HStack(spacing: 8) {
            Button {
                navigator.showsUpNext.toggle()
            } label: {
                Image(systemName: "list.bullet")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 32, height: 32)
                    .background(
                        RoundedRectangle(cornerRadius: 8).fill(navigator.showsUpNext ? HushStyle.gold.opacity(0.18) : .clear)
                    )
            }
            .buttonStyle(HushIconButtonStyle(isActive: navigator.showsUpNext, idle: Color(red: 0.722, green: 0.710, blue: 0.682)))
            .help("Up Next (⌘U)")

            VolumeControl()
                .frame(width: 132)

            Button {
                navigator.showsNowPlaying = true
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(HushIconButtonStyle(idle: Color(red: 0.722, green: 0.710, blue: 0.682)))
            .help("Now Playing (⇧⌘F)")
        }
    }
}

/// Elapsed time, the gold scrubber, and time remaining.
struct Scrubber: View {
    var compact = false
    var tint: Color = HushStyle.gold
    var textColor = Color(red: 0.663, green: 0.651, blue: 0.624)
    var track: Color = HushStyle.ink.opacity(0.14)
    @Environment(Player.self) private var player
    @State private var dragTime: TimeInterval?

    var body: some View {
        let duration = player.duration
        let time = dragTime ?? player.currentTime
        let slider = HushSlider(
            value: duration > 0 ? time / duration : 0,
            tint: tint,
            track: track,
            height: compact ? 4 : 6,
            alwaysShowsKnob: !compact,
            knobColor: compact ? HushStyle.ink : Color(red: 0.969, green: 0.945, blue: 0.894),
            onChange: { fraction in dragTime = fraction * duration },
            onEnded: { fraction in
                player.seek(to: fraction * duration)
                dragTime = nil
            }
        )
        let elapsed = Text(HushStyle.timestamp(time))
        let remaining = Text("−" + HushStyle.timestamp(max(duration - time, 0)))
        Group {
            if compact {
                HStack(spacing: 10) {
                    elapsed.frame(width: 38, alignment: .trailing)
                    slider
                    remaining.frame(width: 38, alignment: .leading)
                }
            } else {
                VStack(spacing: 6) {
                    slider
                    HStack {
                        elapsed
                        Spacer()
                        remaining
                    }
                }
            }
        }
        .font(HushStyle.rounded(compact ? 10.5 : 11.5, weight: .medium))
        .monospacedDigit()
        .foregroundStyle(textColor)
    }
}

/// Hush's own volume (the Mac's volume keys still control the whole system).
struct VolumeControl: View {
    var tint = Color(red: 0.914, green: 0.902, blue: 0.867)
    var iconColor = Color(red: 0.722, green: 0.710, blue: 0.682)
    var showsLoudIcon = false
    @Environment(Player.self) private var player

    var body: some View {
        @Bindable var player = player
        HStack(spacing: 8) {
            Button {
                player.volume = player.volume > 0 ? 0 : 0.8
            } label: {
                Image(systemName: volumeSymbol)
                    .font(.system(size: 13))
                    .frame(width: 18)
            }
            .buttonStyle(HushIconButtonStyle(idle: iconColor))
            .help(player.volume > 0 ? "Mute" : "Unmute")
            HushSlider(value: player.volume, tint: tint, track: HushStyle.ink.opacity(0.14), alwaysShowsKnob: true, knobColor: HushStyle.ink) {
                player.volume = $0
            }
            if showsLoudIcon {
                Image(systemName: "speaker.wave.3.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(iconColor)
            }
        }
    }

    private var volumeSymbol: String {
        switch player.volume {
        case 0: return "speaker.slash.fill"
        case ..<0.34: return "speaker.wave.1.fill"
        case ..<0.67: return "speaker.wave.2.fill"
        default: return "speaker.wave.3.fill"
        }
    }
}
