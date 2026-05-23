import SwiftUI

// MARK: - View Model

@Observable
final class LeaderboardViewModel {
    var metric: LeaderboardMetric = .miles {
        didSet { if oldValue != metric { refresh() } }
    }
    var period: LeaderboardPeriod = .week {
        didSet { if oldValue != period { refresh() } }
    }

    private(set) var entries: [LeaderboardEntry] = []
    private(set) var currentUserEntry: LeaderboardEntry?
    private(set) var totalCount: Int = 0
    private(set) var hasMore: Bool = false
    private(set) var isLoading: Bool = false
    private(set) var isLoadingMore: Bool = false
    private(set) var errorMessage: String?

    private var loadTask: Task<Void, Never>?

    func refresh() {
        loadTask?.cancel()
        let snapshotMetric = metric
        let snapshotPeriod = period

        loadTask = Task { @MainActor in
            isLoading = true
            errorMessage = nil
            do {
                let page = try await LeaderboardService.fetch(
                    metric: snapshotMetric,
                    period: snapshotPeriod,
                    offset: 0
                )
                guard !Task.isCancelled,
                      snapshotMetric == self.metric,
                      snapshotPeriod == self.period else { return }

                self.entries = page.entries
                self.currentUserEntry = page.current_user_entry
                self.totalCount = page.total_count
                self.hasMore = page.has_more
            } catch {
                if !Task.isCancelled {
                    print("[Leaderboard] fetch failed: \(error)")
                    self.errorMessage = friendlyMessage(for: error)
                }
            }
            self.isLoading = false
        }
    }

    func loadMore() {
        guard hasMore, !isLoading, !isLoadingMore else { return }
        let nextOffset = entries.count
        let snapshotMetric = metric
        let snapshotPeriod = period

        Task { @MainActor in
            isLoadingMore = true
            do {
                let page = try await LeaderboardService.fetch(
                    metric: snapshotMetric,
                    period: snapshotPeriod,
                    offset: nextOffset
                )
                guard snapshotMetric == self.metric,
                      snapshotPeriod == self.period else {
                    self.isLoadingMore = false
                    return
                }
                self.entries.append(contentsOf: page.entries)
                self.hasMore = page.has_more
                self.totalCount = page.total_count
            } catch {
                print("[Leaderboard] loadMore failed: \(error)")
            }
            isLoadingMore = false
        }
    }

    /// Translate framework errors into one-line user copy. Surfaces the real
    /// error message so we can diagnose without console access — generic
    /// fallbacks were hiding the actual cause.
    private func friendlyMessage(for error: Error) -> String {
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain {
            return "Couldn't reach the server. Check your connection."
        }
        if error is DecodingError {
            return "Decode error — backend response doesn't match. Update the app or backend."
        }
        // APIError (and most other errors) conform to LocalizedError —
        // expose the real message so 500s, 404s, auth issues etc. are visible.
        if let localized = (error as? LocalizedError)?.errorDescription {
            return localized
        }
        return error.localizedDescription
    }
}

// MARK: - Section View

