import SwiftUI

/// What the Fun dashboard's flame is FEELING right now — resolved once from
/// the day's state by the hero card and drawn by `FlameMoodLayer` inside
/// `FlameBuddyView`, next to the figure, so props bob and shrink with him.
///
/// The lifecycle (coal → burning → blazing, size = time left) stays exactly
/// what it was; moods are dressing on top: a speech bubble that rotates every
/// few seconds, a prop for the states that earn one (sunglasses once the mile
/// is banked, a sweat drop when the streak is at risk, a party hat on a
/// milestone, zzz's before the day has started), a poke reaction when the
/// buddy is tapped. Everything is a function of the hero's own timeline
/// clock — no timers, no extra state — and transform-only.
struct FlameMood: Equatable {
    enum Kind: Equatable {
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
    }

    /// A play gesture on the hero buddy, played once from `reactionAt`.
    enum Reaction: Equatable {
        /// Double-tap once the mile is in: a flame-hand pops up, "Up top!".
        case highFive
        /// A double-tap before the mile: he shakes his head — earn it first.
        case refuse
        /// A horizontal rub: he wiggles and giggles.
        case tickle
        /// Long-press: today's Well Earned treat flies into his mouth.
        case feed(CalorieTreat)
    }

    var kind: Kind
    var streak: Int
    /// When the buddy was last tapped — the squash reaction plays from it.
    var pokedAt: Date? = nil
    /// What he says about being tapped, while the reaction is live; nil once
    /// the hero clears it. Non-nil SUPPRESSES the mood bubble outright, so the
    /// two can never be on screen together.
    var pokeQuip: String? = nil
    /// The play gesture in flight and when it started (see `Reaction`).
    var reaction: Reaction? = nil
    var reactionAt: Date? = nil
    /// Today's holiday / the signup anniversary — each gets its own line in
    /// the rotation (the outfit itself is `FlameyLook`'s job).
    var holiday: HolidayKey? = nil
    var isAnniversary: Bool = false
    /// ONE line built from the user's own data ("3 days before 8 AM!"),
    /// already chosen for today by `FlameyMemory`. Joins the rotation once —
    /// never every slot — and only when it's true.
    var memoryLine: String? = nil

    /// Eyes shut right now. A bedtime sleeper opens them while a poke's
    /// grumble is up and closes them the moment it clears.
    var eyesShut: Bool {
        switch kind {
        case .sleepy: return true
        case .bedtime: return pokeQuip == nil
        default: return false
        }
    }

