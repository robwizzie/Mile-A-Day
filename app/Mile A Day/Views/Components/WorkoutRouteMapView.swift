import SwiftUI
import MapKit

/// A finished map snapshot plus the only projection that registers route
/// coordinates onto it.
///
/// Why this exists: MapKit draws in Web Mercator AND — more importantly — it
/// ADJUSTS the `MKCoordinateRegion` it was handed to fit the requested image's
/// aspect ratio, expanding whichever axis is short. So neither the requested
/// region nor a linear lat/lon → pixel mapping describes where a coordinate
/// actually landed in the image. `MKMapSnapshotter.Snapshot.point(for:)` is
/// the snapshot's own answer, and it is what keeps our line on the same
/// streets Apple Fitness draws it on.
struct RouteMapSnapshot {
    let image: UIImage
    /// Point size the snapshot was rendered at (== `options.size`, which is
    /// also the space `snapshot.point(for:)` answers in).
    let size: CGSize
    fileprivate let snapshot: MKMapSnapshotter.Snapshot

    /// Where `coordinate` sits in a view of `viewSize` that displays `image`
    /// with `.aspectRatio(contentMode: .fill)` — scaled to cover, centered,
    /// cropped. Snapshots are requested at the view's own size, so the scale
    /// is normally 1 and the crop zero; the math stays correct if the view
    /// resizes (rotation, re-layout) before a fresh snapshot lands.
    func point(for coordinate: CLLocationCoordinate2D, in viewSize: CGSize) -> CGPoint {
        let raw = snapshot.point(for: coordinate)
        guard size.width > 0, size.height > 0 else { return raw }
        let scale = max(viewSize.width / size.width, viewSize.height / size.height)
        return CGPoint(
            x: raw.x * scale + (viewSize.width - size.width * scale) / 2,
            y: raw.y * scale + (viewSize.height - size.height * scale) / 2
        )
    }
}

struct WorkoutRouteMapView: View {
    let coordinates: [CLLocationCoordinate2D]
    let routeColor: Color
    /// Fired once the map snapshot lands — lets containers build a static
    /// composite (map + fully-drawn route) for the pinch-zoom floating copy.
    /// Carries the projection, not just the image: a `UIImage` alone can't say
    /// where a coordinate belongs on it.
    var onSnapshot: ((RouteMapSnapshot) -> Void)? = nil

    @State private var snapshot: RouteMapSnapshot?
    @State private var trimProgress: CGFloat = 0
    @State private var showMarkers = false
    @State private var hasAnimated = false

