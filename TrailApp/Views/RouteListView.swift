import SwiftUI
import UniformTypeIdentifiers

struct RouteListView: View {
    @EnvironmentObject private var store: RouteStore
    @State private var showingImporter = false

    var body: some View {
        NavigationStack {
            Group {
                if store.routes.isEmpty {
                    ContentUnavailableView(
                        "No routes yet",
                        systemImage: "map",
                        description: Text("Import a GPX file to preview it and send it to your Apple Watch.")
                    )
                } else {
                    List {
                        ForEach(store.routes) { route in
                            NavigationLink(value: route) {
                                RouteRow(route: route)
                            }
                        }
                        .onDelete { indexSet in
                            for index in indexSet { store.delete(route: store.routes[index]) }
                        }
                    }
                }
            }
            .navigationTitle("TrailApp")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingImporter = true
                    } label: {
                        Label("Import GPX", systemImage: "square.and.arrow.down")
                    }
                }
            }
            .navigationDestination(for: Route.self) { route in
                RouteDetailView(route: route)
            }
            .fileImporter(
                isPresented: $showingImporter,
                allowedContentTypes: [.gpx],
                allowsMultipleSelection: true
            ) { result in
                switch result {
                case .success(let urls):
                    for url in urls {
                        do { try store.importGPX(from: url) }
                        catch { store.lastError = error.localizedDescription }
                    }
                case .failure(let error):
                    store.lastError = error.localizedDescription
                }
            }
            .alert("Import failed", isPresented: .constant(store.lastError != nil)) {
                Button("OK") { store.lastError = nil }
            } message: {
                Text(store.lastError ?? "")
            }
        }
    }
}

private struct RouteRow: View {
    let route: Route

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(route.name).font(.headline).lineLimit(1)
            HStack(spacing: 12) {
                Label(formatDistance(route.stats.distance), systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                if route.stats.ascent > 0 {
                    Label("\(Int(route.stats.ascent)) m ↑", systemImage: "mountain.2")
                }
                Text("\(route.points.count) pts")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func formatDistance(_ meters: Double) -> String {
        meters >= 1000 ? String(format: "%.1f km", meters / 1000) : "\(Int(meters)) m"
    }
}
