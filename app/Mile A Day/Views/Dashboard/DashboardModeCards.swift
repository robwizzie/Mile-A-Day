import SwiftUI
import HealthKit

struct DashboardStartMileButton: View {
    let hasActiveWorkout: Bool
    var prominent: Bool = false
    /// Today's goal is already met: the same red button stays (we want
    /// people to keep going), titled for another one.
    var goalDone: Bool = false
    @Binding var showWorkoutView: Bool

    var body: some View {
        Button {
            showWorkoutView = true
        } label: {
            // The day's one action, said once: a play glyph and the words, on
            // flat brand red. It used to stack a play disc, tracked capitals,
            // a chevron, a rim and a red glow, five ways of saying "tap me".
            HStack(spacing: 10) {
                Image(systemName: "play.fill")
                    .madFont(size: prominent ? 15 : 13, weight: .black, maxScale: 1.3)
                    .accessibilityHidden(true)
                Text(buttonTitle)
                    .madFont(size: prominent ? 18 : 16, weight: .heavy, design: .rounded)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 18)
            .padding(.vertical, prominent ? 16 : 13)
            .background(
                RoundedRectangle(cornerRadius: prominent ? 16 : 20, style: .continuous)
                    .fill(MADTheme.Colors.madRed)
            )
            .contentShape(RoundedRectangle(cornerRadius: prominent ? 16 : 20, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var buttonTitle: String {
        if hasActiveWorkout { return String(localized: "Resume workout") }
        return goalDone ? String(localized: "Go another mile") : String(localized: "Start your mile")
    }
}

/// The streak's next rung — and ONLY the streak's. It sits a few points under
/// the day's mile numbers on both heroes, and as a continuous capsule it read
/// as a second distance bar: people asked why their mile was "40% done" after
/// they had finished it. So it is now a row of DAY notches — one per day of
/// the climb from the rung just passed to the one ahead (capped at 12, then
/// each notch stands for a slice of the span) — under a flame title and a
/// "Day 4 of 7" caption. Discrete steps can't be mistaken for a distance, and
/// there is no marker or third label row to collide with what's below.
struct DashboardMilestoneBar: View {
    let streak: Int
    var title: String = String(localized: "Streak milestone")

    private static let maxNotches = 12

    var body: some View {
        if let milestone = StreakMilestone.next(after: streak) {
            let from = StreakMilestone.previous(before: streak)
            let span = max(1, milestone.value - from)
            let done = max(0, min(span, streak - from))
            let notches = min(span, Self.maxNotches)
            // Notches lit = the climb so far, scaled onto the row. A day in
            // hand always lights at least one notch, and the last only lights
            // when the rung is actually reached (it never is here — reaching
            // it moves the target — so a full row is impossible by design).
            let lit = done == 0 ? 0 : max(1, min(notches - 1, Int((Double(done) / Double(span) * Double(notches)).rounded(.down))))

            // One line says it: how far to the next rung, then where you are.
            // It used to say the same fact three times (a STREAK MILESTONE
            // title, "Day 511 of 600" and "89 DAYS TO DAY 600" under the bar).
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    Image(systemName: "flame.fill")
                        .madFont(size: 11, weight: .bold)
                        .foregroundColor(.orange)
                        .accessibilityHidden(true)
                    Text(milestone.daysToGo == 1
                         ? "1 day to Day \(milestone.value)"
                         : "\(milestone.daysToGo) days to Day \(milestone.value)")
                        .madFont(size: 12, weight: .bold, design: .rounded, monospacedDigit: true)
                        .foregroundColor(.white.opacity(0.72))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    // No "Day N" on the right: the streak number sits right
                    // above this row on both heroes.
                    Spacer(minLength: 0)
                }

                HStack(spacing: 3) {
                    ForEach(0..<notches, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(index < lit
                                  ? AnyShapeStyle(LinearGradient(
                                        colors: [
                                            Color(red: 1.0, green: 0.68, blue: 0.14),
                                            Color(red: 1.0, green: 0.34, blue: 0.16)
                                        ],
                                        startPoint: .top,
                                        endPoint: .bottom))
                                  : AnyShapeStyle(Color.white.opacity(0.12)))
                            .frame(height: 6)
                    }
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Streak milestone: day \(streak) of \(milestone.value), \(milestone.daysToGo) days to go")
        }
    }
}

struct FunDashboardBody: View {
    @Environment(\.duoHomeWide) private var duoHomeWide
    @ObservedObject var healthManager: HealthKitManager
    @ObservedObject var userManager: UserManager
    @ObservedObject var friendService: FriendService
    let hasActiveWorkout: Bool
    @Binding var showWorkoutView: Bool
    /// Opens the manual-entry sheet DashboardView hosts.
    let onLogPastWorkout: () -> Void
    /// Replays today's celebration; nil until it has played today.
    var onReplay: (() -> Void)? = nil

    private var state: (distance: Double, goal: Double, progress: Double, completed: Bool) {
        let distance = healthManager.todaysDistance
        let goal = userManager.currentUser.goalMiles
        return (
            distance,
            goal,
            ProgressCalculator.calculateProgress(current: distance, goal: goal),
            ProgressCalculator.isGoalCompleted(current: distance, goal: goal)
        )
    }

    @ViewBuilder
    private var hero: some View {
        FlameBuddyHeroCard(
            healthManager: healthManager,
            userManager: userManager,
            currentDistance: state.distance,
            goalDistance: state.goal,
            progress: state.progress,
            isGoalCompleted: state.completed,
            todaySteps: healthManager.todaysSteps,
            stepGoalMet: StepGoalDayStore.isTodayMet(),
            hasActiveWorkout: hasActiveWorkout,
            distanceIsFresh: healthManager.hasFreshTodaysDistance,
            showWorkoutView: $showWorkoutView,
            onReplay: onReplay
        )
        // The stat frame grows with its text (statFrameHeight), but the
        // column beside Flamey is ~155pt wide, so it caps here.
        .madTypeCap(.madFixedChromeCap)
        .tourAnchor("home.hero")
    }

    /// The day's cards. A multi-view result on purpose, read the note below.
    @ViewBuilder
    private var dayCards: some View {
        // NOT wrapped in a stack: FunStartCard's parts (the share card,
        // the buddy pill) and the Plus card each hide on their own, and an
        // EMPTY wrapper stack still takes a slot in this one, so a done,
        // shared day had a doubled gap under the hero.
        FunStartCard(
            healthManager: healthManager,
            userManager: userManager,
            trustedDone: (state.completed && healthManager.hasFreshTodaysDistance)
                || StepGoalDayStore.isTodayMet(),
            hasActiveWorkout: hasActiveWorkout,
            showWorkoutView: $showWorkoutView,
            onLogPastWorkout: onLogPastWorkout
        )
        // Friend requests come right after the day's action (they used to
        // lead the page, which pushed Start under the tab bar on small
        // phones). Draws nothing when there are none.
        FriendRequestsHomeRow(friendService: friendService)
        // Mile A Day+ at the moment it would have helped: hides itself
        // unless the streak is at risk or Plus would already hold a Save.
        // Its body is an always-present (empty) stack, so it shares a
        // ZERO-spacing stack with the medal card and brings its own gap:
        // as its own item here it left a doubled gap under the hero.
        VStack(spacing: 0) {
            PlusStreakCard(streak: userManager.currentUser.streak, bottomSpacing: 18)
            NextMedalCard(userManager: userManager, style: .fun)
        }
    }

    @AppStorage(DashboardCards.funKey) private var cardsRaw = ""

    /// One card fits under the day's cards on the wide spread, beside the hero.
    private var soleCard: Bool { DashboardCards.ordered(in: cardsRaw, for: .fun).count == 1 }

    private var cardsBlock: some View {
        DashboardCardsBlock(
            style: .fun,
            healthManager: healthManager,
            userManager: userManager,
            friendService: friendService
        )
    }

    var body: some View {
        VStack(spacing: 18) {
            if duoHomeWide {
                HStack(alignment: .top, spacing: 16) {
                    hero.frame(maxWidth: .infinity)
                    VStack(spacing: 18) {
                        dayCards
                        if soleCard { cardsBlock.environment(\.duoHomeWide, false) }
                    }
                    .frame(maxWidth: .infinity)
                }
            } else {
                hero
                dayCards
            }

            // Everything below the day's cards is the user's to arrange
            // (DashboardCards): default here is just the daily challenge.
            if !(duoHomeWide && soleCard) { cardsBlock }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        // Everything else on the dashboard is cards whose rows wrap.
        .madTypeCap(.madCardCap)
    }

    private var statusColor: Color {
        if state.completed && healthManager.hasFreshTodaysDistance { return .green }
        if StepGoalDayStore.isTodayMet() { return .green }
        if userManager.currentUser.isStreakAtRisk { return .red }
        return .orange
    }
}

/// The longest-ever streak, rendered under the hero flame in one of two moods:
/// a faint "ghost" target while the current run chases the record, or a gold
/// record chip while the user is living it (streak >= 7 so brand-new accounts
/// don't get a record chip on day 1). Renders nothing when there's no
/// meaningful record yet — both heroes share this row.
///
/// It lives in the hero's NARROW right-hand column, roughly 150pt wide. That
/// is the whole design constraint: the old version put "LONGEST EVER" and
/// "447 days and counting" in one capsule and both ends truncated, so it read
/// "LONGE… 447 days an…". The record chip therefore carries ONE short label
/// and no number — the streak count is already the biggest thing on the card,
/// directly above it, and repeating it is what cost the space.
private struct RecordGhostRow: View {
    let streak: Int
    let longest: Int
    /// False where the hero already crowns the streak itself (the Modern
    /// hero's headline box), so the record is never stated twice.
    var showsRecord: Bool = true

    private var atRecord: Bool { longest > 0 && streak >= longest && streak >= 7 }
    private var chasing: Bool { longest > streak && longest >= 3 }
    private let gold = Color(red: 1.0, green: 0.78, blue: 0.25)

    var body: some View {
        if atRecord, showsRecord {
            // Deliberately NOT a filled capsule. As one it was a third pill in
            // a column that already had a bordered box and a pill, and it read
            // as tacked on. A bare crown + label sits quietly next to the
            // stats instead of competing with them.
            HStack(spacing: 5) {
                Image(systemName: "crown.fill")
                    .madFont(size: 9, weight: .black)
                Text("ALL-TIME BEST")
                    .madFont(size: 10, weight: .black, design: .rounded)
                    .tracking(0.8)
            }
            .foregroundColor(gold)
            .fixedSize()
            .padding(.top, 10)
        } else if chasing {
            // One Text, not two competing ones: in a narrow column a pair of
            // labels with a Spacer between them both truncate rather than one
            // of them winning.
            HStack(spacing: 5) {
                Image(systemName: "flame")
                    .madFont(size: 9, weight: .bold)
                Text("BEST \(longest) · \(longest - streak) TO GO")
                    .madFont(size: 10, weight: .heavy, design: .rounded)
                    .tracking(0.4)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundColor(.white.opacity(0.6))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.05))
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.09), lineWidth: 1))
            )
            .padding(.top, 10)
        }
    }
}

