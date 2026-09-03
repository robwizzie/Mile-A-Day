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

/// Session cache for generated route snapshots. LazyVStack recycling resets a
/// card's @State, so without this every scroll pass re-requested the same
/// tiles (network + battery) for cards already seen. Keyed by a content hash
/// of the coordinates plus the render size — routes are immutable per
/// workout, so the key is stable.
private enum RouteSnapshotCache {
    final class Box {
        let snapshot: RouteMapSnapshot
        init(_ snapshot: RouteMapSnapshot) { self.snapshot = snapshot }
    }

    private static let cache: NSCache<NSString, Box> = {
        let c = NSCache<NSString, Box>()
        c.countLimit = 60
        return c
    }()

    static func key(coordinates: [CLLocationCoordinate2D], size: CGSize) -> NSString {
        var hasher = Hasher()
        hasher.combine(coordinates.count)
        // First/last plus a coarse sample — enough to distinguish real routes
        // without hashing 300 × N points per feed render.
        for c in [coordinates.first, coordinates.last].compactMap({ $0 }) {
            hasher.combine(c.latitude); hasher.combine(c.longitude)
        }
        let stride = max(1, coordinates.count / 8)
        var i = 0
        while i < coordinates.count {
            hasher.combine(coordinates[i].latitude)
            hasher.combine(coordinates[i].longitude)
            i += stride
        }
        return NSString(string: "\(hasher.finalize())-\(Int(size.width))x\(Int(size.height))")
    }

    static func snapshot(for key: NSString) -> RouteMapSnapshot? { cache.object(forKey: key)?.snapshot }
    static func store(_ snapshot: RouteMapSnapshot, for key: NSString) {
        cache.setObject(Box(snapshot), forKey: key)
    }
}

extension RouteMapSnapshot {
    /// One dark, POI-free snapshot covering `coordinates` at `size` — the same
    /// options the live map view uses, shared so `RouteArtView`'s ghost-map
    /// underlay and the baked auto-post image frame routes identically.
    /// Session-cached: recycled feed cells re-use instead of re-requesting.
    static func generate(coordinates: [CLLocationCoordinate2D], size: CGSize) async -> RouteMapSnapshot? {
        guard !coordinates.isEmpty, size.width > 1, size.height > 1 else { return nil }
        let key = RouteSnapshotCache.key(coordinates: coordinates, size: size)
        if let cached = RouteSnapshotCache.snapshot(for: key) { return cached }
        let options = MKMapSnapshotter.Options()
        options.region = WorkoutRouteMapView.region(for: coordinates)
        options.size = size
        options.mapType = .standard
        options.traitCollection = UITraitCollection(userInterfaceStyle: .dark)
        options.pointOfInterestFilter = .excludingAll
        guard let snap = try? await MKMapSnapshotter(options: options).start() else { return nil }
        let made = RouteMapSnapshot(image: snap.image, size: size, snapshot: snap)
        RouteSnapshotCache.store(made, for: key)
        return made
    }
}

/// One more person's trace on the same map — a buddy walk drawn as the one
/// walk it was, rather than as N separate cards each showing a third of it.
///
/// Colour is assigned by the caller (`CrewRoutePalette`) so the legend beside
/// the map and the line on it can't disagree about whose is whose.
struct CompanionRoute: Identifiable {
    let id: String
    let coordinates: [CLLocationCoordinate2D]
    let color: Color
}

