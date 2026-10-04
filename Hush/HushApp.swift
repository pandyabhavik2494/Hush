 import SwiftUI

@main
struct HushApp: App {
    /// Lets the phone turn sideways while a video is playing (see HushAppDelegate); upright otherwise.
    @UIApplicationDelegateAdaptor(HushAppDelegate.self) private var appDelegate
    @StateObject private var library = MusicLibraryStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(library)
                .environmentObject(library.playback)
                .environmentObject(library.queue)
                .preferredColorScheme(.dark)
                .onChange(of: scenePhase) { _, phase in
                    // Re-check permission and playback state whenever Hush comes back to the foreground.
                    if phase == .active { library.handleBecameActive() }
                    // Remember the queue and position so a relaunch picks up where you left off.
                    if phase == .background { library.saveSession() }
                }
        }
    }
}
