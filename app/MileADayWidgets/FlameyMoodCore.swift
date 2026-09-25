import SwiftUI

// SHARED by the app and the widget extension — two BYTE-IDENTICAL copies:
//   app/Mile A Day/Views/Components/FlameyMoodCore.swift
//   app/MileADayWidgets/FlameyMoodCore.swift
// Edit one, `cp` it over the other, `cmp` them. Dependency-free beyond the
// other shared Flamey files (FlameyWardrobe's `FlameyItem`, the figure's
// `FlameArmPose`), because the widget process sees nothing else.
//
// What lives here is everything that decides WHICH Flamey a surface draws —
// the mood, the props it puts on him, his arms, whether his eyes are shut —
// plus the mood props that are safe to draw still. The Fun hero
// (`FlameMood` / `FlameMoodLayer` / `FlameBuddyView`) and the flame widget
// both call it, so the home screen can't sleep in while the dashboard is
// awake, or wear shades the dashboard hasn't earned.

/// Lifecycle of the streak flame shared by both dashboard styles.
///
/// The flame is a day-long candle: full right after midnight, shrinking as the
/// day drains, and nothing at all at the stroke of midnight unless the mile
/// reignites it. With no living streak there is no flame — just a cold coal
/// waiting to be lit by the first mile.
enum StreakFlamePhase: Equatable {
    /// No living streak and no mile banked today — a cold coal.
    case coal
    /// Streak alive but today's mile not done — the flame burns down with the time left.
    case burning
    /// Today's mile is banked — full flame, nothing left to lose.
    case blazing

    /// Mirrors the trust rules of `FlameHealth.forState`: completion and
    /// streak-zero are only believed when today's distance is fresh, so a
    /// locked-device zero can never flash the coal at a streaking user.
    static func forState(isCompleted: Bool, distanceIsFresh: Bool, streak: Int) -> StreakFlamePhase {
        if isCompleted && distanceIsFresh { return .blazing }
        if streak == 0 && distanceIsFresh { return .coal }
        return .burning
    }
}

/// What the flame is feeling (`FlameMood.Kind` in the app — a typealias of
/// this). Pure: every surface resolves it from the same inputs.
enum FlameMoodKind: Equatable {
    /// No streak, no mile: the coal.
    case unlit
    /// Burning, nothing done, still early — ASLEEP. Eyes shut, zzz's, and
    /// every line he says is a snore or sleep-talk: he is not awake to
    /// say "mornin'".
    case sleepy
    /// Early, nothing done, and poked awake. Eyes open, no zzz's, and the
    /// morning lines live here — they used to be the SLEEPER's bubble,
    /// which is how a buddy with his eyes shut said "Mornin'…".
    case groggy
    /// Burning, nothing done, the day is on.
    case ready
    /// Some distance in.
    case going
    case halfway
    case almost
    /// Streak at risk and the mile not done.
    case nervous
    /// Mile banked.
    case done
    /// Mile banked on a milestone streak.
    case party
    /// Mile banked and it's past 10 PM: nightcap on, eyes shut, gentle
    /// zzz's. A poke gets a grumble and he dozes straight back off — unlike
    /// the morning, nothing about bedtime persists a wake.
    case bedtime

    /// Asleep right now (eyes shut, zzz's, no blinking).
    var isAsleep: Bool { self == .sleepy || self == .bedtime }

    static func resolve(
        phase: StreakFlamePhase,
        progress: Double,
        isAtRisk: Bool,
        hasActiveWorkout: Bool,
        streak: Int,
        /// The user woke him today (a poke while he was asleep). He stays up
        /// for the rest of the morning — falling back asleep the moment the
        /// bubble times out would make the poke feel like it did nothing.
        wokenToday: Bool = false,
        now: Date = Date()
    ) -> FlameMoodKind {
        let hour = Calendar.current.component(.hour, from: now)
        switch phase {
        case .coal:
            return .unlit
        case .blazing:
            // A milestone outranks bedtime: it happens once, and a party that
            // falls asleep at ten reads as the app forgetting it.
            if isMilestone(streak) { return .party }
            if hour >= 22 { return .bedtime }
            return .done
        case .burning:
            if isAtRisk { return .nervous }
            if progress >= 0.8 { return .almost }
            if progress >= 0.5 { return .halfway }
            if progress > 0.05 || hasActiveWorkout { return .going }
            if hour < 10 { return wokenToday ? .groggy : .sleepy }
            return .ready
        }
    }

    static func isMilestone(_ streak: Int) -> Bool {
        guard streak > 0 else { return false }
        return [7, 14, 30, 50, 100, 200, 365, 500, 730, 1000].contains(streak) || streak % 100 == 0
    }

