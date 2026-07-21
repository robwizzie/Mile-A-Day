import SwiftUI
import HealthKit

// MARK: - Week At A Glance Card

struct WeekAtAGlanceCard: View {
    @ObservedObject var healthManager: HealthKitManager
    @ObservedObject var userManager: UserManager
    @Environment(\.colorScheme) var colorScheme
    @State private var selectedDay: Date?

    private var last7Days: [Date] {
        let calendar = Calendar.current
        let today = Date()

        // Get the start of the current week (Sunday)
        let weekday = calendar.component(.weekday, from: today)
        let daysFromSunday = weekday - 1 // Sunday is 1, so this gives us offset

        guard let startOfWeek = calendar.date(byAdding: .day, value: -daysFromSunday, to: calendar.startOfDay(for: today)) else {
            return []
        }

        // Generate Sunday through Saturday
        return (0..<7).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: startOfWeek)
        }
    }

    var body: some View {
        NavigationLink(destination: StepsView(healthManager: healthManager, userManager: userManager)) {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                HStack {
                    Image(systemName: "calendar.circle.fill")
                        .font(.title2)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color(red: 217/255, green: 64/255, blue: 63/255), .orange],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        Text("This Week")
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // Week view
                HStack(spacing: 8) {
                    ForEach(last7Days, id: \.self) { date in
                        DayProgressView(
                            date: date,
                            healthManager: healthManager,
                            userManager: userManager,
                            isSelected: selectedDay == date
                        )
                    }
                }
            }
            .padding()
            .background(
                ZStack {
                    // Liquid glass background
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.ultraThinMaterial)

                    // Gradient overlay
                    LinearGradient(
                        colors: [
                            Color(red: 217/255, green: 64/255, blue: 63/255).opacity(0.05),
                            Color.clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                    // Glass border
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(colorScheme == .dark ? 0.2 : 0.3),
                                    Color.clear
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
            )
            .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Day Progress View

struct DayProgressView: View {
    let date: Date
    @ObservedObject var healthManager: HealthKitManager
    @ObservedObject var userManager: UserManager
    let isSelected: Bool

    private static let dayLetterFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "E"
        return f
    }()

    private static let dayNumberFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d"
        return f
    }()

    private var dayLetter: String {
        String(Self.dayLetterFormatter.string(from: date).prefix(1))
    }

    private var dayNumber: String {
        Self.dayNumberFormatter.string(from: date)
    }

    private var isToday: Bool {
        Calendar.current.isDateInToday(date)
    }

    private var completedGoal: Bool {
        let calendar = Calendar.current
        let dateKey = calendar.startOfDay(for: date)
        return healthManager.dailyMileGoals[dateKey] ?? false
    }

    private var stepCount: Int {
        let calendar = Calendar.current
        let dateKey = calendar.startOfDay(for: date)
        return healthManager.dailyStepsData[dateKey] ?? 0
    }

    private var hasActivity: Bool {
        return stepCount > 0
    }

    private var reachedStepGoal: Bool {
        return stepCount >= 10000
    }

    var body: some View {
        VStack(spacing: 4) {
            Text(dayLetter)
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundColor(.secondary)

            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.2), lineWidth: 2)
                    .frame(width: 36, height: 36)

                if completedGoal {
                    // Mile goal completed - green circle with running man
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [.green, .green.opacity(0.7)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 36, height: 36)

                    Image(systemName: "figure.run")
                        .font(.system(size: 14))
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                } else if hasActivity {
                    // Has activity but didn't reach mile goal
                    Circle()
                        .fill(Color.orange.opacity(0.3))
                        .frame(width: 36, height: 36)

                    // Small dot for partial activity
                    Circle()
                        .fill(Color.orange.opacity(0.6))
                        .frame(width: 12, height: 12)
                }

                if isToday {
                    Circle()
                        .stroke(Color(red: 217/255, green: 64/255, blue: 63/255), lineWidth: 2)
                        .frame(width: 40, height: 40)
                }
            }

            // Step goal indicator (like calendar)
            if reachedStepGoal {
                Image(systemName: "shoeprints.fill")
                    .font(.system(size: 8))
                    .foregroundColor(.blue)
            } else {
                // Placeholder to maintain spacing
                Image(systemName: "shoeprints.fill")
                    .font(.system(size: 8))
                    .foregroundColor(.clear)
            }

            Text(dayNumber)
                .font(.caption2)
                .fontWeight(isToday ? .bold : .regular)
                .foregroundColor(isToday ? .primary : .secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Badges Preview Card

struct BadgesPreviewCard: View {
    @ObservedObject var userManager: UserManager
    @ObservedObject var healthManager: HealthKitManager
    @AppStorage("trackedBadgeIds") private var trackedBadgeIdsRaw: String = ""
    @State private var challengesCompletedCount: Int = ChallengeService.shared.allCompletions().count

    private var trackedBadgeIds: Set<String> {
        Set(trackedBadgeIdsRaw.split(separator: ",").map(String.init))
    }

    private var recentBadges: [Badge] {
        let earnedBadges = userManager.currentUser.badges.filter { !$0.isLocked }
        let sortedBadges = earnedBadges.sorted { badge1, badge2 in
            (badge1.dateAwarded) > (badge2.dateAwarded)
        }
        return Array(sortedBadges.prefix(3))
    }

    private var earnedCount: Int {
        userManager.currentUser.badges.filter { !$0.isLocked }.count
    }

    private var totalCount: Int {
        userManager.currentUser.getAllBadges().count
    }

    private var progress: Double {
        totalCount > 0 ? Double(earnedCount) / Double(totalCount) : 0
    }

    /// Computes the closest locked badges and their progress
    private var closestLockedBadges: [(badge: Badge, progress: Double)] {
        let user = userManager.currentUser
        let lockedBadges = user.getAllBadges().filter { $0.isLocked }

        var results: [(badge: Badge, progress: Double)] = []

        for badge in lockedBadges {
            let badgeProgress: Double

            if badge.id.starts(with: "streak_") || badge.id.starts(with: "consistency_") {
                let target = Double(badge.numericValue)
                badgeProgress = target > 0 ? min(Double(user.streak) / target, 0.99) : 0
            } else if badge.id.starts(with: "miles_") {
                let target = Double(badge.numericValue)
                badgeProgress = target > 0 ? min(healthManager.totalLifetimeMiles / target, 0.99) : 0
            } else if badge.id.starts(with: "pace_") {
                // Pace badges: lower is better, progress = target / current
                let target = Double(badge.numericValue)
                let currentPace = user.fastestMilePace
                if currentPace > 0 && target > 0 {
                    badgeProgress = min(target / currentPace, 0.99)
                } else {
                    badgeProgress = 0
                }
            } else if badge.id.starts(with: "daily_") {
                // Daily distance badges
                let target: Double
                switch badge.id {
                case "daily_10k": target = 6.2
                case "daily_half": target = 13.1
                case "daily_marathon": target = 26.2
                case "daily_50k": target = 31.0
                case "daily_ultra": target = 50.0
                default: target = Double(badge.numericValue)
                }
                badgeProgress = target > 0 ? min(user.mostMilesInOneDay / target, 0.99) : 0
            } else if badge.id.starts(with: "challenge_") {
                let target = Double(badge.numericValue)
                badgeProgress = target > 0 ? min(Double(challengesCompletedCount) / target, 0.99) : 0
            } else {
                badgeProgress = 0
            }

            results.append((badge, badgeProgress))
        }

        // Sort by highest progress (closest to unlocking), take top 2
        return Array(results.sorted { $0.progress > $1.progress }.prefix(2))
    }

    var body: some View {
        NavigationLink(destination: BadgesView(userManager: userManager, initialBadge: nil)) {
            VStack(spacing: 14) {
                // Header row
                HStack(spacing: 12) {
                    // Trophy icon
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.yellow, .orange],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Medals")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)

                        Text("\(earnedCount) of \(totalCount) unlocked")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    // Progress pill
                    Text("\(Int(progress * 100))%")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(.orange)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(Color.orange.opacity(0.15))
                        )

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                }

                if recentBadges.isEmpty {
                    HStack {
                        Spacer()
                        VStack(spacing: 6) {
                            Image(systemName: "trophy")
                                .font(.system(size: 24))
                                .foregroundColor(.secondary.opacity(0.4))
                            Text("Start running to earn medals!")
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 8)
                        Spacer()
                    }
                } else {
                    // Recent badges row
                    HStack(spacing: 8) {
                        ForEach(recentBadges, id: \.id) { badge in
                            HomeBadgeItem(badge: badge)
                        }
                    }
                }

                // Tracked / Next Up badge progress teaser
                let trackedItems = closestLockedBadges.filter { trackedBadgeIds.contains($0.badge.id) }
                let hasTracked = !trackedItems.isEmpty
                let displayItems = hasTracked ? trackedItems : closestLockedBadges.filter { $0.progress > 0.1 }
                if !displayItems.isEmpty {
                    VStack(spacing: 8) {
                        Rectangle()
                            .fill(Color.white.opacity(0.1))
                            .frame(height: 1)

                        HStack(spacing: 4) {
                            Image(systemName: hasTracked ? "pin.fill" : "arrow.up.circle.fill")
                                .font(.system(size: 10))
                                .foregroundColor(hasTracked ? .cyan.opacity(0.8) : .orange.opacity(0.8))
                            Text(hasTracked ? "Tracked" : "Next Up")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundColor(hasTracked ? .cyan.opacity(0.8) : .orange.opacity(0.8))
                            Spacer()
                        }

                        ForEach(displayItems, id: \.badge.id) { item in
                            HStack(spacing: 10) {
                                // Badge name
                                Text(item.badge.name)
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .foregroundColor(.primary)
                                    .lineLimit(1)

                                Spacer()

                                // Progress bar
                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        RoundedRectangle(cornerRadius: 3)
                                            .fill(Color.white.opacity(0.1))
                                            .frame(height: 6)

                                        RoundedRectangle(cornerRadius: 3)
                                            .fill(
                                                LinearGradient(
                                                    colors: hasTracked ? [.cyan, .blue] : [.orange, .yellow],
                                                    startPoint: .leading,
                                                    endPoint: .trailing
                                                )
                                            )
                                            .frame(width: item.progress * geo.size.width, height: 6)
                                    }
                                }
                                .frame(width: 80, height: 6)

                                // Percentage
                                Text("\(Int(item.progress * 100))%")
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .foregroundColor(hasTracked ? .cyan : .orange)
                                    .frame(width: 36, alignment: .trailing)
                            }
                        }
                    }
                }
            }
            .padding(16)
            .liquidGlassCard()
        }
        .buttonStyle(PlainButtonStyle())
        .onAppear {
            challengesCompletedCount = ChallengeService.shared.allCompletions().count
        }
        .onReceive(NotificationCenter.default.publisher(for: ChallengeService.changedNotification)) { _ in
            challengesCompletedCount = ChallengeService.shared.allCompletions().count
        }
    }
}

