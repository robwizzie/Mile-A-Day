import SwiftUI

// MARK: - Main Tabbed Card
// Combines Today's Race / Standings / Flex into one tabbed container. Replaces
// the separate stacked hero + leaderboard + interval-content blocks so the
// most actionable view (today's race) is always one tap from view.

enum CompetitionMainTab: String, CaseIterable, Identifiable {
    case todayRace
    case standings
    case flex

    var id: String { rawValue }

    var label: String {
        switch self {
        case .todayRace: return "Today"
        case .standings: return "Standings"
        case .flex: return "Flex"
        }
    }

    var icon: String {
        switch self {
        case .todayRace: return "bolt.fill"
        case .standings: return "trophy.fill"
        case .flex: return "hand.raised.fill"
        }
    }
}

extension CompetitionDetailView {

    // MARK: - Default tab per mode
    /// Streaks and Race default to Standings because their "today" view is
    /// just goal-met-or-not; the leaderboard reads first. Clash/Apex/Targets
    /// default to Today since the daily race is the headline.
    static func defaultMainTab(for type: CompetitionType) -> CompetitionMainTab {
        switch type {
        case .clash, .apex, .targets: return .todayRace
        case .streaks, .race: return .standings
        }
    }

    // MARK: - Main Tabbed Card
    var mainTabbedCard: some View {
        VStack(spacing: MADTheme.Spacing.md) {
            todayMotivationCallout
            mainTabSelector

            Group {
                switch selectedMainTab {
                case .todayRace:
                    todayRaceTabContent
                case .standings:
                    standingsTabContent
                case .flex:
                    flexSection
                }
            }
            .transition(.opacity)
        }
    }

    // MARK: - Today's Motivation Callout
    /// Always-visible single-line summary of "you vs the leader today".
    /// Stays put across tab switches so the primary motivation hook never
    /// disappears. Mode-specific phrasing.
    @ViewBuilder
    var todayMotivationCallout: some View {
        let currentUserId = UserDefaults.standard.string(forKey: "backendUserId")
        let accepted = competition.users.filter { $0.invite_status == .accepted }
        let me = accepted.first(where: { $0.user_id == currentUserId })
        let todayKey = intervalKey(for: Date())
        let myToday = me?.intervals?[todayKey] ?? 0

        switch competition.type {
        case .clash, .apex:
            let opponents = accepted.filter { $0.user_id != currentUserId }
            if let leader = opponents.max(by: { ($0.intervals?[todayKey] ?? 0) < ($1.intervals?[todayKey] ?? 0) }) {
                let leaderToday = leader.intervals?[todayKey] ?? 0
                clashApexCallout(me: me, myToday: myToday, leader: leader, leaderToday: leaderToday)
            } else {
                soloCallout(myToday: myToday)
            }
        case .targets:
            targetsCallout(myToday: myToday)
        case .streaks:
            streaksCallout(me: me, myToday: myToday)
        case .race:
            raceCallout(me: me)
        }
    }

    @ViewBuilder
    private func clashApexCallout(me: CompetitionUser?, myToday: Double, leader: CompetitionUser, leaderToday: Double) -> some View {
        let diff = myToday - leaderToday
        let unit = competition.options.unit.shortDisplayName

        if leaderToday == 0 && myToday == 0 {
            calloutBubble(icon: "figure.run", tint: .white.opacity(0.5),
                          title: "No activity yet today",
                          subtitle: "Be the first to put miles on the board.")
        } else if diff >= 0 && myToday > 0 {
            calloutBubble(icon: "crown.fill", tint: .green,
                          title: "You're leading today by \(String(format: "%.2f", diff)) \(unit)",
                          subtitle: "Keep the gap open — they could close it.")
        } else {
            let gap = abs(diff)
            calloutBubble(icon: "bolt.fill", tint: .orange,
                          title: "You're \(String(format: "%.2f", gap)) \(unit) behind \(leader.displayName) today",
                          subtitle: "Run \(String(format: "%.2f", gap)) \(unit) more to take the lead.")
        }
    }

