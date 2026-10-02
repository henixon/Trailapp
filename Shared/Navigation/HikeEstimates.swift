import Foundation

/// Hiking time estimates (Naismith's rule). Pure logic, shared by iPhone and watch.
public enum HikeEstimates {
    /// Naismith's rule: 12 min per km + 10 min per 100 m of ascent.
    /// Returns a (lower, upper) band at ±20% — shown to the user as a range.
    public static func estimatedDuration(
        distanceMeters: Double,
        ascentMeters: Double
    ) -> (lower: TimeInterval, upper: TimeInterval) {
        guard distanceMeters > 0 else { return (0, 0) }
        let base = (distanceMeters / 1000) * 12 * 60 + (ascentMeters / 100) * 10 * 60
        return (base * 0.8, base * 1.2)
    }

    /// "45–60 min" or "6–8 h". Returns "—" when there is nothing to estimate.
    public static func formatRange(lower: TimeInterval, upper: TimeInterval) -> String {
        guard upper > 0 else { return "—" }
        if upper < 3600 {
            let lo = Int((lower / 60).rounded(.down) / 5) * 5
            let hi = Int((upper / 60).rounded(.up) / 5) * 5
            return "\(max(lo, 5))–\(hi) min"
        } else {
            let lo = Int((lower / 3600).rounded(.down))
            let hi = Int((upper / 3600).rounded(.up))
            return "\(max(lo, 1))–\(hi) h"
        }
    }
}
