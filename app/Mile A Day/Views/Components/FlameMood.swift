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
    /// The mood itself — its cases, resolution, props, arms and eyes — is
    /// `FlameMoodKind` in FlameyMoodCore.swift, a file the widget extension
    /// compiles too, so the home-screen Flamey resolves the SAME mood.
    typealias Kind = FlameMoodKind

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
    var eyesShut: Bool { kind.eyesShut(grumbling: pokeQuip != nil) }

    /// The props this mood puts on him (see `FlameMoodKind.props`).
    var props: [FlameyItem] { kind.props }

    static func resolve(
        phase: StreakFlamePhase,
        progress: Double,
        isAtRisk: Bool,
        hasActiveWorkout: Bool,
        streak: Int,
        /// The user woke him today (a poke while he was asleep).
        wokenToday: Bool = false,
        now: Date = Date()
    ) -> FlameMood {
        FlameMood(kind: Kind.resolve(phase: phase, progress: progress, isAtRisk: isAtRisk,
                                     hasActiveWorkout: hasActiveWorkout, streak: streak,
                                     wokenToday: wokenToday, now: now),
                  streak: streak)
    }

    static func isMilestone(_ streak: Int) -> Bool { Kind.isMilestone(streak) }

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
    /// His speech-bubble style from the wardrobe (`FlameyLook.bubble`).
    /// Classic draws the bubble below, unchanged.
    var bubbleStyle: FlameyItem = .classicBubble
    /// His hover (rocket jets / winged sandals), as a fraction of `size`, so
    /// the bubble and props stay on him in the air.
    var lift: CGFloat = 0
    /// How far above his tip his look reaches (body units — a crown, a
    /// countdown hat; `FlameyArt.crest(of:)`), so the bubble sits OVER the
    /// hat instead of on it. 0 = bare, the old placement's anchor.
    var crest: CGFloat = 0
    /// The bubble's width cap as a fraction of `size`. The dashboard hero
    /// passes less: its bubble shares a band with the savers/Share chips.
    var bubbleWidth: CGFloat = 0.78

    private var bottom: CGFloat { size / 2 - lift * size }
    private var topY: CGFloat { bottom - 0.98 * size * scale }

    var body: some View {
        ZStack {
            // The props are shared with the widget (FlameyMoodCore.swift).
            FlameMoodProps(kind: mood.kind, eyesShut: mood.eyesShut, size: size, scale: scale,
                           still: still, drawsWornProps: drawsWornProps, lift: lift)
            if showsBubble {
                bubble
            }
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
            // Anchored by its BOTTOM (the tail) just over his crest, so a
            // two-line quip grows UP — away from his hat — and a surface can
            // reserve room for it (`FlameyArt.extentAboveView`). It used to
            // be centred a fixed 0.13·size over the tip, which sat it ON a
            // crown and pushed a tall hat's bubble off the hero card.
            .frame(height: 1, alignment: .bottom)
            .offset(x: -size * (bubbleWidth < 0.78 ? 0.07 : 0.03),
                    y: topY - crest * size * scale - FlameyArt.bubbleGap * size)
        }
    }

    /// A real speech bubble — cream, dark rounded lettering, a tail pointing
    /// at him, a slight tilt — not a status chip. Split out with explicit
    /// types (the inline chain tipped the type-checker past its time
    /// budget). Width-capped to the flame's own column and allowed a second
    /// line, so a long quip wraps rather than widens, on every screen size.
    @ViewBuilder
    private func bubbleLabel(_ text: String) -> some View {
        if bubbleStyle == .classicBubble {
            classicBubbleLabel(text)
        } else {
            FlameyStyledBubble(text: text, style: bubbleStyle, size: size, widthFraction: bubbleWidth)
        }
    }

    private func classicBubbleLabel(_ text: String) -> some View {
        let fontSize: CGFloat = max(10, size * 0.07)
        let padX: CGFloat = size * 0.055
        let padY: CGFloat = size * 0.03
        let maxWidth: CGFloat = size * bubbleWidth
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
