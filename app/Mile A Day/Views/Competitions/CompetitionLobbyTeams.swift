import SwiftUI

// MARK: - Lobby Teams Section
// Team setup lives in the lobby (and scheduled state) — the server locks
// teams once the competition starts. Owners get the full manager: create/
// rename/delete teams, assign members, Randomize/Balance, and the
// "members pick their own team" toggle. Non-owners see the rosters, plus
// Join/Switch buttons when member-pick is on. Stat badges show each
// runner's recent form (14-day average matched to the comp's activities
// and interval) so Balance decisions are transparent.

struct CompetitionLobbyTeamsSection: View {
    @Binding var competition: Competition
    @ObservedObject var competitionService: CompetitionService

    @State private var stats: TeamStatsResponse?
    @State private var isWorking = false
    @State private var errorText: String?
    @State private var renameTarget: CompetitionTeam?
    @State private var renameText = ""

    private var isOwner: Bool { competition.isOwner }
    private var memberPick: Bool { competition.teams?.member_pick ?? false }
    private var teams: [CompetitionTeam] { competition.teams?.teams ?? [] }
    private var myUserId: String? { UserDefaults.standard.string(forKey: "backendUserId") }
    private var myTeamId: String? {
        guard let uid = myUserId,
              let teamId = competition.users.first(where: { $0.user_id == uid })?.team_id,
              teams.contains(where: { $0.id == teamId }) else { return nil }
        return teamId
    }
    private var iAmAccepted: Bool {
        guard let uid = myUserId else { return false }
        return competition.users.contains { $0.user_id == uid && $0.invite_status == .accepted }
    }