// MARK: - Home Badge Item
struct HomeBadgeItem: View {
    let badge: Badge

    var body: some View {
        VStack(spacing: 10) {
            // Shared MedalView at dashboard size — keeps the look identical to
            // the grid, detail, and showcase. No shimmer at this compact size
            // to keep the dashboard lightweight.
            MedalView(badge: badge, size: 56, showShimmer: false)
                .frame(width: 70, height: 70)

            // Badge name
            Text(badge.name)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Calendar Preview Card

struct CalendarPreviewCard: View {
    @ObservedObject var healthManager: HealthKitManager
    @ObservedObject var userManager: UserManager

    private var todaysSteps: Int {
        healthManager.todaysSteps
    }

    private var stepProgress: Double {
        min(Double(todaysSteps) / 10000.0, 1.0)
    }

    private var stepColor: Color {
        if todaysSteps >= 10000 {
            return .green
        } else if todaysSteps >= 7500 {
            return .orange
        } else if todaysSteps >= 5000 {
            return .yellow
        } else {
            return .gray
        }
    }

    var body: some View {
        NavigationLink(destination: StepsView(healthManager: healthManager, userManager: userManager)) {
            HStack(spacing: 16) {
                // Step count circle
                ZStack {
                    // Track
                    Circle()
                        .stroke(Color.white.opacity(0.1), lineWidth: 5)

                    // Progress arc
                    Circle()
                        .trim(from: 0, to: stepProgress)
                        .stroke(
                            LinearGradient(
                                colors: [stepColor, stepColor.opacity(0.7)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            style: StrokeStyle(lineWidth: 5, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))

                    // Icon
                    Image(systemName: "shoeprints.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.blue, .cyan],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                .frame(width: 56, height: 56)

                // Text content
                VStack(alignment: .leading, spacing: 4) {
                    Text("Steps")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(.secondary)

                    Text("\(todaysSteps)")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)

                    Text("\(Int(stepProgress * 100))% of 10k goal")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(stepColor)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            .padding(16)
            .liquidGlassCard()
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Daily Challenge Card

struct DailyChallengeCard: View {
    @ObservedObject var healthManager: HealthKitManager
    @ObservedObject var userManager: UserManager
    @Environment(\.colorScheme) var colorScheme
    @State private var todaysChallenge: DailyChallenge?
    @State private var tomorrowsChallenge: DailyChallenge?
    @State private var challengeProgressValue: Double = 0
    @State private var isCompleted: Bool = false
    @State private var challengesCompletedCount: Int = ChallengeService.shared.allCompletions().count
    @State private var challengeStreak: Int = ChallengeService.shared.currentChallengeStreak()
    @State private var opponent: ChallengeOpponent?
    @State private var iconPulse: Bool = false

    private var primaryColor: Color {
        todaysChallenge?.gradient.first ?? MADTheme.Colors.madRed
    }

    private var accentColor: Color {
        isCompleted ? .green : primaryColor
    }

    var body: some View {
        Group {
            if let challenge = todaysChallenge {
                challengeCard(challenge)
            } else {
                placeholderCard
            }
        }
        // task(id:) re-runs when backendUserId changes. A plain .task fires once on
        // appear — if the profile hadn't loaded yet at that instant it bailed on the
        // guard and never fetched, leaving the card on "Loading…" forever.
        .task(id: userManager.currentUser.backendUserId) {
            guard let userId = userManager.currentUser.backendUserId else { return }
            await ChallengeService.refresh(userId: userId)
            refreshFromService()
        }
        .onReceive(NotificationCenter.default.publisher(for: ChallengeService.changedNotification)) { _ in
            refreshFromService()
        }
        .onAppear {
            // Pick up any cached challenge state immediately (the service restores
            // today's snapshot from UserDefaults) instead of waiting on the network.
            refreshFromService()
            // Subtle pulse on the icon when not completed — draws the eye without being annoying.
            iconPulse = true
        }
    }

    // MARK: Loading / empty state — never disappear from the dashboard.

    @ViewBuilder
    private var placeholderCard: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 54, height: 54)
                Image(systemName: "trophy.fill")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundColor(MADTheme.Colors.madRed.opacity(0.7))
            }
            VStack(alignment: .leading, spacing: 7) {
                Text("Daily Challenge")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(MADTheme.Colors.madRed)
                Text("Loading today's challenge…")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                Text("Tap to see what's in store")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.secondary)
        }
        .padding(16)
        .background(cardBackground)
        .shadow(color: .black.opacity(0.12), radius: 12, x: 0, y: 6)
    }

    @ViewBuilder
    private func challengeCard(_ challenge: DailyChallenge) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Top row: icon + title + reward chip
            HStack(spacing: 14) {
                challengeIcon(challenge)

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Text("Daily Challenge")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundColor(accentColor)

                        if challengeStreak >= 2 {
                            HStack(spacing: 2) {
                                Image(systemName: "flame.fill")
                                    .font(.system(size: 8, weight: .bold))
                                Text("\(challengeStreak)")
                                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                            }
                            .foregroundColor(.orange)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(
                                Capsule().fill(Color.orange.opacity(0.18))
                            )
                        }

                        Spacer(minLength: 0)

                        if isCompleted {
                            HStack(spacing: 3) {
                                Image(systemName: "checkmark.seal.fill")
                                    .font(.system(size: 12, weight: .bold))
                                Text("\(challengesCompletedCount)")
                                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                            }
                            .foregroundColor(.green)
                        } else {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 17, weight: .bold))
                                .foregroundColor(.secondary)
                        }
                    }

                    Text(isCompleted ? "\(challenge.title) — Complete!" : challenge.title)
                        .font(.system(size: 18, weight: .heavy, design: .rounded))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)

                    Text(challenge.description)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            // Progress bar with inline percentage
            progressRow(challenge)

            // Head-to-Head: show the live "you vs rival" strip.
            if challenge.key == "head_to_head", let opp = opponent {
                HeadToHeadStrip(opponent: opp, accent: primaryColor)
            }

            // Footer: tomorrow preview (incomplete) OR celebration (complete)
            footerRow(challenge)
        }
        .padding(16)
        .background(cardBackground)
        .shadow(color: accentColor.opacity(0.16), radius: 14, x: 0, y: 7)
    }

    @ViewBuilder
    private func challengeIcon(_ challenge: DailyChallenge) -> some View {
        ZStack {
            // Outer halo
            Circle()
                .fill(
                    LinearGradient(
                        colors: isCompleted ? [.green.opacity(0.35), .green.opacity(0.0)] : [primaryColor.opacity(0.35), primaryColor.opacity(0.0)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 58, height: 58)
                .scaleEffect(iconPulse && !isCompleted ? 1.05 : 1.0)
                .animation(
                    isCompleted ? .default :
                        .easeInOut(duration: 1.8).repeatForever(autoreverses: true),
                    value: iconPulse
                )

            Circle()
                .fill(
                    LinearGradient(
                        colors: isCompleted ? [.green, Color(red: 0.18, green: 0.78, blue: 0.42)] : challenge.gradient,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 46, height: 46)
                .overlay(
                    Circle().stroke(Color.white.opacity(0.25), lineWidth: 1)
                )

            Image(systemName: isCompleted ? "checkmark" : challenge.icon)
                .font(.system(size: 19, weight: .bold))
                .foregroundColor(.white)
        }
    }

    @ViewBuilder
    private func progressRow(_ challenge: DailyChallenge) -> some View {
        let progress = challengeProgressValue
            VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.10))
                        .frame(height: 8)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            LinearGradient(
                                colors: isCompleted ? [.green, Color(red: 0.18, green: 0.78, blue: 0.42)] : challenge.gradient,
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(8, progress * geo.size.width), height: 8)
                        .animation(.spring(response: 0.7, dampingFraction: 0.85), value: progress)
                }
            }
            .frame(height: 8)
            HStack {
                Text(isCompleted ? "Locked in" : progressLabel(progress))
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(accentColor)
                Spacer()
                Text("\(Int(round(min(progress, 1.0) * 100)))%")
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundColor(.primary.opacity(0.7))
                    .contentTransition(.numericText())
            }
        }
    }

