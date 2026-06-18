import SwiftUI

/// Main view for managing competitions
struct CompetitionsListView: View {
    @ObservedObject var competitionService: CompetitionService
    @ObservedObject private var trophyService = TrophyService.shared
    @State private var selectedTab = 0
    @State private var showingCreateCompetition = false
    @State private var selectedCompetition: Competition?
    @State private var showingTrophyCase = false

    // Filter chip selection (replaces stacked collapsible sections)
    @State private var selectedFilter: CompetitionFilter = .active

    // Inline confirm + swipe action state (no detached popups)
    @State private var pendingDeleteId: String?
    @State private var pendingLeaveId: String?
    @State private var competitionToEdit: Competition?
    @State private var actionError: String?

    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(spacing: 0) {
            MADTabHeader(
                title: "Compete",
                actions: headerActions
            )

            // Pill-style sub-tabs replace the underline TabButtons for
            // consistency with the Friends tab's mode picker.
            MADPillPicker(
                selection: Binding(
                    get: { selectedTab == 0 ? CompeteTab.my : .invites },
                    set: { selectedTab = $0 == .my ? 0 : 1 }
                ),
                options: [
                    .init(
                        id: .my,
                        title: "My Comps",
                        systemImage: "trophy.fill",
                        badgeCount: 0
                    ),
                    .init(
                        id: .invites,
                        title: "Invites",
                        systemImage: "envelope.fill",
                        badgeCount: competitionService.invites.count
                    )
                ]
            )
            .padding(.horizontal, MADTheme.Spacing.md)
            .padding(.top, MADTheme.Spacing.xs)
            .padding(.bottom, MADTheme.Spacing.sm)

            // Content
            Group {
                if selectedTab == 0 {
                    competitionsTab
                        .id("competitions-tab")
                } else {
                    invitesTab
                        .id("invites-tab")
                }
            }
        }
        .background(MADTheme.Colors.appBackgroundGradient)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showingCreateCompetition) {
            CreateCompetitionView { createdId in
                Task {
                    await competitionService.refreshAllData()
                    if let competition = competitionService.competitions.first(where: { $0.id == createdId }) {
                        selectedCompetition = competition
                    }
                }
            }
        }
        .sheet(item: $selectedCompetition) { competition in
            NavigationStack {
                CompetitionDetailView(competition: competition, competitionService: competitionService)
            }
        }
        .sheet(isPresented: $showingTrophyCase) {
            NavigationStack {
                TrophyCaseView(trophyService: trophyService, competitionService: competitionService)
            }
        }
        .sheet(item: $competitionToEdit) { competition in
            EditCompetitionWrapper(initial: competition, service: competitionService)
        }
        .alert("Couldn't complete action", isPresented: Binding(
            get: { actionError != nil },
            set: { if !$0 { actionError = nil } }
        )) {
            Button("OK", role: .cancel) { actionError = nil }
        } message: {
            Text(actionError ?? "")
        }
        .task {
            // Handle cold-launch deep link
            if MADNotificationService.shared.pendingNotificationType == "competition_invite" {
                selectedTab = 1
                MADNotificationService.shared.pendingNotificationType = nil
            }
        }
        .onAppear {
            Task {
                await competitionService.refreshAllData()
                trophyService.updateTrophies(from: competitionService.competitions)
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            Task {
                await competitionService.refreshAllData()
                trophyService.updateTrophies(from: competitionService.competitions)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .didTapPushNotification)) { notification in
            guard let type = notification.userInfo?["type"] as? String else { return }
            if type == "competition_invite" {
                selectedTab = 1
            }
        }
        .onChange(of: showingCreateCompetition) { _, isPresented in
            if !isPresented {
                // Refresh after creating a competition
                Task {
                    await competitionService.refreshAllData()
                }
            }
        }
    }

    // MARK: - Header Actions
    private var headerActions: [MADHeaderAction] {
        var actions: [MADHeaderAction] = []
        if trophyService.totalCompetitions > 0 {
            // Achievement style: gold pill with the win count. Reads as a flex,
            // not an alert — distinct from notification-style red badges.
            actions.append(
                MADHeaderAction(
                    id: "trophy",
                    systemImage: "trophy.fill",
                    style: .achievement(count: trophyService.totalCompetitions)
                ) { showingTrophyCase = true }
            )
        }
        // CTA style: filled red circle so "create new competition" stands out
        // as the primary action on the page.
        actions.append(
            MADHeaderAction(
                id: "create",
                systemImage: "plus",
                style: .cta
            ) { showingCreateCompetition = true }
        )
        return actions
    }

    private enum CompeteTab: Hashable { case my, invites }

    // MARK: - Competitions Tab
    private var competitionsTab: some View {
        Group {
            // Skeletons only while we have nothing to show. Keying on isLoading
            // alone swapped the live List out on every background refresh — which
            // also cancelled pull-to-refresh mid-flight (the List hosting
            // .refreshable was destroyed), leaving stale data until app restart.
            if competitionService.competitions.isEmpty && !competitionService.hasLoadedOnce {
                loadingView
            } else if competitionService.competitions.isEmpty {
                CompetitionEmptyStateView(
                    title: "No Competitions Yet",
                    message: "Create a competition to challenge your friends!",
                    systemImage: "trophy",
                    actionTitle: "Create Competition",
                    action: { showingCreateCompetition = true }
                )
            } else {
                competitionsList
            }
        }
    }

    private var competitionsList: some View {
        let filtered = filteredCompetitions
        return VStack(spacing: 0) {
            filterChipsBar

            if filtered.isEmpty {
                emptyFilterState
                    .transition(.opacity)
            } else {
                List {
                    if selectedFilter == .all {
                        allGroupedRows
                    } else {
                        ForEach(filtered, id: \.competition_id) { competition in
                            competitionRow(competition)
                        }
                    }

                    Color.clear
                        .frame(height: 24)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets())
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .scrollBounceBehavior(.basedOnSize)
                .environment(\.defaultMinListRowHeight, 0)
                .animation(.spring(response: 0.32, dampingFraction: 0.85), value: selectedFilter)
                .refreshable {
                    await competitionService.refreshAllData()
                    trophyService.updateTrophies(from: competitionService.competitions)
                }
            }
        }
    }

    /// When viewing "All", split the list into Active / Waiting / Finished blocks
    /// with subtle, inline group labels so users see structure at a glance without
    /// the heavy collapsible-section feel from before.
    @ViewBuilder
    private var allGroupedRows: some View {
        let comps = competitionService.competitions
        let active = comps.filter { $0.status == .active }
        let waiting = comps.filter { $0.status == .lobby || $0.status == .scheduled }
        let finished = comps.filter { $0.status == .finished }

        if !active.isEmpty {
            allGroupDivider(title: "Active", count: active.count, accent: .green, icon: "bolt.fill")
            ForEach(active, id: \.competition_id) { competitionRow($0) }
        }
        if !waiting.isEmpty {
            allGroupDivider(title: "Waiting", count: waiting.count, accent: .orange, icon: "hourglass")
            ForEach(waiting, id: \.competition_id) { competitionRow($0) }
        }
        if !finished.isEmpty {
            allGroupDivider(title: "Finished", count: finished.count, accent: .gray, icon: "flag.checkered")
            ForEach(finished, id: \.competition_id) { competitionRow($0) }
        }
    }

    private func allGroupDivider(title: String, count: Int, accent: Color, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(accent)

            Text(title.uppercased())
                .font(.system(size: 11, weight: .black, design: .rounded))
                .tracking(1.4)
                .foregroundColor(.white.opacity(0.85))

            Text("\(count)")
                .font(.system(size: 10, weight: .black, design: .rounded))
                .foregroundColor(accent)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(Capsule().fill(accent.opacity(0.2)))

            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [accent.opacity(0.4), accent.opacity(0)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 1)
        }
        .padding(.top, 4)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 18, leading: 14, bottom: 4, trailing: 14))
    }

    /// Horizontal pill-style filter chips that replace the stacked sections.
    /// Empty filters are hidden so the bar never offers a chip you can't use.
    private var filterChipsBar: some View {
        let counts = filterCounts
        let visible = visibleFilters

        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(visible, id: \.self) { filter in
                    CompetitionFilterChip(
                        filter: filter,
                        count: counts[filter] ?? 0,
                        isSelected: selectedFilter == filter
                    ) {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                            selectedFilter = filter
                            pendingDeleteId = nil
                            pendingLeaveId = nil
                        }
                    }
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.85).combined(with: .opacity),
                        removal: .scale(scale: 0.85).combined(with: .opacity)
                    ))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .animation(.spring(response: 0.35, dampingFraction: 0.82), value: visible)
        }
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        .background(
            LinearGradient(
                colors: [Color.white.opacity(0.04), Color.white.opacity(0)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 0.5)
        }
        .onAppear { reconcileSelectedFilter(with: visible) }
        .onChange(of: visible) { _, newVisible in
            reconcileSelectedFilter(with: newVisible)
        }
    }

    /// Live count per filter, used both for chip badges and visibility decisions.
    private var filterCounts: [CompetitionFilter: Int] {
        let comps = competitionService.competitions
        return [
            .all: comps.count,
            .active: comps.filter { $0.status == .active }.count,
            .waiting: comps.filter { $0.status == .lobby || $0.status == .scheduled }.count,
            .finished: comps.filter { $0.status == .finished }.count
        ]
    }

    /// `.all` is always shown when there's at least one comp; other filters only
    /// appear when they have entries — no dead chips that select an empty tab.
    private var visibleFilters: [CompetitionFilter] {
        let counts = filterCounts
        return CompetitionFilter.allCases.filter { filter in
            filter == .all || (counts[filter] ?? 0) > 0
        }
    }

    /// If the currently selected filter disappears (e.g., last Active comp ends),
    /// pick the next sensible non-empty filter. Preference: active → waiting → finished → all.
    private func reconcileSelectedFilter(with visible: [CompetitionFilter]) {
        guard !visible.contains(selectedFilter) else { return }
        let priority: [CompetitionFilter] = [.active, .waiting, .finished, .all]
        let target = priority.first(where: { visible.contains($0) }) ?? .all
        withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
            selectedFilter = target
        }
    }

    private var filteredCompetitions: [Competition] {
        let comps = competitionService.competitions
        switch selectedFilter {
        case .all:
            // Active first, then waiting, then finished — visual priority.
            return comps.sorted { lhs, rhs in
                statusOrder(lhs.status) < statusOrder(rhs.status)
            }
        case .active:
            return comps.filter { $0.status == .active }
        case .waiting:
            return comps.filter { $0.status == .lobby || $0.status == .scheduled }
        case .finished:
            return comps.filter { $0.status == .finished }
        }
    }

    private func statusOrder(_ status: CompetitionStatus) -> Int {
        switch status {
        case .active: return 0
        case .lobby: return 1
        case .scheduled: return 2
        case .finished: return 3
        }
    }

    /// Filter-empty state — shows up when a tab has no matching comps but others do.
    private var emptyFilterState: some View {
        VStack(spacing: 14) {
            Image(systemName: selectedFilter.icon)
                .font(.system(size: 38, weight: .medium))
                .foregroundColor(selectedFilter.accent.opacity(0.5))

            Text(selectedFilter.emptyTitle)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(.white)

            Text(selectedFilter.emptyMessage)
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.55))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 40)
    }

    /// A competition row: card normally, in-line confirm banner when a swipe action is pending.
    @ViewBuilder
    private func competitionRow(_ competition: Competition) -> some View {
        Group {
            if pendingDeleteId == competition.competition_id {
                InlineConfirmBanner(
                    title: "Delete \"\(competition.competition_name)\"?",
                    subtitle: "Removes for everyone. Can't be undone.",
                    icon: "trash.fill",
                    confirmLabel: "Delete",
                    accent: .red,
                    onCancel: {
                        withAnimation(.easeOut(duration: 0.2)) { pendingDeleteId = nil }
                    },
                    onConfirm: { performDelete(competition) }
                )
            } else if pendingLeaveId == competition.competition_id {
                InlineConfirmBanner(
                    title: "Leave \"\(competition.competition_name)\"?",
                    subtitle: "You'll be removed from the standings.",
                    icon: "rectangle.portrait.and.arrow.right",
                    confirmLabel: "Leave",
                    accent: .orange,
                    onCancel: {
                        withAnimation(.easeOut(duration: 0.2)) { pendingLeaveId = nil }
                    },
                    onConfirm: { performLeave(competition) }
                )
            } else {
                CompetitionCard(competition: competition, action: {
                    selectedCompetition = competition
                })
            }
        }
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 6, leading: 14, bottom: 6, trailing: 14))
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if competition.isOwner {
                Button(role: .destructive) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        pendingLeaveId = nil
                        pendingDeleteId = competition.competition_id
                    }
                } label: {
                    Label("Delete", systemImage: "trash.fill")
                }

                if competition.status != .finished {
                    Button {
                        competitionToEdit = competition
                    } label: {
                        Label("Edit", systemImage: "slider.horizontal.3")
                    }
                    .tint(.blue)
                }
            } else if competition.status != .finished {
                Button(role: .destructive) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        pendingDeleteId = nil
                        pendingLeaveId = competition.competition_id
                    }
                } label: {
                    Label("Leave", systemImage: "rectangle.portrait.and.arrow.right")
                }
            }
        }
    }

    // MARK: - Invites Tab
    private var invitesTab: some View {
        Group {
            // Same cold-start-only skeleton rule as competitionsTab.
            if competitionService.invites.isEmpty && !competitionService.hasLoadedOnce {
                loadingView
            } else if competitionService.invites.isEmpty {
                CompetitionEmptyStateView(
                    title: "No Invites",
                    message: "You don't have any pending competition invites at the moment.",
                    systemImage: "envelope.open"
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: MADTheme.Spacing.lg) {
                        ForEach(competitionService.invites, id: \.competition_id) { competition in
                            InviteCard(
                                competition: competition,
                                onAccept: {
                                    handleAcceptInvite(competition)
                                },
                                onDecline: {
                                    handleDeclineInvite(competition)
                                }
                            )
                        }
                    }
                    .padding(.horizontal, MADTheme.Spacing.md)
                    .padding(.vertical, MADTheme.Spacing.lg)
                }
                .scrollBounceBehavior(.basedOnSize)
                .refreshable {
                    await competitionService.refreshAllData()
                    trophyService.updateTrophies(from: competitionService.competitions)
                }
            }
        }
    }

    // MARK: - Loading View
    /// Skeleton card list — mirrors the Friends-home loading state so both
    /// tabs share the same perceived-performance treatment instead of a bare
    /// spinner. Renders 3 placeholder competition cards while the real list
    /// fetches.
    private var loadingView: some View {
        ScrollView {
            VStack(spacing: MADTheme.Spacing.md) {
                ForEach(0..<3, id: \.self) { _ in competitionSkeletonCard }
            }
            .padding(.horizontal, MADTheme.Spacing.md)
            .padding(.top, MADTheme.Spacing.md)
        }
        .scrollIndicators(.hidden)
    }

    private var competitionSkeletonCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: MADTheme.Spacing.md) {
                Circle()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 48, height: 48)
                    .shimmer()
                VStack(alignment: .leading, spacing: 6) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 140, height: 14)
                        .shimmer()
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.06))
                        .frame(width: 80, height: 10)
                        .shimmer()
                }
                Spacer()
            }
            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { _ in
                    Capsule()
                        .fill(Color.white.opacity(0.06))
                        .frame(width: 60, height: 24)
                        .shimmer()
                }
                Spacer()
            }
            HStack(spacing: -8) {
                ForEach(0..<3, id: \.self) { _ in
                    Circle()
                        .fill(Color.white.opacity(0.06))
                        .frame(width: 28, height: 28)
                        .overlay(Circle().strokeBorder(MADTheme.Colors.madBlack, lineWidth: 2))
                        .shimmer()
                }
                Spacer()
                Capsule()
                    .fill(Color.white.opacity(0.06))
                    .frame(width: 80, height: 22)
                    .shimmer()
            }
        }
        .padding(MADTheme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
                )
        )
    }

    // MARK: - Helper Methods
    private func handleAcceptInvite(_ competition: Competition) {
        Task {
            do {
                try await competitionService.acceptInvite(competitionId: competition.competition_id)
            } catch {
                print("Error accepting invite: \(error)")
            }
        }
    }

    private func handleDeclineInvite(_ competition: Competition) {
        Task {
            do {
                try await competitionService.declineInvite(competitionId: competition.competition_id)
            } catch {
                print("Error declining invite: \(error)")
            }
        }
    }

    // MARK: - Swipe Action Handlers

    private func performDelete(_ competition: Competition) {
        let id = competition.competition_id
        withAnimation(.easeOut(duration: 0.2)) { pendingDeleteId = nil }
        Task { @MainActor in
            do {
                try await competitionService.deleteCompetition(id: id)
            } catch {
                actionError = "Couldn't delete this competition. \(error.localizedDescription)"
            }
        }
    }

    private func performLeave(_ competition: Competition) {
        guard let userId = UserDefaults.standard.string(forKey: "backendUserId") else {
            withAnimation(.easeOut(duration: 0.2)) { pendingLeaveId = nil }
            actionError = "You need to be signed in to leave a competition."
            return
        }
        let competitionId = competition.competition_id
        withAnimation(.easeOut(duration: 0.2)) { pendingLeaveId = nil }
        Task { @MainActor in
            do {
                try await competitionService.removeUser(competitionId: competitionId, userId: userId)
            } catch {
                actionError = "Couldn't leave this competition. \(error.localizedDescription)"
            }
        }
    }
}