struct LeaderboardSection: View {
    @ObservedObject var friendService: FriendService
    /// Optional handler so the empty state can offer an "Add friends" CTA
    /// without coupling the leaderboard view to the parent's sheet machinery.
    var onAddFriends: (() -> Void)? = nil
    @State private var vm = LeaderboardViewModel()
    @State private var selectedUser: BackendUser?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: MADTheme.Spacing.lg, pinnedViews: []) {
                heroCard
                filterChips
                contentBody
            }
            .padding(.horizontal, MADTheme.Spacing.md)
            .padding(.top, MADTheme.Spacing.md)
            .padding(.bottom, MADTheme.Spacing.xl)
        }
        .scrollIndicators(.hidden)
        .refreshable { vm.refresh() }
        .onAppear {
            if vm.entries.isEmpty && vm.errorMessage == nil { vm.refresh() }
        }
        .sheet(item: $selectedUser) { user in
            NavigationStack {
                UserProfileDetailView(user: user, friendService: friendService)
            }
        }
    }

    /// Build a BackendUser stub from a leaderboard entry. UserProfileDetailView
    /// reads `username`, `displayName`, `bio`, `profile_image_url`, `user_id` —
    /// the other BackendUser fields aren't used in its render path, so leaving
    /// them empty is safe. Avoids a network roundtrip on every row tap.
    private func makeBackendUser(_ entry: LeaderboardEntry) -> BackendUser {
        BackendUser(
            user_id: entry.user_id,
            username: entry.username,
            email: "",
            first_name: entry.first_name,
            last_name: entry.last_name,
            bio: nil,
            profile_image_url: entry.profile_image_url,
            apple_id: nil,
            auth_provider: nil,
            role: nil
        )
    }

    // MARK: Hero — viewer's own rank within friends

    @ViewBuilder
    private var heroCard: some View {
        if let me = vm.currentUserEntry {
            youCard(entry: me)
        } else if !vm.isLoading && vm.entries.isEmpty == false {
            // Viewer has no activity for this period yet — nudge them.
            notRankedCard
        } else {
            EmptyView()
        }
    }

    private func youCard(entry: LeaderboardEntry) -> some View {
        HStack(spacing: MADTheme.Spacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text("YOUR RANK")
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .tracking(1.2)
                    .foregroundColor(.white.opacity(0.5))
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("#\(entry.rank)")
                        .font(.system(size: 34, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                    if vm.totalCount > 0 {
                        Text("of \(vm.totalCount)")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundColor(.white.opacity(0.4))
                    }
                }
                Text(filterSubtitle)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.45))
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(formatValue(entry.value, metric: vm.metric))
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text(metricUnitText)
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .tracking(1.0)
                    .foregroundColor(.white.opacity(0.45))
            }
        }
        .padding(MADTheme.Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                .fill(
                    LinearGradient(
                        colors: [MADTheme.Colors.madRed.opacity(0.55), MADTheme.Colors.madRed.opacity(0.20)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                        .strokeBorder(MADTheme.Colors.madRed.opacity(0.45), lineWidth: 1)
                )
        )
    }

    private var notRankedCard: some View {
        HStack(spacing: MADTheme.Spacing.md) {
            Image(systemName: vm.metric == .streak ? "flame" : "figure.run")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.white.opacity(0.35))
            VStack(alignment: .leading, spacing: 2) {
                Text("YOU'RE NOT RANKED YET")
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .tracking(1.2)
                    .foregroundColor(.white.opacity(0.45))
                Text(vm.metric == .streak ? "Start a streak to appear on the board." : "Log a run for \(vm.period.displayName.lowercased()) to climb the board.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.55))
            }
            Spacer()
        }
        .padding(MADTheme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    // MARK: Filter chips

    /// One horizontal row of compact pill buttons. Each opens a Menu — much
    /// less visually noisy than stacked segmented controls.
    private var filterChips: some View {
        HStack(spacing: 8) {
            metricChip
            if vm.metric == .miles {
                periodChip
            }
            Spacer()
        }
    }

    private var metricChip: some View {
        Menu {
            Picker("Metric", selection: Binding(get: { vm.metric }, set: { vm.metric = $0 })) {
                ForEach(LeaderboardMetric.allCases) { m in
                    Label(m.displayName, systemImage: m == .miles ? "figure.run" : "flame.fill").tag(m)
                }
            }
        } label: {
            chipLabel(
                icon: vm.metric == .miles ? "figure.run" : "flame.fill",
                text: vm.metric.displayName
            )
        }
    }

    private var periodChip: some View {
        Menu {
            Picker("Period", selection: Binding(get: { vm.period }, set: { vm.period = $0 })) {
                ForEach(LeaderboardPeriod.allCases) { p in
                    Text(p.displayName).tag(p)
                }
            }
        } label: {
            chipLabel(icon: "calendar", text: vm.period.displayName)
        }
    }

    private func chipLabel(icon: String, text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
            Text(text)
                .font(.system(size: 12, weight: .bold, design: .rounded))
            Image(systemName: "chevron.down")
                .font(.system(size: 8, weight: .heavy))
                .opacity(0.6)
        }
        .foregroundColor(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.08))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
        )
    }

    // MARK: Content

    @ViewBuilder
    private var contentBody: some View {
        if vm.isLoading && vm.entries.isEmpty {
            loadingState
        } else if let err = vm.errorMessage, vm.entries.isEmpty {
            errorState(err)
        } else if vm.entries.isEmpty {
            // First-time onboarding when the user hasn't added any friends —
            // turns a dead-end empty state into a clear next action.
            if friendService.friends.isEmpty {
                firstTimeEmptyState
            } else {
                emptyState
            }
        } else {
            entriesList
        }
    }

    private var firstTimeEmptyState: some View {
        VStack(spacing: MADTheme.Spacing.md) {
            Image(systemName: "person.2.badge.plus")
                .font(.system(size: 36, weight: .bold))
                .foregroundColor(MADTheme.Colors.madRed.opacity(0.85))
                .padding(.bottom, 4)

            Text("Add friends to compete")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(.white)

            Text("Your leaderboard fills in as soon as you add a friend. The board ranks you against people you actually know.")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.55))
                .multilineTextAlignment(.center)
                .padding(.horizontal, MADTheme.Spacing.lg)

            if let onAddFriends = onAddFriends {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onAddFriends()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "person.badge.plus")
                            .font(.system(size: 13, weight: .bold))
                        Text("Find Friends")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(
                        Capsule()
                            .fill(MADTheme.Colors.madRed)
                            .shadow(color: MADTheme.Colors.madRed.opacity(0.35), radius: 8, y: 3)
                    )
                }
                .buttonStyle(.plain)
                .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, MADTheme.Spacing.xl)
    }

    private var loadingState: some View {
        VStack(spacing: MADTheme.Spacing.md) {
            ProgressView().tint(MADTheme.Colors.madRed)
            Text("Loading rankings…")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, MADTheme.Spacing.xxl)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: MADTheme.Spacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 28))
                .foregroundColor(.orange.opacity(0.75))

            Text("Leaderboard didn't load")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(.white.opacity(0.85))

            // Full error text — selectable so the user can copy + send it back
            // when reporting issues. Wider than the rest of the UI on purpose.
            Text(message)
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
                .padding(MADTheme.Spacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                        .fill(Color.black.opacity(0.25))
                        .overlay(
                            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                                .strokeBorder(Color.orange.opacity(0.3), lineWidth: 1)
                        )
                )

            Button("Retry") { vm.refresh() }
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 9)
                .background(Capsule().fill(MADTheme.Colors.madRed))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, MADTheme.Spacing.xl)
    }

    private var emptyState: some View {
        VStack(spacing: MADTheme.Spacing.sm) {
            Image(systemName: vm.metric == .streak ? "flame" : "figure.run")
                .font(.system(size: 32))
                .foregroundColor(.white.opacity(0.25))
            Text(emptyStateMessage)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.55))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, MADTheme.Spacing.xxl)
    }

    private var emptyStateMessage: String {
        switch vm.metric {
        case .streak: return "None of your friends have an active streak yet."
        case .miles: return "None of your friends have logged miles for this period."
        }
    }

    @ViewBuilder
    private var entriesList: some View {
        let podium = Array(vm.entries.prefix(3))
        let rest = vm.entries.count > 3 ? Array(vm.entries.dropFirst(3)) : []

        VStack(spacing: MADTheme.Spacing.lg) {
            if !podium.isEmpty {
                podiumRow(podium: podium)
            }

            if !rest.isEmpty {
                VStack(spacing: 4) {
                    ForEach(rest) { entry in
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            selectedUser = makeBackendUser(entry)
                        } label: {
                            listRow(entry: entry)
                        }
                        .buttonStyle(.plain)
                        .onAppear {
                            if let last = vm.entries.last,
                               entry.id == last.id || entry.rank >= last.rank - 1 {
                                vm.loadMore()
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                        .fill(Color.white.opacity(0.03))
                        .overlay(
                            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                                .strokeBorder(Color.white.opacity(0.05), lineWidth: 1)
                        )
                )
            }

            if vm.isLoadingMore {
                ProgressView().tint(MADTheme.Colors.madRed)
                    .padding(.vertical, MADTheme.Spacing.md)
            } else if !vm.hasMore && vm.entries.count > 5 {
                Text("END OF LEADERBOARD")
                    .font(.system(size: 9, weight: .heavy, design: .rounded))
                    .tracking(1.4)
                    .foregroundColor(.white.opacity(0.25))
                    .padding(.top, 4)
            }
        }
    }

    // MARK: Podium (top 3)

    private func podiumRow(podium: [LeaderboardEntry]) -> some View {
        // Visually: 2nd · 1st · 3rd, with 1st elevated. Falls back gracefully
        // when fewer than 3 entries exist.
        let first = podium.first(where: { $0.rank == 1 }) ?? podium[0]
        let second = podium.first(where: { $0.rank == 2 })
        let third = podium.first(where: { $0.rank == 3 })

        return HStack(alignment: .bottom, spacing: MADTheme.Spacing.sm) {
            if let s = second {
                podiumSlot(entry: s, height: 100, avatarSize: 48, accent: medalColor(2))
            } else {
                Color.clear.frame(maxWidth: .infinity, maxHeight: 100)
            }

            podiumSlot(entry: first, height: 124, avatarSize: 60, accent: medalColor(1), isFirst: true)

            if let t = third {
                podiumSlot(entry: t, height: 84, avatarSize: 44, accent: medalColor(3))
            } else {
                Color.clear.frame(maxWidth: .infinity, maxHeight: 84)
            }
        }
    }

    private func podiumSlot(entry: LeaderboardEntry, height: CGFloat, avatarSize: CGFloat, accent: Color, isFirst: Bool = false) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            selectedUser = makeBackendUser(entry)
        } label: {
            podiumSlotContent(entry: entry, height: height, avatarSize: avatarSize, accent: accent, isFirst: isFirst)
        }
        .buttonStyle(.plain)
    }

    private func podiumSlotContent(entry: LeaderboardEntry, height: CGFloat, avatarSize: CGFloat, accent: Color, isFirst: Bool) -> some View {
        VStack(spacing: 6) {
            ZStack(alignment: .topTrailing) {
                AvatarView(name: entry.fullName, imageURL: entry.profile_image_url, size: avatarSize)
                    .overlay(
                        Circle().strokeBorder(accent, lineWidth: isFirst ? 3 : 2)
                    )
                Text("\(entry.rank)")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .foregroundColor(.black.opacity(0.8))
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(accent))
                    .offset(x: 4, y: -4)
            }
            if isFirst {
                Image(systemName: "crown.fill")
                    .font(.system(size: 14))
                    .foregroundColor(accent)
                    .offset(y: -2)
            }
            VStack(spacing: 1) {
                Text(handleText(entry))
                    .font(.system(size: isFirst ? 13 : 11, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
                if entry.is_current_user {
                    Text("YOU")
                        .font(.system(size: 8, weight: .black, design: .rounded))
                        .tracking(0.5)
                        .foregroundColor(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(Capsule().fill(MADTheme.Colors.madRed))
                }
                Text(formatValue(entry.value, metric: vm.metric))
                    .font(.system(size: isFirst ? 14 : 12, weight: .heavy, design: .rounded))
                    .foregroundColor(accent)
                if let subtitle = podiumStatsSubtitle(entry) {
                    Text(subtitle)
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.45))
                        .lineLimit(1)
                        .padding(.horizontal, 2)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height, alignment: .bottom)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                .fill(entry.is_current_user ? MADTheme.Colors.madRed.opacity(0.10) : Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                        .strokeBorder(entry.is_current_user ? MADTheme.Colors.madRed.opacity(0.3) : Color.white.opacity(0.06), lineWidth: 1)
                )
        )
    }

    private func medalColor(_ rank: Int) -> Color {
        switch rank {
        case 1: return Color(red: 1.0, green: 0.82, blue: 0.20)        // gold
        case 2: return Color(white: 0.78)                                // silver
        case 3: return Color(red: 0.82, green: 0.55, blue: 0.30)         // bronze
        default: return .white.opacity(0.4)
        }
    }

    // MARK: List row (ranks 4+)

    private func listRow(entry: LeaderboardEntry) -> some View {
        HStack(spacing: MADTheme.Spacing.md) {
            Text("\(entry.rank)")
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundColor(.white.opacity(0.5))
                .frame(width: 28, alignment: .center)

            AvatarView(name: entry.fullName, imageURL: entry.profile_image_url, size: 34)
                .overlay(
                    Circle().strokeBorder(entry.is_current_user ? MADTheme.Colors.madRed : Color.clear, lineWidth: 1.5)
                )

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(handleText(entry))
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    if entry.is_current_user {
                        Text("YOU")
                            .font(.system(size: 8, weight: .black, design: .rounded))
                            .tracking(0.5)
                            .foregroundColor(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(Capsule().fill(MADTheme.Colors.madRed))
                    }
                }
                if let subtitle = statsSubtitle(entry) {
                    Text(subtitle)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.45))
                        .lineLimit(1)
                }
            }

            Spacer()

            Text(formatValue(entry.value, metric: vm.metric))
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(.white.opacity(0.85))
        }
        .padding(.horizontal, MADTheme.Spacing.md)
        .padding(.vertical, 9)
        .background(
            entry.is_current_user
                ? RoundedRectangle(cornerRadius: 0).fill(MADTheme.Colors.madRed.opacity(0.06))
                : RoundedRectangle(cornerRadius: 0).fill(Color.clear)
        )
    }

    // MARK: Helpers

    private var filterSubtitle: String {
        switch vm.metric {
        case .miles:
            return "\(vm.period.displayName) · Friends"
        case .streak:
            return "Current streak · Friends"
        }
    }

    private var metricUnitText: String {
        switch vm.metric {
        case .miles: return "MILES"
        case .streak: return "DAYS"
        }
    }

    /// Username with @ prefix when available, real name as fallback so users
    /// without a username still render readably.
    private func handleText(_ entry: LeaderboardEntry) -> String {
        if let u = entry.username, !u.isEmpty { return "@\(u)" }
        return entry.fullName
    }

    /// Sub-line shown beneath the handle in list rows.
    /// For the miles metric we omit total miles (it's already the primary value
    /// on the right), keeping just the best pace. For streak we show both.
    private func statsSubtitle(_ entry: LeaderboardEntry) -> String? {
        let paceText = formatPace(entry.period_best_pace)
        switch vm.metric {
        case .miles:
            return paceText.map { "Best mile · \($0)" }
        case .streak:
            let milesText = entry.period_miles.map { formatMiles($0) }
            let joined = [milesText, paceText].compactMap { $0 }.joined(separator: " · ")
            return joined.isEmpty ? nil : joined
        }
    }

    /// Tighter version of statsSubtitle for the podium — no labels, just
    /// "X.X mi · 8:32/mi". Falls back gracefully when either stat is missing.
    private func podiumStatsSubtitle(_ entry: LeaderboardEntry) -> String? {
        let paceText = formatPace(entry.period_best_pace)
        switch vm.metric {
        case .miles:
            return paceText
        case .streak:
            let milesText = entry.period_miles.map { formatMiles($0) }
            let joined = [milesText, paceText].compactMap { $0 }.joined(separator: " · ")
            return joined.isEmpty ? nil : joined
        }
    }

    private func formatMiles(_ value: Double) -> String {
        if value >= 100 { return String(format: "%.0f mi", value) }
        return String(format: "%.1f mi", value)
    }

    private func formatPace(_ secondsPerMile: Double?) -> String? {
        guard let s = secondsPerMile, s > 0, s.isFinite else { return nil }
        let total = Int(s.rounded())
        let m = total / 60
        let sec = total % 60
        return String(format: "%d:%02d/mi", m, sec)
    }

    private func formatValue(_ value: Double, metric: LeaderboardMetric) -> String {
        switch metric {
        case .miles:
            if value >= 100 { return String(format: "%.0f", value) }
            return String(format: "%.1f", value)
        case .streak:
            return "\(Int(value))"
        }
    }
}
