import AppKit
import SwiftUI

/// Every song in a sortable table. Double-click (or Return) plays from that song through the list
/// as it's sorted; right-click for Play Next, Up Next, Go to Album and more.
struct SongsTable: View {
    @Environment(LibraryModel.self) private var library
    @Environment(Player.self) private var player
    @Environment(Navigator.self) private var navigator
    @State private var selection = Set<Track.ID>()
    @State private var sortOrder: [KeyPathComparator<Track>] = [KeyPathComparator(\Track.title, comparator: .localizedStandard)]

    var body: some View {
        let query = LibrarySearch.normalizedQuery(navigator.search(for: .songs))
        let rows = library.songs
            .filter { LibrarySearch.matches($0.searchKey, query: query) }
            .sorted(using: sortOrder)
        Group {
            if rows.isEmpty {
                EmptyStateView(symbol: "music.note", title: query.isEmpty ? "No songs yet" : "No matches",
                               message: query.isEmpty ? "Songs you download in the Music app show up here." : "Try another title, artist or album.")
            } else {
                ScrollViewReader { proxy in
                    table(rows)
                        .onChange(of: navigator.revealRequest) {
                            guard let id = navigator.revealTrackID else { return }
                            selection = [id]
                            proxy.scrollTo(id, anchor: .center)
                        }
                }
            }
        }
        .padding(.horizontal, 12)
    }

    private func table(_ rows: [Track]) -> some View {
        Table(rows, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("") { (track: Track) in
                let isCurrent = player.current?.id == track.id
                ZStack {
                    if isCurrent {
                        NowPlayingBars(isPlaying: player.isPlaying, barWidth: 2.5, height: 11)
                    } else if library.isFavoriteSong(track.id) {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(HushStyle.gold.opacity(0.8))
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .width(28)

            TableColumn("Title", value: \Track.title, comparator: .localizedStandard) { track in
                HStack(spacing: 10) {
                    CoverView(id: track.id, pixels: 80, cornerRadius: 4)
                        .frame(width: 30, height: 30)
                    Text(track.title)
                        .font(.system(size: 13, weight: player.current?.id == track.id ? .semibold : .regular))
                        .foregroundStyle(player.current?.id == track.id ? HushStyle.gold : HushStyle.ink)
                        .lineLimit(1)
                }
            }
            .width(min: 180, ideal: 320)

            TableColumn("Artist", value: \Track.artist, comparator: .localizedStandard) { track in
                Text(track.artist)
                    .foregroundStyle(HushStyle.ink.opacity(0.78))
                    .lineLimit(1)
            }
            .width(min: 120, ideal: 220)

            TableColumn("Album", value: \Track.albumTitle, comparator: .localizedStandard) { track in
                Text(track.albumTitle)
                    .foregroundStyle(HushStyle.ink.opacity(0.78))
                    .lineLimit(1)
            }
            .width(min: 120, ideal: 220)

            TableColumn("Plays", value: \Track.playCount) { track in
                Text(track.playCount > 0 ? "\(track.playCount)" : "")
                    .monospacedDigit()
                    .foregroundStyle(HushStyle.muted)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(56)

            TableColumn("Time", value: \Track.duration) { track in
                Text(HushStyle.timestamp(track.duration))
                    .monospacedDigit()
                    .foregroundStyle(HushStyle.muted)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(56)
        }
        .font(.system(size: 13))
        .scrollContentBackground(.hidden)
        .alternatingRowBackgrounds(.disabled)
        .tint(HushStyle.gold)
        .contextMenu(forSelectionType: Track.ID.self) { ids in
            let picked = rows.filter { ids.contains($0.id) }
            if picked.count == 1, let track = picked.first {
                SongMenu(track: track, list: rows)
            } else if !picked.isEmpty {
                Button("Play \(picked.count) Songs") { player.play(picked) }
                Button("Play Next") { player.playNext(picked) }
                Button("Add to Up Next") { player.addToQueue(picked) }
            }
        } primaryAction: { ids in
            guard let track = rows.first(where: { ids.contains($0.id) }) else { return }
            player.play(rows, startingAt: track)
        }
    }
}