// MARK: - Competition Filter

enum CompetitionFilter: String, CaseIterable, Hashable {
    case all = "All"
    case active = "Active"
    case waiting = "Waiting"
    case finished = "Finished"

    var icon: String {
        switch self {
        case .all: return "square.stack.3d.up.fill"
        case .active: return "bolt.fill"
        case .waiting: return "hourglass"
        case .finished: return "flag.checkered"
        }
    }

    var accent: Color {
        switch self {
        case .all: return MADTheme.Colors.madRed
        case .active: return .green
        case .waiting: return .orange
        case .finished: return .gray
        }
    }

    var emptyTitle: String {
        switch self {
        case .all: return "No competitions yet"
        case .active: return "Nothing active"
        case .waiting: return "Nothing waiting"
        case .finished: return "No history yet"
        }
    }

    var emptyMessage: String {
        switch self {
        case .all: return "Create one to challenge your friends."
        case .active: return "No comps are currently running. Check Waiting or create a new one."
        case .waiting: return "Anything not yet started will show up here."
        case .finished: return "Past competitions will land here when they wrap up."
        }
    }
}

// MARK: - Filter Chip

struct CompetitionFilterChip: View {
    let filter: CompetitionFilter
    let count: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: filter.icon)
                    .font(.system(size: 11, weight: .bold))

                Text(filter.rawValue)
                    .font(.system(size: 13, weight: .bold, design: .rounded))

                Text("\(count)")
                    .font(.system(size: 11, weight: .black, design: .rounded))
                    .foregroundColor(isSelected ? .white : filter.accent)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(isSelected ? Color.white.opacity(0.28) : filter.accent.opacity(0.22))
                    )
            }
            .foregroundColor(isSelected ? .white : .white.opacity(0.72))
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(chipBackground)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var chipBackground: some View {
        if isSelected {
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [filter.accent, filter.accent.opacity(0.78)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    Capsule()
                        .strokeBorder(Color.white.opacity(0.25), lineWidth: 1)
                )
                .shadow(color: filter.accent.opacity(0.5), radius: 6, x: 0, y: 3)
        } else {
            Capsule()
                .fill(Color.white.opacity(0.06))
                .overlay(
                    Capsule()
                        .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                )
        }
    }
}