    /// The workout's DAY progress → how he feels while a workout runs: the
    /// tracker's buddy and the Workout Live Activity. Calm while the day is
    /// young, bouncing mid-way, hyped near the end, shades once it's in.
    static func forWorkoutProgress(_ progress: Double) -> FlameMoodKind {
        switch progress {
        case ..<0.35: return .going
        case ..<0.75: return .halfway
        case ..<1.0: return .almost
        default: return .done
        }
    }

    /// The props this mood puts on him, handed to `FlameyLook.resolve` as its
    /// mood layer — so a holiday hat can outrank the party hat and he still
    /// never wears two. Mood dressing may only take the HEAD from what he
    /// chose; the done-shades only go on bare eyes.
    var props: [FlameyItem] {
        switch self {
        case .done: return [.moodShades]
        case .party: return [.moodShades, .partyHat]
        case .bedtime, .sleepy: return [.nightcap]
        default: return []
        }
    }

    /// Eyes shut. A bedtime sleeper opens them while a poke's grumble is up
    /// (`grumbling`) and closes them the moment it clears; a still surface
    /// has no poke and passes false.
    func eyesShut(grumbling: Bool = false) -> Bool {
        switch self {
        case .sleepy: return true
        case .bedtime: return !grumbling
        default: return false
        }
    }

    /// Hands on cheeks when nervous, tucked in asleep, both up at a party;
    /// relaxed at his sides otherwise.
    func armPose(eyesShut: Bool) -> FlameArmPose {
        switch self {
        case .nervous: return .cheeks
        case .party: return .cheer
        case .sleepy, .bedtime: return eyesShut ? .tucked : .rest
        default: return .rest
        }
    }

    /// The local-day stamp a poke-wake is recorded under
    /// (`flameyWokenDayV1`, mirrored into the App Group) and compared with.
    static func dayStamp(_ date: Date = Date()) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}

// MARK: - The mood's props

/// The mood's props (never the bubble), laid out in the figure's own
/// size × size frame. Every position is derived from the figure's geometry —
/// face 0.32·size above the bottom edge before scaling, eyes 0.145·size
/// either side — times the same body `scale` the figure is drawn at, so a
/// sweat drop stays on the temple as the flame burns down through the day.
///
/// The Fun hero draws these inside `FlameMoodLayer` (moving, `still: false`);
/// a widget or Live Activity draws the SAME views with `still: true`, which
/// is the Reduce-Motion frame: the zzz trail laid out along its climb, the
/// sweat drop on the temple, confetti part way down its fall.
///
/// Nothing here runs on a per-frame clock. Props that move are
/// `repeatForever` Core Animation transforms started once on appear.
struct FlameMoodProps: View {
    let kind: FlameMoodKind
    /// `kind.eyesShut(grumbling:)` — bedtime's zzz's stop while he grumbles.
    let eyesShut: Bool
    let size: CGFloat
    /// The figure's body scale right now.
    let scale: CGFloat
    var still: Bool = false
    /// Draw the shades / party hat here. OFF when the surface passes a
    /// `FlameyLook`: the look already carries the mood's props.
    var drawsWornProps: Bool = true
    /// His hover (legs / jets), as a fraction of `size`.
    var lift: CGFloat = 0
    /// A surface that is ALWAYS still (a widget, a Live Activity) draws a
    /// twinkling prop at its peak: with no motion to say "twinkle", the
    /// Reduce-Motion rest frame (sparkles at 35%) reads as nothing at widget
    /// size. The hero never passes it, so its frames are unchanged.
    var peak: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Flipped once on appear; every moving prop animates off it.
    @State private var animate = false

    private var bottom: CGFloat { size / 2 - lift * size }
    private var faceY: CGFloat { bottom - 0.32 * size * scale }
    private var eyeX: CGFloat { 0.145 * size * scale }
    private var topY: CGFloat { bottom - 0.98 * size * scale }
    private var moving: Bool { animate && !still && !reduceMotion }

