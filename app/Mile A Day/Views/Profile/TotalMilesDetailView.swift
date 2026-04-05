import SwiftUI

struct TotalMilesDetailView: View {
    @ObservedObject var userManager: UserManager
    @ObservedObject var healthManager: HealthKitManager
    @Environment(\.dismiss) private var dismiss

    private var totalMiles: Double {
        userManager.currentUser.totalMiles
    }

    private var streak: Int {
        userManager.currentUser.streak
    }

    private var avgPerDay: Double {
        guard streak > 0 else { return 0 }
        return totalMiles / Double(streak)
    }

    /// Miles badges from the user's badge list, sorted by mile threshold
    private var milesBadges: [Badge] {
        userManager.currentUser.getAllBadges()
            .filter { $0.id.starts(with: "miles_") }
            .sorted { $0.numericValue < $1.numericValue }
    }

    /// The next locked miles badge (target to work toward)
    private var nextBadge: Badge? {
        milesBadges.first { $0.isLocked }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                MADTheme.Colors.appBackgroundGradient
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: MADTheme.Spacing.lg) {
                        heroCard
                        keyStatsRow
                        nextBadgeProgress
                        medalsSection
                        funFactsSection
                    }
                    .padding(MADTheme.Spacing.md)
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(MADTheme.Colors.madRed)
                    .fontWeight(.semibold)
                }
            }
        }
    }

    // MARK: - Hero Card

    private var heroCard: some View {
        VStack(spacing: MADTheme.Spacing.md) {
            HStack(spacing: MADTheme.Spacing.sm) {
                Image(systemName: "map.fill")
                    .font(.system(size: 14, weight: .semibold))
                Text("Lifetime")
                    .font(MADTheme.Typography.smallBold)
            }
            .foregroundColor(MADTheme.Colors.madRed)
            .padding(.horizontal, MADTheme.Spacing.md)
            .padding(.vertical, MADTheme.Spacing.xs + 2)
            .background(
                Capsule()
                    .fill(MADTheme.Colors.madRed.opacity(0.15))
            )

            Text(totalMiles.milesFormatted)
                .font(.system(size: 52, weight: .bold, design: .rounded))
                .foregroundColor(.primary)

            Text("Total Miles Covered")
                .font(MADTheme.Typography.body)
                .foregroundColor(.secondary)
        }
        .padding(MADTheme.Spacing.lg)
        .frame(maxWidth: .infinity)
        .madLiquidGlass()
    }

    // MARK: - Key Stats Row

    private var keyStatsRow: some View {
        HStack(spacing: MADTheme.Spacing.sm) {
            DashboardStatBox(
                title: "Days Active",
                value: "\(streak)",
                icon: "flame.fill",
                color: .orange
            )
            DashboardStatBox(
                title: "Avg/Day",
                value: String(format: "%.1f mi", avgPerDay),
                icon: "chart.bar.fill",
                color: MADTheme.Colors.madRed
            )
            DashboardStatBox(
                title: "Est. Calories",
                value: formatLargeNumber(totalMiles * 100),
                icon: "flame.fill",
                color: .orange
            )
        }
    }

    // MARK: - Next Badge Progress

    @ViewBuilder
    private var nextBadgeProgress: some View {
        if let badge = nextBadge {
            let target = Double(badge.numericValue)
            let remaining = target - totalMiles
            let progress = target > 0 ? totalMiles / target : 0

            VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
                HStack(spacing: MADTheme.Spacing.sm) {
                    Image(systemName: "flag.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(MADTheme.Colors.redGradient)
                    Text("Next Medal")
                        .font(MADTheme.Typography.headline)
                        .foregroundColor(.primary)
                }

                HStack(spacing: MADTheme.Spacing.md) {
                    // Mini locked medal
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color(white: 0.25), Color(white: 0.15)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 44, height: 44)
                            .overlay(
                                Circle().stroke(Color.white.opacity(0.08), lineWidth: 1)
                            )

                        Image(systemName: "figure.run")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.white.opacity(0.25))
                    }

                    VStack(alignment: .leading, spacing: MADTheme.Spacing.sm) {
                        Text(badge.name)
                            .font(MADTheme.Typography.body)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)

                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.white.opacity(0.1))
                                    .frame(height: 6)

                                RoundedRectangle(cornerRadius: 4)
                                    .fill(MADTheme.Colors.redGradient)
                                    .frame(width: geo.size.width * min(progress, 1.0), height: 6)
                            }
                        }
                        .frame(height: 6)

                        Text(String(format: "%.1f mi to go", remaining))
                            .font(MADTheme.Typography.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(MADTheme.Spacing.md)
            .madLiquidGlass()
        }
    }

    // MARK: - Medals Section

    private var medalsSection: some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
            HStack(spacing: MADTheme.Spacing.sm) {
                Image(systemName: "medal.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(MADTheme.Colors.redGradient)
                Text("Mile Medals")
                    .font(MADTheme.Typography.headline)
                    .foregroundColor(.primary)

                Spacer()

                let earned = milesBadges.filter { !$0.isLocked }.count
                Text("\(earned)/\(milesBadges.count)")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(.secondary)
            }

            ForEach(Array(milesBadges.enumerated()), id: \.element.id) { index, badge in
                BadgeRowCard(badge: badge, userManager: userManager)

                if index < milesBadges.count - 1 {
                    Divider().overlay(Color.white.opacity(0.06))
                }
            }
        }
        .padding(MADTheme.Spacing.md)
        .madLiquidGlass()
    }

    // MARK: - Fun Facts

    private var funFactsSection: some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
            HStack(spacing: MADTheme.Spacing.sm) {
                Image(systemName: "sparkles")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(MADTheme.Colors.redGradient)
                Text("Your Journey")
                    .font(MADTheme.Typography.headline)
                    .foregroundColor(.primary)
            }

            VStack(spacing: 0) {
                funFactRow(
                    icon: "globe.americas.fill",
                    text: earthCircumferenceComparison
                )

                Divider().overlay(Color.white.opacity(0.06))

                funFactRow(
                    icon: "figure.walk",
                    text: String(format: "~%.0f steps taken", totalMiles * 2000)
                )

                if totalMiles >= 26.2 {
                    Divider().overlay(Color.white.opacity(0.06))

                    funFactRow(
                        icon: "figure.run",
                        text: String(format: "%.1f full marathons", totalMiles / 26.2)
                    )
                }

                Divider().overlay(Color.white.opacity(0.06))

                funFactRow(
                    icon: "mappin.and.ellipse",
                    text: landmarkComparison
                )
            }
        }
        .padding(MADTheme.Spacing.md)
        .madLiquidGlass()
    }

    private func funFactRow(icon: String, text: String) -> some View {
        HStack(spacing: MADTheme.Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(MADTheme.Colors.madRed)
                .frame(width: 24)

            Text(text)
                .font(MADTheme.Typography.body)
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, MADTheme.Spacing.sm)
    }

    // MARK: - Data

    private var earthCircumferenceComparison: String {
        let earthCircumference = 24901.0
        let percentage = (totalMiles / earthCircumference) * 100
        if percentage >= 1 {
            return String(format: "%.1f%% around the Earth", percentage)
        }
        return String(format: "%.2f%% around the Earth", percentage)
    }

    private var landmarkComparison: String {
        let centralParkLoops = totalMiles / 6.1
        if centralParkLoops >= 1 {
            return String(format: "%.0f loops around Central Park", centralParkLoops)
        }
        let goldenGateCrossings = totalMiles / 1.7
        return String(format: "%.0f trips across the Golden Gate Bridge", goldenGateCrossings)
    }

    private func formatLargeNumber(_ value: Double) -> String {
        if value >= 1000 {
            return String(format: "%.1fk", value / 1000)
        }
        return String(format: "%.0f", value)
    }
}

#Preview {
    TotalMilesDetailView(userManager: UserManager(), healthManager: HealthKitManager())
}