    @ViewBuilder
    private func targetsCallout(myToday: Double) -> some View {
        let goal = competition.options.goal
        let unit = competition.options.unit.shortDisplayName
        if myToday >= goal {
            calloutBubble(icon: "target", tint: .green,
                          title: "Target hit — \(String(format: "%.2f", myToday)) \(unit) today",
                          subtitle: "Point locked in for this interval.")
        } else {
            let remaining = max(0, goal - myToday)
            calloutBubble(icon: "target", tint: .orange,
                          title: "\(String(format: "%.2f", remaining)) \(unit) to hit today's target",
                          subtitle: "Hit \(competition.options.goalFormatted) \(unit) to earn the point.")
        }
    }

    @ViewBuilder
    private func streaksCallout(me: CompetitionUser?, myToday: Double) -> some View {
        let goal = competition.options.goal
        let unit = competition.options.unit.shortDisplayName
        let lives = me?.remaining_lives ?? competition.streakLives
        if myToday >= goal {
            calloutBubble(icon: "flame.fill", tint: .green,
                          title: "Streak safe — \(String(format: "%.2f", myToday)) \(unit) done",
                          subtitle: "\(lives) \(lives == 1 ? "life" : "lives") in the bank.")
        } else {
            let remaining = max(0, goal - myToday)
            calloutBubble(icon: "flame.fill", tint: .orange,
                          title: "\(String(format: "%.2f", remaining)) \(unit) left today",
                          subtitle: "Miss it and you lose a life. \(lives) left.")
        }
    }

    @ViewBuilder
    private func raceCallout(me: CompetitionUser?) -> some View {
        let total = me?.score ?? 0
        let goal = competition.options.goal
        let pct = goal > 0 ? min(100, Int((total / goal) * 100)) : 0
        let unit = competition.options.unit.shortDisplayName
        let remaining = max(0, goal - total)
        if total >= goal {
            calloutBubble(icon: "flag.checkered", tint: .green,
                          title: "You finished the race!",
                          subtitle: "\(String(format: "%.1f", total)) \(unit) total.")
        } else {
            calloutBubble(icon: "flag.checkered", tint: .orange,
                          title: "\(pct)% there — \(String(format: "%.1f", remaining)) \(unit) to go",
                          subtitle: "Total: \(String(format: "%.1f", total)) of \(competition.options.goalFormatted) \(unit).")
        }
    }

    @ViewBuilder
    private func soloCallout(myToday: Double) -> some View {
        if myToday > 0 {
            calloutBubble(icon: "checkmark.circle.fill", tint: .green,
                          title: "\(String(format: "%.2f", myToday)) \(competition.options.unit.shortDisplayName) today",
                          subtitle: "Solo run — invite a friend to make it a race.")
        } else {
            calloutBubble(icon: "figure.run", tint: .white.opacity(0.5),
                          title: "No activity yet today",
                          subtitle: "Solo run — invite a friend to make it a race.")
        }
    }