    /// The props this mood puts on him, handed to `FlameyLook.resolve` as its
    /// mood layer — so a holiday hat can outrank the party hat and he still
    /// never wears two.
    var props: [FlameyItem] {
        switch kind {
        case .done: return [.shades]
        case .party: return [.shades, .partyHat]
        case .bedtime, .sleepy: return [.nightcap]
        default: return []
        }
    }

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
    ) -> FlameMood {
        let hour = Calendar.current.component(.hour, from: now)
        let kind: Kind
        switch phase {
        case .coal:
            kind = .unlit
        case .blazing:
            // A milestone outranks bedtime: it happens once, and a party that
            // falls asleep at ten reads as the app forgetting it.
            if isMilestone(streak) { kind = .party }
            else if hour >= 22 { kind = .bedtime }
            else { kind = .done }
        case .burning:
            if isAtRisk { kind = .nervous }
            else if progress >= 0.8 { kind = .almost }
            else if progress >= 0.5 { kind = .halfway }
            else if progress > 0.05 || hasActiveWorkout { kind = .going }
            else if hour < 10 { kind = wokenToday ? .groggy : .sleepy }
            else { kind = .ready }
        }
        return FlameMood(kind: kind, streak: streak)
    }

    static func isMilestone(_ streak: Int) -> Bool {
        guard streak > 0 else { return false }
        return [7, 14, 30, 50, 100, 200, 365, 500, 730, 1000].contains(streak) || streak % 100 == 0
    }

    /// What he says, rotating: the mood's lines, plus — when he's awake — the
    /// day's occasion up front and at most ONE line about the user's own data.
    var bubbles: [String] {
        var lines = moodLines
        guard !kind.isAsleep else { return lines }
        var special: [String] = []
        if isAnniversary { special.append("Happy Flamey-versary!") }
        if let holiday { special.append(Self.holidayLine(holiday)) }
        else if HolidayCalendar.components(of: Date()).month == 12 { special.append("Ho ho ho!") }
        lines.insert(contentsOf: special, at: 0)
        if let memoryLine, kind != .unlit {
            // Mid-rotation, so it reads as a thought, not a headline.
            lines.insert(memoryLine, at: min(special.count + 1, lines.count))
        }
        return lines
    }

    /// One line per holiday — warm, never a claim about health.
    static func holidayLine(_ holiday: HolidayKey) -> String {
        switch holiday {
        case .newYearsDay: return "Happy New Year!"
        case .valentinesDay: return "Love a good walk"
        case .stPatricksDay: return "Feeling lucky!"
        case .easter: return "Hoppy Easter!"
        case .independenceDay: return "Happy 4th!"
        case .halloween: return "Boo! Trick or treat?"
        case .thanksgiving: return "Gobble gobble!"
        case .christmasEve: return "Santa's coming!"
        case .christmas: return "Merry Christmas!"
        case .newYearsEve: return "Last mile of the year!"
        }
    }

    /// The mood's own rotation. Short, because the bubble sits beside a stat
    /// column.
    private var moodLines: [String] {
        // ≤ 16 characters each: the bubble sits over a flame that shares its
        // card with a stat column, so it is width-capped and two-line at most.
        switch kind {
        case .unlit: return ["Light me up!", "One mile, lit", "Ready when you are"]
        // Snores and sleep-talk only. Every line here is said with his eyes
        // shut, so none of them may sound awake.
        case .sleepy: return ["Zzz…", "Hnnnk… shoo…", "zzZZzz…", "*snore*", "mmm… donuts…", "…one more mi…"]
        case .groggy: return ["Mornin'…", "I'm up, I'm up", "Coffee first?", "*yaaawn*", "Mile o'clock?"]
        case .ready: return ["Let's walk!", "Mile o'clock?", "Shoes on!", "Waiting…"]
        case .going: return ["Nice start!", "Keep it rolling", "Warming up"]
        case .halfway: return ["Halfway!", "Don't stop now", "Half to go"]
        case .almost: return ["Almost!", "So close", "Finish strong"]
        case .nervous: return ["Tick tock…", "Still time!", "Not like this…", "A mile. Tonight."]
        case .done: return ["Nailed it", "Streak safe", "Look at us", "Again tomorrow?"]
        case .party: return ["\(streak) days!", "Legend", "Cake?", "Party time"]
        // Said drifting off and asleep — drowsy, never chirpy.
        case .bedtime: return ["Night night", "*yaaawn*", "Big day tmrw", "Zzz…", "Good mile today"]
        }
    }

    static let pokeQuips = ["Hey!", "That tickles", "Working here", "Boop", "Careful, hot", "Again!"]

    /// What a poke gets out of him, by what he was doing when it landed.
    /// Poking a SLEEPER wakes him, so those lines are the startle.
    /// What a play gesture gets out of him.
    static func reactionQuips(_ reaction: Reaction) -> [String] {
        switch reaction {
        case .highFive: return ["Up top!", "Yeah!", "Nailed it!"]
        case .refuse: return ["Earn it first!", "Mile first!", "Not yet!"]
        case .tickle: return ["Hehe stop!", "Tickles!", "Hahaha!"]
        case .feed(let treat):
            // FOOD lines only. Flamey is never shown drinking — `food(for:)`
            // swaps an alcoholic pick for a donut before a feed can start, so
            // `.tipsy` is unreachable here; it still gets food lines rather
            // than a toast, belt and braces.
            switch food(for: treat).effect {
            case .stuffed, .tipsy: return ["Nom!", "So good", "Nom nom nom"]
            case .wired: return ["Zoom zoom!", "Mmm, latte"]
            }
        }
    }

    /// What Flamey actually EATS for a Well Earned pick. He is a mascot on a
    /// 13+ fitness app and is never shown consuming alcohol: wine and beer
    /// (any `.tipsy` treat) become a donut, counted in DONUTS — the Well
    /// Earned cards themselves keep the user's pick unchanged.
    static func food(for treat: CalorieTreat) -> CalorieTreat {
        treat.effect == .tipsy ? .donut : treat
    }

    /// Long-press with nothing earned yet today: he asks for it instead.
    static func hungryQuip(_ treat: CalorieTreat) -> String {
        switch food(for: treat) {
        case .wine, .beer: return "Earn me a donut!"
        case .cheeseburger: return "Earn me a burger!"
        case .pizza: return "Earn me pizza!"
        case .donut: return "Earn me a donut!"
        case .coffee: return "Earn me a latte!"
        }
    }

    static func pokeQuips(for kind: Kind) -> [String] {
        switch kind {
        case .sleepy: return ["Huh?! I'm up!", "Wha—? Who?", "I wasn't asleep!", "*snort* Huh?", "Five more mi… ok"]
        case .groggy: return ["Okay, okay…", "Still waking up", "Gentle! I'm up"]
        case .nervous: return ["No time! Walk!", "Tickle me later", "Shoes. On. Now."]
        case .done: return ["I was chilling!", "Careful, hot", "Boop"]
        case .party: return ["Party foul!", "Boop!", "Cake first"]
        case .bedtime: return ["Lights out!", "Five more hours…", "Shhh… sleeping", "Mmf. Night."]
        default: return pokeQuips
        }
    }
}

