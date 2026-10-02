import SwiftUI

/// The aspect ratios a feed card's media box can take.
///
/// PHOTOS are 4:5 — that's what they're composed for, and every page of a
/// carousel that holds one must be that size too (the TabView sizes once). A
/// card with NO photo page (a raw walk, an auto card, a routeless workout) is
/// drawn by us at whatever size we ask for, so it asks for less: 1:1 shows the
/// same card ~20% shorter and puts more of the feed on screen at once.
enum FeedMediaAspect {
    static let photo: CGFloat = 4.0 / 5.0
    static let compact: CGFloat = 1.0

    /// The zoom copy's design size for an aspect — 360 wide like
    /// `RunStatsCardView.designSize`, so the floating copy is the live card.
    static func designSize(_ aspect: CGFloat) -> CGSize {
        CGSize(width: 360, height: (360 / max(aspect, 0.1)).rounded())
    }
}

/// Whose look a routeless card wears — the AUTHOR's dashboard style.
///
/// A friend on Fun gets the playful card with THEIR Flamey (dressed as they
/// dressed him, named what they named him) cheering the walk on; a friend on
/// Modern gets the clean card with no mascot. The signal is `author_flamey`,
/// which the server sends ONLY for an author whose `dashboard_style` is Fun —
/// so an older server (no key for anyone) reads as Modern for everyone, the
/// calm default. Your OWN card follows your own current style from local
/// facts, which is fresher than the post's copy.
enum RoutelessCardStyle {
    case fun(look: FlameyLook, name: String?)
    case modern

    var isFun: Bool {
        if case .fun = self { return true }
        return false
    }

    @MainActor
    static func resolve(authorFlamey: AuthorFlamey?, isOwn: Bool) -> RoutelessCardStyle {
        if isOwn {
            // `FlameyFacts.look` is nil on Modern — exactly the switch wanted.
            guard let own = FlameyFacts.look(detail: .compact) else { return .modern }
            return .fun(look: own, name: FlameyFacts.name)
        }
        guard let authorFlamey else { return .modern }
        return .fun(look: authorFlamey.resolved(), name: authorFlamey.displayName)
    }
}

/// The routeless workout's card — what draws where a route slide would when
/// there is no GPS trace to draw.
///
/// TWO scenes, chosen by what the data actually says:
/// - `is_indoor == true` — a treadmill or indoor track, so a TRACK: the
///   distance as laps of a 400 m lane with the runner's badge circling it.
/// - anything else (outdoor, or unknown) — a walk whose map simply isn't
///   here, so NO track: an outdoor walk read as "8.8 LAPS" contradicts
///   itself. It's the distance as a mile-by-mile ribbon instead, each mile
///   tinted by its pace. Deliberately silent about WHY there's no map:
///   routeless can be a privacy choice (maps off, stealth) or a device that
///   recorded no trace, and a friend must not be able to tell those apart.
///   It never says "map hidden"; it says OUTDOOR only when HealthKit
///   flagged the walk outdoor (the flag, never the missing map).
///
/// Each scene comes in the AUTHOR's style (`RoutelessCardStyle`).
struct IndoorWorkoutCard: View {
    let stats: PostStats
    let workoutType: String?
    var splits: [WorkoutSplitBar] = []
    var avatar: RouteArtAvatar? = nil
    /// HealthKit's indoor flag from the wire — nil (older data) means UNKNOWN,
    /// which draws the ribbon: routeless alone is never "indoor".
    var isIndoor: Bool? = nil
    /// The author's Flamey off the wire (nil = not a Fun author / older
    /// server ⇒ the Modern card).
    var authorFlamey: AuthorFlamey? = nil
    /// The viewer IS the author — their own current style and look.
    var isOwn: Bool = false
    /// 1:1 when this is the card's only face, 4:5 beside a photo.
    var aspect: CGFloat = FeedMediaAspect.photo
    /// Final frame for `ImageRenderer` (the pinch-zoom copy) — no tasks, no
    /// motion.
    var still: Bool = false