/// Colours for the crew's lines on a combined route map.
///
/// One list, consulted by BOTH the map and the legend beside it — they were
/// always going to be derived twice otherwise, and a legend that disagrees
/// with the map is worse than no legend at all. Indexed by position in the
/// post's `acceptedCoauthors`, which the server orders deterministically
/// (`ORDER BY pca.created_at`), so a card doesn't reshuffle its colours
/// between reads.
///
/// Lives here rather than beside the model it describes because `Color` is
/// SwiftUI and PostService.swift is deliberately UIKit/Foundation only.
enum CrewRoutePalette {
    /// Seven hues spaced ~50° apart around the wheel, so no two lines on one
    /// map can read as the same person's.
    ///
    /// The previous list was picked for looks alone and had two collisions in
    /// it: `mint` sat beside `aqua`, `amber` beside `sand`, and — the one that
    /// actually mattered — the first entry was a sky blue about 13° off
    /// `walkBlue`, which is the colour the AUTHOR's line takes on every
    /// walking buddy walk. So the two most prominent traces on the commonest
    /// kind of crew card were near-identical. Spacing is the whole point of
    /// this list now; brightness is secondary.
    ///
    /// Ordered so that the first few taken are also the furthest apart — a
    /// three-person walk is far more common than an eight-person one, and it
    /// should get the strongest separation available, not merely a valid one.
    static let colors: [Color] = [
        Color(red: 1.00, green: 0.48, blue: 0.27),  // ember   ~17°
        Color(red: 0.18, green: 0.91, blue: 0.78),  // teal   ~169°
        Color(red: 0.69, green: 0.36, blue: 1.00),  // violet ~271°
        Color(red: 0.85, green: 0.95, blue: 0.30),  // citron  ~69°
        Color(red: 0.29, green: 0.49, blue: 1.00),  // cobalt ~223°
        Color(red: 0.35, green: 0.92, blue: 0.35),  // green  ~120°
        Color(red: 1.00, green: 0.29, blue: 0.72),  // magenta~323°
    ]

    /// How close (in degrees of hue) a crew colour may come to the author's
    /// before it counts as the same colour at a glance. 25° is where the
    /// walkBlue/sky pair that prompted this sat — comfortably inside it.
    private static let minimumHueSeparation: CGFloat = 25

    static func color(at index: Int) -> Color {
        colors[index % colors.count]
    }

    /// `count` companion colours, none of which reads as `authorColor`.
    ///
    /// The author's line keeps the activity accent (see `CompanionRoute`), and
    /// that accent is a fixed handful of values — walks blue, runs red — so the
    /// clash isn't hypothetical, it's what every walking buddy card did. Rather
    /// than recolour the author (their colour is the one the rest of the card
    /// is already using), the palette simply steps over anything too close.
    ///
    /// Deterministic and position-stable: colours are assigned by the caller's
    /// index into the crew, so the same walk draws the same way on every read.
    /// Falls back to the skipped entries once the distinct ones run out — at
    /// eight people a far-apart repeat beats an index out of range.
    static func companionColors(count: Int, avoiding authorColor: Color) -> [Color] {
        guard count > 0 else { return [] }
        let authorHue = hue(authorColor)
        var distinct: [Color] = []
        var skipped: [Color] = []
        for color in colors {
            if hueDistance(hue(color), authorHue) < minimumHueSeparation {
                skipped.append(color)
            } else {
                distinct.append(color)
            }
        }
        let ring = distinct.isEmpty ? colors : distinct + skipped
        return (0..<count).map { ring[$0 % ring.count] }
    }

    /// Degrees, 0–360. `UIColor` is the only thing that can read a `Color`'s
    /// components back out; every colour reaching this is an opaque sRGB
    /// literal, so the conversion is exact.
    private static func hue(_ color: Color) -> CGFloat {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return h * 360
    }

    /// Shortest way round the wheel — 350° and 10° are 20° apart, not 340°.
    private static func hueDistance(_ lhs: CGFloat, _ rhs: CGFloat) -> CGFloat {
        let raw = abs(lhs - rhs).truncatingRemainder(dividingBy: 360)
        return min(raw, 360 - raw)
    }
}

/// The one timing signature for a route drawing itself on — shared by the map
/// view and `RouteArtView`, so the same walk animates identically whichever
/// face renders it. Duration/stagger live HERE and nowhere else; two copies of
/// these numbers would drift the first time one card was "tuned".
enum RouteDrawTiming {
    /// How long one line takes to draw, and how far apart consecutive lines
    /// leave the start. Slowed twice on request (1.15 → 1.8 → 2.6): the draw
    /// is the card's whole show and deserves a beat to watch. Eight people at
    /// 0.13s still all leave inside the first second.
    static let drawDuration: Double = 2.6
    static let lineStagger: Double = 0.13

