import AppKit
import AVFoundation
import MediaPlayer
import Observation
import SwiftUI

enum RepeatMode: String, Codable {
    case off, all, one
}

struct QueueEntry: Identifiable, Equatable {
    let id: UUID
    let track: Track
    /// Position in the list it was started from (nil: added with Play Next / Add to Queue).
    let sourceIndex: Int?

    init(track: Track, sourceIndex: Int?) {
        self.id = UUID()
        self.track = track
        self.sourceIndex = sourceIndex
    }

    static func == (lhs: QueueEntry, rhs: QueueEntry) -> Bool { lhs.id == rhs.id }
}

/// Plays your songs. Hush owns the queue (so Up Next, shuffle and repeat are exactly what you see);
/// AVQueuePlayer always has the next song lined up behind the current one, so albums play without
/// gaps. Reports to Control Center, so media keys, AirPods and the Lock Screen all work.
@MainActor
@Observable
final class Player {
    static let shared = Player()

    private(set) var entries: [QueueEntry] = []
    private(set) var currentIndex = 0
    private(set) var isPlaying = false
    private(set) var currentTime: TimeInterval = 0
    private(set) var shuffleEnabled: Bool
    private(set) var repeatMode: RepeatMode
    private(set) var source: PlaybackSource?
    /// Songs played before the current one, most recent first.
    private(set) var history: [QueueEntry] = []
    /// Short confirmation ("Playing Next", "Added to Queue").
    private(set) var toast: String?
    /// 0…1. Hush's own volume (the Mac's volume keys still control the whole system).
    var volume: Double {
        get { volumeLevel }
        set {
            volumeLevel = min(max(newValue, 0), 1)
            avPlayer.volume = Float(volumeLevel)
            UserDefaults.standard.set(volumeLevel, forKey: Keys.volume)
        }
    }
    private var volumeLevel: Double

    /// Exposed only so the AirPlay button can route Hush's sound.
    let avPlayer = AVQueuePlayer()

    @ObservationIgnored private var entryIDForItem: [ObjectIdentifier: UUID] = [:]
    @ObservationIgnored private weak var lastCurrentItem: AVPlayerItem?
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var toastTask: Task<Void, Never>?
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var isSeeking = false
    /// After a tap, the player reports its old state for a moment; keep showing what you chose.
    @ObservationIgnored private var pendingPlayState: (isPlaying: Bool, until: Date)?
    @ObservationIgnored private var nowPlayingArtworkID: UInt64?
    @ObservationIgnored private var nowPlayingArtwork: MPMediaItemArtwork?
    @ObservationIgnored private var hasRestoredSession = false
    @ObservationIgnored private var lastStartedEntryID: UUID?

    private enum Keys {
        static let volume = "hush.volume"
        static let shuffle = "hush.shuffle"
        static let repeatMode = "hush.repeat"
        static let session = "hush.session.v1"
    }

    var current: Track? {
        entries.indices.contains(currentIndex) ? entries[currentIndex].track : nil
    }

    var upNext: [QueueEntry] {
        currentIndex + 1 < entries.count ? Array(entries[(currentIndex + 1)...]) : []
    }

    var duration: TimeInterval { current?.duration ?? 0 }

    private init() {
        let defaults = UserDefaults.standard
        shuffleEnabled = defaults.bool(forKey: Keys.shuffle)
        repeatMode = RepeatMode(rawValue: defaults.string(forKey: Keys.repeatMode) ?? "") ?? .off
        volumeLevel = defaults.object(forKey: Keys.volume) as? Double ?? 0.8
        avPlayer.volume = Float(volumeLevel)
        avPlayer.actionAtItemEnd = .advance
        observePlayer()
        setUpRemoteCommands()
    }

    // MARK: Starting music

