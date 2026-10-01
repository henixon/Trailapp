import Foundation

/// Tunable navigation behavior. Bands are distances *before* a cue at which
/// prompts fire. Defaults are scaled for hiking speeds (~3–6 km/h): at 5 km/h
/// a 200 m warning lands ~2.5 minutes before the turn, 50 m ~35 seconds.
///
/// Driving-tuned bands do NOT transfer to hiking — they fire far too late at
/// walking pace. Adjust these per user testing on real trails.
public struct PromptPolicy: Codable, Equatable {
    /// First spoken warning, e.g. "Turn right in 200 meters".
    public var longRangeMeters: Double = 200
    /// Second spoken warning, e.g. "Turn right in 50 meters".
    public var shortRangeMeters: Double = 50
    /// Final prompt + directional haptic, e.g. "Turn right now".
    public var imminentRangeMeters: Double = 15

    /// Cross-track deviation that counts as off-route.
    /// NOTE: road-tuned 30–50 m tolerances are loose on trails where
    /// switchbacks and parallel paths sit 10–20 m apart. 40 m with
    /// consecutive-fix confirmation is the starting compromise; tighten
    /// per trail testing.
    public var offRouteMeters: Double = 40
    /// Consecutive off-route fixes before declaring off-route.
    public var offRouteFixes: Int = 3
    /// Cross-track distance that counts as rejoined.
    public var rejoinMeters: Double = 25
    /// Ignore GPS fixes worse than this accuracy.
    public var minFixAccuracyMeters: Double = 100
    /// Arrival radius at the final cue.
    public var arrivalMeters: Double = 15

    public init(
        longRangeMeters: Double = 200,
        shortRangeMeters: Double = 50,
        imminentRangeMeters: Double = 15,
        offRouteMeters: Double = 40,
        offRouteFixes: Int = 3,
        rejoinMeters: Double = 25,
        minFixAccuracyMeters: Double = 100,
        arrivalMeters: Double = 15
    ) {
        self.longRangeMeters = longRangeMeters
        self.shortRangeMeters = shortRangeMeters
        self.imminentRangeMeters = imminentRangeMeters
        self.offRouteMeters = offRouteMeters
        self.offRouteFixes = offRouteFixes
        self.rejoinMeters = rejoinMeters
        self.minFixAccuracyMeters = minFixAccuracyMeters
        self.arrivalMeters = arrivalMeters
    }

    public static let hiking = PromptPolicy()
}