    /// One line's draw: same curve for everybody, a later start for each
    /// person behind the author.
    ///
    /// Deterministic (never random): a card re-renders constantly while
    /// scrolling, and timing that changed per render would make the same walk
    /// animate differently every time it came back on screen.
    static func lineAnimation(index: Int) -> Animation {
        .easeOut(duration: drawDuration).delay(Double(index) * lineStagger)
    }

    /// How long until the LAST line lands — the author plus one stagger step
    /// per companion.
    static func packDuration(_ companionCount: Int) -> Double {
        drawDuration + Double(companionCount) * lineStagger
    }
}

struct WorkoutRouteMapView: View {
    let coordinates: [CLLocationCoordinate2D]
    let routeColor: Color
    /// Everyone else who was on this walk and shared their route.
    ///
    /// Drawn onto the SAME snapshot, and — the part that matters — folded into
    /// the region, so the map frames the whole group rather than framing the
    /// author and letting the others run off the edge. Empty for every
    /// non-buddy caller, which is all of them but the feed's crew card.
    var companionRoutes: [CompanionRoute] = []
    /// Fired once the map snapshot lands — lets containers build a static
    /// composite (map + fully-drawn route) for the pinch-zoom floating copy.
    /// Carries the projection, not just the image: a `UIImage` alone can't say
    /// where a coordinate belongs on it.
    var onSnapshot: ((RouteMapSnapshot) -> Void)? = nil

    @State private var snapshot: RouteMapSnapshot?
    /// 0 → 1 for every line at once. The STAGGER is not in this value — each
    /// line carries its own `.animation(_:value:)` with its own delay, because
    /// a `Shape`'s `.trim` animates inside the shape without re-evaluating the
    /// parent body. The previous per-line "pace" multiplier was therefore a
    /// no-op: body saw this value exactly twice, at 0 and at 1, so
    /// `min(1, trim * pace)` evaluated to 0 and 1 for every line and the whole
    /// crew drew as one rigid object. Anything that must vary DURING the draw
    /// has to live in the animation, never in an expression on this.
    @State private var trimProgress: CGFloat = 0
    @State private var showStartMarkers = false
    /// Held back until the lines have actually landed. Same trap as above —
    /// gating the end pin on `trimProgress >= 1` put it on screen the instant
    /// the animation was *scheduled*, so every route finished before it drew.
    @State private var showEndMarkers = false
    /// The bright bead riding each line's drawing tip. Faded out once the pack
    /// is home rather than switched off, so it lands and settles.
    @State private var cometOpacity: Double = 1
    /// …and then removed outright. A bead left at zero opacity still costs its
    /// stroke and its coloured drop shadow on every frame, eight times over on
    /// a full crew card, for the whole time the post sits in a scrolling feed.
    /// Can't be folded into `cometOpacity`: gating the view on the value the
    /// fade animates TO would delete it before the fade ever ran.
    @State private var cometVisible = true
    @State private var hasAnimated = false

