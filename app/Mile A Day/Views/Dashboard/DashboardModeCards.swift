import SwiftUI
import HealthKit

struct DashboardStartMileButton: View {
    let hasActiveWorkout: Bool
    var prominent: Bool = false
    @Binding var showWorkoutView: Bool

    var body: some View {
        Button {
            showWorkoutView = true
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.10))
                        .frame(width: 32, height: 32)
                    Image(systemName: hasActiveWorkout ? "play.circle.fill" : "play.fill")
                        .madFont(size: 14, weight: .black, maxScale: 1.3)
                        .offset(x: hasActiveWorkout ? 0 : 1)
                }

                Text(buttonTitle)
                    .madFont(size: prominent ? 17 : 16, weight: .black, design: .rounded)
                    .tracking(prominent ? 1.2 : 0)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Spacer(minLength: 0)

                Image(systemName: prominent ? "chevron.right" : "arrow.right")
                    .madFont(size: prominent ? 18 : 14, weight: .bold)
                    .foregroundColor(.white.opacity(0.72))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.leading, 16)
            .padding(.trailing, 18)
            .padding(.vertical, prominent ? 14 : 12)
            .background(
                RoundedRectangle(cornerRadius: prominent ? 16 : 20, style: .continuous)
                    .fill(prominent ? Color(red: 0.78, green: 0.13, blue: 0.30) : Color(red: 0.72, green: 0.12, blue: 0.26))
                    .overlay(
                        RoundedRectangle(cornerRadius: prominent ? 16 : 20, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                    )
            )
            .shadow(color: MADTheme.Colors.madRed.opacity(prominent ? 0.18 : 0.12), radius: prominent ? 10 : 8, x: 0, y: prominent ? 5 : 4)
        }
        .buttonStyle(.plain)
    }

    private var buttonTitle: String {
        if prominent {
            return hasActiveWorkout ? "RESUME WORKOUT" : "START MILE"
        }
        return hasActiveWorkout ? "Resume Workout" : "Start Mile"
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
    var title: String = "Streak milestone"

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

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    Image(systemName: "flame.fill")
                        .madFont(size: 10, weight: .bold)
                        .foregroundColor(.orange)
                    Text(title.uppercased())
                        .madFont(size: 10, weight: .heavy, design: .rounded)
                        .tracking(1.0)
                        .foregroundColor(.white.opacity(0.56))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 0)
                    Text("Day \(streak) of \(milestone.value)")
                        .madFont(size: 11, weight: .heavy, design: .rounded, monospacedDigit: true)
                        .foregroundColor(.white.opacity(0.70))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
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

                HStack(spacing: 0) {
                    Text(milestone.daysToGo == 1
                         ? "1 day to Day \(milestone.value)"
                         : "\(milestone.daysToGo) days to Day \(milestone.value)")
                        .foregroundColor(.white.opacity(0.42))
                    Spacer(minLength: 0)
                }
                .madFont(size: 9, weight: .heavy, design: .rounded)
                .tracking(0.6)
                .monospacedDigit()
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Streak milestone: day \(streak) of \(milestone.value), \(milestone.daysToGo) days to go")
        }
    }
}

struct WeekMileDaysRow: View {
    @ObservedObject var healthManager: HealthKitManager
    let statusColor: Color
    var showLabels: Bool = true

