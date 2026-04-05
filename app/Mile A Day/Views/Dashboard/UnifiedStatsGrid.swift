import SwiftUI
import HealthKit

// MARK: - Supporting Components

// Unified Stats Grid Component
struct UnifiedStatsGrid: View {
    let user: User
    @ObservedObject var healthManager: HealthKitManager
    @EnvironmentObject var userManager: UserManager
    let statsType: StatsViewType
    @State private var statsData: (totalMiles: Double, mostMiles: Double, fastestPace: TimeInterval, streakDays: Int) = (0.0, 0.0, 0.0, 0)
    @State private var hasLoadedOnce = false
    @State private var isCalculating = false
    @State private var showFastestPaceDetail = false
    @State private var showMostMilesDetail = false
    @State private var showTotalMilesDetail = false
    @State private var showGoalSheet = false
    @State private var isRefreshingFastestPace = false

    enum StatsViewType: String, CaseIterable {
        case allTime = "All Time"
        case currentStreak = "Current Streak"
    }

    /// HealthKit pace (from actual split times) is authoritative; backend is fallback only
    var bestAllTimeFastestPace: TimeInterval {
        let hkPace = healthManager.fastestMilePace
        if hkPace > 0 { return hkPace }
        return user.fastestMilePace
    }

    var isFastestPaceLoading: Bool {
        if statsType == .allTime {
            return isRefreshingFastestPace && bestAllTimeFastestPace <= 0
        } else {
            return isCalculating && statsData.fastestPace <= 0
        }
    }

    var formattedFastestPace: String {
        if statsType == .allTime {
            let pace = bestAllTimeFastestPace
            if pace > 0 {
                let minutes = Int(pace)
                let seconds = Int((pace - Double(minutes)) * 60)
                return String(format: "%d:%02d /mi", minutes, seconds)
            }
        } else {
            if statsData.fastestPace > 0 {
                let totalMinutes = statsData.fastestPace
                let minutes = Int(totalMinutes)
                let seconds = Int((totalMinutes - Double(minutes)) * 60)
                return String(format: "%d:%02d /mi", minutes, seconds)
            }
        }
        return "Not yet recorded"
    }

    var headerIcon: String {
        statsType == .allTime ? "trophy.fill" : "flame.fill"
    }

    var headerTitle: String {
        statsType == .allTime ? "All Time Stats" : "Current Streak Stats"
    }

    var badgeValue: String {
        if statsType == .allTime {
            return "All Time"
        } else {
            return "\(statsData.streakDays) days"
        }
    }

    var badgeColor: Color {
        statsType == .allTime ? .blue : .orange
    }

    var totalMiles: Double {
        statsType == .allTime ? user.totalMiles : statsData.totalMiles
    }

    var mostMiles: Double {
        if statsType == .allTime {
            // Use pre-computed cached value instead of recalculating on every render
            if healthManager.cachedMostMilesInOneDay > 0 {
                return healthManager.cachedMostMilesInOneDay
            } else if healthManager.mostMilesInOneDay > 0 {
                return healthManager.mostMilesInOneDay
            } else {
                return user.mostMilesInOneDay
            }
        } else {
            return statsData.mostMiles
        }
    }

    var streakDays: Int {
        statsType == .allTime ? user.streak : statsData.streakDays
    }

