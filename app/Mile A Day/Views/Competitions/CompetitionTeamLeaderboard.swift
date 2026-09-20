import SwiftUI

// MARK: - Team Leaderboard
// The standings a TEAM competition is actually scored on.
//
// A team is one competitor over its members' COMBINED quantity — never a sum of
// their individual scores (see `usesTeamEntityScoring` server-side) — so a flat
// list of people ranked by their own score answers a question this competition
// never asks, and answers it confusingly: two members of different teams both
// read "1 pt" while their teams are miles apart, and the person at the top of
// that list can be on the losing side.
//
// So in team mode the leaderboard IS the team list, with each roster nested
// under its team showing what that person CONTRIBUTED (the number that adds up
// to the team's). The individual ranking stays reachable through the
// Teams/Players toggle rather than sitting underneath as a second card that
// contradicts the first.

extension CompetitionDetailView {

    var teamLeaderboard: some View {
        // RANKED, not payload order: `DailyActivityCalendar` indexes this array
        // to pick its gold/silver/bronze focus colours, so an unsorted one
        // assigns them by whatever order the server happened to serialise.
        let accepted = competition.acceptedRanked
        let accent = CompeteDesign.accent(competition.type)
        let teamStandings = competition.rankedTeamStandings

        return VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
            CompeteHeader(
                eyebrow: "Standings",
                trailingText: standingsShowsTeams
                    ? "\(teamStandings.count) team\(teamStandings.count == 1 ? "" : "s")"
                    : "\(accepted.count) player\(accepted.count == 1 ? "" : "s")"
            ) {
                CompeteSegmented(
                    options: [(true, "Teams"), (false, "Players")],
                    selection: $standingsShowsTeams
                )
            }
            .padding(.horizontal, 2)

            CompeteSurface {
                VStack(spacing: 0) {
                    if standingsShowsTeams {
                        teamGroups(standings: teamStandings)
                    } else {
                        playerRows(accepted)
                    }

                    CompeteRowRule().padding(.vertical, 12)

                    // Same calendar in both modes — it reports the whole
                    // competition, and tapping any person focuses it on them.
                    DailyActivityCalendar(
                        allUsers: accepted,
                        competition: competition,
                        accent: accent,
                        focusedUserId: $expandedLeaderboardUserId
                    )
                }
            }
        }
    }

    // MARK: - Teams mode

    /// Teams, each collapsible to its own row. Same block as the finished
    /// screen's results (`CompeteTeamBlock`) — a team that reads one way while
    /// the competition runs and another once it ends is two designs for one
    /// object.
    @ViewBuilder
    private func teamGroups(standings: [(place: Int, team: CompetitionTeam)]) -> some View {
        let unassigned = competition.unassignedUsers
        let leaderScore = standings.first?.team.score ?? 0

        VStack(spacing: 0) {
            ForEach(Array(standings.enumerated()), id: \.element.team.id) { index, entry in
                if index > 0 {
                    CompeteRowRule().padding(.vertical, 12)
                }

                CompeteTeamBlock(
                    competition: competition,
                    team: entry.team,
                    place: entry.place,
                    leaderScore: leaderScore,
                    isTied: standings.filter { $0.place == entry.place }.count > 1,
                    rosterMode: .collapsible,
                    isFinished: false,
                    isExpanded: !collapsedTeamIds.contains(entry.team.id),
                    onToggle: {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                            if collapsedTeamIds.contains(entry.team.id) {
                                collapsedTeamIds.remove(entry.team.id)
                            } else {
                                collapsedTeamIds.insert(entry.team.id)
                            }
                        }
                    }
                )
            }

            // People with no team still compete as themselves — grouping them
            // under a heading is the difference between "also competing" and
            // "quietly missing from the standings".
            if !unassigned.isEmpty {
                CompeteRowRule().padding(.vertical, 12)
                unassignedGroup(unassigned)
            }
        }
    }

    @ViewBuilder
    private func unassignedGroup(_ users: [CompetitionUser]) -> some View {
        let currentUserId = UserDefaults.standard.string(forKey: "backendUserId")
        let ranked = Competition.ranked(users, by: { $0.contributionValue })
        let places = Competition.places(ranked, by: { $0.contributionValue })

        VStack(alignment: .leading, spacing: 8) {
            Text("COMPETING WITHOUT A TEAM")
                .font(CompeteDesign.eyebrow)
                .tracking(CompeteDesign.eyebrowTracking)
                .foregroundColor(CompeteDesign.inkFaint)

            VStack(spacing: 0) {
                ForEach(Array(zip(places, ranked).enumerated()), id: \.element.1.id) { index, pair in
                    if index > 0 { CompeteRowRule(inset: 49) }
                    CompeteStandingsRow(
                        place: pair.0,
                        user: pair.1,
                        competition: competition,
                        isCurrentUser: pair.1.user_id == currentUserId,
                        // Miles, like every other person-row in a team
                        // competition — these people have no team, but they
                        // are on the same screen as ones who do.
                        metric: .contribution,
                        leaderScore: ranked.first?.contributionValue ?? 0,
                        isTied: places.filter { $0 == pair.0 }.count > 1
                    )
                }
            }
        }
    }

    // MARK: - Players mode

    /// The people view of a TEAM competition — measured in MILES.
    ///
    /// It used to rank them by their individual `score` and print those points
    /// beside each name, under a caption apologising for them. That caption
    /// was doing work no caption can do: the numbers were computed under a
    /// scoring rule this competition is not played on, so they don't sum to
    /// any team's total and routinely disagree with it (more points on fewer
    /// miles; members of the losing team above members of the winning one).
    /// Miles are what a member actually puts into their team, so miles are
    /// what this list reports — and every row carries the team it was walked
    /// for.
    @ViewBuilder
    private func playerRows(_ accepted: [CompetitionUser]) -> some View {
        let currentUserId = UserDefaults.standard.string(forKey: "backendUserId")
        let standings = competition.rankedByContribution
        let leader = standings.first?.user.contributionValue ?? 0

        VStack(alignment: .leading, spacing: 10) {
            Text("What each walker has put in. The competition is won on the team totals.")
                .font(CompeteDesign.caption)
                .foregroundColor(CompeteDesign.inkFaint)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 0) {
                ForEach(Array(standings.enumerated()), id: \.element.user.id) { index, entry in
                    if index > 0 { CompeteRowRule(inset: 49) }

                    Button {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                            expandedLeaderboardUserId =
                                expandedLeaderboardUserId == entry.user.user_id ? nil : entry.user.user_id
                        }
                    } label: {
                        CompeteStandingsRow(
                            place: entry.place,
                            user: entry.user,
                            competition: competition,
                            isCurrentUser: entry.user.user_id == currentUserId,
                            metric: .contribution,
                            leaderScore: leader,
                            isTied: standings.filter { $0.place == entry.place }.count > 1,
                            isFocused: expandedLeaderboardUserId == entry.user.user_id
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - Shared team lives chip

/// A team's shared pool of lives. Zero reads as "OUT" in words — a row of empty
/// heart outlines is easy to skim straight past, and being out is the single
/// most important thing a Streaks row can say.
struct TeamLivesChip: View {
    let lives: Int

    var body: some View {
        if lives <= 0 {
            Text("OUT")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundColor(.white.opacity(0.5))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.white.opacity(0.08)))
                .fixedSize()
                .accessibilityLabel("Out of lives")
        } else {
            HStack(spacing: 2) {
                ForEach(0..<min(lives, 3), id: \.self) { _ in
                    Image(systemName: "heart.fill")
                        .font(.system(size: 9))
                        .foregroundColor(MADTheme.Colors.madRed.opacity(0.9))
                }
                if lives > 3 {
                    Text("×\(lives)")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundColor(MADTheme.Colors.madRed.opacity(0.9))
                }
            }
            .fixedSize()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(lives) live\(lives == 1 ? "" : "s") left")
        }
    }
}
