import SwiftUI

/// A raw walk/run in the unified feed (no photo) — the auto activity card.
/// Shares the visual language of PostCardView: author header, a big
/// distance hero line, the GPS route map when the workout has one, a stat
/// strip, and a hype affordance. Double-tapping anywhere on the card body
/// hypes, same as photo posts.
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

    @State private var hypeBurst = 0
    /// Collapses duplicate reports of one physical double-tap (see
    /// PostCardView.lastDoubleTapAt).
    @State private var lastDoubleTapAt = Date.distantPast
    /// The map snapshot (~400×300) kept for the zoom's on-demand composite.
    @State private var routeSnapshot: UIImage?

    private var distance: Double { entry.distance ?? 0 }
    private var completedMile: Bool { distance >= ProgressCalculator.dailyGoalTolerance }
    private var accent: Color { Self.color(entry.workout_type) }

    var body: some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.sm) {
            header
            // Instagram behavior: double-tap ANYWHERE on the card body (hero
            // line, map, stat chips, spacing) hypes. Header/footer buttons
            // stay out so double-tapping them can't hype by accident.
            VStack(alignment: .leading, spacing: MADTheme.Spacing.sm) {
                heroLine
                if let coords = entry.routeCoordinates {
                    WorkoutRouteMapView(coordinates: coords, routeColor: accent,
                                        onSnapshot: { routeSnapshot = $0 })
                        .frame(maxWidth: .infinity)
                        // Proportional, not a fixed 160pt: the map scales with the
                        // card on every screen size instead of shrinking to a strip.
                        .aspectRatio(16.0 / 10.0, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                        )
                        // Pinch-zooms like a photo; the floating copy is
                        // composed on demand at the card's own 16:10 aspect
                        // so the lift matches the on-screen slide exactly.
                        .instagramZoomable(
                            imageProvider: {
                                guard let snapshot = routeSnapshot else { return nil }
                                return WorkoutRouteMapView.zoomComposite(
                                    snapshot: snapshot,
                                    coordinates: coords,
                                    routeColor: accent,
                                    size: CGSize(width: 720, height: 450)
                                ) { EmptyView() }
                            },
                            onDoubleTap: entry.is_self ? nil : doubleTapHype
                        )
                }
                statStrip
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

    private var header: some View {
        HStack(spacing: 10) {
            Button {
                onTapAuthor?()
            } label: {
                HStack(spacing: 10) {
                    AvatarView(name: entry.displayName, imageURL: entry.profile_image_url, size: 40)
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 5) {
                            Text(entry.displayName)
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                                .lineLimit(1)
                            if completedMile {
                                Image(systemName: "checkmark.seal.fill")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.green)
                            }
                        }
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
        }
    }

    /// The workout headline: what they did, with the distance as the hero
    /// number instead of a body-text line.
    private var heroLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(Self.verb(entry.workout_type))
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(.white.opacity(0.7))
            Text(String(format: "%.2f", distance))
                .font(.system(size: 30, weight: .black, design: .rounded))
                .monospacedDigit()
                .foregroundColor(.white)
            Text("mi")
                .font(.system(size: 16, weight: .heavy, design: .rounded))
                .foregroundColor(.white.opacity(0.7))
        }
        .padding(.horizontal, 2)
    }

    @ViewBuilder
    private var statStrip: some View {
        let items = statItems
        if !items.isEmpty {
            // Scrollable so four chips with long values (1:02:15, 10:30 /mi, …)
            // can never overflow the card on smaller screens.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(items, id: \.0) { item in
                        HStack(spacing: 5) {
                            Image(systemName: item.1)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.orange)
                            Text(item.2)
                                .font(.system(size: 13, weight: .heavy, design: .rounded))
                                .monospacedDigit()
                                .foregroundColor(.white.opacity(0.9))
                        }
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Capsule().fill(Color.white.opacity(0.07)))
                    }
                }
                .padding(.horizontal, 2)
            }
        }
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

    // (label-key, icon, value) for time / pace / calories / steps when present.
    private var statItems: [(String, String, String)] {
        var out: [(String, String, String)] = []
        if let d = entry.total_duration, d > 0 {
            out.append(("time", "clock.fill", RunStatsStickerView.durationText(d)))
            if distance > 0 {
                out.append(("pace", "speedometer", "\(RunStatsStickerView.paceText(d / distance)) /mi"))
            }
        }
        if let c = entry.calories, c > 0 {
            out.append(("cal", "bolt.fill", "\(Int(c.rounded())) cal"))
        }
        if let s = entry.steps, s > 0 {
            out.append(("steps", "shoeprints.fill", s.formatted(.number.grouping(.automatic))))
        }
        return out
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
