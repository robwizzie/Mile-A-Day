import SwiftUI
import MapKit

struct WorkoutRouteMapView: View {
    let coordinates: [CLLocationCoordinate2D]
    let routeColor: Color

    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var trimProgress: CGFloat = 0
    @State private var screenPoints: [CGPoint] = []
    @State private var showStartMarker = false
    @State private var showEndMarker = false

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

        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLat - minLat) * 1.3, 0.003),
            longitudeDelta: max((maxLon - minLon) * 1.3, 0.003)
        )

        return MKCoordinateRegion(center: center, span: span)
    }

    var body: some View {
        MapReader { proxy in
            Map(position: $cameraPosition, interactionModes: []) {
                // Full route as a subtle background line (always visible once loaded)
                if !screenPoints.isEmpty {
                    MapPolyline(coordinates: coordinates)
                        .stroke(routeColor.opacity(0.15), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                }
            }
            .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
            .colorScheme(.dark)
            .allowsHitTesting(false)
            .overlay {
                if !screenPoints.isEmpty {
                    ZStack {
                        // Glow layer
                        RoutePath(points: screenPoints)
                            .trim(from: 0, to: trimProgress)
                            .stroke(routeColor.opacity(0.35), style: StrokeStyle(lineWidth: 10, lineCap: .round, lineJoin: .round))
                            .blur(radius: 4)

                        // Main route line
                        RoutePath(points: screenPoints)
                            .trim(from: 0, to: trimProgress)
                            .stroke(routeColor, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))

                        // Start marker
                        if showStartMarker, let start = screenPoints.first {
                            ZStack {
                                Circle()
                                    .fill(.green)
                                    .frame(width: 12, height: 12)
                                Circle()
                                    .stroke(.white, lineWidth: 2)
                                    .frame(width: 12, height: 12)
                            }
                            .shadow(color: .green.opacity(0.5), radius: 4)
                            .position(start)
                            .transition(.scale.combined(with: .opacity))
                        }

                        // End marker
                        if showEndMarker, let end = screenPoints.last {
                            ZStack {
                                Circle()
                                    .fill(routeColor)
                                    .frame(width: 12, height: 12)
                                Circle()
                                    .stroke(.white, lineWidth: 2)
                                    .frame(width: 12, height: 12)
                            }
                            .shadow(color: routeColor.opacity(0.5), radius: 4)
                            .position(end)
                            .transition(.scale.combined(with: .opacity))
                        }
                    }
                }
            }
            .onAppear {
                cameraPosition = .region(region)
            }
            .task {
                guard !coordinates.isEmpty else { return }

                // Wait for the map to settle into position
                try? await Task.sleep(for: .milliseconds(600))

                // Convert geo coordinates to screen points
                let points = coordinates.compactMap { proxy.convert($0, to: .local) }
                guard points.count >= 2 else { return }
                screenPoints = points

                // Show start marker
                withAnimation(.easeOut(duration: 0.3)) {
                    showStartMarker = true
                }

                try? await Task.sleep(for: .milliseconds(200))

                // Animate route drawing
                withAnimation(.easeInOut(duration: 1.8)) {
                    trimProgress = 1.0
                }

                // Show end marker after route finishes drawing
                try? await Task.sleep(for: .milliseconds(1800))
                withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                    showEndMarker = true
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
