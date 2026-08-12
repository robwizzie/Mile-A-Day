import SwiftUI

/// All-time Head-to-Head duel history: record, rivals, and every past matchup
/// with both sides' miles. Fed by `RemoteChallengeService.matchupHistory`
/// (GET /users/:id/challenges/matchups).
struct MatchupHistoryView: View {
    @ObservedObject var userManager: UserManager

    @State private var history: RemoteChallengeService.MatchupHistoryDTO? =
        (ChallengeService.shared as? RemoteChallengeService)?.matchupHistory

    var body: some View {
        ZStack {
            MADTheme.Colors.appBackgroundGradient
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    if let history, !history.matchups.isEmpty {
                        recordHero(history)
                        if !history.rivals.isEmpty {
                            rivalsSection(history.rivals)
                        }
                        duelsSection(history.matchups)
                    } else {
                        emptyState
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 20)
            }
        }
        .navigationTitle("Head-to-Head")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if let userId = userManager.currentUser.backendUserId,
               let remote = ChallengeService.shared as? RemoteChallengeService {
                await remote.refreshMatchups(userId: userId)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: ChallengeService.changedNotification)) { _ in
            history = (ChallengeService.shared as? RemoteChallengeService)?.matchupHistory
        }
    }

    // MARK: - Record hero

    private func recordHero(_ history: RemoteChallengeService.MatchupHistoryDTO) -> some View {
        VStack(spacing: 16) {
            HStack {
                Text("ALL-TIME RECORD")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(1.2)
                    .foregroundColor(.white.opacity(0.6))
                Spacer()
                Text(history.record.total == 1 ? "1 duel" : "\(history.record.total) duels")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.6))
            }

            HStack(spacing: 12) {
                recordColumn(value: history.record.wins, label: "Wins", color: .green)
                recordDivider
                recordColumn(value: history.record.losses, label: "Losses", color: .orange)
                recordDivider
                recordColumn(value: history.record.ties, label: "Ties", color: .yellow)
            }

            winRateBar(record: history.record)

            if history.currentWinStreak > 1 || history.bestWinStreak > 1 {
                HStack(spacing: 8) {
                    if history.currentWinStreak > 1 {
                        streakChip(
                            icon: "flame.fill",
                            text: "\(history.currentWinStreak) wins in a row",
                            color: .orange
                        )
                    }
                    if history.bestWinStreak > 1 {
                        streakChip(
                            icon: "crown.fill",
                            text: "Best streak: \(history.bestWinStreak)",
                            color: .yellow
                        )
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .fill(
                            LinearGradient(
                                colors: [MADTheme.Colors.madRed.opacity(0.12), Color.clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
        )
    }

    private func recordColumn(value: Int, label: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.system(size: 32, weight: .heavy, design: .rounded))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
    }

    private var recordDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.1))
            .frame(width: 1, height: 36)
    }

    private func winRateBar(record: RemoteChallengeService.MatchupRecordDTO) -> some View {
        let rate = record.total > 0 ? Double(record.wins) / Double(record.total) : 0
        return VStack(spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.1))
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [.green, .green.opacity(0.7)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(rate * geo.size.width, rate > 0 ? 8 : 0))
                }
            }
            .frame(height: 8)
            HStack {
                Text("Win rate")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.5))
                Spacer()
                Text("\(Int((rate * 100).rounded()))%")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(.green)
            }
        }
    }

    private func streakChip(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(color)
            Text(text)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.85))
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(Capsule().fill(color.opacity(0.15)))
    }

    // MARK: - Rivals

    private func rivalsSection(_ rivals: [RemoteChallengeService.MatchupRivalRecordDTO]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("YOUR RIVALS")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .tracking(1.2)
                .foregroundColor(.white.opacity(0.6))

            VStack(spacing: 10) {
                ForEach(rivals) { rival in
                    rivalRow(rival)
                }
            }
        }
        .padding(16)
        .background(sectionBackground)
    }

    private func rivalRow(_ rival: RemoteChallengeService.MatchupRivalRecordDTO) -> some View {
        HStack(spacing: 12) {
            AvatarView(name: rival.displayName, imageURL: rival.profileImageUrl, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(rival.displayName)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                Text(rival.total == 1 ? "1 duel" : "\(rival.total) duels")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.5))
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(rival.wins)–\(rival.losses)\(rival.ties > 0 ? "–\(rival.ties)" : "")")
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .foregroundColor(edgeColor(rival))
                Text(edgeText(rival))
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundColor(edgeColor(rival).opacity(0.8))
            }
        }
    }

    private func edgeColor(_ rival: RemoteChallengeService.MatchupRivalRecordDTO) -> Color {
        if rival.wins > rival.losses { return .green }
        if rival.wins < rival.losses { return .orange }
        return .yellow
    }

    private func edgeText(_ rival: RemoteChallengeService.MatchupRivalRecordDTO) -> String {
        if rival.wins > rival.losses { return "You lead" }
        if rival.wins < rival.losses { return "They lead" }
        return "Dead even"
    }

    // MARK: - Past duels

    private func duelsSection(_ matchups: [RemoteChallengeService.MatchupItemDTO]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("PAST DUELS")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .tracking(1.2)
                .foregroundColor(.white.opacity(0.6))

            VStack(spacing: 14) {
                ForEach(monthGroups(matchups), id: \.title) { group in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(group.title.uppercased())
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .tracking(1.0)
                            .foregroundColor(.white.opacity(0.4))
                        VStack(spacing: 8) {
                            ForEach(group.items) { item in
                                MatchupDuelRow(matchup: item)
                            }
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(sectionBackground)
    }

    private func monthGroups(
        _ matchups: [RemoteChallengeService.MatchupItemDTO]
    ) -> [(title: String, items: [RemoteChallengeService.MatchupItemDTO])] {
        var groups: [(title: String, items: [RemoteChallengeService.MatchupItemDTO])] = []
        for item in matchups {
            let title = MatchupDateFormat.monthTitle(item.localDate)
            if let lastIndex = groups.indices.last, groups[lastIndex].title == title {
                groups[lastIndex].items.append(item)
            } else {
                groups.append((title: title, items: [item]))
            }
        }
        return groups
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "figure.run")
                .font(.system(size: 40, weight: .semibold))
                .foregroundColor(MADTheme.Colors.madRed.opacity(0.8))
                .padding(.top, 60)
            Text("No duels yet")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            Text("Head-to-Head days pit you against a friend — whoever logs more miles by midnight takes the duel. Your results will show up here.")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.65))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity)
    }

    private var sectionBackground: some View {
        RoundedRectangle(cornerRadius: 14)
            .fill(.white.opacity(0.06))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(.white.opacity(0.1), lineWidth: 1)
            )
    }
}