    @ViewBuilder
    private func footerRow(_ challenge: DailyChallenge) -> some View {
        // Tomorrow preview is shown in every state — completed or not — so users always
        // know what's coming and can plan ahead.
        if let tomorrow = tomorrowsChallenge {
            HStack(spacing: 8) {
                Image(systemName: "calendar")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.secondary)
                Text("Tomorrow:")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(.secondary)
                HStack(spacing: 5) {
                    Image(systemName: tomorrow.icon)
                        .font(.system(size: 11, weight: .bold))
                    Text(tomorrow.title)
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .lineLimit(1)
                }
                .foregroundColor(tomorrow.gradient.first ?? .primary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule().fill((tomorrow.gradient.first ?? .gray).opacity(0.12))
                )
                Spacer(minLength: 0)
                if isCompleted {
                    Image(systemName: "sparkles")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.yellow)
                }
            }
            .padding(.top, 2)
        } else if isCompleted {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.yellow)
                Text("Nice work — \(challengesCompletedCount) total completion\(challengesCompletedCount == 1 ? "" : "s")")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary.opacity(0.8))
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.secondary)
            }
            .padding(.top, 2)
        }
    }

    private var cardBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial)

            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            accentColor.opacity(0.10),
                            accentColor.opacity(0.035),
                            Color.clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            accentColor.opacity(0.32),
                            accentColor.opacity(0.10),
                            Color.white.opacity(0.07)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
    }

    private func progressLabel(_ value: Double) -> String {
        if value <= 0 { return "Let's go — start your mile" }
        if value < 0.5 { return "Off the line — keep building" }
        if value < 0.85 { return "Closing in" }
        return "So close — finish strong"
    }

    /// Read the server-backed state from `ChallengeService.shared` (a `RemoteChallengeService`).
    /// Server is authoritative for completion + challenge_* badges.
    private func refreshFromService() {
        if let remote = ChallengeService.shared as? RemoteChallengeService {
            todaysChallenge = remote.todayChallenge
            tomorrowsChallenge = remote.tomorrowChallenge
            challengeProgressValue = remote.todayProgress
            isCompleted = remote.todayCompleted
            opponent = remote.todayOpponent
        }
        challengesCompletedCount = ChallengeService.shared.allCompletions().count
        challengeStreak = ChallengeService.shared.currentChallengeStreak()
    }
}