private struct ModernHeroStatLine: View {
    let icon: String
    let value: String
    let unit: String
    let label: String
    let tint: Color
    /// Fun hero: "1.00 mi to go" on ONE baseline (the stacked form spent
    /// two lines per fact). Falls back to stacked when it doesn't fit.
    var inline: Bool = false

    var body: some View {
        if inline {
            ViewThatFits(in: .horizontal) {
                inlineForm
                stackedForm
            }
        } else {
            stackedForm
        }
    }

    private var inlineForm: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: icon)
                .madFont(size: 11, weight: .bold, maxScale: 1.3)
                .foregroundColor(tint)
                .accessibilityHidden(true)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(value)
                    .madFont(size: 20, weight: .black, design: .rounded, monospacedDigit: true)
                    .foregroundColor(.white)
                if !unit.isEmpty {
                    Text(unit)
                        .madFont(size: 12, weight: .bold, design: .rounded)
                        .foregroundColor(.white.opacity(0.55))
                }
            }
            Text(label)
                .madFont(size: 12, weight: .semibold, design: .rounded)
                .foregroundColor(.white.opacity(0.5))
        }
        .lineLimit(1)
        .fixedSize()
        .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
    }

    private var stackedForm: some View {
        // The number leads; what it means sits under it in plain words, with
        // the state colour on a small glyph rather than a filled icon circle.
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .madFont(size: 22, weight: .black, design: .rounded, monospacedDigit: true)
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.60)
                Text(unit)
                    .madFont(size: 12, weight: .bold, design: .rounded)
                    .foregroundColor(.white.opacity(0.55))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .madFont(size: 10, weight: .bold, maxScale: 1.3)
                    .foregroundColor(tint)
                    .accessibilityHidden(true)
                Text(label)
                    .madFont(size: 12, weight: .semibold, design: .rounded)
                    .foregroundColor(.white.opacity(0.5))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
    }
}

private struct ModernHeroDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.07))
            .frame(height: 1)
            .padding(.vertical, 4)
    }
}

/// The stat lines beside the streak hero — today's mileage, today's best
/// pace and the time left to run.
///
/// BOTH dashboard styles render this exact view. They used to build their own
/// columns and had drifted apart (Fun showed two stats, Modern three, with
/// different labels), so the same day read as different numbers depending on
/// which dashboard you had picked. Anything added here lands on both. Steps
/// aren't here: the Steps tile sits directly below the hero, and the same
/// number twice in one screenful read as clutter. The middle row answers the
/// question the day is asking: "how far to go?" until the goal is met, then
/// today's best pace (or that the goal's done). A bare "Best pace --" read as
/// a stat with no answer, and didn't say whether it meant today, the streak
/// or all time — it was always today's.
private struct HeroStatColumn: View {
    let currentDistance: Double
    let goalMiles: Double
    let fastestPace: TimeInterval?
    /// Time until local midnight, e.g. "6h 30m".
    let timeLeftText: String
    let statusColor: Color
    /// Today's steps, and whether they reached 10k — a day the steps finished
    /// answers "how far to go?" with "Done", not miles still owed.
    let todaySteps: Int
    let stepGoalMet: Bool
    /// Opens the Steps screen (the Steps tile that used to be its door is
    /// gone: it repeated the goal bars' step count).
    var onOpenSteps: (() -> Void)? = nil
    /// Fun hero: one line per fact, no divider, and no "left today" line
    /// (the time rides in the status pill under the streak).
    var compact: Bool = false

    private var goal: Double { max(goalMiles, 0.01) }
    private var milesDone: Bool { ProgressCalculator.isGoalCompleted(current: currentDistance, goal: goal) }
    private var dayDone: Bool { milesDone || stepGoalMet }

    var body: some View {
        // Two lines, not three: today's distance is the first number in the
        // "either one" goal bars directly under this column, and saying it
        // twice in one screenful read as clutter.
        //
        // Once the day is done the bars fold to one "Done" line and the time
        // left stops mattering, so the column takes over the facts the bars
        // no longer show: today's best pace, and the steps (or, on a day the
        // steps finished, the distance).
        VStack(spacing: compact ? 2 : 0) {
            middleLine
            if !compact { ModernHeroDivider() }
            if dayDone {
                doneSecondLine
            } else if !compact {
                ModernHeroStatLine(
                    icon: "clock.fill",
                    value: timeLeftText.isEmpty ? "--" : timeLeftText,
                    unit: "",
                    label: String(localized: "left today"),
                    tint: statusColor,
                    inline: compact
                )
            }
        }
    }

