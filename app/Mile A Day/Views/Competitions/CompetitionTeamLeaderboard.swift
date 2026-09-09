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
        let accepted = competition.users.filter { $0.invite_status == .accepted }
        let accent = competition.type.gradient.map { Color(hex: $0) }.first ?? MADTheme.Colors.madRed

        return VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
            teamLeaderboardHeader(teamCount: competition.rankedTeams.count, playerCount: accepted.count)

            VStack(spacing: MADTheme.Spacing.md) {
                if standingsShowsTeams {
                    teamGroups
                } else {
                    playerRows(accepted)
                }

                // Same calendar in both modes — it reports the whole
                // competition, and tapping any person (team member or not)
                // focuses it on them.
                DailyActivityCalendar(
                    allUsers: accepted,
                    competition: competition,
                    accent: accent,
                    focusedUserId: $expandedLeaderboardUserId
                )
            }
            .padding(MADTheme.Spacing.md)
            .background(teamLeaderboardCardBackground)
        }
    }

    // MARK: - Header

    @ViewBuilder
    private func teamLeaderboardHeader(teamCount: Int, playerCount: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: MADTheme.Spacing.sm) {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(
                        LinearGradient(colors: [.yellow, .orange], startPoint: .top, endPoint: .bottom)
                    )
                    .accessibilityHidden(true)
                Text("Leaderboard")
                    .font(MADTheme.Typography.title3)
                    .foregroundColor(.white)

                Spacer(minLength: MADTheme.Spacing.sm)

                standingsModePicker
            }

            Text("\(teamCount) team\(teamCount == 1 ? "" : "s") · \(playerCount) player\(playerCount == 1 ? "" : "s")")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.35))
        }
        .padding(.horizontal, MADTheme.Spacing.sm)
    }

    /// Teams first, always. A team competition that opens on a list of people
    /// is the bug this view exists to fix, so Players is a place you can go —
    /// never where you land.
    private var standingsModePicker: some View {
        HStack(spacing: 2) {
            standingsModePill(title: "Teams", isOn: standingsShowsTeams) {
                standingsShowsTeams = true
            }
            standingsModePill(title: "Players", isOn: !standingsShowsTeams) {
                standingsShowsTeams = false
            }
        }
        .padding(2)
        .background(Capsule().fill(Color.white.opacity(0.07)))
    }

    private func standingsModePill(title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { action() }
        } label: {
            Text(title)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(isOn ? .black : .white.opacity(0.6))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(isOn ? Color.white.opacity(0.9) : Color.clear))
        }
        .buttonStyle(.plain)
    }

    private var teamLeaderboardCardBackground: some View {
        let gradientColors = competition.type.gradient.map { Color(hex: $0) }
        return RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                    .stroke(
                        LinearGradient(
                            colors: gradientColors.map { $0.opacity(0.3) } + [Color.clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
    }

    // MARK: - Teams mode

    @ViewBuilder
    private var teamGroups: some View {
        let teams = competition.rankedTeams
        let unassigned = competition.unassignedUsers
        let leaderScore = teams.first?.score ?? 0

        VStack(spacing: 8) {
            ForEach(Array(teams.enumerated()), id: \.element.id) { index, team in
                teamGroup(team: team, rank: index + 1, leaderScore: leaderScore)
            }

            // People with no team still compete as themselves — grouping them
            // under a heading is the difference between "also competing" and
            // "quietly missing from the standings".
            if !unassigned.isEmpty {
                unassignedGroup(unassigned)
            }
        }
    }

    @ViewBuilder
    private func teamGroup(team: CompetitionTeam, rank: Int, leaderScore: Double) -> some View {
        let members = competition.members(of: team.id)
        let color = competition.teamColor(team.id)
        let isCollapsed = collapsedTeamIds.contains(team.id)
        let isMine = myTeamId == team.id

        VStack(spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                    if isCollapsed {
                        collapsedTeamIds.remove(team.id)
                    } else {
                        collapsedTeamIds.insert(team.id)
                    }
                }
            } label: {
                teamHeaderRow(
                    team: team,
                    rank: rank,
                    color: color,
                    members: members,
                    leaderScore: leaderScore,
                    isCollapsed: isCollapsed
                )
            }
            .buttonStyle(.plain)

            if !isCollapsed {
                teamRoster(members, color: color)
            }
        }
        .background(color.opacity(isMine ? 0.12 : 0.05))
        .overlay(alignment: .leading) {
            // The team's colour as a rail down the whole group. Without it two
            // adjacent rosters read as one long list of people again.
            Rectangle()
                .fill(color)
                .frame(width: 3)
        }
        // Clip BEFORE the stroke: a stroke is centred on its path, so an
        // outline drawn under the clip loses its outer half and reads thinner
        // than the one beside it.
        .clipShape(RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium, style: .continuous)
                .stroke(isMine ? color.opacity(0.55) : Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    private func teamHeaderRow(
        team: CompetitionTeam,
        rank: Int,
        color: Color,
        members: [CompetitionUser],
        leaderScore: Double,
        isCollapsed: Bool
    ) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: MADTheme.Spacing.sm) {
                rankBadge(rank)

                VStack(alignment: .leading, spacing: 2) {
                    Text(team.name)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    teamGapCaption(team: team, rank: rank, leaderScore: leaderScore)
                }

                Spacer(minLength: 4)

                memberAvatars(members)

                if competition.type == .streaks, let lives = team.remaining_lives {
                    TeamLivesChip(lives: lives)
                }

                // A number beside a name wraps its DIGITS without this. Safe to
                // fix the size here and not on the team NAME beside it: a score
                // is bounded, a user-typed team name is not.
                Text(competition.teamScoreLabel(team))
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .foregroundColor(rank == 1 ? .yellow : .white.opacity(0.9))
                    .lineLimit(1)
                    .fixedSize()

                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white.opacity(0.3))
                    .rotationEffect(.degrees(isCollapsed ? -90 : 0))
                    .accessibilityHidden(true)
            }

            teamShareBar(team: team, color: color, leaderScore: leaderScore)
        }
        .padding(.vertical, 10)
        .padding(.leading, 13)
        .padding(.trailing, 12)
        .contentShape(Rectangle())
    }

    private func rankBadge(_ rank: Int) -> some View {
        let medal: Color = rank == 1 ? .yellow : (rank == 2 ? Color(white: 0.78) : (rank == 3 ? .orange : .white.opacity(0.35)))
        return Text("\(rank)")
            .font(.system(size: 12, weight: .heavy, design: .rounded))
            .foregroundColor(rank <= 3 ? .black : .white.opacity(0.7))
            .frame(width: 22, height: 22)
            .background(Circle().fill(rank <= 3 ? medal : Color.white.opacity(0.1)))
    }

    /// How far this team is off the lead, in the competition's own unit. The
    /// number a losing team most wants is not their own score.
    @ViewBuilder
    private func teamGapCaption(team: CompetitionTeam, rank: Int, leaderScore: Double) -> some View {
        let gap = leaderScore - (team.score ?? 0)
        if leaderScore <= 0 {
            // Nobody has scored, so "leading" and "behind" are both lies.
            Text("Nothing on the board yet")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.35))
        } else if rank == 1 {
            Text("Leading")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundColor(.yellow.opacity(0.85))
        } else if gap > 0 {
            Text("\(competition.scoreLabel(gap)) behind")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.4))
        } else {
            Text("Tied for the lead")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.45))
        }
    }

    private func memberAvatars(_ members: [CompetitionUser]) -> some View {
        HStack(spacing: -8) {
            ForEach(members.prefix(4)) { member in
                AvatarView(name: member.displayName, imageURL: member.profile_image_url, size: 22)
                    .overlay(Circle().stroke(Color.black.opacity(0.45), lineWidth: 1))
            }
            if members.count > 4 {
                Text("+\(members.count - 4)")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.45))
                    .padding(.leading, 10)
            }
        }
    }

    private func teamShareBar(team: CompetitionTeam, color: Color, leaderScore: Double) -> some View {
        let top = max(leaderScore, 0.001)
        let fill = min(max((team.score ?? 0) / top, 0), 1)
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.07))
                Capsule()
                    .fill(color)
                    .frame(width: max(geo.size.width * CGFloat(fill), fill > 0 ? 4 : 0))
            }
        }
        .frame(height: 4)
        .accessibilityHidden(true)
    }

    // MARK: - Roster

    @ViewBuilder
    private func teamRoster(_ members: [CompetitionUser], color: Color) -> some View {
        VStack(spacing: 2) {
            if members.isEmpty {
                HStack {
                    Text("No members yet")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.4))
                    Spacer()
                }
                .padding(.vertical, 6)
            }
            ForEach(Array(members.enumerated()), id: \.element.id) { index, member in
                teamMemberRow(member, placeInTeam: index + 1, color: color)
            }
        }
        .padding(.leading, 13)
        .padding(.trailing, 12)
        .padding(.bottom, 10)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    /// One person inside their team. The trailing number is their CONTRIBUTION,
    /// not their score: the team is what's being scored, so member points
    /// wouldn't sum to the team's number and "Red 4 pts" over "Alice 3, Bob 2"
    /// reads as arithmetic that got away from us. Tapping focuses the calendar
    /// on them, exactly like an individual leaderboard row.
    private func teamMemberRow(_ member: CompetitionUser, placeInTeam: Int, color: Color) -> some View {
        let isMe = member.user_id == UserDefaults.standard.string(forKey: "backendUserId")
        let isFocused = expandedLeaderboardUserId == member.user_id

        return Button {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                expandedLeaderboardUserId = isFocused ? nil : member.user_id
            }
        } label: {
            HStack(spacing: MADTheme.Spacing.sm) {
                Text("\(placeInTeam)")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.3))
                    .frame(width: 12)

                AvatarView(name: member.displayName, imageURL: member.profile_image_url, size: 26)

                Text(member.displayName)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.92))
                    .lineLimit(1)

                if isMe {
                    Text("YOU")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(MADTheme.Colors.madRed))
                        .fixedSize()
                }

                Spacer(minLength: 4)

                Text(competition.memberScoreLabel(member))
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.62))
                    .lineLimit(1)
                    .fixedSize()
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: MADTheme.CornerRadius.small)
                    .fill(isFocused ? color.opacity(0.22) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func unassignedGroup(_ users: [CompetitionUser]) -> some View {
        VStack(spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: "person.fill.questionmark")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.35))
                    .accessibilityHidden(true)
                Text("Competing without a team")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.4))
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.top, 8)
            .padding(.bottom, 2)

            // Ranked among themselves: they compete individually, so their own
            // score is the number that means something here — and a row of
            // 1, 2, 3 beside an unsorted list would be a ranking that isn't one.
            ForEach(Array(users.sorted { ($0.score ?? 0) > ($1.score ?? 0) }.enumerated()),
                    id: \.element.id) { index, user in
                teamMemberRow(user, placeInTeam: index + 1, color: .gray)
            }
        }
        .padding(.leading, 13)
        .padding(.trailing, 12)
        .padding(.bottom, 10)
        .background(
            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                .fill(Color.white.opacity(0.04))
        )
    }

    // MARK: - Players mode

    @ViewBuilder
    private func playerRows(_ accepted: [CompetitionUser]) -> some View {
        let currentUserId = UserDefaults.standard.string(forKey: "backendUserId")
        let ranked = accepted.sorted { ($0.score ?? 0) > ($1.score ?? 0) }

        VStack(spacing: 6) {
            // Said once, plainly: these points are not what decides the
            // competition, and somebody at the top of this list can still be
            // on the losing team.
            HStack(spacing: 5) {
                Image(systemName: "info.circle")
                    .font(.system(size: 10))
                    .accessibilityHidden(true)
                Text("Individual scores — this competition is won by teams.")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                Spacer()
            }
            .foregroundColor(.white.opacity(0.4))
            .padding(.bottom, 2)

            ForEach(Array(ranked.enumerated()), id: \.element.id) { index, user in
                leaderboardEntry(
                    rank: index + 1,
                    user: user,
                    isMe: user.user_id == currentUserId,
                    isExpanded: false
                )
            }
        }
    }

    private var myTeamId: String? {
        let currentUserId = UserDefaults.standard.string(forKey: "backendUserId")
        return competition.users.first { $0.user_id == currentUserId }?.team_id
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
