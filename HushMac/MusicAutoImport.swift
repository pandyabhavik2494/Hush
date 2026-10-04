import AppKit
import Foundation
import Observation

/// New songs and videos dropped into the Music app's "Automatically Add to Music" folder only go
/// into the library while the Music app is open. When Hush loads or refreshes and finds files
/// waiting there, it opens Music in the background (never in front), waits for the folder to empty,
/// and reads the library again. If Music wasn't open before, it's quit again afterwards, unless it's
/// playing or you've brought it forward. Files Music won't take stay where they are and are noted
/// once, never retried in a loop. Hush itself never moves, renames or deletes anything.
@MainActor
@Observable
final class MusicAutoImport {
    static let shared = MusicAutoImport()

    /// "Importing 40 new videos into Music", while it runs.
    private(set) var importingNote: String?
    /// "2 files Music couldn't add", when some were refused.
    private(set) var refusedNote: String?

    @ObservationIgnored private var isRunning = false
    @ObservationIgnored private var refused: Set<String>

    private static let musicID = "com.apple.Music"
    private static let refusedKey = "hush.mac.refusedImports"
    nonisolated private static let videoExtensions: Set<String> = ["m4v", "mp4", "mov"]

    private init() {
        refused = Set(UserDefaults.standard.stringArray(forKey: Self.refusedKey) ?? [])
    }

    /// Called whenever a library load finishes.
    func check(folder: URL?) {
        guard !isRunning, let folder else { return }
        isRunning = true
        Task {
            await run(folder)
            isRunning = false
        }
    }

    private func run(_ folder: URL) async {
        let (found, notAdded) = await Self.scan(folder)
        let waiting = found.filter { !refused.contains(Self.fingerprint($0)) }
        guard !waiting.isEmpty else {
            updateRefusedNote(stuck: found.count - waiting.count, notAdded: notAdded)
            return
        }

        importingNote = "Importing \(waiting.count) new \(Self.noun(for: waiting)) into Music"
        hushLog.info("\(waiting.count) files waiting in Automatically Add to Music")
        let wasRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: Self.musicID).isEmpty
        if !wasRunning { await Self.openMusicInBackground() }

        // Music moves each file into the library as it adds it. Check every two seconds, for up to
        // three minutes, for as long as it keeps making progress.
        var remaining = Set(waiting)
        var lastProgress = Date()
        while !remaining.isEmpty, Date().timeIntervalSince(lastProgress) < 180 {
            try? await Task.sleep(for: .seconds(2))
            let now = Set(await Self.scan(folder).waiting)
            let left = remaining.intersection(now)
            if left.count < remaining.count { lastProgress = Date() }
            remaining = left
        }
        // Give Music a moment to finish writing its library.
        try? await Task.sleep(for: .seconds(3))

        if !remaining.isEmpty {
            hushLog.info("Music didn't add \(remaining.count) files; leaving them be")
            refused.formUnion(remaining.map(Self.fingerprint))
            UserDefaults.standard.set(Array(refused), forKey: Self.refusedKey)
        }
        importingNote = nil
        LibraryModel.shared.reload()
        if !wasRunning { Self.quitMusicIfIdle() }
        let (afterFound, afterNotAdded) = await Self.scan(folder)
        updateRefusedNote(stuck: afterFound.filter { refused.contains(Self.fingerprint($0)) }.count, notAdded: afterNotAdded)
    }

    private func updateRefusedNote(stuck: Int, notAdded: Int) {
        let total = stuck + notAdded
        refusedNote = total == 0 ? nil : (total == 1 ? "1 file Music couldn't add" : "\(total) files Music couldn't add")
    }

    // MARK: The folder

    /// The "Automatically Add to Music" folder: inside the library's media folder, found by walking
    /// up from a song's file (the library doesn't always say where its media folder is).
    nonisolated static func folder(mediaFolder: URL?, nearFile file: URL?) -> URL? {
        var candidates: [URL] = []
        if let mediaFolder { candidates.append(mediaFolder) }
        if let file {
            var url = file.deletingLastPathComponent()
            while url.pathComponents.count > 2 {
                candidates.append(url)
                url = url.deletingLastPathComponent()
            }
        }
        for directory in candidates {
            let children = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
            if let match = children.first(where: { $0.lastPathComponent.hasPrefix("Automatically Add to Music") }) {
                return match
            }
        }
        return nil
    }

    /// Files waiting directly in the folder, and how many sit in Music's "Not Added" folder (files
    /// it already turned down; left alone).
    nonisolated private static func scan(_ folder: URL) async -> (waiting: [URL], notAdded: Int) {
        await Task.detached(priority: .utility) {
            let manager = FileManager.default
            let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey]
            let children = (try? manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])) ?? []
            var waiting: [URL] = []
            var notAdded = 0
            for child in children {
                let values = try? child.resourceValues(forKeys: Set(keys))
                if values?.isRegularFile == true {
                    waiting.append(child)
                } else if values?.isDirectory == true, child.lastPathComponent.hasPrefix("Not Added") {
                    notAdded += ((try? manager.contentsOfDirectory(at: child, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []).count
                }
            }
            return (waiting, notAdded)
        }.value
    }

    nonisolated private static func fingerprint(_ url: URL) -> String {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        return "\(url.lastPathComponent)|\(size)"
    }

    nonisolated private static func noun(for files: [URL]) -> String {
        let videos = files.filter { videoExtensions.contains($0.pathExtension.lowercased()) }.count
        if videos == files.count { return files.count == 1 ? "video" : "videos" }
        if videos == 0 { return files.count == 1 ? "song" : "songs" }
        return "files"
    }

    // MARK: The Music app

    private static func openMusicInBackground() async {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: musicID) else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.hides = true
        configuration.addsToRecentItems = false
        _ = try? await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
    }

    /// Quits Music only if it's still hidden in the background and not playing.
    private static func quitMusicIfIdle() {
        guard let music = NSRunningApplication.runningApplications(withBundleIdentifier: musicID).first,
              music.isHidden, !music.isActive else { return }
        DispatchQueue.global(qos: .utility).async {
            var error: NSDictionary?
            NSAppleScript(source: """
            tell application id "com.apple.Music"
                if player state is stopped then quit
            end tell
            """)?.executeAndReturnError(&error)
            if let error {
                hushLog.info("Left Music open: \(error.description, privacy: .public)")
            }
        }
    }
}