    @ViewBuilder
    private var doneSecondLine: some View {
        if milesDone {
            Button {
                MADHaptics.tap()
                onOpenSteps?()
            } label: {
                ModernHeroStatLine(
                    icon: "shoeprints.fill",
                    value: todaySteps.formatted(),
                    unit: "steps",
                    label: "today",
                    tint: .orange,
                    inline: compact
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(onOpenSteps == nil)
            .accessibilityHint("Opens your steps")
        } else {
            ModernHeroStatLine(
                icon: "figure.walk",
                value: currentDistance.distanceText,
                unit: DistanceUnits.current.abbreviation,
                label: "today",
                tint: MADTheme.Colors.walkBlue,
                inline: compact
            )
        }
    }

    @ViewBuilder
    private var middleLine: some View {
        // No "this week" line once the day is done: the week's miles (and a
        // row of day dots on it) read as clutter beside the streak. Done
        // shows today's best pace, or that the goal is done.
        if !dayDone {
            ModernHeroStatLine(
                icon: "flag.checkered",
                value: max(goal - currentDistance, 0).distanceToGoText,
                unit: DistanceUnits.current.abbreviation,
                label: String(localized: "to go"),
                tint: MADTheme.Colors.walkBlue,
                inline: compact
            )
        } else if let pace = fastestPace {
            ModernHeroStatLine(
                icon: "timer",
                value: Self.formatPace(pace),
                unit: DistanceUnits.current.paceSuffix,
                label: String(localized: "today's best pace"),
                tint: MADTheme.Colors.walkBlue,
                inline: compact
            )
        } else {
            ModernHeroStatLine(
                icon: "checkmark.circle.fill",
                value: "Done",
                unit: "",
                label: String(localized: "today's goal"),
                tint: MADTheme.Colors.success,
                inline: compact
            )
        }
    }

    /// `pace` is MINUTES per mile; shown per display unit.
    private static func formatPace(_ pace: TimeInterval) -> String {
        let shown = pace.pacePerDisplayUnit
        let minutes = Int(shown)
        let seconds = Int((shown - Double(minutes)) * 60)
        return String(format: "%d:%02d", minutes, seconds)
    }
}

/// Option C of "1 mile OR 10,000 steps": the day's two ways to finish, side
/// by side inside the hero, so the rule is visible where the day is.
///
/// Both heroes render this one view (Modern under the flame row, Fun under
/// the buddy), so the two styles can't explain the goal differently. Sized
/// for the narrowest phone first: at 320pt (an SE under Display Zoom) each
/// path gets ~94pt, so every label is one short line that scales down
/// before it would truncate, and nothing has a fixed width.
private struct DailyGoalBars: View {
    let miles: Double
    let goalMiles: Double
    let steps: Int
    let stepGoalMet: Bool
    /// Set once today's celebration has played: the done line offers it
    /// again (it was a gold-rimmed banner above the hero, a third "you're
    /// done" on one screen).
    var onReplay: (() -> Void)? = nil
    /// Fun only: a full-width Share button under the done line. Sharing was
    /// a tap on the hero card itself, which nothing on screen pointed to.
    var onShare: (() -> Void)? = nil
    /// Opens the Steps screen from the steps half.
    var onOpenSteps: (() -> Void)? = nil

    private var goal: Double { max(goalMiles, 0.01) }
    private var milesDone: Bool { ProgressCalculator.isGoalCompleted(current: miles, goal: goal) }
    private var done: Bool { milesDone || stepGoalMet }
    private var milesProgress: Double { min(max(miles / goal, 0), 1) }
    private var stepsProgress: Double {
        stepGoalMet ? 1 : min(max(Double(steps) / Double(ProgressCalculator.dailyStepGoal), 0), 1)
    }

    /// "1" / "2" / "1.61" in the display unit — a whole goal reads without
    /// decimals, so "/ 1 mi" fits beside today's miles.
    private var goalText: String {
        let value = goal.inDisplayUnit
        let isWhole = abs(value - value.rounded()) < 0.005
        return isWhole ? String(Int(value.rounded())) : String(format: "%.2f", value)
    }

    var body: some View {
        if done {
            doneLine
        } else {
            bars
        }
    }

    /// The finished day in one line. The two bars (and the steps one stuck
    /// part-way, which read as unfinished business) said nothing once either
    /// path was done.
    private var doneLine: some View {
        VStack(spacing: 10) {
            doneRow
            if let onShare {
                Button {
                    MADHaptics.action()
                    onShare()
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "square.and.arrow.up")
                            .madFont(size: 14, weight: .heavy, maxScale: 1.3)
                            .accessibilityHidden(true)
                        Text("Share your streak")
                            .madFont(size: 15, weight: .heavy, design: .rounded, maxScale: 1.3)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    // Tinted, not filled: the red Start button under the
                    // hero is the screen's one primary action.
                    .foregroundColor(.orange)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Capsule().fill(Color.orange.opacity(0.16)))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .padding(.bottom, onShare == nil ? 0 : 3)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.045))
        )
    }

    private var doneRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .madFont(size: 15, weight: .bold, maxScale: 1.3)
                .foregroundColor(MADTheme.Colors.success)
                .accessibilityHidden(true)
            Text(milesDone ? "Done · \(miles.distanceFormatted)" : "Done · \(steps.formatted()) steps")
                .madFont(size: 14, weight: .heavy, design: .rounded, monospacedDigit: true)
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Spacer(minLength: 4)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) { doneActions(labels: true) }
                HStack(spacing: 6) { doneActions(labels: false) }
            }
        }
    }

    @ViewBuilder
    private func doneActions(labels: Bool) -> some View {
        if let onReplay {
            doneAction("Replay", icon: "sparkles", labels: labels, action: onReplay)
        }
    }

    private func doneAction(_ title: String, icon: String, labels: Bool, action: @escaping () -> Void) -> some View {
        Button {
            MADHaptics.tap()
            action()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .madFont(size: 11, weight: .bold, maxScale: 1.3)
                    .accessibilityHidden(true)
                if labels {
                    Text(title)
                        .madFont(size: 12, weight: .bold, design: .rounded)
                        .lineLimit(1)
                }
            }
            .foregroundColor(.white.opacity(0.85))
            .padding(.horizontal, labels ? 10 : 9)
            .frame(minHeight: 30)
            .background(Capsule().fill(Color.white.opacity(0.08)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .accessibilityLabel(title)
    }

    private var bars: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("Today · either one counts")
                    .madFont(size: 12, weight: .bold, design: .rounded)
                    .foregroundColor(.white.opacity(0.55))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 0)
            }

            HStack(alignment: .bottom, spacing: 8) {
                path(
                    icon: "figure.run",
                    value: miles.distanceText,
                    target: "/ \(goalText) \(DistanceUnits.current.abbreviation)",
                    progress: milesProgress,
                    tint: milesDone ? MADTheme.Colors.success : MADTheme.Colors.madRed
                )
                Text("or")
                    .madFont(size: 12, weight: .semibold, design: .rounded)
                    .foregroundColor(.white.opacity(0.6))
                    .padding(.horizontal, 2)
                    .fixedSize()
                    .padding(.bottom, 1)
                    .accessibilityHidden(true)
                Button {
                    MADHaptics.tap()
                    onOpenSteps?()
                } label: {
                    path(
                        icon: "shoeprints.fill",
                        value: steps.formatted(),
                        target: "/ 10k",
                        progress: stepsProgress,
                        tint: stepGoalMet ? MADTheme.Colors.success : .orange
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(onOpenSteps == nil)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.045))
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAction(named: "Open steps") { onOpenSteps?() }
    }

    private func path(icon: String, value: String, target: String, progress: Double, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Image(systemName: icon)
                    .madFont(size: 11, weight: .bold, maxScale: 1.2)
                    .foregroundColor(tint)
                Text(value)
                    .madFont(size: 13, weight: .heavy, design: .rounded, monospacedDigit: true)
                    .foregroundColor(.white)
                Text(target)
                    .madFont(size: 11, weight: .bold, design: .rounded)
                    .foregroundColor(.white.opacity(0.45))
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)

            Capsule()
                .fill(Color.white.opacity(0.10))
                .frame(height: 5)
                .overlay(alignment: .leading) {
                    GeometryReader { geo in
                        Capsule()
                            .fill(tint)
                            .frame(width: max(5, geo.size.width * progress), height: 5)
                    }
                }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var accessibilityText: String {
        let milesPart = String(localized: "\(miles.distanceText) of \(goalText) \(DistanceUnits.current.plural)")
        let stepsPart = String(localized: "\(steps.formatted()) of 10,000 steps")
        let status = done ? String(localized: "Today's goal is done.") : String(localized: "Either one finishes today.")
        return String(localized: "\(milesPart), or \(stepsPart). \(status)")
    }
}

private struct ModernMetricPill: View {
    let icon: String
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .madFont(size: 13, weight: .bold, maxScale: 1.25)
                .foregroundColor(tint)
                .frame(width: 24, height: 24)
                .background(Circle().fill(tint.opacity(0.15)))
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .madFont(size: 10, weight: .bold, design: .rounded)
                    .foregroundColor(.white.opacity(0.42))
                Text(value)
                    .madFont(size: 15, weight: .heavy, design: .rounded, monospacedDigit: true)
                    .foregroundColor(.white.opacity(0.92))
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.055))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
        )
    }
}