    var body: some View {
        let style = RoutelessCardStyle.resolve(authorFlamey: authorFlamey, isOwn: isOwn)
        let accent = ActivityCardView.color(workoutType)
        Group {
            if isIndoor == true {
                IndoorTrackCard(stats: stats, workoutType: workoutType, splits: splits,
                                avatar: avatar, style: style, still: still)
            } else {
                DistanceRibbonCard(stats: stats, workoutType: workoutType, splits: splits,
                                   avatar: avatar, style: style, isIndoor: isIndoor, still: still)
            }
        }
        // Beside a photo this is a page of the carousel, whose page dots sit
        // over the bottom edge — keep the last row clear of them (the 1:1
        // card is always alone, so it has no dots).
        .padding(.bottom, aspect < 0.9 ? 14 : 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoutelessCardBackground(style: style, accent: accent))
        .aspectRatio(aspect, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        var parts = [ActivityCardView.verb(workoutType, paceSecondsPerMile: stats.pace)]
        if let d = stats.distance, d > 0 { parts.append("\(d.milesText) miles") }
        if let p = stats.pace, p > 0 { parts.append("pace \(RunStatsStickerView.paceText(p)) per mile") }
        if let t = stats.duration, t > 0 { parts.append("time \(RunStatsStickerView.durationText(t))") }
        if let isIndoor { parts.append(isIndoor ? "indoors" : "outdoors") }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Shared chrome

/// The canvas. Fun is the Route Art canvas (dot grid, activity glow) — the
/// same ground a Fun author's route cards stand on. Modern is a flat graphite
/// ground with one quiet accent wash: no texture, nothing that isn't data.
struct RoutelessCardBackground: View {
    let style: RoutelessCardStyle
    let accent: Color

    var body: some View {
        if style.isFun {
            ArtCanvasBackground(accent: accent)
        } else {
            ZStack {
                LinearGradient(colors: [Color(white: 0.10), Color(white: 0.035)],
                               startPoint: .top, endPoint: .bottom)
                RadialGradient(colors: [accent.opacity(0.16), .clear],
                               center: .init(x: 0.85, y: 0.05), startRadius: 4, endRadius: 260)
            }
        }
    }
}

/// Type for the two styles: Fun is rounded and heavy (the mascot's voice);
/// Modern is SF Pro, tighter, a weight lighter — the Modern dashboard's.
struct RoutelessType {
    let style: RoutelessCardStyle
    var design: Font.Design { style.isFun ? .rounded : .default }
    var heroWeight: Font.Weight { style.isFun ? .black : .bold }
    var valueWeight: Font.Weight { style.isFun ? .heavy : .semibold }
}

/// "🚶 WALKED" (+ "INDOOR" on the track scene). No date: the header above the
/// media already says "2h" and the footer prints the exact time.
struct RoutelessHeaderRow: View {
    let style: RoutelessCardStyle
    let accent: Color
    let workoutType: String?
    let pace: Double?
    /// HealthKit's indoor flag: true ⇒ INDOOR, false ⇒ OUTDOOR, nil ⇒ no
    /// chip. Only the FLAG may say where a walk was — a missing map can be a
    /// privacy choice, so routeless alone never claims either.
    var isIndoor: Bool? = nil

    var body: some View {
        let type = RoutelessType(style: style)
        HStack(spacing: 6) {
            HStack(spacing: 5) {
                // Pace-aware: a third-party bridge stamping a walk as `.other`
                // would otherwise print "MOVED" on a card that plainly shows a
                // walk's pace.
                Image(systemName: ActivityCardView.icon(workoutType, paceSecondsPerMile: pace))
                    .font(.system(size: 11, weight: .bold))
                Text(ActivityCardView.verb(workoutType, paceSecondsPerMile: pace).uppercased())
                    .font(.system(size: 11, weight: .heavy, design: type.design))
                    .tracking(1.4)
            }
            .foregroundColor(accent)
            .padding(.horizontal, style.isFun ? 10 : 0)
            .padding(.vertical, style.isFun ? 5 : 0)
            .background(Capsule().fill(style.isFun ? accent.opacity(0.16) : .clear))
            Spacer(minLength: 0)
            if let isIndoor {
                // Same height as the activity capsule, tinted so it reads at
                // a glance: outdoor in the success green, indoor in white.
                let tint = isIndoor ? Color.white.opacity(0.75) : MADTheme.Colors.success
                HStack(spacing: 4) {
                    Image(systemName: isIndoor ? "house.fill" : "sun.max.fill")
                        .font(.system(size: 10, weight: .bold))
                    Text(isIndoor ? "INDOOR" : "OUTDOOR")
                        .font(.system(size: 10, weight: .heavy, design: type.design))
                        .tracking(1.2)
                        .fixedSize(horizontal: true, vertical: false)
                }
                .foregroundColor(tint)
                .padding(.horizontal, 9).padding(.vertical, 5)
                .background(Capsule().fill(tint.opacity(style.isFun ? 0.16 : 0.12)))
                .overlay(Capsule().stroke(tint.opacity(0.3), lineWidth: 1))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(isIndoor ? "Indoor" : "Outdoor")
            }
        }
        .lineLimit(1)
    }
}

/// "2.19 MI", counting up once. Laid out against the FINAL number so nothing
/// shifts while the overlay counts.
struct RoutelessDistanceHeadline: View {
    let style: RoutelessCardStyle
    let distance: Double
    var size: CGFloat = 48
    let revealed: Bool
    let still: Bool
    var duration: Double = 1.6

    var body: some View {
        let type = RoutelessType(style: style)
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(distance.milesText)
                .modifier(CountUpNumberModifier(value: (still || revealed) ? distance : 0,
                                                format: "%.2f", floorsMiles: true))
                .font(.system(size: size, weight: type.heroWeight, design: type.design))
                .tracking(style.isFun ? 0 : -1)
                .foregroundColor(.white)
                .monospacedDigit()
                .animation(still ? nil : .easeOut(duration: duration), value: revealed)
            Text("MI")
                .font(.system(size: size * 0.3, weight: .heavy, design: type.design))
                .foregroundColor(.white.opacity(0.6))
        }
        .lineLimit(1)
        .minimumScaleFactor(0.5)
        .shadow(color: .black.opacity(style.isFun ? 0.35 : 0), radius: 5, y: 2)
    }
}

/// PACE · TIME as two small label-over-value columns — the two numbers every
/// walk has, without a tile grid's boxes and padding.
struct RoutelessStatPair: View {
    let style: RoutelessCardStyle
    let accent: Color
    let stats: PostStats
    var alignment: HorizontalAlignment = .trailing

    private struct Item { let label: String; let value: String }

    private var items: [Item] {
        var out: [Item] = []
        if let p = stats.pace, p > 0 { out.append(Item(label: "PACE", value: "\(RunStatsStickerView.paceText(p))/mi")) }
        if let d = stats.duration, d > 0 { out.append(Item(label: "TIME", value: RunStatsStickerView.durationText(d))) }
        return out
    }

    var body: some View {
        let type = RoutelessType(style: style)
        HStack(alignment: .top, spacing: 16) {
            ForEach(items, id: \.label) { item in
                VStack(alignment: alignment, spacing: 2) {
                    Text(item.label)
                        .font(.system(size: 9, weight: .heavy, design: type.design))
                        .tracking(1.2)
                        .foregroundColor(style.isFun ? accent : .white.opacity(0.45))
                    Text(item.value)
                        .font(.system(size: 17, weight: type.valueWeight, design: type.design))
                        .monospacedDigit()
                        .foregroundColor(.white)
                }
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .fixedSize(horizontal: true, vertical: false)
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
