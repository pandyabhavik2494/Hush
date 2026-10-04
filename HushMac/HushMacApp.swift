import AppKit
import SwiftUI

@main
struct HushMacApp: App {
    @NSApplicationDelegateAdaptor(HushAppDelegate.self) private var appDelegate
    @State private var library = LibraryModel.shared
    @State private var player = Player.shared
    @State private var navigator = Navigator.shared
    @State private var video = VideoPlayback.shared
    @State private var access = MediaAccess.shared

    var body: some Scene {
        Window("Hush", id: "main") {
            ContentView()
                .hushEnvironment(library: library, player: player, navigator: navigator, video: video, access: access)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1440, height: 900)
        .commands {
            HushCommands(library: library, player: player, navigator: navigator, video: video)
        }

        Window("Mini Player", id: "mini") {
            MiniPlayerView()
                .hushEnvironment(library: library, player: player, navigator: navigator, video: video, access: access)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.topTrailing)
    }
}

extension View {
    func hushEnvironment(library: LibraryModel, player: Player, navigator: Navigator, video: VideoPlayback, access: MediaAccess) -> some View {
        environment(library)
            .environment(player)
            .environment(navigator)
            .environment(video)
            .environment(access)
            .preferredColorScheme(.dark)
            .tint(HushStyle.gold)
    }
}

// MARK: - Menus and keyboard shortcuts

struct HushCommands: Commands {
    let library: LibraryModel
    let player: Player
    let navigator: Navigator
    let video: VideoPlayback

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Refresh Library") {
                library.reload()
                Task { await ArtistPhotoService.shared.forgetMisses() }
            }
            .keyboardShortcut("r", modifiers: .command)
        }

        CommandGroup(after: .textEditing) {
            Button("Find") { navigator.focusSearch() }
                .keyboardShortcut("f", modifiers: .command)
        }

        CommandMenu("Controls") {
            Button(player.isPlaying ? "Pause" : "Play") { player.togglePlayPause() }
                .disabled(player.current == nil)
            // While a video is open these move through the videos instead.
            Button(video.isShowing ? "Next Video" : "Next Song") {
                if video.isShowing { video.next() } else { player.next() }
            }
            .keyboardShortcut(.rightArrow, modifiers: .command)
            .disabled(video.isShowing ? !video.hasNext : player.current == nil)
            Button(video.isShowing ? "Previous Video" : "Previous Song") {
                if video.isShowing { video.previous() } else { player.previous() }
            }
            .keyboardShortcut(.leftArrow, modifiers: .command)
            .disabled(video.isShowing ? !video.canGoBack : player.current == nil)
            Divider()
            Button("Volume Up") { player.nudgeVolume(by: 0.08) }
                .keyboardShortcut(.upArrow, modifiers: .command)
            Button("Volume Down") { player.nudgeVolume(by: -0.08) }
                .keyboardShortcut(.downArrow, modifiers: .command)
            Divider()
            Button(player.shuffleEnabled ? "Turn Shuffle Off" : "Turn Shuffle On") { player.toggleShuffle() }
                .keyboardShortcut("s", modifiers: [.command, .option])
            Button(repeatTitle) { player.cycleRepeat() }
                .keyboardShortcut("r", modifiers: [.command, .option])
            Divider()
            Button("Go to Current Song") {
                navigator.showsNowPlaying = false
                navigator.revealCurrentSong(player: player, library: library)
            }
            .keyboardShortcut("l", modifiers: .command)
            .disabled(player.current == nil)
            Button("Stop") { player.stop() }
                .keyboardShortcut(".", modifiers: .command)
                .disabled(player.current == nil)
        }

        CommandGroup(before: .sidebar) {
            ForEach(LibrarySection.allCases) { section in
                Button(section.title) { navigator.select(section) }
                    .keyboardShortcut(section.shortcut, modifiers: .command)
            }
            Divider()
            Button("Back") { navigator.back() }
                .keyboardShortcut("[", modifiers: .command)
                .disabled(!navigator.canGoBack)
            Button("Forward") { navigator.forward() }
                .keyboardShortcut("]", modifiers: .command)
                .disabled(!navigator.canGoForward)
            Divider()
            Button(navigator.showsUpNext ? "Hide Up Next" : "Show Up Next") {
                navigator.showsUpNext.toggle()
            }
            .keyboardShortcut("u", modifiers: .command)
            Button(navigator.showsNowPlaying ? "Hide Now Playing" : "Show Now Playing") {
                navigator.showsNowPlaying.toggle()
            }
            .keyboardShortcut("f", modifiers: [.command, .shift])
            .disabled(player.current == nil)
            Divider()
        }

        CommandGroup(after: .windowArrangement) {
            MiniPlayerMenuButton()
        }
    }

    private var repeatTitle: String {
        switch player.repeatMode {
        case .off: return "Repeat All"
        case .all: return "Repeat This Song"
        case .one: return "Turn Repeat Off"
        }
    }
}

