import SwiftUI

/// Watch home: routes synced from the iPhone. Tapping one opens navigation.
struct ContentView: View {
    @EnvironmentObject private var sessionManager: WatchSessionManager
    @State private var showFreeHike = false

    var body: some View {
        NavigationStack {
            Group {
                if sessionManager.packages.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "map")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("No routes yet")
                            .font(.headline)
                        Text("Import a GPX on your iPhone and tap Send to Watch.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        freeHikeButton
                    }
                    .padding()
                } else {
                    List {
                        Section {
                            freeHikeButton
                        }
                        ForEach(sessionManager.packages) { package in
                            NavigationLink(value: package.id) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(package.route.name)
                                        .font(.headline)
                                        .lineLimit(2)
                                    Text("\(NavigationViewModel.formatDistance(package.route.stats.distance)) · \(package.cues.count) cues")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .onDelete { indexSet in
                            for index in indexSet {
                                sessionManager.delete(sessionManager.packages[index])
                            }
                        }
                    }
                }
            }
            .navigationTitle("TrailApp")
            .navigationDestination(for: UUID.self) { id in
                if let package = sessionManager.package(id: id) {
                    NavigationView(package: package)
                }
            }
            .navigationDestination(isPresented: $showFreeHike) {
                FreeHikeView()
            }
            .alert("Sync issue", isPresented: .constant(sessionManager.lastError != nil)) {
                Button("OK") { sessionManager.lastError = nil }
            } message: {
                Text(sessionManager.lastError ?? "")
            }
        }
    }

    private var freeHikeButton: some View {
        Button {
            showFreeHike = true
        } label: {
            Label("Start Free Hike", systemImage: "figure.hiking")
                .font(.headline)
        }
        .buttonStyle(.borderedProminent)
        .tint(.green)
    }
}