    var body: some View {
        Group {
            if competition.hasTeams {
                teamsManager
            } else if isOwner {
                setupCTA
            }
        }
        .task { await loadStats() }
        .alert("Team Error", isPresented: .init(
            get: { errorText != nil },
            set: { if !$0 { errorText = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorText ?? "")
        }
        .alert("Rename Team", isPresented: .init(
            get: { renameTarget != nil },
            set: { if !$0 { renameTarget = nil } }
        )) {
            TextField("Team name", text: $renameText)
            Button("Save") {
                if let target = renameTarget { rename(target, to: renameText) }
            }
            Button("Delete Team", role: .destructive) {
                if let target = renameTarget { delete(target) }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - No teams yet (owner)

    private var setupCTA: some View {
        Button {
            // Two starter teams; the manager appears once they exist.
            run { try await competitionService.setTeams(
                competitionId: competition.competition_id,
                teams: [.init(id: nil, name: "Team 1"), .init(id: nil, name: "Team 2")]
            ) }
        } label: {
            HStack(spacing: MADTheme.Spacing.md) {
                Image(systemName: "person.3.fill")
                    .font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Set Up Teams")
                        .font(MADTheme.Typography.headline)
                    Text("Split the lobby into teams — scores combine")
                        .font(MADTheme.Typography.caption)
                        .foregroundColor(.white.opacity(0.7))
                }
                Spacer()
                if isWorking { ProgressView().tint(.white) } else { Image(systemName: "plus") }
            }
            .foregroundColor(.white)
            .padding(MADTheme.Spacing.lg)
            .background(
                RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                    .fill(Color.white.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                            .stroke(Color.white.opacity(0.15), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(ScaleButtonStyle())
        .disabled(isWorking)
    }

    // MARK: - Teams manager

    private var teamsManager: some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
            HStack(spacing: MADTheme.Spacing.sm) {
                Text("Teams")
                    .font(MADTheme.Typography.title3)
                    .foregroundColor(.white)
                Spacer()
                if isWorking { ProgressView().tint(.white).scaleEffect(0.8) }
            }
            .padding(.horizontal, MADTheme.Spacing.sm)

            if isOwner {
                ownerToolbar
            } else if memberPick, iAmAccepted {
                Text("Pick your team before the comp starts")
                    .font(MADTheme.Typography.caption)
                    .foregroundColor(.white.opacity(0.5))
                    .padding(.horizontal, MADTheme.Spacing.sm)
            }

            VStack(spacing: MADTheme.Spacing.sm) {
                ForEach(teams) { team in
                    teamCard(team)
                }

                let unassigned = competition.unassignedUsers
                if !unassigned.isEmpty {
                    unassignedCard(unassigned)
                }

                if isOwner {
                    memberPickToggle
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

    private var ownerToolbar: some View {
        HStack(spacing: MADTheme.Spacing.sm) {
            toolbarButton(title: "Randomize", icon: "shuffle", tint: MADTheme.Colors.madRed) { randomize() }
            toolbarButton(title: "Balance", icon: "scalemass", tint: .green) { balance() }

            Button { addTeam() } label: {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white.opacity(0.8))
                    .frame(width: 40, height: 36)
                    .background(
                        RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                            .fill(Color.white.opacity(0.08))
                    )
            }
            .disabled(isWorking || teams.count >= 12)
        }
        .padding(.horizontal, MADTheme.Spacing.sm)
    }

    private func toolbarButton(title: String, icon: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
            }
            .foregroundColor(tint)
            .frame(maxWidth: .infinity)
            .frame(height: 36)
            .background(
                RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                    .fill(tint.opacity(0.12))
                    .overlay(
                        RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                            .stroke(tint.opacity(0.35), lineWidth: 1)
                    )
            )
        }
        .disabled(isWorking)
    }

    // MARK: - Team card

    private func teamCard(_ team: CompetitionTeam) -> some View {
        let members = competition.members(of: team.id)
        let color = competition.teamColor(team.id)
        let isMine = myTeamId == team.id

        return VStack(alignment: .leading, spacing: MADTheme.Spacing.sm) {
            HStack(spacing: MADTheme.Spacing.sm) {
                Circle().fill(color).frame(width: 10, height: 10)

                Text(team.name)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)

                if isOwner {
                    Button {
                        renameText = team.name
                        renameTarget = team
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.35))
                    }
                    .disabled(isWorking)
                }

                if isMine {
                    Text("YOUR TEAM")
                        .font(.system(size: 8, weight: .heavy, design: .rounded))
                        .tracking(0.5)
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(color.opacity(0.8)))
                }

                Spacer()

                if memberPick, iAmAccepted, !isMine {
                    Button {
                        run { try await competitionService.pickTeam(
                            competitionId: competition.competition_id, teamId: team.id
                        ) }
                    } label: {
                        Text(myTeamId == nil ? "Join" : "Switch")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(color.opacity(0.7)))
                    }
                    .disabled(isWorking)
                } else if memberPick, iAmAccepted, isMine, !isOwner {
                    Button {
                        run { try await competitionService.pickTeam(
                            competitionId: competition.competition_id, teamId: nil
                        ) }
                    } label: {
                        Text("Leave")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundColor(.white.opacity(0.6))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Capsule().stroke(Color.white.opacity(0.25), lineWidth: 1))
                    }
                    .disabled(isWorking)
                }

                Text("\(members.count)")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.35))
            }

            if members.isEmpty {
                Text("No members yet")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.35))
                    .padding(.leading, 20)
            } else {
                VStack(spacing: 6) {
                    ForEach(members) { member in
                        memberRow(member)
                    }
                }
            }
        }
        .padding(MADTheme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                .fill(Color.white.opacity(isMine ? 0.07 : 0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                        .stroke(isMine ? color.opacity(0.5) : Color.white.opacity(0.06), lineWidth: 1)
                )
        )
    }

    private func unassignedCard(_ users: [CompetitionUser]) -> some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.sm) {
            Text("UNASSIGNED (\(users.count))")
                .font(.system(size: 10, weight: .heavy, design: .rounded))
                .tracking(1.0)
                .foregroundColor(.white.opacity(0.4))

            VStack(spacing: 6) {
                ForEach(users) { member in
                    memberRow(member)
                }
            }
        }
        .padding(MADTheme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                .strokeBorder(Color.white.opacity(0.15), style: StrokeStyle(lineWidth: 1, dash: [5]))
        )
    }

    @ViewBuilder
    private func memberRow(_ member: CompetitionUser) -> some View {
        let row = HStack(spacing: MADTheme.Spacing.sm) {
            AvatarView(name: member.displayName, imageURL: member.profile_image_url, size: 28)

            Text(member.displayName)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.9))
                .lineLimit(1)

            if member.user_id == competition.owner {
                Image(systemName: "crown.fill")
                    .font(.system(size: 9))
                    .foregroundColor(.yellow.opacity(0.8))
            }

            Spacer()

            if let label = statLabel(for: member.user_id) {
                Text(label)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundColor(.green)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.green.opacity(0.12)))
            }

            if isOwner {
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.white.opacity(0.3))
            }
        }

        if isOwner {
            Menu {
                ForEach(teams) { team in
                    Button(team.name) { assign(member.user_id, to: team.id) }
                }
                Button("Unassign", role: .destructive) { assign(member.user_id, to: nil) }
            } label: {
                row
            }
            .disabled(isWorking)
        } else {
            row
        }
    }

    private var memberPickToggle: some View {
        Toggle(isOn: .init(
            get: { memberPick },
            set: { newValue in
                run { try await competitionService.setTeams(
                    competitionId: competition.competition_id, memberPick: newValue
                ) }
            }
        )) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Members pick their own team")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.9))
                Text(memberPick ? "Anyone can join or switch teams" : "Only you can assign teams")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.4))
            }
        }
        .tint(MADTheme.Colors.madRed)
        .disabled(isWorking)
        .padding(.horizontal, 4)
        .padding(.top, 4)
    }

    // MARK: - Stats

    private func loadStats() async {
        guard competition.hasTeams || isOwner else { return }
        stats = try? await competitionService.getTeamStats(competitionId: competition.competition_id)
    }

    /// "2.3 mi/day", "16.1 mi/wk", "7,000 steps/day" — recent form matched to
    /// the comp. Nil until stats load (badges just don't render).
    private func statLabel(for userId: String) -> String? {
        guard let stat = stats?.stats[userId] else { return nil }
        let value = competition.options.formatQuantity(stat.avg_per_interval)
        let unit = competition.options.unit.shortDisplayName
        let suffix: String
        switch stats?.interval {
        case .week: suffix = "wk"
        case .month: suffix = "mo"
        default: suffix = "day"
        }
        return "\(value) \(unit)/\(suffix)"
    }

    // MARK: - Owner actions

    private func addTeam() {
        var n = teams.count + 1
        while teams.contains(where: { $0.name.caseInsensitiveCompare("Team \(n)") == .orderedSame }) { n += 1 }
        let newList = teams.map { SetTeamsRequest.TeamDefinition(id: $0.id, name: $0.name) }
            + [SetTeamsRequest.TeamDefinition(id: nil, name: "Team \(n)")]
        run { try await competitionService.setTeams(
            competitionId: competition.competition_id, teams: newList
        ) }
    }

    private func rename(_ team: CompetitionTeam, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != team.name else { return }
        let newList = teams.map {
            SetTeamsRequest.TeamDefinition(id: $0.id, name: $0.id == team.id ? trimmed : $0.name)
        }
        run { try await competitionService.setTeams(
            competitionId: competition.competition_id, teams: newList
        ) }
    }

    private func delete(_ team: CompetitionTeam) {
        let newList = teams.filter { $0.id != team.id }
            .map { SetTeamsRequest.TeamDefinition(id: $0.id, name: $0.name) }
        run { try await competitionService.setTeams(
            competitionId: competition.competition_id, teams: newList
        ) }
    }

    private func assign(_ userId: String, to teamId: String?) {
        var assignments: [String: String?] = [:]
        assignments.updateValue(teamId, forKey: userId)
        run { try await competitionService.setTeams(
            competitionId: competition.competition_id, assignments: assignments
        ) }
    }

    /// Shuffle accepted users and deal them round-robin into even-sized teams.
    private func randomize() {
        let users = competition.users.filter { $0.invite_status == .accepted }.shuffled()
        var assignments: [String: String?] = [:]
        for (index, user) in users.enumerated() {
            assignments.updateValue(teams[index % teams.count].id, forKey: user.user_id)
        }
        run { try await competitionService.setTeams(
            competitionId: competition.competition_id, assignments: assignments
        ) }
    }

    /// Greedy balance on recent form: strongest runner first, each into the
    /// team with the lowest running total.
    private func balance() {
        let users = competition.users
            .filter { $0.invite_status == .accepted }
            .sorted { (stats?.stats[$0.user_id]?.avg_per_day ?? 0) > (stats?.stats[$1.user_id]?.avg_per_day ?? 0) }
        var totals: [String: Double] = Dictionary(uniqueKeysWithValues: teams.map { ($0.id, 0.0) })
        var assignments: [String: String?] = [:]
        for user in users {
            guard let target = totals.min(by: { $0.value < $1.value })?.key else { break }
            assignments.updateValue(target, forKey: user.user_id)
            totals[target]! += stats?.stats[user.user_id]?.avg_per_day ?? 0
        }
        run { try await competitionService.setTeams(
            competitionId: competition.competition_id, assignments: assignments
        ) }
    }

    // MARK: - Plumbing

    /// One in-flight mutation at a time; refreshed competition flows back into
    /// the detail view's binding so every section updates together.
    private func run(_ operation: @escaping () async throws -> Competition) {
        guard !isWorking else { return }
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                competition = try await operation()
            } catch {
                errorText = error.localizedDescription
            }
        }
    }
}
