import Foundation
import CoreLocation

/// Shared geographic math. All planar approximations use an equirectangular
/// projection around the query point — accurate to well under a meter at
/// trail scale, far cheaper than repeated geodesic solves per GPS fix.
public enum GeoMath {
    public static let earthRadiusMeters = 6_371_000.0
    public static let metersPerDegreeLatitude = 111_320.0

    /// Haversine distance in meters.
    public static func distance(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> Double {
        let lat1 = a.latitude * .pi / 180
        let lat2 = b.latitude * .pi / 180
        let dLat = (b.latitude - a.latitude) * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * earthRadiusMeters * asin(min(1, sqrt(h)))
    }

    /// Initial bearing from a to b in degrees. 0 = north, clockwise.
    public static func bearing(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> Double {
        let lat1 = a.latitude * .pi / 180
        let lat2 = b.latitude * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        return (atan2(y, x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
    }

    /// Signed turn angle in degrees, in (-180, 180]. Positive = right (clockwise).
    public static func turnAngle(bearingIn: Double, bearingOut: Double) -> Double {
        var delta = bearingOut - bearingIn
        while delta > 180 { delta -= 360 }
        while delta <= -180 { delta += 360 }
        return delta
    }

    public struct NearestResult {
        /// Index of the segment's start point in the polyline.
        public let segmentIndex: Int
        public let point: CLLocationCoordinate2D
        /// Perpendicular distance from the query location to the polyline.
        public let crossTrackDistance: Double
        /// Distance along the polyline from its start to the projection.
        public let alongTrackDistance: Double
    }

    /// Nearest point on a polyline to a location.
    /// - Parameters:
    ///   - polyline: Route coordinates.
    ///   - cumulative: Cumulative distances matching `polyline` (see `cumulativeDistances`).
    public static func nearestPoint(
        on polyline: [CLLocationCoordinate2D],
        cumulative: [Double],
        to location: CLLocationCoordinate2D
    ) -> NearestResult? {
        guard polyline.count >= 2, cumulative.count == polyline.count else { return nil }
        let lat0 = location.latitude * .pi / 180
        let kx = earthRadiusMeters * .pi / 180 * cos(lat0)
        let ky = earthRadiusMeters * .pi / 180

        func proj(_ c: CLLocationCoordinate2D) -> (x: Double, y: Double) {
            ((c.longitude - location.longitude) * kx, (c.latitude - location.latitude) * ky)
        }

        var best: NearestResult?
        for i in 0..<(polyline.count - 1) {
            let a = proj(polyline[i])
            let b = proj(polyline[i + 1])
            let abx = b.x - a.x
            let aby = b.y - a.y
            let len2 = abx * abx + aby * aby
            var t: Double = 0
            if len2 > 0 {
                // p is at origin in this local frame.
                t = (-a.x * abx + -a.y * aby) / len2
                t = min(1, max(0, t))
            }
            let qx = a.x + t * abx
            let qy = a.y + t * aby
            let d = hypot(qx, qy)
            if best == nil || d < best!.crossTrackDistance {
                let lon = location.longitude + qx / kx * 180 / .pi
                let lat = location.latitude + qy / ky * 180 / .pi
                let along = cumulative[i] + t * (cumulative[i + 1] - cumulative[i])
                best = NearestResult(
                    segmentIndex: i,
                    point: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                    crossTrackDistance: d,
                    alongTrackDistance: along
                )
            }
        }
        return best
    }

    /// Cumulative distance in meters at each index of `coords`.
    public static func cumulativeDistances(_ coords: [CLLocationCoordinate2D]) -> [Double] {
        var out = [Double](repeating: 0, count: coords.count)
        for i in 1..<coords.count {
            out[i] = out[i - 1] + distance(from: coords[i - 1], to: coords[i])
        }
        return out
    }
}
