import SwiftUI
import Charts

/// Elevation profile chart for a route. Only points carrying elevation are
/// plotted; routes without elevation data show an empty state instead of a
/// flat misleading line.
struct ElevationProfileView: View {
    let points: [RoutePoint]

    private struct Sample: Identifiable {
        let id = UUID()
        let distanceKm: Double
        let elevation: Double
    }

    private var samples: [Sample] {
        let coords = points.map(\.coordinate)
        let cumulative = GeoMath.cumulativeDistances(coords)
        var out: [Sample] = []
        for (i, p) in points.enumerated() {
            guard let ele = p.elevation else { continue }
            out.append(Sample(distanceKm: cumulative[i] / 1000, elevation: ele))
        }
        // Downsample very dense tracks for chart performance.
        if out.count > 600 {
            let stride = out.count / 600
            return out.enumerated().filter { $0.offset % stride == 0 }.map(\.element)
        }
        return out
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Elevation").font(.headline)
            if samples.isEmpty {
                Text("No elevation data in this GPX file.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Chart(samples) { s in
                    AreaMark(
                        x: .value("Distance", s.distanceKm),
                        y: .value("Elevation", s.elevation)
                    )
                    .foregroundStyle(.green.opacity(0.25))
                    LineMark(
                        x: .value("Distance", s.distanceKm),
                        y: .value("Elevation", s.elevation)
                    )
                    .foregroundStyle(.green)
                }
                .chartXAxisLabel("km")
                .chartYAxisLabel("m")
                .chartYScale(domain: .automatic(includesZero: false))
                .frame(height: 140)
            }
        }
    }
}
