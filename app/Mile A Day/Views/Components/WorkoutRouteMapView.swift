import SwiftUI
import MapKit

struct WorkoutRouteMapView: View {
    let coordinates: [CLLocationCoordinate2D]
    let routeColor: Color

    @State private var snapshotImage: UIImage?
    @State private var trimProgress: CGFloat = 0
    @State private var showMarkers = false
    @State private var hasLoaded = false

    private var region: MKCoordinateRegion {
        guard !coordinates.isEmpty else {
            return MKCoordinateRegion()
        }
        var minLat = coordinates[0].latitude
        var maxLat = coordinates[0].latitude
        var minLon = coordinates[0].longitude
        var maxLon = coordinates[0].longitude

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

        // Use a minimum span of ~55 meters (0.0005°) for tiny routes
        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLat - minLat) * 1.8, 0.0005),
            longitudeDelta: max((maxLon - minLon) * 1.8, 0.0005)
        )

        return MKCoordinateRegion(center: center, span: span)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let image = snapshotImage {
                    // Static map snapshot — no lag in scroll
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width, height: geo.size.height)

                    // Animated route overlay
                    RouteOverlay(
                        coordinates: coordinates,
                        region: region,
                        viewSize: geo.size,
                        routeColor: routeColor,
                        trimProgress: trimProgress,
                        showMarkers: showMarkers
                    )
                } else {
                    // Loading placeholder
                    RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                        .fill(Color.white.opacity(0.05))
                        .overlay(
                            ProgressView()
                                .tint(.white.opacity(0.4))
                        )
                }
            }
        }
        .task {
            guard !hasLoaded else { return }
            hasLoaded = true
            await generateSnapshot()

            // Animate route after snapshot loads
            try? await Task.sleep(for: .milliseconds(300))
            withAnimation(.easeOut(duration: 0.3)) {
                showMarkers = true
            }
            withAnimation(.easeInOut(duration: 1.2)) {
                trimProgress = 1.0
            }
        }
    }

    private func generateSnapshot() async {
        let options = MKMapSnapshotter.Options()
        options.region = region
        options.size = CGSize(width: 400, height: 300)
        options.mapType = .standard
        options.traitCollection = UITraitCollection(userInterfaceStyle: .dark)
        options.pointOfInterestFilter = .excludingAll

        let snapshotter = MKMapSnapshotter(options: options)
        do {
            let snapshot = try await snapshotter.start()
            snapshotImage = snapshot.image
        } catch {
            print("[WorkoutRouteMapView] Snapshot failed: \(error)")
        }
    }
}

// MARK: - Route Overlay (pure SwiftUI drawing — no Map view)

private struct RouteOverlay: View {
    let coordinates: [CLLocationCoordinate2D]
    let region: MKCoordinateRegion
    let viewSize: CGSize
    let routeColor: Color
    let trimProgress: CGFloat
    let showMarkers: Bool

    private func coordToPoint(_ coord: CLLocationCoordinate2D) -> CGPoint {
        let latRange = region.span.latitudeDelta
        let lonRange = region.span.longitudeDelta
        let centerLat = region.center.latitude
        let centerLon = region.center.longitude

        let x = (coord.longitude - (centerLon - lonRange / 2)) / lonRange * viewSize.width
        let y = ((centerLat + latRange / 2) - coord.latitude) / latRange * viewSize.height

        return CGPoint(x: x, y: y)
    }

    private var points: [CGPoint] {
        coordinates.map { coordToPoint($0) }
    }

    var body: some View {
        ZStack {
            if points.count >= 2 {
                // Glow
                RoutePath(points: points)
                    .trim(from: 0, to: trimProgress)
                    .stroke(routeColor.opacity(0.3), style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))
                    .blur(radius: 3)

                // Main line
                RoutePath(points: points)
                    .trim(from: 0, to: trimProgress)
                    .stroke(routeColor, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))

                // Start marker
                if showMarkers, let start = points.first {
                    Circle()
                        .fill(.green)
                        .frame(width: 10, height: 10)
                        .overlay(Circle().stroke(.white, lineWidth: 2))
                        .shadow(color: .green.opacity(0.5), radius: 3)
                        .position(start)
                }

                // End marker
                if showMarkers, trimProgress >= 1.0, let end = points.last {
                    Circle()
                        .fill(routeColor)
                        .frame(width: 10, height: 10)
                        .overlay(Circle().stroke(.white, lineWidth: 2))
                        .shadow(color: routeColor.opacity(0.5), radius: 3)
                        .position(end)
                }
            }
        }
    }
}

// MARK: - Route Path Shape

private struct RoutePath: Shape {
    let points: [CGPoint]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        for point in points.dropFirst() {
            path.addLine(to: point)
        }
        return path
    }
}