/// The medal you're closest to, in place of the old Medals tile.
///
/// That tile said one number three ways ("84/105", "80% unlocked", "21 left
/// to collect") under three random recent medals. A collection count doesn't
/// move day to day; the next medal does, and it says what today's walk is
/// for. The count stays, small, on the right. Uses `MedalProgress` — the
/// same measure the medal grid and its detail screen use — so the three
/// can't disagree. The Steps tile that sat beside it is gone: it repeated
/// the goal bars' step count (they open the Steps screen now).
private struct NextMedalCard: View {
    @ObservedObject var userManager: UserManager
    let style: DashboardStyle

    private struct Summary {
        let next: Badge?
        let progress: MedalProgress?
        let latest: Badge?
        let earned: Int
        let total: Int
    }

    /// `getAllBadges()` builds and sorts the whole catalogue; the answer only
    /// moves when the shelf or one of the measures does.
    private static var cache: (key: String, value: Summary)?

    private var summary: Summary {
        let user = userManager.currentUser
        let earnedBadges = user.badges.filter { !$0.isLocked }
        let key = "\(user.badges.count)|\(earnedBadges.count)|\(user.streak)|\(user.totalMiles)|\(user.mostMilesInOneDay)"
        if let cached = Self.cache, cached.key == key { return cached.value }
        let all = user.getAllBadges()
        var best: (badge: Badge, progress: MedalProgress)?
        for badge in all where badge.isLocked {
            guard let progress = MedalProgress.forLocked(badge, user: user) else { continue }
            if progress.fraction > (best?.progress.fraction ?? -1) { best = (badge, progress) }
        }
        let value = Summary(
            next: best?.badge,
            progress: best?.progress,
            latest: earnedBadges.max { $0.dateAwarded < $1.dateAwarded },
            earned: earnedBadges.count,
            total: all.count
        )
        Self.cache = (key, value)
        return value
    }

