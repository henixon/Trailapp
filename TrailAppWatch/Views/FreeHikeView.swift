import SwiftUI
import MapKit

/// Free recording screen: map with the recorded breadcrumb, live stats,
/// pause/resume/stop. No route, no cues — v1 scope.
struct FreeHikeView: View {
    @StateObject private var viewModel = FreeHikeViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var showEndConfirm = false

    var body: some View {
        ZStack(alignment: .top) {
            Map(position: $viewModel.cameraPosition) {
                if !viewModel.breadcrumb.isEmpty {
                    MapPolyline(coordinates: viewModel.breadcrumb)
                        .stroke(.green, lineWidth: 4)
                }
                UserAnnotation()
            }

            VStack(spacing: 6) {
                statsOverlay
                Spacer()
                controls
            }
            .padding(8)
        }
        .navigationBarBackButtonHidden(true)
        .task {
            await viewModel.start()
        }
        .alert("Couldn't start recording", isPresented: .constant(viewModel.startError != nil)) {
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
                value: NavigationViewModel.formatDistance(viewModel.distanceTraveled),
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
