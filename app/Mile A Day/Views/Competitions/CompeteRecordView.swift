import SwiftUI

/// The "Record" segment — your competition identity.
///
/// Wins and losses used to be invisible: `TrophyCaseView` counted medals and a
/// win rate, but only behind a small gold pill that appeared once you'd already
/// finished something, and it never said how many you'd *lost*. A record you
/// can see is a record you can want to improve.
///
/// Phase 1 derives everything client-side from the competitions the tab already
/// loaded, so this ships with no API work. That derivation only sees one page
/// of competitions, which is what the server-side record endpoint will fix —
/// and it stays afterwards as the offline fallback.
struct CompeteRecordView: View {
    @ObservedObject var competitionService: CompetitionService
    @ObservedObject var trophyService: TrophyService

    let onOpen: (Competition) -> Void
    let onOpenTrophyCase: () -> Void

    /// Finished competitions, newest first — the full history list.
    private var finished: [Competition] {
        competitionService.competitions
            .filter { $0.status == .finished }
            .sorted { ($0.end_date ?? "") > ($1.end_date ?? "") }
    }

    private var hasRecord: Bool { trophyService.totalCompetitions > 0 }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MADTheme.Spacing.lg) {
                RecordHeroCard(
                    wins: trophyService.wins,
                    losses: trophyService.losses,
                    podiums: trophyService.podiums,
                    currentStreak: trophyService.currentWinStreak,
                    // Everything here comes from the competitions already in
                    // memory rather than a full server-side history.
                    isPartial: true
                )

                if hasRecord {
                    modeBreakdown
                    trophyShelf
                    history
                } else {
                    emptyState
                }
            }
            .padding(.horizontal, MADTheme.Spacing.md)
            .padding(.top, MADTheme.Spacing.md)
            .padding(.bottom, 32)
        }
        .scrollBounceBehavior(.basedOnSize)
        .refreshable {
            await competitionService.refreshAllData()
            trophyService.updateTrophies(from: competitionService.competitions)
        }
    }

    // MARK: - By mode

    private var modeBreakdown: some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
            CompeteSectionHeader(title: "By mode", systemImage: "chart.bar.fill", accent: MADTheme.Colors.madRed)

            VStack(spacing: 12) {
                ForEach(trophyService.byMode) { record in
                    ModeRecordRow(record: record)
                }
            }
            .padding(MADTheme.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large, style: .continuous)
                    .fill(Color.white.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.07), lineWidth: 1)
                    )
            )

            if let strongest = trophyService.strongestMode, strongest.wins > 0 {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.yellow)
                    Text("\(strongest.type.displayName) is your best mode — \(strongest.wins)–\(strongest.losses).")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.7))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    // MARK: - Medals

    private var trophyShelf: some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
            CompeteSectionHeader(
                title: "Medals",
                systemImage: "medal.fill",
                accent: .yellow,
                actionTitle: "Trophy case",
                action: onOpenTrophyCase
            )

            HStack(spacing: 0) {
                medalCell(count: trophyService.goldCount, label: "Gold", colors: [.yellow, .orange])
                medalCell(count: trophyService.silverCount, label: "Silver", colors: [Color(white: 0.85), Color(white: 0.6)])
                medalCell(count: trophyService.bronzeCount, label: "Bronze", colors: [.brown, Color(red: 0.7, green: 0.4, blue: 0.2)])
            }
            .padding(.vertical, MADTheme.Spacing.md)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large, style: .continuous)
                    .fill(Color.white.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.07), lineWidth: 1)
                    )
            )
        }
    }

    private func medalCell(count: Int, label: String, colors: [Color]) -> some View {
        VStack(spacing: 6) {
            Image(systemName: "medal.fill")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(
                    count > 0
                        ? LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
                        : LinearGradient(colors: [Color.white.opacity(0.15)], startPoint: .top, endPoint: .bottom)
                )

            Text("\(count)")
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .foregroundColor(count > 0 ? .white : .white.opacity(0.3))

            Text(label.uppercased())
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(0.6)
                .foregroundColor(.white.opacity(0.45))
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - History

    private var history: some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
            CompeteSectionHeader(title: "History", systemImage: "clock.arrow.circlepath", accent: .white.opacity(0.6))

            VStack(spacing: 8) {
                ForEach(finished, id: \.competition_id) { competition in
                    FinishedCompetitionRow(competition: competition) {
                        onOpen(competition)
                    }
                }
            }
        }
    }

    // MARK: - Empty

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "trophy")
                .font(.system(size: 34, weight: .medium))
                .foregroundColor(MADTheme.Colors.madRed.opacity(0.5))

            Text("No record yet")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(.white)

            Text("Finish a competition and your wins, losses and medals will show up here.")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.55))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}