    var body: some View {
        ZStack {
            switch kind {
            case .done, .party:
                if drawsWornProps { sunglasses }
                if kind == .party {
                    if drawsWornProps { partyHat }
                    confetti
                }
            case .nervous:
                sweatDrop
            case .sleepy:
                zzz
            case .bedtime:
                if eyesShut { zzz }
            case .almost:
                sparkles
            default:
                EmptyView()
            }
        }
        .onAppear {
            guard !still, !reduceMotion else { return }
            animate = true
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Mile banked: shades on. Lenses LARGER than the eyes (0.12 × 0.155 of
    /// size) on every axis, so no eye peeks out around a lens. Static.
    private var sunglasses: some View {
        let lensW = 0.20 * size * scale
        let lensH = 0.185 * size * scale
        let frame = Color(red: 0.18, green: 0.16, blue: 0.20)
        return ZStack {
            ForEach([-1, 1] as [CGFloat], id: \.self) { side in
                RoundedRectangle(cornerRadius: lensH * 0.45, style: .continuous)
                    .fill(Color(red: 0.08, green: 0.07, blue: 0.10))
                    .overlay(
                        RoundedRectangle(cornerRadius: lensH * 0.45, style: .continuous)
                            .fill(LinearGradient(
                                colors: [Color.white.opacity(0.28), .clear],
                                startPoint: .topLeading, endPoint: .center))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: lensH * 0.45, style: .continuous)
                            .strokeBorder(frame, lineWidth: max(1, size * 0.006))
                    )
                    .frame(width: lensW, height: lensH)
                    .offset(x: side * eyeX)
            }
            Capsule()
                .fill(frame)
                .frame(width: max(2, eyeX * 2 - lensW + size * 0.02), height: max(1.5, size * 0.012))
            ForEach([-1, 1] as [CGFloat], id: \.self) { side in
                Capsule()
                    .fill(frame)
                    .frame(width: size * 0.06 * scale, height: max(1.5, size * 0.012))
                    .offset(x: side * (eyeX + lensW / 2 + size * 0.025 * scale), y: -lensH * 0.15)
            }
        }
        .offset(y: faceY - 0.005 * size * scale)
    }

    /// Streak at risk: a sweat drop on the temple that falls, and falls again.
    private var sweatDrop: some View {
        let blue = Color(red: 0.55, green: 0.85, blue: 1.0)
        return ZStack {
            Circle().fill(blue)
            FlameMoodTriangle()
                .fill(blue)
                .frame(width: size * 0.05, height: size * 0.045)
                .offset(y: -size * 0.035)
            Circle()
                .fill(Color.white.opacity(0.7))
                .frame(width: size * 0.016, height: size * 0.016)
                .offset(x: -size * 0.01, y: -size * 0.008)
        }
        .frame(width: size * 0.05, height: size * 0.05)
        .offset(y: moving ? size * 0.16 : 0)
        .opacity(moving ? 0 : 1)
        .animation(moving ? .easeIn(duration: 2.2).repeatForever(autoreverses: false) : nil, value: moving)
        .offset(x: eyeX + size * 0.13 * scale, y: faceY - size * 0.13 * scale)
    }

    /// Before the day has started: Z's rising off his head, the way a
    /// cartoon sleeper's do — from the temple, up and away to the right,
    /// each a little bigger than the last and growing as it climbs, held
    /// solid for most of the trip and gone in the last stretch. Three of
    /// them a third of a period apart, so one is always on its way and no
    /// two ever bunch.
    ///
    /// It used to be three small lowercase z's parked beside the TIP at 85%
    /// white on an `easeOut` — they shot off, hung half-faded at the top,
    /// and read as a dim "zzz" caption floating next to an awake face.
    /// Cream, like the bubble, with a shadow so they hold over the glow.
    ///
    /// Still frames (Reduce Motion, previews, widgets) draw the trail already
    /// laid out along the path instead of three Z's stacked on the start
    /// point.
    private var zzz: some View {
        let parked = still || reduceMotion
        return ForEach(0..<3, id: \.self) { index in
            let i = CGFloat(index)
            let restScale: CGFloat = 0.75 + 0.25 * i
            let restX: CGFloat = size * 0.06 * i
            let restY: CGFloat = -size * 0.11 * i
            zGlyph(index: index)
                .scaleEffect(parked ? restScale : (moving ? 1.3 : 0.7))
                .offset(
                    x: parked ? restX : (moving ? size * 0.15 : 0),
                    y: parked ? restY : (moving ? -size * 0.30 : 0)
                )
                .animation(moving
                    ? .linear(duration: Self.zzzPeriod).repeatForever(autoreverses: false).delay(Double(index) * Self.zzzPeriod / 3)
                    : nil, value: moving)
                // Held at full opacity, then a short fade at the very end of
                // the climb: the delay INSIDE the repeat is per cycle, the
                // one outside is the same stagger as the motion, so the two
                // animations share a period and stay in phase.
                .opacity(parked ? 1 - 0.25 * Double(index) : (moving ? 0 : 1))
                .animation(moving
                    ? .linear(duration: Self.zzzFade).delay(Self.zzzPeriod - Self.zzzFade)
                        .repeatForever(autoreverses: false).delay(Double(index) * Self.zzzPeriod / 3)
                    : nil, value: moving)
                .offset(
                    x: eyeX + size * 0.14 * scale,
                    y: faceY - size * 0.22 * scale
                )
        }
    }

    private static let zzzPeriod = 3.6
    private static let zzzFade = 0.9

    private func zGlyph(index: Int) -> some View {
        Text("Z")
            .font(.system(size: size * (0.075 + 0.015 * CGFloat(index)), weight: .black, design: .rounded))
            .foregroundColor(Color(red: 1.0, green: 0.97, blue: 0.91))
            .shadow(color: Color(red: 0.24, green: 0.10, blue: 0.08).opacity(0.55),
                    radius: max(1, size * 0.006), y: max(1, size * 0.004))
            .rotationEffect(.degrees(-14))
    }

    /// Nearly there: a pair of twinkling sparkles.
    private var sparkles: some View {
        ForEach(0..<2, id: \.self) { index in
            Image(systemName: "sparkle")
                .font(.system(size: size * (index == 0 ? 0.07 : 0.05), weight: .bold))
                .foregroundColor(Color(red: 1.0, green: 0.92, blue: 0.55))
                .opacity(moving || peak ? 1 : 0.35)
                .scaleEffect(moving || peak ? 1.1 : 0.8)
                .animation(moving
                    ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true).delay(Double(index) * 0.4)
                    : nil, value: moving)
                .offset(
                    x: (index == 0 ? -1 : 1) * (eyeX + size * 0.16 * scale),
                    y: faceY - size * (index == 0 ? 0.22 : 0.10) * scale
                )
        }
    }

    /// Milestone: a striped cone on the tip of the flame, with a pom-pom.
    private var partyHat: some View {
        let width = size * 0.22
        let height = size * 0.24
        return ZStack {
            FlameMoodTriangle()
                .fill(LinearGradient(
                    colors: [Color(red: 1.0, green: 0.42, blue: 0.62), Color(red: 0.55, green: 0.42, blue: 1.0)],
                    startPoint: .top, endPoint: .bottom))
            FlameMoodTriangle()
                .stroke(Color.white.opacity(0.35), lineWidth: max(1, size * 0.006))
            ForEach(0..<2, id: \.self) { index in
                Rectangle()
                    .fill(Color.white.opacity(0.28))
                    .frame(width: width, height: height * 0.08)
                    .offset(y: -height * 0.05 + CGFloat(index) * height * 0.28)
                    .mask(FlameMoodTriangle())
            }
            Circle()
                .fill(Color(red: 1.0, green: 0.9, blue: 0.45))
                .frame(width: size * 0.05, height: size * 0.05)
                .offset(y: -height / 2)
        }
        .frame(width: width, height: height)
        .rotationEffect(.degrees(14))
        .offset(x: size * 0.06, y: topY - height * 0.35)
    }

    /// Milestone: confetti falling past him, forever — each piece its own
    /// linear repeat with its own delay and period, so the shower never
    /// looks like a loop.
    private var confetti: some View {
        let seeds: [(x: CGFloat, delay: Double, period: Double, hue: Int)] = [
            (-0.34, 0.0, 3.2, 0), (-0.18, 1.3, 2.7, 1), (0.02, 0.6, 3.5, 2), (0.20, 2.1, 2.9, 3),
            (0.36, 0.4, 3.1, 1), (-0.26, 2.6, 3.8, 2), (0.12, 1.7, 2.6, 0), (0.30, 3.0, 3.4, 3),
        ]
        let colors = [
            Color(red: 1.0, green: 0.42, blue: 0.62), Color(red: 0.55, green: 0.42, blue: 1.0),
            Color(red: 0.35, green: 0.85, blue: 0.95), Color(red: 1.0, green: 0.9, blue: 0.45),
        ]
        let fall = bottom - topY + size * 0.15
        // A still frame (a share card, Reduce Motion, a widget) parks each
        // piece part way down its own fall, so the shower reads as confetti
        // in the air rather than eight pieces lined up on the start row.
        let parked = still || reduceMotion
        return ForEach(0..<seeds.count, id: \.self) { index in
            let seed = seeds[index]
            RoundedRectangle(cornerRadius: 1)
                .fill(colors[seed.hue])
                .frame(width: size * 0.035, height: size * 0.02)
                .rotationEffect(.degrees(moving ? 360 + Double(index) * 40 : Double(index) * 40))
                .offset(y: moving ? fall : (parked ? fall * CGFloat(seed.delay / 3.2) * 0.8 : 0))
                .animation(moving
                    ? .linear(duration: seed.period).repeatForever(autoreverses: false).delay(seed.delay)
                    : nil, value: moving)
                .opacity(0.9)
                .offset(x: size * seed.x, y: topY - size * 0.15)
        }
    }
}

private struct FlameMoodTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
