import Foundation
import HealthKit
import CoreLocation

/// Owns the HKWorkoutSession lifecycle on the watch and streams live data:
/// GPS locations, heart rate, and elapsed active time.
///
/// Background execution: the workout session (with the `workout-processing`
/// background mode) plus a CLBackgroundActivitySession keeps location
/// delivery alive with the wrist down. There is NO geofencing on watchOS —
/// turn proximity is computed by polling locations in `locationStream`,
/// which the NavigationEngine consumes.
@MainActor
final class WorkoutManager: ObservableObject {
    @Published private(set) var state: WorkoutState = .idle
    @Published private(set) var heartRateBPM: Double?
    @Published private(set) var elapsed: TimeInterval = 0

    enum WorkoutState { case idle, active, paused }

    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var backgroundSession: CLBackgroundActivitySession?
    private var heartRateQuery: HKAnchoredObjectQuery?
    private var heartRateAnchor: HKQueryAnchor?
    private var locationTask: Task<Void, Never>?
    private var locationContinuation: AsyncStream<CLLocation>.Continuation?
    private var elapsedTimer: Timer?
    private var segmentStart: Date?
    private var accumulatedActive: TimeInterval = 0

    /// Hot stream of GPS fixes. Created on `start()`, finished on `end()`.
    private(set) var locationStream: AsyncStream<CLLocation>?

    var isActive: Bool { state == .active }

    // MARK: - Authorization

    func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let share: Set<HKSampleType> = [HKObjectType.workoutType()]
        let read: Set<HKObjectType> = [
            HKObjectType.quantityType(forIdentifier: .heartRate)!,
            HKObjectType.workoutType(),
        ]
        try await healthStore.requestAuthorization(toShare: share, read: read)
    }

    // MARK: - Lifecycle

    /// Starts the workout session, location streaming, HR query, and timer.
    /// NOTE (verify on device/Xcode 16): HKWorkoutSession async start/pause/
    /// resume/stop API availability on the watchOS 10 SDK.
    func start() async throws {
        try await requestAuthorization()

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .hiking
        configuration.locationType = .outdoor

        let session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
        self.session = session

        // Keeps CoreLocation delivery alive in the background.
        backgroundSession = try CLBackgroundActivitySession()

        startHeartRateQuery(from: Date())
        startElapsedClock()
        startLocationStream()

        try await session.start()
        state = .active
    }

    func pause() async {
        guard state == .active else { return }
        await session?.pause()
        pauseElapsedClock()
        state = .paused
    }

    func resume() async {
        guard state == .paused else { return }
        await session?.resume()
        resumeElapsedClock()
        state = .active
    }

    func end() async {
        await session?.stop()
        locationTask?.cancel()
        locationTask = nil
        locationContinuation?.finish()
        locationContinuation = nil
        locationStream = nil
        if let query = heartRateQuery {
            healthStore.stop(query)
            heartRateQuery = nil
        }
        elapsedTimer?.invalidate()
        elapsedTimer = nil
        backgroundSession?.invalidate()
        backgroundSession = nil
        session = nil
        state = .idle
    }

    // MARK: - Location

    private func startLocationStream() {
        let (stream, continuation) = AsyncStream<CLLocation>.makeStream()
        locationStream = stream
        locationContinuation = continuation
        locationTask = Task { [weak self] in
            // `.fitness` tunes accuracy/power for workout use.
            // NOTE (verify on Xcode 16): exact liveUpdates signature on watchOS 10 SDK.
            for await update in CLLocationUpdate.liveUpdates(.fitness) {
                guard let location = update.location else { continue }
                self?.locationContinuation?.yield(location)
            }
        }
    }

    // MARK: - Heart rate

    private func startHeartRateQuery(from start: Date) {
        guard let type = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return }
        let predicate = HKQuery.predicateForSamples(
            withStart: start, end: nil, options: .strictStartDate)

        let query = HKAnchoredObjectQuery(
            type: type,
            predicate: predicate,
            anchor: heartRateAnchor,
            limit: HKObjectQueryNoLimit
        ) { [weak self] _, samples, _, newAnchor, _ in
            self?.heartRateAnchor = newAnchor
            self?.ingest(samples: samples)
        }
        query.updateHandler = { [weak self] _, samples, _, newAnchor, _ in
            self?.heartRateAnchor = newAnchor
            self?.ingest(samples: samples)
        }
        heartRateQuery = query
        healthStore.execute(query)
    }

    private func ingest(samples: [HKSample]?) {
        guard let sample = (samples as? [HKQuantitySample])?.last else { return }
        let bpm = sample.quantity.doubleValue(
            for: HKUnit.count().unitDivided(by: .minute()))
        Task { @MainActor in self.heartRateBPM = bpm }
    }

    // MARK: - Elapsed time (excludes paused periods)

    private func startElapsedClock() {
        accumulatedActive = 0
        segmentStart = Date()
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func pauseElapsedClock() {
        if let start = segmentStart {
            accumulatedActive += Date().timeIntervalSince(start)
        }
        segmentStart = nil
        tick()
    }

    private func resumeElapsedClock() {
        segmentStart = Date()
    }

    private func tick() {
        var total = accumulatedActive
        if let start = segmentStart { total += Date().timeIntervalSince(start) }
        elapsed = total
    }
}