struct DailyChallenge {
    let key: String
    let title: String
    let description: String
    let icon: String
    let gradient: [Color]
    let type: ChallengeType

    enum ChallengeType {
        case pace, distance, time, activity, steps, social
    }
}

/// Today's Head-to-Head rival (only present when the challenge is `head_to_head`).
struct ChallengeOpponent: Equatable {
    let userId: String
    let username: String?
    let profileImageUrl: String?
    let miles: Double
    let myMiles: Double
    /// TRUE when the rival's own Head-to-Head is against you too (reciprocal pair).
    let mutual: Bool
}

/// Fun "you vs rival" strip for the Head-to-Head daily challenge. Shows both
/// avatars + today's miles with a live lead indicator. Reused by the dashboard
/// card and the dedicated challenges hero.
struct HeadToHeadStrip: View {
    let opponent: ChallengeOpponent
    let accent: Color

    private var myName: String {
        UserManager.shared.currentUser.username ?? UserManager.shared.currentUser.name
    }
    private var myImage: String? { UserManager.shared.currentUser.profileImageUrl }
    private var rivalName: String { opponent.username ?? "Rival" }
    private var tied: Bool { abs(opponent.myMiles - opponent.miles) < 0.01 }
    private var leading: Bool { opponent.myMiles > opponent.miles && !tied }

    private var statusText: String {
        if tied { return "Dead even" }
        if leading {
            return "You lead by \(String(format: "%.2f", opponent.myMiles - opponent.miles)) mi"
        }
        return "Behind by \(String(format: "%.2f", opponent.miles - opponent.myMiles)) mi"
    }

    private var statusColor: Color { tied ? .yellow : (leading ? .green : .orange) }

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                side(name: "You", image: myImage, miles: opponent.myMiles,
                     highlight: leading, color: accent)

                VStack(spacing: 2) {
                    Text("VS")
                        .font(.system(size: 13, weight: .black, design: .rounded))
                        .foregroundColor(.primary.opacity(0.6))
                    Text(statusText)
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundColor(statusColor)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(width: 86)

                side(name: rivalName, image: opponent.profileImageUrl, miles: opponent.miles,
                     highlight: !leading && !tied, color: .orange)
            }

