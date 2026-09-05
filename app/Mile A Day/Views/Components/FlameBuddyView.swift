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
    /// The Fun hero's dressing: props, a rotating bubble, darting eyes, a poke
    /// reaction (see `FlameMood`). nil = the plain flame every other caller
    /// gets. Drawn INSIDE the flame's own animated stack so it bobs and
    /// shrinks with the figure.
    var mood: FlameMood? = nil

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

    // Mood gestures are SwiftUI animations on the CONTAINER — Core Animation
    // at 60 fps, never samples of the 12 fps content clock below. A hop or a
    // pace sampled at 12 fps read as lag, and driving it from the timeline
    // also meant every gesture frame was a figure redraw (shadow + blur).
    @State private var moodHopPhase = false
    @State private var moodPacePhase = false
    @State private var bobPhase = false
    @State private var pokeSquash: CGFloat = 1

    private var animatedFlame: some View {
        ZStack {
            // The ONLY per-frame clock: the figure's flicker and blink. 12 fps
            // of a shadowed, blurred shape is the one cost this view has
            // always carried; nothing else may ride it.
            TimelineView(.animation(minimumInterval: 1.0 / 12.0)) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let vigorNow = currentVigor(at: timeline.date)

                ZStack {
                    if grounded, let vigorNow, vigorNow < 0.45 {
                        EmberBaseGlow(size: size, intensity: min(1, (0.45 - vigorNow) / 0.45))
                    }

                    figure(vigor: vigorNow, flicker: CGFloat(t * 5.5), blink: moodBlink(at: t), gaze: moodGaze(at: t))

                    if resolvedPhase == .blazing {
                        BlazingEmberField(time: t, size: size)
                    }
                }
            }

            if let mood {
                // No clock of its own (see FlameMoodLayer). Shares the
                // container's bob/hop/pace below, so props ride with him.
                FlameMoodLayer(mood: mood, size: size, scale: figureScale(vigor: currentVigor(at: Date())))
            }
        }
        .scaleEffect(x: 1, y: pokeSquash, anchor: .bottom)
        .offset(x: paceOffset, y: hopOffset + bobOffset)
        .onAppear {
            // Off the appear commit, on purpose: a `repeatForever` animation
            // started INSIDE onAppear is attached to the view's initial
            // transaction, and every later layout change in the subtree —
            // the 12 fps blink toggling the eye frame — inherited it. The eyes
            // then opened as a 2-second overshooting stretch, taller than the
            // sunglasses drawn over them. Starting on the next turn scopes the
            // animation to the phase flip alone (the figure's face also
            // refuses inherited animations outright, as belt and braces).
            DispatchQueue.main.async {
                startBob()
                startMoodMotion()
            }
        }
        .onChange(of: mood?.kind) { _, _ in restartMoodMotion() }
        .onChange(of: mood?.pokedAt) { _, newValue in
            if newValue != nil { pokeBounce() }
        }
    }

    /// The idle bob — used to be a sine sampled on the 12 fps content clock;
    /// now a 60 fps container animation, so the mood props ride it too.
    private var bobOffset: CGFloat {
        guard !reduceMotion else { return 0 }
        let bodyScale = figureScale(vigor: currentVigor(at: Date()))
        let amplitude: CGFloat = 2.2 * (resolvedPhase == .blazing ? 1 : max(0.35, bodyScale))
        return bobPhase ? -amplitude : amplitude
    }

    private func startBob() {
        guard !reduceMotion else { return }
        withAnimation(.easeInOut(duration: 2.1).repeatForever(autoreverses: true)) { bobPhase = true }
    }

    private var staticFlame: some View {
        let vigorNow = currentVigor(at: Date())
        return ZStack {
            if grounded, let vigorNow, vigorNow < 0.45 {
                EmberBaseGlow(size: size, intensity: min(1, (0.45 - vigorNow) / 0.45))
            }
            figure(vigor: vigorNow, flicker: 0, blink: false, gaze: .zero)
            if let mood {
                FlameMoodLayer(mood: mood, size: size, scale: figureScale(vigor: vigorNow), still: true)
            }
        }
    }

    /// The scale the FIGURE actually draws at (FlameBuddyFigure's
    /// `effectiveBodyScale`): the vigor ramp while burning, the stage's own
    /// `bodyScale` otherwise — and blazing is 1.05, not 1. Props placed at 1
    /// on a 1.05 face missed the eyes by enough to read as a second pair.
    private func figureScale(vigor: Double?) -> CGFloat {
        if let vigor, health != .dead, health != .blazing {
            return StreakFlameClock.flameScale(vigor: vigor)
        }
        return health.bodyScale
    }

    private func figure(vigor: Double?, flicker: CGFloat, blink: Bool, gaze: CGSize) -> some View {
        FlameBuddyFigure(
            health: health,
            flickerPhase: flicker,
            blink: blink,
            size: size,
            showsFace: showsFace,
            vigor: vigor.map { CGFloat($0) },
            gaze: gaze,
            asleep: mood?.kind == .sleepy,
            grounded: grounded
        )
    }

    // MARK: - Mood: face (content clock — discrete, cheap)

    /// The ordinary blink. Asleep is not a blink: the sleepy mood used to be
    /// drawn as long lids on this clock (closed 2.4 s in every 4), which is
    /// a buddy who is AWAKE for 40% of every cycle — and the blink frame is a
    /// squashed sliver, not a lid. Sleeping is a face the figure draws
    /// (`asleep`), so here the sleeper simply never blinks.
    private func moodBlink(at t: TimeInterval) -> Bool {
        if mood?.kind == .sleepy { return false }
        return Int(t * 2.0) % 9 == 0
    }

    /// Nervous eyes dart; everyone else looks straight ahead.
    private func moodGaze(at t: TimeInterval) -> CGSize {
        guard mood?.kind == .nervous else { return .zero }
        let dart = t.truncatingRemainder(dividingBy: 2.6)
        let x: CGFloat = dart < 0.9 ? -0.025 : (dart < 1.8 ? 0.025 : 0)
        return CGSize(width: x, height: 0)
    }

    // MARK: - Mood: gestures (container animations)

    /// Ready / halfway / almost / party: a bounce whose height and tempo rise
    /// with the mood. Zero for every other mood, so the phase flag is inert.
    private var hopOffset: CGFloat {
        guard !reduceMotion, let kind = mood?.kind else { return 0 }
        let height: CGFloat
        switch kind {
        case .ready: height = 0.025
        case .halfway: height = 0.035
        case .almost: height = 0.045
        case .party: height = 0.05
        default: return 0
        }
        return moodHopPhase ? -size * height : 0
    }

    /// Nervous: pacing side to side.
    private var paceOffset: CGFloat {
        guard !reduceMotion, mood?.kind == .nervous else { return 0 }
        return moodPacePhase ? size * 0.05 : -size * 0.05
    }

    private func startMoodMotion() {
        guard !reduceMotion, let kind = mood?.kind else { return }
        switch kind {
        case .ready:
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { moodHopPhase = true }
        case .halfway:
            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) { moodHopPhase = true }
        case .almost:
            withAnimation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true)) { moodHopPhase = true }
        case .party:
            withAnimation(.easeInOut(duration: 0.45).repeatForever(autoreverses: true)) { moodHopPhase = true }
        case .nervous:
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { moodPacePhase = true }
        default:
            break
        }
    }

    /// A new mood is a new tempo: land the phases without animation, then
    /// start the new one on the next turn (re-assigning an at-target phase
    /// inside the same update would be a no-op and keep the old timing).
    private func restartMoodMotion() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            moodHopPhase = false
            moodPacePhase = false
        }
        DispatchQueue.main.async { startMoodMotion() }
    }

    /// Poked: squash, then spring back.
    private func pokeBounce() {
        guard !reduceMotion else { return }
        withAnimation(.spring(response: 0.16, dampingFraction: 0.6)) { pokeSquash = 0.88 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            // Settles without overshooting: a stretch past 1 tall-ens the
            // whole face and the eyes with it.
            withAnimation(.spring(response: 0.34, dampingFraction: 0.8)) { pokeSquash = 1 }
        }
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
