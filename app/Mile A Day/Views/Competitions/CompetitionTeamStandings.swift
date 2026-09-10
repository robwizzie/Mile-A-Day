import SwiftUI

// MARK: - Team Standings
// The FINISHED screen's team results card (`CompetitionDetailView+Finished`).
// A team is scored SERVER-SIDE as one competitor over its members' combined
// miles — never as a sum of their individual scores — so member rows show what
// each person CONTRIBUTED rather than points that wouldn't add up. Tap a team
// to expand them.
//
// The LIVE standings tab uses `teamLeaderboard` instead, which folds this and
// the individual leaderboard into one card: shown together they were two
// leaderboards on one screen disagreeing about who was winning.

struct CompetitionTeamStandings: View {
    let competition: Competition
    var isFinished: Bool = false

    @State private var expandedTeamId: String?

    private var ranked: [CompetitionTeam] { competition.rankedTeams }
    private var topScore: Double { max(ranked.first?.score ?? 0, 0.001) }

    var body: some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
            // Section header
            HStack(spacing: MADTheme.Spacing.sm) {
                Image(systemName: "person.3.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(
                        LinearGradient(colors: [MADTheme.Colors.madRed, .orange], startPoint: .top, endPoint: .bottom)
                    )
                Text(isFinished ? "Team Results" : "Team Standings")
                    .font(MADTheme.Typography.title3)
                    .foregroundColor(.white)

                Spacer()

                Text("\(ranked.count) teams")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.35))
            }
            .padding(.horizontal, MADTheme.Spacing.sm)

            VStack(spacing: 6) {
                ForEach(Array(ranked.enumerated()), id: \.element.id) { index, team in
                    teamRow(team: team, rank: index + 1)
                }

                if !competition.unassignedUsers.isEmpty {
                    unassignedFootnote
                }
            }
            .padding(MADTheme.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
            )
        }
    }

    @ViewBuilder
    private func teamRow(team: CompetitionTeam, rank: Int) -> some View {
        let members = competition.members(of: team.id)
        let color = competition.teamColor(team.id)
        let isExpanded = expandedTeamId == team.id
        let isLeading = rank == 1 && (team.score ?? 0) > 0

        VStack(spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                    expandedTeamId = isExpanded ? nil : team.id
                }
            } label: {
                VStack(spacing: 8) {
                    HStack(spacing: MADTheme.Spacing.sm) {
                        // Rank
                        Text("\(rank)")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundColor(isLeading ? .yellow : .white.opacity(0.55))
                            .frame(width: 20)

                        Circle()
                            .fill(color)
                            .frame(width: 10, height: 10)

                        Text(team.name)
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                            .lineLimit(1)

                        if isLeading && isFinished {
                            Image(systemName: "crown.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.yellow)
                        }

                        Spacer()

                        // Stacked member avatars
                        HStack(spacing: -8) {
                            ForEach(members.prefix(4)) { member in
                                AvatarView(name: member.displayName, imageURL: member.profile_image_url, size: 22)
                                    .overlay(Circle().stroke(Color.black.opacity(0.4), lineWidth: 1))
                            }
                        }
                        if members.count > 4 {
                            Text("+\(members.count - 4)")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundColor(.white.opacity(0.45))
                        }

                        // Streaks: the pool of lives belongs to the TEAM, and
                        // a team that has spent one is the only thing on this
                        // row that says the standing is fragile.
                        if competition.type == .streaks, let lives = team.remaining_lives {
                            TeamLivesChip(lives: lives)
                        }

                        Text(competition.teamScoreLabel(team))
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundColor(isLeading ? .yellow : .white.opacity(0.85))

                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white.opacity(0.3))
                            .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    }

                    // Relative score bar — makes the gap between teams glanceable.
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.07))
                            Capsule()
                                .fill(color)
                                .frame(width: geo.size.width * CGFloat(min((team.score ?? 0) / topScore, 1.0)))
                        }
                    }
                    .frame(height: 4)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 10)
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(spacing: 4) {
                    if members.isEmpty {
                        Text("No members yet")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.4))
                            .padding(.vertical, 6)
                    }
                    ForEach(members) { member in
                        memberRow(member)
                    }
                }
                .padding(.leading, 30)
                .padding(.trailing, 10)
                .padding(.bottom, 8)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                .fill(Color.white.opacity(isExpanded ? 0.05 : 0))
        )
    }

    private func memberRow(_ member: CompetitionUser) -> some View {
        let isMe = member.user_id == UserDefaults.standard.string(forKey: "backendUserId")
        return HStack(spacing: MADTheme.Spacing.sm) {
            AvatarView(name: member.displayName, imageURL: member.profile_image_url, size: 24)
            Text(member.displayName)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.9))
            if isMe {
                Text("YOU")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(MADTheme.Colors.madRed))
            }
            Spacer()
            Text(competition.memberScoreLabel(member))
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.6))
        }
        .padding(.vertical, 3)
    }

    /// Participants without a team still compete individually — surface that
    /// instead of hiding them.
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

// MARK: - Score formatting

// The three score formatters below LIVED HERE and moved to Models/Competition.swift.
// `stickerSummary` needs `memberScoreLabel` so the post sticker and this
// leaderboard describe the same person's contribution identically, and a
// Models/ file may also be a Watch target member — a dependency reaching from
// there into Views/ compiles on iPhone and fails the Watch with "Cannot find
// 'memberScoreLabel' in scope", which neither CI workflow would catch (ios.md).
// Everything they need (`options.formatQuantityWithUnit`, `type`) was already
// on the model.
