import Foundation
import SwiftUI
import MapKit
import Combine

/// Wires the watch navigation stack together:
/// WorkoutManager (GPS + HR + clock) → NavigationEngine (route logic) →
/// VoicePrompter + HapticAnnouncer (outputs). The SwiftUI views observe
/// this single object.
@MainActor
final class NavigationViewModel: ObservableObject {
    let package: RoutePackage

    let workout = WorkoutManager()
    let engine = NavigationEngine()
    let voice = VoicePrompter()

    @Published var cameraPosition: MapCameraPosition = .userLocation(fallback: .automatic)
    @Published var startError: String?

    private var cancellables = Set<AnyCancellable>()
    private var locationTask: Task<Void, Never>?

    init(package: RoutePackage) {
        self.package = package

        // Forward nested observable changes so one @ObservedObject drives the UI.
        engine.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
        workout.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
        voice.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)

        engine.onSpeak = { [weak self] text, interrupt in self?.voice.speak(text, interrupt: interrupt) }
        engine.onHapticTurn = { HapticAnnouncer.turn($0) }
        engine.onUpcomingManeuver = { HapticAnnouncer.upcomingManeuver() }
        engine.onOffRoute = { HapticAnnouncer.offRoute() }
        engine.onBackOnRoute = { HapticAnnouncer.backOnRoute() }
        engine.onArrived = { HapticAnnouncer.arrived() }
    }

    var routeCoordinates: [CLLocationCoordinate2D] {
        package.route.coordinates
    }

    func cueCoordinate(_ cue: TurnCue) -> CLLocationCoordinate2D? {
        guard cue.routePointIndex < routeCoordinates.count else { return nil }
        return routeCoordinates[cue.routePointIndex]
    }

    // MARK: - Lifecycle

    func start() async {
        do {
            try await workout.start()
        } catch {
            startError = "Couldn't start the workout: \(error.localizedDescription)"
            return
        }
        engine.start(package: package)
        guard let stream = workout.locationStream else { return }
        locationTask = Task { [weak self] in
            for await location in stream {
                await self?.engine.process(location: location)
            }
        }
    }

    func pause() async {
        engine.pause()
        await workout.pause()
    }

    func resume() async {
        await workout.resume()
        engine.resume()
    }

    func end() async {
        locationTask?.cancel()
        locationTask = nil
        voice.stop()
        engine.stop()
        await workout.end()
    }

    // MARK: - Formatting

    static func formatDistance(_ meters: Double) -> String {
        meters >= 1000
            ? String(format: "%.2f km", meters / 1000)
            : "\(Int(meters.rounded())) m"
    }

    static func formatElapsed(_ interval: TimeInterval) -> String {
        let total = Int(interval)
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
    }
}
