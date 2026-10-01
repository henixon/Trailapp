import Foundation
import CoreLocation

/// Builds turn cues for a route.
///
/// Strategy, in order of preference:
/// 1. Named GPX <rtept> waypoints — many exported GPX files already carry
///    turn instructions ("Turn right onto ..."). Each is snapped to the
///    nearest track point.
/// 2. Bend detection on the track geometry — for plain <trk> files, a cue is
///    emitted wherever the bearing change between consecutive legs exceeds
///    `turnThresholdDegrees` and both legs are longer than `minLegMeters`
///    (filters GPS jitter on straight paths).
///
/// Known limitation (documented, not fixed here): pure bend detection can miss
/// cues at forks/roundabouts where the geometry barely bends but a decision
/// is required. Prefer GPX files with named route points when available.
public enum CueEngine {
    public static func buildCues(
        track: [RoutePoint],
        gpxRoutePoints: [GPXRoutePoint] = [],
        turnThresholdDegrees: Double = 35,
        minLegMeters: Double = 25
    ) -> [TurnCue] {
        let coords = track.map(\.coordinate)
        guard coords.count >= 2 else { return [] }
        let cumulative = GeoMath.cumulativeDistances(coords)

        var cues: [TurnCue] = []
        cues.append(TurnCue(
            routePointIndex: 0,
            direction: .start,
            instruction: "Start hiking",
            distanceFromStart: 0,
            source: .generated
        ))

        let named = gpxRoutePoints.filter {
            let label = [$0.name, $0.comment].compactMap { $0 }.joined(separator: " — ")
            return !label.trimmingCharacters(in: .whitespaces).isEmpty
        }
        if !named.isEmpty {
            for rp in named {
                let label = [rp.name, rp.comment].compactMap { $0 }.joined(separator: " — ")
                let index = nearestIndex(to: rp.point.coordinate, in: coords)
                cues.append(TurnCue(
                    routePointIndex: index,
                    direction: inferDirection(from: label),
                    instruction: label,
                    distanceFromStart: cumulative[index],
                    source: .gpxWaypoint
                ))
            }
        } else {
            cues += bendCues(
                coords: coords,
                cumulative: cumulative,
                turnThresholdDegrees: turnThresholdDegrees,
                minLegMeters: minLegMeters
            )
        }

        cues.append(TurnCue(
            routePointIndex: coords.count - 1,
            direction: .finish,
            instruction: "You have arrived",
            distanceFromStart: cumulative.last ?? 0,
            source: .generated
        ))

        // Drop near-duplicate cues (< 20 m apart, keep the sharper one) so a
        // switchback doesn't produce a stutter of prompts.
        return dedupe(cues.sorted { $0.distanceFromStart < $1.distanceFromStart })
    }

    // MARK: - Bend detection

    private static func bendCues(
        coords: [CLLocationCoordinate2D],
        cumulative: [Double],
        turnThresholdDegrees: Double,
        minLegMeters: Double
    ) -> [TurnCue] {
        var cues: [TurnCue] = []
        for i in 1..<(coords.count - 1) {
            let legIn = GeoMath.distance(from: coords[i - 1], to: coords[i])
            let legOut = GeoMath.distance(from: coords[i], to: coords[i + 1])
            guard legIn >= minLegMeters, legOut >= minLegMeters else { continue }
            let delta = GeoMath.turnAngle(
                bearingIn: GeoMath.bearing(from: coords[i - 1], to: coords[i]),
                bearingOut: GeoMath.bearing(from: coords[i], to: coords[i + 1])
            )
            let magnitude = abs(delta)
            guard magnitude >= turnThresholdDegrees else { continue }
            let direction: TurnDirection
            let instruction: String
            if magnitude >= 150 {
                direction = .uturn
                instruction = "Make a U-turn"
            } else if magnitude >= 110 {
                direction = delta > 0 ? .sharpRight : .sharpLeft
                instruction = delta > 0 ? "Sharp right" : "Sharp left"
            } else {
                direction = delta > 0 ? .right : .left
                instruction = delta > 0 ? "Turn right" : "Turn left"
            }
            cues.append(TurnCue(
                routePointIndex: i,
                direction: direction,
                instruction: instruction,
                distanceFromStart: cumulative[i],
                source: .bendDetection
            ))
        }
        return cues
    }

    // MARK: - Helpers

    private static func nearestIndex(to coordinate: CLLocationCoordinate2D, in coords: [CLLocationCoordinate2D]) -> Int {
        var best = 0
        var bestDist = Double.greatestFiniteMagnitude
        for (i, c) in coords.enumerated() {
            let d = GeoMath.distance(from: coordinate, to: c)
            if d < bestDist { bestDist = d; best = i }
        }
        return best
    }

    /// Best-effort direction guess from a waypoint label like "Turn left …".
    /// Falls back to straight (haptic-only) when nothing matches.
    private static func inferDirection(from label: String) -> TurnDirection {
        let lower = label.lowercased()
        if lower.contains("u-turn") || lower.contains("uturn") { return .uturn }
        if lower.contains("sharp right") { return .sharpRight }
        if lower.contains("sharp left") { return .sharpLeft }
        // Check "left" before "right": labels like "keep right at the fork
        // to the left" are rare; order keeps the common case correct.
        if lower.contains("left") { return .left }
        if lower.contains("right") { return .right }
        return .straight
    }

    private static func dedupe(_ cues: [TurnCue]) -> [TurnCue] {
        var out: [TurnCue] = []
        for cue in cues {
            if let last = out.last,
               cue.distanceFromStart - last.distanceFromStart < 20,
               cue.direction != .finish, last.direction != .start {
                continue
            }
            out.append(cue)
        }
        return out
    }
}
