import SwiftUI
import CoreLocation

/// A raw walk/run in the unified feed — a run its author DIDN'T post. Renders
/// in the same visual language as PostCardView so the feed reads uniformly no
/// matter what a friend's device did: identical author header (avatar, name,
/// time, type chip, menu), a full 4:5 media slide — the GPS route with the
/// standard stats band, or the branded workout card when there's no route
/// (the exact face an auto post bakes into its image) — the same stat strip,
/// and the same hype/comment footer. The functional difference stays honest:
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
    /// The map snapshot (~400×300) kept for the zoom's on-demand composite.
    @State private var routeSnapshot: UIImage?

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
        guard let duration = entry.total_duration, duration > 0, distance > 0 else { return nil }
        return duration / distance
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
                PostStatStrip(stats: stats).padding(.horizontal, 2)
            }
            .contentShape(Rectangle())
            .simultaneousGesture(
                TapGesture(count: 2).onEnded { doubleTapHype() }
            )
            footer
        }
        .padding(MADTheme.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        // Card-level so the burst plays centered over the whole card.
        .overlay(HypeBurstView(trigger: hypeBurst))
    }

    /// Shared by double-tap and the footer HypeButton, so the button plays
    /// the same clap burst the double-tap does.
    private func celebrateAndHype() {
        hypeBurst += 1
        MADHaptics.action()
        if !entry.is_hyped {
            onHype()
        }
    }

    private func doubleTapHype() {
        guard !entry.is_self else { return }
        let now = Date()
        guard now.timeIntervalSince(lastDoubleTapAt) > 0.35 else { return }
        lastDoubleTapAt = now
        celebrateAndHype()
    }

    /// Same header as PostCardView: avatar + name + time on the left, the
    /// workout-type chip and (for others) the "…" menu on the right.
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
                        Text(entry.relativeTime)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.5))
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(onTapAuthor == nil)
            Spacer()
            Image(systemName: Self.icon(entry.workout_type))
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(accent)
                .frame(width: 30, height: 30)
                .background(Circle().fill(accent.opacity(0.15)))
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
    @ViewBuilder
    private var media: some View {
        if let coords = entry.routeCoordinates {
            routeSlide(coords)
        } else {
            workoutCardSlide
        }
    }

    private func routeSlide(_ coords: [CLLocationCoordinate2D]) -> some View {
        WorkoutRouteMapView(
            coordinates: coords,
            routeColor: accent,
            onSnapshot: { routeSnapshot = $0 }
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
        // demand from the retained snapshot.
        .instagramZoomable(
            imageProvider: { routeZoomComposite(coords) },
            onDoubleTap: entry.is_self ? nil : doubleTapHype
        )
    }

    /// The route slide's floating zoom copy, on demand — 720×900 keeps the
    /// post slides' 4:5 so the lift is pixel-identical.
    private func routeZoomComposite(_ coords: [CLLocationCoordinate2D]) -> UIImage? {
        guard let snapshot = routeSnapshot else { return nil }
        let type = entry.workout_type ?? "running"
        let stats = overlayStats
        return WorkoutRouteMapView.zoomComposite(
            snapshot: snapshot,
            coordinates: coords,
            routeColor: accent,
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

    /// Routeless runs: the branded stats card, live-rendered — identical to
    /// the image an auto post would have baked, so posted and unposted runs
    /// are indistinguishable at a glance.
    private var workoutCardSlide: some View {
        FeedWorkoutCard(stats: stats, workoutType: entry.workout_type)
            .frame(maxWidth: .infinity)
            .aspectRatio(4.0 / 5.0, contentMode: .fit)
            .instagramZoomable(
                imageProvider: {
                    let renderer = ImageRenderer(content:
                        FeedWorkoutCard(stats: stats, workoutType: entry.workout_type)
                            .frame(width: RunStatsCardView.designSize.width,
                                   height: RunStatsCardView.designSize.height)
                    )
                    renderer.scale = 2
                    renderer.isOpaque = true
                    return renderer.uiImage
                },
                onDoubleTap: entry.is_self ? nil : doubleTapHype
            )
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if let count = entry.hype_count, count > 0 {
                Button { onTapHypeCount?() } label: {
                    HypeTally(count: count, showsLabel: true)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(onTapHypeCount == nil)
            }
            Button { onOpenComments?() } label: {
                HStack(spacing: 5) {
                    Image(systemName: "bubble.right")
                        .font(.system(size: 15, weight: .semibold))
                    if let count = entry.comment_count, count > 0 {
                        Text("\(count)")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                    }
                }
                .foregroundColor(.white.opacity(0.7))
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(onOpenComments == nil)
            Spacer()
            if !entry.is_self {
                HypeButton(
                    isHyped: entry.is_hyped,
                    isBusy: isHyping,
                    isOutOfHypes: isOutOfHypes && !entry.is_hyped,
                    action: celebrateAndHype
                )
            }
        }
        .padding(.horizontal, 2)
        .padding(.bottom, 2)
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
