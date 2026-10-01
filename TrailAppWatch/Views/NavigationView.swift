import SwiftUI
import MapKit

/// The in-hike screen: route map with the key stats overlaid, next-turn
/// banner, and workout controls. Everything on this screen works offline —
/// GPS, cues, voice, haptics, and heart rate are all on-device.
///
/// Map backdrop note: MapKit renders Apple Maps tiles, which need network or
/// tile cache. The navigation itself (position, cues, prompts) is fully
/// offline; a custom offline tile renderer backed by the corridor PMTiles
/// pack (see Tools/build-corridor-pack.sh) is the planned upgrade — see
/// BUILD_NOTES.md.
struct NavigationView: View {
    @StateObject private var viewModel: NavigationViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showEndConfirm = false

    init(package: RoutePackage) {
        _viewModel = StateObject(wrappedValue: NavigationViewModel(package: package))
    }

    var body: some View {
        ZStack(alignment: .top) {
            Map(position: $viewModel.cameraPosition) {
                MapPolyline(coordinates: viewModel.routeCoordinates)
                    .stroke(.blue, lineWidth: 4)
                UserAnnotation()
                if let cue = viewModel.engine.nextCue,
                   let coord = viewModel.cueCoordinate(cue) {
                    Marker("", systemImage: "arrow.turn.up.right", coordinate: coord)
                        .tint(.orange)
                }
            }

            VStack(spacing: 6) {
                statsOverlay
                if viewModel.engine.state == .offRoute {
                    offRouteBanner
                } else if let cue = viewModel.engine.nextCue,
                          let remaining = viewModel.engine.nextCueRemaining {
                    nextCueBanner(cue: cue, remaining: remaining)
                }
                Spacer()
                controls
            }
            .padding(8)
        }
        .navigationBarBackButtonHidden(true)
        .task {
            await viewModel.start()
        }
        .alert("Couldn't start navigation", isPresented: .constant(viewModel.startError != nil)) {
            Button("Back") {
                viewModel.startError = nil
                dismiss()
            }
        } message: {
            Text(viewModel.startError ?? "")
        }
        .confirmationDialog("End hike?", isPresented: $showEndConfirm, titleVisibility: .visible) {
            Button("End hike", role: .destructive) {
                Task {
                    await viewModel.end()
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Overlays

    /// Heart rate, distance, and elapsed time over the map — the Komoot gap
    /// this app closes. Glanceable at arm's length on the small screen.
    private var statsOverlay: some View {
        HStack(spacing: 10) {
            StatPill(
                systemImage: "heart.fill",
                value: viewModel.workout.heartRateBPM.map { "\(Int($0))" } ?? "--",
                unit: "bpm",
                tint: .red
            )
            StatPill(
                systemImage: "point.topleft.down.to.point.bottomright.curvepath",
                value: NavigationViewModel.formatDistance(viewModel.engine.distanceTraveled),
                unit: "",
                tint: .blue
            )
            StatPill(
                systemImage: "timer",
                value: NavigationViewModel.formatElapsed(viewModel.workout.elapsed),
                unit: "",
                tint: .green
            )
        }
        .padding(6)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func nextCueBanner(cue: TurnCue, remaining: Double) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.turn.up.right")
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(cue.instruction)
                    .font(.headline)
                    .lineLimit(1)
                Text("in \(NavigationViewModel.formatDistance(remaining))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                viewModel.voice.isEnabled.toggle()
            } label: {
                Image(systemName: viewModel.voice.isEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
            }
            .buttonStyle(.plain)
        }
        .padding(8)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var offRouteBanner: some View {
        HStack(spacing: 8) {
            // Arrow rotated toward the route, relative to GPS course.
            // Without a magnetometer heading this needs motion to be accurate.
            Image(systemName: "arrow.up")
                .font(.title3)
                .rotationEffect(.degrees(relativeBearing))
            VStack(alignment: .leading, spacing: 2) {
                Text("Off route")
                    .font(.headline)
                    .foregroundStyle(.red)
                Text("Follow the arrow back to the trail")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(8)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var relativeBearing: Double {
        guard let target = viewModel.engine.bearingToRoute else { return 0 }
        let course = viewModel.engine.currentCourse ?? 0
        var delta = target - course
        while delta > 180 { delta -= 360 }
        while delta <= -180 { delta += 360 }
        return delta
    }

    private var controls: some View {
        HStack(spacing: 12) {
            if viewModel.workout.isActive {
                Button {
                    Task { await viewModel.pause() }
                } label: {
                    Image(systemName: "pause.fill")
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.bordered)
                .tint(.yellow)
            } else {
                Button {
                    Task { await viewModel.resume() }
                } label: {
                    Image(systemName: "play.fill")
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.bordered)
                .tint(.green)
            }
            Button {
                showEndConfirm = true
            } label: {
                Image(systemName: "stop.fill")
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.bordered)
            .tint(.red)
        }
        .padding(6)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

private struct StatPill: View {
    let systemImage: String
    let value: String
    let unit: String
    let tint: Color

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 3) {
                Image(systemName: systemImage)
                    .font(.caption2)
                    .foregroundStyle(tint)
                Text(value)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            if !unit.isEmpty {
                Text(unit)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }
}