    /// Region math is static so the zoom composite can reproduce the framing
    /// without an instance — and `nonisolated` because it's pure math:
    /// `SwiftUI.View` is a @MainActor protocol, so statics here inherit
    /// isolation, and `RouteMapSnapshot.generate` (nonisolated async) calls
    /// this. Without the keyword that call is a Swift 6 error.
    nonisolated static func region(for coordinates: [CLLocationCoordinate2D]) -> MKCoordinateRegion {
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

    /// Framed over EVERY trace on the map. Framing on the author's alone left
    /// a buddy who looped the other way half off the card.
    private var region: MKCoordinateRegion {
        Self.region(for: coordinates + companionRoutes.flatMap(\.coordinates))
    }

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
        // Zooming a combined map must show the SAME lines the card does —
        // otherwise pinching a buddy walk's route quietly deletes everyone but
        // the poster from it.
        companionRoutes: [CompanionRoute] = [],
        size: CGSize,
        @ViewBuilder overlay: () -> Overlay
    ) -> UIImage? {
        let content = ZStack(alignment: .topLeading) {
            Image(uiImage: snapshot.image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: size.width, height: size.height)
                .clipped()
            ForEach(companionRoutes) { companion in
                RouteOverlay(
                    coordinates: companion.coordinates,
                    project: { snapshot.point(for: $0, in: size) },
                    routeColor: companion.color,
                    trimProgress: 1,
                    showEndMarker: true
                )
            }
            RouteOverlay(
                coordinates: coordinates,
                project: { snapshot.point(for: $0, in: size) },
                routeColor: routeColor,
                trimProgress: 1,
                showStartMarker: true,
                showEndMarker: true
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

                    // Everyone else's lines go UNDER the author's, and without
                    // start pins: five people on one map is five more markers
                    // on top of the author's two, which buries the route they
                    // annotate. Each companion DOES land a small dot of its own
                    // colour where they stopped — the legend says whose line is
                    // whose, and the dot is what lets you follow one to its end
                    // without tracing it back to the key.
                    ForEach(Array(companionRoutes.enumerated()), id: \.element.id) {
                        index, companion in
                        RouteOverlay(
                            coordinates: companion.coordinates,
                            project: { snapshot.point(for: $0, in: geo.size) },
                            routeColor: companion.color,
                            trimProgress: trimProgress,
                            cometOpacity: cometVisible ? cometOpacity : 0,
                            showStartMarker: false,
                            showEndMarker: showEndMarkers
                        )
                        // The stagger, applied where it actually works. Index 0
                        // here is the FIRST COMPANION; the author leaves first
                        // (delay 0, below) because the post is theirs.
                        .animation(Self.lineAnimation(index: index + 1), value: trimProgress)
                    }

                    // Animated route overlay, projected THROUGH the snapshot.
                    RouteOverlay(
                        coordinates: coordinates,
                        project: { snapshot.point(for: $0, in: geo.size) },
                        routeColor: routeColor,
                        trimProgress: trimProgress,
                        cometOpacity: cometVisible ? cometOpacity : 0,
                        showStartMarker: showStartMarkers,
                        showEndMarker: showEndMarkers
                    )
                    .animation(Self.lineAnimation(index: 0), value: trimProgress)
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
                    showStartMarkers = true
                }
                // A beat, so the start pin lands in its OWN update. Changed in
                // the same one as `trimProgress`, it would inherit the line
                // animation below — `.animation(_:value:)` governs everything
                // animatable in that subtree for the update its value changes
                // in, so the pin would fade over 1.15s instead of dropping.
                // It also just reads better: the pin drops, then the pack
                // leaves it.
                try? await Task.sleep(for: .milliseconds(120))

                // Deliberately NOT inside `withAnimation`: each line's own
                // `.animation(_:value:)` above owns the curve and the delay, and
                // an enclosing transaction would override both and put the pack
                // back in lockstep.
                trimProgress = 1.0

                // Everyone home. The end dots pop, and the beads that carried
                // the lines out there settle into them.
                try? await Task.sleep(for: .seconds(Self.packDuration(companionRoutes.count)))
                withAnimation(.spring(response: 0.42, dampingFraction: 0.55)) {
                    showEndMarkers = true
                }
                withAnimation(.easeOut(duration: 0.45)) {
                    cometOpacity = 0
                }
                try? await Task.sleep(for: .milliseconds(500))
                cometVisible = false
            }
        }
    }

    /// Timing shared with `RouteArtView` — see `RouteDrawTiming`.
    private static func lineAnimation(index: Int) -> Animation {
        RouteDrawTiming.lineAnimation(index: index)
    }

    private static func packDuration(_ companionCount: Int) -> Double {
        RouteDrawTiming.packDuration(companionCount)
    }

    /// Whole-point size: sub-pixel layout jitter must not re-trigger the
    /// snapshot task on every scroll frame.
    private static func renderSize(_ size: CGSize) -> CGSize {
        CGSize(width: size.width.rounded(), height: size.height.rounded())
    }

    private func generateSnapshot(size: CGSize) async {
        // Size MUST match the view this draws into. The image is displayed
        // aspect-fill while the route is drawn in the VIEW's coordinate
        // space, so a fixed 400×300 snapshot inside a 4:5 card had a third of
        // its width cropped away while the line still spanned the full frame
        // — which is how a shoreline walk got drawn out in the bay.
        guard let made = await RouteMapSnapshot.generate(
            coordinates: coordinates + companionRoutes.flatMap(\.coordinates),
            size: size
        ) else {
            print("[WorkoutRouteMapView] Snapshot failed")
            return
        }
        snapshot = made
        onSnapshot?(made)
    }
}

