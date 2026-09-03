import SwiftUI
import CoreLocation

/// A raw walk/run in the unified feed — a run its author DIDN'T post. Renders
/// in the same visual language as PostCardView so the feed reads uniformly no
/// matter what a friend's device did: identical author header (avatar, name,
/// "Walk · 1.08 mi · 2d", menu), a full 4:5 media slide — the GPS route with
/// the standard stats band and the Flyover chip, or the indoor card when
/// there's no route (the exact face an auto post bakes into its image) — and
/// the same hype/comment footer. There is no PHOTO | MAP toggle here because
/// a raw run has no photo: the map IS the card. The functional difference stays honest:
/// no photo or caption — those belong to posts the author chose to make.
/// Double-tapping anywhere on the body hypes, like posts.
struct ActivityCardView: View {
    let entry: FeedEntry
    var isHyping: Bool = false
    /// Daily hype allowance spent (never true for unlimited roles) — dims the
    /// unspent Hype button, same as the friends list.
    var isOutOfHypes: Bool = false
    let onHype: () -> Void
    /// Tap the author's avatar or name to open their profile.
    var onTapAuthor: (() -> Void)? = nil
    /// Tap the hype tally to see who hyped (Instagram-likes style).
    var onTapHypeCount: (() -> Void)? = nil
    /// Open the Instagram-style comments sheet.
    var onOpenComments: (() -> Void)? = nil
    /// Block the author — the "…" menu, matching post cards (others' only).
    var onBlock: (() -> Void)? = nil

    @State private var hypeBurst = 0
    /// Collapses duplicate reports of one physical double-tap (see
    /// PostCardView.lastDoubleTapAt).
    @State private var lastDoubleTapAt = Date.distantPast
    /// Set by the route slide's Flyover chip (item-based cover, per ios.md).
    @State private var flyoverLaunch: FlyoverLaunch?
    /// The art card's ghost-map snapshot, kept for the zoom composite.
    @State private var routeArtSnapshot: RouteMapSnapshot?
    /// Same route-image share as the old floating route share chip.
    @State private var routeShare: RouteSharePayload?

    private var distance: Double { entry.distance ?? 0 }
    private var accent: Color { Self.color(entry.workout_type) }

    /// The run's stats shaped exactly like a post's snapshot, so the shared
    /// components (stats band, workout card, stat strip) render identically
    /// to a posted run.
    private var stats: PostStats {
        PostStats(
            distance: distance > 0 ? distance : nil,
            pace: pace,
            duration: entry.total_duration,
            streak: nil,
            date: dateText,
            calories: entry.calories,
            steps: entry.steps
        )
    }

    private var pace: Double? {
        // Moving time when the tracker recorded it (additive server field),
        // elapsed otherwise — the same fallback the server bakes into
        // restated snapshots, so post and workout cards agree.
        guard let divisor = entry.moving_seconds ?? entry.total_duration,
              divisor > 0, distance > 0 else { return nil }
        return divisor / distance
    }

    /// Stats band input for the route slide — same band the auto post bakes
    /// into its image, so a raw run's map reads identically to a posted one.
    private var overlayStats: RunStatsInput? {
        guard distance > 0 else { return nil }
        return RunStatsInput(
            distance: distance,
            paceSecondsPerMile: pace,
            durationSeconds: entry.total_duration,
            streak: nil,
            calories: entry.calories,
            steps: entry.steps,
            workoutId: nil,
            dateText: dateText
        )
    }

    private var dateText: String? {
        guard let date = RelativeTime.date(from: entry.sort_ts) else { return nil }
        return Self.cardDateFormatter.string(from: date)
    }

