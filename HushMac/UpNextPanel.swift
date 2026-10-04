import SwiftUI

/// The Up Next panel: the playing song, then the queue (drag to reorder) or what's been played.
struct UpNextPanel: View {
    /// Over Now Playing's colours: translucent instead of the panel colour.
    var onColor = false
    @Environment(Player.self) private var player
    @State private var tab: Tab = .queue

    enum Tab: String, CaseIterable {
        case queue = "Queue"
        case history = "History"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Up Next")
                    .font(HushStyle.serif(22))
                    .foregroundStyle(HushStyle.ink)
                Spacer()
                HStack(spacing: 0) {
                    ForEach(Tab.allCases, id: \.self) { option in
                        Button {
                            tab = option
                        } label: {
                            Text(option.rawValue)
                                .font(.system(size: 12, weight: tab == option ? .semibold : .medium))
                                .foregroundStyle(tab == option ? HushStyle.paper : HushStyle.ink.opacity(0.85))
                                .padding(.horizontal, 12)
                                .frame(height: 26)
                                .background(Capsule().fill(tab == option ? HushStyle.gold : .clear))
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(3)
                .background(Capsule().fill(HushStyle.fill))
            }
            .padding(.horizontal, 18)
            .padding(.top, onColor ? 66 : 18)
            .padding(.bottom, 12)

            if let track = player.current {
                HStack(spacing: 12) {
                    CoverView(id: track.id, pixels: 120, cornerRadius: 6)
                        .frame(width: 44, height: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(track.title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(HushStyle.ink)
                            .lineLimit(1)
                        Text(track.artist)
                            .font(.system(size: 11.5))
                            .foregroundStyle(HushStyle.muted)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 6)
                    NowPlayingBars(isPlaying: player.isPlaying, height: 12)
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(HushStyle.gold.opacity(0.10)))
                .padding(.horizontal, 14)
            }

            switch tab {
            case .queue: queue
            case .history: history
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(onColor ? AnyShapeStyle(Color.black.opacity(0.28)) : AnyShapeStyle(Color(red: 0.078, green: 0.075, blue: 0.067).opacity(0.96)))
        .overlay(alignment: .leading) {
            Rectangle().fill(onColor ? Color.white.opacity(0.10) : HushStyle.line).frame(width: 1)
        }
    }

    private var queue: some View {
        let upcoming = player.upNext
        return VStack(alignment: .leading, spacing: 0) {
            listHeader(title: upcoming.isEmpty ? "NOTHING QUEUED" : "\(upcoming.count) TO COME", clearTitle: "Clear", canClear: !upcoming.isEmpty) {
                player.clearUpNext()
            }
            if upcoming.isEmpty {
                Text("Right-click any song and choose Play Next or Add to Up Next.")
                    .font(.system(size: 12))
                    .foregroundStyle(HushStyle.muted)
                    .padding(.horizontal, 18)
                    .padding(.top, 4)
                Spacer()
            } else {
                List {
                    ForEach(upcoming) { entry in
                        QueueRow(track: entry.track) {
                            player.playFromUpNext(id: entry.id)
                        } remove: {
                            player.removeFromUpNext(id: entry.id)
                        }
                        .listRowInsets(EdgeInsets(top: 0, leading: 6, bottom: 0, trailing: 6))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }
                    .onMove { offsets, destination in
                        player.moveUpNext(from: offsets, to: destination)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: 0) {
            listHeader(title: player.history.isEmpty ? "NOTHING PLAYED YET" : "RECENTLY PLAYED", clearTitle: "Clear", canClear: !player.history.isEmpty) {
                player.clearHistory()
            }
            if player.history.isEmpty {
                Spacer()
            } else {
                List {
                    ForEach(player.history) { entry in
                        QueueRow(track: entry.track, play: { player.playFromHistory(id: entry.id) }, remove: nil)
                        .listRowInsets(EdgeInsets(top: 0, leading: 6, bottom: 0, trailing: 6))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
    }

    private func listHeader(title: String, clearTitle: String, canClear: Bool, clear: @escaping () -> Void) -> some View {
        HStack {
            Text(title)
                .font(HushStyle.rounded(10.5, weight: .bold))
                .tracking(0.85)
                .foregroundStyle(HushStyle.muted)
            Spacer()
            if canClear {
                Button(clearTitle, action: clear)
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(HushStyle.gold)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 6)
    }
}

struct QueueRow: View {
    let track: Track
    let play: () -> Void
    let remove: (() -> Void)?
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 10) {
            CoverView(id: track.id, pixels: 90, cornerRadius: 5)
                .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(.system(size: 13))
                    .foregroundStyle(HushStyle.ink)
                    .lineLimit(1)
                Text(track.artist)
                    .font(.system(size: 11.5))
                    .foregroundStyle(HushStyle.muted)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            if isHovering, let remove {
                Button(action: remove) {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).frame(width: 22, height: 22)
                }
                .buttonStyle(HushIconButtonStyle())
                .help("Remove from Up Next")
            } else {
                Text(HushStyle.timestamp(track.duration))
                    .font(.system(size: 11.5))
                    .monospacedDigit()
                    .foregroundStyle(HushStyle.muted)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 48)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(isHovering ? HushStyle.ink.opacity(0.05) : .clear))
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture(count: 2, perform: play)
        .contextMenu {
            Button("Play Now", action: play)
            if let remove { Button("Remove from Up Next", action: remove) }
        }
        .help("Double-click to play")
    }
}
