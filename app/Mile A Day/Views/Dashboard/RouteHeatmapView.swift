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
    /// False = focus the densest cluster of routes (the default — one
    /// out-of-town run must not zoom the map out to state level); true = fit
    /// every stored route.
    @State private var showAllRoutes = false
    /// Set after load: the fit-all region differs from the cluster region, so
    /// the Nearby/All toggle is worth showing.
    @State private var hasRemoteRoutes = false
    @State private var clusterRegion: MKCoordinateRegion?
    @State private var allRegion: MKCoordinateRegion?

    /// A decoded, drawable polyline with its pre-resolved accent.
    private struct DrawableRoute: Identifiable {
        let id: String
        let color: Color
        let coords: [CLLocationCoordinate2D]
    }

    /// Routes that actually have a drawable polyline, in the feed's color
    /// language (running red, walking orange, hiking green, cycling blue) so
    /// the heatmap speaks the same colors as everywhere else in the app.
    private var drawableRoutes: [DrawableRoute] {
        routes.compactMap { entry in
            guard let coords = entry.coordinates else { return nil }
            return DrawableRoute(
                id: entry.workout_id,
                color: ActivityCardView.color(entry.workout_type),
                coords: coords
            )
        }
    }

    /// Workout types present, for the legend (in a stable order).
    private var presentTypes: [String] {
        let all = ["running", "walking", "hiking", "cycling"]
        let present = Set(routes.map(\.workout_type))
        return all.filter { present.contains($0) }
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
            // Two strokes per route: a wide translucent halo that stacks up
            // where paths repeat (the heat), and a solid core line so even a
            // single, short route reads clearly at any zoom.
            ForEach(drawableRoutes) { route in
                MapPolyline(coordinates: route.coords)
                    .stroke(
                        route.color.opacity(0.28),
                        style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round)
                    )
            }
            ForEach(drawableRoutes) { route in
                MapPolyline(coordinates: route.coords)
                    .stroke(
                        route.color.opacity(0.85),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
                    )
            }
        }
        // Muted emphasis desaturates the base map so the routes own the color.
        .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
        .ignoresSafeArea(edges: .bottom)
        .overlay(alignment: .top) { statsPill }
        .overlay(alignment: .bottom) {
            if hasRemoteRoutes {
                scopeToggle
            }
        }
    }

    private var statsPill: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "map.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(MADTheme.Colors.madRed)
                Text("\(drawableRoutes.count) \(drawableRoutes.count == 1 ? "route" : "routes")")
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                    .monospacedDigit()
            }
            if presentTypes.count > 1 {
                ForEach(presentTypes, id: \.self) { type in
                    HStack(spacing: 4) {
                        Circle()
                            .fill(ActivityCardView.color(type))
                            .frame(width: 7, height: 7)
                        Text(ActivityCardView.verb(type))
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(.white.opacity(0.8))
                    }
                }
            }
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

    /// Nearby ↔ All toggle — only offered when some routes live outside the
    /// home cluster (trips, races), so the default view stays zoomed in where
    /// the running actually happens.
    private var scopeToggle: some View {
        HStack(spacing: 0) {
            scopeButton("Nearby", isOn: !showAllRoutes) {
                guard showAllRoutes else { return }
                showAllRoutes = false
                if let clusterRegion {
                    withAnimation { cameraPosition = .region(clusterRegion) }
                }
            }
            scopeButton("All Routes", isOn: showAllRoutes) {
                guard !showAllRoutes else { return }
                showAllRoutes = true
                if let allRegion {
                    withAnimation { cameraPosition = .region(allRegion) }
                }
            }
        }
        .padding(3)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.65))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.15), lineWidth: 1))
        )
        .padding(.bottom, MADTheme.Spacing.lg)
    }

    private func scopeButton(_ title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundColor(isOn ? .white : .white.opacity(0.55))
                .padding(.horizontal, 16)
                .padding(.vertical, 7)
                .background(
                    Capsule().fill(isOn ? MADTheme.Colors.madRed : Color.clear)
                )
        }
        .buttonStyle(.plain)
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

            let polylines = fetched.compactMap { $0.coordinates }
            allRegion = Self.boundingRegion(for: polylines.flatMap { $0 })
            clusterRegion = Self.densestClusterRegion(for: polylines) ?? allRegion
            hasRemoteRoutes = Self.regionsDiffer(clusterRegion, allRegion)
            if let region = clusterRegion ?? allRegion {
                cameraPosition = .region(region)
            }
        } catch {
            print("[RouteHeatmapView] loadRoutes failed: \(error)")
            loadFailed = true
        }
        isLoading = false
    }

    /// The region around where the user actually runs: routes are grouped by
    /// midpoint into ~50 km cells, the densest cell wins, and the camera fits
    /// only the routes within ~40 km of that cluster's center. Without this,
    /// a single vacation run zooms the whole map out until every route is an
    /// invisible speck.
    static func densestClusterRegion(for polylines: [[CLLocationCoordinate2D]]) -> MKCoordinateRegion? {
        let midpoints = polylines.compactMap { coords -> CLLocationCoordinate2D? in
            coords.isEmpty ? nil : coords[coords.count / 2]
        }
        guard !midpoints.isEmpty else { return nil }

        var cells: [String: [Int]] = [:]
        for (index, mid) in midpoints.enumerated() {
            let key = "\(Int((mid.latitude / 0.5).rounded())):\(Int((mid.longitude / 0.5).rounded()))"
            cells[key, default: []].append(index)
        }
        guard let densest = cells.values.max(by: { $0.count < $1.count }) else { return nil }

        let centerLat = densest.map { midpoints[$0].latitude }.reduce(0, +) / Double(densest.count)
        let centerLon = densest.map { midpoints[$0].longitude }.reduce(0, +) / Double(densest.count)
        let center = CLLocation(latitude: centerLat, longitude: centerLon)

        let nearbyPoints = polylines.enumerated()
            .filter { index, _ in
                let mid = midpoints.indices.contains(index) ? midpoints[index] : nil
                guard let mid else { return false }
                return CLLocation(latitude: mid.latitude, longitude: mid.longitude)
                    .distance(from: center) < 40_000
            }
            .flatMap { $0.element }
        return boundingRegion(for: nearbyPoints)
    }

    /// Whether the fit-all region is meaningfully wider than the cluster —
    /// drives showing the Nearby/All toggle.
    static func regionsDiffer(_ a: MKCoordinateRegion?, _ b: MKCoordinateRegion?) -> Bool {
        guard let a, let b else { return false }
        return b.span.latitudeDelta > a.span.latitudeDelta * 1.5
            || b.span.longitudeDelta > a.span.longitudeDelta * 1.5
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