    var body: some View {
        let info = summary
        NavigationLink {
            BadgesView(userManager: userManager, initialBadge: nil)
        } label: {
            HStack(spacing: 14) {
                if let badge = info.next ?? info.latest {
                    MedalView(badge: badge, size: 52, showShimmer: false)
                        .frame(width: 52, height: 52)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(info.next == nil ? "Medals" : "Next medal · \(info.earned) of \(info.total)")
                        .madFont(size: 12, weight: .semibold, design: .rounded, monospacedDigit: true)
                        .foregroundColor(.white.opacity(0.5))
                        .lineLimit(2)
                        .minimumScaleFactor(0.75)
                    if let next = info.next, let progress = info.progress {
                        Text(next.name)
                            .madFont(size: 16, weight: .heavy, design: .rounded)
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                        MedalProgressBar(fraction: progress.fraction, tint: next.rarity.color)
                            .padding(.vertical, 2)
                        Text(progress.label)
                            .madFont(size: 12, weight: .semibold, design: .rounded, monospacedDigit: true)
                            .foregroundColor(.white.opacity(0.55))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    } else {
                        Text(info.earned >= info.total && info.total > 0
                             ? "All \(info.total) collected"
                             : "\(info.earned) of \(info.total) collected")
                            .madFont(size: 16, weight: .heavy, design: .rounded, monospacedDigit: true)
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .madFont(size: 11, weight: .bold)
                    .foregroundColor(.white.opacity(0.3))
                    .accessibilityHidden(true)
            }
            .padding(DashboardCardSurface.padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DashboardCardSurface(style: style))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens your medals")
    }
}

private struct FlameBuddyHeroCard: View {
    @ObservedObject private var injuryPause = InjuryPauseState.shared
    /// Redraws him when the Closet closes — his look is read from
    /// UserDefaults (`FlameyFacts`), which nothing else here observes.
    @ObservedObject private var closetLink = FlameyClosetLink.shared

    /// The number to print on the hero. A pause FREEZES a specific value, and
    /// `currentUser.streak` is not it: the local copy is quarantined and
    /// raise-only, so a pause started after a couple of missed days (the normal
    /// case — you back-date it once you're out of the hospital) leaves it at 0
    /// while the server has correctly frozen 412.
    private var heroStreakValue: Int {
        injuryPause.status?.active?.frozen_streak ?? userManager.currentUser.streak
    }

    /// Distance from the hero's top edge to the ground the buddy stands on.
    /// Held constant so the art keeps its footing when the card's height moves.
    private static let groundBaseline: CGFloat = 196

    /// The stat frame's height: 258 exactly at the default text size, grown
    /// with the column's text (`.largeTitle` grows ~6% at xLarge and ~12% at
    /// xxLarge, which is about what the column's content measures out to).
    /// The buddy and its ground are anchored to the TOP and stay put, so the
    /// extra height lands under the stats, where the text needs it.
    @MADScaledMetric(relativeTo: .largeTitle) private var statFrameHeight: CGFloat = 246
    /// Flamey, his ground and the Closet button drawn at 90%: the whole
    /// hero is shorter and the stat column fits its contents. One scale on
    /// the column keeps every internal offset (ground under feet, button
    /// under ground) as it was.
    private static let flameyScale: CGFloat = 0.8
    /// The 0.9 the column was drawn at before the stat column was condensed:
    /// the Closet button keeps that size (counter-scaled), so its tap target
    /// doesn't shrink with him.
    private static let closetButtonScale: CGFloat = 0.9
    /// His column's unscaled height (frame top to just under the Closet
    /// button): the 246pt the hero reserved at the old 0.9 scale, unscaled.
    /// A FIXED design value, never the text-scaled `statFrameHeight`: his
    /// art doesn't grow with Dynamic Type, the stats do.
    private static let buddyColumnHeight: CGFloat = 246 / 0.9
    /// Extra room for the counter-scaled Closet button's lower edge.
    private static let closetOverhang: CGFloat = 6
    /// The stat column's measured natural height (`funStatRows`). The hero is
    /// as tall as the TALLER of his scaled column and the stats, so large
    /// text grows the card and nothing is ever clipped; never a predicted
    /// height.
    @State private var statsHeight: CGFloat = 0

    @ObservedObject var healthManager: HealthKitManager
    @ObservedObject var userManager: UserManager
    let currentDistance: Double
    let goalDistance: Double
    let progress: Double
    let isGoalCompleted: Bool
    /// Today's step count, for the hero's step bar.
    let todaySteps: Int
    /// Today's steps reached 10k — see ModernHeroCard.stepGoalMet.
    let stepGoalMet: Bool
    let hasActiveWorkout: Bool
    let distanceIsFresh: Bool
    @Binding var showWorkoutView: Bool
    var onReplay: (() -> Void)? = nil
    /// The Steps screen, opened from the goal bars' steps half or the
    /// column's steps line (the Steps tile that was its door is gone).
    @State private var showSteps = false

    @State private var timeRemainingText = ""
    @State private var timer: Timer?
    @State private var showShareSheet = false
    @State private var showTokens = false
    @ObservedObject private var tokensState = StreakTokensState.shared
    /// The last poke on the buddy — the squash plays from it; the quip is
    /// live until the clear task fires.
    @State private var pokedAt: Date?
    @State private var pokeQuip: String?
    @State private var pokeClearTask: Task<Void, Never>?
    /// The local day a poke woke him, so he stays up for the rest of that
    /// morning — across tab switches and relaunches, not just this view's
    /// lifetime. A new day's date never matches, so he sleeps in again.
    @AppStorage("flameyWokenDayV1") private var flameyWokenDay = ""
    /// The play gesture in flight (high five / refuse / tickle / feed) — the
    /// buddy view plays it from `reactionAt`; its line rides the poke-quip
    /// channel, so it can never share the screen with another bubble.
    @State private var reaction: FlameMood.Reaction?
    @State private var reactionAt: Date?
    /// The previous tap, for double-tap detection without delaying the poke.
    @State private var lastTapAt: Date?
    /// Today's "Flamey remembers" facts — computed off-main once per
    /// appearance / day / completion change, never in `body`.
    @State private var memory: FlameyMemory?

    private var trustedDone: Bool { (isGoalCompleted && distanceIsFresh) || stepGoalMet }
    /// The flame reads the DAY: a mile or 10k steps (see ModernHeroCard).
    private var dayCompleted: Bool { isGoalCompleted || stepGoalMet }
    private var dayFresh: Bool { distanceIsFresh || stepGoalMet }
    /// The nearer of the two ways to finish, for his mood and the coals.
    private var dayProgress: Double {
        max(progress, Double(todaySteps) / Double(ProgressCalculator.dailyStepGoal))
    }

    /// The same stamp the widget compares against (FlameyMoodCore.swift).
    private static func localDayStamp(_ date: Date = Date()) -> String {
        FlameMoodKind.dayStamp(date)
    }

    /// What the flame is feeling: resolved from the same state the phase and
    /// health already read, so it can never disagree with the face.
    private var mood: FlameMood {
        var mood = FlameMood.resolve(
            phase: flamePhase,
            progress: min(dayProgress, 1),
            isAtRisk: userManager.currentUser.isStreakAtRisk && !trustedDone,
            hasActiveWorkout: hasActiveWorkout,
            streak: heroStreakValue,
            wokenToday: flameyWokenDay == Self.localDayStamp()
        )
        mood.pokedAt = pokedAt
        mood.pokeQuip = pokeQuip
        mood.reaction = reaction
        mood.reactionAt = reactionAt
        let today = Date()
        mood.holiday = HolidayCalendar.holiday(on: today)
        mood.isAnniversary = FlameyFacts.signupDate.map { HolidayCalendar.isAnniversary(of: $0, on: today) } ?? false
        mood.memoryLine = memory?.line(for: mood.kind, dayIndex: FlameyMemory.dayIndex(today))
        return mood
    }

    /// What he wears — gear from the longest streak, the day's outfit, the
    /// mood's props — resolved from durable facts, never stored.
    private func look(for mood: FlameMood) -> FlameyLook? {
        FlameyFacts.look(mood: mood.kind)
    }

    /// Recomputes `memory` when any input to it moves.
    private var memoryKey: String {
        "\(Self.localDayStamp())|\(heroStreakValue)|\(trustedDone)|\(healthManager.cachedWorkouts.count)|\(healthManager.todaysWorkouts.count)"
    }

    private func refreshMemory() async {
        let result = await FlameyMemory.compute(
            cachedWorkouts: healthManager.cachedWorkouts,
            todaysWorkouts: healthManager.todaysWorkouts,
            goalMiles: goalDistance,
            streak: heroStreakValue,
            longestStreak: userManager.currentUser.longestStreak ?? 0,
            doneToday: trustedDone
        )
        memory = result
    }

    /// Shows a line on the poke-quip channel for `seconds`, then hands the
    /// bubble back to the mood.
    private func say(_ line: String, for seconds: Double = 2.4) {
        pokeQuip = line
        pokeClearTask?.cancel()
        pokeClearTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(Int(seconds * 1000)))
            guard !Task.isCancelled else { return }
            pokeQuip = nil
        }
    }

    private func react(_ reaction: FlameMood.Reaction, line: String? = nil) {
        self.reaction = reaction
        reactionAt = Date()
        say(line ?? FlameMood.reactionQuips(reaction).randomElement() ?? "Hey!")
    }

    /// A tap. The FIRST tap pokes immediately (no double-tap wait delaying
    /// every poke); a second one within 0.35 s upgrades it to a high five —
    /// or, before the mile is in, a head-shake: earn it first.
    private func handleTap() {
        let now = Date()
        if let last = lastTapAt, now.timeIntervalSince(last) < 0.35 {
            lastTapAt = nil
            if trustedDone {
                MADHaptics.success()
                react(.highFive)
            } else {
                MADHaptics.warning()
                react(.refuse)
            }
            return
        }
        lastTapAt = now
        poke()
    }

    /// A horizontal rub across him.
    private func tickle() {
        MADHaptics.tap()
        react(.tickle)
    }

    /// Long-press: feed him today's Well Earned treat — if at least one whole
    /// one has been earned today; otherwise he asks for it.
    private func feed() {
        // Never a drink: an alcoholic pick feeds him a donut, earned in donuts.
        let treat = FlameMood.food(for: CalorieTreat.current)
        let cached = healthManager.cachedWorkouts
        let todays = healthManager.todaysWorkouts
        Task { @MainActor in
            let kcal = await CalorieLedger.workoutKilocalories(
                period: .today, cachedWorkouts: cached, todaysWorkouts: todays)
            let earned = treat.kcalPerUnit > 0 ? kcal / treat.kcalPerUnit : 0
            if earned >= 1 {
                MADHaptics.success()
                react(.feed(treat))
            } else {
                MADHaptics.tap()
                say(FlameMood.hungryQuip(treat))
            }
        }
    }

    /// Tapping the buddy pokes him (the rest of the card still opens the
    /// share sheet — a child gesture wins over the card's). The quip stays
    /// up 2.4s, then the mood bubble gets its turn back.
    private func poke() {
        MADHaptics.emphasis()
        // The line answers the mood he was IN when poked — so poking a
        // sleeper gets the startle, and the same poke wakes him (the mood
        // flips to .groggy: eyes open, zzz's gone). Bedtime is NOT persisted:
        // he grumbles with his eyes open while the line is up, then dozes
        // straight back off.
        let before = mood.kind
        if before == .sleepy {
            flameyWokenDay = Self.localDayStamp()
            // The home-screen Flamey wakes with him (one reload, once a day).
            WidgetDataStore.save(flameyWokenDay: flameyWokenDay)
        }
        pokedAt = Date()
        say(FlameMood.pokeQuips(for: before).randomElement() ?? "Hey!")
    }
    private var health: FlameHealth {
        FlameHealth.forState(
            isCompleted: dayCompleted,
            distanceIsFresh: dayFresh,
            isAtRisk: userManager.currentUser.isStreakAtRisk,
            secondsToReset: userManager.currentUser.timeUntilStreakReset,
            streak: userManager.currentUser.streak
        )
    }

    private var flamePhase: StreakFlamePhase {
        StreakFlamePhase.forState(
            isCompleted: dayCompleted,
            distanceIsFresh: dayFresh,
            streak: userManager.currentUser.streak
        )
    }

    /// A streak token is carrying today (almost always an Assist a friend's
    /// mile paid for). The hero must not go on saying "Streak at risk" about
    /// a day that is already safe — that is the same contradiction the
    /// friends row had, on the screen the owner looks at most. Suppressed
    /// once the mile is genuinely in: the server refunds the coverage on that
    /// upload, and a finished day is a done day.
    private var savedToday: CoveredDate? {
        guard !trustedDone else { return nil }
        return tokensState.payload?.today_covered
    }

    private var statusColor: Color {
        // Nothing about a paused streak is urgent: it can't break today, so the
        // at-risk red (and the amber "running out of day") would be lying.
        if injuryPause.isPaused { return MADTheme.Colors.warning }
        if trustedDone { return .green }
        // Neither is a covered day. The mile is still worth running (it hands
        // the token back), so this stays a live colour rather than going
        // green — but it is not RED.
        if savedToday != nil { return SavedDayStyle.tint }
        if userManager.currentUser.isStreakAtRisk { return MADTheme.Colors.madRed }
        return .orange
    }

    /// Buddy size for a stat frame `width` wide (his column is 48% of it).
    private func buddySize(forWidth width: CGFloat) -> CGFloat {
        min(max(width * 0.48 * 1.14, 176), min(216, statFrameHeight * 0.90))
    }

    /// Room reserved ABOVE the usual layout so nothing he wears or says
    /// leaves the card: his tallest point (hat crest + hover + legs) plus a
    /// two-line bubble over it (`FlameyArt.extentAboveView`), minus what the
    /// card already had over him — 36pt of card padding less the frame's
    /// −28 offset, plus the frame's own slack above his square (0.17·size).
    /// Measured at the blazing scale (his biggest) so the card doesn't
    /// breathe as he burns down through the day. A crown on rocket boots
    /// used to be sliced at the card top and a Pixel bubble sat over the
    /// "Replay today's celebration" banner above the hero.
    private func headroom(for look: FlameyLook?, buddySize: CGFloat) -> CGFloat {
        guard let look, !injuryPause.isPaused else { return 0 }
        let extent = FlameyArt.extentAboveView(look: look, size: buddySize, scale: FlameHealth.blazing.bodyScale,
                                               fit: 1 / (1 + look.standLift), bubble: true)
        return max(0, (extent - (8 + 0.17 * buddySize) + 6).rounded(.up))
    }

    /// The taller of his scaled column (with the outfit's headroom, so rocket
    /// boots, crowns and his bubble stay inside) and the measured stats.
    private func heroHeight(top: CGFloat) -> CGFloat {
        let buddy = (Self.buddyColumnHeight + top) * Self.flameyScale + Self.closetOverhang
        return max(buddy, statsHeight + Self.saversRoom)
    }

    /// The strip at the top of the stat column the savers' shield owns, so
    /// the streak number never runs under it. Fixed: the shield's font caps
    /// at 1.3× (6pt inset + ~18pt glyph at the cap).
    private static let saversRoom: CGFloat = 24

    /// The stat frame's width, measured (the headroom needs his size BEFORE
    /// the frame's height is set). 0 until the first layout pass.
    @State private var heroFrameWidth: CGFloat = 0

    var body: some View {
        let currentMood = mood
        let heroLook = look(for: currentMood)
        let top = heroFrameWidth > 0 ? headroom(for: heroLook, buddySize: buddySize(forWidth: heroFrameWidth)) : 0
        return VStack(spacing: 14) {
            GeometryReader { geo in
                let leftWidth = geo.size.width * 0.48
                let rightWidth = geo.size.width - leftWidth - 12
                let buddySize = buddySize(forWidth: geo.size.width)

                HStack(alignment: .top, spacing: 12) {
                    ZStack(alignment: .top) {
                        // A paused streak is not a point on the flame's daily
                        // lifecycle, so it gets no phase — it replaces the
                        // figure outright. Nothing is burning down, so nothing
                        // should shrink with the clock.
                        if injuryPause.isPaused {
                            InjuredFlameBuddyView(size: buddySize, look: FlameyFacts.look())
                                .frame(width: buddySize * 1.50, height: buddySize * 1.34)
                                .offset(y: -28)
                        } else {
                            FlameBuddyView(
                                health: health,
                                size: buddySize,
                                phase: flamePhase,
                                dayEnd: StreakFlameClock.nextLocalMidnight(),
                                coalWarmth: min(dayProgress, 1),
                                mood: currentMood,
                                look: heroLook,
                                // His column is narrow: the stat column sits
                                // just to his right and the card edge to his
                                // left, so the cape/trail and companion
                                // squeeze in close.
                                wardrobeReach: 0.62
                            )
                            .frame(width: buddySize * 1.50, height: buddySize * 1.34)
                            .offset(y: -28 + top)
                            .contentShape(Rectangle())
                            // Every play gesture is scoped to HIS hit area,
                            // so the card's own tap (share) and the page's
                            // vertical scroll are untouched: taps and the
                            // long-press are child gestures (they beat the
                            // card's tap), and the rub only begins on a
                            // horizontal-dominant drag.
                            .onTapGesture { handleTap() }
                            .onLongPressGesture(minimumDuration: 0.5) { feed() }
                            .flameyRubGesture { tickle() }
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(FlameyFacts.displayName)
                            .accessibilityHint("Tap to poke. Double-tap for a high five once your mile is done.")
                            .accessibilityAction(named: "Poke") { poke() }
                            .accessibilityAction(named: "High five") {
                                if trustedDone { react(.highFive) } else { react(.refuse) }
                            }
                            .accessibilityAction(named: "Feed a treat") { feed() }
                        }

                        FunHeroGround()
                            .frame(width: buddySize * 1.26, height: 28)
                            // A fixed distance from the TOP, not from the card's
                            // bottom: the buddy is top-anchored, so tying the
                            // ground to the card height detaches it from the
                            // flame's feet the moment the card grows.
                            .offset(y: Self.groundBaseline + top)

                        // The way into Flamey's Closet, under his feet — his
                        // own column, and the one free spot on this card: the
                        // top-left is HIS frame's overflow and the top-right
                        // holds savers + Share. Below the ground, clear of the
                        // rocket boots' jets and of his hit area (the frame
                        // ends ~208pt down).
                        // Closet only. A Share icon rode beside it, a third
                        // way to share on a card whose own tap already opens
                        // the share sheet (and the done card has the Flamey
                        // card), so it went: two pills under him competed
                        // with the stats.
                        if !injuryPause.isPaused {
                            HeroClosetButton()
                                // Back to the size it had at the old 0.9
                                // column scale: the art shrank, its tap
                                // target must not.
                                .scaleEffect(Self.closetButtonScale / Self.flameyScale)
                                .offset(y: Self.groundBaseline + top + 32)
                        }
                    }
                    .scaleEffect(Self.flameyScale, anchor: .top)
                    .frame(width: leftWidth, height: geo.size.height, alignment: .top)

                    funStatRows
                        .padding(.top, 2)
                        .padding(.bottom, 4)
                        // NATURAL height (fixedSize): measured inside a
                        // shorter frame, the stats compressed (the milestone
                        // line shrank) and the card never grew to fit them.
                        // `heroHeight` then takes the taller side.
                        .fixedSize(horizontal: false, vertical: true)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { statsHeight = $0 }
                        // Centred in what's left under the savers' row: a
                        // tall hat (his headroom) makes his side taller than
                        // the stats, and top-aligned that left one big band
                        // under them. The shield is pinned separately.
                        .frame(width: rightWidth, height: max(0, geo.size.height - Self.saversRoom), alignment: .center)
                        .padding(.top, Self.saversRoom)
                        // The savers stay in the hero's top-right corner,
                        // whatever he wears or however tall the card grows.
                        .overlay(alignment: .topTrailing) { saversChip }
                }
                .onAppear { heroFrameWidth = geo.size.width }
                .onChange(of: geo.size.width) { _, width in heroFrameWidth = width }
            }
            .frame(height: heroHeight(top: top))

            if !injuryPause.isPaused {
                DailyGoalBars(
                    miles: currentDistance,
                    goalMiles: userManager.currentUser.goalMiles,
                    steps: todaySteps,
                    stepGoalMet: stepGoalMet,
                    onReplay: onReplay,
                    // No "Go again" capsule: the red Start button stays
                    // under the hero on a done day ("Go another mile").
                    onShare: { showShareSheet = true },
                    onOpenSteps: { showSteps = true }
                )
            }

        }
        .padding(18)
        .padding(.top, 18)
        .background(cardBackground)
        .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .onTapGesture {
            MADHaptics.action()
            showShareSheet = true
        }
        .sheet(isPresented: $showShareSheet) {
            EnhancedShareView(
                user: userManager.currentUser,
                currentDistance: currentDistance,
                progress: progress,
                isGoalCompleted: isGoalCompleted,
                fastestPace: bestFastestPace,
                mostMiles: healthManager.cachedCurrentStreakStats.mostMiles > 0
                    ? healthManager.cachedCurrentStreakStats.mostMiles
                    : healthManager.mostMilesInOneDay
            )
        }
        .sheet(isPresented: $showTokens) {
            StreakTokensDetailView()
        }
        .navigationDestination(isPresented: $showSteps) {
            StepsView(healthManager: healthManager, userManager: userManager)
        }
        .task(id: memoryKey) { await refreshMemory() }
        .onAppear {
            updateTimeRemaining()
            timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in updateTimeRemaining() }
        }
        .onDisappear {
            timer?.invalidate()
            timer = nil
        }
    }