// MARK: - Inline Confirm Banner

/// Replaces the row's card with an inline confirmation prompt when a destructive
/// swipe action fires. No detached popup — the confirmation lives in the row.
struct InlineConfirmBanner: View {
    let title: String
    let subtitle: String
    let icon: String
    let confirmLabel: String
    let accent: Color
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(accent)
                .frame(width: 36, height: 36)
                .background(
                    Circle()
                        .fill(accent.opacity(0.18))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(subtitle)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.62))
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            Button(action: onCancel) {
                Text("Cancel")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.75))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        Capsule().fill(Color.white.opacity(0.1))
                    )
            }
            .buttonStyle(.plain)

            Button(action: onConfirm) {
                Text(confirmLabel)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [accent, accent.opacity(0.82)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .shadow(color: accent.opacity(0.45), radius: 6, x: 0, y: 3)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                        .fill(Color.black.opacity(0.2))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                        .strokeBorder(accent.opacity(0.45), lineWidth: 1.5)
                )
                .shadow(color: accent.opacity(0.25), radius: 10, x: 0, y: 6)
        )
        .transition(.asymmetric(
            insertion: .scale(scale: 0.96).combined(with: .opacity),
            removal: .opacity
        ))
    }
}

// MARK: - Edit Competition Wrapper
// `EditCompetitionSettingsView` needs a `Binding<Competition>`; this wrapper owns
// the mutable state so we can present the edit sheet inline from a swipe action.

