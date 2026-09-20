import SwiftUI

// MARK: - Team results
//
// The table a TEAM competition is actually decided on, and the one block both
// the live Standings tab and the finished screen draw it with.
//
// A team is scored SERVER-SIDE as one competitor over its members' combined
// quantity — never as a sum of their individual scores (`usesTeamEntityScoring`)
// — so a member row shows what that person CONTRIBUTED. Their own points would
// not add up to their team's number, and "Team 2 · 5 pts" over "Aaron 2 pts,
// dave 2 pts" reads as arithmetic that got away from us.
//
// On the FINISHED screen every roster is open. A final result that makes you
// tap each team to find out who was on it, and tap again to see how far they
// went, is withholding the two facts the screen exists to deliver; the
// competition is over, there is nothing left to progressively disclose. Live,
// the rosters collapse, because there the score is what moves and the roster
// is reference.

// MARK: Finished screen

struct CompetitionTeamResults: View {
    let competition: Competition

    private var standings: [(place: Int, team: CompetitionTeam)] {
        competition.rankedTeamStandings
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
            CompeteHeader(
                eyebrow: "Team Results",
                trailingText: "\(standings.count) team\(standings.count == 1 ? "" : "s")"
            )
            .padding(.horizontal, 2)

            CompeteSurface {
                VStack(spacing: 0) {
                    ForEach(Array(standings.enumerated()), id: \.element.team.id) { index, entry in
                        if index > 0 {
                            CompeteRowRule().padding(.vertical, 13)
                        }
                        CompeteTeamBlock(
                            competition: competition,
                            team: entry.team,
                            place: entry.place,
                            leaderScore: standings.first?.team.score ?? 0,
                            isTied: standings.filter { $0.place == entry.place }.count > 1,
                            rosterMode: .always,
                            isFinished: true
                        )
                    }

                    if !competition.unassignedUsers.isEmpty {
                        CompeteRowRule().padding(.vertical, 13)
                        unassignedFootnote
                    }
                }
            }
        }
    }

    /// Participants without a team still competed — say so rather than leaving
    /// them off a results screen entirely.
    private var unassignedFootnote: some View {
        let count = competition.unassignedUsers.count
        return Text("\(count) \(count == 1 ? "person" : "people") competed without a team — they're in the list below.")
            .font(CompeteDesign.caption)
            .foregroundColor(CompeteDesign.inkFaint)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Team block

/// One team: its place, its name, what it scored, and who put that together.
struct CompeteTeamBlock: View {
    enum RosterMode {
        /// Finished screen — the roster is part of the result.
        case always
        /// Live standings — the roster collapses behind the team's own row.
        case collapsible
    }

    let competition: Competition
    let team: CompetitionTeam
    let place: Int
    let leaderScore: Double
    var isTied: Bool = false
    var rosterMode: RosterMode = .collapsible
    var isFinished: Bool = false
    /// Live standings keeps collapse state on the host, so switching tabs
    /// doesn't silently reopen every team.
    var isExpanded: Bool = true
    var onToggle: (() -> Void)? = nil

    private var color: Color { competition.teamColor(team.id) }
    private var members: [CompetitionUser] { competition.members(of: team.id) }
    private var showsRoster: Bool { rosterMode == .always || isExpanded }

    /// The team's combined distance, or nil when this competition can't say.
    ///
    /// `quantity` is the figure the server scored the team on — but a
    /// `legacy_team_scoring` competition (one decided under the old
    /// sum-of-member-scores rule, stamped at migration 0061) is served with
    /// neither `quantity` NOR `team_contribution`, so both this and the member
    /// rows would confidently print "0.0 mi". A number we don't have is not
    /// zero; the line is omitted instead.
    private var combinedQuantity: Double? {
        if let quantity = team.quantity { return quantity }
        let contributions = members.compactMap { $0.teamRankValue }
        guard !contributions.isEmpty else { return nil }
        return contributions.reduce(0, +)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            header
            if showsRoster { roster }
        }
    }

    // MARK: Header

    private var header: some View {
        Group {
            if rosterMode == .collapsible, let onToggle {
                Button(action: onToggle) { headerContent }
                    .buttonStyle(.plain)
            } else {
                headerContent
            }
        }
    }

    private var headerContent: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 11) {
                CompeteRankBadge(place: place, isTied: isTied, size: 28)

                Circle()
                    .fill(color)
                    .frame(width: 9, height: 9)
                    .accessibilityHidden(true)

                Text(team.name)
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .foregroundColor(CompeteDesign.ink)
                    .lineLimit(1)
                    .truncationMode(.tail)

                if place == 1 && isFinished && (team.score ?? 0) > 0 {
                    CompeteTag(text: "WON", color: CompeteDesign.medal(1) ?? .yellow)
                }

                if competition.type == .streaks, let lives = team.remaining_lives {
                    TeamLivesChip(lives: lives)
                }

                Spacer(minLength: 6)

                Text(competition.teamScoreLabel(team))
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .foregroundColor(place == 1 ? (CompeteDesign.medal(1) ?? .yellow) : CompeteDesign.ink)
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize()

                if rosterMode == .collapsible {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(CompeteDesign.inkGhost)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        .accessibilityHidden(true)
                }
            }

            CompeteBar(
                fraction: leaderScore > 0 ? (team.score ?? 0) / leaderScore : 0,
                color: color,
                height: 5,
                isEmpty: (team.score ?? 0) <= 0
            )

            // The one line that says what the team physically did. The score
            // above it is the competition's currency (days, points); this is
            // the distance those points were bought with, and on a team screen
            // it is the number the member rows sum to.
            HStack(spacing: 4) {
                if let combinedQuantity {
                    Text(competition.options.formatQuantityWithUnit(combinedQuantity))
                        .font(CompeteDesign.detail)
                        .foregroundColor(CompeteDesign.inkMuted)
                        .monospacedDigit()
                    Text("together")
                        .font(CompeteDesign.detail)
                        .foregroundColor(CompeteDesign.inkFaint)
                    Text("·")
                        .foregroundColor(CompeteDesign.inkGhost)
                }
                Text("\(members.count) \(members.count == 1 ? "member" : "members")")
                    .font(CompeteDesign.detail)
                    .foregroundColor(CompeteDesign.inkFaint)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
    }

    // MARK: Roster

    private var roster: some View {
        VStack(spacing: 0) {
            if members.isEmpty {
                Text("Nobody joined this team.")
                    .font(CompeteDesign.detail)
                    .foregroundColor(CompeteDesign.inkFaint)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
            }

            ForEach(Array(members.enumerated()), id: \.element.id) { index, member in
                memberRow(member, rank: index + 1, topContribution: members.first?.teamRankValue ?? 0)
                    .padding(.vertical, 6)

                if index < members.count - 1 {
                    CompeteRowRule(inset: 34)
                }
            }
        }
        .padding(.leading, 12)
        .padding(.top, 2)
        .overlay(alignment: .leading) {
            // A colour rail ties the roster to its team without repeating the
            // team's name on every line.
            Capsule()
                .fill(color.opacity(0.35))
                .frame(width: 2)
                .padding(.vertical, 2)
                .accessibilityHidden(true)
        }
    }

    private func memberRow(_ member: CompetitionUser, rank: Int, topContribution: Double) -> some View {
        let isMe = member.user_id == UserDefaults.standard.string(forKey: "backendUserId")
        let contribution = member.teamRankValue ?? 0

        return HStack(spacing: 9) {
            AvatarView(name: member.displayName, imageURL: member.profile_image_url, size: 26)
                .overlay(
                    Circle().strokeBorder(
                        isMe ? CompeteDesign.accent(competition.type).opacity(0.9) : CompeteDesign.hairline,
                        lineWidth: isMe ? 1.5 : 1
                    )
                )

            Text(member.displayName)
                .font(CompeteDesign.nameSmall)
                .foregroundColor(CompeteDesign.ink.opacity(0.92))
                .lineLimit(1)
                .truncationMode(.tail)

            if isMe { CompeteTag(text: "YOU", color: CompeteDesign.accent(competition.type)) }

            // Who carried it. Only worth saying on a team of more than one,
            // and only when they actually did something.
            if rank == 1, members.count > 1, contribution > 0 {
                CompeteTag(text: "TOP", color: color, filled: false)
            }

            Spacer(minLength: 6)

            // Each member's own distance — the thing a team result is asked
            // for and the reason these rows exist.
            Text(competition.memberScoreLabel(member))
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(CompeteDesign.inkMuted)
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()
        }
    }
}
