import SwiftUI
import WatchKit

/// Entry point for the watchOS app. Activates WatchConnectivity on launch so
/// route packages sent from the iPhone are received even if the watch app
/// was just installed.
@main
struct TrailAppWatchApp: App {
    @StateObject private var sessionManager = WatchSessionManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(sessionManager)
        }
    }
}