    private static let narrowDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEEE"
        return f
    }()

    private var weekDays: [Date] {
        let calendar = Calendar.current
        let today = Date()
        let weekday = calendar.component(.weekday, from: today)
        guard let start = calendar.date(
            byAdding: .day,
            value: -(weekday - 1),
            to: calendar.startOfDay(for: today)
        ) else { return [] }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    private var completedCount: Int {
        let calendar = Calendar.current
        return weekDays.filter { healthManager.dailyMileGoals[calendar.startOfDay(for: $0)] ?? false }.count
    }

    var body: some View {
        VStack(spacing: 12) {
            if showLabels {
                HStack {
                    Text("Mile days")
                        .madFont(size: 14, weight: .heavy, design: .rounded)
                        .foregroundColor(.white)
                    Spacer()
                    Text("\(completedCount) of 7 this week")
                        .madFont(size: 12, weight: .bold, design: .rounded, monospacedDigit: true)
                        .foregroundColor(.white.opacity(0.58))
                }
            }

            HStack(spacing: 0) {
                ForEach(weekDays, id: \.self) { date in
                    let calendar = Calendar.current
                    let completed = healthManager.dailyMileGoals[calendar.startOfDay(for: date)] ?? false
                    let isToday = calendar.isDateInToday(date)
                    let isFuture = calendar.startOfDay(for: date) > calendar.startOfDay(for: Date())

                    VStack(spacing: 6) {
                        Text(Self.narrowDayFormatter.string(from: date))
                            .madFont(size: 11, weight: .bold, design: .rounded)
                            .foregroundColor(.white.opacity(0.46))

                        ZStack {
                            Circle()
                                .fill(completed ? Color.green.opacity(0.95) : Color.white.opacity(isFuture ? 0.07 : 0.12))
                                .frame(width: 34, height: 34)
                                .overlay(Circle().strokeBorder(Color.white.opacity(completed ? 0.18 : 0.08), lineWidth: 1))

                            if completed {
                                Image(systemName: "checkmark")
                                    .madFont(size: 15, weight: .black, maxScale: 1.3)
                                    .foregroundColor(.white)
                            }

                            if isToday {
                                Circle()
                                    .stroke(statusColor, lineWidth: 2.5)
                                    .frame(width: 39, height: 39)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }
}

struct ModernDashboardBody: View {
    @ObservedObject var healthManager: HealthKitManager
    @ObservedObject var userManager: UserManager
    /// Only the optional friends' activity card reads it.
    @ObservedObject var friendService: FriendService
    let hasActiveWorkout: Bool
    @Binding var showWorkoutView: Bool

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

    var body: some View {
        VStack(spacing: 14) {
            ModernHeroCard(
                healthManager: healthManager,
                userManager: userManager,
                currentDistance: state.distance,
                goalDistance: state.goal,
                progress: state.progress,
                isGoalCompleted: state.completed,
                hasActiveWorkout: hasActiveWorkout,
                distanceIsFresh: healthManager.hasFreshTodaysDistance,
                showWorkoutView: $showWorkoutView
            )
            // Fixed flame box beside a ~130pt stat column: the hero's text
            // grows only as far as that column honestly holds.
            .madTypeCap(.madFixedChromeCap)

            DashboardStartMileButton(hasActiveWorkout: hasActiveWorkout, prominent: true, showWorkoutView: $showWorkoutView)

            BuddyWalkPill(hasActiveWorkout: hasActiveWorkout)

            HStack(alignment: .top, spacing: 12) {
                ModernStepsTile(healthManager: healthManager, userManager: userManager)
                ModernBadgesTile(userManager: userManager, healthManager: healthManager)
            }
            // Half-width tiles: their height scales (tileHeight), their width
            // can't.
            .madTypeCap(.madFixedChromeCap)

            // Everything below the day's cards is the user's to arrange
            // (DashboardCards): default here is just the daily challenge.
            DashboardCardsBlock(
                style: .modern,
                healthManager: healthManager,
                userManager: userManager,
                friendService: friendService
            )
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        // Everything else on the dashboard is cards whose rows wrap.
        .madTypeCap(.madCardCap)
    }
}

struct FunDashboardBody: View {
    @ObservedObject var healthManager: HealthKitManager
    @ObservedObject var userManager: UserManager
    @ObservedObject var friendService: FriendService
    let hasActiveWorkout: Bool
    @Binding var showWorkoutView: Bool

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

    var body: some View {
        VStack(spacing: 18) {
            FlameBuddyHeroCard(
                healthManager: healthManager,
                userManager: userManager,
                currentDistance: state.distance,
                goalDistance: state.goal,
                progress: state.progress,
                isGoalCompleted: state.completed,
                hasActiveWorkout: hasActiveWorkout,
                distanceIsFresh: healthManager.hasFreshTodaysDistance,
                showWorkoutView: $showWorkoutView
            )
            // The stat frame grows with its text (statFrameHeight), but the
            // column beside Flamey is ~155pt wide, so it caps here.
            .madTypeCap(.madFixedChromeCap)

            FunStartCard(
                trustedDone: state.completed && healthManager.hasFreshTodaysDistance,
                hasActiveWorkout: hasActiveWorkout,
                showWorkoutView: $showWorkoutView
            )

            HStack(alignment: .top, spacing: 12) {
                ModernStepsTile(healthManager: healthManager, userManager: userManager)
                ModernBadgesTile(userManager: userManager, healthManager: healthManager)
            }
            // Half-width tiles: their height scales (tileHeight), their width
            // can't.
            .madTypeCap(.madFixedChromeCap)

            // Everything below the day's cards is the user's to arrange
            // (DashboardCards): default here is Streak Tokens, the daily
            // challenge and friends' activity — what always shipped.
            DashboardCardsBlock(
                style: .fun,
                healthManager: healthManager,
                userManager: userManager,
                friendService: friendService
            )
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        // Everything else on the dashboard is cards whose rows wrap.
        .madTypeCap(.madCardCap)
    }

    private var statusColor: Color {
        if state.completed && healthManager.hasFreshTodaysDistance { return .green }
        if userManager.currentUser.isStreakAtRisk { return .red }
        return .orange
    }
}

private struct ModernHeroCard: View {
    @ObservedObject private var injuryPause = InjuryPauseState.shared

    /// The number to print on the hero. A pause FREEZES a specific value, and
    /// `currentUser.streak` is not it: the local copy is quarantined and
    /// raise-only, so a pause started after a couple of missed days (the normal
    /// case — you back-date it once you're out of the hospital) leaves it at 0
    /// while the server has correctly frozen 412.
    private var heroStreakValue: Int {
        injuryPause.status?.active?.frozen_streak ?? userManager.currentUser.streak
    }

    @ObservedObject var healthManager: HealthKitManager
    @ObservedObject var userManager: UserManager
    let currentDistance: Double
    let goalDistance: Double
    let progress: Double
    let isGoalCompleted: Bool
    let hasActiveWorkout: Bool
    let distanceIsFresh: Bool
    @Binding var showWorkoutView: Bool

    @State private var showTokens = false
    @State private var timeRemainingText = ""
    @State private var timer: Timer?
    @ObservedObject private var tokensState = StreakTokensState.shared

    private var trustedDone: Bool { isGoalCompleted && distanceIsFresh }
    private var flameHealth: FlameHealth {
        FlameHealth.forState(
            isCompleted: isGoalCompleted,
            distanceIsFresh: distanceIsFresh,
            isAtRisk: userManager.currentUser.isStreakAtRisk,
            secondsToReset: secondsUntilLocalMidnight,
            streak: userManager.currentUser.streak
        )
    }

    private var flamePhase: StreakFlamePhase {
        StreakFlamePhase.forState(
            isCompleted: isGoalCompleted,
            distanceIsFresh: distanceIsFresh,
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

    var body: some View {
        VStack(spacing: 16) {
            HStack(alignment: .center, spacing: 18) {
                ZStack {
                    // While paused there is no countdown to draw — the ring
                    // measures time left in the day, and a frozen streak isn't
                    // losing any. Same injured buddy as the Fun hero so the two
                    // styles agree about what a pause looks like.
                    if injuryPause.isPaused {
                        // Smaller and lifted: this hero overlays the streak
                        // number on the figure, and at ring size the number
                        // lands squarely on the buddy's face.
                        InjuredFlameBuddyView(size: 112)
                            .offset(y: -30)
                    } else {
                        ProfessionalFlameView(
                            phase: flamePhase,
                            health: flameHealth,
                            size: 166,
                            ringProgress: timeLeftRingProgress,
                            dayEnd: StreakFlameClock.nextLocalMidnight(),
                            coalWarmth: min(progress, 1)
                        )
                    }

                    VStack(spacing: 0) {
                        Text("\(heroStreakValue)")
                            .madFont(size: 34, weight: .black, design: .rounded, monospacedDigit: true)
                            .foregroundColor(.white)
                            .shadow(color: .black.opacity(0.72), radius: 5, x: 0, y: 2)
                            .lineLimit(1)
                            .minimumScaleFactor(0.60)
                        Text(injuryPause.isPaused ? "DAYS · PAUSED" : "DAYS")
                            .madFont(size: 8, weight: .black, design: .rounded)
                            .tracking(1.1)
                            .foregroundColor(injuryPause.isPaused
                                             ? MADTheme.Colors.warning
                                             : .white.opacity(0.88))
                            .shadow(color: .black.opacity(0.72), radius: 4, x: 0, y: 2)
                    }
                    .offset(y: injuryPause.isPaused ? 54 : 39)
                }
                .frame(width: 172, height: 176)
                .layoutPriority(1)

                HeroStatColumn(
                    currentDistance: currentDistance,
                    steps: healthManager.todaysSteps,
                    fastestPace: healthManager.todaysFastestPace,
                    timeLeftText: formattedTimeOnly,
                    statusColor: statusColor
                )
                .frame(maxWidth: .infinity)
            }

            RecordGhostRow(
                streak: userManager.currentUser.streak,
                longest: userManager.currentUser.longestStreak ?? 0
            )

            DashboardMilestoneBar(streak: userManager.currentUser.streak)
        }
        .padding(18)
        .padding(.top, 20)
        .background(heroBackground)
        .overlay(alignment: .topTrailing) {
            tokensChip
                // Horizontal inset matches the card's own 18, so the chip's
                // right edge lines up with the stats beneath it instead of
                // hanging 4pt further out.
                .padding(.horizontal, 18)
                .padding(.top, 14)
        }
        .sheet(isPresented: $showTokens) {
            StreakTokensDetailView()
        }
        .onAppear {
            updateTimeRemaining()
            timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in updateTimeRemaining() }
        }
        .onDisappear {
            timer?.invalidate()
            timer = nil
        }
    }

    private var statusPill: some View {
        HStack(spacing: 6) {
            Image(systemName: statusGlyph(atRisk: "exclamationmark.triangle.fill"))
                .madFont(size: 12, weight: .bold)
            Text(statusText)
                .madFont(size: 12, weight: .heavy, design: .rounded)
                .lineLimit(1)
        }
        .foregroundColor(statusColor)
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background(Capsule().fill(statusColor.opacity(0.13)))
        .overlay(Capsule().strokeBorder(statusColor.opacity(0.22), lineWidth: 1))
    }

    private var tokensChip: some View {
        Button {
            showTokens = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "shield.lefthalf.filled")
                    .accessibilityLabel("Streak savers")
                    .madFont(size: 11, weight: .bold)
                Text("\(readyTokens)")
                    .madFont(size: 12, weight: .black, design: .rounded, monospacedDigit: true)
                Text(readyTokens == 1 ? "saver" : "savers")
                    .madFont(size: 11, weight: .heavy, design: .rounded)
            }
            .foregroundColor(.white.opacity(0.88))
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(Capsule().fill(Color.cyan.opacity(0.10)))
            .overlay(Capsule().strokeBorder(Color.cyan.opacity(0.22), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(readyTokens) streak savers ready")
    }

    private var readyTokens: Int {
        guard let payload = tokensState.payload else { return 0 }
        return [payload.double_down.held, payload.streak_save.held, payload.streak_assist.held].filter { $0 }.count
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
        if injuryPause.isPaused { return "Paused for injury" }
        if trustedDone { return "Done today" }
        if savedToday != nil { return "Covered today" }
        if !distanceIsFresh { return "Syncing today" }
        if userManager.currentUser.isStreakAtRisk { return "Streak at risk" }
        return timeRemainingText.isEmpty ? "Today's mile" : "\(formattedTimeOnly) left"
    }

    private var formattedTimeOnly: String {
        if injuryPause.isPaused { return "—" }
        let remaining = secondsUntilLocalMidnight
        let hours = Int(remaining) / 3600
        let minutes = Int(remaining) % 3600 / 60
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
    }

    private func updateTimeRemaining() {
        timeRemainingText = trustedDone ? "" : userManager.currentUser.formattedTimeUntilReset
    }

    private var milestoneCaption: String {
        guard let next = StreakMilestone.next(after: userManager.currentUser.streak) else {
            return "Legend status"
        }
        return "\(next.daysToGo) to Day \(next.value)"
    }

    private var modernProgressLine: some View {
        GeometryReader { geo in
            let next = StreakMilestone.next(after: userManager.currentUser.streak)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.10))
                Capsule()
                    .fill(statusColor)
                    .frame(width: max(5, geo.size.width * CGFloat(next?.progress ?? progress)))
            }
        }
        .frame(height: 5)
    }

    private var timeLeftRingProgress: Double {
        guard !trustedDone else { return 1.0 }
        let secondsInDay: TimeInterval = 24 * 60 * 60
        return max(0.025, min(secondsUntilLocalMidnight / secondsInDay, 1.0))
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

    private var heroBackground: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(Color(red: 0.075, green: 0.075, blue: 0.085))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.095), lineWidth: 1)
            )
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
            }
            .foregroundColor(.white.opacity(0.45))
            .fixedSize()
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

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .madFont(size: 14, weight: .bold, maxScale: 1.3)
                .foregroundColor(tint)
                .frame(width: 28, height: 28)
                .background(Circle().fill(tint.opacity(0.13)))

            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(value)
                        .madFont(size: 20, weight: .black, design: .rounded, monospacedDigit: true)
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.60)
                    Text(unit)
                        .madFont(size: 10, weight: .heavy, design: .rounded)
                        .foregroundColor(.white.opacity(0.62))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }

                Text(label)
                    .madFont(size: 10, weight: .black, design: .rounded)
                    .textCase(.uppercase)
                    .foregroundColor(.white.opacity(0.42))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
    }
}

private struct ModernHeroDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.08))
            .frame(height: 1)
            .padding(.leading, 38)
    }
}

