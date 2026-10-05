import SwiftUI

// MARK: - Standings row
//
// THE row. Every board — the live standings tab, a team's roster, the finished
// screen's full table, the streak board — draws this one, so a competitor
// cannot look like two different people on two screens of the same
// competition. It replaces `CompetitionLeaderboardRow`, which had grown a
// medal-gradient rank circle, a gradient avatar ring, an inline badge cluster
// and a per-row rounded background with its own stroke: five decorations
// around two numbers.
//
// What a row has to say, in order of how hard the eye has to work for it:
//   1. the place        — the rank, left, medal-tinted for the top three
//   2. who              — avatar + name
//   3. the score        — right, heavy, monospaced digits
//   4. by how much      — the bar, relative to the leader
//   5. how far they went — under the name, because on a points competition
//                          that number is what BREAKS TIES (see
//                          `Competition.ranked`), and a board whose order looks
//                          arbitrary is a board nobody trusts. It is the
//                          explanation of the ordering, so it is never hidden.

/// What a standings row is measured in.
enum CompeteStandingsMetric {
    /// The competition's own score — points, days or distance. The right
    /// answer whenever PEOPLE are the competitors.
    case score
    /// What this person put into their team's combined total, in the
    /// competition's distance unit.
    ///
    /// The only honest per-person figure in a TEAM competition. A member's
    /// `score` there is computed under individual scoring: it does not sum to
    /// their team's number, and it contradicts it — on the competition this
    /// was reported from, the person with the most points (3) had walked
    /// FEWER miles than the person with 2, and a list ranked that way put
    /// members of the losing team above members of the winning one, under a
    /// heading that looked like a second set of standings for the same
    /// competition. Points belong to the team; miles belong to the person.
    case contribution
}

struct CompeteStandingsRow: View {
    let place: Int
    let user: CompetitionUser
    let competition: Competition
    let isCurrentUser: Bool
    /// Which figure this row reports. Team competitions pass `.contribution`.
    var metric: CompeteStandingsMetric = .score
    /// The leader's value in the same metric, for the bar. Zero draws empty track.
    var leaderScore: Double = 0
    /// True when this place is SHARED — more than one competitor holds it,
    /// because the chain in `Competition.ranked` ran out and they are
    /// genuinely level. Both rows of a tie carry it: marking only the second
    /// drew "4" directly above "T4".
    var isTied: Bool = false
    /// Focus state from the host (tapping a row focuses the activity calendar).
    var isFocused: Bool = false
    var onManualTap: (() -> Void)? = nil

    @State private var showingManualInfo = false

    private var accent: Color { CompeteDesign.accent(competition.type) }

    /// The figure this row is ranked and labelled by.
    private var value: Double {
        switch metric {
        case .score: return user.score ?? 0
        case .contribution: return user.contributionValue
        }
    }

    /// The team this person walked for, when the competition has teams. Drawn
    /// as a colour dot + name, because a people-board in a team competition
    /// that doesn't say whose side anyone is on is a list of strangers.
    private var team: CompetitionTeam? {
        guard competition.hasTeams else { return nil }
        return competition.team(for: user.user_id)
    }

    private var isEliminated: Bool {
        guard competition.type == .streaks, competition.streakLives > 0,
              let lives = user.remaining_lives else { return false }
        return lives <= 0
    }

    /// Apex and Race are SCORED in distance, so the distance line under the
    /// name would restate the score; steps competitions don't track miles.
    /// Everywhere else it is the number the ordering rests on.
    private var showsDistance: Bool {
        // In contribution mode the distance IS the headline figure on the
        // right; repeating it under the name would print it twice.
        guard metric == .score else { return false }
        guard competition.options.unit != .steps, user.intervals != nil else { return false }
        switch competition.type {
        case .streaks, .targets, .clash: return true
        case .apex, .race: return false
        }
    }

    private var distanceText: String {
        let total = user.totalIntervalDistance
        let figure = total >= 100 ? String(format: "%.0f", total) : String(format: "%.1f", total)
        return "\(figure) \(competition.options.unit.shortDisplayName)"
    }

