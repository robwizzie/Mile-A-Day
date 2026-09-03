import SwiftUI
import UIKit
import CoreLocation

/// Who rides a route line — name for the initials fallback, path/URL for the
/// photo (`profile_image_url` as the API serves it).
struct RouteArtAvatar {
    let name: String
    let imageURL: String?
}

/// Time-of-day tint for the art canvas: a dawn walk, a midday run, a dusk
/// loop and a night mile each get their own subtle cast — instant variety
/// across a profile of cards, from a timestamp every surface already has.
/// Deliberately gentle: the activity accent stays the loudest colour.
enum RouteArtPalette {
    static func bucket(for date: Date?) -> Int? {
        guard let date else { return nil }
        return Calendar.current.component(.hour, from: date)
    }

    /// The canvas gradient's top colour for an hour (nil hour = the default).
    static func canvasTop(hour: Int?) -> Color {
        switch hour {
        case .some(5..<8):   return Color(red: 0.15, green: 0.09, blue: 0.11)  // dawn rose
        case .some(17..<20): return Color(red: 0.13, green: 0.08, blue: 0.15)  // dusk violet
        case .some(20...), .some(..<5):
            return Color(red: 0.05, green: 0.07, blue: 0.14)                   // night indigo
        default:             return Color(red: 0.09, green: 0.09, blue: 0.12)  // day
        }
    }

    /// A faint horizon wash at the canvas foot; nil for plain daytime.
    static func horizon(hour: Int?) -> Color? {
        switch hour {
        case .some(5..<8):   return Color(red: 1.0, green: 0.55, blue: 0.35)
        case .some(17..<20): return Color(red: 0.85, green: 0.45, blue: 0.75)
        case .some(20...), .some(..<5):
            return Color(red: 0.35, green: 0.45, blue: 1.0)
        default:             return nil
        }
    }
}

/// The branded dark canvas every Route Art surface draws on — same visual
/// language as `FeedWorkoutCard` (dark vertical gradient + activity-colour
/// radial glow), plus a faint dot grid so the empty space reads as a designed
/// surface rather than a missing map. Reused by the indoor cards.
struct ArtCanvasBackground: View {
    let accent: Color
    /// Hour of the workout, for the time-of-day cast; nil = default look.
    var hour: Int? = nil

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [RouteArtPalette.canvasTop(hour: hour), .black],
                startPoint: .top, endPoint: .bottom
            )
            if let horizon = RouteArtPalette.horizon(hour: hour) {
                LinearGradient(
                    colors: [.clear, horizon.opacity(0.16)],
                    startPoint: .center, endPoint: .bottom
                )
            }
            RadialGradient(
                colors: [accent.opacity(0.4), .clear],
                center: .init(x: 0.5, y: 0.32), startRadius: 8, endRadius: 220
            )
            DotGridTexture()
        }
    }
}

/// Static texture — a plain `Canvas`, so it costs one draw and renders fine
/// inside `ImageRenderer` (zoom composites, the baked auto-post image).
private struct DotGridTexture: View {
    var body: some View {
        Canvas { context, size in
            let pitch: CGFloat = 14
            let radius: CGFloat = 1
            var y: CGFloat = pitch / 2
            while y < size.height {
                var x: CGFloat = pitch / 2
                while x < size.width {
                    context.fill(
                        Path(ellipseIn: CGRect(x: x - radius, y: y - radius,
                                               width: radius * 2, height: radius * 2)),
                        with: .color(.white.opacity(0.05))
                    )
                    x += pitch
                }
                y += pitch
            }
        }
        .allowsHitTesting(false)
    }
}

/// The faint real-world context behind the art: the dark POI-free map
/// snapshot, desaturated and washed with the canvas gradient + accent glow so
/// streets GHOST behind the line rather than compete with it. When this is
/// present every piece of route geometry projects THROUGH the snapshot
/// (ios.md rule) — a line over visible streets must land on those streets.
struct GhostMapUnderlay: View {
    let snapshot: RouteMapSnapshot
    let accent: Color
    let viewSize: CGSize
    var hour: Int? = nil

