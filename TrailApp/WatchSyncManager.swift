import Foundation
import WatchConnectivity

/// Sends route packages from iPhone to Apple Watch via WatchConnectivity.
///
/// Uses `transferFile` (background delivery, survives the phone app being
/// suspended) rather than `sendMessage` (requires reachability). The payload
/// is a small JSON `RoutePackage` — kilobytes, so transfer is fast even over
/// Bluetooth. The offline tile pack, when built, goes as a separate file
/// transfer; keep it in the low hundreds of MB (no published per-app watch
/// storage cap, but the 75 MB *app* cap means map data must always arrive
/// at runtime, never bundled).
@MainActor
final class WatchSyncManager: NSObject, ObservableObject {
    @Published var isPaired = false
    @Published var isWatchAppInstalled = false
    @Published var isReachable = false
    @Published var pendingTransfers = 0
    @Published var lastError: String?
    @Published var lastSentAt: Date?

    override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    var canSend: Bool {
        WCSession.isSupported() && WCSession.default.isPaired && WCSession.default.isWatchAppInstalled
    }

    /// Builds a RoutePackage for the route and queues a background file transfer.
    func sendToWatch(route: Route, cues: [TurnCue], policy: PromptPolicy = .hiking) {
        guard canSend else {
            lastError = "Apple Watch is not paired or the watch app isn't installed."
            return
        }
        do {
            let package = RoutePackage(
                route: route,
                cues: cues,
                corridor: Corridor.from(route: route),
                promptPolicy: policy
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(package)

            let tmp = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(package.id.uuidString).trailroute")
            try data.write(to: tmp, options: .atomic)

            WCSession.default.transferFile(tmp, metadata: [
                "kind": "route-package",
                "schemaVersion": String(RoutePackage.currentSchemaVersion),
                "routeName": route.name,
            ])
            pendingTransfers = WCSession.default.outstandingFileTransfers.count
            lastSentAt = Date()
            lastError = nil
        } catch {
            lastError = "Couldn't prepare the route for the watch: \(error.localizedDescription)"
        }
    }
}

// MARK: - WCSessionDelegate

extension WatchSyncManager: WCSessionDelegate {
    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor in
            updateReachability(session)
            if let error { lastError = error.localizedDescription }
        }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in updateReachability(session) }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) {
        // Re-activate after switch (required by the API contract).
        WCSession.default.activate()
    }

    private func updateReachability(_ session: WCSession) {
        isPaired = session.isPaired
        isWatchAppInstalled = session.isWatchAppInstalled
        isReachable = session.isReachable
        pendingTransfers = session.outstandingFileTransfers.count
    }
}
