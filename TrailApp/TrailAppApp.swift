import SwiftUI
import UniformTypeIdentifiers

@main
struct TrailAppApp: App {
    @StateObject private var routeStore = RouteStore()
    @StateObject private var watchSync = WatchSyncManager()

    var body: some Scene {
        WindowGroup {
            RouteListView()
                .environmentObject(routeStore)
                .environmentObject(watchSync)
                .onOpenURL { url in
                    // Handles "Open in TrailApp" from Files, Safari downloads, AirDrop, etc.
                    // The system copies the file into our Inbox; import from there.
                    Task { @MainActor in
                        do {
                            try routeStore.importGPX(from: url)
                        } catch {
                            routeStore.lastError = error.localizedDescription
                        }
                    }
                }
        }
    }
}

extension UTType {
    /// GPX isn't a system type; we declare it via UTExportedTypeDeclarations
    /// in project.yml so this resolves on device. Falls back to .xml for the
    /// simulator / pre-install edge cases.
    static var gpx: UTType {
        UTType(filenameExtension: "gpx") ?? .xml
    }
}
