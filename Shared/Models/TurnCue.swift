import Foundation

/// Direction of a turn cue.
public enum TurnDirection: String, Codable, Equatable {
    case start
    case left
    case right
    case sharpLeft
    case sharpRight
    case uturn
    case straight
    case finish

    /// Short spoken verb for the direction, e.g. "Turn right".
    public var spokenVerb: String {
        switch self {
        case .start: return "Start"
        case .left: return "Turn left"
        case .right: return "Turn right"
        case .sharpLeft: return "Sharp left"
        case .sharpRight: return "Sharp right"
        case .uturn: return "Make a U-turn"
        case .straight: return "Continue straight"
        case .finish: return "You have arrived"
        }
    }

    /// Whether this cue deserves a spoken prompt (vs. haptic only).
    public var isSpoken: Bool {
        switch self {
        case .straight: return false
        default: return true
        }
    }
}

/// Where a cue came from.
public enum CueSource: String, Codable, Equatable {
    /// From named <rtept> elements in the GPX file.
    case gpxWaypoint
    /// From bend detection on the track geometry.
    case bendDetection
    /// Synthetic (start/finish).
    case generated
}

/// A single turn cue anchored to a route point.
public struct TurnCue: Codable, Identifiable, Equatable {
    public var id: UUID
    /// Index into Route.points.
    public var routePointIndex: Int
    public var direction: TurnDirection
    /// Human-readable instruction, e.g. "Turn right onto MacLehose Trail".
    public var instruction: String
    /// Distance in meters from the route start to this cue.
    public var distanceFromStart: Double
    public var source: CueSource

    public init(
        id: UUID = UUID(),
        routePointIndex: Int,
        direction: TurnDirection,
        instruction: String,
        distanceFromStart: Double,
        source: CueSource
    ) {
        self.id = id
        self.routePointIndex = routePointIndex
        self.direction = direction
        self.instruction = instruction
        self.distanceFromStart = distanceFromStart
        self.source = source
    }

    /// Builds the spoken prompt for this cue at a given remaining distance,
    /// e.g. "Turn right in 200 meters" / "Turn right in 50 meters" / "Turn right now".
    public func spokenPrompt(remainingMeters: Double) -> String {
        let verb = direction.spokenVerb
        if direction == .start || direction == .finish {
            return instruction
        }
        if remainingMeters <= 12 {
            return "\(verb) now"
        }
        return "\(verb) in \(Int(remainingMeters.rounded())) meters"
    }
}