    /// Plays a list, from `startIndex` (or from a random song when shuffling with no start).
    func play(_ tracks: [Track], startIndex: Int? = nil, source: PlaybackSource? = nil, shuffle: Bool? = nil) {
        guard !tracks.isEmpty else { return }
        // The song that was playing goes into History before the new list replaces the queue.
        recordHistory()
        lastStartedEntryID = nil
        if let shuffle { setShuffleFlag(shuffle) }
        self.source = source
        let start = startIndex.flatMap { tracks.indices.contains($0) ? $0 : nil }
            ?? (shuffleEnabled ? Int.random(in: tracks.indices) : 0)
        var list = tracks.enumerated().map { QueueEntry(track: $0.element, sourceIndex: $0.offset) }
        if shuffleEnabled {
            let first = list.remove(at: start)
            entries = [first] + list.shuffled()
            startEntry(at: 0, autoplay: true)
        } else {
            entries = list
            startEntry(at: start, autoplay: true)
        }
    }

    func play(_ tracks: [Track], startingAt track: Track, source: PlaybackSource? = nil) {
        play(tracks, startIndex: tracks.firstIndex { $0.id == track.id }, source: source)
    }

    func shufflePlay(_ tracks: [Track], source: PlaybackSource? = nil) {
        play(tracks, startIndex: nil, source: source, shuffle: true)
    }

    // MARK: Transport

    func togglePlayPause() {
        guard current != nil else { return }
        setPlaying(!isPlaying)
    }

    func setPlaying(_ playing: Bool) {
        guard current != nil else { return }
        pendingPlayState = (playing, Date().addingTimeInterval(0.8))
        if playing {
            VideoPlayback.shared.pauseForMusic()
            if avPlayer.currentItem == nil {
                startEntry(at: currentIndex, autoplay: true, at: currentTime)
                return
            }
            avPlayer.play()
        } else {
            avPlayer.pause()
            saveSession()
        }
        isPlaying = playing
        updateNowPlayingInfo()
    }

    func next() {
        guard !entries.isEmpty else { return }
        if let index = indexAfter(currentIndex, automatic: false) {
            startEntry(at: index, autoplay: true)
        } else {
            // End of the list: stay on the last song, stopped at the start.
            startEntry(at: currentIndex, autoplay: false)
        }
    }

    /// Restarts the song if you're more than a few seconds in; otherwise goes back one.
    func previous() {
        guard !entries.isEmpty else { return }
        if currentTime > 3 {
            seek(to: 0)
        } else if currentIndex > 0 {
            startEntry(at: currentIndex - 1, autoplay: true)
        } else if repeatMode == .all, entries.count > 1 {
            startEntry(at: entries.count - 1, autoplay: true)
        } else {
            seek(to: 0)
        }
    }

