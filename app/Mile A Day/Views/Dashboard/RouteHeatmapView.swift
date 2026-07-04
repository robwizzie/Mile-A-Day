import SwiftUI
import MapKit
import CoreLocation

// MARK: - Model

/// One stored GPS trace from `GET /workouts/{userId}/routes`. Snake_case to
/// decode the backend JSON directly, matching PostItem/FeedEntry.
private struct WorkoutRouteEntry: Decodable, Identifiable {
    let workout_id: String
    let local_date: String
    let workout_type: String
    /// [[lat, lng], ...]
    let route: [[Double]]

    var id: String { workout_id }

    /// Decoded polyline (nil when degenerate) — same rule as the feed models.
    var coordinates: [CLLocationCoordinate2D]? { decodeRouteCoordinates(route) }
}

// MARK: - View

/// Full-screen personal heatmap: every stored route overlaid on one map, low
/// opacity so repeated paths build up brighter. Presented as a sheet from the
/// profile's Stats tab.
struct RouteHeatmapView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var routes: [WorkoutRouteEntry] = []
    @State private var isLoading = true
    @State private var loadFailed = false
    @State private var cameraPosition: MapCameraPosition = .automatic

    /// A decoded, drawable polyline with its pre-resolved stroke color.
    private struct DrawableRoute: Identifiable {
        let id: String
        let color: Color
        let coords: [CLLocationCoordinate2D]
    }

    /// Routes that actually have a drawable polyline. Running builds up red;
    /// walking builds up blue — low opacity so overlaps glow brighter (the
    /// heatmap effect).
    private var drawableRoutes: [DrawableRoute] {
        routes.compactMap { entry in
            guard let coords = entry.coordinates else { return nil }
            let base: Color = entry.workout_type == "walking" ? .blue : MADTheme.Colors.madRed
            return DrawableRoute(id: entry.workout_id, color: base.opacity(0.35), coords: coords)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                if isLoading {
                    MADTheme.Colors.appBackgroundGradient.ignoresSafeArea()
                    VStack(spacing: MADTheme.Spacing.md) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: MADTheme.Colors.madRed))
                        Text("Loading your routes…")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.5))
                    }
                } else if drawableRoutes.isEmpty {
                    MADTheme.Colors.appBackgroundGradient.ignoresSafeArea()
                    emptyState
                } else {
                    heatmap
                }
            }
            .navigationTitle("Route Heatmap")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundColor(MADTheme.Colors.madRed)
                        .fontWeight(.semibold)
                }
            }
            .preferredColorScheme(.dark)
            .task { await loadRoutes() }
        }
    }

    // MARK: - Map

    private var heatmap: some View {
        Map(position: $cameraPosition, interactionModes: .all) {
            ForEach(drawableRoutes) { route in
                MapPolyline(coordinates: route.coords)
                    .stroke(
                        route.color,
                        style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
                    )
            }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
        .ignoresSafeArea(edges: .bottom)
        .overlay(alignment: .top) { statsPill }
    }

    private var statsPill: some View {
        HStack(spacing: 6) {
            Image(systemName: "map.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(MADTheme.Colors.madRed)
            Text("\(drawableRoutes.count) \(drawableRoutes.count == 1 ? "route" : "routes")")
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
                .monospacedDigit()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.65))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.15), lineWidth: 1))
        )
        .padding(.top, MADTheme.Spacing.sm)
    }

    // MARK: - Empty / error state

    private var emptyState: some View {
        VStack(spacing: MADTheme.Spacing.md) {
            Image(systemName: "map")
                .font(.system(size: 44, weight: .semibold))
                .foregroundColor(.white.opacity(0.25))
            Text(loadFailed ? "Couldn't load your routes" : "No routes yet")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            Text(loadFailed
                 ? "Check your connection and try again."
                 : "No routes yet — outdoor walks and runs will paint this map.")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.5))
                .multilineTextAlignment(.center)
                .padding(.horizontal, MADTheme.Spacing.xl)
        }
    }

    // MARK: - Data

    private func loadRoutes() async {
        guard isLoading else { return }
        guard let userId = UserDefaults.standard.string(forKey: "backendUserId") else {
            isLoading = false
            loadFailed = true
            return
        }
        do {
            let fetched = try await APIClient.fancyFetch(
                endpoint: "/workouts/\(userId)/routes",
                responseType: [WorkoutRouteEntry].self
            )
            routes = fetched
            if let region = Self.boundingRegion(for: fetched.compactMap { $0.coordinates }.flatMap { $0 }) {
                cameraPosition = .region(region)
            }
        } catch {
            print("[RouteHeatmapView] loadRoutes failed: \(error)")
            loadFailed = true
        }
        isLoading = false
    }

    /// Region fitting every point, with padding and a sane minimum span.
    /// Nil when there are no points (leaves the camera on .automatic).
    static func boundingRegion(for coordinates: [CLLocationCoordinate2D]) -> MKCoordinateRegion? {
        guard let first = coordinates.first else { return nil }
        var minLat = first.latitude, maxLat = first.latitude
        var minLon = first.longitude, maxLon = first.longitude
        for coord in coordinates {
            minLat = min(minLat, coord.latitude)
            maxLat = max(maxLat, coord.latitude)
            minLon = min(minLon, coord.longitude)
            maxLon = max(maxLon, coord.longitude)
        }
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLat - minLat) * 1.3, 0.005),
            longitudeDelta: max((maxLon - minLon) * 1.3, 0.005)
        )
        return MKCoordinateRegion(center: center, span: span)
    }
}

#Preview {
    RouteHeatmapView()
}