            // The duel is a whole-day total scored after midnight, so the lead
            // shown above is live standings, not a verdict.
            Text(opponent.mutual
                 ? "\(rivalName) got the same matchup · winner decided at day's end"
                 : "Winner decided at day's end")
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(statusColor.opacity(0.35), lineWidth: 1)
                )
        )
    }

    private func side(name: String, image: String?, miles: Double, highlight: Bool, color: Color) -> some View {
        VStack(spacing: 4) {
            AvatarView(name: name, imageURL: image, size: 36)
                .overlay(
                    Circle().strokeBorder(highlight ? color : .clear, lineWidth: 2)
                )
            Text(name)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
                .lineLimit(1)
            Text("\(String(format: "%.2f", miles)) mi")
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundColor(highlight ? color : .primary.opacity(0.75))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Friend Activity Strip

struct FriendActivityStripView: View {
    @ObservedObject var friendService: FriendService
    @State private var activityData: [FriendActivityItem] = []
    @State private var isLoading = true
    @State private var lastFetchDate: Date?
    @State private var selectedUser: BackendUser?

    private var completedCount: Int {
        activityData.filter { $0.completed_today }.count
    }

    private var totalCount: Int {
        activityData.count
    }

    var body: some View {
        Group {
            if !isLoading && !activityData.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    // Header
                    HStack(spacing: 8) {
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.cyan)

                        Text("\(completedCount) of \(totalCount) friends ran today")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundColor(.primary)

                        Spacer()
                    }

                    // Horizontal avatar strip
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(activityData) { friend in
                                Button {
                                    selectedUser = makeBackendUser(friend)
                                } label: {
                                    friendActivityAvatar(friend)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(14)
                .liquidGlassCard()
            }
        }
        .sheet(item: $selectedUser) { user in
            NavigationStack {
                UserProfileDetailView(user: user, friendService: friendService)
            }
        }
        .task {
            // Only fetch if data is stale (>5 min) or never loaded
            if let last = lastFetchDate, Date().timeIntervalSince(last) < 300 {
                return
            }
            await loadActivity()
        }
    }

    /// Build a BackendUser stub from an activity item. UserProfileDetailView
    /// only reads `username`, `displayName`, `profile_image_url`, `user_id` in
    /// its render path — same pattern as LeaderboardSection's row taps.
    private func makeBackendUser(_ friend: FriendActivityItem) -> BackendUser {
        BackendUser(
            user_id: friend.user_id,
            username: friend.username,
            email: "",
            first_name: friend.first_name,
            last_name: friend.last_name,
            bio: nil,
            profile_image_url: friend.profile_image_url,
            apple_id: nil,
            auth_provider: nil,
            role: nil
        )
    }

    private func friendActivityAvatar(_ friend: FriendActivityItem) -> some View {
        VStack(spacing: 4) {
            ZStack {
                AvatarView(
                    name: friend.displayName,
                    imageURL: friend.profile_image_url,
                    size: 42
                )

                // Completion ring
                Circle()
                    .stroke(
                        friend.completed_today ? Color.green : Color.white.opacity(0.15),
                        lineWidth: 2.5
                    )
                    .frame(width: 48, height: 48)

                // Checkmark for completed
                if friend.completed_today {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.green)
                        .background(Circle().fill(Color.black).frame(width: 12, height: 12))
                        .offset(x: 16, y: 16)
                }
            }

            Text(friend.displayName)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundColor(friend.completed_today ? .primary : .secondary)
                .lineLimit(1)
                .frame(width: 50)
        }
        .opacity(friend.completed_today ? 1.0 : 0.5)
    }

    private func loadActivity() async {
        do {
            let data = try await friendService.fetchFriendsActivityToday()
            await MainActor.run {
                activityData = data.sorted { a, b in
                    if a.completed_today != b.completed_today {
                        return a.completed_today
                    }
                    return a.today_miles > b.today_miles
                }
                isLoading = false
                lastFetchDate = Date()
            }
        } catch {
            await MainActor.run {
                isLoading = false
            }
        }
    }
}

// MARK: - Competition Invite Banner

struct CompetitionInviteBanner: View {
    let inviteCount: Int
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        Button {
            NotificationCenter.default.post(
                name: NSNotification.Name("MAD_SwitchTab"),
                object: nil,
                userInfo: ["tab": 1]
            )
        } label: {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [MADTheme.Colors.madRed, MADTheme.Colors.madRed.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 36, height: 36)

                Image(systemName: "trophy.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Competition \(inviteCount == 1 ? "Invite" : "Invites")")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)

                Text("You have \(inviteCount) pending \(inviteCount == 1 ? "invitation" : "invitations")")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
            }

            Spacer()

            Text("View")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(MADTheme.Colors.madRed)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(MADTheme.Colors.madRed.opacity(0.15))
                )
        }
        .padding(14)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(.ultraThinMaterial)

                RoundedRectangle(cornerRadius: 14)
                    .fill(MADTheme.Colors.madRed.opacity(0.05))

                RoundedRectangle(cornerRadius: 14)
                    .stroke(
                        LinearGradient(
                            colors: [
                                MADTheme.Colors.madRed.opacity(0.3),
                                Color.clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
        )
        .shadow(color: MADTheme.Colors.madRed.opacity(0.1), radius: 6, x: 0, y: 3)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Active Competition Banner Card

/// Dashboard preview tile for one active competition. Designed to answer
/// "which comp do I focus on right now?" — leads with today's actionable
/// status (behind by X mi, life at risk, target hit, etc.) rather than the
/// cumulative rank. Cumulative rank still appears as a small chip so the
/// user knows where they stand overall.
struct ActiveCompetitionBannerCard: View {
    let competition: Competition
    var embedded: Bool = false
    @EnvironmentObject var competitionService: CompetitionService
    @Environment(\.colorScheme) var colorScheme
    @State private var showDetail = false

    private var currentUserId: String? {
        UserDefaults.standard.string(forKey: "backendUserId")
    }

    private var rankedUsers: [CompetitionUser] {
        competition.users
            .filter { $0.invite_status == .accepted }
            .sorted { ($0.score ?? 0) > ($1.score ?? 0) }
    }

    private var currentUserRank: Int? {
        guard let userId = currentUserId else { return nil }
        return rankedUsers.firstIndex(where: { $0.user_id == userId }).map { $0 + 1 }
    }

    private var me: CompetitionUser? {
        guard let userId = currentUserId else { return nil }
        return competition.users.first(where: { $0.user_id == userId })
    }

    private var typeGradientColors: [Color] {
        competition.type.gradient.map { Color(hex: $0) }
    }

    /// Today's interval key — matches the comp's interval setting so weekly /
    /// monthly comps still show the current period's bucket.
    private var todayKey: String {
        CompetitionCard.todayIntervalKey(for: competition)
    }

    private var myToday: Double {
        me?.intervals?[todayKey] ?? 0
    }

    private var focus: TodayFocus {
        TodayFocus.compute(for: competition, currentUserId: currentUserId)
    }

    var body: some View {
        Button {
            showDetail = true
        } label: {
            if embedded {
                VStack(alignment: .leading, spacing: 10) {
                    topRow
                    Divider()
                        .background(Color.white.opacity(0.06))
                    bottomRow
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 6)
                .contentShape(Rectangle())
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    topRow
                    Divider()
                        .background(Color.white.opacity(0.06))
                    bottomRow
                }
                .padding(14)
                .liquidGlassCard(accentColor: focus.level.color)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .sheet(isPresented: $showDetail) {
            NavigationStack {
                CompetitionDetailView(competition: competition, competitionService: competitionService)
            }
        }
    }

    private var topRow: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: typeGradientColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 40, height: 40)

                Image(systemName: competition.type.icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(competition.competition_name)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(competition.type.displayName.uppercased())
                        .font(.system(size: 9, weight: .black, design: .rounded))
                        .tracking(0.8)
                        .foregroundColor(typeGradientColors.first ?? .green)

                    if let interval = competition.options.interval {
                        Text("·")
                            .foregroundColor(.secondary.opacity(0.5))
                        Text(interval.displayName)
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundColor(.secondary)
                    }

                    if let rank = currentUserRank {
                        Text("·")
                            .foregroundColor(.secondary.opacity(0.5))
                        Text("\(rankOrdinal(rank)) of \(rankedUsers.count)")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundColor(rank == 1 ? .yellow : .secondary)
                    }
                }
            }

            Spacer(minLength: 6)

            urgencyPill
        }
    }

    private var urgencyPill: some View {
        HStack(spacing: 4) {
            Image(systemName: focus.pillIcon)
                .font(.system(size: 9, weight: .heavy))
            Text(focus.pill)
                .font(.system(size: 9, weight: .black, design: .rounded))
                .tracking(0.7)
        }
        .foregroundColor(focus.level.color)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(focus.level.color.opacity(0.15))
                .overlay(Capsule().strokeBorder(focus.level.color.opacity(0.4), lineWidth: 1))
        )
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
    }

    private var bottomRow: some View {
        HStack(spacing: 8) {
            Image(systemName: focus.level.iconBackground)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(focus.level.color)
                .frame(width: 18)

            Text(focus.detail)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(.primary.opacity(0.85))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 4)

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .heavy))
                .foregroundColor(.secondary)
        }
    }

    private func fmt(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    private func rankOrdinal(_ rank: Int) -> String {
        switch rank {
        case 1: return "1st"
        case 2: return "2nd"
        case 3: return "3rd"
        default: return "\(rank)th"
        }
    }
}