/// The stat lines beside the streak hero — today's mileage, steps, and either
/// today's best pace or the time left to run.
///
/// BOTH dashboard styles render this exact view. They used to build their own
/// columns and had drifted apart (Fun showed two stats, Modern three, with
/// different labels), so the same day read as different numbers depending on
/// which dashboard you had picked. Anything added here lands on both.
private struct HeroStatColumn: View {
    let currentDistance: Double
    let steps: Int
    let fastestPace: TimeInterval?
    /// Time until local midnight, e.g. "6h 30m". Shown when there's no pace yet.
    let timeLeftText: String
    let statusColor: Color

    var body: some View {
        VStack(spacing: 0) {
            ModernHeroStatLine(
                icon: "figure.run",
                value: currentDistance.distanceText,
                unit: DistanceUnits.current.abbreviation,
                label: "Distance",
                tint: MADTheme.Colors.madRed
            )
            ModernHeroDivider()
            ModernHeroStatLine(
                icon: "shoeprints.fill",
                value: steps.formatted(),
                unit: "steps",
                label: "Steps",
                tint: stepTint
            )
            ModernHeroDivider()
            if let pace = fastestPace {
                ModernHeroStatLine(
                    icon: "timer",
                    value: Self.formatPace(pace),
                    unit: DistanceUnits.current.paceSuffix,
                    label: "Best pace",
                    tint: MADTheme.Colors.walkBlue
                )
            } else {
                ModernHeroStatLine(
                    icon: "clock.fill",
                    value: timeLeftText.isEmpty ? "--" : timeLeftText,
                    unit: "left",
                    label: "Left today",
                    tint: statusColor
                )
            }
        }
    }

