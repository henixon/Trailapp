import Foundation
import SwiftUI
import MapKit
import Combine
import CoreLocation

/// Free recording mode: workout + GPS breadcrumb with no route attached.
/// v1 scope — no cues, no voice; just start/stop with live stats.
@MainActor
final class FreeHikeViewModel: ObservableObject {
    let workout = WorkoutManager()

    @Published var cameraPosition: MapCameraPosition = .userLocation(fallback: .automatic)
    @Published var breadcrumb: [CLLocationCoordinate2D] = []
    @Published var distanceTraveled: Double = 0
    @Published var startError: String?

    private var cancellables = Set<AnyCancellable>()
    private var locationTask: Task<Void, Never>?
    private var lastLocation: CLLocation?

    init() {
        workout.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    func start() async {
        do {
            try await workout.start()
        } catch {
            startError = "Couldn't start the workout: \(error.localizedDescription)"
            return
        }
        guard let stream = workout.locationStream else { return }
        locationTask = Task { [weak self] in
            for await location in stream {
                await self?.ingest(location)
            }
        }
    }

    private func ingest(_ location: CLLocation) {
        // Drop noisy fixes.
        guard location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 50 else { return }
        if let last = lastLocation {
            let delta = location.distance(from: last)
            // Ignore teleport jumps (tunnel exit, GPS glitch).
            guard delta < 500 else {
                lastLocation = location
                return
            }
            distanceTraveled += delta
        }
        lastLocation = location
        breadcrumb.append(location.coordinate)
    }

    func pause() async {
        await workout.pause()
    }

    func resume() async {
        await workout.resume()
    }

    func end() async {
        locationTask?.cancel()
        locationTask = nil
        await workout.end()
    }
}
