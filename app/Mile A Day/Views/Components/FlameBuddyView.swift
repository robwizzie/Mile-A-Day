import SwiftUI

/// The animated streak flame used by both dashboard heroes.
///
/// Drives the full lifecycle: a cold coal when there is no streak, a flame
/// that burns down continuously with the time left in the day, a full blaze
/// once the mile is banked, an ignition burst on the transition into blazing,
/// and a puff of smoke if the flame dies on screen at midnight.
///
/// Legacy call sites that pass only `health` keep their existing stage-based
/// look — the lifecycle engages only when `phase` is provided.
struct FlameBuddyView: View {
    let health: FlameHealth
    var size: CGFloat = 170
    var showsFace: Bool = true
    /// Streak lifecycle phase. When nil the view falls back to health-driven
    /// rendering (style chooser preview, legacy callers).
    var phase: StreakFlamePhase? = nil
    /// End of the local day; drives the continuous burn-down while `.burning`.
    /// When nil it is derived from the calendar.
    var dayEnd: Date? = nil
    /// Today's partial mile progress (0-1) — pre-warms the coal's ember cracks.
    var coalWarmth: Double = 0
    /// Grounded (Fun buddy) sits on the ground and shrinks toward its base with
    /// an ember bed; non-grounded (Modern ring) shrinks toward center to stay
    /// framed in the circle.
    var grounded: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var ignitionDate: Date?
    @State private var smokeDate: Date?

    private var resolvedPhase: StreakFlamePhase {
        if let phase { return phase }
        switch health {
        case .blazing: return .blazing
        case .dead: return .coal
        default: return .burning
        }
    }

    var body: some View {
        ZStack {
            switch resolvedPhase {
            case .coal:
                coalView
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.85, anchor: .bottom)),
                            removal: .opacity.combined(with: .scale(scale: 0.7, anchor: .bottom))
                        )
                    )
            default:
                flameView
                    .transition(
                        .asymmetric(
                            insertion: .scale(scale: 0.18, anchor: .bottom).combined(with: .opacity),
                            removal: .opacity
                        )
                    )
            }

            if let smokeDate {
                FlameSmokePuff(startDate: smokeDate, size: size)
            }
            if let ignitionDate {
                FlameIgnitionBurst(startDate: ignitionDate, size: size)
            }
        }
        .animation(reduceMotion ? nil : .spring(response: 0.55, dampingFraction: 0.62), value: resolvedPhase)
        .onChange(of: resolvedPhase) { oldValue, newValue in
            guard oldValue != newValue else { return }
            if newValue == .blazing {
                MADHaptics.success()
                guard !reduceMotion else { return }
                ignitionDate = Date()
                DispatchQueue.main.asyncAfter(deadline: .now() + FlameIgnitionBurst.duration + 0.1) {
                    ignitionDate = nil
                }
            } else if newValue == .coal, oldValue == .burning {
                guard !reduceMotion else { return }
                smokeDate = Date()
                DispatchQueue.main.asyncAfter(deadline: .now() + FlameSmokePuff.duration + 0.1) {
                    smokeDate = nil
                }
            }
        }
    }

    private var coalView: some View {
        CoalLumpView(size: size * 0.74, showsFace: showsFace, warmth: coalWarmth)
            .frame(width: size, height: size, alignment: .bottom)
            .offset(y: -size * 0.01)
    }

    private var flameView: some View {
        Group {
            if reduceMotion {
                staticFlame
            } else {
                animatedFlame
            }
        }
        // When the day rolls over, dayEnd jumps a full day forward and the
        // burn-down scale snaps with it — ease the regrowth instead of popping.
        .animation(reduceMotion ? nil : .easeInOut(duration: 1.4), value: dayEnd)
    }

    private var animatedFlame: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 12.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let vigorNow = currentVigor(at: timeline.date)
            let bodyScale = vigorNow.map { StreakFlameClock.flameScale(vigor: $0) } ?? 1

            ZStack {
                if grounded, let vigorNow, vigorNow < 0.45 {
                    EmberBaseGlow(size: size, intensity: min(1, (0.45 - vigorNow) / 0.45))
                }

                figure(vigor: vigorNow, flicker: CGFloat(t * 5.5), blink: Int(t * 2.0) % 9 == 0)
                    .offset(y: sin(CGFloat(t) * 1.5) * 2.2 * (resolvedPhase == .blazing ? 1 : max(0.35, bodyScale)))

                if resolvedPhase == .blazing {
                    BlazingEmberField(time: t, size: size)
                }
            }
        }
    }

    private var staticFlame: some View {
        let vigorNow = currentVigor(at: Date())
        return ZStack {
            if grounded, let vigorNow, vigorNow < 0.45 {
                EmberBaseGlow(size: size, intensity: min(1, (0.45 - vigorNow) / 0.45))
            }
            figure(vigor: vigorNow, flicker: 0, blink: false)
        }
    }

    private func figure(vigor: Double?, flicker: CGFloat, blink: Bool) -> some View {
        FlameBuddyFigure(
            health: health,
            flickerPhase: flicker,
            blink: blink,
            size: size,
            showsFace: showsFace,
            vigor: vigor.map { CGFloat($0) },
            grounded: grounded
        )
    }

    /// Continuous time-left fraction, only while the lifecycle drives a
    /// burning flame. Legacy (phase-less) callers get nil and keep the
    /// stage-based look.
    private func currentVigor(at date: Date) -> Double? {
        guard resolvedPhase == .burning, phase != nil else { return nil }
        return StreakFlameClock.vigor(at: date, dayEnd: dayEnd)
    }
}

