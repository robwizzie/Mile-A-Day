import SwiftUI
import CoreLocation

/// A raw walk/run in the unified feed — a run its author DIDN'T post. Renders
/// in the same visual language as PostCardView so the feed reads uniformly no
/// matter what a friend's device did: identical author header (avatar, name,
/// "Walk · 1.08 mi · 2d", menu), one compact (1:1) media slide — the GPS
/// route with the standard stats band, or the routeless card when there's no
/// route (the same faces an auto post draws) — and the same footer: actions
/// with FLYOVER/SPLITS trailing, then streak · time on one line. There is no PHOTO | MAP toggle here because
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
    @State private var showSplits = false
    /// The art card's ghost-map snapshot, kept for the zoom composite.
    @State private var routeArtSnapshot: RouteMapSnapshot?
    /// Same route-image share as the old floating route share chip.
    @State private var storyShare: MADStoryContent?

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
        // Moving time when the tracker recorded it (additive server field)
        // AND that clock covered the workout, elapsed otherwise — the same
        // rule the server applies before serving `moving_seconds` and the
        // one the author's own post bakes, so a card and its splits can't
        // report two different walks.
        DisplayPace.secondsPerMile(
            distanceMiles: distance,
            movingSeconds: entry.moving_seconds,
            elapsedSeconds: entry.total_duration
        )
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

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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
        // Same rule as PostCardView: chrome scales, media doesn't; above the
        // presentations so the flyover and share studio don't inherit it.
        .madTypeCap(.madCardCap)
        .fullScreenCover(item: $flyoverLaunch) { launch in
            RouteFlyoverPlayerView(launch: launch)
        }
        .sheet(item: $storyShare) { content in
            ShareStudioView(content: content)
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
                .madFont(size: 10, weight: .bold)
                .foregroundColor(accent)
            Text(headerSubtitle)
                .madFont(size: 12, weight: .medium, design: .rounded)
                .foregroundColor(.white.opacity(0.5))
                // Wraps only at accessibility sizes — see PostCardView.
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
        }
    }

    private var headerSubtitle: String {
        var parts = [PostCardView.activityNoun(entry.workout_type, pace: pace)]
        if distance > 0 {
            parts.append(entry.feed_role == "extra" ? "+\(distance.distanceFormatted) extra" : distance.distanceFormatted)
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
                            .madFont(size: 15, weight: .bold, design: .rounded)
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
                        .madFont(size: 16, weight: .bold, maxScale: 1.3)
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
        // On the MEDIA node: the card root owns the flyover cover and the
        // share sheet, and two presentations on one node drop one.
        .sheet(isPresented: $showSplits) {
            WorkoutSplitsSheet(
                bars: splitBars,
                stats: stats,
                workoutType: entry.workout_type,
                isIndoor: entry.is_indoor,
                ownerName: entry.is_self ? "You" : entry.displayName
            )
        }
    }

    /// FLYOVER · SPLITS, never on the media — one position on every card.
    /// See `PostCardView.actionRow`: they share the hype/comment/share row
    /// when it fits and drop to their own row above it when it doesn't.
    @ViewBuilder
    private func mediaControlChips(compactSplits: Bool) -> some View {
        if canPlayFlyover { flyoverChip }
        if hasSplits {
            SplitsChipButton(accent: accent, iconOnly: compactSplits) { showSplits = true }
        }
    }

    private var hasMediaControls: Bool { canPlayFlyover || hasSplits }

    private var splitBars: [WorkoutSplitBar] {
        WorkoutSplitBar.bars(from: entry.splits)
    }

    private var hasSplits: Bool { !splitBars.isEmpty }

    private func routeSlide(_ coords: [CLLocationCoordinate2D]) -> some View {
        RouteArtView(
            coordinates: coords,
            routeColor: accent,
            pointTimes: entry.route_times,
            authorAvatar: RouteArtAvatar(name: entry.displayName, imageURL: entry.profile_image_url),
            onSnapshot: { routeArtSnapshot = $0 },
            paletteDate: RelativeTime.date(from: entry.sort_ts),
            routeTrimmed: entry.route_trimmed ?? false
        )
        .frame(maxWidth: .infinity)
        // A raw workout never has a photo, so its map is the compact box —
        // the same card ~20% shorter (see `FeedMediaAspect`).
        .aspectRatio(FeedMediaAspect.compact, contentMode: .fit)
        .overlay {
            if let stats = overlayStats {
                RouteStatsBandOverlay(stats: stats, workoutType: entry.workout_type ?? "running")
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

    /// Own runs only — sharing a friend's card would export their walk (and,
    /// with a route, where they were). No `>= 2 coordinates` gate any more:
    /// the studio always has a face for a walk (Sticker at worst), and a
    /// treadmill mile was previously the one run you couldn't share at all.
    private var canShareRouteImage: Bool { entry.is_self }

    /// ▶ FLYOVER, top-left of the route slide — the shared chip.
    private var flyoverChip: some View {
        FlyoverChipButton(accent: accent) {
            guard var launch = FlyoverLaunch.forEntry(entry) else { return }
            launch.initiallyHyped = entry.is_hyped
            launch.onHype = { onHype() }
            flyoverLaunch = launch
        }
    }

    /// The route slide's floating zoom copy, on demand — the slide's own
    /// aspect at 2× the design width, so the lift is pixel-identical.
    private func routeZoomComposite(_ coords: [CLLocationCoordinate2D]) -> UIImage? {
        let type = entry.workout_type ?? "running"
        let stats = overlayStats
        return RouteArtView.zoomComposite(
            coordinates: coords,
            routeColor: accent,
            authorAvatar: RouteArtAvatar(name: entry.displayName, imageURL: entry.profile_image_url),
            underlay: routeArtSnapshot,
            paletteDate: RelativeTime.date(from: entry.sort_ts),
            routeTrimmed: entry.route_trimmed ?? false,
            size: CGSize(width: 720, height: 720 / FeedMediaAspect.compact)
        ) {
            if let stats {
                RouteStatsBandOverlay(stats: stats, workoutType: type)
                    .frame(width: 720, height: 720 / FeedMediaAspect.compact)
            }
        }
    }

    /// Routeless runs: the routeless card (track when HealthKit says indoor,
    /// the mile ribbon otherwise; Fun or Modern by the AUTHOR's style), fed
    /// by the entry's splits when the server sent them. Compact, like the
    /// route face — a raw workout has no photo to be 4:5 for.
    private var workoutCardSlide: some View {
        indoorCard(still: false)
            .frame(maxWidth: .infinity)
            .instagramZoomable(
                imageProvider: {
                    // One helper for live + zoom, so the pinch copy can't
                    // drift from the cell it lifted out of.
                    let renderer = ImageRenderer(content:
                        indoorCard(still: true)
                            .frame(width: FeedMediaAspect.designSize(FeedMediaAspect.compact).width,
                                   height: FeedMediaAspect.designSize(FeedMediaAspect.compact).height)
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
            authorFlamey: entry.author_flamey,
            isOwn: entry.is_self,
            aspect: FeedMediaAspect.compact,
            still: still
        )
    }

    /// The card's bottom, as tight as it reads: the actions row (FLYOVER /
    /// SPLITS trailing on it when they fit) and ONE quiet line under it for
    /// the streak and the time — they used to be two more rows.
    private var footer: some View {
        VStack(alignment: .leading, spacing: 0) {
            FeedActionRow(hasControls: hasMediaControls) {
                footerActions
            } controls: { compact in
                mediaControlChips(compactSplits: compact)
            }
            FeedMetaLine(streak: entry.day_streak, timestamp: absoluteTimestamp)
        }
        .padding(.horizontal, 2)
        .padding(.bottom, 2)
    }

    @ViewBuilder
    private var footerActions: some View {
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
    }

    /// When the walk happened — "OCT 1 · 1:25 PM", the post cards' format.
    private var absoluteTimestamp: String? {
        guard let date = RelativeTime.date(from: entry.sort_ts) else { return nil }
        return FeedTimestamp.timestamp(for: date)
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
                        .madFont(size: 14, weight: .heavy, design: .rounded, monospacedDigit: true)
                        .foregroundColor(.white.opacity(0.92))
                        .frame(minWidth: 24, minHeight: 44)
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
        TelemetryService.record(ShareTelemetry.opened)
        storyShare = MADStoryContent(
            distanceMiles: distance > 0 ? distance : nil,
            paceSecondsPerMile: pace,
            durationSeconds: entry.total_duration,
            // A raw workout card carries no streak (`stats` sets it nil) —
            // pass none rather than a number this card never showed.
            streak: nil,
            activityName: PostCardView.activityNoun(entry.workout_type, pace: pace),
            date: RelativeTime.date(from: entry.sort_ts),
            dateText: dateText,
            coordinates: entry.routeCoordinates ?? [],
            routeColor: accent,
            avatar: RouteArtAvatar(name: entry.displayName,
                                   imageURL: entry.profile_image_url)
        )
        storyShare?.workoutId = entry.workout_id
    }

    private func footerIconButton(
        icon: String,
        label: String?,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                // Secondary to Hype on purpose: a step smaller and dimmer than
                // the clap, so the row reads as one primary action and two
                // quiet ones of equal weight, with the counts kept.
                Image(systemName: icon)
                    .madFont(size: 20, weight: .regular, maxScale: 1.4)
                if let label {
                    Text(label)
                        .madFont(size: 13, weight: .semibold, design: .rounded, monospacedDigit: true)
                }
            }
            .foregroundColor(.white.opacity(0.62))
            // 44pt in both directions — the dimmer glyph is no reason for a
            // smaller target.
            .frame(minWidth: 44, minHeight: 44)
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