    var body: some View {
        ZStack {
            Image(uiImage: snapshot.image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: viewSize.width, height: viewSize.height)
                .clipped()
                .saturation(0.35)
            // Wash toward the canvas look — heavy enough to stay moody,
            // light enough that blocks and shorelines still read.
            LinearGradient(
                colors: [Color(red: 0.09, green: 0.09, blue: 0.12).opacity(0.35),
                         Color.black.opacity(0.55)],
                startPoint: .top, endPoint: .bottom
            )
            if let horizon = RouteArtPalette.horizon(hour: hour) {
                LinearGradient(
                    colors: [.clear, horizon.opacity(0.12)],
                    startPoint: .center, endPoint: .bottom
                )
            }
            RadialGradient(
                colors: [accent.opacity(0.25), .clear],
                center: .init(x: 0.5, y: 0.32), startRadius: 8, endRadius: 220
            )
        }
    }
}

/// The route as art: the polyline drawn on the branded canvas instead of an
/// Apple map — the default route face everywhere (the full map stays one tap
/// away on detail surfaces). Same stroke recipe (`RouteOverlay`), same draw
/// timing (`RouteDrawTiming`) as `WorkoutRouteMapView`. A ghosted, washed
/// map snapshot sits UNDER the art for real-world context; when it's there,
/// all geometry projects through it (see `GhostMapUnderlay`), and when it
/// can't load the card falls back to the pure canvas + fit projection.
///
/// New over the map view: the author's profile picture rides the tip of the
/// line as it draws and settles as the end marker (companions each ride their
/// own line), and mile ticks pop along the path as the line crosses them.
struct RouteArtView: View {
    let coordinates: [CLLocationCoordinate2D]
    let routeColor: Color
    /// Everyone else on this walk who shared a route — same contract as
    /// `WorkoutRouteMapView.companionRoutes` (colours assigned by the caller
    /// via `CrewRoutePalette` so the legend can't disagree with the lines).
    var companionRoutes: [CompanionRoute] = []
    var authorAvatar: RouteArtAvatar? = nil
    /// Keyed by `CompanionRoute.id` (the participant's user id).
    var companionAvatars: [String: RouteArtAvatar] = [:]
    var showsMileMarkers: Bool = true
    /// Fired when the ghost-map underlay's snapshot lands — call sites keep it
    /// for the pinch-zoom composite, exactly the old map-view contract.
    var onSnapshot: ((RouteMapSnapshot) -> Void)? = nil
    /// When the workout happened, for the canvas's time-of-day cast.
    var paletteDate: Date? = nil
    /// One walker's line brought to the front at full strength while the
    /// others dim — `"author"` for the poster, else a `CompanionRoute.id`.
    /// nil = everyone equal. Driven by the card's legend chips.
    var highlightedRouteId: String? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Same state machine as WorkoutRouteMapView — see the comments there; the
    // stagger lives in per-line `.animation(_:value:)`, never in an
    // expression on `trimProgress` (ios.md).
    @State private var trimProgress: CGFloat = 0
    @State private var showStartMarkers = false
    @State private var showEndMarkers = false
    @State private var ridersVisible = false
    @State private var cometOpacity: Double = 1
    @State private var cometVisible = true
    @State private var hasAnimated = false
    /// The ghost-map underlay. While nil the card is the pure branded canvas;
    /// once it lands, all geometry projects through it.
    @State private var snapshot: RouteMapSnapshot?
    /// Loaded avatar bitmaps, keyed by the avatar's `imageURL`. Filled by
    /// `.task` through `FeedImageCache`; until (or unless) a photo lands the
    /// badge shows initials.
    @State private var avatarImages: [String: UIImage] = [:]

