import Foundation
import CoreLocation

/// A single track point on a route.
public struct RoutePoint: Codable, Equatable, Hashable {
    public var latitude: Double
    public var longitude: Double
    /// Elevation in meters, if present in the GPX.
    public var elevation: Double?
    public var timestamp: Date?

    public init(latitude: Double, longitude: Double, elevation: Double? = nil, timestamp: Date? = nil) {
        self.latitude = latitude
        self.longitude = longitude
        self.elevation = elevation
        self.timestamp = timestamp
    }

    public var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    private enum CodingKeys: String, CodingKey {
        case latitude, longitude, elevation, timestamp
    }
}

/// Aggregate stats computed once at import time.
public struct RouteStats: Codable, Equatable, Hashable {
    /// Total distance in meters.
    public var distance: Double
    /// Total ascent in meters.
    public var ascent: Double
    /// Total descent in meters.
    public var descent: Double

    /// Computes distance/ascent/descent. Small elevation jitter below
    /// `smoothingThreshold` meters is ignored to avoid inflating ascent
    /// from noisy GPX elevation data.
    public static func compute(points: [RoutePoint], smoothingThreshold: Double = 3.0) -> RouteStats {
        var distance = 0.0
        var ascent = 0.0
        var descent = 0.0
        let coords = points.map(\.coordinate)
        for i in 1..<coords.count {
            distance += GeoMath.distance(from: coords[i - 1], to: coords[i])
            if let prev = points[i - 1].elevation, let cur = points[i].elevation {
                let delta = cur - prev
                if delta > smoothingThreshold {
                    ascent += delta
                } else if delta < -smoothingThreshold {
                    descent += -delta
                }
            }
        }
        return RouteStats(distance: distance, ascent: ascent, descent: descent)
    }
}

/// A hiking route imported from a GPX file.
public struct Route: Codable, Identifiable, Equatable, Hashable {
    public var id: UUID
    public var name: String
    public var points: [RoutePoint]
    public var sourceFileName: String?
    public var importedAt: Date
    public var stats: RouteStats

    public init(
        id: UUID = UUID(),
        name: String,
        points: [RoutePoint],
        sourceFileName: String? = nil,
        importedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.points = points
        self.sourceFileName = sourceFileName
        self.importedAt = importedAt
        self.stats = RouteStats.compute(points: points)
    }

    public var coordinates: [CLLocationCoordinate2D] {
        points.map(\.coordinate)
    }

    /// True when at least one track point carries elevation. When false,
    /// ascent/descent are unknown (not zero) and the UI must show "—".
    public var hasElevationData: Bool {
        points.contains { $0.elevation != nil }
    }

    /// Cumulative distance in meters at each point index.
    public var cumulativeDistances: [Double] {
        GeoMath.cumulativeDistances(coordinates)
    }

    /// Bounding box of the route, for map framing and corridor-pack building.
    public var boundingBox: (minLat: Double, maxLat: Double, minLon: Double, maxLon: Double)? {
        guard let first = points.first else { return nil }
        var minLat = first.latitude, maxLat = first.latitude
        var minLon = first.longitude, maxLon = first.longitude
        for p in points.dropFirst() {
            minLat = min(minLat, p.latitude); maxLat = max(maxLat, p.latitude)
            minLon = min(minLon, p.longitude); maxLon = max(maxLon, p.longitude)
        }
        return (minLat, maxLat, minLon, maxLon)
    }
}