/// Warm ember bed that fades in beneath the flame as it burns low — the last
/// thing left glowing before midnight takes the rest.
private struct EmberBaseGlow: View {
    let size: CGFloat
    let intensity: Double

    var body: some View {
        ZStack {
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 1.0, green: 0.45, blue: 0.10).opacity(0.55 * intensity),
                            Color(red: 0.85, green: 0.20, blue: 0.05).opacity(0.22 * intensity),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 1,
                        endRadius: size * 0.20
                    )
                )
                .frame(width: size * 0.38, height: size * 0.15)

            Capsule()
                .fill(Color(red: 0.16, green: 0.09, blue: 0.08))
                .frame(width: size * 0.075, height: size * 0.035)
                .overlay(Capsule().stroke(Color.orange.opacity(0.5 * intensity), lineWidth: 0.8))
                .rotationEffect(.degrees(-8))
                .offset(x: -size * 0.05, y: size * 0.012)

            Capsule()
                .fill(Color(red: 0.13, green: 0.07, blue: 0.07))
                .frame(width: size * 0.06, height: size * 0.03)
                .overlay(Capsule().stroke(Color.orange.opacity(0.4 * intensity), lineWidth: 0.8))
                .rotationEffect(.degrees(10))
                .offset(x: size * 0.055, y: size * 0.02)
        }
        .offset(y: size * 0.44)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Ambient embers that drift up from a blazing flame — the quiet reward state
/// after the mile is banked.
private struct BlazingEmberField: View {
    let time: TimeInterval
    let size: CGFloat

    private static let seeds: [(x: CGFloat, period: Double, delay: Double, size: CGFloat)] = [
        (-0.16, 3.4, 0.0, 3.2),
        (0.06, 2.8, 1.1, 2.6),
        (0.19, 3.9, 0.4, 3.0),
        (-0.05, 3.1, 2.0, 2.2),
        (0.12, 4.3, 2.8, 2.8),
        (-0.22, 3.7, 1.6, 2.4)
    ]

    var body: some View {
        ZStack {
            ForEach(0..<Self.seeds.count, id: \.self) { index in
                ember(index: index)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func ember(index: Int) -> some View {
        let seed = Self.seeds[index]
        let cycle = ((time + seed.delay).truncatingRemainder(dividingBy: seed.period)) / seed.period

        return Circle()
            .fill(index.isMultiple(of: 2)
                  ? Color(red: 1.0, green: 0.80, blue: 0.30)
                  : Color(red: 1.0, green: 0.55, blue: 0.16))
            .frame(width: seed.size, height: seed.size)
            .offset(
                x: size * seed.x + sin(CGFloat(time) * 1.8 + CGFloat(index)) * size * 0.03,
                y: size * 0.28 - CGFloat(cycle) * size * 0.72
            )
            .opacity(sin(.pi * min(max(cycle, 0), 1)) * 0.55)
            .blur(radius: 0.4)
    }
}
