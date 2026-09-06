import SwiftUI

// MARK: - Team Interval View
// The Today tab, for a competition with teams.
//
// Every per-mode Today view (Matchup, Activity, Targets, streaks, Race) listed
// PEOPLE, ranked against each other. In a team competition that is the wrong
// contest: the server scores the interval on each team's COMBINED quantity, so
// a list of individuals shows a race nobody is running and can put a name on
// top whose team is losing. This draws the teams, with each member's
// contribution nested under their own team.
//
// The team total is derived from the members' `intervals` — the same
// arithmetic the server does — because the server sends a team's SCORE for the
// whole competition and never its per-interval totals.

struct CompetitionTeamIntervalView: View {
    let competition: Competition
    let title: String
    /// The interval being shown ("YYYY-MM-DD" / "YYYY-MM" key).
    let intervalKey: String
    /// When set, each team row draws progress toward it and reads as hit/missed
    /// rather than as a ranking (Targets, Streaks, Race).
    var goal: Double?
    /// Race measures the whole competition, not one interval, so it reads each
    /// team's total instead of the interval bucket.
    var useTotalScore: Bool = false

    private var currentUserId: String? {
        UserDefaults.standard.string(forKey: "backendUserId")
    }

    private var myTeamId: String? {
        competition.users.first { $0.user_id == currentUserId }?.team_id
    }

    private func total(_ team: CompetitionTeam) -> Double {
        if useTotalScore {
            return competition.members(of: team.id).reduce(0) { $0 + ($1.score ?? 0) }
        }
        return competition.teamIntervalTotal(team.id, key: intervalKey)
    }

    private func contribution(_ member: CompetitionUser) -> Double {
        useTotalScore ? (member.score ?? 0) : (member.intervals?[intervalKey] ?? 0)
    }

    private var ranked: [CompetitionTeam] {
        (competition.teams?.teams ?? []).sorted { total($0) > total($1) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
            Text(title)
                .font(MADTheme.Typography.title3)
                .foregroundColor(.white)
                .padding(.horizontal, MADTheme.Spacing.sm)

            VStack(spacing: MADTheme.Spacing.sm) {
                ForEach(Array(ranked.enumerated()), id: \.element.id) { index, team in
                    teamRow(team: team, rank: index + 1)
                }

                if !competition.unassignedUsers.isEmpty {
                    unassignedFootnote
                }
            }
            .padding(MADTheme.Spacing.lg)
            .background(
                RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                            .stroke(
                                LinearGradient(
                                    colors: competition.type.gradient.map { Color(hex: $0).opacity(0.3) } + [Color.clear],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
            )
        }
    }

    @ViewBuilder
    private func teamRow(team: CompetitionTeam, rank: Int) -> some View {
        let value = total(team)
        let color = competition.teamColor(team.id)
        let isMine = team.id == myTeamId
        // Only a RANKING crowns a leader. Under a goal every team that clears
        // it has done the thing, so crowning one of them invents a contest the
        // mode does not have.
        let isLeading = goal == nil && rank == 1 && value > 0
        let hitGoal = goal.map { value >= $0 } ?? false
        let members = competition.members(of: team.id)

        VStack(spacing: MADTheme.Spacing.sm) {
            HStack(spacing: MADTheme.Spacing.md) {
                if let goal {
                    Image(systemName: hitGoal ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundColor(hitGoal ? .green : .white.opacity(0.4))
                        .frame(width: 28)
                        .accessibilityLabel(hitGoal
                            ? "Goal met"
                            : "\(competition.options.formatQuantityWithUnit(max(0, goal - value))) to go")
                } else if isLeading {
                    Image(systemName: "crown.fill")
                        .font(.caption)
                        .foregroundColor(.yellow)
                        .frame(width: 24)
                } else {
                    Text("\(rank)")
                        .font(MADTheme.Typography.caption)
                        .foregroundColor(.white.opacity(0.5))
                        .frame(width: 24)
                }

                Circle()
                    .fill(color)
                    .frame(width: 10, height: 10)

                Text(team.name)
                    .font(MADTheme.Typography.callout)
                    .foregroundColor(.white)
                    .lineLimit(1)

                Spacer(minLength: 0)

                if let goal {
                    Text("\(competition.options.formatQuantity(value))/\(competition.options.goalFormatted) \(competition.options.unit.shortDisplayName)")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(hitGoal ? .green : .white.opacity(0.8))
                } else {
                    Text(competition.options.formatQuantityWithUnit(value))
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(isLeading ? .green : .white.opacity(0.8))
                }
            }

            if let goal {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.white.opacity(0.08))
                            .frame(height: 6)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(hitGoal ? Color.green : color)
                            .frame(width: geo.size.width * min(value / max(goal, 0.1), 1.0), height: 6)
                    }
                }
                .frame(height: 6)
            }

            // Who put it there. Without this the team total is a number with no
            // way to see it is right, and the tab stops answering "did my mile
            // land" — which is the question people open it with.
            VStack(spacing: 4) {
                ForEach(members) { member in
                    memberRow(member, color: color)
                }
                if members.isEmpty {
                    Text("No members yet")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.4))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.leading, 30)
        }
        .padding(MADTheme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                .fill(Color.white.opacity(isMine ? 0.1 : (isLeading ? 0.05 : 0)))
                .overlay(
                    RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                        .stroke(isMine ? color : Color.clear, lineWidth: 1)
                )
        )
    }

    private func memberRow(_ member: CompetitionUser, color: Color) -> some View {
        let value = contribution(member)
        let isMe = member.user_id == currentUserId

        return HStack(spacing: MADTheme.Spacing.sm) {
            AvatarView(name: member.displayName, imageURL: member.profile_image_url, size: 22)

            Text(member.displayName)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.75))
                .lineLimit(1)

            if isMe {
                Text("YOU")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(color))
            }

            Spacer(minLength: 0)

            Text(competition.options.formatQuantityWithUnit(value))
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(value > 0 ? 0.6 : 0.3))
        }
    }

    /// Participants without a team still compete individually — surface that
    /// rather than dropping them off a screen that only draws teams.
    private var unassignedFootnote: some View {
        HStack(spacing: 6) {
            Image(systemName: "person.fill.questionmark")
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.35))
            Text("\(competition.unassignedUsers.count) competing without a team")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.4))
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.top, 4)
    }
}