// MARK: - Duel row (shared with DailyChallengesView's preview card)

/// One past duel: result pill, rival, date, and both sides' miles.
struct MatchupDuelRow: View {
    let matchup: RemoteChallengeService.MatchupItemDTO

    private var resultColor: Color {
        if matchup.won { return .green }
        if matchup.tied { return .yellow }
        return .orange
    }

    private var resultLetter: String {
        if matchup.won { return "W" }
        if matchup.tied { return "T" }
        return "L"
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(resultLetter)
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundColor(resultColor)
                .frame(width: 28, height: 28)
                .background(Circle().fill(resultColor.opacity(0.18)))
                .overlay(Circle().stroke(resultColor.opacity(0.4), lineWidth: 1))

            AvatarView(name: matchup.rival.displayName, imageURL: matchup.rival.profileImageUrl, size: 32)

            VStack(alignment: .leading, spacing: 1) {
                Text("vs \(matchup.rival.displayName)")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text(MatchupDateFormat.dayTitle(matchup.localDate))
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.5))
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 1) {
                // Server-final scores, rounded to 2dp by the resolver — plain
                // %.2f matches them exactly. `.milesText` floors and would show
                // 1.23 for a duel the server decided at 1.24.
                HStack(spacing: 4) {
                    Text(String(format: "%.2f", matchup.myMiles))
                        .font(.system(size: 14, weight: matchup.won || matchup.tied ? .heavy : .medium, design: .rounded))
                        .foregroundColor(matchup.won || matchup.tied ? resultColor : .white.opacity(0.6))
                    Text("–")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.35))
                    Text(String(format: "%.2f", matchup.rivalMiles))
                        .font(.system(size: 14, weight: !matchup.won && !matchup.tied ? .heavy : .medium, design: .rounded))
                        .foregroundColor(!matchup.won && !matchup.tied ? resultColor : .white.opacity(0.6))
                }
                Text("mi")
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.4))
            }

            if matchup.completed {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.yellow)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(resultColor.opacity(0.18), lineWidth: 1)
                )
        )
    }
}

// MARK: - Date formatting

/// Shared yyyy-MM-dd parsing/formatting for matchup dates. Formatters are
/// static — building a DateFormatter per row while scrolling is a hitch.
enum MatchupDateFormat {
    private static let parser: DateFormatter = {
        let fmt = DateFormatter()
        fmt.calendar = Calendar(identifier: .gregorian)
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt
    }()

    private static let dayFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "EEE, MMM d"
        return fmt
    }()

    private static let monthFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "MMMM yyyy"
        return fmt
    }()

    static func dayTitle(_ localDate: String) -> String {
        guard let date = parser.date(from: localDate) else { return localDate }
        return dayFormatter.string(from: date)
    }

    static func monthTitle(_ localDate: String) -> String {
        guard let date = parser.date(from: localDate) else { return localDate }
        return monthFormatter.string(from: date)
    }
}
