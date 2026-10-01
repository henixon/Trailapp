import Foundation
import CoreLocation

/// On-watch navigation engine: snap-to-route, along-track progress, cue
/// triggering, and off-route detection. Pure logic — no HealthKit, no UI —
/// driven by GPS fixes from WorkoutManager.
///
/// For each fix:
/// 1. Project onto the route polyline (nearest point).
/// 2. If cross-track distance exceeds the policy for N consecutive reliable
///    fixes → off-route. While off-route, publish the bearing back to the
///    nearest route point (no U-turn demanded; the hiker rejoins anywhere).
/// 3. Otherwise advance along-track progress and fire cue prompts as the
///    remaining distance crosses each band (long → short → imminent).
/// 4. Rerouting on trails = rejoin connector to the nearest not-yet-traversed
///    point. Full re-planning needs a routing graph that doesn't fit on the
///    watch in v1, so the engine degrades gracefully to bearing-and-distance.
@MainActor
public final class NavigationEngine: ObservableObject {
    public enum State: Equatable {
        case idle
        case navigating
        case paused
        case offRoute
        case finished
    }

    // MARK: - Published state (drives the watch UI)

    @Published public private(set) var state: State = .idle
    @Published public private(set) var nextCue: TurnCue?
    @Published public private(set) var nextCueRemaining: Double?
    @Published public private(set) var distanceTraveled: Double = 0
    @Published public private(set) var distanceRemaining: Double = 0
    /// Bearing (degrees, 0 = north) from the user to the nearest route point.
    /// Non-nil only while off-route; the UI pairs it with GPS course.
    @Published public private(set) var bearingToRoute: Double?
    /// GPS course (direction of travel), when available.
    @Published public private(set) var currentCourse: Double?

    // MARK: - Event callbacks (wired by NavigationViewModel)

    /// Speak a prompt. Bool = interrupt current speech (safety events).
    public var onSpeak: ((String, Bool) -> Void)?
    public var onHapticTurn: ((TurnDirection) -> Void)?
    public var onUpcomingManeuver: (() -> Void)?
    public var onOffRoute: (() -> Void)?
    public var onBackOnRoute: (() -> Void)?
    public var onArrived: (() -> Void)?

    // MARK: - Private

    private var coords: [CLLocationCoordinate2D] = []
    private var cumulative: [Double] = []
    private var totalDistance: Double = 0
    private var cues: [TurnCue] = []
    private var policy: PromptPolicy = .hiking
    /// Bands already announced per cue id: 0 = long, 1 = short, 2 = imminent.
    private var announcedBands: [UUID: Set<Int>] = [:]
    private var offRouteStreak = 0
    private var lastLocation: CLLocation?

    // MARK: - Control

    public func start(package: RoutePackage) {
        let route = package.route
        coords = route.coordinates
        cumulative = route.cumulativeDistances
        totalDistance = route.stats.distance
        cues = package.cues
        policy = package.promptPolicy
        announcedBands = [:]
        offRouteStreak = 0
        lastLocation = nil
        distanceTraveled = 0
        distanceRemaining = totalDistance
        bearingToRoute = nil
        state = .navigating
        onSpeak?("Navigation started. \(Int(totalDistance / 1000)) kilometers, \(cues.count) turns.", false)
    }

    public func pause() {
        guard state == .navigating || state == .offRoute else { return }
        state = .paused
    }

    public func resume() {
        guard state == .paused else { return }
        state = .navigating
        offRouteStreak = 0
    }

    public func stop() {
        state = .idle
        nextCue = nil
        nextCueRemaining = nil
        bearingToRoute = nil
    }

    // MARK: - Per-fix processing

    public func process(location: CLLocation) {
        guard state == .navigating || state == .offRoute else { return }
        guard location.horizontalAccuracy >= 0,
              location.horizontalAccuracy <= policy.minFixAccuracyMeters else { return }
        guard let nearest = GeoMath.nearestPoint(
            on: coords, cumulative: cumulative, to: location.coordinate) else { return }

        // Distance accumulation (sanity-capped against GPS jumps).
        if let last = lastLocation {
            let delta = location.distance(from: last)
            if location.horizontalAccuracy <= 65, delta < 200 {
                distanceTraveled += delta
            }
        }
        lastLocation = location
        if location.course >= 0 { currentCourse = location.course }

        // --- Off-route handling ---
        if state == .offRoute {
            if nearest.crossTrackDistance <= policy.rejoinMeters {
                state = .navigating
                offRouteStreak = 0
                bearingToRoute = nil
                onBackOnRoute?()
                onSpeak?("Back on route.", true)
            } else {
                bearingToRoute = GeoMath.bearing(from: location.coordinate, to: nearest.point)
                distanceRemaining = max(0, totalDistance - nearest.alongTrackDistance)
            }
            return
        }

        if nearest.crossTrackDistance > policy.offRouteMeters {
            offRouteStreak += 1
            if offRouteStreak >= policy.offRouteFixes {
                state = .offRoute
                bearingToRoute = GeoMath.bearing(from: location.coordinate, to: nearest.point)
                onOffRoute?()
                onSpeak?("Off route. Follow the arrow back to the trail.", true)
            }
            return
        }
        offRouteStreak = 0

        // --- Along-track progress ---
        let along = nearest.alongTrackDistance
        distanceRemaining = max(0, totalDistance - along)

        // Arrival check.
        if totalDistance - along <= policy.arrivalMeters {
            state = .finished
            nextCue = nil
            nextCueRemaining = nil
            onArrived?()
            onSpeak?("You have arrived.", true)
            return
        }

        // --- Next cue ---
        // The next actionable cue strictly ahead of us.
        let upcoming = cues
            .filter { $0.direction != .start && $0.distanceFromStart > along + 5 }
            .sorted { $0.distanceFromStart < $1.distanceFromStart }
            .first
        nextCue = upcoming
        if let cue = upcoming {
            let remaining = cue.distanceFromStart - along
            nextCueRemaining = remaining
            fireBands(for: cue, remaining: remaining)
        } else {
            nextCueRemaining = nil
        }
    }

    // MARK: - Cue bands

    private func fireBands(for cue: TurnCue, remaining: Double) {
        var announced = announcedBands[cue.id] ?? []
        let bands: [(index: Int, threshold: Double)] = [
            (0, policy.longRangeMeters),
            (1, policy.shortRangeMeters),
            (2, policy.imminentRangeMeters),
        ]
        for (index, threshold) in bands where remaining <= threshold && !announced.contains(index) {
            announced.insert(index)
            if cue.direction.isSpoken {
                onSpeak?(cue.spokenPrompt(remainingMeters: remaining), false)
            }
            if index == 2 {
                onHapticTurn?(cue.direction)
            } else {
                onUpcomingManeuver?()
            }
        }
        announcedBands[cue.id] = announced
    }
}