    private var scoreText: String {
        if metric == .contribution {
            return competition.options.formatQuantityWithUnit(value)
        }
        switch competition.type {
        case .streaks: return "\(Int(value))d"
        case .apex, .race:
            return String(format: "%.1f %@", value, competition.options.unit.shortDisplayName)
        case .targets, .clash:
            return "\(Int(value)) pt\(Int(value) == 1 ? "" : "s")"
        }
    }

    var body: some View {
        HStack(spacing: 11) {
            CompeteRankBadge(place: place, isTied: isTied)

            AvatarView(name: user.displayName, imageURL: user.profile_image_url, size: 38)
                .opacity(isEliminated ? 0.45 : 1)
                .overlay(
                    Circle().strokeBorder(
                        isCurrentUser ? accent.opacity(0.9) : CompeteDesign.hairline,
                        lineWidth: isCurrentUser ? 2 : 1
                    )
                )

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 5) {
                    Text(user.displayName)
                        .font(CompeteDesign.name)
                        .foregroundColor(isEliminated ? CompeteDesign.inkGhost : CompeteDesign.ink)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    if isCurrentUser { CompeteTag(text: "YOU", color: accent) }
                    if isEliminated { CompeteTag(text: "OUT", color: .red, filled: false) }
                    if let team {
                        CompeteTag(
                            text: team.name,
                            color: competition.teamColor(team.id),
                            filled: false
                        )
                    }
                    // The manual-entry badge rides the NAME, not the row. In
                    // the row it sat between the bar and the score, so the one
                    // row that had it got a shorter bar than every other row
                    // and the column visibly stepped in at that line.
                    if user.has_manual_workouts == true { manualBadge }
                }

                // The bar and the supporting figure share a line: the bar is
                // the comparison, the figure is the receipt for it.
                HStack(spacing: 8) {
                    CompeteBar(
                        fraction: leaderScore > 0 ? value / leaderScore : 0,
                        color: isEliminated ? CompeteDesign.inkGhost : (place == 1 ? accent : accent.opacity(0.55)),
                        isEmpty: value <= 0
                    )

                    if showsDistance {
                        Text(distanceText)
                            .font(CompeteDesign.detail)
                            .foregroundColor(CompeteDesign.inkFaint)
                            .monospacedDigit()
                            .lineLimit(1)
                            // A minimum width, trailing-aligned, so the figures
                            // line up as a COLUMN. Sized to content alone,
                            // "7.5 mi" and "28.4 mi" end at different x and the
                            // bars beside them end at different lengths, which
                            // reads as a ragged table. Safe to constrain: a
                            // distance is bounded by how far a person can walk,
                            // unlike a username.
                            .frame(minWidth: 52, alignment: .trailing)
                            .fixedSize()
                    }
                }

                if competition.type == .streaks, competition.streakLives > 0,
                   let lives = user.remaining_lives, !isEliminated {
                    livesRow(lives: lives)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(scoreText)
                .font(CompeteDesign.score)
                .foregroundColor(
                    isEliminated ? CompeteDesign.inkGhost
                        : (place == 1 ? (CompeteDesign.medal(1) ?? .white) : CompeteDesign.ink)
                )
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: CompeteDesign.innerRadius, style: .continuous)
                .fill(isFocused ? Color.white.opacity(0.05) : Color.clear)
        )
        .sheet(isPresented: $showingManualInfo) {
            ManualWorkoutsInfoSheet(user: user)
                .presentationDetents([.fraction(0.4), .medium])
        }
    }

    private func livesRow(lives: Int) -> some View {
        HStack(spacing: 2) {
            ForEach(0..<min(competition.streakLives, 6), id: \.self) { index in
                Image(systemName: index < lives ? "heart.fill" : "heart")
                    .font(.system(size: 8))
                    .foregroundColor(index < lives ? .red.opacity(0.85) : CompeteDesign.inkGhost)
            }
            if competition.streakLives > 6 {
                Text("+\(competition.streakLives - 6)")
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .foregroundColor(CompeteDesign.inkGhost)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(lives) of \(competition.streakLives) lives left")
    }

    private var manualBadge: some View {
        Button {
            if let onManualTap { onManualTap() } else { showingManualInfo = true }
        } label: {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(MADTheme.Colors.warning)
                .frame(width: 18, height: 18)
                .background(Circle().fill(MADTheme.Colors.warning.opacity(0.16)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Some workouts were entered by hand")
    }
}