    private func calloutBubble(icon: String, tint: Color, title: String, subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.18))
                    .frame(width: 32, height: 32)
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(tint)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(subtitle)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.55))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(tint.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(tint.opacity(0.25), lineWidth: 1)
                )
        )
    }

    // MARK: - Tab Selector
    var mainTabSelector: some View {
        HStack(spacing: 4) {
            ForEach(CompetitionMainTab.allCases) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        selectedMainTab = tab
                    }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 11, weight: .heavy))
                        Text(tab.label)
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                    }
                    .foregroundColor(selectedMainTab == tab ? .white : .white.opacity(0.5))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(selectedMainTab == tab ? Color.white.opacity(0.12) : Color.clear)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    // MARK: - Today's Race Tab Content
    @ViewBuilder
    var todayRaceTabContent: some View {
        let key = intervalKey(for: selectedIntervalDate)
        let acceptedUsers = competition.users.filter { $0.invite_status == .accepted }
        let currentUserId = UserDefaults.standard.string(forKey: "backendUserId")

        VStack(spacing: MADTheme.Spacing.md) {
            // Interval navigator stays at the top of this tab so users can
            // page back through past intervals if they want to (e.g. catch up
            // on yesterday's results after the new interval starts).
            intervalNavigator

            switch competition.type {
            case .clash:
                clashIntervalView(key: key, users: acceptedUsers, currentUserId: currentUserId)
            case .apex:
                apexIntervalView(key: key, users: acceptedUsers, currentUserId: currentUserId)
            case .targets:
                targetsIntervalView(key: key, users: acceptedUsers, currentUserId: currentUserId)
            case .streaks:
                streaksTodayView(key: key, users: acceptedUsers, currentUserId: currentUserId)
            case .race:
                raceProgressView
            }
        }
    }

    /// Per-user goal-hit status for the selected day in a streaks comp. The
    /// existing `intervalContent` returns EmptyView for streaks because the
    /// monthly calendar covers it, but inside the Today's tab we want a fast
    /// "who's locked in for the day" list.
    func streaksTodayView(key: String, users: [CompetitionUser], currentUserId: String?) -> some View {
        let goal = competition.options.goal
        let sortedUsers = users.sorted {
            // hit-goal users first, then by today's miles desc
            let aHit = ($0.intervals?[key] ?? 0) >= goal
            let bHit = ($1.intervals?[key] ?? 0) >= goal
            if aHit != bHit { return aHit && !bHit }
            return ($0.intervals?[key] ?? 0) > ($1.intervals?[key] ?? 0)
        }

        return VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
            Text("Today's Status")
                .font(MADTheme.Typography.title3)
                .foregroundColor(.white)
                .padding(.horizontal, MADTheme.Spacing.sm)

            VStack(spacing: MADTheme.Spacing.sm) {
                ForEach(sortedUsers, id: \.id) { user in
                    let distance = user.intervals?[key] ?? 0
                    let hitGoal = distance >= goal
                    let isEliminated = (user.remaining_lives ?? competition.streakLives) <= 0

                    HStack(spacing: MADTheme.Spacing.md) {
                        Image(systemName: hitGoal ? "flame.fill" : (isEliminated ? "xmark.circle.fill" : "circle"))
                            .font(.system(size: 16))
                            .foregroundColor(hitGoal ? .orange : (isEliminated ? .red.opacity(0.5) : .white.opacity(0.25)))
                            .frame(width: 24)

                        AvatarView(name: user.displayName, imageURL: user.profile_image_url, size: 36)
                            .opacity(isEliminated ? 0.4 : 1.0)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(user.displayName)
                                .font(MADTheme.Typography.callout)
                                .foregroundColor(.white.opacity(isEliminated ? 0.4 : 1.0))
                            if isEliminated {
                                Text("OUT")
                                    .font(.system(size: 9, weight: .heavy, design: .rounded))
                                    .foregroundColor(.red.opacity(0.8))
                            } else if hitGoal {
                                Text("Streak safe")
                                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                                    .foregroundColor(.green.opacity(0.8))
                            } else {
                                Text(String(format: "%.2f / %@ %@",
                                            distance,
                                            competition.options.goalFormatted,
                                            competition.options.unit.shortDisplayName))
                                    .font(.system(size: 10, weight: .medium, design: .rounded))
                                    .foregroundColor(.white.opacity(0.5))
                            }
                        }

                        Spacer()

                        if let lives = user.remaining_lives {
                            HStack(spacing: 2) {
                                ForEach(0..<min(competition.streakLives, 6), id: \.self) { i in
                                    Image(systemName: i < lives ? "heart.fill" : "heart")
                                        .font(.system(size: 8))
                                        .foregroundColor(i < lives ? .red : .white.opacity(0.15))
                                }
                            }
                        }
                    }
                    .padding(MADTheme.Spacing.md)
                    .background(
                        RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                            .fill(Color.white.opacity(user.user_id == currentUserId ? 0.1 : 0))
                            .overlay(
                                RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                                    .stroke(user.user_id == currentUserId ? MADTheme.Colors.primary : Color.clear, lineWidth: 1)
                            )
                    )
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

    // MARK: - Standings Tab Content
    var standingsTabContent: some View {
        enhancedLeaderboard
    }
}