    func seek(to seconds: TimeInterval) {
        guard current != nil else { return }
        let target = min(max(seconds, 0), max(duration, 0))
        isSeeking = true
        currentTime = target
        avPlayer.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            Task { @MainActor in
                self?.isSeeking = false
                self?.updateNowPlayingInfo()
            }
        }
    }

    func nudgeVolume(by delta: Double) {
        volume = min(max(volume + delta, 0), 1)
    }

    func toggleShuffle() {
        setShuffleFlag(!shuffleEnabled)
        guard entries.indices.contains(currentIndex) else { return }
        let head = Array(entries[...currentIndex])
        var upcoming = upNext
        if shuffleEnabled {
            upcoming.shuffle()
        } else {
            // Back to list order from the current song on, then what you added, then the songs from
            // earlier in the list that shuffle hadn't reached yet — nothing is lost.
            let currentSource = entries[currentIndex].sourceIndex ?? -1
            let fromList = upcoming.filter { $0.sourceIndex != nil }.sorted { ($0.sourceIndex ?? 0) < ($1.sourceIndex ?? 0) }
            let added = upcoming.filter { $0.sourceIndex == nil }
            upcoming = added + fromList.filter { ($0.sourceIndex ?? 0) > currentSource } + fromList.filter { ($0.sourceIndex ?? 0) < currentSource }
        }
        entries = head + upcoming
        enqueueFollowing()
        saveSessionSoon()
    }

    func cycleRepeat() {
        switch repeatMode {
        case .off: repeatMode = .all
        case .all: repeatMode = .one
        case .one: repeatMode = .off
        }
        UserDefaults.standard.set(repeatMode.rawValue, forKey: Keys.repeatMode)
        enqueueFollowing()
    }

    /// Stops the music and forgets the queue.
    func stop() {
        avPlayer.removeAllItems()
        entryIDForItem.removeAll()
        lastCurrentItem = nil
        entries = []
        currentIndex = 0
        isPlaying = false
        currentTime = 0
        source = nil
        lastStartedEntryID = nil
        let center = MPNowPlayingInfoCenter.default()
        center.nowPlayingInfo = nil
        center.playbackState = .stopped
        UserDefaults.standard.removeObject(forKey: Keys.session)
    }

    // MARK: Up Next

    func playNext(_ tracks: [Track]) {
        guard !tracks.isEmpty else { return }
        guard current != nil else {
            play(tracks)
            return
        }
        entries.insert(contentsOf: tracks.map { QueueEntry(track: $0, sourceIndex: nil) }, at: currentIndex + 1)
        enqueueFollowing()
        showToast("Playing Next")
        saveSessionSoon()
    }

    func addToQueue(_ tracks: [Track]) {
        guard !tracks.isEmpty else { return }
        guard current != nil else {
            play(tracks)
            return
        }
        entries.append(contentsOf: tracks.map { QueueEntry(track: $0, sourceIndex: nil) })
        enqueueFollowing()
        showToast("Added to Queue")
        saveSessionSoon()
    }

    func moveUpNext(from offsets: IndexSet, to destination: Int) {
        guard entries.indices.contains(currentIndex) else { return }
        var upcoming = upNext
        upcoming.move(fromOffsets: offsets, toOffset: destination)
        entries = Array(entries[...currentIndex]) + upcoming
        enqueueFollowing()
        saveSessionSoon()
    }

    func removeFromUpNext(id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }), index > currentIndex else { return }
        entries.remove(at: index)
        enqueueFollowing()
        saveSessionSoon()
    }

    func clearUpNext() {
        guard entries.indices.contains(currentIndex) else { return }
        entries = Array(entries[...currentIndex])
        enqueueFollowing()
        saveSessionSoon()
    }

    /// Plays a song from Up Next right away; the rest of Up Next stays as it was.
    func playFromUpNext(id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }), index > currentIndex else { return }
        let entry = entries.remove(at: index)
        entries.insert(entry, at: currentIndex + 1)
        startEntry(at: currentIndex + 1, autoplay: true)
    }

    /// Plays a song from History again right away; what's in Up Next stays as it was.
    func playFromHistory(id: UUID) {
        guard let entry = history.first(where: { $0.id == id }) else { return }
        let again = QueueEntry(track: entry.track, sourceIndex: nil)
        guard current != nil else {
            play([entry.track])
            return
        }
        entries.insert(again, at: currentIndex + 1)
        startEntry(at: currentIndex + 1, autoplay: true)
    }

    func clearHistory() {
        history.removeAll()
    }

    /// Moves the song that was playing into History (when another song takes its place).
    private func recordHistory() {
        guard let lastStartedEntryID,
              let entry = entries.first(where: { $0.id == lastStartedEntryID }) else { return }
        history.removeAll { $0.id == entry.id }
        history.insert(entry, at: 0)
        if history.count > 200 { history.removeLast(history.count - 200) }
    }

    // MARK: Queue engine

    private func startEntry(at index: Int, autoplay: Bool, at time: TimeInterval = 0) {
        guard entries.indices.contains(index) else { return }
        if index != currentIndex || entries[index].id != lastStartedEntryID { recordHistory() }
        currentIndex = index
        lastStartedEntryID = entries[index].id
        avPlayer.removeAllItems()
        entryIDForItem.removeAll()
        let item = makeItem(for: entries[index])
        lastCurrentItem = item
        avPlayer.insert(item, after: nil)
        enqueueFollowing()
        currentTime = time
        if time > 0 {
            avPlayer.seek(to: CMTime(seconds: time, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        }
        pendingPlayState = (autoplay, Date().addingTimeInterval(0.8))
        if autoplay {
            VideoPlayback.shared.pauseForMusic()
            avPlayer.play()
        } else {
            avPlayer.pause()
        }
        isPlaying = autoplay
        updateNowPlayingInfo()
        saveSessionSoon()
    }

    private func makeItem(for entry: QueueEntry) -> AVPlayerItem {
        let item = AVPlayerItem(url: entry.track.location)
        entryIDForItem[ObjectIdentifier(item)] = entry.id
        return item
    }

    /// Keeps exactly one song lined up behind the current one, so the next starts without a gap.
    private func enqueueFollowing() {
        let queued = avPlayer.items()
        guard let playing = queued.first else { return }
        for extra in queued.dropFirst() {
            avPlayer.remove(extra)
        }
        if let next = indexAfter(currentIndex, automatic: true) {
            let item = makeItem(for: entries[next])
            if avPlayer.canInsert(item, after: playing) {
                avPlayer.insert(item, after: playing)
            }
        }
        let live = Set(avPlayer.items().map { ObjectIdentifier($0) })
        entryIDForItem = entryIDForItem.filter { live.contains($0.key) }
    }

    /// The song after `index`. Songs ending on their own repeat under "repeat one"; skipping doesn't.
    private func indexAfter(_ index: Int, automatic: Bool) -> Int? {
        if automatic, repeatMode == .one { return index }
        if index + 1 < entries.count { return index + 1 }
        return repeatMode == .all && !entries.isEmpty ? 0 : nil
    }

    private func currentItemDidChange() {
        guard let item = avPlayer.currentItem else {
            // Played through the whole list: stay on the last song, stopped at the start.
            if avPlayer.items().isEmpty, !entries.isEmpty {
                startEntry(at: currentIndex, autoplay: false)
            }
            return
        }
        guard item !== lastCurrentItem else { return }
        lastCurrentItem = item
        if let entryID = entryIDForItem[ObjectIdentifier(item)],
           let index = entries.firstIndex(where: { $0.id == entryID }),
           index != currentIndex {
            recordHistory()
            currentIndex = index
            lastStartedEntryID = entries[index].id
        }
        currentTime = 0
        enqueueFollowing()
        updateNowPlayingInfo()
        saveSessionSoon()
    }

    private func playerReported(isPlaying reported: Bool) {
        if let pending = pendingPlayState, Date() < pending.until, pending.isPlaying != reported { return }
        pendingPlayState = nil
        guard isPlaying != reported else { return }
        isPlaying = reported
        updateNowPlayingInfo()
    }

    private func observePlayer() {
        observations.append(avPlayer.observe(\.currentItem, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in self?.currentItemDidChange() }
        })
        observations.append(avPlayer.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            let playing = player.timeControlStatus != .paused
            Task { @MainActor in self?.playerReported(isPlaying: playing) }
        })
        timeObserver = avPlayer.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            let seconds = time.seconds
            MainActor.assumeIsolated {
                guard let self, !self.isSeeking, seconds.isFinite else { return }
                self.currentTime = seconds
            }
        }
    }

    private func setShuffleFlag(_ enabled: Bool) {
        guard shuffleEnabled != enabled else { return }
        shuffleEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Keys.shuffle)
    }

    func showToast(_ message: String) {
        toastTask?.cancel()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { toast = message }
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.25)) { self?.toast = nil }
        }
    }

    // MARK: Control Center, media keys, AirPods

    private func setUpRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                if VideoPlayback.shared.handlesMediaKeys { VideoPlayback.shared.setPlaying(true); return }
                self?.setPlaying(true)
            }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                if VideoPlayback.shared.handlesMediaKeys { VideoPlayback.shared.setPlaying(false); return }
                self?.setPlaying(false)
            }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                if VideoPlayback.shared.handlesMediaKeys { VideoPlayback.shared.togglePlayPause(); return }
                self?.togglePlayPause()
            }
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                if VideoPlayback.shared.handlesMediaKeys { VideoPlayback.shared.next(); return }
                self?.next()
            }
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                if VideoPlayback.shared.handlesMediaKeys { VideoPlayback.shared.previous(); return }
                self?.previous()
            }
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let position = event.positionTime
            Task { @MainActor in self?.seek(to: position) }
            return .success
        }
    }

    private func updateNowPlayingInfo() {
        let center = MPNowPlayingInfoCenter.default()
        guard let track = current else {
            center.nowPlayingInfo = nil
            center.playbackState = .stopped
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtist: track.artist,
            MPMediaItemPropertyAlbumTitle: track.albumTitle,
            MPMediaItemPropertyPlaybackDuration: track.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
        ]
        if nowPlayingArtworkID == track.id, let artwork = nowPlayingArtwork {
            info[MPMediaItemPropertyArtwork] = artwork
        }
        center.nowPlayingInfo = info
        center.playbackState = isPlaying ? .playing : .paused
        if nowPlayingArtworkID != track.id {
            loadNowPlayingArtwork(for: track.id)
        }
    }

    private func loadNowPlayingArtwork(for trackID: UInt64) {
        nowPlayingArtworkID = trackID
        nowPlayingArtwork = nil
        Task { [weak self] in
            guard let image = await ArtworkStore.shared.image(for: trackID, pixels: 600) else { return }
            guard let self, self.current?.id == trackID else { return }
            self.nowPlayingArtwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            self.updateNowPlayingInfo()
        }
    }

    // MARK: Resume where you left off

    private struct SavedSession: Codable {
        var trackIDs: [UInt64]
        var sourceIndexes: [Int]
        var currentIndex: Int
        var time: TimeInterval
        var source: PlaybackSource?
    }

    func saveSession() {
        guard !entries.isEmpty else {
            UserDefaults.standard.removeObject(forKey: Keys.session)
            return
        }
        let session = SavedSession(
            trackIDs: entries.map(\.track.id),
            sourceIndexes: entries.map { $0.sourceIndex ?? -1 },
            currentIndex: currentIndex,
            time: currentTime,
            source: source
        )
        if let data = try? JSONEncoder().encode(session) {
            UserDefaults.standard.set(data, forKey: Keys.session)
        }
    }

    private func saveSessionSoon() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else { return }
            self?.saveSession()
        }
    }

    /// After launch, puts your last queue back — paused, at the same spot — once the library is read.
    func restoreSessionIfNeeded(from library: LibraryModel) {
        guard !hasRestoredSession, entries.isEmpty, library.status == .ready else { return }
        hasRestoredSession = true
        guard let data = UserDefaults.standard.data(forKey: Keys.session),
              let session = try? JSONDecoder().decode(SavedSession.self, from: data) else { return }
        var restored: [QueueEntry] = []
        var index = 0
        for (offset, id) in session.trackIDs.enumerated() {
            guard let track = library.track(id: id) else { continue }
            if offset == session.currentIndex { index = restored.count }
            let sourceIndex = offset < session.sourceIndexes.count ? session.sourceIndexes[offset] : -1
            restored.append(QueueEntry(track: track, sourceIndex: sourceIndex >= 0 ? sourceIndex : nil))
        }
        guard restored.indices.contains(index) else { return }
        entries = restored
        source = session.source
        startEntry(at: index, autoplay: false, at: session.time)
    }
}