    private var stepTint: Color {
        if steps >= 10000 { return MADTheme.Colors.success }
        if steps >= 7500 { return MADTheme.Colors.warning }
        if steps >= 5000 { return .yellow }
        return .orange
    }

    /// `pace` is MINUTES per mile; shown per display unit.
    private static func formatPace(_ pace: TimeInterval) -> String {
        let shown = pace.pacePerDisplayUnit
        let minutes = Int(shown)
        let seconds = Int((shown - Double(minutes)) * 60)
        return String(format: "%d:%02d", minutes, seconds)
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

private struct ModernStepsTile: View {
    @ObservedObject var healthManager: HealthKitManager
    @ObservedObject var userManager: UserManager
    /// The tile's fixed height, grown with the text inside it. 168 exactly
    /// at the default text size; `.title2` because that's the style of the
    /// value that dominates the tile. BOTH tiles declare it identically so the
    /// pair in the dashboard's HStack stays level.
    @MADScaledMetric(relativeTo: .title2) private var tileHeight: CGFloat = 168

    private var steps: Int { healthManager.todaysSteps }
    private var progress: Double { min(Double(steps) / 10000.0, 1) }
    private var tint: Color { steps >= 10000 ? .green : .orange }

    var body: some View {
        NavigationLink {
            StepsView(healthManager: healthManager, userManager: userManager)
        } label: {
            ModernTile(icon: "shoeprints.fill", title: "Steps", value: steps.formatted(), subtitle: "\(ProgressCalculator.formatProgress(progress)) of 10k", tint: tint) {
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
            .frame(height: tileHeight, alignment: .topLeading)
        }
        .buttonStyle(.plain)
    }
}

private struct ModernBadgesTile: View {
    @ObservedObject var userManager: UserManager
    @ObservedObject var healthManager: HealthKitManager
    /// The tile's fixed height, grown with the text inside it. 168 exactly
    /// at the default text size; `.title2` because that's the style of the
    /// value that dominates the tile. BOTH tiles declare it identically so the
    /// pair in the dashboard's HStack stays level.
    @MADScaledMetric(relativeTo: .title2) private var tileHeight: CGFloat = 168

    private var earned: Int {
        userManager.currentUser.badges.filter { !$0.isLocked }.count
    }

    private var total: Int {
        userManager.currentUser.getAllBadges().count
    }

    private var progress: Double {
        total > 0 ? Double(earned) / Double(total) : 0
    }

    private var remaining: Int {
        max(total - earned, 0)
    }

    private var recentUnlocked: [Badge] {
        userManager.currentUser.badges
            .filter { !$0.isLocked }
            .sorted { $0.dateAwarded > $1.dateAwarded }
            .prefix(3)
            .map { $0 }
    }

    var body: some View {
        NavigationLink {
            BadgesView(userManager: userManager, initialBadge: nil)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    medalPreviewStrip
                    Spacer()
                    Image(systemName: "chevron.right")
                        .madFont(size: 10, weight: .bold)
                        .foregroundColor(.white.opacity(0.28))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Medals")
                        .madFont(size: 11, weight: .bold, design: .rounded)
                        .foregroundColor(.white.opacity(0.48))
                    Text("\(earned)/\(total)")
                        .madFont(size: 25, weight: .black, design: .rounded, monospacedDigit: true)
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text("\(ProgressCalculator.formatProgress(progress)) unlocked")
                        .madFont(size: 11, weight: .heavy, design: .rounded)
                        .foregroundColor(.yellow)
                        .lineLimit(1)
                }

                VStack(alignment: .leading, spacing: 4) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.white.opacity(0.10))
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color(red: 1.0, green: 0.84, blue: 0.22),
                                            Color(red: 1.0, green: 0.55, blue: 0.08)
                                        ],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: max(6, geo.size.width * progress))
                        }
                    }
                    .frame(height: 6)

                    Text(remaining == 0 ? "Collection complete" : "\(remaining) left to collect")
                        .madFont(size: 10, weight: .bold, design: .rounded)
                        .foregroundColor(.white.opacity(0.46))
                    .lineLimit(1)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: tileHeight, maxHeight: tileHeight, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(red: 0.075, green: 0.075, blue: 0.085))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.white.opacity(0.09), lineWidth: 1))
            )
        }
        .buttonStyle(.plain)
    }

    private var medalPreviewStrip: some View {
        HStack(spacing: -6) {
            if recentUnlocked.isEmpty {
                ForEach(0..<3, id: \.self) { _ in
                    Circle()
                        .fill(Color.white.opacity(0.07))
                        .frame(width: 34, height: 34)
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
                }
            } else {
                ForEach(Array(recentUnlocked.enumerated()), id: \.element.id) { index, badge in
                    MedalView(badge: badge, size: 38, showShimmer: index == 0)
                        .frame(width: 38, height: 38)
                        .zIndex(Double(3 - index))
                }
            }
        }
        .frame(height: 40)
        .accessibilityLabel(recentUnlocked.isEmpty ? "No medals unlocked yet" : "Recent unlocked medals")
    }
}

