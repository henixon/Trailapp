import WatchKit

/// Wrist haptics for navigation events.
///
/// Uses the dedicated turn haptic types — these are the same patterns Apple
/// Maps uses, so they read instantly as "turn left/right". CoreHaptics is NOT
/// available on watchOS; WKInterfaceDevice is the API.
///
/// IMPORTANT: haptics only fire while the app is in the foreground or inside
/// an active workout/extended session. NavigationViewModel starts an
/// HKWorkoutSession before navigating, which satisfies this.
public enum HapticAnnouncer {
    /// Directional turn cue. Call at the imminent band ("Turn right now").
    public static func turn(_ direction: TurnDirection) {
        let device = WKInterfaceDevice.current()
        switch direction {
        case .left, .sharpLeft:
            device.play(.navigationLeftTurn)
        case .right, .sharpRight:
            device.play(.navigationRightTurn)
        default:
            device.play(.navigationGenericManeuver)
        }
    }

    /// Soft pre-warning at the long/short bands (no direction yet).
    public static func upcomingManeuver() {
        WKInterfaceDevice.current().play(.navigationGenericManeuver)
    }

    public static func offRoute() {
        WKInterfaceDevice.current().play(.notification)
    }

    public static func backOnRoute() {
        WKInterfaceDevice.current().play(.click)
    }

    public static func arrived() {
        WKInterfaceDevice.current().play(.success)
    }
}
