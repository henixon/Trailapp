import SwiftUI
import MapKit

struct RouteDetailView: View {
    @EnvironmentObject private var store: RouteStore
    @EnvironmentObject private var watchSync: WatchSyncManager
    let route: Route

    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var sending = false

    private var cues: [TurnCue] { store.cues(for: route.id) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Map(position: $cameraPosition) {
                    MapPolyline(coordinates: route.coordinates)
                        .stroke(.trailAccent, lineWidth: 4)
                    if let first = route.coordinates.first {
                        Marker("Start", coordinate: first)
                    }
                    if let last = route.coordinates.last {
                        Marker("Finish", coordinate: last)
                    }
                    // Turn cue markers (skip synthetic start/finish).
                    ForEach(cues.filter { $0.source != .generated }) { cue in
                        if cue.routePointIndex < route.coordinates.count {
                            Marker(cue.instruction,
                                   systemImage: "arrow.turn.up.right",
                                   coordinate: route.coordinates[cue.routePointIndex])
                            .tint(.orange)
                        }
                    }
                }
                .frame(height: 280)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .onAppear {
                    let rect = routeBoundingRect
                    if rect.isNull || rect.width == 0 {
                        cameraPosition = .automatic
                    } else {
                        // Pad ~10% around the route.
                        let padded = rect.insetBy(dx: -rect.width * 0.1, dy: -rect.height * 0.1)
                        cameraPosition = .rect(padded)
                    }
                }

                statsRow

                ElevationProfileView(points: route.points)

                cueList

                sendToWatchButton
            }
            .padding()
        }
        .navigationTitle(route.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var routeBoundingRect: MKMapRect {
        route.coordinates
            .map { MKMapPoint($0) }
            .reduce(MKMapRect.null) { $0.union(MKMapRect(x: $1.x, y: $1.y, width: 0, height: 0)) }
    }

    private var statsRow: some View {
        HStack(spacing: 20) {
            StatCell(title: "Distance", value: formatDistance(route.stats.distance))
            StatCell(
                title: "Ascent",
                // Unknown is not zero — never print a false 0 m.
                value: route.hasElevationData ? "\(Int(route.stats.ascent)) m" : "—"
            )
            StatCell(title: "Est. time", value: estimatedTime)
        }
    }

    private var estimatedTime: String {
        let ascent = route.hasElevationData ? route.stats.ascent : 0
        let range = HikeEstimates.estimatedDuration(
            distanceMeters: route.stats.distance,
            ascentMeters: ascent
        )
        return HikeEstimates.formatRange(lower: range.lower, upper: range.upper)
    }

    private var cueList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Turn cues (\(cues.count))").font(.headline)
            if cues.isEmpty {
                Text("No cues generated.").foregroundStyle(.secondary)
            } else {
                ForEach(cues) { cue in
                    HStack {
                        Image(systemName: icon(for: cue.direction))
                            .foregroundStyle(.orange)
                            .frame(width: 28)
                        VStack(alignment: .leading) {
                            Text(cue.instruction).font(.subheadline)
                            Text("\(formatDistance(cue.distanceFromStart)) into route · \(cue.source == .gpxWaypoint ? "from GPX" : cue.source == .bendDetection ? "bend detection" : "auto")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private var sendToWatchButton: some View {
        VStack(spacing: 8) {
            Button {
                sending = true
                watchSync.sendToWatch(route: route, cues: cues)
                sending = false
            } label: {
                Label("Send to Watch", systemImage: "applewatch")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.trailAccent)
            .disabled(!watchSync.canSend || sending)

            if !watchSync.canSend {
                Text("Pair an Apple Watch with the TrailApp watch app installed to sync routes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if watchSync.pendingTransfers > 0 {
                Text("\(watchSync.pendingTransfers) transfer(s) in progress…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let sent = watchSync.lastSentAt {
                Text("Last sent \(sent.formatted(date: .omitted, time: .shortened)).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let error = watchSync.lastError {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
    }

    private func icon(for direction: TurnDirection) -> String {
        switch direction {
        case .start: return "flag"
        case .left, .sharpLeft: return "arrow.turn.up.left"
        case .right, .sharpRight: return "arrow.turn.up.right"
        case .uturn: return "arrow.uturn.left"
        case .straight: return "arrow.up"
        case .finish: return "flag.checkered"
        }
    }

    private func formatDistance(_ meters: Double) -> String {
        meters >= 1000 ? String(format: "%.1f km", meters / 1000) : "\(Int(meters)) m"
    }
}

private struct StatCell: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading) {
            Text(value).font(.headline)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
    }
}