private struct ModernMilestoneCard: View {
    let streak: Int

    var body: some View {
        DashboardMilestoneBar(streak: streak)
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(red: 0.075, green: 0.075, blue: 0.085))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.white.opacity(0.09), lineWidth: 1))
            )
    }
}

private struct ModernTile<Accessory: View>: View {
    let icon: String
    let title: String
    let value: String
    let subtitle: String
    let tint: Color
    @ViewBuilder let accessory: () -> Accessory
    /// The tile's fixed height, grown with the text inside it. 168 exactly
    /// at the default text size; `.title2` because that's the style of the
    /// value that dominates the tile. BOTH tiles declare it identically so the
    /// pair in the dashboard's HStack stays level.
    @MADScaledMetric(relativeTo: .title2) private var tileHeight: CGFloat = 168

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .madFont(size: 15, weight: .bold, maxScale: 1.3)
                    .foregroundColor(tint)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(tint.opacity(0.15)))
                Spacer()
                Image(systemName: "chevron.right")
                    .madFont(size: 10, weight: .bold)
                    .foregroundColor(.white.opacity(0.28))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .madFont(size: 11, weight: .bold, design: .rounded)
                    .foregroundColor(.white.opacity(0.48))
                Text(value)
                    .madFont(size: 23, weight: .black, design: .rounded, monospacedDigit: true)
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(subtitle)
                    .madFont(size: 11, weight: .semibold, design: .rounded)
                    .foregroundColor(tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            accessory()
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: tileHeight, maxHeight: tileHeight, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(red: 0.075, green: 0.075, blue: 0.085))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.white.opacity(0.09), lineWidth: 1))
        )
    }
}

