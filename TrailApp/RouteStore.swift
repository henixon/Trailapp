import Foundation
import SwiftUI

/// Owns the user's route library on iPhone: GPX import, cue computation,
/// and JSON persistence under the app's Documents directory.
@MainActor
final class RouteStore: ObservableObject {
    @Published private(set) var routes: [Route] = []
    @Published private(set) var cuesByRouteID: [UUID: [TurnCue]] = [:]
    @Published var lastError: String?

    private let fileManager = FileManager.default

    init() {
        load()
        importSampleRoutesIfNeeded()
    }

    // MARK: - Bundled samples

    private static let didImportSamplesKey = "didImportSampleRoutes"

    /// Imports the GPX files bundled in SampleRoutes/ on first launch so the
    /// library isn't empty. Runs once (flagged in UserDefaults).
    func importSampleRoutesIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: Self.didImportSamplesKey) else { return }
        UserDefaults.standard.set(true, forKey: Self.didImportSamplesKey)
        guard let urls = Bundle.main.urls(forResourcesWithExtension: "gpx", subdirectory: "SampleRoutes") else { return }
        for url in urls.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            do {
                let route = try importGPX(from: url)
                // Wikiloc files are named "Wikiloc - <Trail>"; drop the prefix.
                let clean = route.name.replacingOccurrences(
                    of: "^Wikiloc - ", with: "", options: .regularExpression)
                if clean != route.name {
                    rename(route: route, to: clean)
                }
            } catch {
                lastError = "Couldn't load sample route \(url.lastPathComponent): \(error.localizedDescription)"
            }
        }
    }

    func rename(route: Route, to newName: String) {
        guard let index = routes.firstIndex(where: { $0.id == route.id }) else { return }
        routes[index].name = newName
        if let cues = cuesByRouteID[route.id] {
            persist(route: routes[index], cues: cues)
        }
    }

    // MARK: - Import

    /// Import failures always name the file and the reason.
    enum ImportError: LocalizedError {
        case failed(fileName: String, underlying: Error)
        var errorDescription: String? {
            switch self {
            case .failed(let fileName, let underlying):
                "Couldn't import \(fileName): \(underlying.localizedDescription)"
            }
        }
    }

    /// Imports a GPX file, parses it, computes turn cues, and persists.
    /// A route with a colliding name gets " 2", " 3", … — never a silent duplicate.
    /// - Returns: The imported route.
    @discardableResult
    func importGPX(from url: URL) throws -> Route {
        let needsScope = url.startAccessingSecurityScopedResource()
        defer { if needsScope { url.stopAccessingSecurityScopedResource() } }

        // Copy into our Documents so the file survives the source going away
        // (e.g. a download that gets cleaned up, or the Files Inbox).
        let dest = documentsDirectory()
            .appendingPathComponent("Routes")
            .appendingPathComponent(url.deletingPathExtension().lastPathComponent)
            .appendingPathExtension("gpx")
        do {
            try fileManager.createDirectory(at: dest.deletingLastPathComponent(),
                                            withIntermediateDirectories: true)
            if fileManager.fileExists(atPath: dest.path) {
                try fileManager.removeItem(at: dest)
            }
            try fileManager.copyItem(at: url, to: dest)

            let parsed = try GPXParser.parse(url: dest)
            let track: [RoutePoint]
            if !parsed.trackPoints.isEmpty {
                track = parsed.trackPoints
            } else {
                // Route-only GPX (no <trk>): treat the named route points as the track.
                track = parsed.routePoints.map(\.point)
            }

            let baseName = parsed.name ?? dest.deletingPathExtension().lastPathComponent
            let route = Route(
                name: uniqueName(for: baseName),
                points: track,
                sourceFileName: dest.lastPathComponent
            )
            let cues = CueEngine.buildCues(track: track, gpxRoutePoints: parsed.routePoints)

            routes.append(route)
            cuesByRouteID[route.id] = cues
            persist(route: route, cues: cues)
            saveIndex()
            return route
        } catch {
            // Don't leave the copied file behind on a failed import.
            try? fileManager.removeItem(at: dest)
            throw ImportError.failed(fileName: url.lastPathComponent, underlying: error)
        }
    }

    /// "Maclehose" → "Maclehose 2" → "Maclehose 3" … first unused variant wins.
    private func uniqueName(for base: String) -> String {
        let existing = Set(routes.map(\.name))
        guard existing.contains(base) else { return base }
        var n = 2
        while existing.contains("\(base) \(n)") { n += 1 }
        return "\(base) \(n)"
    }

    func cues(for routeID: UUID) -> [TurnCue] {
        cuesByRouteID[routeID] ?? []
    }

    func delete(route: Route) {
        routes.removeAll { $0.id == route.id }
        cuesByRouteID.removeValue(forKey: route.id)
        let dir = documentsDirectory().appendingPathComponent("Routes")
        try? fileManager.removeItem(at: dir.appendingPathComponent("\(route.id.uuidString).json"))
        try? fileManager.removeItem(at: dir.appendingPathComponent("\(route.id.uuidString).cues.json"))
        saveIndex()
    }

    // MARK: - Persistence

    private func documentsDirectory() -> URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private func persist(route: Route, cues: [TurnCue]) {
        let dir = documentsDirectory().appendingPathComponent("Routes")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        try? encoder.encode(route)
            .write(to: dir.appendingPathComponent("\(route.id.uuidString).json"))
        try? encoder.encode(cues)
            .write(to: dir.appendingPathComponent("\(route.id.uuidString).cues.json"))
    }

    private func saveIndex() {
        let ids = routes.map(\.id.uuidString)
        UserDefaults.standard.set(ids, forKey: "routeIndex")
    }

    private func load() {
        let dir = documentsDirectory().appendingPathComponent("Routes")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var loaded: [Route] = []
        var cues: [UUID: [TurnCue]] = [:]
        let ids = UserDefaults.standard.stringArray(forKey: "routeIndex") ?? []
        for id in ids {
            let routeURL = dir.appendingPathComponent("\(id).json")
            let cuesURL = dir.appendingPathComponent("\(id).cues.json")
            guard let routeData = try? Data(contentsOf: routeURL),
                  let route = try? decoder.decode(Route.self, from: routeData) else { continue }
            loaded.append(route)
            if let cuesData = try? Data(contentsOf: cuesURL),
               let decoded = try? decoder.decode([TurnCue].self, from: cuesData) {
                cues[route.id] = decoded
            }
        }
        // Fallback: index missing but files present (e.g. restored backup).
        if loaded.isEmpty,
           let files = try? fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
            for file in files where file.pathExtension == "json" && !file.lastPathComponent.hasSuffix(".cues.json") {
                guard let data = try? Data(contentsOf: file),
                      let route = try? decoder.decode(Route.self, from: data) else { continue }
                loaded.append(route)
            }
        }
        self.routes = loaded.sorted { $0.importedAt > $1.importedAt }
        self.cuesByRouteID = cues
    }
}