/// The mood's props and bubble, laid out in `FlameBuddyView`'s own frame
/// (the size × size square the figure is centred in). Every position is
/// derived from the figure's geometry — face 0.32·size above the bottom
/// edge before scaling, eyes 0.145·size either side — times the same body
/// `scale` the figure is drawn at, so a sweat drop stays on the temple as
/// the flame burns down through the day.
///
/// NOTHING here runs on a per-frame clock. Props that move (sweat, zzz,
/// sparkles, confetti) are `repeatForever` Core Animation transforms
/// started once on appear; the bubble advances on a 3.5-second periodic
/// schedule. The first version recomputed every prop and the bubble's fade
/// on a 10 fps timeline, and that — on top of the figure's own 12 fps
/// redraw — is what made the dashboard drag.
///
/// TWO bubbles can never overlap: there is ONE mood bubble whose text only
/// changes while it is hidden (visible slots alternate with hidden ones),
/// and the poke quip is a separate view that suppresses it instantly and
/// snaps away (removal `.identity`) when the hero clears it.
struct FlameMoodLayer: View {
    let mood: FlameMood
    let size: CGFloat
    /// The figure's body scale right now (`flameScale(vigor:)` while burning,
    /// the stage's `bodyScale` otherwise).
    let scale: CGFloat
    /// Reduce Motion / still frames: the first bubble, props at rest.
    var still: Bool = false
    /// The speech bubble. OFF for a share card: a bubble baked into a picture
    /// somebody posts reads as a caption nobody wrote — the props stay.
    var showsBubble: Bool = true
    /// Draw the shades / party hat here. OFF when the caller passes a
    /// `FlameyLook`: the look already carries the mood's props (resolved
    /// against holiday outfits and gear), and drawing them twice is exactly
    /// the two-hats bug the look exists to prevent.
    var drawsWornProps: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Flipped once on appear; every moving prop animates off it.
    @State private var animate = false

    private var bottom: CGFloat { size / 2 }
    private var faceY: CGFloat { bottom - 0.32 * size * scale }
    private var eyeX: CGFloat { 0.145 * size * scale }
    private var topY: CGFloat { bottom - 0.98 * size * scale }
    private var moving: Bool { animate && !still && !reduceMotion }

    var body: some View {
        ZStack {
            switch mood.kind {
            case .done, .party:
                if drawsWornProps { sunglasses }
                if mood.kind == .party {
                    if drawsWornProps { partyHat }
                    confetti
                }
            case .nervous:
                sweatDrop
            case .sleepy:
                zzz
            case .bedtime:
                if mood.eyesShut { zzz }
            case .almost:
                sparkles
            default:
                EmptyView()
            }
            if showsBubble {
                bubble
            }
        }
        .onAppear {
            guard !still, !reduceMotion else { return }
            animate = true
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: Bubble

    /// Visible for a slot, hidden for a slot, next line — from a fixed epoch,
    /// so a hero re-render can't restart the rhythm.
    private static let bubbleSlot: TimeInterval = 3.5

    private var bubble: some View {
        TimelineView(.periodic(from: Date(timeIntervalSinceReferenceDate: 0), by: Self.bubbleSlot)) { context in
            let slot = Int(context.date.timeIntervalSinceReferenceDate / Self.bubbleSlot)
            let lines = mood.bubbles
            let index = lines.isEmpty ? 0 : (slot / 2) % lines.count
            let pokeActive = mood.pokeQuip != nil
            let moodShown = !pokeActive && (still || slot % 2 == 0)
            ZStack(alignment: .bottom) {
                // ONE mood bubble, alive across the cycle. Its text changes
                // only at a shown-slot boundary, i.e. while it is at opacity
                // 0, so a change is never a crossfade.
                if !lines.isEmpty {
                    bubbleLabel(lines[index])
                        .opacity(moodShown ? 1 : 0)
                        .scaleEffect(moodShown ? 1 : 0.7, anchor: .bottom)
                        // Instant when a poke takes over; a spring otherwise.
                        .animation(pokeActive || still ? nil : .spring(response: 0.38, dampingFraction: 0.7),
                                   value: moodShown)
                }
                if let quip = mood.pokeQuip {
                    bubbleLabel(quip)
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.6, anchor: .bottom).combined(with: .opacity),
                            removal: .identity))
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: mood.pokeQuip)
            .offset(x: -size * 0.03, y: topY - size * 0.13)
        }
    }