    var body: some View {
        GeometryReader { geo in
            let layout = RouteArtLayout(
                coordinates: coordinates,
                companionRoutes: companionRoutes,
                size: geo.size,
                snapshot: snapshot
            )
            ZStack(alignment: .topLeading) {
                if let snapshot {
                    GhostMapUnderlay(snapshot: snapshot, accent: routeColor, viewSize: geo.size,
                                     hour: RouteArtPalette.bucket(for: paletteDate))
                } else {
                    // Pure canvas until (or unless — offline, degenerate) the
                    // underlay lands. Nothing has drawn yet at that point, so
                    // the projection switch is invisible.
                    ArtCanvasBackground(accent: routeColor,
                                        hour: RouteArtPalette.bucket(for: paletteDate))
                }
                RouteArtStage(
                    layout: layout,
                    coordinates: coordinates,
                    routeColor: routeColor,
                    companionRoutes: companionRoutes,
                    authorAvatar: authorAvatar,
                    companionAvatars: companionAvatars,
                    avatarImages: avatarImages,
                    showsMileMarkers: showsMileMarkers,
                    trimProgress: trimProgress,
                    cometOpacity: cometVisible ? cometOpacity : 0,
                    showStartMarkers: showStartMarkers,
                    showEndMarkers: showEndMarkers,
                    ridersVisible: ridersVisible,
                    animationsEnabled: !reduceMotion,
                    highlightedRouteId: highlightedRouteId
                )
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: highlightedRouteId)
            }
            // Keyed on whole-point size (same rule as the map view): scroll
            // jitter must not re-snapshot, a real resize must.
            .task(id: renderSize(geo.size)) {
                let size = renderSize(geo.size)
                guard size.width > 1, size.height > 1 else { return }
                let all = coordinates + companionRoutes.flatMap(\.coordinates)
                if !all.isEmpty, snapshot == nil {
                    if let made = await RouteMapSnapshot.generate(coordinates: all, size: size) {
                        snapshot = made
                        onSnapshot?(made)
                    }
                }
                // The draw waits for the underlay attempt to resolve either
                // way — animating on the fit projection and then re-projecting
                // onto streets would visibly jump the line.
                await animateIn()
            }
            .task(id: avatarKeySignature) { await loadAvatars() }
        }
    }

    private func renderSize(_ size: CGSize) -> CGSize {
        CGSize(width: size.width.rounded(), height: size.height.rounded())
    }

    /// The draw-on, lifted verbatim from `WorkoutRouteMapView` (the snapshot
    /// wait happens in the caller task above). Every beat's reasoning lives in
    /// the comments there: the start pin in its OWN update, `trimProgress`
    /// set OUTSIDE `withAnimation`, the comet faded then removed.
    private func animateIn() async {
        guard !hasAnimated else { return }
        hasAnimated = true
        if reduceMotion {
            // Land the finished frame with no draw-on. The stage's
            // `.animation(_:value:)` modifiers are nil'd below, so these
            // writes don't animate either.
            showStartMarkers = true
            ridersVisible = true
            trimProgress = 1.0
            showEndMarkers = true
            cometOpacity = 0
            cometVisible = false
            return
        }
        try? await Task.sleep(for: .milliseconds(300))
        withAnimation(.easeOut(duration: 0.3)) {
            showStartMarkers = true
            ridersVisible = true
        }
        try? await Task.sleep(for: .milliseconds(120))
        trimProgress = 1.0
        try? await Task.sleep(for: .seconds(RouteDrawTiming.packDuration(companionRoutes.count)))
        withAnimation(.spring(response: 0.42, dampingFraction: 0.55)) {
            showEndMarkers = true
        }
        withAnimation(.easeOut(duration: 0.45)) {
            cometOpacity = 0
        }
        try? await Task.sleep(for: .milliseconds(500))
        cometVisible = false
    }

    private var allAvatars: [RouteArtAvatar] {
        (authorAvatar.map { [$0] } ?? []) + Array(companionAvatars.values)
    }

    private var avatarKeySignature: String {
        allAvatars.compactMap(\.imageURL).sorted().joined(separator: "|")
    }

    private func loadAvatars() async {
        for avatar in allAvatars {
            guard let key = avatar.imageURL, !key.isEmpty, avatarImages[key] == nil else { continue }
            if let image = await RouteAvatarImageLoader.loadImage(for: key) {
                avatarImages[key] = image
            }
        }
    }

    // MARK: - Statics for composites

    /// The finished frame — trim complete, markers on, riders settled at their
    /// endpoints — built without a GeometryReader so `ImageRenderer` can bake
    /// it (the zoom composite and the auto-post image both do).
    static func still(
        coordinates: [CLLocationCoordinate2D],
        routeColor: Color,
        companionRoutes: [CompanionRoute] = [],
        authorAvatar: RouteArtAvatar? = nil,
        companionAvatars: [String: RouteArtAvatar] = [:],
        avatarImages: [String: UIImage] = [:],
        showsMileMarkers: Bool = true,
        underlay: RouteMapSnapshot? = nil,
        paletteDate: Date? = nil,
        highlightedRouteId: String? = nil,
        size: CGSize
    ) -> some View {
        let layout = RouteArtLayout(
            coordinates: coordinates,
            companionRoutes: companionRoutes,
            size: size,
            snapshot: underlay
        )
        return ZStack(alignment: .topLeading) {
            if let underlay {
                GhostMapUnderlay(snapshot: underlay, accent: routeColor, viewSize: size,
                                 hour: RouteArtPalette.bucket(for: paletteDate))
            } else {
                ArtCanvasBackground(accent: routeColor,
                                    hour: RouteArtPalette.bucket(for: paletteDate))
            }
            RouteArtStage(
                layout: layout,
                coordinates: coordinates,
                routeColor: routeColor,
                companionRoutes: companionRoutes,
                authorAvatar: authorAvatar,
                companionAvatars: companionAvatars,
                avatarImages: avatarImages,
                showsMileMarkers: showsMileMarkers,
                trimProgress: 1,
                cometOpacity: 0,
                showStartMarkers: true,
                showEndMarkers: true,
                ridersVisible: true,
                highlightedRouteId: highlightedRouteId
            )
        }
        .frame(width: size.width, height: size.height)
    }

    /// Replacement for `WorkoutRouteMapView.zoomComposite` on art surfaces:
    /// the pinch-zoom floating copy, composed ON DEMAND at pinch-begin.
    /// Avatars are read cache-only (a pinch must not wait on a download —
    /// initials are the miss behaviour, and by pinch time the live card has
    /// almost always warmed the cache).
    static func zoomComposite<Overlay: View>(
        coordinates: [CLLocationCoordinate2D],
        routeColor: Color,
        companionRoutes: [CompanionRoute] = [],
        authorAvatar: RouteArtAvatar? = nil,
        companionAvatars: [String: RouteArtAvatar] = [:],
        showsMileMarkers: Bool = true,
        underlay: RouteMapSnapshot? = nil,
        paletteDate: Date? = nil,
        highlightedRouteId: String? = nil,
        size: CGSize,
        @ViewBuilder overlay: () -> Overlay
    ) -> UIImage? {
        var images: [String: UIImage] = [:]
        let avatars = (authorAvatar.map { [$0] } ?? []) + Array(companionAvatars.values)
        for avatar in avatars {
            guard let key = avatar.imageURL, images[key] == nil else { continue }
            if let cached = RouteAvatarImageLoader.cachedImage(for: key) {
                images[key] = cached
            }
        }
        let content = ZStack(alignment: .topLeading) {
            still(
                coordinates: coordinates,
                routeColor: routeColor,
                companionRoutes: companionRoutes,
                authorAvatar: authorAvatar,
                companionAvatars: companionAvatars,
                avatarImages: images,
                showsMileMarkers: showsMileMarkers,
                underlay: underlay,
                paletteDate: paletteDate,
                highlightedRouteId: highlightedRouteId,
                size: size
            )
            overlay()
        }
        .frame(width: size.width, height: size.height)

        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        renderer.isOpaque = true
        return renderer.uiImage
    }
}

