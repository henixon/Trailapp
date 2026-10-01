import Foundation

/// Geographic corridor around a route, used to size the offline map pack.
/// The watch app must never bundle map data (75 MB app cap) — it receives
/// only this corridor's tile pack at runtime via WatchConnectivity.
public struct Corridor: Codable, Equatable {
    public var minLatitude: Double
    public var maxLatitude: Double
    public var minLongitude: Double
    public var maxLongitude: Double
    /// Padding in meters applied around the route bbox when this was built.
    public var paddingMeters: Double

    public init(minLatitude: Double, maxLatitude: Double, minLongitude: Double, maxLongitude: Double, paddingMeters: Double) {
        self.minLatitude = minLatitude
        self.maxLatitude = maxLatitude
        self.minLongitude = minLongitude
        self.maxLongitude = maxLongitude
        self.paddingMeters = paddingMeters
    }

    /// Builds a corridor from a route bbox with padding (approx degrees).
    public static func from(route: Route, paddingMeters: Double = 1500) -> Corridor? {
        guard let box = route.boundingBox else { return nil }
        // ~111,320 m per degree of latitude.
        let padLat = paddingMeters / 111_320.0
        let midLat = (box.minLat + box.maxLat) / 2
        let padLon = paddingMeters / (111_320.0 * max(0.2, cos(midLat * .pi / 180)))
        return Corridor(
            minLatitude: box.minLat - padLat,
            maxLatitude: box.maxLat + padLat,
            minLongitude: box.minLon - padLon,
            maxLongitude: box.maxLon + padLon,
            paddingMeters: paddingMeters
        )
    }
}

/// The complete payload synced from iPhone to Apple Watch for one route.
/// Sent as a single JSON file via WCSession.transferFile. Deliberately small
/// (kilobytes): route geometry + cues + corridor descriptor. The (much larger)
/// offline tile pack, when present, is transferred as a separate file.
public struct RoutePackage: Codable, Identifiable, Equatable {
    public var id: UUID
    public var route: Route
    public var cues: [TurnCue]
    public var corridor: Corridor?
    public var promptPolicy: PromptPolicy
    public var createdAt: Date
    /// Schema version so the watch can reject packages it can't read.
    public var schemaVersion: Int

    public static let currentSchemaVersion = 1

    public init(
        id: UUID = UUID(),
        route: Route,
        cues: [TurnCue],
        corridor: Corridor?,
        promptPolicy: PromptPolicy = .hiking,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.route = route
        self.cues = cues
        self.corridor = corridor
        self.promptPolicy = promptPolicy
        self.createdAt = createdAt
        self.schemaVersion = Self.currentSchemaVersion
    }
}
