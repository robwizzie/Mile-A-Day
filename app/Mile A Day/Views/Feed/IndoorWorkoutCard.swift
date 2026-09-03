import SwiftUI

/// The routeless workout's 4:5 card, animated — what draws where a route slide
/// would when there is no GPS trace to draw.
///
/// Deliberately never says "indoor": a card can be routeless because the walk
/// was on a treadmill OR because the owner shares no maps, and the two must
/// read identically (the same rule the buddy wizard's copy follows).
///
/// One face for everyone — the stadium track. The VIEWER's
/// `DashboardStylePreference` (the runner's style isn't on the wire) only
/// decides whether Flamey stands trackside cheering: the Fun dashboard's
/// mascot joins the scene, the Modern one keeps it clean. (An earlier build
/// had a whole separate treadmill face for Fun; retired — one scene, one
/// small delight.)
struct IndoorWorkoutCard: View {
    let stats: PostStats
    let workoutType: String?
    var splits: [WorkoutSplitBar] = []
    var avatar: RouteArtAvatar? = nil
    /// HealthKit's indoor flag from the wire — nil (older data) means UNKNOWN
    /// and the card makes no claim; routeless alone is never "indoor".
    var isIndoor: Bool? = nil
    /// Final frame for `ImageRenderer` (zoom composites, baked auto-post
    /// images) — no tasks, no motion.
    var still: Bool = false

    var body: some View {
        IndoorTrackCard(
            stats: stats,
            workoutType: workoutType,
            splits: splits,
            avatar: avatar,
            isIndoor: isIndoor,
            cheerleader: DashboardStylePreference.current == .fun,
            still: still
        )
    }
}

/// The shared chrome both indoor faces render inside: canvas background,
/// activity capsule + date header, count-up MILES headline, the pace wave,
/// one row of stat tiles, and the brand mark — the `FeedWorkoutCard` language
/// with a hero scene in the middle.
struct IndoorCardScaffold<Hero: View>: View {
    let stats: PostStats
    let workoutType: String?
    var splits: [WorkoutSplitBar] = []
    /// nil = unknown — the chip simply doesn't draw.
    var isIndoor: Bool? = nil
    var still: Bool = false
    /// How long the headline takes to count up — each face passes its hero's
    /// own duration so number and scene land together.
    var revealDuration: Double = 1.6
    @ViewBuilder var hero: () -> Hero

    /// Flipped once outside `withAnimation`; the headline's Animatable
    /// modifier interpolates on its own `.animation(_:value:)` (ios.md: a
    /// plain Text on this state would only ever show 0 and the total).
    @State private var revealed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Reduce Motion renders the finished frame, same as a baked still.
    private var effectiveStill: Bool { still || reduceMotion }

    private var accent: Color { ActivityCardView.color(workoutType) }
    // Pace-aware: a third-party bridge stamping a walk as `.other` would
    // otherwise print "MOVED" on a card that plainly shows a walk's pace.
    private var icon: String { ActivityCardView.icon(workoutType, paceSecondsPerMile: stats.pace) }
    private var verb: String { ActivityCardView.verb(workoutType, paceSecondsPerMile: stats.pace) }
    private var distance: Double { max(0, stats.distance ?? 0) }

    var body: some View {
        ZStack {
            ArtCanvasBackground(accent: accent)

            VStack(spacing: 0) {
                HStack {
                    HStack(spacing: 5) {
                        Image(systemName: icon).font(.system(size: 12, weight: .bold))
                        Text(verb.uppercased())
                            .font(.system(size: 11, weight: .heavy, design: .rounded))
                            .tracking(1.4)
                    }
                    .foregroundColor(accent)
                    .padding(.horizontal, 11).padding(.vertical, 6)
                    .background(Capsule().fill(accent.opacity(0.15)))
                    // Indoor/outdoor, only when the data actually says —
                    // nil (older rows) makes no claim, because a blank route
                    // can also be a privacy choice.
                    if let isIndoor {
                        HStack(spacing: 4) {
                            Image(systemName: isIndoor ? "house.fill" : "sun.max.fill")
                                .font(.system(size: 10, weight: .bold))
                            Text(isIndoor ? "INDOOR" : "OUTDOOR")
                                .font(.system(size: 10, weight: .heavy, design: .rounded))
                                .tracking(1.2)
                        }
                        .foregroundColor(.white.opacity(0.65))
                        .padding(.horizontal, 9).padding(.vertical, 6)
                        .background(Capsule().fill(Color.white.opacity(0.08)))
                        .padding(.leading, 6)
                    }
                    Spacer()
                    if let date = stats.date, !date.isEmpty {
                        Text(date)
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundColor(.white.opacity(0.55))
                    }
                }

                Spacer(minLength: 6)

                hero()
                    .frame(maxWidth: .infinity)

                Spacer(minLength: 6)

                // Layout against the FINAL number so nothing shifts while the
                // interpolated overlay counts up under it.
                Text(distance.milesText)
                    .modifier(CountUpNumberModifier(
                        value: (effectiveStill || revealed) ? distance : 0, format: "%.2f",
                        floorsMiles: true))
                    .font(.system(size: 46, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .monospacedDigit()
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .shadow(color: .black.opacity(0.4), radius: 6, y: 3)
                    .animation(effectiveStill ? nil : .easeOut(duration: revealDuration), value: revealed)
                Text("MILES")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .tracking(5)
                    .foregroundColor(.white.opacity(0.6))

                if splits.count >= 2 {
                    PaceWaveStrip(bars: splits, accent: accent, still: effectiveStill)
                        .padding(.top, 8)
                        .padding(.horizontal, 6)
                }

                Spacer(minLength: 8)

                WorkoutStatTileGrid(stats: stats, accent: accent, maxTiles: 2)

                MADLogoMark(size: 28, opacity: 0.9)
                    .padding(.top, 12)
            }
            .padding(18)
            // Same as FeedWorkoutCard: keep the brand row above the paging
            // carousel's page dots.
            .padding(.bottom, 16)
        }
        .aspectRatio(4.0 / 5.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium, style: .continuous))
        .task {
            guard !effectiveStill, !revealed else { return }
            try? await Task.sleep(for: .milliseconds(300))
            revealed = true
        }
    }
}

/// A number that moves DURING an animation: the driving state only ever shows
/// a body its endpoints, so the interpolated value has to live in
/// `animatableData` (same mechanism as `RouteRiderEffect`). The content is the
/// laid-out placeholder (render the FINAL value into it, monospaced digits) and
/// this overlays the counting copy — font/colour propagate to the overlay, so
/// style once, after the modifier.
struct CountUpNumberModifier: ViewModifier, Animatable {
    var value: Double
    let format: String

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    /// MILES displays floor to 2 decimals (the ios.md `milesFloor2` rule —
    /// `%.2f` rounds 0.995 to "1.00" the dashboard prints as 0.99). True on
    /// every miles count-up; false for laps and other non-mile numbers.
    var floorsMiles: Bool = false

    func body(content: Content) -> some View {
        let shown = max(0, floorsMiles ? value.milesFloor2 : value)
        return content
            .hidden()
            .overlay(Text(String(format: format, shown)))
    }
}
