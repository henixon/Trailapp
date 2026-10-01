import Foundation
import WatchConnectivity

/// Receives RoutePackage files from the iPhone and persists them locally on
/// the watch. Packages are small JSON (kilobytes); the offline tile pack —
/// when we ship one — arrives as a separate file transfer.
@MainActor
final class WatchSessionManager: NSObject, ObservableObject {
    @Published private(set) var packages: [RoutePackage] = []
    @Published var lastError: String?

    private let fileManager = FileManager.default

    override init() {
        super.init()
        if WCSession.isSupported() {
            let session = WCSession.default
            session.delegate = self
            session.activate()
        }
        loadPackages()
    }

    func package(id: UUID) -> RoutePackage? {
        packages.first { $0.id == id }
    }

    func delete(_ package: RoutePackage) {
        packages.removeAll { $0.id == package.id }
        try? fileManager.removeItem(at: packageURL(for: package.id))
    }

    // MARK: - Persistence

    private func packagesDirectory() -> URL {
        let url = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Packages")
        try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func packageURL(for id: UUID) -> URL {
        packagesDirectory().appendingPathComponent("\(id.uuidString).trailroute")
    }

    private func loadPackages() {
        let dir = packagesDirectory()
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var loaded: [RoutePackage] = []
        if let files = try? fileManager.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil) {
            for file in files where file.pathExtension == "trailroute" {
                guard let data = try? Data(contentsOf: file),
                      let pkg = try? decoder.decode(RoutePackage.self, from: data),
                      pkg.schemaVersion <= RoutePackage.currentSchemaVersion else { continue }
                loaded.append(pkg)
            }
        }
        packages = loaded.sorted { $0.createdAt > $1.createdAt }
    }
}

// MARK: - WCSessionDelegate

extension WatchSessionManager: WCSessionDelegate {
    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        if let error {
            Task { @MainActor in self.lastError = error.localizedDescription }
        }
    }

    /// Called when the iPhone's `transferFile` completes — even if our app
    /// wasn't running. Validate, persist, and publish.
    func session(_ session: WCSession, didReceive file: WCSessionFile) {
        Task { @MainActor in
            do {
                guard file.metadata?["kind"] as? String == "route-package" else { return }
                let data = try Data(contentsOf: file.fileURL)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let package = try decoder.decode(RoutePackage.self, from: data)
                guard package.schemaVersion <= RoutePackage.currentSchemaVersion else {
                    lastError = "Route package is from a newer app version."
                    return
                }
                try data.write(to: packageURL(for: package.id), options: .atomic)
                packages.removeAll { $0.id == package.id }
                packages.insert(package, at: 0)
                lastError = nil
                // Haptic tap so the user knows a route arrived.
                WKInterfaceDevice.current().play(.success)
            } catch {
                lastError = "Couldn't save the incoming route: \(error.localizedDescription)"
            }
        }
    }
}
