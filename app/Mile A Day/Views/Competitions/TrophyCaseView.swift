import SwiftUI

struct TrophyCaseView: View {
    @ObservedObject var trophyService: TrophyService
    @Environment(\.dismiss) private var dismiss
    @State private var animateIn = false

    var body: some View {
        ScrollView {
            VStack(spacing: MADTheme.Spacing.xl) {
                // Stats header
                statsHeader

                // Medal summary
                medalSummary

                // Trophy list
                if trophyService.trophies.isEmpty {
                    emptyState
                } else {
                    trophyList
                }
            }
            .padding(.horizontal, MADTheme.Spacing.md)
            .padding(.vertical, MADTheme.Spacing.lg)
        }
        .background(MADTheme.Colors.appBackgroundGradient)
        .navigationTitle("Trophy Case")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }
                    .foregroundColor(MADTheme.Colors.madRed)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                animateIn = true
            }
        }
    }

    // MARK: - Stats Header
    private var statsHeader: some View {
        VStack(spacing: MADTheme.Spacing.md) {
            // Big trophy icon
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                MADTheme.Colors.madRed.opacity(0.3),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 20,
                            endRadius: 60
                        )
                    )
                    .frame(width: 120, height: 120)

                Image(systemName: "trophy.fill")
                    .font(.system(size: 50))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.yellow, .orange],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .scaleEffect(animateIn ? 1.0 : 0.5)
                    .opacity(animateIn ? 1.0 : 0.0)
            }

            Text("\(trophyService.totalCompetitions)")
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundColor(.white)

            Text(trophyService.totalCompetitions == 1 ? "Competition Completed" : "Competitions Completed")
                .font(MADTheme.Typography.callout)
                .foregroundColor(.white.opacity(0.6))
        }
        .padding(.top, MADTheme.Spacing.md)
    }

    // MARK: - Medal Summary
    private var medalSummary: some View {
        HStack(spacing: MADTheme.Spacing.md) {
            medalCard(
                medal: .gold,
                count: trophyService.goldCount,
                delay: 0.1
            )
            medalCard(
                medal: .silver,
                count: trophyService.silverCount,
                delay: 0.2
            )
            medalCard(
                medal: .bronze,
                count: trophyService.bronzeCount,
                delay: 0.3
            )
        }
    }

    private func medalCard(medal: TrophyMedal, count: Int, delay: Double) -> some View {
        VStack(spacing: MADTheme.Spacing.sm) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: medal.gradient,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 52, height: 52)
                    .shadow(color: medal.color.opacity(0.4), radius: 8, y: 4)

                Image(systemName: "medal.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.white)
            }
            .scaleEffect(animateIn ? 1.0 : 0.3)
            .opacity(animateIn ? 1.0 : 0.0)
            .animation(.spring(response: 0.5, dampingFraction: 0.7).delay(delay), value: animateIn)

            Text("\(count)")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(.white)

            Text(medal.displayName)
                .font(MADTheme.Typography.caption)
                .foregroundColor(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, MADTheme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                .fill(.ultraThinMaterial)
        )
    }

    // MARK: - Win Rate
    private var winRateSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Win Rate")
                    .font(MADTheme.Typography.caption)
                    .foregroundColor(.white.opacity(0.5))
                Text(String(format: "%.0f%%", trophyService.winRate))
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }

            Spacer()

            // Win rate bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.white.opacity(0.1))

                    RoundedRectangle(cornerRadius: 6)
                        .fill(
                            LinearGradient(
                                colors: [.yellow, .orange],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: animateIn ? geo.size.width * CGFloat(trophyService.winRate / 100.0) : 0)
                }
            }
            .frame(width: 120, height: 12)
        }
        .padding(MADTheme.Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                .fill(.ultraThinMaterial)
        )
    }

    // MARK: - Empty State
    private var emptyState: some View {
        VStack(spacing: MADTheme.Spacing.lg) {
            Image(systemName: "trophy")
                .font(.system(size: 60))
                .foregroundColor(.white.opacity(0.2))

            Text("No Trophies Yet")
                .font(MADTheme.Typography.title3)
                .foregroundColor(.white.opacity(0.6))

            Text("Complete competitions to earn trophies and medals!")
                .font(MADTheme.Typography.body)
                .foregroundColor(.white.opacity(0.4))
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, MADTheme.Spacing.xxl)
    }

    // MARK: - Trophy List
    private var trophyList: some View {
        VStack(spacing: MADTheme.Spacing.sm) {
            if trophyService.totalCompetitions > 0 {
                winRateSection
                    .padding(.bottom, MADTheme.Spacing.sm)
            }

            HStack {
                Text("History")
                    .font(MADTheme.Typography.headline)
                    .foregroundColor(.white.opacity(0.85))
                Spacer()
            }

            ForEach(trophyService.trophies.sorted(by: { $0.completedDate > $1.completedDate })) { trophy in
                trophyRow(trophy)
            }
        }
    }

    private func trophyRow(_ trophy: CompetitionTrophy) -> some View {
        HStack(spacing: MADTheme.Spacing.md) {
            // Medal or placement
            if let medal = trophy.medal {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: medal.gradient,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 44, height: 44)

                    Image(systemName: "medal.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.white)
                }
            } else {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.1))
                        .frame(width: 44, height: 44)

                    Text("#\(trophy.placement)")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(.white.opacity(0.6))
                }
            }

            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(trophy.competitionName)
                    .font(MADTheme.Typography.callout)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .lineLimit(1)

                HStack(spacing: MADTheme.Spacing.sm) {
                    Image(systemName: trophy.competitionType.icon)
                        .font(.system(size: 10))
                        .foregroundColor(Color(hex: trophy.competitionType.gradient[0]))

                    Text(trophy.competitionType.displayName)
                        .font(MADTheme.Typography.caption)
                        .foregroundColor(.white.opacity(0.5))

                    Text("·")
                        .foregroundColor(.white.opacity(0.3))

                    Text(formattedDate(trophy.completedDate))
                        .font(MADTheme.Typography.caption)
                        .foregroundColor(.white.opacity(0.4))
                }
            }

            Spacer()

            // Score
            VStack(alignment: .trailing, spacing: 2) {
                Text(formatScore(trophy.score, unit: trophy.unit))
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                Text(trophy.unit.shortDisplayName)
                    .font(MADTheme.Typography.caption)
                    .foregroundColor(.white.opacity(0.4))
            }
        }
        .padding(MADTheme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                .fill(.ultraThinMaterial)
        )
    }

    // MARK: - Helpers
    private func formattedDate(_ dateString: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        guard let date = formatter.date(from: dateString) else { return dateString }
        let display = DateFormatter()
        display.dateFormat = "MMM d, yyyy"
        return display.string(from: date)
    }

    private func formatScore(_ score: Double, unit: CompetitionUnit) -> String {
        if unit == .steps {
            return String(format: "%.0f", score)
        }
        return String(format: "%.1f", score)
    }
}

#Preview {
    NavigationStack {
        TrophyCaseView(trophyService: TrophyService.shared)
    }
}