// MARK: - Layout (projection + per-person metrics, computed once per size)

private struct RouteArtLayout {
    /// With a ghost-map underlay this is the SNAPSHOT's projection — a line
    /// over visible streets must land on those streets (ios.md rule); without
    /// one it is the plain aspect-fit canvas projection.
    let project: (CLLocationCoordinate2D) -> CGPoint
    let authorMetrics: RouteArtMetrics?
    let companionMetrics: [String: RouteArtMetrics]
    /// Each companion's projected polyline, LANED sideways by a few points
    /// (`RouteLaneOffset`) so two people who walked the same loop draw as two
    /// lines. Riders and end dots follow these same points, never the raw
    /// projection, so a badge sits on the line it belongs to.
    let companionPoints: [String: [CGPoint]]

    init(coordinates: [CLLocationCoordinate2D], companionRoutes: [CompanionRoute],
         size: CGSize, snapshot: RouteMapSnapshot?) {
        // Framing covers EVERY trace — same rule as the map view's region:
        // framing on the author alone runs a buddy off the edge. (The
        // snapshot was generated over the same combined list.)
        let all = coordinates + companionRoutes.flatMap(\.coordinates)
        let projector: (CLLocationCoordinate2D) -> CGPoint
        if let snapshot {
            projector = { snapshot.point(for: $0, in: size) }
        } else {
            let projection = RouteArtProjection(coordinates: all, size: size)
            projector = projection.point(for:)
        }
        project = projector
        if coordinates.count >= 2 {
            let metrics = RouteArtMetrics(coordinates: coordinates, project: projector)
            authorMetrics = metrics.isDrawable ? metrics : nil
        } else {
            // A crew card whose author walked indoors (or shares no maps)
            // still frames the companions — the author simply has no line.
            authorMetrics = nil
        }
        var byId: [String: RouteArtMetrics] = [:]
        var pointsById: [String: [CGPoint]] = [:]
        // ≈5pt on a 360-wide card; scales with the composite so the zoom copy
        // keeps the same separation.
        let laneUnit = max(3, size.width / 72)
        for (index, companion) in companionRoutes.enumerated()
        where companion.coordinates.count >= 2 {
            let raw = RouteArtMetrics(coordinates: companion.coordinates, project: projector)
            guard raw.isDrawable else { continue }
            let laned = RouteLaneOffset.offset(
                raw.points, by: RouteLaneOffset.lane(index: index, unit: laneUnit))
            byId[companion.id] = RouteArtMetrics(points: laned)
            pointsById[companion.id] = laned
        }
        companionMetrics = byId
        companionPoints = pointsById
    }
}