struct ModernChallengeRow: View {
    @ObservedObject var healthManager: HealthKitManager
    @ObservedObject var userManager: UserManager
    @State private var todaysChallenge: DailyChallenge?
    @State private var tomorrowsChallenge: DailyChallenge?
    @State private var challengeProgressValue: Double = 0
    @State private var isCompleted = false
    @State private var opponent: ChallengeOpponent?

    private var primaryColor: Color {
        todaysChallenge?.gradient.first ?? .green
    }

    private var accentColor: Color {
        isCompleted ? .green : primaryColor
    }

    var body: some View {
        Group {
            if let challenge = todaysChallenge {
                challengeRow(challenge)
            } else {
                placeholderRow
            }
        }
        .task(id: userManager.currentUser.backendUserId) {
            guard let userId = userManager.currentUser.backendUserId else { return }
            await ChallengeService.refresh(userId: userId)
            refreshFromService()
        }
        .onReceive(NotificationCenter.default.publisher(for: ChallengeService.changedNotification)) { _ in
            refreshFromService()
        }
        .onAppear {
            refreshFromService()
        }
    }

    private func challengeRow(_ challenge: DailyChallenge) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                challengeIcon(challenge)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Daily Challenge")
                        .madFont(size: 11, weight: .bold, design: .rounded)
                        .foregroundColor(accentColor)

                    Text(isCompleted ? "\(challenge.title) complete" : challenge.title)
                        .madFont(size: 17, weight: .heavy, design: .rounded)
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)

                    Text(challenge.description)
                        .madFont(size: 12, weight: .semibold, design: .rounded)
                        .foregroundColor(.white.opacity(0.54))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .madFont(size: 12, weight: .bold)
                    .foregroundColor(.white.opacity(0.30))
            }

            progressRow

            if challenge.key == "head_to_head", let opponent {
                HeadToHeadStrip(
                    opponent: opponent,
                    accent: accentColor,
                    myMilesOverride: healthManager.todaysDistance
                )
            }

            tomorrowRow
        }
        .padding(14)
        .background(rowBackground)
    }

    private var placeholderRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "flag.fill")
                .madFont(size: 15, weight: .bold, maxScale: 1.3)
                .foregroundColor(.green)
                .frame(width: 34, height: 34)
                .background(Circle().fill(Color.green.opacity(0.13)))

            VStack(alignment: .leading, spacing: 3) {
                Text("Daily Challenge")
                    .madFont(size: 15, weight: .heavy, design: .rounded)
                    .foregroundColor(.white)
                Text("Loading today's challenge")
                    .madFont(size: 12, weight: .semibold, design: .rounded)
                    .foregroundColor(.white.opacity(0.48))
            }

            Spacer()

            Image(systemName: "chevron.right")
                .madFont(size: 11, weight: .bold)
                .foregroundColor(.white.opacity(0.30))
        }
        .padding(14)
        .background(rowBackground)
    }

    private func challengeIcon(_ challenge: DailyChallenge) -> some View {
        Image(systemName: isCompleted ? "checkmark" : challenge.icon)
            .madFont(size: 16, weight: .bold, maxScale: 1.3)
            .foregroundColor(accentColor)
            .frame(width: 38, height: 38)
            .background(Circle().fill(accentColor.opacity(0.14)))
            .overlay(Circle().strokeBorder(accentColor.opacity(0.20), lineWidth: 1))
    }

    private var progressRow: some View {
        let progress = min(challengeProgressValue, 1.0)
        return VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.10))
                    Capsule()
                        .fill(accentColor)
                        .frame(width: max(6, geo.size.width * progress))
                }
            }
            .frame(height: 6)

            HStack {
                Text(isCompleted ? "Locked in" : progressLabel(progress))
                    .madFont(size: 11, weight: .bold, design: .rounded)
                    .foregroundColor(accentColor)
                Spacer()
                Text(ProgressCalculator.formatProgress(progress))
                    .madFont(size: 11, weight: .heavy, design: .rounded, monospacedDigit: true)
                    .foregroundColor(.white.opacity(0.58))
            }
        }
    }

    @ViewBuilder
    private var tomorrowRow: some View {
        if let tomorrow = tomorrowsChallenge {
            HStack(spacing: 7) {
                Image(systemName: "calendar")
                    .madFont(size: 11, weight: .bold)
                    .foregroundColor(.white.opacity(0.42))
                Text("Tomorrow")
                    .madFont(size: 11, weight: .bold, design: .rounded)
                    .foregroundColor(.white.opacity(0.48))
                HStack(spacing: 5) {
                    Image(systemName: tomorrow.icon)
                        .madFont(size: 10, weight: .bold)
                    Text(tomorrow.title)
                        .madFont(size: 11, weight: .heavy, design: .rounded)
                        .lineLimit(1)
                }
                .foregroundColor(tomorrow.gradient.first ?? .orange)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill((tomorrow.gradient.first ?? .orange).opacity(0.13)))
                Spacer(minLength: 0)
            }
        }
    }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Color(red: 0.075, green: 0.075, blue: 0.085))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.09), lineWidth: 1)
            )
    }

    private func progressLabel(_ value: Double) -> String {
        if value <= 0 { return "Start today's effort" }
        if value < 0.5 { return "Building progress" }
        if value < 0.85 { return "Closing in" }
        return "Almost there"
    }

    private func refreshFromService() {
        if let remote = ChallengeService.shared as? RemoteChallengeService {
            todaysChallenge = remote.todayChallenge
            tomorrowsChallenge = remote.tomorrowChallenge
            challengeProgressValue = remote.todayProgress
            isCompleted = remote.todayCompleted
            opponent = remote.todayOpponent
        }
    }
}