/// Lightweight value type carrying everything the banner needs to render the
/// "today focus" portion. Built fresh per body evaluation, so it's free.
struct TodayFocus {
    let level: UrgencyLevel
    let pill: String
    let pillIcon: String
    let detail: String

    /// Mode-specific status that answers "what should I do today?". Used by
    /// the dashboard banner for rendering AND by the dashboard list sort.
    /// Extracted to a static so the sort doesn't need to spin up a View.
    static func compute(for competition: Competition, currentUserId: String?) -> TodayFocus {
        let me = competition.users.first(where: { $0.user_id == currentUserId })
        let todayKey = CompetitionCard.todayIntervalKey(for: competition)
        let myToday = me?.intervals?[todayKey] ?? 0
        let unit = competition.options.unit.shortDisplayName
        let goal = competition.options.goal

        switch competition.type {
        case .clash, .apex:
            let opponents = competition.users.filter { $0.invite_status == .accepted && $0.user_id != currentUserId }
            let leader = opponents.max(by: { ($0.intervals?[todayKey] ?? 0) < ($1.intervals?[todayKey] ?? 0) })
            let leaderToday = leader?.intervals?[todayKey] ?? 0

            if leader == nil || (leaderToday == 0 && myToday == 0) {
                return TodayFocus(
                    level: .neutral,
                    pill: "NO ACTIVITY YET",
                    pillIcon: "figure.run",
                    detail: "Be the first to put miles on the board today."
                )
            }
            let diff = myToday - leaderToday
            if diff >= 0 && myToday > 0 {
                return TodayFocus(
                    level: .winning,
                    pill: "LEADING TODAY",
                    pillIcon: "crown.fill",
                    detail: "You: \(fmt(myToday)) \(unit) · ahead by \(fmt(diff)) \(unit)"
                )
            }
            let gap = abs(diff)
            return TodayFocus(
                level: gap <= 0.5 ? .urgent : .behind,
                pill: "BEHIND \(fmt(gap)) \(unit.uppercased())",
                pillIcon: "bolt.fill",
                detail: "You: \(fmt(myToday)) \(unit) · \(leader?.displayName ?? "Leader"): \(fmt(leaderToday)) \(unit)"
            )

        case .targets:
            if myToday >= goal {
                return TodayFocus(
                    level: .winning,
                    pill: "TARGET HIT",
                    pillIcon: "checkmark.seal.fill",
                    detail: "+1 point locked in · total \(Int(me?.score ?? 0)) pts"
                )
            }
            let remaining = max(0, goal - myToday)
            return TodayFocus(
                level: remaining <= goal * 0.25 ? .urgent : .behind,
                pill: "\(fmt(remaining)) \(unit.uppercased()) TO GO",
                pillIcon: "target",
                detail: "\(fmt(myToday)) / \(competition.options.goalFormatted) \(unit) — hit it for the point"
            )

        case .streaks:
            let lives = me?.remaining_lives ?? competition.streakLives
            let streakDays = Int(me?.score ?? 0)

            if myToday >= goal {
                return TodayFocus(
                    level: .winning,
                    pill: "STREAK SAFE",
                    pillIcon: "flame.fill",
                    detail: "\(streakDays)-day streak · \(lives) \(lives == 1 ? "life" : "lives") in the bank"
                )
            }
            let remaining = max(0, goal - myToday)
            let isUrgent = lives <= 1
            return TodayFocus(
                level: isUrgent ? .urgent : .behind,
                pill: isUrgent ? "1 LIFE LEFT" : "\(fmt(remaining)) \(unit.uppercased()) LEFT",
                pillIcon: "flame.fill",
                detail: isUrgent
                    ? "Miss today's \(competition.options.goalFormatted) \(unit) and you're out."
                    : "\(fmt(remaining)) \(unit) to keep the \(streakDays)-day streak"
            )

        case .race:
            let total = me?.score ?? 0
            let pct = goal > 0 ? min(100, Int((total / goal) * 100)) : 0
            if total >= goal {
                return TodayFocus(
                    level: .winning,
                    pill: "FINISHED",
                    pillIcon: "flag.checkered",
                    detail: "You crossed the finish line · \(fmt(total)) \(unit)"
                )
            }
            let remaining = max(0, goal - total)
            return TodayFocus(
                level: pct >= 80 ? .urgent : .behind,
                pill: "\(pct)% TO GO",
                pillIcon: "flag.checkered",
                detail: "+\(fmt(myToday)) today · \(fmt(remaining)) \(unit) left to finish"
            )
        }
    }