    /// Worth saying in words even at the cost of the crown: today's miles
    /// haven't synced, or the streak is running out of day.
    private var statusIsUrgent: Bool {
        guard !trustedDone else { return false }
        return !distanceIsFresh || userManager.currentUser.isStreakAtRisk
    }

    /// Living the longest streak they have ever had. `>= 7` so a brand-new
    /// account isn't crowned on day 1.
    private var atAllTimeBest: Bool {
        let longest = userManager.currentUser.longestStreak ?? 0
        let streak = userManager.currentUser.streak
        return longest > 0 && streak >= longest && streak >= 7
    }

    /// The record lives ON the streak, not beside it.
    ///
    /// It used to be a separate gold capsule below the stat lines — a third
    /// pill in a column that already had a bordered box and a pill, floating
    /// in the gap above the milestone bar. Too many competing capsules, and
    /// it read as tacked on. Decorating the number the record BELONGS to says
    /// the same thing with no new element: gold frame, crown, and a second
    /// label line, all inside the box that was already there.
    private var streakHeadline: some View {
        let gold = Color(red: 1.0, green: 0.78, blue: 0.25)

        // The number, what it is, and ONE status line under it — no box. It
        // was a gold-rimmed capsule holding the number, a divider, and three
        // tracked-capital lines (DAY STREAK / BEST EVER / 3 SAVERS) at 9pt.
        // The number and what it is on ONE line ("539 day streak"); on its
        // own line under the number "day streak" read as a separate fact.
        // Narrower columns (or a 4-digit streak) fall back to "days", then
        // to the stacked form.
        // Option 3: the streak and a shield count for the savers on ONE row,
        // then one status pill that also carries the time left ("Streak at
        // risk · 3h 23m left"). It was five lines: number, status, savers,
        // and the time left as its own two-line stat further down.
        return VStack(alignment: .leading, spacing: 6) {
            // Tight spacing: at 375pt the column is ~148pt, and "87 days"
            // plus the shield only just fit on one line.
            // `.top`: the savers sit in the column's top-right corner, level
            // with the top of the number, never centred beside it.
            HStack(alignment: .top, spacing: 2) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        streakNumber
                        streakUnit("day streak")
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        streakNumber
                        streakUnit("days")
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(heroStreakValue)")
                            .madFont(size: 46, weight: .black, design: .rounded, monospacedDigit: true)
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.55)
                        streakUnit("day streak")
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(heroStreakValue) day streak")
                Spacer(minLength: 0)
            }