    var avgMilesPerDay: Double {
        if streakDays > 0 {
            return totalMiles / Double(streakDays)
        }
        return 0.0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            // Header with icon and badge
            HStack {
                Image(systemName: headerIcon)
                    .foregroundColor(badgeColor)
                    .font(.title2)

                Text(headerTitle)
                    .font(.headline)
                    .fontWeight(.semibold)

                Spacer()

                // Badge
                Text(badgeValue)
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(badgeColor)
                    )
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 15) {
                // Total Miles Card
                Button {
                    showTotalMilesDetail = true
                } label: {
                    statsCard(
                        icon: "map.fill",
                        iconColor: .blue,
                        title: statsType == .allTime ? "Total Miles" : "Streak Miles",
                        isLoading: isCalculating && statsType == .currentStreak && !hasLoadedOnce,
                        value: String(format: "%.1f mi", totalMiles),
                        subtitle: streakDays > 0 && statsType == .currentStreak
                            ? String(format: "%.1f avg/day", avgMilesPerDay)
                            : (statsType == .allTime ? "All time" : " "),
                        subtitleColor: .blue
                    )
                }
                .buttonStyle(PlainButtonStyle())

                // Fastest Mile Card
                Button {
                    showFastestPaceDetail = true
                } label: {
                    statsCard(
                        icon: "hare.fill",
                        iconColor: .green,
                        title: "Fastest Mile",
                        isLoading: isFastestPaceLoading,
                        value: formattedFastestPace,
                        subtitle: (isCalculating || isRefreshingFastestPace) ? nil : (statsType == .allTime ? "All time" : "Current streak"),
                        subtitleColor: .green,
                        showSubtitleLoader: isCalculating || isRefreshingFastestPace
                    )
                }
                .buttonStyle(PlainButtonStyle())

                // Most Miles Card
                Button {
                    showMostMilesDetail = true
                } label: {
                    statsCard(
                        icon: "calendar.badge.clock",
                        iconColor: .purple,
                        title: "Most in One Day",
                        isLoading: isCalculating && statsType == .currentStreak && !hasLoadedOnce,
                        value: String(format: "%.1f mi", mostMiles),
                        subtitle: statsType == .allTime ? "All time" : "Current streak",
                        subtitleColor: .purple
                    )
                }
                .buttonStyle(PlainButtonStyle())

                // Daily Goal / Streak Days Card
                if statsType == .allTime {
                    Button {
                        showGoalSheet = true
                    } label: {
                        statsCard(
                            icon: "target",
                            iconColor: .gray,
                            title: "Daily Goal",
                            isLoading: false,
                            value: user.goalMiles.milesFormatted,
                            subtitle: "Tap to edit",
                            subtitleColor: .gray
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                } else {
                    statsCard(
                        icon: "flame.fill",
                        iconColor: .orange,
                        title: "Streak Days",
                        isLoading: isCalculating && !hasLoadedOnce,
                        value: "\(streakDays)",
                        subtitle: streakDays > 0 ? "Current streak" : nil,
                        subtitleColor: .orange
                    )

                    // Total Miles (lifetime) card in current streak view
                    statsCard(
                        icon: "map.fill",
                        iconColor: .red,
                        title: "Total Miles",
                        isLoading: false,
                        value: String(format: "%.1f mi", user.totalMiles),
                        subtitle: "Lifetime",
                        subtitleColor: .red
                    )

                    // Average per day card
                    statsCard(
                        icon: "chart.line.uptrend.xyaxis",
                        iconColor: .cyan,
                        title: "Avg Per Day",
                        isLoading: isCalculating && !hasLoadedOnce,
                        value: String(format: "%.2f mi", avgMilesPerDay),
                        subtitle: "Current streak",
                        subtitleColor: .cyan
                    )
                }
            }
        }
        .onAppear {
            if statsType == .currentStreak {
                calculateCurrentStreakStats()
            }
        }
        .onChange(of: healthManager.retroactiveStreak) { _, _ in
            if statsType == .currentStreak {
                calculateCurrentStreakStats()
            }
        }
        .onChange(of: statsType) { _, newType in
            if newType == .currentStreak {
                calculateCurrentStreakStats()
            }
        }
        .sheet(isPresented: $showTotalMilesDetail) {
            TotalMilesDetailView(userManager: userManager, healthManager: healthManager)
        }
        .sheet(isPresented: $showFastestPaceDetail) {
            if statsType == .allTime {
                FastestPaceDetailView(healthManager: healthManager, userManager: userManager)
            } else {
                CurrentStreakFastestPaceDetailView(healthManager: healthManager, currentStreakStats: statsData)
            }
        }
        .sheet(isPresented: $showMostMilesDetail) {
            if statsType == .allTime {
                MostMilesDetailView(miles: mostMiles, healthManager: healthManager)
            } else {
                CurrentStreakMostMilesDetailView(mostMiles: mostMiles, healthManager: healthManager, currentStreakStats: statsData)
            }
        }
        .sheet(isPresented: $showGoalSheet) {
            GoalSettingSheet(
                currentGoal: user.goalMiles,
                onSave: { newGoal in
                    // Note: This will need to be handled by the parent view
                    // since we don't have access to userManager here
                }
            )
            .presentationDetents([.height(300)])
        }
    }

    // MARK: - Reusable Stats Card

    private func statsCard(
        icon: String,
        iconColor: Color,
        title: String,
        isLoading: Bool,
        value: String,
        subtitle: String?,
        subtitleColor: Color,
        showSubtitleLoader: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(iconColor)
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if isLoading {
                ProgressView()
                    .frame(height: 28)
            } else {
                Text(value)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.leading)
            }

            if showSubtitleLoader {
                ProgressView()
                    .scaleEffect(0.6)
                    .frame(height: 14)
            } else if let subtitle = subtitle {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundColor(subtitleColor)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 100)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(iconColor.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(iconColor.opacity(0.3), lineWidth: 1)
                )
        )
    }

    private func calculateCurrentStreakStats() {
        // Show cached data immediately to avoid content shift
        let cached = healthManager.cachedCurrentStreakStats
        if cached.streakDays > 0 && !hasLoadedOnce {
            statsData = cached
        }

        isCalculating = !hasLoadedOnce

        DispatchQueue.global(qos: .userInitiated).async {
            let stats = healthManager.calculateCurrentStreakStats()

            DispatchQueue.main.async {
                self.statsData = stats
                self.isCalculating = false
                self.hasLoadedOnce = true
            }
        }
    }
}
