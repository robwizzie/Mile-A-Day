import SwiftUI

struct TrophyCaseView: View {
    @ObservedObject var trophyService: TrophyService
    @ObservedObject var competitionService: CompetitionService
    @Environment(\.dismiss) private var dismiss
    @State private var animateIn = false
    @State private var selectedCompetition: Competition?
    @State private var isLoadingCompetition = false

    private static let isoDateFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        return f
    }()

    private static let displayDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy"
        return f
    }()

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
        .sheet(item: $selectedCompetition) { competition in
            NavigationStack {
                CompetitionDetailView(competition: competition, competitionService: competitionService)
            }
        }
        .overlay {
            if isLoadingCompetition {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .overlay(ProgressView().tint(.white))
            }
        }
    }

    // MARK: - Load Competition
    private func loadCompetition(_ id: String) {
        isLoadingCompetition = true
        Task {
            do {
                let competition = try await competitionService.loadCompetition(id: id)
                selectedCompetition = competition
            } catch {
                print("[TrophyCaseView] Failed to load competition: \(error)")
            }
            isLoadingCompetition = false
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
                Button {
                    loadCompetition(trophy.id)
                } label: {
                    trophyRow(trophy)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func trophyRow(_ trophy: CompetitionTrophy) -> some View {
        let medalColors: [Color] = trophy.medal?.gradient ?? [Color.white.opacity(0.4), Color.white.opacity(0.2)]
        let accentColor = trophy.medal?.color ?? Color.white.opacity(0.4)

        return HStack(spacing: MADTheme.Spacing.md) {
            // Placement badge
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: medalColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 48, height: 48)
                    .shadow(color: accentColor.opacity(0.4), radius: 6, y: 2)

                if trophy.medal != nil {
                    Image(systemName: "medal.fill")
                        .font(.system(size: 22))
                        .foregroundColor(.white)
                } else {
                    Text("#\(trophy.placement)")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }
            }

            // Info
            VStack(alignment: .leading, spacing: 5) {
                Text(trophy.competitionName)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    // Type pill
                    HStack(spacing: 4) {
                        Image(systemName: trophy.competitionType.icon)
                            .font(.system(size: 9))
                        Text(trophy.competitionType.displayName)
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(Color(hex: trophy.competitionType.gradient[0]))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(Color(hex: trophy.competitionType.gradient[0]).opacity(0.15))
                    )

                    Text(formattedDate(trophy.completedDate))
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.4))
                }

                // Placement text
                Text(placementText(trophy))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(accentColor)
            }

            Spacer()

            // Score + chevron
            HStack(spacing: MADTheme.Spacing.sm) {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(formatScore(trophy))
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(.white)

                    Text(scoreUnitLabel(trophy))
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.4))
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.3))
            }
        }
        .padding(MADTheme.Spacing.md)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                        .stroke(
                            LinearGradient(
                                colors: [accentColor.opacity(0.2), Color.clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        )
    }

    // MARK: - Helpers
    private func formattedDate(_ dateString: String) -> String {
        guard let date = Self.isoDateFormatter.date(from: dateString) else { return dateString }
        return Self.displayDateFormatter.string(from: date)
    }

    private func formatScore(_ trophy: CompetitionTrophy) -> String {
        switch trophy.competitionType {
        case .clash, .targets:
            // Score is a win/target count (integer points)
            return String(format: "%.0f", trophy.score)
        case .streaks:
            // Score is streak length in intervals (integer)
            return String(format: "%.0f", trophy.score)
        case .apex, .race:
            // Score is actual distance
            if trophy.unit == .steps {
                return String(format: "%.0f", trophy.score)
            }
            return String(format: "%.1f", trophy.score)
        }
    }

    private func placementText(_ trophy: CompetitionTrophy) -> String {
        let ordinal: String
        switch trophy.placement {
        case 1: ordinal = "1st"
        case 2: ordinal = "2nd"
        case 3: ordinal = "3rd"
        default: ordinal = "\(trophy.placement)th"
        }
        return "\(ordinal) of \(trophy.totalParticipants) competitors"
    }

    private func scoreUnitLabel(_ trophy: CompetitionTrophy) -> String {
        switch trophy.competitionType {
        case .clash:
            return trophy.score == 1 ? "win" : "wins"
        case .targets:
            return trophy.score == 1 ? "day" : "days"
        case .streaks:
            return trophy.score == 1 ? "day" : "days"
        case .apex, .race:
            return trophy.unit.shortDisplayName
        }
    }
}

#Preview {
    NavigationStack {
        TrophyCaseView(trophyService: TrophyService.shared, competitionService: CompetitionService())
    }
}