// MARK: - Stage (lines + ticks + riders at explicit state values)

/// One drawing of the whole scene at explicit state values — shared by the
/// live animating view and the baked `still`. The `.animation(_:value:)`
/// modifiers are inert when the values never change, so the still frame costs
/// nothing extra.
private struct RouteArtStage: View {
    let layout: RouteArtLayout
    let coordinates: [CLLocationCoordinate2D]
    let routeColor: Color
    let companionRoutes: [CompanionRoute]
    let authorAvatar: RouteArtAvatar?
    let companionAvatars: [String: RouteArtAvatar]
    let avatarImages: [String: UIImage]
    let showsMileMarkers: Bool
    let trimProgress: CGFloat
    let cometOpacity: Double
    let showStartMarkers: Bool
    let showEndMarkers: Bool
    let ridersVisible: Bool
    /// False under Reduce Motion (and for still frames the values simply
    /// never change): the `.animation(_:value:)` attachments become nil so
    /// state landings render instantly.
    var animationsEnabled: Bool = true
    /// See `RouteArtView.highlightedRouteId`.
    var highlightedRouteId: String? = nil

    private static let authorId = "author"

    private func lineAnimation(_ index: Int) -> Animation? {
        animationsEnabled ? RouteDrawTiming.lineAnimation(index: index) : nil
    }

    /// Everyone but the chosen walker dims; nobody chosen ⇒ everyone equal.
    private func emphasis(_ id: String) -> Double {
        guard let highlightedRouteId else { return 1 }
        return highlightedRouteId == id ? 1 : 0.28
    }

