import MediaPlayer
import MusicKit
import SwiftUI
import UIKit

struct QuietTextField: UIViewRepresentable {
    @Binding var text: String
    let placeholder: String
    var capitalization: UITextAutocapitalizationType = .sentences
    var returnKeyType: UIReturnKeyType = .done
    var fontSize: CGFloat = 15
    var fontWeight: UIFont.Weight = .regular
    var placeholderColor: UIColor = UIColor(HushStyle.muted)
    var onSubmit: () -> Void = {}

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.delegate = context.coordinator
        field.addTarget(context.coordinator, action: #selector(Coordinator.textDidChange(_:)), for: .editingChanged)
        field.inlinePredictionType = .no
        field.autocorrectionType = .no
        field.spellCheckingType = .no
        field.smartQuotesType = .no
        field.smartDashesType = .no
        field.smartInsertDeleteType = .no
        field.autocapitalizationType = capitalization
        field.returnKeyType = returnKeyType
        field.clearButtonMode = .never
        field.backgroundColor = .clear
        applyStyle(to: field)
        return field
    }

    func updateUIView(_ field: UITextField, context: Context) {
        context.coordinator.parent = self
        if field.text != text {
            field.text = text
        }
        field.placeholder = placeholder
        field.autocapitalizationType = capitalization
        field.returnKeyType = returnKeyType
        applyStyle(to: field)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    private func applyStyle(to field: UITextField) {
        let systemFont = UIFont.systemFont(ofSize: fontSize, weight: fontWeight)
        if let roundedDescriptor = systemFont.fontDescriptor.withDesign(.rounded) {
            field.font = UIFont(descriptor: roundedDescriptor, size: fontSize)
        } else {
            field.font = systemFont
        }
        field.textColor = UIColor(HushStyle.ink)
        field.tintColor = UIColor(HushStyle.gold)
        field.attributedPlaceholder = NSAttributedString(
            string: placeholder,
            attributes: [.foregroundColor: placeholderColor]
        )
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: QuietTextField

        init(_ parent: QuietTextField) {
            self.parent = parent
        }

        @objc func textDidChange(_ field: UITextField) {
            parent.text = field.text ?? ""
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            textField.resignFirstResponder()
            parent.onSubmit()
            return true
        }
    }
}

struct PlaylistArtwork: View {
    let items: [MPMediaItem]
    let size: CGFloat
    /// The playlist's own cover from the Music app; when nil, a mosaic of album covers is shown.
    var artwork: Artwork? = nil
    var cornerRadius: CGFloat = 10

    private var shownItems: [MPMediaItem] { Array(items.prefix(4)) }
    private var safeSize: CGFloat { size.isFinite ? max(size, 0) : 0 }
    private var cellSize: CGFloat { max((safeSize - 2) / 2, 0) }

    var body: some View {
        Group {
            if let artwork {
                ArtworkImage(artwork, width: safeSize, height: safeSize)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            } else if shownItems.isEmpty {
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(HushStyle.surface)
                    Image(systemName: "music.note.list")
                        .font(.system(size: safeSize * 0.28, weight: .light))
                        .foregroundStyle(HushStyle.gold.opacity(0.8))
                }
            } else if shownItems.count == 1 {
                ArtworkView(item: shownItems[0], cornerRadius: cornerRadius, size: CGSize(width: safeSize, height: safeSize))
            } else {
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 2), GridItem(.flexible(), spacing: 2)],
                    spacing: 2
                ) {
                    ForEach(Array(shownItems.enumerated()), id: \.offset) { _, item in
                        ArtworkView(item: item, cornerRadius: 3, size: CGSize(width: 120, height: 120))
                            .frame(width: cellSize, height: cellSize)
                    }
                }
                .frame(width: safeSize, height: safeSize)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            }
        }
        .frame(width: safeSize, height: safeSize)
        .accessibilityHidden(true)
    }
}

/// Read-only view of a Music app playlist. Edit playlists in Apple Music, then pull down to refresh.
struct PlaylistDetailView: View {
    @EnvironmentObject private var library: MusicLibraryStore

    let playlist: MusicPlaylist
    let artworkNamespace: Namespace.ID
    let onPlay: (MPMediaItem, [MPMediaItem], String) -> Void
    let onShuffle: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The playing song is brought into view once, when the page first opens.
    @State private var hasRevealedCurrentTrack = false

    private var songs: [MPMediaItem] { playlist.items }

