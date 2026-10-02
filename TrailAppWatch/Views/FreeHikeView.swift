import SwiftUI
import MapKit

/// Free recording screen: map with the recorded breadcrumb, live stats,
/// pause/resume/stop. No route, no cues — v1 scope.
struct FreeHikeView: View {
    @StateObject private var viewModel = FreeHikeViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var showEndConfirm = false
    @State private var isLocked = false

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

            if isLocked {
                lockOverlay
            }
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
            Button {
                isLocked = true
            } label: {
                Image(systemName: "lock.fill")
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.bordered)
            .tint(.blue)
        }
        .padding(6)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    /// Full-screen touch shield. A stray tap does nothing; a deliberate
    /// 1-second hold unlocks.
    private var lockOverlay: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
            VStack(spacing: 8) {
                Image(systemName: "lock.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.white)
                Text("Screen locked")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text("Hold to unlock")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .onLongPressGesture(minimumDuration: 1.0) {
            isLocked = false
            HapticAnnouncer.backOnRoute()
        }
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