    private static let cardDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.sm) {
            header
            // Instagram behavior: double-tap ANYWHERE on the card body hypes.
            // Header/footer buttons stay out so double-tapping them can't
            // hype by accident.
            VStack(alignment: .leading, spacing: MADTheme.Spacing.sm) {
                media
                // Only when the mile took several goes — a normal single-workout
                // day renders exactly as it did before.
                if entry.isStitchedMile, let segments = entry.segments, segments.count > 1 {
                    MileSegmentStrip(segments: segments, accent: accent)
                }
            }
            .contentShape(Rectangle())
            .simultaneousGesture(
                TapGesture(count: 2).onEnded { doubleTapHype() }
            )
            footer
        }
        .padding(MADTheme.Spacing.sm + 2)
        .background(
            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        // Card-level so the burst plays centered over the whole card.
        .overlay(HypeBurstView(trigger: hypeBurst))
        .fullScreenCover(item: $flyoverLaunch) { launch in
            RouteFlyoverPlayerView(launch: launch)
        }
        .sheet(item: $routeShare) { payload in
            ShareSheet(items: [payload.image])
        }
    }

    /// Footer button: toggle hype with the same clap burst the double-tap uses.
    private func celebrateAndHype() {
        hypeBurst += 1
        MADHaptics.action()
        onHype()
    }

    private func doubleTapHype() {
        let now = Date()
        guard now.timeIntervalSince(lastDoubleTapAt) > 0.35 else { return }
        lastDoubleTapAt = now
        hypeBurst += 1
        MADHaptics.action()
        if !entry.is_hyped { onHype() }
    }

    /// "Walk · 1.08 mi · 2d" — the same line PostCardView draws under the
    /// name, with the feed role's framing on the distance.
    private var subtitleLine: some View {
        HStack(spacing: 4) {
            Image(systemName: Self.icon(entry.workout_type, paceSecondsPerMile: pace))
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(accent)
            Text(headerSubtitle)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.5))
                .lineLimit(1)
        }
    }

    private var headerSubtitle: String {
        var parts = [PostCardView.activityNoun(entry.workout_type, pace: pace)]
        if distance > 0 {
            parts.append(entry.feed_role == "extra" ? "+\(distance.milesText) mi extra" : "\(distance.milesText) mi")
        }
        parts.append(entry.relativeTime)
        return parts.joined(separator: " · ")
    }

    /// Same header as PostCardView: avatar + name + subtitle on the left and
    /// (for others) the "…" menu on the right.
    private var header: some View {
        HStack(spacing: 10) {
            Button {
                onTapAuthor?()
            } label: {
                HStack(spacing: 10) {
                    AvatarView(name: entry.displayName, imageURL: entry.profile_image_url, size: 40)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(entry.displayName)
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        subtitleLine
                    }
                }
            }
            .buttonStyle(.plain)
            .allowsHitTesting(onTapAuthor != nil)
            Spacer()
            if !entry.is_self, onBlock != nil {
                Menu {
                    Button(role: .destructive) { onBlock?() } label: {
                        Label("Block \(entry.displayName)", systemImage: "hand.raised")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white.opacity(0.6))
                        .padding(6)
                        .contentShape(Rectangle())
                }
            }
        }
    }

    /// The run as a full 4:5 slide, exactly like a post's media: the route
    /// map with the standard stats band when a GPS trace exists, otherwise
    /// the branded workout card (the same face auto posts bake).
    private var media: some View {
        Group {
            if let coords = entry.routeCoordinates {
                routeSlide(coords)
            } else {
                workoutCardSlide
            }
        }
        // Overlaid on the container — AFTER the slide's `.instagramZoomable`
        // — or the zoom gesture host eats the chip's taps.
        .overlay(alignment: .topLeading) {
            if canPlayFlyover {
                flyoverChip.padding(10)
            }
        }
    }

    private func routeSlide(_ coords: [CLLocationCoordinate2D]) -> some View {
        RouteArtView(
            coordinates: coords,
            routeColor: accent,
            authorAvatar: RouteArtAvatar(name: entry.displayName, imageURL: entry.profile_image_url),
            onSnapshot: { routeArtSnapshot = $0 },
            paletteDate: RelativeTime.date(from: entry.sort_ts)
        )
        .frame(maxWidth: .infinity)
        .aspectRatio(4.0 / 5.0, contentMode: .fit)
        .overlay {
            if let stats = overlayStats {
                // Lays out at the baked card's 360×450 design size; the slide
                // is the same 4:5, so scaling by width alone reproduces the
                // auto post's look pixel-for-pixel (see PostCardView).
                GeometryReader { geo in
                    RouteStatsOverlayView(stats: stats, workoutType: entry.workout_type ?? "running")
                        .scaleEffect(geo.size.width / RunStatsCardView.designSize.width,
                                     anchor: .topLeading)
                }
                .allowsHitTesting(false)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium, style: .continuous))
        // Same pinch-zoom as post slides; the floating copy is composed on
        // demand at pinch-begin.
        .instagramZoomable(
            imageProvider: { routeZoomComposite(coords) },
            onDoubleTap: doubleTapHype
        )
    }

    private var canPlayFlyover: Bool {
        (entry.routeCoordinates?.count ?? 0) >= 2 && (entry.is_self || entry.flyover_allowed != false)
    }

    private var canShareRouteImage: Bool {
        entry.is_self && (entry.routeCoordinates?.count ?? 0) >= 2
    }

    /// ▶ FLYOVER, top-left of the route slide — the shared chip.
    private var flyoverChip: some View {
        FlyoverChipButton(accent: accent) {
            guard var launch = FlyoverLaunch.forEntry(entry) else { return }
            launch.initiallyHyped = entry.is_hyped
            launch.onHype = { onHype() }
            flyoverLaunch = launch
        }
    }

    /// The route slide's floating zoom copy, on demand — 720×900 keeps the
    /// post slides' 4:5 so the lift is pixel-identical.
    private func routeZoomComposite(_ coords: [CLLocationCoordinate2D]) -> UIImage? {
        let type = entry.workout_type ?? "running"
        let stats = overlayStats
        return RouteArtView.zoomComposite(
            coordinates: coords,
            routeColor: accent,
            authorAvatar: RouteArtAvatar(name: entry.displayName, imageURL: entry.profile_image_url),
            underlay: routeArtSnapshot,
            paletteDate: RelativeTime.date(from: entry.sort_ts),
            size: CGSize(width: 720, height: 900)
        ) {
            if let stats {
                RouteStatsOverlayView(stats: stats, workoutType: type)
                    .frame(width: RunStatsCardView.designSize.width,
                           height: RunStatsCardView.designSize.height,
                           alignment: .topLeading)
                    .scaleEffect(720 / RunStatsCardView.designSize.width, anchor: .topLeading)
            }
        }
    }

    /// Routeless runs: the animated indoor card (track or treadmill face by
    /// the viewer's dashboard style), fed by the entry's splits when the
    /// server sent them.
    private var workoutCardSlide: some View {
        indoorCard(still: false)
            .frame(maxWidth: .infinity)
            .aspectRatio(4.0 / 5.0, contentMode: .fit)
            .instagramZoomable(
                imageProvider: {
                    // One helper for live + zoom, so the pinch copy can't
                    // drift from the cell it lifted out of.
                    let renderer = ImageRenderer(content:
                        indoorCard(still: true)
                            .frame(width: RunStatsCardView.designSize.width,
                                   height: RunStatsCardView.designSize.height)
                    )
                    renderer.scale = 2
                    renderer.isOpaque = true
                    return renderer.uiImage
                },
                onDoubleTap: doubleTapHype
            )
    }

    private func indoorCard(still: Bool) -> IndoorWorkoutCard {
        IndoorWorkoutCard(
            stats: stats,
            workoutType: entry.workout_type,
            splits: WorkoutSplitBar.bars(from: entry.splits),
            avatar: RouteArtAvatar(name: entry.displayName, imageURL: entry.profile_image_url),
            isIndoor: entry.is_indoor,
            still: still
        )
    }

    private var footer: some View {
        HStack(alignment: .center, spacing: 14) {
            hypeControl
            footerIconButton(
                icon: "bubble.right",
                label: commentActionLabel,
                accessibilityLabel: "Comments",
                action: { onOpenComments?() }
            )
            .disabled(onOpenComments == nil)
            if canShareRouteImage {
                footerIconButton(
                    icon: "paperplane",
                    label: nil,
                    accessibilityLabel: "Share route",
                    action: shareRoute
                )
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 2)
        .padding(.bottom, 2)
    }

    /// Clap + count, exactly as on a post card: the clap hypes (your own run
    /// too), the count opens who hyped.
    private var hypeControl: some View {
        HStack(spacing: 4) {
            HypeButton(
                isHyped: entry.is_hyped,
                isBusy: isHyping,
                isOutOfHypes: isOutOfHypes && !entry.is_hyped,
                style: .compactIcon,
                action: celebrateAndHype
            )
            if let count = entry.hype_count, count > 0 {
                Button {
                    onTapHypeCount?()
                } label: {
                    Text("\(count)")
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(.white.opacity(0.92))
                        .frame(minHeight: 40)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(onTapHypeCount == nil)
                .accessibilityLabel("\(count) hype\(count == 1 ? "" : "s")")
            }
        }
    }

    private var commentActionLabel: String? {
        guard let count = entry.comment_count, count > 0 else { return nil }
        return "\(count)"
    }

    private func shareRoute() {
        guard let coords = entry.routeCoordinates,
              let image = routeZoomComposite(coords) else { return }
        routeShare = RouteSharePayload(image: image)
    }

    private func footerIconButton(
        icon: String,
        label: String?,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .medium))
                if let label {
                    Text(label)
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                }
            }
            .foregroundColor(.white.opacity(0.92))
            .frame(minWidth: 36, minHeight: 40)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    // MARK: workout type styling
    static func verb(_ type: String?) -> String {
        switch (type ?? "").lowercased() {
        case "running": return "Ran"
        case "walking": return "Walked"
        case "hiking": return "Hiked"
        case "cycling": return "Cycled"
        default: return "Moved"
        }
    }

    /// Pace-aware fallback for workouts third-party bridges stamp as `.other`
    /// (Fitbit via Google Health writes walks that way, which is how a walk
    /// card ends up saying "MOVED"). Display-only inference, never scoring:
    /// 13:30/mi is the walk/run divide.
    static func verb(_ type: String?, paceSecondsPerMile pace: Double?) -> String {
        let base = verb(type)
        guard base == "Moved", let pace, pace > 0 else { return base }
        return pace >= 810 ? "Walked" : "Ran"
    }

    static func icon(_ type: String?, paceSecondsPerMile pace: Double?) -> String {
        let base = icon(type)
        guard verb(type) == "Moved", let pace, pace > 0 else { return base }
        return pace >= 810 ? "figure.walk" : "figure.run"
    }
    static func icon(_ type: String?) -> String {
        switch (type ?? "").lowercased() {
        case "running": return "figure.run"
        case "walking": return "figure.walk"
        case "hiking": return "figure.hiking"
        case "cycling": return "figure.outdoor.cycle"
        default: return "figure.run"
        }
    }
    static func color(_ type: String?) -> Color {
        // Delegates to the app-wide language (walks BLUE, runs red) so the
        // feed can never drift from the rest of the app again.
        MADTheme.workoutColor(type)
    }
}