    private var highlightedCompanion: CompanionRoute? {
        guard let highlightedRouteId, highlightedRouteId != Self.authorId else { return nil }
        return companionRoutes.first { $0.id == highlightedRouteId }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Companions' lines UNDER the author's, no start pins — same
            // layering rationale as WorkoutRouteMapView. A line whose walker
            // has a rider badge drops its coloured end dot (the badge IS the
            // end marker); one without keeps it. A HIGHLIGHTED companion
            // skips this pass and is painted above the author instead.
            ForEach(Array(companionRoutes.enumerated()), id: \.element.id) { index, companion in
                if companion.id != highlightedCompanion?.id {
                    companionLine(companion, index: index)
                }
            }

            if layout.authorMetrics != nil {
                RouteOverlay(
                    coordinates: coordinates,
                    project: layout.project,
                    routeColor: routeColor,
                    trimProgress: trimProgress,
                    cometOpacity: cometOpacity,
                    showStartMarker: showStartMarkers,
                    showEndMarker: showEndMarkers && authorAvatar == nil
                )
                .opacity(emphasis(Self.authorId))
                .animation(lineAnimation(0), value: trimProgress)
            }

            if let chosen = highlightedCompanion,
               let index = companionRoutes.firstIndex(where: { $0.id == chosen.id }) {
                companionLine(chosen, index: index)
            }

            // Mile ticks — author's line only; a crew map with everyone's
            // ticks buries the routes they annotate.
            if showsMileMarkers, let metrics = layout.authorMetrics {
                let marks = metrics.mileMarks()
                let labeled = metrics.totalMiles <= 6
                ForEach(marks) { mark in
                    mileTick(mark, labeled: labeled)
                }
                .opacity(emphasis(Self.authorId))
            }

            // Riders ride ON TOP of every line; the author's badge is topmost
            // for the same reason their line is.
            ForEach(Array(companionRoutes.enumerated()), id: \.element.id) { index, companion in
                if let avatar = rider(for: companion),
                   let metrics = layout.companionMetrics[companion.id] {
                    riderBadge(avatar, metrics: metrics, color: companion.color,
                               size: 20, animationIndex: index + 1)
                        .opacity(emphasis(companion.id))
                }
            }
            if let authorAvatar, let metrics = layout.authorMetrics {
                riderBadge(authorAvatar, metrics: metrics, color: routeColor,
                           size: 26, animationIndex: 0)
                    .opacity(emphasis(Self.authorId))
            }
        }
    }

    @ViewBuilder
    private func companionLine(_ companion: CompanionRoute, index: Int) -> some View {
        if let points = layout.companionPoints[companion.id] {
            RouteOverlay(
                coordinates: companion.coordinates,
                project: layout.project,
                routeColor: companion.color,
                trimProgress: trimProgress,
                cometOpacity: cometOpacity,
                showStartMarker: false,
                showEndMarker: showEndMarkers && rider(for: companion) == nil,
                overridePoints: points
            )
            .opacity(emphasis(companion.id))
            .animation(lineAnimation(index + 1), value: trimProgress)
        }
    }

    private func rider(for companion: CompanionRoute) -> RouteArtAvatar? {
        guard layout.companionMetrics[companion.id] != nil else { return nil }
        return companionAvatars[companion.id]
    }

    private func riderBadge(
        _ avatar: RouteArtAvatar,
        metrics: RouteArtMetrics,
        color: Color,
        size: CGFloat,
        animationIndex: Int
    ) -> some View {
        RouteAvatarBadge(
            name: avatar.name,
            image: avatar.imageURL.flatMap { avatarImages[$0] },
            size: size,
            ring: color
        )
        // Slightly small while riding; the end-marker spring pops it to full
        // size when the pack lands.
        .scaleEffect(showEndMarkers ? 1.0 : 0.92)
        .modifier(RouteRiderEffect(progress: trimProgress, metrics: metrics))
        .animation(lineAnimation(animationIndex), value: trimProgress)
        .opacity(ridersVisible ? 1 : 0)
    }

    private func mileTick(_ mark: RouteMileMark, labeled: Bool) -> some View {
        ZStack {
            Circle()
                .fill(routeColor)
                .frame(width: 7, height: 7)
                .overlay(Circle().stroke(.white.opacity(0.9), lineWidth: 1.2))
            if labeled {
                Text("\(mark.mile)")
                    .font(.system(size: 9, weight: .heavy, design: .rounded))
                    .foregroundColor(.white.opacity(0.9))
                    .shadow(color: .black.opacity(0.6), radius: 2)
                    .offset(y: -12)
            }
        }
        .modifier(TickRevealModifier(progress: trimProgress, threshold: mark.fraction))
        .animation(lineAnimation(0), value: trimProgress)
        .position(mark.point)
    }
}
