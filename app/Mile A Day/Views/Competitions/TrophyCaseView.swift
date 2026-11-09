import SwiftUI

struct TrophyCaseView: View {
    @ObservedObject var trophyService: TrophyService
    @ObservedObject var competitionService: CompetitionService
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
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
        f.setLocalizedDateFormatFromTemplate("MMMdyyyy")
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

    /// The count, said once, big. Was a 50pt gold trophy inside a 120pt red
    /// radial glow, over the same number — two decorations announcing a figure
    /// that is perfectly able to announce itself, on a screen whose entire
    /// subject is already trophies.
    private var statsHeader: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(trophyService.totalCompetitions)")
                .madFont(size: 46, weight: .heavy, design: .rounded)
                .foregroundColor(CompeteDesign.ink)
                .monospacedDigit()

            Text(trophyService.totalCompetitions == 1 ? "COMPETITION COMPLETED" : "COMPETITIONS COMPLETED")
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .competeFont(CompeteDesign.eyebrow)
                .tracking(CompeteDesign.eyebrowTracking)
                .foregroundColor(CompeteDesign.inkFaint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 2)
    }

    // MARK: - Medal Summary

    /// Gold / silver / bronze as one rail of figures. Three 52pt gradient
    /// discs with coloured drop shadows were the loudest thing on a screen
    /// where the DIFFERENCE between the three numbers is the whole point.
    private var medalSummary: some View {
        CompeteSurface {
            HStack(spacing: 0) {
                medalColumn(.gold, count: trophyService.goldCount)
                railDivider
                medalColumn(.silver, count: trophyService.silverCount)
                railDivider
                medalColumn(.bronze, count: trophyService.bronzeCount)
            }
        }
    }

    private var railDivider: some View {
        Rectangle()
            .fill(CompeteDesign.rowRule)
            .frame(width: 1, height: 30)
            .padding(.horizontal, 10)
            .accessibilityHidden(true)
    }

    private func medalColumn(_ medal: TrophyMedal, count: Int) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Circle()
                    .fill(medal.color)
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)
                Text("\(count)")
                    .madFont(size: 22, weight: .heavy, design: .rounded, maxScale: 1.3)
                    .foregroundColor(CompeteDesign.ink)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            Text(medal.displayName.uppercased())
                .madFont(size: 11, weight: .bold, design: .rounded)
                .tracking(0.8)
                .foregroundColor(CompeteDesign.inkFaint)
                .madNameLines()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(count) \(medal.displayName)")
    }

    // MARK: - Win Rate
    private var winRateSection: some View {
        CompeteSurface {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("WIN RATE")
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .competeFont(CompeteDesign.eyebrow)
                        .tracking(CompeteDesign.eyebrowTracking)
                        .foregroundColor(CompeteDesign.inkFaint)
                    Spacer()
                    Text(ProgressCalculator.formatWholePercent(trophyService.winRate))
                        .madFont(size: 26, weight: .heavy, design: .rounded)
                        .foregroundColor(CompeteDesign.ink)
                        .monospacedDigit()
                        .lineLimit(1)
                        .fixedSize()
                }

                CompeteBar(
                    fraction: animateIn ? trophyService.winRate / 100.0 : 0,
                    color: CompeteDesign.medal(1) ?? .yellow,
                    height: 6
                )
            }
        }
    }

    // MARK: - Empty State
    private var emptyState: some View {
        VStack(spacing: MADTheme.Spacing.lg) {
            Image(systemName: "trophy")
                .madFont(size: 60, maxScale: 1.5)
                .foregroundColor(.white.opacity(0.2))

            Text("No Trophies Yet")
                .madFont(size: 20, weight: .semibold, design: .rounded)
                .foregroundColor(.white.opacity(0.6))

            Text("Complete competitions to earn trophies and medals!")
                .madFont(size: 17, design: .rounded)
                .foregroundColor(.white.opacity(0.6))
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
                    .madFont(size: 17, weight: .semibold, design: .rounded)
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
        let accentColor = trophy.medal?.color ?? CompeteDesign.inkFaint

        return HStack(spacing: 11) {
            // The same rank chip as every board in the app. A 48pt gradient
            // disc with a coloured drop shadow said "medal" a second time on a
            // screen called Trophy Case.
            CompeteRankBadge(place: trophy.placement, size: 30)

            VStack(alignment: .leading, spacing: 3) {
                Text(trophy.competitionName)
                    .competeFont(CompeteDesign.nameSmall)
                    .foregroundColor(CompeteDesign.ink)
                    .madBodyLines(1)
                    .truncationMode(.tail)

                trophyDetails(trophy, accentColor: accentColor)

                if dynamicTypeSize.isAccessibilitySize {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        trophyScore(trophy)
                        trophyScoreUnit(trophy)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if !dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .trailing, spacing: 0) {
                    trophyScore(trophy)
                    trophyScoreUnit(trophy)
                }
                .fixedSize()
            }

            Image(systemName: "chevron.right")
                .madFont(size: 11, weight: .bold, maxScale: 1.5)
                .foregroundColor(CompeteDesign.inkGhost)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: CompeteDesign.radius, style: .continuous)
                .fill(CompeteDesign.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: CompeteDesign.radius, style: .continuous)
                .strokeBorder(CompeteDesign.hairline, lineWidth: 1)
        )
    }

    /// Type, placement and date. One dotted line normally; a line each at
    /// accessibility sizes, where sharing one cuts all three down to "R…".
    @ViewBuilder
    private func trophyDetails(_ trophy: CompetitionTrophy, accentColor: Color) -> some View {
        let type = Text(trophy.competitionType.displayName.uppercased())
            .madFont(size: 11, weight: .heavy, design: .rounded)
            .tracking(0.9)
            .foregroundColor(Color(hex: trophy.competitionType.gradient[0]))
        let placement = Text(placementText(trophy))
            .competeFont(CompeteDesign.caption)
            .foregroundColor(accentColor)
        let date = Text(formattedDate(trophy.completedDate))
            .competeFont(CompeteDesign.caption)
            .foregroundColor(CompeteDesign.inkFaint)

        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 2) {
                type
                placement
                date
            }
        } else {
            HStack(spacing: 5) {
                type
                Text("·").foregroundColor(CompeteDesign.inkGhost)
                placement
                Text("·").foregroundColor(CompeteDesign.inkGhost)
                date
            }
            .lineLimit(1)
        }
    }

    private func trophyScore(_ trophy: CompetitionTrophy) -> some View {
        Text(formatScore(trophy))
            .madFont(size: 17, weight: .heavy, design: .rounded)
            .foregroundColor(CompeteDesign.ink)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.75)
    }

    private func trophyScoreUnit(_ trophy: CompetitionTrophy) -> some View {
        Text(scoreUnitLabel(trophy).uppercased())
            .madFont(size: 11, weight: .bold, design: .rounded)
            .tracking(0.6)
            .foregroundColor(CompeteDesign.inkFaint)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
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
        let field = trophy.placedAmongTeams == true
            ? (trophy.totalParticipants == 1 ? "team" : "teams")
            : (trophy.totalParticipants == 1 ? "competitor" : "competitors")
        return "\(ordinal) of \(trophy.totalParticipants) \(field)"
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
