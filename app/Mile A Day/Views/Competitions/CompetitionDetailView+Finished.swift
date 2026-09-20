import SwiftUI
import HealthKit

// MARK: - Finished Content

extension CompetitionDetailView {

    // MARK: - Finished Content
    /// The end screen.
    ///
    /// Answers, in this order: who won, how everyone finished, and what the
    /// competition amounted to. On a TEAM competition the first two are about
    /// TEAMS — that is what was scored (`usesTeamEntityScoring` server-side) —
    /// so the result banner names the winning team, and the full team table
    /// below it carries every team, in order, with its roster and each
    /// member's distance ON the card rather than behind a tap. A team result
    /// that hides who was on the team is a result about nobody.
    var finishedContent: some View {
        let standings = competition.rankedStandings
        let currentUserId = UserDefaults.standard.string(forKey: "backendUserId")
        let myPlace = standings.first(where: { $0.user.user_id == currentUserId })?.place

        return VStack(spacing: MADTheme.Spacing.lg) {
            resultBanner(standings: standings, currentUserId: currentUserId, myPlace: myPlace)

            if competition.hasTeams {
                CompetitionTeamResults(competition: competition)
            }

            finalStandings(standings: standings, currentUserId: currentUserId)

            if !standings.isEmpty {
                CompeteSurface {
                    DailyActivityCalendar(
                        allUsers: standings.map { $0.user },
                        competition: competition,
                        accent: CompeteDesign.accent(competition.type),
                        focusedUserId: $expandedLeaderboardUserId
                    )
                }
            }

            competitionRecap(rankedUsers: standings.map { $0.user })
        }
        .onAppear {
            showCelebration = false
            podiumAnimated = false
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                showCelebration = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                withAnimation(.spring(response: 0.7, dampingFraction: 0.8)) {
                    podiumAnimated = true
                }
            }
        }
    }

    // MARK: - Result banner

    /// The headline. One statement of who won and one of where the viewer
    /// landed — the old screen said "COMPETITION COMPLETE" in tracked caps
    /// over a 60pt trophy, then repeated the viewer's placement in a separate
    /// card much further down the page, so the two facts a person opens this
    /// screen for were the ones furthest apart on it.
    @ViewBuilder
    func resultBanner(
        standings: [(place: Int, user: CompetitionUser)],
        currentUserId: String?,
        myPlace: Int?
    ) -> some View {
        let winningTeam = competition.hasTeams ? competition.rankedTeams.first : nil
        // Likewise for the name on the card: the server's recorded winner, and
        // only our own ranking when it hasn't recorded one yet.
        let individualWinner = competition.winner
            .flatMap { id in standings.first(where: { $0.user.user_id == id })?.user }
            ?? standings.first?.user
        let winnerName = winningTeam?.name ?? individualWinner?.displayName
        let winnerScore = winningTeam.map { competition.teamScoreLabel($0) }
            ?? individualWinner.map { scoreLabel(for: $0) }
        // On a team competition the viewer WON if their team did — a member of
        // the winning team placed 4th among people has still won it.
        let iWon: Bool = {
            if competition.hasTeams, let currentUserId {
                // Through `rankedTeamStandings`, like the WON tag and the
                // result sentence. `rankedTeams.first` is ONE team even when
                // two are genuinely level, so on a tie the same screen showed
                // a team placed 1st and withheld the win from it.
                guard let myTeam = competition.team(for: currentUserId) else { return false }
                return competition.rankedTeamStandings
                    .first(where: { $0.team.id == myTeam.id })?.place == 1
            }
            // The stored winner is the answer when there is one. Deriving it
            // from our own first place tells every competitor in a genuine tie
            // "You won it." while the Trophy Case, which does trust the stored
            // winner, hands most of them silver.
            if let winnerId = competition.winner { return winnerId == currentUserId }
            return myPlace == 1
        }()

        ZStack {
            if showCelebration && iWon {
                CompetitionConfettiView()
            }

            CompeteSurface(padding: 18) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 13))
                            .foregroundColor(CompeteDesign.inkFaint)
                            .accessibilityHidden(true)
                        Text("FINAL RESULT")
                            .font(CompeteDesign.eyebrow)
                            .tracking(CompeteDesign.eyebrowTracking)
                            .foregroundColor(CompeteDesign.inkFaint)
                        Spacer()
                        if let ended = competition.endDateFormatted {
                            Text(ended.formatted(date: .abbreviated, time: .omitted))
                                .font(CompeteDesign.caption)
                                .foregroundColor(CompeteDesign.inkGhost)
                                .lineLimit(1)
                        }
                    }

                    if let winnerName {
                        HStack(alignment: .center, spacing: 12) {
                            winnerMark(winningTeam: winningTeam, winner: individualWinner)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(winnerName)
                                    .font(.system(size: 27, weight: .heavy, design: .rounded))
                                    .foregroundColor(CompeteDesign.ink)
                                    .lineLimit(2)
                                    .minimumScaleFactor(0.7)
                                Text(winningTeam == nil ? "Winner" : "Winning team")
                                    .font(CompeteDesign.caption)
                                    .foregroundColor(CompeteDesign.inkFaint)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            if let winnerScore {
                                Text(winnerScore)
                                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                                    .foregroundColor(CompeteDesign.medal(1) ?? .yellow)
                                    .monospacedDigit()
                                    .lineLimit(1)
                                    .fixedSize()
                            }
                        }
                    }

                    CompeteRowRule()

                    Text(myResultSentence(myPlace: myPlace, fieldSize: standings.count, iWon: iWon))
                        .font(CompeteDesign.detail)
                        .foregroundColor(iWon ? (CompeteDesign.medal(1) ?? .yellow) : CompeteDesign.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// The winner's face, or the winning team's colour dot. A team has no
    /// avatar and borrowing its top contributor's would name the wrong winner.
    @ViewBuilder
    private func winnerMark(winningTeam: CompetitionTeam?, winner: CompetitionUser?) -> some View {
        if let winningTeam {
            ZStack {
                Circle()
                    .fill(competition.teamColor(winningTeam.id).opacity(0.2))
                Circle()
                    .strokeBorder(competition.teamColor(winningTeam.id), lineWidth: 2)
                Image(systemName: "flag.fill")
                    .font(.system(size: 18))
                    .foregroundColor(competition.teamColor(winningTeam.id))
            }
            .frame(width: 48, height: 48)
            .accessibilityHidden(true)
        } else if let winner {
            AvatarView(name: winner.displayName, imageURL: winner.profile_image_url, size: 48)
                .overlay(
                    Circle().strokeBorder(CompeteDesign.medal(1) ?? .yellow, lineWidth: 2)
                )
        }
    }

    /// "You finished 4th of 6." — said once, in the banner, in words.
    ///
    /// On a team competition it reports the TEAM's place and the viewer's own
    /// MILES. It used to append "you finished 4th of 6 overall", which is a
    /// placing on the individual leaderboard — a board this competition was
    /// never scored on, and one that can rank you above people whose team beat
    /// yours. Saying a team won and then immediately ranking the person is how
    /// a reader ends up unsure which number decided anything.
    private func myResultSentence(myPlace: Int?, fieldSize: Int, iWon: Bool) -> String {
        let uid = UserDefaults.standard.string(forKey: "backendUserId")
        let me = uid.flatMap { id in
            competition.users.first(where: { $0.user_id == id && $0.invite_status == .accepted })
        }

        if competition.hasTeams {
            guard let me else { return "You weren't in this one." }
            let mine = competition.options.formatQuantityWithUnit(me.contributionValue)
            guard let myTeam = uid.flatMap({ competition.team(for: $0) }),
                  let teamPlace = competition.rankedTeamStandings
                    .first(where: { $0.team.id == myTeam.id })?.place else {
                // Accepted, but on no team — they competed as themselves.
                return "You competed without a team and covered \(mine)."
            }
            if iWon { return "\(myTeam.name) won it. You put in \(mine)." }
            return "\(myTeam.name) finished \(Self.ordinal(teamPlace)) of \(competition.rankedTeams.count). You put in \(mine)."
        }

        guard let myPlace else { return "You weren't in this one." }
        if iWon { return "You won it." }
        return "You finished \(Self.ordinal(myPlace)) of \(fieldSize)."
    }

    static func ordinal(_ n: Int) -> String {
        let suffix: String
        switch (n % 100, n % 10) {
        case (11, _), (12, _), (13, _): suffix = "th"
        case (_, 1): suffix = "st"
        case (_, 2): suffix = "nd"
        case (_, 3): suffix = "rd"
        default: suffix = "th"
        }
        return "\(n)\(suffix)"
    }

    // MARK: - Final standings

    /// Every competitor, in order, in one table.
    ///
    /// On a TEAM competition this measures people in MILES, never points.
    /// Points are the team's — a member's own score is computed under
    /// individual scoring, so it neither sums to their team's number nor
    /// agrees with it, and a board ranked by it printed "MegsMiles 3 pts ·
    /// 41.2 mi" above "Aaron 2 pts · 47.5 mi" under a heading that read as a
    /// second, competing set of standings for the same competition. Ranked by
    /// distance the list says something true and additive: who covered the
    /// most ground, with the team they did it for on every row.
    @ViewBuilder
    func finalStandings(
        standings: [(place: Int, user: CompetitionUser)],
        currentUserId: String?
    ) -> some View {
        let isTeamComp = competition.hasTeams
        let rows = isTeamComp ? competition.rankedByContribution : standings

        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
                CompeteHeader(
                    eyebrow: isTeamComp ? "Who Went Furthest" : "Final Standings",
                    trailingText: "\(rows.count) competed"
                )
                .padding(.horizontal, 2)

                CompeteSurface {
                    VStack(alignment: .leading, spacing: 0) {
                        if isTeamComp {
                            Text("Every walker's own miles. \(competition.rankedTeams.first?.name ?? "The winning team") won on the TEAM totals above.")
                                .font(CompeteDesign.caption)
                                .foregroundColor(CompeteDesign.inkFaint)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.bottom, 12)
                        }

                        standingsTable(
                            standings: rows,
                            currentUserId: currentUserId,
                            metric: isTeamComp ? .contribution : .score
                        )
                    }
                }
            }
        }
    }

    // MARK: - Competition Recap

    /// What the competition amounted to, as a rail of figures rather than a
    /// grid of coloured icon cards. Six tinted glyphs under a leaderboard were
    /// six more colours arguing with the one accent that means something.
    func competitionRecap(rankedUsers: [CompetitionUser]) -> some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
            CompeteHeader(eyebrow: "Recap")
                .padding(.horizontal, 2)

            CompeteSurface {
                VStack(alignment: .leading, spacing: 16) {
                    CompeteStatRail(stats: sharedRecapStats(rankedUsers: rankedUsers))
                    CompeteRowRule()
                    CompeteStatRail(stats: typeRecapStats(rankedUsers: rankedUsers))
                }
            }
        }
    }

    private func sharedRecapStats(rankedUsers: [CompetitionUser]) -> [(value: String, label: String)] {
        var stats: [(value: String, label: String)] = [
            ("\(rankedUsers.count)", "Competitors")
        ]
        if competition.hasTeams {
            stats.append(("\(competition.rankedTeams.count)", "Teams"))
        }
        if let start = competition.startDateFormatted, let end = competition.endDateFormatted {
            let days = Calendar.current.dateComponents([.day], from: start, to: end).day ?? 0
            stats.append(("\(max(1, days))", days == 1 ? "Day" : "Days"))
        }
        return stats
    }

    private func typeRecapStats(rankedUsers: [CompetitionUser]) -> [(value: String, label: String)] {
        let unit = competition.options.unit.shortDisplayName
        // The winning score is the WINNER's — which on a team competition is a
        // team's, not the top individual's. Reading the person here printed
        // "Rounds won 3" beside a team table whose winner held 5.
        let winnerScore = competition.hasTeams
            ? (competition.rankedTeams.first?.score ?? 0)
            : (rankedUsers.first?.score ?? 0)

        switch competition.type {
        case .race, .apex:
            let total = rankedUsers.reduce(0.0) { $0 + ($1.score ?? 0) }
            let average = rankedUsers.isEmpty ? 0 : total / Double(rankedUsers.count)
            return [
                (String(format: "%.1f %@", winnerScore, unit), competition.type == .race ? "Winning distance" : "Top distance"),
                (String(format: "%.1f %@", average, unit), "Average"),
                (String(format: "%.0f %@", total, unit), "Covered in total"),
            ]

        case .streaks:
            let best = Int(winnerScore)
            let average = rankedUsers.isEmpty ? 0 : rankedUsers.reduce(0.0) { $0 + ($1.score ?? 0) } / Double(rankedUsers.count)
            return [
                ("\(best)", competition.hasTeams ? "Winning team's streak" : (best == 1 ? "Best streak (day)" : "Best streak (days)")),
                (String(format: "%.0f", average), "Average streak"),
            ]

        case .clash:
            let rounds = rankedUsers.first?.intervals?.count ?? 0
            return [
                ("\(Int(winnerScore))", competition.hasTeams ? "Winning team's rounds" : "Rounds won"),
                ("\(rounds)", "Rounds played"),
            ]

        case .targets:
            let intervals = rankedUsers.first?.intervals?.count ?? 0
            let hitRate = intervals > 0 ? Double(Int(winnerScore)) / Double(intervals) * 100 : 0
            return [
                ("\(Int(winnerScore))", competition.hasTeams ? "Winning team's points" : "Winning points"),
                (ProgressCalculator.formatWholePercent(hitRate), "Goal hit rate"),
            ]
        }
    }

    // MARK: - Info Section (shared)
    var infoContent: some View {
        VStack(spacing: 11) {
            // Type-specific settings
            switch competition.type {
            case .apex:
                InfoRow(icon: "ruler", title: "Unit", value: competition.options.unit.displayName)
                durationRow

            case .streaks:
                InfoRow(
                    icon: "target",
                    title: "Goal",
                    value: "\(competition.options.goalFormatted) \(competition.options.unit.shortDisplayName)"
                )
                if let interval = competition.options.interval {
                    InfoRow(icon: "arrow.trianglehead.2.clockwise", title: "Interval", value: interval.displayName)
                }
                let streakLives = competition.streakLives
                if streakLives > 0 {
                    InfoRow(icon: "heart", title: "Lives", value: "\(streakLives)")
                }

            case .targets:
                InfoRow(
                    icon: "target",
                    title: "Goal",
                    value: "\(competition.options.goalFormatted) \(competition.options.unit.shortDisplayName)"
                )
                if let interval = competition.options.interval {
                    InfoRow(icon: "arrow.trianglehead.2.clockwise", title: "Interval", value: interval.displayName)
                }
                durationRow

            case .clash:
                InfoRow(icon: "ruler", title: "Unit", value: competition.options.unit.displayName)
                if competition.options.first_to > 0 {
                    InfoRow(icon: "star", title: "Points to Win", value: "\(competition.options.first_to)")
                }
                if let interval = competition.options.interval {
                    InfoRow(icon: "arrow.trianglehead.2.clockwise", title: "Interval", value: interval.displayName)
                }

            case .race:
                InfoRow(
                    icon: "target",
                    title: "Goal",
                    value: "\(competition.options.goalFormatted) \(competition.options.unit.shortDisplayName)"
                )
            }

            // Activities (all types) — colored pills
            ActivitiesInfoRow(activities: competition.workouts)
        }
    }

    var infoSection: some View {
        CompeteSurface(padding: 16) {
            VStack(spacing: 12) {
                infoContent
            }
        }
    }

    @ViewBuilder
    var durationRow: some View {
        if let startDate = competition.startDateFormatted,
           let endDate = competition.endDateFormatted {
            InfoRow(
                icon: "calendar",
                title: "Duration",
                value: "\(startDate.formatted(date: .abbreviated, time: .omitted)) - \(endDate.formatted(date: .abbreviated, time: .omitted))"
            )
        } else if let durationStr = competition.options.durationFormatted {
            InfoRow(icon: "clock", title: "Duration", value: durationStr)
        }
    }

    // MARK: - Invite Button
    var inviteButton: some View {
        Button(action: {
            showingInviteFriend = true
        }) {
            HStack {
                Image(systemName: "person.badge.plus")
                    .font(.title3)

                Text("Invite Friends")
                    .font(MADTheme.Typography.callout)
                    .fontWeight(.semibold)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, MADTheme.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                    .fill(MADTheme.Colors.madRed)
            )
        }
        .buttonStyle(ScaleButtonStyle())
    }

    // MARK: - Toolbar
    @ToolbarContentBuilder
    var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }

        ToolbarItem(placement: .navigationBarTrailing) {
            if competition.isOwner {
                Menu {
                    if competition.status == .lobby || competition.status == .scheduled {
                        Button {
                            showingInviteFriend = true
                        } label: {
                            Label("Invite Friends", systemImage: "person.badge.plus")
                        }
                    }

                    if competition.status == .lobby {
                        Button {
                            showingEditSettings = true
                        } label: {
                            Label("Edit Settings", systemImage: "slider.horizontal.3")
                        }
                    }

                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Label("Delete Competition", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundColor(.white)
                }
            }
        }
    }

    // MARK: - Actions
    func refreshCompetition() async {
        do {
            competition = try await competitionService.loadCompetition(id: competition.competition_id)
        } catch {
            print("Error refreshing competition: \(error)")
        }
    }

    func startCompetition() {
        isStarting = true
        Task {
            do {
                competition = try await competitionService.startCompetition(id: competition.competition_id)
                isStarting = false
            } catch {
                isStarting = false
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }

    func removeUserFromCompetition(_ user: CompetitionUser) {
        removeTargetUser = user
        showRemoveConfirmation = true
    }

    func confirmRemoveUser() {
        guard let user = removeTargetUser else { return }
        Task {
            do {
                try await competitionService.removeUser(
                    competitionId: competition.competition_id,
                    userId: user.user_id
                )
                competition = try await competitionService.loadCompetition(id: competition.competition_id)
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
            removeTargetUser = nil
        }
    }

    func deleteCompetition() {
        isDeleting = true
        Task {
            do {
                try await competitionService.deleteCompetition(id: competition.competition_id)
                dismiss()
            } catch {
                isDeleting = false
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }

    func scoreLabel(for user: CompetitionUser) -> String {
        let score = user.score ?? 0
        switch competition.type {
        case .streaks:
            return "\(Int(score)) day streak"
        case .apex:
            return String(format: "%.1f %@", score, competition.options.unit.shortDisplayName)
        case .targets:
            return "\(Int(score)) point\(Int(score) == 1 ? "" : "s")"
        case .clash:
            return "\(Int(score)) win\(Int(score) == 1 ? "" : "s")"
        case .race:
            return String(format: "%.1f %@", score, competition.options.unit.shortDisplayName)
        }
    }
}