struct EditCompetitionWrapper: View {
    @State private var competition: Competition
    let service: CompetitionService

    init(initial: Competition, service: CompetitionService) {
        _competition = State(initialValue: initial)
        self.service = service
    }

    var body: some View {
        EditCompetitionSettingsView(
            competition: $competition,
            competitionService: service
        )
        // Form sheet — an accidental slide-down would silently discard edits.
        // Cancel/Save in the toolbar are the explicit exits.
        .interactiveDismissDisabled()
    }
}

// MARK: - Empty State View
struct CompetitionEmptyStateView: View {
    let title: String
    let message: String
    let systemImage: String
    var actionTitle: String?
    var action: (() -> Void)?

    @State private var iconScale: CGFloat = 0.8
    @State private var glowOpacity: Double = 0.3

    var body: some View {
        VStack(spacing: MADTheme.Spacing.xl) {
            // Animated icon with glow effect
            ZStack {
                // Outer glow rings
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .stroke(
                            MADTheme.Colors.madRed.opacity(glowOpacity * (0.3 - Double(index) * 0.1)),
                            lineWidth: 2
                        )
                        .frame(width: 140 + CGFloat(index * 20), height: 140 + CGFloat(index * 20))
                        .scaleEffect(iconScale)
                }

                // Icon container
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    MADTheme.Colors.madRed.opacity(0.3),
                                    MADTheme.Colors.madRed.opacity(0.1),
                                    Color.clear
                                ],
                                center: .center,
                                startRadius: 30,
                                endRadius: 70
                            )
                        )
                        .frame(width: 140, height: 140)

                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 100, height: 100)

                    Image(systemName: systemImage)
                        .font(.system(size: 50, weight: .medium))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [MADTheme.Colors.madRed, .orange],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                .scaleEffect(iconScale)
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                    iconScale = 1.1
                    glowOpacity = 0.6
                }
            }

            VStack(spacing: MADTheme.Spacing.md) {
                Text(title)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)

                Text(message)
                    .font(MADTheme.Typography.body)
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, MADTheme.Spacing.lg)
            }

            if let actionTitle = actionTitle, let action = action {
                Button(action: action) {
                    HStack(spacing: MADTheme.Spacing.sm) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                        Text(actionTitle)
                            .font(MADTheme.Typography.callout)
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, MADTheme.Spacing.xl)
                    .padding(.vertical, MADTheme.Spacing.md)
                    .background(
                        RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                            .fill(MADTheme.Colors.primaryGradient)
                            .shadow(color: MADTheme.Colors.madRed.opacity(0.4), radius: 15, x: 0, y: 8)
                    )
                }
                .buttonStyle(ScaleButtonStyle())
            }
        }
        .padding(MADTheme.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    NavigationStack {
        CompetitionsListView(competitionService: CompetitionService())
    }
}
