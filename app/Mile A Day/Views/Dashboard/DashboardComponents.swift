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
    @State private var shimmerPhase: CGFloat = -1
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
                            HomeBadgeItem(badge: badge, shimmerPhase: shimmerPhase)
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
            withAnimation(.linear(duration: 2.5).repeatForever(autoreverses: false)) {
                shimmerPhase = 1.5
            }
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
    let shimmerPhase: CGFloat
    
    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                // Outer glow
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [badge.rarity.color.opacity(0.35), badge.rarity.color.opacity(0)],
                            center: .center,
                            startRadius: 15,
                            endRadius: 35
                        )
                    )
                    .frame(width: 70, height: 70)
                
                // Medal base
                Circle()
                    .fill(
                        LinearGradient(
                            colors: medalGradientColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 52, height: 52)
                    .overlay(
                        Circle()
                            .stroke(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.5), badge.rarity.color.opacity(0.3)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 2
                            )
                    )
                    .shadow(color: badge.rarity.color.opacity(0.4), radius: 8, x: 0, y: 4)
                
                // Inner ring
                Circle()
                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    .frame(width: 40, height: 40)

                // Icon
                Image(systemName: badgeIcon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.white, .white.opacity(0.85)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .shadow(color: .black.opacity(0.25), radius: 1, x: 0, y: 1)
                
                // Shimmer
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.clear, .white.opacity(0.25), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: 52, height: 52)
                    .offset(x: (shimmerPhase - 0.25) * 100)
                    .clipShape(Circle())
                
                // Rarity indicator dot
                Circle()
                    .fill(badge.rarity.color)
                    .frame(width: 8, height: 8)
                    .overlay(Circle().stroke(Color.white.opacity(0.5), lineWidth: 1))
                    .offset(y: 30)
            }

            // Badge name
            Text(badge.name)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }
    
    private var badgeIcon: String {
        if badge.id.starts(with: "streak_") || badge.id.starts(with: "consistency_") {
            return "flame.fill"
        } else if badge.id.starts(with: "miles_") {
            return "figure.run"
        } else if badge.id.starts(with: "pace_") {
            return "bolt.fill"
        } else if badge.id.starts(with: "daily_") {
            return "figure.run.circle.fill"
        } else if badge.id.starts(with: "challenge_") {
            return "star.circle.fill"
        } else if badge.id.starts(with: "special_") {
            return "sparkles"
        } else {
            return "star.fill"
        }
    }
    
    private var medalGradientColors: [Color] {
        switch badge.rarity {
        case .legendary:
            return [
                Color(red: 1.0, green: 0.85, blue: 0.4),
                Color(red: 0.85, green: 0.55, blue: 0.15)
            ]
        case .rare:
            return [
                Color(red: 0.7, green: 0.5, blue: 0.9),
                Color(red: 0.5, green: 0.3, blue: 0.75)
            ]
        case .common:
            return [
                Color(red: 0.45, green: 0.65, blue: 0.95),
                Color(red: 0.3, green: 0.5, blue: 0.8)
            ]
        }
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
    @State private var challengeProgressValue: Double = 0
    @State private var isCompleted: Bool = false
    @State private var challengesCompletedCount: Int = ChallengeService.shared.allCompletions().count

    private var challengeProgress: Double? {
        todaysChallenge == nil ? nil : challengeProgressValue
    }

    var body: some View {
        Group {
            if let challenge = todaysChallenge {
                challengeCard(challenge)
            } else {
                EmptyView()
            }
        }
        .task {
            guard let userId = userManager.currentUser.backendUserId else { return }
            await ChallengeService.refresh(userId: userId)
            refreshFromService()
        }
        .onReceive(NotificationCenter.default.publisher(for: ChallengeService.changedNotification)) { _ in
            refreshFromService()
        }
    }

    @ViewBuilder
    private func challengeCard(_ challenge: DailyChallenge) -> some View {
        HStack(spacing: 14) {
            // Challenge icon
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: isCompleted ? [.green, .green.opacity(0.8)] : challenge.gradient,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 40, height: 40)

                Image(systemName: isCompleted ? "checkmark" : challenge.icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
            }

                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text("Daily Challenge")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundColor(isCompleted ? .green : (challenge.gradient.first ?? .orange))
                            .textCase(.uppercase)
                            .tracking(0.8)

                        Spacer()

                        if isCompleted {
                            HStack(spacing: 3) {
                                Image(systemName: "star.fill")
                                    .font(.system(size: 9))
                                    .foregroundColor(.yellow)
                                Text("\(challengesCompletedCount)")
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .foregroundColor(.yellow)
                            }
                        }
                    }

                    Text(isCompleted ? "\(challenge.title) — Complete!" : challenge.title)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)

                    Text(challenge.description)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(.secondary)
                        .lineLimit(2)

                    if let progress = challengeProgress {
                        // Progress bar
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.white.opacity(0.1))
                                    .frame(height: 4)

                                RoundedRectangle(cornerRadius: 3)
                                    .fill(
                                        LinearGradient(
                                            colors: isCompleted ? [.green, .green] : challenge.gradient,
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .frame(width: progress * geo.size.width, height: 4)
                                    .animation(.easeOut(duration: 0.5), value: progress)
                            }
                        }
                        .frame(height: 4)
                        .padding(.top, 4)
                    }
                }
            }
            .padding(14)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(.ultraThinMaterial)

                    RoundedRectangle(cornerRadius: 14)
                        .fill((isCompleted ? Color.green : (challenge.gradient.first ?? .orange)).opacity(0.05))

                    RoundedRectangle(cornerRadius: 14)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    (isCompleted ? Color.green : (challenge.gradient.first ?? .orange)).opacity(0.2),
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

    /// Read the server-backed state from `ChallengeService.shared` (a `RemoteChallengeService`).
    /// Server is authoritative for completion + challenge_* badges.
    private func refreshFromService() {
        if let remote = ChallengeService.shared as? RemoteChallengeService {
            todaysChallenge = remote.todayChallenge
            challengeProgressValue = remote.todayProgress
            isCompleted = remote.todayCompleted
        }
        challengesCompletedCount = ChallengeService.shared.allCompletions().count
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
        case pace, distance, time, activity, steps
    }
}

