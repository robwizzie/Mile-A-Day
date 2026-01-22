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

    private var dayLetter: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "E"
        let day = formatter.string(from: date)
        return String(day.prefix(1))
    }

    private var dayNumber: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter.string(from: date)
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
    @Environment(\.colorScheme) var colorScheme
    @State private var shimmerPhase: CGFloat = -1

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

    var body: some View {
        NavigationLink(destination: BadgesView(userManager: userManager)) {
            VStack(alignment: .leading, spacing: 16) {
                // Header with progress
                HStack(spacing: 12) {
                    // Trophy with glow
                    ZStack {
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [Color.orange.opacity(0.3), Color.clear],
                                    center: .center,
                                    startRadius: 5,
                                    endRadius: 25
                                )
                            )
                            .frame(width: 50, height: 50)
                        
                        Image(systemName: "trophy.fill")
                            .font(.title2)
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.yellow, .orange],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Medals")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)

                        // Progress bar
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.white.opacity(0.1))
                                    .frame(height: 6)
                                
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(
                                        LinearGradient(
                                            colors: [.orange, .yellow],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .frame(width: geo.size.width * progress, height: 6)
                            }
                        }
                        .frame(height: 6)
                        
                        Text("\(earnedCount) of \(totalCount) unlocked")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                }

                if recentBadges.isEmpty {
                    // Empty state
                    HStack {
                        Spacer()
                        VStack(spacing: 8) {
                            Image(systemName: "trophy")
                                .font(.system(size: 32))
                                .foregroundColor(.secondary.opacity(0.4))

                            Text("Start running to earn badges!")
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 12)
                        Spacer()
                    }
                } else {
                    // Recent badges with modern styling
                    HStack(spacing: 8) {
                        ForEach(recentBadges, id: \.id) { badge in
                            HomeBadgeItem(badge: badge, shimmerPhase: shimmerPhase)
                        }
                    }
                }
            }
            .padding()
            .frame(minHeight: 180)
            .background(
                ZStack {
                    // Liquid glass background
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.ultraThinMaterial)

                    // Gradient overlay
                    LinearGradient(
                        colors: [
                            Color.orange.opacity(0.08),
                            Color.yellow.opacity(0.03),
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
        .onAppear {
            withAnimation(.linear(duration: 2.5).repeatForever(autoreverses: false)) {
                shimmerPhase = 1.5
            }
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
                
                // Secret indicator
                if badge.isHidden {
                    Image(systemName: "eye.slash.fill")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.white)
                        .padding(5)
                        .background(
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [Color.purple, Color.purple.opacity(0.8)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        )
                        .overlay(Circle().stroke(Color.white.opacity(0.3), lineWidth: 1))
                        .offset(x: 20, y: -20)
                }
                
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
        } else if badge.id.starts(with: "hidden_") || badge.id.starts(with: "secret_") || badge.id.starts(with: "special_") {
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
    @Environment(\.colorScheme) var colorScheme

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
            VStack(alignment: .leading, spacing: 16) {
                // Header
                HStack {
                    Image(systemName: "shoeprints.fill")
                        .font(.title2)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.blue, .cyan],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Steps")
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // Steps display
                HStack(alignment: .bottom, spacing: 6) {
                    Text("\(todaysSteps)")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                }

                // Progress bar
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Goal: 10,000 steps")
                            .font(.caption2)
                            .foregroundColor(.secondary)

                        Spacer()

                        Text("\(Int(stepProgress * 100))%")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                    }

                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.gray.opacity(0.2))
                                .frame(height: 4)

                            RoundedRectangle(cornerRadius: 2)
                                .fill(stepColor)
                                .frame(width: stepProgress * geometry.size.width, height: 4)
                        }
                    }
                    .frame(height: 4)
                }
            }
            .padding()
            .frame(minHeight: 180)
            .background(
                ZStack {
                    // Liquid glass background
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.ultraThinMaterial)

                    // Gradient overlay
                    LinearGradient(
                        colors: [
                            Color.blue.opacity(0.05),
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