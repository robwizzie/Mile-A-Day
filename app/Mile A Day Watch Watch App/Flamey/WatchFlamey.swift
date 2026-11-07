import SwiftUI

// Flamey on the wrist. The art is the widget extension's shared files (see
// `Flamey/`, kept BYTE-IDENTICAL with `app/MileADayWidgets/`); this file only
// feeds them what the Watch knows, the same way `StreakFlameWidget` does.

/// What the iPhone told us he's wearing. Arrives over `MADWatchBridge`.
enum WatchFlameyWardrobe {
    private static let ownedKey = "watchFlameyOwnedV1"
    private static let choiceKey = "watchFlameyChoiceV1"
    private static let signupKey = "watchFlameySignupV1"

    /// Ids this build doesn't know are dropped, so a newer phone's catalog
    /// never breaks an older Watch.
    static func apply(context: [String: Any]) {
        let defaults = UserDefaults.standard
        if let owned = context["flameyOwned"] as? [String] { defaults.set(owned, forKey: ownedKey) }
        if let choice = context["flameyChoice"] as? Data { defaults.set(choice, forKey: choiceKey) }
        if let signup = context["flameySignup"] as? TimeInterval { defaults.set(signup, forKey: signupKey) }
    }

    static func look(mood: FlameMoodKind, date: Date) -> FlameyLook {
        let defaults = UserDefaults.standard
        let owned = Set((defaults.stringArray(forKey: ownedKey) ?? []).compactMap(FlameyItem.init(rawValue:)))
        let choice = defaults.data(forKey: choiceKey)
            .flatMap { try? JSONDecoder().decode(FlameyLookChoice.self, from: $0) } ?? .basic
        let signup = defaults.object(forKey: signupKey) as? TimeInterval
        return FlameyLook.resolve(owned: owned, choice: choice, date: date, mood: mood.props,
                                  signupDate: signup.map(Date.init(timeIntervalSince1970:)), detail: .compact)
    }
}

/// How he is right now, resolved exactly as the home screen widget resolves it.
struct WatchFlameyState: Equatable {
    let mood: FlameMoodKind
    let health: FlameHealth
    let vigor: CGFloat?
    let isAtRisk: Bool
    let dayEnd: Date

    init(streak: Int, miles: Double, goal: Double, now: Date = Date()) {
        let completed = miles >= goal
        let calendar = Calendar.current
        dayEnd = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        let secondsToReset = max(0, dayEnd.timeIntervalSince(now))
        isAtRisk = !completed && streak > 0 && calendar.component(.hour, from: now) >= 18
        health = FlameHealth.forState(isCompleted: completed, distanceIsFresh: true, isAtRisk: isAtRisk,
                                      secondsToReset: completed ? nil : secondsToReset, streak: streak)
        let phase = StreakFlamePhase.forState(isCompleted: completed, distanceIsFresh: true, streak: streak)
        mood = FlameMoodKind.resolve(phase: phase, progress: goal > 0 ? miles / goal : 0, isAtRisk: isAtRisk,
                                     hasActiveWorkout: false, streak: streak, now: now)
        vigor = !completed && streak > 0
            ? Self.wristVigor(min(max(secondsToReset / StreakFlameClock.dayLength, 0), 1)) : nil
    }

    /// The vigor he bottoms out at on the wrist, about 40% of his full size.
    private static let vigorFloor = 0.33

    /// The phone's burn-down ends near nothing, which is a speck in a ring this
    /// small. Squeezing the day into a higher range keeps him shrinking right
    /// up to midnight, where a plain cutoff would freeze him from mid-afternoon.
    private static func wristVigor(_ dayLeft: Double) -> CGFloat {
        CGFloat(vigorFloor + (1 - vigorFloor) * dayLeft)
    }

    /// One short line, sized for the wrist.
    var line: String {
        switch mood {
        case .unlit: return "Light me up!"
        case .sleepy: return "Zzz…"
        case .groggy: return "Mornin'…"
        case .ready: return "Ready when you are"
        case .going: return "Keep going!"
        case .halfway: return "Halfway there!"
        case .almost: return "So close!"
        case .nervous: return "Don't let me go out!"
        case .done: return "Mile done!"
        case .party: return "Milestone day!"
        case .bedtime: return "Night night"
        }
    }
}

/// The dressed, still figure, or his coal with no streak. Same drawing as the
/// iPhone widget, so he looks like the same character on every screen.
struct WatchFlameyView: View {
    let mood: FlameMoodKind
    let health: FlameHealth
    var vigor: CGFloat? = nil
    let size: CGFloat
    var warmth: Double = 0
    /// He stands on the floor of his box and burns down toward it. Inside a
    /// ring that reads as sliding off the bottom, so hold him in the middle.
    var centred = false

    init(state: WatchFlameyState, size: CGFloat, warmth: Double = 0, centred: Bool = false) {
        self.init(mood: state.mood, health: state.health, vigor: state.vigor, size: size, warmth: warmth,
                  centred: centred)
    }