private struct FlameBuddyHeroCard: View {
    @ObservedObject private var injuryPause = InjuryPauseState.shared

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
    @MADScaledMetric(relativeTo: .largeTitle) private var statFrameHeight: CGFloat = 258

    @ObservedObject var healthManager: HealthKitManager
    @ObservedObject var userManager: UserManager
    let currentDistance: Double
    let goalDistance: Double
    let progress: Double
    let isGoalCompleted: Bool
    let hasActiveWorkout: Bool
    let distanceIsFresh: Bool
    @Binding var showWorkoutView: Bool

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

    private var trustedDone: Bool { isGoalCompleted && distanceIsFresh }

    private static func localDayStamp(_ date: Date = Date()) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// What the flame is feeling: resolved from the same state the phase and
    /// health already read, so it can never disagree with the face.
    private var mood: FlameMood {
        var mood = FlameMood.resolve(
            phase: flamePhase,
            progress: progress,
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
        }
        pokedAt = Date()
        say(FlameMood.pokeQuips(for: before).randomElement() ?? "Hey!")
    }
    private var health: FlameHealth {
        FlameHealth.forState(
            isCompleted: isGoalCompleted,
            distanceIsFresh: distanceIsFresh,
            isAtRisk: userManager.currentUser.isStreakAtRisk,
            secondsToReset: userManager.currentUser.timeUntilStreakReset,
            streak: userManager.currentUser.streak
        )
    }