// MARK: - Route Overlay (pure SwiftUI drawing — no Map view)

/// Internal (not private) because `RouteArtView` draws its lines through the
/// SAME recipe on its branded canvas — a second copy of these strokes would
/// drift the first time one was touched.
struct RouteOverlay: View {
    let coordinates: [CLLocationCoordinate2D]
    /// Coordinate → view point. Always the snapshot's own projection; never
    /// re-derived from the requested region (see `RouteMapSnapshot`).
    let project: (CLLocationCoordinate2D) -> CGPoint
    let routeColor: Color
    let trimProgress: CGFloat
    /// Fades the drawing bead out once the line has landed.
    var cometOpacity: Double = 0
    var showStartMarker: Bool = false
    var showEndMarker: Bool = false
    /// Pre-projected (and possibly LANED — see `RouteLaneOffset`) points. When
    /// set, `coordinates`/`project` are ignored for the line itself.
    var overridePoints: [CGPoint]? = nil

    private var points: [CGPoint] {
        overridePoints ?? coordinates.map(project)
    }

    /// The bead's length as a fraction of the whole line. Short enough to read
    /// as a head rather than a second, brighter route.
    private static let cometLength: CGFloat = 0.055

    var body: some View {
        // Projected once, not per-stroke: the glow, the casing, the line, the
        // bead and both markers all read the same array.
        let points = self.points
        return ZStack {
            if points.count >= 2 {
                // Glow
                RoutePath(points: points)
                    .trim(from: 0, to: trimProgress)
                    .stroke(routeColor.opacity(0.3), style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))
                    .blur(radius: 3)

                // Dark casing under the colour. Eight lines on one map cross
                // each other constantly, and where two bright strokes overlap
                // with nothing between them the eye reads a single line that
                // changes colour. A hairline of map-dark on either side is what
                // keeps them legible as separate people — the same trick every
                // transit map uses, and it costs one stroke.
                RoutePath(points: points)
                    .trim(from: 0, to: trimProgress)
                    .stroke(Color.black.opacity(0.45), style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))

                // Main line
                RoutePath(points: points)
                    .trim(from: 0, to: trimProgress)
                    .stroke(routeColor, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))

                // The bead riding the tip while the line draws.
                //
                // Positioned by trimming the path itself — both ends of the
                // window animate, so it slides along the route for free. The
                // alternative (a cumulative arc-length table sampled per frame)
                // is a second answer to a question `Path.trim` has already
                // answered, and one that could disagree with the line under it.
                RoutePath(points: points)
                    .trim(from: max(0, trimProgress - Self.cometLength), to: trimProgress)
                    .stroke(Color.white, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                    .shadow(color: routeColor, radius: 6)
                    .opacity(cometOpacity)

                // Start marker
                if showStartMarker, let start = points.first {
                    Circle()
                        .fill(.green)
                        .frame(width: 10, height: 10)
                        .overlay(Circle().stroke(.white, lineWidth: 2))
                        .shadow(color: .green.opacity(0.5), radius: 3)
                        .position(start)
                }

                // End marker — this walker's own colour, so a crew card says
                // where each person stopped without any of them wearing the
                // same dot.
                if showEndMarker, let end = points.last {
                    Circle()
                        .fill(routeColor)
                        .frame(width: 10, height: 10)
                        .overlay(Circle().stroke(.white, lineWidth: 2))
                        .shadow(color: routeColor.opacity(0.5), radius: 3)
                        .position(end)
                        .transition(.scale(scale: 0.2).combined(with: .opacity))
                }
            }
        }
    }
}

// MARK: - Route Path Shape

struct RoutePath: Shape {
    let points: [CGPoint]

    func path(in rect: CGRect) -> Path {
        // Drawn identically to the baked auto-post image (RunPostService).
        Path(RoutePolyline.path(through: points))
    }
}