    /// "24 songs · 1 hr 32 min · Apple Music".
    private var playlistDetails: String {
        var parts = [songs.count == 1 ? "1 song" : "\(songs.count) songs"]
        if let length = HushStyle.durationText(songs.reduce(0) { $0 + $1.playbackDuration }) {
            parts.append(length)
        }
        parts.append("Apple Music")
        return parts.joined(separator: " · ")
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                HushStyle.paper.ignoresSafeArea()
                // The playlist's cover colors light the top of the page, behind the glass controls.
                AmbientArtworkGlow(item: playlist.artworkItems.first, height: 560, strength: 0.72)
                ScrollViewReader { proxy in
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 0) {
                            PlaylistArtwork(
                                items: playlist.artworkItems,
                                size: min(max(geometry.size.width - 72, 0), 310),
                                artwork: library.artwork(for: playlist)
                            )
                                // The player grows out of this cover when you tap Shuffle.
                                .zoomSource(PlayerArtworkTransitionID.playlistTile(playlist.id), in: artworkNamespace)
                                .shadow(color: .black.opacity(0.16), radius: 14, x: 0, y: 7)
                                .frame(maxWidth: .infinity)
                                .padding(.top, 8)

                            Text(playlist.name)
                                .font(.system(size: 29, weight: .regular, design: .serif))
                                .tracking(-0.5)
                                .foregroundStyle(HushStyle.ink)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity)
                                .padding(.horizontal, 26)
                                .padding(.top, 20)

                            Text(playlistDetails)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(HushStyle.muted)
                                .frame(maxWidth: .infinity)
                                .padding(.top, 7)

                            HStack(spacing: 10) {
                                Button {
                                    guard let first = songs.first else { return }
                                    onPlay(first, songs, PlayerArtworkTransitionID.playlistTrack(first.persistentID))
                                } label: {
                                    Label("Play", systemImage: "play.fill")
                                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                                        .foregroundStyle(HushStyle.paper)
                                        .padding(.horizontal, 20)
                                        .frame(height: 44)
                                        .background(HushStyle.gold, in: Capsule())
                                }
                                .buttonStyle(PopButtonStyle())

                                Button(action: onShuffle) {
                                    Label("Shuffle", systemImage: "shuffle")
                                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                                        .foregroundStyle(HushStyle.gold)
                                        .padding(.horizontal, 20)
                                        .frame(height: 44)
                                        .hushGlassBackground(Capsule())
                                        .contentShape(Capsule())
                                }
                                // Plain press style: the glass never scales or animates.
                                .buttonStyle(.plain)
                            }
                            .disabled(songs.isEmpty)
                            .opacity(songs.isEmpty ? 0.45 : 1)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 19)

                            if songs.isEmpty {
                                VStack(spacing: 9) {
                                    Text("Nothing here yet")
                                        .font(.system(size: 20, weight: .regular, design: .serif))
                                        .foregroundStyle(HushStyle.ink)
                                    Text("Add songs to this playlist in Apple Music, then pull down to refresh.")
                                        .font(.system(size: 13))
                                        .foregroundStyle(HushStyle.muted)
                                        .multilineTextAlignment(.center)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.horizontal, 28)
                                .padding(.top, 34)
                            } else {
                                LazyVStack(spacing: 0) {
                                    // Identify rows by position: Music playlists can contain the same song twice.
                                    ForEach(Array(songs.enumerated()), id: \.offset) { index, item in
                                        Button {
                                            onPlay(item, songs, PlayerArtworkTransitionID.playlistTrack(item.persistentID))
                                        } label: {
                                            trackRow(item, number: index + 1)
                                        }
                                        .buttonStyle(.plain)
                                        .queueMenu([item])
                                        .id(index)

                                        if index < songs.count - 1 {
                                            Rectangle()
                                                .fill(HushStyle.line.opacity(0.55))
                                                .frame(height: 0.6)
                                                .padding(.leading, 62)
                                        }
                                    }
                                }
                                .padding(.horizontal, 24)
                                .padding(.top, 22)
                            }
                        }
                        .padding(.bottom, 28)
                    }
                    .miniPlayerClearance()
                    .refreshable { await library.refreshLibrary() }
                    .onAppear { revealCurrentTrack(with: proxy) }
                }
            }
        }
        // System back button (gold chevron, no title) keeps the standard swipe-from-edge to go back.
        // The navigation bar is left transparent, so on iOS 26 the back button floats as Liquid
        // Glass over the cover's glow.
        .toolbarRole(.editor)
        .tint(HushStyle.gold)
    }

    /// Opening the playlist that's playing brings its current song into view — only when that song
    /// is below the first screen, and only once the page has finished opening.
    private func revealCurrentTrack(with proxy: ScrollViewProxy) {
        guard !hasRevealedCurrentTrack else { return }
        hasRevealedCurrentTrack = true
        guard let currentID = library.currentItem?.persistentID,
              let index = songs.firstIndex(where: { $0.persistentID == currentID }),
              index >= 4 else { return }
        let animation: Animation? = reduceMotion ? nil : .smooth(duration: 0.6)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 450_000_000)
            withAnimation(animation) {
                proxy.scrollTo(index, anchor: .center)
            }
        }
    }

    @ViewBuilder
    private func trackRow(_ item: MPMediaItem, number: Int) -> some View {
        let isCurrent = library.currentItem?.persistentID == item.persistentID
        HStack(spacing: 12) {
            TrackNumberLabel(number: number, isCurrent: isCurrent)
                .frame(width: 26, alignment: .leading)

            let artwork = ArtworkView(item: item, cornerRadius: 8, size: CGSize(width: 120, height: 120))
                .frame(width: 48, height: 48)
            if #available(iOS 18.0, *) {
                artwork.matchedTransitionSource(
                    id: PlayerArtworkTransitionID.playlistTrack(item.persistentID),
                    in: artworkNamespace
                )
            } else {
                artwork
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title ?? "Untitled")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(isCurrent ? HushStyle.gold : HushStyle.ink)
                    .lineLimit(1)
                Text([item.artist, item.albumTitle].compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 12))
                    .foregroundStyle(HushStyle.muted)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}
