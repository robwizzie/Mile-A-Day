import SwiftUI

struct CompetitionDetailView: View {
    @State var competition: Competition
    @ObservedObject var competitionService: CompetitionService
    @Environment(\.dismiss) var dismiss
    @StateObject private var friendService = FriendService()

    @State var showingInviteFriend = false
    @State var showingEditSettings = false
    @State var isStarting = false
    @State var isDeleting = false
    @State var showError = false
    @State var errorMessage = ""
    @State var showDeleteConfirmation = false
    @State var selectedIntervalDate: Date = Date()
    @State var showCelebration = false
    @State var podiumAnimated = false
    @State var heartsAnimated = false
    @State var raceAnimated = false

    // Flex state
    @State var isSendingAction = false
    @State var actionFeedback: ActionFeedback?

    // Remove user
    @State var showRemoveConfirmation = false
    @State var removeTargetUser: CompetitionUser?

    // Settings dropdown
    @State var showSettings = false

    // Leaderboard animation
    @State var leaderboardAnimated = false

    /// Which leaderboard row is currently expanded to show daily activity. `nil` = none.
    @State var expandedLeaderboardUserId: String?

    // Hero count-up animation
    @State var heroAnimated = false

    var body: some View {
        ZStack {
            MADTheme.Colors.appBackgroundGradient
                .ignoresSafeArea(.all)

            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: MADTheme.Spacing.lg) {
                    // Unified premium header across all states
                    premiumHero

                    // Always-visible Timeline (start/end/remaining) + Rules cards
                    // so users can read the comp at a glance no matter the state.
                    timelineCard

                    quickRulesCard

                    // Status-specific content (leaderboard / podium / participants etc.)
                    switch competition.status {
                    case .lobby, .scheduled:
                        lobbyContent
                    case .active:
                        activeContent
                    case .finished:
                        finishedContent
                    }
                }
                .padding(MADTheme.Spacing.md)
                .padding(.bottom, MADTheme.Spacing.xxl)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .navigationTitle(competition.competition_name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .sheet(isPresented: $showingInviteFriend) {
            InviteFriendView(
                competition: competition,
                competitionService: competitionService,
                friendService: friendService
            )
        }
        .sheet(isPresented: $showingEditSettings) {
            EditCompetitionSettingsView(
                competition: $competition,
                competitionService: competitionService
            )
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
        .confirmationDialog("Delete Competition?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { deleteCompetition() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This action cannot be undone.")
        }
        .alert(
            "Remove \(removeTargetUser?.displayName ?? "user")?",
            isPresented: $showRemoveConfirmation
        ) {
            Button("Remove", role: .destructive) { confirmRemoveUser() }
            Button("Cancel", role: .cancel) { removeTargetUser = nil }
        } message: {
            Text("They will be removed from the competition.")
        }
        .task {
            await refreshCompetition()
        }
        .refreshable {
            await refreshCompetition()
        }
        .onAppear {
            Task {
                await friendService.refreshAllData()
            }
        }
    }

    // MARK: - Premium Hero
    /// Unified header used across every status. Big gradient icon disc + name +
    /// status pill + activities, sized identically for lobby / active / finished
    /// so the page feels consistent regardless of which state the comp is in.
    private var premiumHero: some View {
        let typeColors = competition.type.gradient.map { Color(hex: $0) }
        let primaryColor = typeColors.first ?? MADTheme.Colors.madRed

        return VStack(spacing: 14) {
            // Icon disc with subtle pulse for active
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [primaryColor.opacity(0.35), primaryColor.opacity(0.0)],
                            center: .center,
                            startRadius: 20,
                            endRadius: 70
                        )
                    )
                    .frame(width: 120, height: 120)

                Circle()
                    .fill(
                        LinearGradient(
                            colors: typeColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 76, height: 76)
                    .overlay(
                        Circle()
                            .strokeBorder(Color.white.opacity(0.25), lineWidth: 1.5)
                    )
                    .shadow(color: primaryColor.opacity(0.45), radius: 14, x: 0, y: 6)

                Image(systemName: competition.type.icon)
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.25), radius: 4, x: 0, y: 2)
            }

            // Name
            Text(competition.competition_name)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, MADTheme.Spacing.md)

            // Status + type pills (inline)
            HStack(spacing: 8) {
                // Type chip
                HStack(spacing: 5) {
                    Text(competition.type.displayName.uppercased())
                        .font(.system(size: 11, weight: .black, design: .rounded))
                        .tracking(1.2)
                        .foregroundColor(primaryColor)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule().fill(primaryColor.opacity(0.18))
                )
                .overlay(
                    Capsule().strokeBorder(primaryColor.opacity(0.4), lineWidth: 1)
                )

                // Status chip
                HStack(spacing: 5) {
                    Circle()
                        .fill(competition.status.color)
                        .frame(width: 6, height: 6)
                    Text(competition.status.displayName.uppercased())
                        .font(.system(size: 11, weight: .black, design: .rounded))
                        .tracking(1.2)
                        .foregroundColor(competition.status.color)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule().fill(competition.status.color.opacity(0.18))
                )
                .overlay(
                    Capsule().strokeBorder(competition.status.color.opacity(0.4), lineWidth: 1)
                )

                if competition.isWinner {
                    HStack(spacing: 5) {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 10, weight: .black))
                        Text("WINNER")
                            .font(.system(size: 11, weight: .black, design: .rounded))
                            .tracking(1.2)
                    }
                    .foregroundColor(.yellow)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.yellow.opacity(0.18)))
                    .overlay(Capsule().strokeBorder(Color.yellow.opacity(0.5), lineWidth: 1))
                }
            }

            // Type description (one-liner so users instantly know how this comp works)
            Text(competition.type.description)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, MADTheme.Spacing.lg)
        }
        .padding(.top, MADTheme.Spacing.sm)
    }

    // MARK: - Timeline Card
    /// Surfaces start / end / remaining-time info that's currently scattered across
    /// status-specific subviews. Always visible above the rules so users can answer
    /// "when does this start/end?" without scrolling.
    private var timelineCard: some View {
        VStack(spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "calendar")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundColor(.white.opacity(0.55))
                Text("TIMELINE")
                    .font(.system(size: 11, weight: .black, design: .rounded))
                    .tracking(1.4)
                    .foregroundColor(.white.opacity(0.55))
                Spacer()
            }

            // Primary callout row — countdown / time-remaining / ended
            timelineCallout

            // Start + End facts
            HStack(spacing: 12) {
                timelineFact(
                    label: "Started",
                    value: competition.startDateFormatted.map(formatShortDate) ?? "—",
                    icon: "play.fill",
                    accent: .green
                )
                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 1, height: 32)
                timelineFact(
                    label: "Ends",
                    value: competition.endDateFormatted.map(formatShortDate) ?? "—",
                    icon: "flag.checkered",
                    accent: .orange
                )
            }
        }
        .padding(MADTheme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    @ViewBuilder
    private var timelineCallout: some View {
        let now = Date()
        switch competition.status {
        case .lobby:
            TimelineCallout(
                icon: "hourglass",
                accent: .orange,
                primary: "Waiting to launch",
                secondary: competition.isOwner
                    ? "Tap Start when everyone's joined"
                    : "Waiting on \(ownerDisplayName ?? "owner") to start"
            )
        case .scheduled:
            if let start = competition.startDateFormatted, start > now {
                TimelineCallout(
                    icon: "calendar.badge.clock",
                    accent: .blue,
                    primary: "Starts \(relativeShort(start, from: now))",
                    secondary: formatShortDate(start)
                )
            } else {
                TimelineCallout(icon: "calendar", accent: .blue, primary: "Scheduled", secondary: nil)
            }
        case .active:
            if let end = competition.endDateFormatted, end > now {
                TimelineCallout(
                    icon: "bolt.fill",
                    accent: .green,
                    primary: relativeShort(end, from: now) + " left",
                    secondary: "Ends \(formatShortDate(end))"
                )
            } else {
                TimelineCallout(
                    icon: "bolt.fill",
                    accent: .green,
                    primary: "In progress",
                    secondary: nil
                )
            }
        case .finished:
            TimelineCallout(
                icon: "checkmark.seal.fill",
                accent: .gray,
                primary: "Finished",
                secondary: competition.endDateFormatted.map { "Ended \(formatShortDate($0))" }
            )
        }
    }

    private func timelineFact(label: String, value: String, icon: String, accent: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(accent)
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 2) {
                Text(label.uppercased())
                    .font(.system(size: 9, weight: .heavy, design: .rounded))
                    .tracking(1.0)
                    .foregroundColor(.white.opacity(0.45))
                Text(value)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Quick Rules Card
    /// Type-aware "how this comp works" tile grid. Replaces the buried info dropdown
    /// with something always visible. Each tile is icon + small label + bold value.
    private var quickRulesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "list.bullet.rectangle")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundColor(.white.opacity(0.55))
                Text("RULES")
                    .font(.system(size: 11, weight: .black, design: .rounded))
                    .tracking(1.4)
                    .foregroundColor(.white.opacity(0.55))
                Spacer()
            }

            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10)
            ], spacing: 10) {
                ForEach(ruleTiles) { tile in
                    RuleTile(tile: tile)
                }
            }

            // Activities row — always last, full-width
            if !competition.workouts.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "figure.run")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white.opacity(0.5))
                    Text("ACTIVITIES")
                        .font(.system(size: 10, weight: .heavy, design: .rounded))
                        .tracking(1.2)
                        .foregroundColor(.white.opacity(0.5))
                    Spacer()
                    HStack(spacing: 5) {
                        ForEach(competition.workouts, id: \.self) { activity in
                            HStack(spacing: 3) {
                                Image(systemName: activity.icon)
                                    .font(.system(size: 9))
                                Text(activity.displayName)
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                            }
                            .foregroundColor(activity.color)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(activity.backgroundColor))
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(MADTheme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    /// Per-type rule tiles. Each comp surface only the rules that matter to it.
    private var ruleTiles: [RuleTileData] {
        var tiles: [RuleTileData] = []
        let opts = competition.options

        switch competition.type {
        case .streaks:
            tiles.append(RuleTileData(icon: "target", label: "Daily Goal",
                value: "\(opts.goalFormatted) \(opts.unit.shortDisplayName)"))
            if let interval = opts.interval {
                tiles.append(RuleTileData(icon: "arrow.trianglehead.2.clockwise",
                    label: "Interval", value: interval.displayName))
            }
            let lives = competition.streakLives
            if lives > 0 {
                tiles.append(RuleTileData(icon: "heart.fill", label: "Lives",
                    value: "\(lives)", tint: .red))
            }
        case .apex:
            tiles.append(RuleTileData(icon: "ruler", label: "Unit",
                value: opts.unit.shortDisplayName))
            if let interval = opts.interval {
                tiles.append(RuleTileData(icon: "arrow.trianglehead.2.clockwise",
                    label: "Interval", value: interval.displayName))
            }
            if let duration = opts.durationFormatted {
                tiles.append(RuleTileData(icon: "clock.fill", label: "Duration", value: duration))
            }
        case .targets:
            tiles.append(RuleTileData(icon: "target", label: "Daily Goal",
                value: "\(opts.goalFormatted) \(opts.unit.shortDisplayName)"))
            if let interval = opts.interval {
                tiles.append(RuleTileData(icon: "arrow.trianglehead.2.clockwise",
                    label: "Interval", value: interval.displayName))
            }
            if let duration = opts.durationFormatted {
                tiles.append(RuleTileData(icon: "clock.fill", label: "Duration", value: duration))
            }
        case .clash:
            tiles.append(RuleTileData(icon: "ruler", label: "Unit",
                value: opts.unit.shortDisplayName))
            if opts.first_to > 0 {
                tiles.append(RuleTileData(icon: "star.fill", label: "First To",
                    value: "\(opts.first_to)", tint: .yellow))
            }
            if let interval = opts.interval {
                tiles.append(RuleTileData(icon: "arrow.trianglehead.2.clockwise",
                    label: "Interval", value: interval.displayName))
            }
        case .race:
            tiles.append(RuleTileData(icon: "flag.checkered", label: "Distance Goal",
                value: "\(opts.goalFormatted) \(opts.unit.shortDisplayName)"))
        }

        // Always tail with participant count for awareness
        tiles.append(RuleTileData(icon: "person.2.fill", label: "Players",
            value: "\(competition.acceptedUsersCount)"))

        return tiles
    }

    private var ownerDisplayName: String? {
        competition.users.first(where: { $0.user_id == competition.owner })?.displayName
    }

    private func formatShortDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy"
        return f.string(from: date)
    }

    /// Compact "2d 4h" style remaining-time string.
    private func relativeShort(_ date: Date, from now: Date) -> String {
        let total = max(0, date.timeIntervalSince(now))
        let days = Int(total) / 86_400
        let hours = (Int(total) % 86_400) / 3_600
        let mins = (Int(total) % 3_600) / 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(mins)m" }
        return "\(mins)m"
    }

    // MARK: - Rank Ordinal Helper
    func rankOrdinal(_ rank: Int) -> String {
        switch rank {
        case 1: return "1st"
        case 2: return "2nd"
        case 3: return "3rd"
        default: return "\(rank)th"
        }
    }
}

// MARK: - Supporting Hero / Rules / Timeline Components

/// Plain data for a Rules grid tile — keeps the per-type tile build code declarative.
struct RuleTileData: Identifiable {
    let icon: String
    let label: String
    let value: String
    var tint: Color = .white
    var id: String { label }
}

struct RuleTile: View {
    let tile: RuleTileData

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(tile.tint == .white ? Color.white.opacity(0.12) : tile.tint.opacity(0.2))
                    .frame(width: 32, height: 32)
                Image(systemName: tile.icon)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(tile.tint == .white ? .white.opacity(0.85) : tile.tint)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(tile.label.uppercased())
                    .font(.system(size: 9, weight: .heavy, design: .rounded))
                    .tracking(1.0)
                    .foregroundColor(.white.opacity(0.5))
                    .lineLimit(1)
                Text(tile.value)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }
}

/// Big readable callout inside the Timeline card. One per state.
struct TimelineCallout: View {
    let icon: String
    let accent: Color
    let primary: String
    let secondary: String?

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(accent.opacity(0.2))
                    .frame(width: 42, height: 42)
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(accent)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(primary)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let secondary {
                    Text(secondary)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.55))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(accent.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(accent.opacity(0.3), lineWidth: 1)
                )
        )
    }
}