    init(mood: FlameMoodKind, health: FlameHealth, vigor: CGFloat? = nil, size: CGFloat, warmth: Double = 0,
         centred: Bool = false) {
        self.mood = mood
        self.health = health
        self.vigor = vigor
        self.size = size
        self.warmth = warmth
        self.centred = centred
    }

    private var bodyScale: CGFloat {
        if let vigor, health != .dead, health != .blazing { return StreakFlameClock.flameScale(vigor: vigor) }
        return health.bodyScale
    }

    var body: some View {
        Group {
            if mood == .unlit {
                CoalLumpView(size: size * 0.74, showsFace: true, warmth: min(warmth, 1), still: true)
                    .frame(width: size, height: size, alignment: .bottom)
            } else {
                let look = WatchFlameyWardrobe.look(mood: mood, date: Date())
                // Fit a tall hat inside the same height as his bare tip,
                // shrinking him about his feet, as the widget does.
                let reach = 0.98 + FlameyArt.crest(of: look) + look.hoverLift
                FlameyDressedFigure(look: look, health: health, size: size, vigor: vigor, scale: bodyScale, mood: mood)
                    .scaleEffect(min(1, (0.98 + 0.03) / reach), anchor: .bottom)
            }
        }
        .offset(y: centred ? -size * max(0, 1 - bodyScale) * 0.42 : 0)
        .accessibilityHidden(true)
    }
}

// MARK: - The mile

/// The payoff for finishing, on the wrist, in the moment. Sits over the
/// tracker: the workout keeps recording underneath.
struct WatchMileCelebration: View {
    let goal: Double
    let streakBefore: Int
    let onClose: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var arrived = false
    @State private var sparksOut = false

    private let sparkCount = 10

    private var mood: FlameMoodKind {
        FlameMoodKind.isMilestone(streakBefore + 1) ? .party : .done
    }

    private var title: String { goal == 1 ? "Mile done!" : "Goal done!" }

    private var subtitle: String { streakBefore == 0 ? "Day one. Nice start." : "Streak safe today" }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            RadialGradient(colors: [WatchTheme.warning.opacity(0.42), WatchTheme.madRed.opacity(0.18), .clear],
                           center: .center, startRadius: 4, endRadius: 120)
                .ignoresSafeArea()
                .opacity(arrived ? 1 : 0)

            if !reduceMotion { sparks }

            VStack(spacing: 2) {
                WatchFlameyView(mood: mood, health: .blazing, size: 104)
                    .scaleEffect(arrived ? 1 : 0.45, anchor: .bottom)
                Text(title)
                    .font(.system(size: 21, weight: .heavy, design: .rounded))
                    .foregroundColor(WatchTheme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(subtitle)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(WatchTheme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .opacity(arrived ? 1 : 0)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onClose)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) \(subtitle)")
        .accessibilityAddTraits(.isButton)
        .task {
            WKInterfaceDevice.current().play(.success)
            withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.5, dampingFraction: 0.55)) {
                arrived = true
            }
            withAnimation(.easeOut(duration: 1.3)) { sparksOut = true }
            try? await Task.sleep(for: .milliseconds(450))
            WKInterfaceDevice.current().play(.notification)
            try? await Task.sleep(for: .seconds(4))
            if !Task.isCancelled { onClose() }
        }
    }

    private var sparks: some View {
        ZStack {
            ForEach(0..<sparkCount, id: \.self) { i in
                let angle = Double(i) / Double(sparkCount) * 2 * .pi
                Circle()
                    .fill(i.isMultiple(of: 2) ? WatchTheme.warning : WatchTheme.madRedBright)
                    .frame(width: i.isMultiple(of: 3) ? 7 : 5, height: i.isMultiple(of: 3) ? 7 : 5)
                    .offset(x: sparksOut ? cos(angle) * 92 : 0, y: sparksOut ? sin(angle) * 92 : 0)
                    .opacity(sparksOut ? 0 : 1)
            }
        }
        .accessibilityHidden(true)
    }
}

#if DEBUG
/// Fixed numbers for simulator checks and App Store captures:
/// `simctl launch <watch> <bundle> -MADWatchDemo <streak> <miles> <hour> [celebrate]`.
enum WatchDemo {
    struct Values {
        let streak: Int
        let miles: Double
        let now: Date
        let celebrate: Bool
    }

    static let current: Values? = {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-MADWatchDemo"), args.count > i + 3,
              let streak = Int(args[i + 1]), let miles = Double(args[i + 2]), let hour = Int(args[i + 3]) else { return nil }
        let now = Calendar.current.date(bySettingHour: hour, minute: 12, second: 0, of: Date()) ?? Date()
        return Values(streak: streak, miles: miles, now: now, celebrate: args.contains("celebrate"))
    }()
}
#endif