            statusPill(gold: gold)

            // A Save already committed to a missed day says so in words: the
            // streak beside it reads reset until the morning sweep.
            pendingSaveLine
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var streakNumber: some View {
        Text("\(heroStreakValue)")
            .madFont(size: 54, weight: .black, design: .rounded, monospacedDigit: true)
            .foregroundColor(.white)
            .lineLimit(1)
            .fixedSize()
    }

    private func streakUnit(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .madFont(size: 15, weight: .heavy, design: .rounded)
            .foregroundColor(.orange)
            .lineLimit(1)
            .fixedSize()
    }

    /// The day's state in one pill, with the time left riding along while
    /// the mile is still owed. The crown ("Best ever") takes the pill on a
    /// record run unless the day is urgent ("Syncing", "Streak at risk").
    /// Never truncated: the full line, then "At risk" (it sits right under
    /// the streak), then the same pill on two lines.
    private func statusPill(gold: Color) -> some View {
        let crowned = atAllTimeBest && !statusIsUrgent
        let tint = crowned ? gold : statusColor
        let showsTime = !trustedDone && !injuryPause.isPaused && savedToday == nil && !formattedTimeOnly.isEmpty
        let atRisk = !crowned && statusText == String(localized: "Streak at risk")
        return ViewThatFits(in: .horizontal) {
            pillBody(tint: tint) {
                HStack(spacing: 4) {
                    pillStatus(crowned: crowned, short: false)
                    if showsTime { pillTime }
                }
            }
            if atRisk && showsTime {
                pillBody(tint: tint) {
                    HStack(spacing: 4) {
                        pillStatus(crowned: crowned, short: true)
                        pillTime
                    }
                }
            }
            pillBody(tint: tint, radius: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    pillStatus(crowned: crowned, short: false)
                    if showsTime { Text("\(formattedTimeOnly) left").monospacedDigit() }
                }
            }
        }
    }

    @ViewBuilder
    private func pillStatus(crowned: Bool, short: Bool) -> some View {
        if crowned {
            HStack(spacing: 3) {
                Image(systemName: "crown.fill")
                    .madFont(size: 10, weight: .bold, maxScale: 1.3)
                    .accessibilityHidden(true)
                Text("Best ever")
            }
        } else if short {
            Text("At risk")
        } else {
            Text(statusText)
        }
    }

    private var pillTime: some View {
        HStack(spacing: 4) {
            Text(verbatim: "·").opacity(0.6)
            Text("\(formattedTimeOnly) left").monospacedDigit()
        }
    }

    private func pillBody<Content: View>(tint: Color, radius: CGFloat? = nil,
                                         @ViewBuilder _ content: () -> Content) -> some View {
        content()
            .madFont(size: 12, weight: .bold, design: .rounded)
            .foregroundColor(tint)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: radius ?? 100, style: .continuous).fill(tint.opacity(0.16))
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius ?? 100, style: .continuous).strokeBorder(tint.opacity(0.24), lineWidth: 1)
            )
    }

    /// The savers as a shield and a count beside the streak, opening the
    /// tokens screen. Hidden until the token status has loaded, and while a
    /// committed Save is pending (`pendingSaveLine` says that in words).
    @ViewBuilder
    private var saversChip: some View {
        if let payload = tokensState.payload, payload.pending_save == nil {
            Button {
                showTokens = true
            } label: {
                HStack(spacing: 2) {
                    Image(systemName: "shield.lefthalf.filled")
                        .madFont(size: 11, weight: .bold, maxScale: 1.3)
                        .accessibilityHidden(true)
                    Text("\(readyTokens)")
                        .madFont(size: 13, weight: .heavy, design: .rounded, maxScale: 1.3)
                }
                .foregroundColor(.white.opacity(readyTokens > 0 ? 0.7 : 0.4))
                // Bare glyph + number: a capsule here cost the width that
                // keeps "87 days" on one line beside it. The hit area stays
                // 44pt tall.
                .padding(.top, 6)
                .frame(minWidth: 24, minHeight: 44, alignment: .top)
                .contentShape(Rectangle())
                .fixedSize()
            }
            .buttonStyle(.plain)
            .accessibilityLabel(readyTokens == 1 ? "1 streak saver ready" : "\(readyTokens) streak savers ready")
            .accessibilityHint("Opens your streak tokens")
        }
    }

    @ViewBuilder
    private var pendingSaveLine: some View {
        if let pending = tokensState.payload?.pending_save {
            Button {
                showTokens = true
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "snowflake")
                        .madFont(size: 10, weight: .bold)
                        .accessibilityHidden(true)
                    Text(pending.heroLabel)
                        .madFont(size: 12, weight: .bold, design: .rounded)
                }
                .foregroundColor(SavedDayStyle.tint)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(pending.accessibilitySummary)
            .accessibilityHint("Opens your streak tokens")
        }
    }

    private var readyTokens: Int {
        guard let payload = tokensState.payload else { return 0 }
        return [payload.double_down.held, payload.streak_save.held, payload.streak_assist.held].filter { $0 }.count
    }

    private var heroStats: some View {
        VStack(spacing: 12) {
            if !trustedDone {
                statusBadge
            }

            VStack(spacing: 2) {
                Text("\(userManager.currentUser.streak)")
                    .madFont(size: 70, weight: .black, design: .rounded, monospacedDigit: true)
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.50)
                Text("Day Streak")
                    .madFont(size: 15, weight: .heavy, design: .rounded)
                    .tracking(4)
                    .foregroundColor(statusColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 7) { heroChips }
                VStack(spacing: 8) { heroChips }
            }
        }
        .frame(maxHeight: .infinity)
    }

    /// The Fun column: the streak box (which carries the status line — see
    /// `streakHeadline`) over the SAME three stats the Modern hero shows.
    private var funStatRows: some View {
        VStack(alignment: .leading, spacing: 0) {
            streakHeadline
                .padding(.bottom, injuryPause.isPaused ? 4 : 8)

            // Says the quiet part out loud: the number is frozen, not stalled.
            // Without this the hero looks identical to a day you simply haven't
            // run yet, which is the reading that panics people.
            if let active = injuryPause.status?.active {
                HStack(spacing: 4) {
                    InjuryStatusChip(compact: true)
                    Text("Paused \(active.paused_days) \(active.paused_days == 1 ? "day" : "days")")
                        .madFont(size: 11, weight: .bold, design: .rounded)
                        .foregroundColor(MADTheme.Colors.warning)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .padding(.bottom, 8)
            }

            // The column spans his whole frame: the streak at the top (level
            // with the room kept above him for a hat and his bubble), its
            // next rung in the middle, the day's lines down by his feet.
            // With only the streak and the day's lines, either the top or
            // the middle was an empty band; the milestone belongs with the
            // streak anyway, and moving it here takes a row off the card.
            // Fixed gaps, not spacers: with the column down to four facts the
            // spacers spread them over Flamey's whole frame and it read as
            // loose. Top-aligned with him; any spare height falls below.
            DashboardMilestoneBar(streak: userManager.currentUser.streak)
                .padding(.top, 6)
                .padding(.bottom, 12)

            HeroStatColumn(
                currentDistance: currentDistance,
                goalMiles: userManager.currentUser.goalMiles,
                fastestPace: healthManager.todaysFastestPace,
                timeLeftText: formattedTimeOnly,
                statusColor: statusColor,
                todaySteps: todaySteps,
                stepGoalMet: stepGoalMet,
                onOpenSteps: { showSteps = true },
                compact: true
            )

            RecordGhostRow(
                streak: userManager.currentUser.streak,
                longest: userManager.currentUser.longestStreak ?? 0,
                showsRecord: false
            )
        }
    }

    @ViewBuilder
    private var heroChips: some View {
        ModernMetricPill(
            icon: trustedDone ? "checkmark.circle.fill" : "figure.run",
            title: trustedDone ? String(localized: "Logged") : String(localized: "To go"),
            // Logged floors, "To go" ceils — mirrored so neither side can
            // claim the goal is closer than it is (0.995 logged used to
            // round up to "1.00 mi" on an incomplete day).
            value: trustedDone
                ? currentDistance.distanceFormatted
                : "\(max(goalDistance - currentDistance, 0).distanceToGoText) \(DistanceUnits.current.abbreviation)",
            tint: trustedDone ? .green : statusColor
        )
        ModernMetricPill(
            icon: "clock.fill",
            title: trustedDone ? String(localized: "Safe") : String(localized: "Left today"),
            value: trustedDone ? "Done" : (formattedTimeOnly.isEmpty ? "--" : formattedTimeOnly),
            tint: trustedDone ? .green : statusColor
        )
    }

    private var statusBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: statusGlyph(atRisk: "exclamationmark.circle.fill"))
                .madFont(size: 12, weight: .bold)
            Text(statusText)
                .madFont(size: 12, weight: .heavy, design: .rounded)
        }
        .foregroundColor(statusColor)
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background(Capsule().fill(statusColor.opacity(0.17)))
        .overlay(Capsule().strokeBorder(statusColor.opacity(0.26), lineWidth: 1))
    }

    /// Matches `statusText` case for case, so the glyph can never describe a
    /// different state than the words beside it.
    private func statusGlyph(atRisk: String) -> String {
        if trustedDone { return "checkmark.circle.fill" }
        if let saved = savedToday { return SavedDayStyle.icon(for: saved.kind) }
        if userManager.currentUser.isStreakAtRisk { return atRisk }
        return "flame.fill"
    }

    private var statusText: String {
        if injuryPause.isPaused { return String(localized: "Paused for injury") }
        if trustedDone { return String(localized: "Streak safe") }
        if savedToday != nil { return String(localized: "Covered today") }
        if !distanceIsFresh { return String(localized: "Syncing") }
        if userManager.currentUser.isStreakAtRisk { return String(localized: "Streak at risk") }
        return String(localized: "Keep it alive")
    }

    /// Same clock as the Modern hero — `timeUntilStreakReset` goes nil once the
    /// mile is done, which left the two dashboards showing different values in
    /// the same "Left today" row.
    private var formattedTimeOnly: String {
        if injuryPause.isPaused { return "—" }
        _ = timeRemainingText
        let remaining = secondsUntilLocalMidnight
        let hours = Int(remaining) / 3600
        let minutes = Int(remaining) % 3600 / 60
        return hours > 0 ? String(localized: "\(hours)h \(minutes)m") : "\(minutes)m"
    }

    private var secondsUntilLocalMidnight: TimeInterval {
        let now = Date()
        guard let nextMidnight = Calendar.current.nextDate(
            after: now,
            matching: DateComponents(hour: 0, minute: 0, second: 0),
            matchingPolicy: .nextTime
        ) else {
            return userManager.currentUser.timeUntilStreakReset ?? 0
        }
        return max(0, nextMidnight.timeIntervalSince(now))
    }

    private func updateTimeRemaining() {
        timeRemainingText = trustedDone ? "" : userManager.currentUser.formattedTimeUntilReset
    }

    private var bestFastestPace: TimeInterval {
        userManager.currentUser.fastestMilePace > 0 ? userManager.currentUser.fastestMilePace : healthManager.fastestMilePace
    }

    private var cardBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color(red: 0.070, green: 0.065, blue: 0.070))

            FunHeroEmbers(tint: statusColor)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .opacity(0.45)
        }
        // No rim, no drop shadow: the card's own fill already separates it
        // from the page; a border plus a shadow boxed it twice.
    }
}