    private var flamePhase: StreakFlamePhase {
        StreakFlamePhase.forState(
            isCompleted: isGoalCompleted,
            distanceIsFresh: distanceIsFresh,
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

    var body: some View {
        VStack(spacing: 14) {
            GeometryReader { geo in
                let leftWidth = geo.size.width * 0.48
                let rightWidth = geo.size.width - leftWidth - 12
                let buddySize = min(max(leftWidth * 1.14, 176), min(216, geo.size.height * 0.90))

                HStack(alignment: .top, spacing: 12) {
                    ZStack(alignment: .top) {
                        // A paused streak is not a point on the flame's daily
                        // lifecycle, so it gets no phase — it replaces the
                        // figure outright. Nothing is burning down, so nothing
                        // should shrink with the clock.
                        if injuryPause.isPaused {
                            InjuredFlameBuddyView(size: buddySize)
                                .frame(width: buddySize * 1.50, height: buddySize * 1.34)
                                .offset(y: -28)
                        } else {
                            let currentMood = mood
                            FlameBuddyView(
                                health: health,
                                size: buddySize,
                                phase: flamePhase,
                                dayEnd: StreakFlameClock.nextLocalMidnight(),
                                coalWarmth: min(progress, 1),
                                mood: currentMood,
                                look: look(for: currentMood),
                                // His column is narrow: the stat column sits
                                // just to his right and the card edge to his
                                // left, so the cape/trail and companion
                                // squeeze in close.
                                wardrobeReach: 0.62
                            )
                            .frame(width: buddySize * 1.50, height: buddySize * 1.34)
                            .offset(y: -28)
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
                            .accessibilityLabel("Flamey")
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
                            .offset(y: Self.groundBaseline)
                    }
                    .frame(width: leftWidth, height: geo.size.height, alignment: .top)

                    funStatRows
                        // Clears the savers chip in the corner above — at 8 the
                        // streak box sat right against it.
                        .padding(.top, 24)
                        .frame(width: rightWidth, height: geo.size.height, alignment: .top)
                }
            }
            .frame(height: statFrameHeight)

            DashboardMilestoneBar(streak: userManager.currentUser.streak)
                .padding(.horizontal, 2)
        }
        .padding(18)
        .padding(.top, 18)
        .background(cardBackground)
        // Share sits beside the savers chip, NOT in the top-left corner where
        // it first went: Flamey's frame is 1.5× his size and offset 28pt up, so
        // it overflows the left column into that corner, covered the glyph, and
        // — since the glyph was a bare Image with no gesture — swallowed its
        // taps into `poke()`. The top-right is the one corner of this card
        // nothing else reaches.
        .overlay(alignment: .topTrailing) {
            // ACTION at the corner, STATUS inboard of it. The two were the
            // other way round, which left the Share button floating in the gap
            // between Flamey and the stat column — anchored to nothing, and
            // reading as a twin of the savers chip rather than as the one
            // thing in this corner you can press.
            HStack(spacing: 6) {
                tokensChip
                HeroShareButton {
                    MADHaptics.action()
                    showShareSheet = true
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
        }
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
        let accent = atAllTimeBest ? gold : statusColor

        return HStack(alignment: .center, spacing: 8) {
            Text("\(heroStreakValue)")
                .madFont(size: 35, weight: .black, design: .rounded, monospacedDigit: true)
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.40), radius: 4, x: 0, y: 2)
                .lineLimit(1)
                .minimumScaleFactor(0.62)

            Rectangle()
                .fill(accent.opacity(0.45))
                .frame(width: 1, height: 26)

            VStack(alignment: .leading, spacing: 2) {
                Text("Day Streak")
                    .madFont(size: 9, weight: .black, design: .rounded)
                    .tracking(1.1)
                    .textCase(.uppercase)
                    .foregroundColor(.white.opacity(0.75))
                    .lineLimit(1)
                    .minimumScaleFactor(0.58)

                // The status ("Streak at risk", "Syncing", "Streak safe") used
                // to be its own pill under this box. It rides ON the streak
                // now — the box already accents in the status colour — and the
                // freed row is what lets this column carry the same three stats
                // the Modern hero does. The crown shares that one line, and
                // yields it whenever the status is actually urgent.
                if atAllTimeBest && !statusIsUrgent {
                    HStack(spacing: 3) {
                        Image(systemName: "crown.fill")
                            .madFont(size: 8, weight: .black)
                        Text("Best ever")
                            .madFont(size: 9, weight: .black, design: .rounded)
                            .tracking(0.9)
                            .textCase(.uppercase)
                    }
                    .foregroundColor(gold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                } else {
                    Text(statusText)
                        .madFont(size: 9, weight: .black, design: .rounded)
                        .tracking(0.5)
                        .textCase(.uppercase)
                        .foregroundColor(statusColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.55)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .fill(atAllTimeBest ? gold.opacity(0.10) : Color.black.opacity(0.18))
                .overlay(
                    RoundedRectangle(cornerRadius: 17, style: .continuous)
                        .strokeBorder(accent.opacity(atAllTimeBest ? 0.45 : 0.20), lineWidth: 1)
                )
        )
    }

    private var tokensChip: some View {
        Button {
            showTokens = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "shield.lefthalf.filled")
                    .accessibilityLabel("Streak savers")
                    .madFont(size: 11, weight: .bold)
                Text("\(readyTokens)")
                    .madFont(size: 12, weight: .black, design: .rounded, monospacedDigit: true)
                Text(readyTokens == 1 ? "saver" : "savers")
                    .madFont(size: 11, weight: .heavy, design: .rounded)
            }
            .foregroundColor(.white.opacity(0.90))
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(Capsule().fill(Color.green.opacity(0.12)))
            .overlay(Capsule().strokeBorder(Color.green.opacity(0.26), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(readyTokens) streak savers ready")
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

            HeroStatColumn(
                currentDistance: currentDistance,
                steps: healthManager.todaysSteps,
                fastestPace: healthManager.todaysFastestPace,
                timeLeftText: formattedTimeOnly,
                statusColor: statusColor
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
            title: trustedDone ? "Logged" : "To go",
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
            title: trustedDone ? "Safe" : "Left today",
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
        if injuryPause.isPaused { return "Paused for injury" }
        if trustedDone { return "Streak safe" }
        if savedToday != nil { return "Covered today" }
        if !distanceIsFresh { return "Syncing" }
        if userManager.currentUser.isStreakAtRisk { return "Streak at risk" }
        return "Keep it alive"
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
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
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

            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(Color.white.opacity(0.09), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.20), radius: 18, x: 0, y: 10)
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
    let trustedDone: Bool
    let hasActiveWorkout: Bool
    @Binding var showWorkoutView: Bool

    var body: some View {
        VStack(spacing: 10) {
            DashboardStartMileButton(hasActiveWorkout: hasActiveWorkout, prominent: true, showWorkoutView: $showWorkoutView)
            BuddyWalkPill(hasActiveWorkout: hasActiveWorkout)
        }
    }
}