// MARK: - Friend Activity Strip

struct FriendActivityStripView: View {
    @ObservedObject var friendService: FriendService
    @State private var activityData: [FriendActivityItem] = []
    @State private var isLoading = true
    @State private var lastFetchDate: Date?

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
                                friendActivityAvatar(friend)
                            }
                        }
                    }
                }
                .padding(14)
                .liquidGlassCard()
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

struct ActiveCompetitionBannerCard: View {
    let competition: Competition
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

    private var typeGradientColors: [Color] {
        let hexStrings = competition.type.gradient
        return hexStrings.map { Color(hex: $0) }
    }

    var body: some View {
        Button {
            showDetail = true
        } label: {
            HStack(spacing: 14) {
                // Competition type icon
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: typeGradientColors,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 44, height: 44)

                    Image(systemName: competition.type.icon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white)
                }

                // Competition info
                VStack(alignment: .leading, spacing: 4) {
                    Text(competition.competition_name)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        // Type pill
                        Text(competition.type.displayName)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundColor(typeGradientColors.first ?? .green)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill((typeGradientColors.first ?? .green).opacity(0.15))
                            )

                        // Participants
                        HStack(spacing: 3) {
                            Image(systemName: "person.2.fill")
                                .font(.system(size: 10))
                            Text("\(competition.acceptedUsersCount)")
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                        }
                        .foregroundColor(.secondary)
                    }
                }

                Spacer()

                // Rank badge
                if let rank = currentUserRank {
                    VStack(spacing: 2) {
                        Text(rankOrdinal(rank))
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundColor(rankColor(rank))

                        Text("of \(rankedUsers.count)")
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundColor(.secondary)
                    }
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            .padding(16)
            .liquidGlassCard()
        }
        .buttonStyle(PlainButtonStyle())
        .sheet(isPresented: $showDetail) {
            NavigationStack {
                CompetitionDetailView(competition: competition, competitionService: competitionService)
            }
        }
    }

    private func rankOrdinal(_ rank: Int) -> String {
        let suffix: String
        switch rank {
        case 1: suffix = "st"
        case 2: suffix = "nd"
        case 3: suffix = "rd"
        default: suffix = "th"
        }
        return "\(rank)\(suffix)"
    }

    private func rankColor(_ rank: Int) -> Color {
        switch rank {
        case 1: return .yellow
        case 2: return Color(white: 0.75)
        case 3: return .brown
        default: return .secondary
        }
    }
}

// MARK: - Dashboard Collapsible Section

struct DashboardCollapsibleSection<Content: View>: View {
    let title: String
    let icon: String
    @Binding var isCollapsed: Bool
    @ViewBuilder let content: () -> Content
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            // Header button
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    isCollapsed.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.secondary)

                    Text(title)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(.primary)

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                        .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                }
                .padding(.vertical, 14)
                .padding(.horizontal, 16)
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

            // Content
            if !isCollapsed {
                content()
                    .padding(.top, 8)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
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