    /// Region math is static so the zoom composite can reproduce the framing
    /// without an instance.
    static func region(for coordinates: [CLLocationCoordinate2D]) -> MKCoordinateRegion {
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

    private var region: MKCoordinateRegion { Self.region(for: coordinates) }

    /// Static composite of the snapshot + fully-drawn route (+ an optional
    /// caller overlay, e.g. the stats band) at `size` — what the Instagram
    /// pinch-zoom floats. Composed ON DEMAND at pinch-begin (never eagerly
    /// per card — a feed of routes would retain megabytes for gestures that
    /// mostly never happen). Callers pass a `size` matching the card's aspect
    /// ratio, so this is pixel-equivalent to the live view.
    static func zoomComposite<Overlay: View>(
        snapshot: RouteMapSnapshot,
        coordinates: [CLLocationCoordinate2D],
        routeColor: Color,
        size: CGSize,
        @ViewBuilder overlay: () -> Overlay
    ) -> UIImage? {
        let content = ZStack(alignment: .topLeading) {
            Image(uiImage: snapshot.image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: size.width, height: size.height)
                .clipped()
            RouteOverlay(
                coordinates: coordinates,
                project: { snapshot.point(for: $0, in: size) },
                routeColor: routeColor,
                trimProgress: 1,
                showMarkers: true
            )
            overlay()
        }
        .frame(width: size.width, height: size.height)

        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        renderer.isOpaque = true
        return renderer.uiImage
    }

    /// A composite size that keeps the card's own aspect ratio, so the zoom
    /// copy is a pure upscale. A hardcoded size whose aspect doesn't match the
    /// card center-crops, which can lop the ends off the route.
    static func zoomSize(for snapshot: RouteMapSnapshot, targetWidth: CGFloat) -> CGSize {
        guard snapshot.size.width > 0, snapshot.size.height > 0 else {
            return CGSize(width: targetWidth, height: targetWidth)
        }
        let scale = targetWidth / snapshot.size.width
        return CGSize(width: targetWidth, height: (snapshot.size.height * scale).rounded())
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let snapshot {
                    // Static map snapshot — no lag in scroll
                    Image(uiImage: snapshot.image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()

                    // Animated route overlay, projected THROUGH the snapshot.
                    RouteOverlay(
                        coordinates: coordinates,
                        project: { snapshot.point(for: $0, in: geo.size) },
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
            // Keyed on the size the snapshot must be taken at, so a view that
            // lays out at zero first (or rotates later) re-snapshots at the
            // right dimensions instead of stretching a stale one.
            .task(id: Self.renderSize(geo.size)) {
                let size = Self.renderSize(geo.size)
                guard size.width > 1, size.height > 1 else { return }
                await generateSnapshot(size: size)

                // Animate the route in once, on the first snapshot only — a
                // re-snapshot after a resize must not replay the draw-on.
                guard !hasAnimated, snapshot != nil else { return }
                hasAnimated = true
                try? await Task.sleep(for: .milliseconds(300))
                withAnimation(.easeOut(duration: 0.3)) {
                    showMarkers = true
                }
                withAnimation(.easeInOut(duration: 1.2)) {
                    trimProgress = 1.0
                }
            }
        }
    }

    /// Whole-point size: sub-pixel layout jitter must not re-trigger the
    /// snapshot task on every scroll frame.
    private static func renderSize(_ size: CGSize) -> CGSize {
        CGSize(width: size.width.rounded(), height: size.height.rounded())
    }

    private func generateSnapshot(size: CGSize) async {
        let options = MKMapSnapshotter.Options()
        options.region = region
        // MUST match the view this draws into. The image is displayed
        // aspect-fill while the route is drawn in the VIEW's coordinate
        // space, so a fixed 400×300 snapshot inside a 4:5 card had a third of
        // its width cropped away while the line still spanned the full frame
        // — which is how a shoreline walk got drawn out in the bay.
        options.size = size
        options.mapType = .standard
        options.traitCollection = UITraitCollection(userInterfaceStyle: .dark)
        options.pointOfInterestFilter = .excludingAll

        let snapshotter = MKMapSnapshotter(options: options)
        do {
            let snap = try await snapshotter.start()
            let made = RouteMapSnapshot(image: snap.image, size: size, snapshot: snap)
            snapshot = made
            onSnapshot?(made)
        } catch {
            print("[WorkoutRouteMapView] Snapshot failed: \(error)")
        }
    }
}

// MARK: - Route Overlay (pure SwiftUI drawing — no Map view)

private struct RouteOverlay: View {
    let coordinates: [CLLocationCoordinate2D]
    /// Coordinate → view point. Always the snapshot's own projection; never
    /// re-derived from the requested region (see `RouteMapSnapshot`).
    let project: (CLLocationCoordinate2D) -> CGPoint
    let routeColor: Color
    let trimProgress: CGFloat
    let showMarkers: Bool

    private var points: [CGPoint] {
        coordinates.map(project)
    }

    var body: some View {
        // Projected once, not per-stroke: the glow, the line and both markers
        // all read the same array.
        let points = self.points
        return ZStack {
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
        // Smoothed identically to the baked auto-post image (RunPostService).
        Path(RouteSmoothing.smoothedPath(through: points))
    }
}