    /// A real speech bubble — cream, dark rounded lettering, a tail pointing
    /// at him, a slight tilt — not a status chip. Split out with explicit
    /// types (the inline chain tipped the type-checker past its time
    /// budget). Width-capped to the flame's own column and allowed a second
    /// line, so a long quip wraps rather than widens, on every screen size.
    private func bubbleLabel(_ text: String) -> some View {
        let fontSize: CGFloat = max(10, size * 0.07)
        let padX: CGFloat = size * 0.055
        let padY: CGFloat = size * 0.03
        let maxWidth: CGFloat = size * 0.78
        let tail: CGFloat = max(5, size * 0.045)
        let cream = Color(red: 1.0, green: 0.97, blue: 0.91)
        let ink = Color(red: 0.24, green: 0.10, blue: 0.08)
        return Text(text)
            .font(.system(size: fontSize, weight: .heavy, design: .rounded))
            .foregroundColor(ink)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.8)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: maxWidth)
            .padding(.horizontal, padX)
            .padding(.vertical, padY)
            .padding(.bottom, tail)
            .background(
                FlameSpeechBubbleShape(cornerRadius: size * 0.065, tailHeight: tail, tailWidth: tail * 1.7)
                    .fill(cream)
                    .shadow(color: Color.black.opacity(0.28), radius: size * 0.02, y: size * 0.012)
            )
            .rotationEffect(.degrees(-2))
    }

    // MARK: Props

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
            Triangle()
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
    /// Still frames (Reduce Motion, previews) draw the trail already laid
    /// out along the path instead of three Z's stacked on the start point.
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
                .opacity(moving ? 1 : 0.35)
                .scaleEffect(moving ? 1.1 : 0.8)
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
            Triangle()
                .fill(LinearGradient(
                    colors: [Color(red: 1.0, green: 0.42, blue: 0.62), Color(red: 0.55, green: 0.42, blue: 1.0)],
                    startPoint: .top, endPoint: .bottom))
            Triangle()
                .stroke(Color.white.opacity(0.35), lineWidth: max(1, size * 0.006))
            ForEach(0..<2, id: \.self) { index in
                Rectangle()
                    .fill(Color.white.opacity(0.28))
                    .frame(width: width, height: height * 0.08)
                    .offset(y: -height * 0.05 + CGFloat(index) * height * 0.28)
                    .mask(Triangle())
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
        // A still frame (a share card, Reduce Motion) parks each piece part
        // way down its own fall, so the shower reads as confetti in the air
        // rather than eight pieces lined up on the start row.
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

/// A rounded bubble with a little tail hanging off its bottom edge, just
/// right of centre, pointing down at the speaker.
private struct FlameSpeechBubbleShape: Shape {
    let cornerRadius: CGFloat
    let tailHeight: CGFloat
    let tailWidth: CGFloat

    func path(in rect: CGRect) -> Path {
        let body = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height - tailHeight)
        var path = Path(roundedRect: body, cornerRadius: cornerRadius, style: .continuous)
        let tailX = body.minX + body.width * 0.58
        var tailPath = Path()
        tailPath.move(to: CGPoint(x: tailX - tailWidth * 0.5, y: body.maxY - 1))
        tailPath.addLine(to: CGPoint(x: tailX + tailWidth * 0.5, y: body.maxY - 1))
        tailPath.addLine(to: CGPoint(x: tailX + tailWidth * 0.12, y: rect.maxY))
        tailPath.closeSubpath()
        path.addPath(tailPath)
        return path
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