    private static func fmt(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
}

enum UrgencyLevel {
    case urgent       // act now — life at risk / behind by tiny gap
    case behind       // behind but not critical
    case neutral      // no activity yet today
    case winning      // already done / leading

    var color: Color {
        switch self {
        case .urgent:   return Color(red: 1.00, green: 0.45, blue: 0.30)
        case .behind:   return .orange
        case .neutral:  return .gray
        case .winning:  return .green
        }
    }

    var iconBackground: String {
        switch self {
        case .urgent:   return "exclamationmark.circle.fill"
        case .behind:   return "arrow.up.circle.fill"
        case .neutral:  return "circle.dashed"
        case .winning:  return "checkmark.circle.fill"
        }
    }

    /// Lower = more urgent. Drives dashboard sort order.
    var sortKey: Int {
        switch self {
        case .urgent:   return 0
        case .behind:   return 1
        case .neutral:  return 2
        case .winning:  return 3
        }
    }
}

// MARK: - Getting Started Checklist

/// New-user activation card: four first-session goals with live completion
/// ticks. Each row deep-links to the place where the action happens. The
/// card hides itself once every item is done (or the user dismisses it), so
/// established users never see it.
struct GettingStartedChecklistCard: View {
    struct Item: Identifiable {
        let id: String
        let icon: String
        let title: String
        let subtitle: String
        let isDone: Bool
        let action: () -> Void
    }

    let items: [Item]
    let onDismiss: () -> Void

    private var completedCount: Int {
        items.filter(\.isDone).count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "checklist")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(
                        LinearGradient(colors: [MADTheme.Colors.madRed, .orange], startPoint: .top, endPoint: .bottom)
                    )

                VStack(alignment: .leading, spacing: 1) {
                    Text("Getting Started")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                    Text("\(completedCount) of \(items.count) done")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.secondary)
                        .padding(6)
                        .background(Circle().fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
            }

            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    Button(action: item.action) {
                        HStack(spacing: 12) {
                            Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 20))
                                .foregroundColor(item.isDone ? .green : .secondary.opacity(0.5))

                            Image(systemName: item.icon)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(item.isDone ? .secondary : MADTheme.Colors.madRed)
                                .frame(width: 22)

                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.title)
                                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                                    .foregroundColor(.primary)
                                    .strikethrough(item.isDone, color: .secondary)
                                Text(item.subtitle)
                                    .font(.system(size: 11, weight: .medium, design: .rounded))
                                    .foregroundColor(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            Spacer()

                            if !item.isDone {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                        .opacity(item.isDone ? 0.6 : 1.0)
                    }
                    .buttonStyle(.plain)
                    .disabled(item.isDone)

                    if index < items.count - 1 {
                        Rectangle()
                            .fill(Color.white.opacity(0.06))
                            .frame(height: 0.5)
                    }
                }
            }
        }
        .padding(16)
        .liquidGlassCard()
    }
}

// MARK: - Dashboard Collapsible Section

struct DashboardCollapsibleSection<Content: View>: View {
    let title: String
    let icon: String
    /// Optional trailing signal ("2 need you today") so a collapsed section
    /// can still surface urgency without being expanded.
    var accessoryText: String? = nil
    var accessoryColor: Color = .orange
    @Binding var isCollapsed: Bool
    var unified: Bool = false
    @ViewBuilder let content: () -> Content
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        if unified {
            unifiedLayout
        } else {
            separatedLayout
        }
    }

    private var headerRow: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.secondary)

            Text(title)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Spacer()

            if let accessoryText {
                Text(accessoryText)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(accessoryColor)
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(accessoryColor.opacity(0.14)))
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
                .rotationEffect(.degrees(isCollapsed ? 0 : 90))
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .contentShape(Rectangle())
    }

    private var separatedLayout: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    isCollapsed.toggle()
                }
            } label: {
                headerRow
                    .background(
                        ZStack {
                            RoundedRectangle(cornerRadius: 14)
                                .fill(.ultraThinMaterial)

                            RoundedRectangle(cornerRadius: 14)
                                .stroke(
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(colorScheme == .dark ? 0.15 : 0.25),
                                            Color.clear
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        }
                    )
                    .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
            }
            .buttonStyle(PlainButtonStyle())

            if !isCollapsed {
                content()
                    .padding(.top, 8)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var unifiedLayout: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    isCollapsed.toggle()
                }
            } label: {
                headerRow
            }
            .buttonStyle(PlainButtonStyle())

            if !isCollapsed {
                Rectangle()
                    .fill(Color.white.opacity(colorScheme == .dark ? 0.08 : 0.12))
                    .frame(height: 0.5)

                content()
                    .padding(.vertical, 10)
                    .padding(.horizontal, 10)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)

                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(colorScheme == .dark ? 0.15 : 0.25),
                                Color.clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
        )
        .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Weekly Trend Card