private struct FunHeroGround: View {
    var body: some View {
        ZStack(alignment: .bottom) {
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.orange.opacity(0.22),
                            Color.black.opacity(0.34),
                            Color.black.opacity(0.02)
                        ],
                        center: .center,
                        startRadius: 2,
                        endRadius: 72
                    )
                )
                .blur(radius: 5)
                .frame(height: 18)
            HStack(alignment: .bottom, spacing: -4) {
                ForEach(0..<9, id: \.self) { index in
                    FunGroundRock(slant: CGFloat([-0.20, 0.28, -0.12, 0.18, -0.24, 0.20, -0.16, 0.26, -0.10][index]))
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.black.opacity(index.isMultiple(of: 2) ? 0.40 : 0.28),
                                Color(red: 0.16, green: 0.055, blue: 0.045).opacity(0.70)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: CGFloat([22, 16, 27, 18, 25, 15, 22, 17, 20][index]), height: CGFloat([18, 10, 23, 13, 20, 9, 17, 12, 15][index]))
                }
            }
        }
    }
}

private struct FunGroundRock: Shape {
    let slant: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let topLeft = CGPoint(x: rect.minX + rect.width * max(0.08, 0.20 + slant), y: rect.minY)
        let topRight = CGPoint(x: rect.maxX - rect.width * max(0.08, 0.18 - slant), y: rect.minY + rect.height * 0.05)

        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.06, y: rect.minY + rect.height * 0.34))
        path.addQuadCurve(to: topLeft, control: CGPoint(x: rect.minX + rect.width * 0.08, y: rect.minY + rect.height * 0.08))
        path.addLine(to: topRight)
        path.addQuadCurve(to: CGPoint(x: rect.maxX - rect.width * 0.06, y: rect.minY + rect.height * 0.38), control: CGPoint(x: rect.maxX - rect.width * 0.06, y: rect.minY + rect.height * 0.12))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
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

private struct FunHeroEmbers: View {
    let tint: Color

    private let embers: [(x: CGFloat, y: CGFloat, size: CGFloat, opacity: Double)] = [
        (0.11, 0.18, 3, 0.34),
        (0.24, 0.28, 2, 0.24),
        (0.38, 0.15, 3, 0.30),
        (0.68, 0.20, 2, 0.20),
        (0.84, 0.32, 2, 0.18)
    ]

    var body: some View {
        GeometryReader { geo in
            ForEach(embers.indices, id: \.self) { index in
                Capsule()
                    .fill(index.isMultiple(of: 2) ? Color.orange.opacity(0.84) : tint.opacity(0.72))
                    .frame(width: embers[index].size, height: embers[index].size * 2.4)
                    .blur(radius: 0.2)
                    .rotationEffect(.degrees(Double(index * 26 - 18)))
                    .opacity(embers[index].opacity)
                    .position(x: geo.size.width * embers[index].x, y: geo.size.height * embers[index].y)
            }
        }
    }
}

private struct FunStartCard: View {
    @ObservedObject var healthManager: HealthKitManager
    @ObservedObject var userManager: UserManager
    let trustedDone: Bool
    let hasActiveWorkout: Bool
    @Binding var showWorkoutView: Bool
    let onLogPastWorkout: () -> Void

    /// A Group, not a stack: its parts sit straight in the dashboard's
    /// stack, so when both hide they leave no empty slot (and no gap).
    var body: some View {
        Group {
            if trustedDone {
                // The day is won, but the red button stays: going again is
                // what we want people to do, and a small "Go again" capsule
                // on the done line was easy to miss and read oddly.
                DashboardStartMileButton(hasActiveWorkout: hasActiveWorkout, prominent: true,
                                         goalDone: true, showWorkoutView: $showWorkoutView)
                    .tourAnchor("home.start")
                // Then the post-it prompt. See `DoneTodayCard`.
                DoneTodayCard(
                    healthManager: healthManager,
                    userManager: userManager
                )
            } else {
                VStack(spacing: 6) {
                    DashboardStartMileButton(hasActiveWorkout: hasActiveWorkout, prominent: true, showWorkoutView: $showWorkoutView)
                        .tourAnchor("home.start")
                    // Before the mile is where logging one done elsewhere
                    // matters; after it, the done card owns this space.
                    LogPastWorkoutLink(action: onLogPastWorkout)
                }
            }
            BuddyWalkPill(hasActiveWorkout: hasActiveWorkout)
        }
    }
}