private struct MiniPlayerMenuButton: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Mini Player") { openWindow(id: "mini") }
            .keyboardShortcut("m", modifiers: [.command, .shift])
    }
}

// MARK: - App delegate: keys, Dock menu, keep playing when the window closes

@MainActor
final class HushAppDelegate: NSObject, NSApplicationDelegate {
    private var keyMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let handled = MainActor.assumeIsolated { HushAppDelegate.handleKey(event) }
            return handled ? nil : event
        }
    }

    /// Closing the window keeps the music going (the Dock menu and media keys still control it).
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        LibraryModel.shared.reloadIfStale()
    }

    func applicationWillTerminate(_ notification: Notification) {
        Player.shared.saveSession()
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let player = Player.shared
        let menu = NSMenu()
        if let track = player.current {
            let nowPlaying = NSMenuItem(title: "\(track.title) — \(track.artist)", action: nil, keyEquivalent: "")
            nowPlaying.isEnabled = false
            menu.addItem(nowPlaying)
            menu.addItem(.separator())
            menu.addItem(ActionMenuItem(title: player.isPlaying ? "Pause" : "Play") { player.togglePlayPause() })
            menu.addItem(ActionMenuItem(title: "Next Song") { player.next() })
            menu.addItem(ActionMenuItem(title: "Previous Song") { player.previous() })
            menu.addItem(.separator())
            let shuffle = ActionMenuItem(title: "Shuffle") { player.toggleShuffle() }
            shuffle.state = player.shuffleEnabled ? .on : .off
            menu.addItem(shuffle)
        } else {
            let idle = NSMenuItem(title: "Nothing playing", action: nil, keyEquivalent: "")
            idle.isEnabled = false
            menu.addItem(idle)
        }
        return menu
    }

    /// Space plays and pauses anywhere (except while typing). In the video player: Esc closes it,
    /// Z cycles Fit / Fill / Zoom, E turns Enhance on and off, F toggles full screen, ← and → skip 10 seconds. Esc also closes
    /// Now Playing.
    static func handleKey(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.capsLock, .function, .numericPad])
        let isTyping = NSApp.keyWindow?.firstResponder is NSText
        let video = VideoPlayback.shared
        let isMainWindow = NSApp.keyWindow?.identifier?.rawValue.contains("main") ?? true

        if video.isShowing, isMainWindow, modifiers.isEmpty, !isTyping {
            switch event.keyCode {
            case 49: video.togglePlayPause(); return true                  // Space
            case 53: video.close(); return true                            // Esc
            case 6: video.cycleGravity(); return true                      // Z
            case 14: video.enhance.toggle(); return true                   // E
            case 3:                                                         // F
                if let window = NSApp.keyWindow {
                    video.enteredFullScreen = !window.styleMask.contains(.fullScreen)
                    window.toggleFullScreen(nil)
                }
                return true
            case 123: video.skip(by: -10); return true                     // ←
            case 124: video.skip(by: 10); return true                      // →
            default: break
            }
        }

        guard modifiers.isEmpty, !isTyping else { return false }
        switch event.keyCode {
        case 49:
            guard Player.shared.current != nil else { return false }
            Player.shared.togglePlayPause()
            return true
        case 53 where Navigator.shared.showsNowPlaying:
            Navigator.shared.showsNowPlaying = false
            return true
        default:
            return false
        }
    }
}

/// A menu item that runs a closure (for the Dock menu).
final class ActionMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(ActionMenuItem.run), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    @objc private func run() {
        handler()
    }
}