struct WeeklyTrendCard: View {
    @ObservedObject var healthManager: HealthKitManager
    @ObservedObject var userManager: UserManager
    @Environment(\.colorScheme) var colorScheme

    private var thisWeekStart: Date {
        let calendar = Calendar.current
        let today = Date()
        let weekday = calendar.component(.weekday, from: today)
        let daysFromSunday = weekday - 1
        return calendar.date(byAdding: .day, value: -daysFromSunday, to: calendar.startOfDay(for: today)) ?? today
    }

    private var lastWeekStart: Date {
        Calendar.current.date(byAdding: .day, value: -7, to: thisWeekStart) ?? thisWeekStart
    }

    /// Number of days elapsed this week (Sun=1 through today, inclusive)
    private var daysElapsed: Int {
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: Date()) // 1=Sun
        return weekday
    }

    private var thisWeek: (miles: Double, daysCompleted: Int) {
        healthManager.workoutIndex?.weekTotal(startingOn: thisWeekStart, dayCount: daysElapsed) ?? (0, 0)
    }

    /// Compare only the same number of elapsed days from last week for fairness
    private var lastWeekSamePeriod: (miles: Double, daysCompleted: Int) {
        healthManager.workoutIndex?.weekTotal(startingOn: lastWeekStart, dayCount: daysElapsed) ?? (0, 0)
    }

    /// Full last week totals for context
    private var lastWeekFull: (miles: Double, daysCompleted: Int) {
        healthManager.workoutIndex?.weekTotal(startingOn: lastWeekStart) ?? (0, 0)
    }

    private var milesChange: Double {
        guard lastWeekSamePeriod.miles > 0 else { return thisWeek.miles > 0 ? 100 : 0 }
        return ((thisWeek.miles - lastWeekSamePeriod.miles) / lastWeekSamePeriod.miles) * 100
    }

    private var daysChange: Int {
        thisWeek.daysCompleted - lastWeekSamePeriod.daysCompleted
    }

    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.title3)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.cyan, .blue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                Text("Weekly Trends")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)

                Spacer()
            }

            // Fair comparison note
            if daysElapsed < 7 {
                Text("Comparing first \(daysElapsed) day\(daysElapsed == 1 ? "" : "s") of each week")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
            }

            // Comparison grid
            HStack(spacing: 16) {
                // This week
                trendColumn(
                    label: "This Week",
                    miles: thisWeek.miles,
                    days: thisWeek.daysCompleted,
                    totalDays: daysElapsed,
                    isCurrent: true
                )

                // Divider
                Rectangle()
                    .fill(Color.white.opacity(0.15))
                    .frame(width: 1)
                    .padding(.vertical, 4)

                // Last week (same period)
                trendColumn(
                    label: "Last Week",
                    miles: lastWeekSamePeriod.miles,
                    days: lastWeekSamePeriod.daysCompleted,
                    totalDays: daysElapsed,
                    isCurrent: false
                )
            }

            // Change indicators
            HStack(spacing: 20) {
                changeIndicator(
                    label: "Miles",
                    value: milesChange,
                    isPercentage: true,
                    isPositive: milesChange >= 0
                )

                changeIndicator(
                    label: "Days",
                    value: Double(daysChange),
                    isPercentage: false,
                    isPositive: daysChange >= 0
                )
            }
        }
        .padding(20)
        .liquidGlassCard()
    }

    private func trendColumn(label: String, miles: Double, days: Int, totalDays: Int = 7, isCurrent: Bool) -> some View {
        VStack(spacing: 10) {
            Text(label)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(.secondary)

            Text(String(format: "%.1f", miles))
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(isCurrent ? .primary : .secondary)

            Text("miles")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundColor(.secondary)

            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.green)
                Text("\(days)/\(totalDays) days")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(isCurrent ? .primary : .secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func changeIndicator(label: String, value: Double, isPercentage: Bool, isPositive: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: value == 0 ? "minus" : (isPositive ? "arrow.up.right" : "arrow.down.right"))
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(value == 0 ? .secondary : (isPositive ? .green : .red))

            if isPercentage {
                Text("\(value >= 0 ? "+" : "")\(Int(value))%")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(value == 0 ? .secondary : (isPositive ? .green : .red))
            } else {
                let intVal = Int(value)
                Text("\(intVal >= 0 ? "+" : "")\(intVal)")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(value == 0 ? .secondary : (isPositive ? .green : .red))
            }

            Text(label)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill((value == 0 ? Color.secondary : (isPositive ? Color.green : Color.red)).opacity(0.1))
        )
    }
}

// MARK: - Liquid Glass Card Modifier (for other cards)

struct LiquidGlassCardModifier: ViewModifier {
    @Environment(\.colorScheme) var colorScheme
    let accentColor: Color

    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    // Liquid glass background
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.ultraThinMaterial)

                    // Subtle highlight gradient for glass effect
                    RoundedRectangle(cornerRadius: 16)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.1),
                                    Color.white.opacity(0.05)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    // Glass border
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(colorScheme == .dark ? 0.25 : 0.3),
                                    Color.clear
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
            )
            .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
    }
}

extension View {
    func liquidGlassCard(accentColor: Color = Color(red: 217/255, green: 64/255, blue: 63/255)) -> some View {
        modifier(LiquidGlassCardModifier(accentColor: accentColor))
    }
}
