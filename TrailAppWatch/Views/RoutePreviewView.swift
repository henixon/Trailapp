import SwiftUI
import MapKit

/// Route preview: full-route map, key stats, and a single Start button.
/// Nothing starts recording until the user deliberately taps Start —
/// tapping a route in the list never launches navigation directly.
struct RoutePreviewView: View {
    let package: RoutePackage

    @State private var cameraPosition: MapCameraPosition
    @State private var started = false

    init(package: RoutePackage) {
        self.package = package
        _cameraPosition = State(initialValue: Self.region(for: package.route))
    }

    var body: some View {
        ZStack(alignment: .top) {
            Map(position: $cameraPosition) {
                MapPolyline(coordinates: package.route.coordinates)
                    .stroke(.blue, lineWidth: 4)
                UserAnnotation()
            }
            .disabled(true)

            VStack(spacing: 6) {
                infoCard
                Spacer()
                Button {
                    started = true
                } label: {
                    Label("Start", systemImage: "figure.hiking")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            }
            .padding(8)
        }
        .navigationTitle(package.route.name)
        .navigationDestination(isPresented: $started) {
            NavigationView(package: package)
        }
    }

    private var infoCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(package.route.name)
                .font(.headline)
                .lineLimit(2)
            HStack(spacing: 12) {
                Label(NavigationViewModel.formatDistance(package.route.stats.distance),
                      systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                Label("\(Int(package.route.stats.ascent.rounded())) m ↑",
                      systemImage: "arrow.up.right")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            Text("\(package.cues.count) turn cues")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private static func region(for route: Route) -> MapCameraPosition {
        guard let box = route.boundingBox else { return .automatic }
        let center = CLLocationCoordinate2D(
            latitude: (box.minLat + box.maxLat) / 2,
            longitude: (box.minLon + box.maxLon) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max((box.maxLat - box.minLat) * 1.3, 0.005),
            longitudeDelta: max((box.maxLon - box.minLon) * 1.3, 0.005)
        )
        return .region(MKCoordinateRegion(center: center, span: span))
    }
}
