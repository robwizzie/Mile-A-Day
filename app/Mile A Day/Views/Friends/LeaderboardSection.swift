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
    var scope: LeaderboardScope = .global {
        didSet { if oldValue != scope { refresh() } }
    }

    private(set) var entries: [LeaderboardEntry] = []
    private(set) var currentUserEntry: LeaderboardEntry?
    private(set) var totalCount: Int = 0
    private(set) var hasMore: Bool = false
    private(set) var isLoading: Bool = false
    private(set) var isLoadingMore: Bool = false
    private(set) var errorMessage: String?
    private(set) var viewerOptedOut: Bool = false
    private(set) var isUpdatingOptOut: Bool = false

    private var loadTask: Task<Void, Never>?

    /// Loads the first page. Cancels any in-flight request. Called on initial
    /// appearance and whenever a filter changes.
    func refresh() {
        loadTask?.cancel()
        let snapshotMetric = metric
        let snapshotPeriod = period
        let snapshotScope = scope

        loadTask = Task { @MainActor in
            isLoading = true
            errorMessage = nil
            do {
                let page = try await LeaderboardService.fetch(
                    metric: snapshotMetric,
                    period: snapshotPeriod,
                    scope: snapshotScope,
                    offset: 0
                )
                // Only commit if filters haven't shifted under us mid-flight.
                guard !Task.isCancelled,
                      snapshotMetric == self.metric,
                      snapshotPeriod == self.period,
                      snapshotScope == self.scope else { return }

                self.entries = page.entries
                self.currentUserEntry = page.current_user_entry
                self.totalCount = page.total_count
                self.hasMore = page.has_more
                self.viewerOptedOut = page.viewer_opted_out
            } catch {
                if !Task.isCancelled {
                    self.errorMessage = "Couldn't load leaderboard"
                }
            }
            self.isLoading = false
        }
    }

    /// Fetches the next page and appends to `entries`. Guarded so duplicate
    /// "load more" triggers from rapid scrolling don't cause overlapping fetches.
    func loadMore() {
        guard hasMore, !isLoading, !isLoadingMore else { return }
        let nextOffset = entries.count
        let snapshotMetric = metric
        let snapshotPeriod = period
        let snapshotScope = scope

        Task { @MainActor in
            isLoadingMore = true
            do {
                let page = try await LeaderboardService.fetch(
                    metric: snapshotMetric,
                    period: snapshotPeriod,
                    scope: snapshotScope,
                    offset: nextOffset
                )
                guard snapshotMetric == self.metric,
                      snapshotPeriod == self.period,
                      snapshotScope == self.scope else {
                    self.isLoadingMore = false
                    return
                }
                self.entries.append(contentsOf: page.entries)
                self.hasMore = page.has_more
                self.totalCount = page.total_count
            } catch {
                // Stay silent on load-more errors — first page already rendered,
                // and the user can pull-to-refresh if they want to retry.
            }
            isLoadingMore = false
        }
    }

    /// Toggles the viewer's leaderboard visibility. Optimistically flips the
    /// local flag, calls the backend, refreshes the page on success, or rolls
    /// back the flag on failure.
    func setOptOut(_ optOut: Bool) {
        guard let userId = UserDefaults.standard.string(forKey: "backendUserId"),
              !userId.isEmpty else { return }
        let previous = viewerOptedOut
        viewerOptedOut = optOut
        isUpdatingOptOut = true

        Task { @MainActor in
            do {
                let committed = try await LeaderboardService.setOptOut(userId: userId, optOut: optOut)
                self.viewerOptedOut = committed
                self.isUpdatingOptOut = false
                // Reload so opting in immediately surfaces the user's row.
                self.refresh()
            } catch {
                self.viewerOptedOut = previous
                self.isUpdatingOptOut = false
                self.errorMessage = "Couldn't update leaderboard visibility"
            }
        }
    }
}

// MARK: - Section View

struct LeaderboardSection: View {
    @State private var vm = LeaderboardViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: MADTheme.Spacing.md) {
                headerRow
                filterStack
                if vm.metric == .miles {
                    periodPicker
                }
                if vm.viewerOptedOut {
                    optOutBanner
                }
                content
            }
            .padding(.horizontal, MADTheme.Spacing.md)
            .padding(.top, MADTheme.Spacing.sm)
            .padding(.bottom, MADTheme.Spacing.lg)
        }
        .scrollIndicators(.hidden)
        .refreshable {
            vm.refresh()
        }
        .onAppear {
            if vm.entries.isEmpty { vm.refresh() }
        }
    }

    // MARK: Header (visibility menu)

    private var headerRow: some View {
        HStack {
            Spacer()
            Menu {
                if vm.viewerOptedOut {
                    Button {
                        vm.setOptOut(false)
                    } label: {
                        Label("Show me on the leaderboard", systemImage: "eye")
                    }
                } else {
                    Button(role: .destructive) {
                        vm.setOptOut(true)
                    } label: {
                        Label("Hide me from the leaderboard", systemImage: "eye.slash")
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white.opacity(0.55))
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .disabled(vm.isUpdatingOptOut)
        }
    }

    // MARK: Opt-out banner

    private var optOutBanner: some View {
        HStack(spacing: MADTheme.Spacing.sm) {
            Image(systemName: "eye.slash.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.orange)

            VStack(alignment: .leading, spacing: 2) {
                Text("You're hidden")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.9))
                Text("Your name and stats don't appear on any leaderboard.")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.55))
            }

            Spacer()

            Button("Show me") { vm.setOptOut(false) }
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(Capsule().fill(MADTheme.Colors.madRed))
                .disabled(vm.isUpdatingOptOut)
        }
        .padding(MADTheme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                .fill(Color.orange.opacity(0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                        .strokeBorder(Color.orange.opacity(0.3), lineWidth: 1)
                )
        )
    }

    // MARK: Filters

    private var filterStack: some View {
        VStack(spacing: MADTheme.Spacing.sm) {
            Picker("Scope", selection: Binding(get: { vm.scope }, set: { vm.scope = $0 })) {
                ForEach(LeaderboardScope.allCases) { scope in
                    Text(scope.displayName).tag(scope)
                }
            }
            .pickerStyle(.segmented)

            Picker("Metric", selection: Binding(get: { vm.metric }, set: { vm.metric = $0 })) {
                ForEach(LeaderboardMetric.allCases) { metric in
                    Text(metric.displayName).tag(metric)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var periodPicker: some View {
        Picker("Period", selection: Binding(get: { vm.period }, set: { vm.period = $0 })) {
            ForEach(LeaderboardPeriod.allCases) { period in
                Text(period.displayName).tag(period)
            }
        }
        .pickerStyle(.segmented)
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if vm.isLoading && vm.entries.isEmpty {
            loadingState
        } else if let err = vm.errorMessage, vm.entries.isEmpty {
            errorState(err)
        } else if vm.entries.isEmpty {
            emptyState
        } else {
            list
        }
    }

    private var loadingState: some View {
        VStack(spacing: MADTheme.Spacing.md) {
            ProgressView()
                .tint(MADTheme.Colors.madRed)
            Text("Loading rankings…")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, MADTheme.Spacing.xl)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: MADTheme.Spacing.sm) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 24))
                .foregroundColor(.orange.opacity(0.7))
            Text(message)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.7))
            Button("Retry") { vm.refresh() }
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(MADTheme.Colors.madRed)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, MADTheme.Spacing.xl)
    }

    private var emptyState: some View {
        VStack(spacing: MADTheme.Spacing.sm) {
            Image(systemName: vm.metric == .streak ? "flame" : "figure.run")
                .font(.system(size: 28))
                .foregroundColor(.white.opacity(0.25))
            Text(vm.metric == .streak ? "No active streaks yet" : "No miles logged for this range")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.5))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, MADTheme.Spacing.xl)
    }

    private var list: some View {
        VStack(spacing: 6) {
            // Pin the current user's row at the top when they're not already on
            // the visible page — keeps "where am I?" answerable without scrolling.
            if let me = vm.currentUserEntry,
               !vm.entries.contains(where: { $0.is_current_user }) {
                LeaderboardRow(entry: me, metric: vm.metric)
                Divider()
                    .overlay(Color.white.opacity(0.06))
                    .padding(.vertical, 4)
            }

            ForEach(vm.entries) { entry in
                LeaderboardRow(entry: entry, metric: vm.metric)
                    .onAppear {
                        // Trigger next-page fetch when the second-to-last visible
                        // row appears — smoother than waiting for the very last.
                        if let last = vm.entries.last,
                           entry.id == last.id || entry.rank >= last.rank - 1 {
                            vm.loadMore()
                        }
                    }
            }

            if vm.isLoadingMore {
                ProgressView()
                    .tint(MADTheme.Colors.madRed)
                    .padding(.vertical, MADTheme.Spacing.md)
            } else if !vm.hasMore && vm.entries.count > 5 {
                Text("End of leaderboard")
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .tracking(1.2)
                    .foregroundColor(.white.opacity(0.3))
                    .padding(.vertical, MADTheme.Spacing.md)
            }
        }
    }
}

// MARK: - Row

private struct LeaderboardRow: View {
    let entry: LeaderboardEntry
    let metric: LeaderboardMetric

    private var rankColors: [Color] {
        switch entry.rank {
        case 1: return [.yellow, .orange]
        case 2: return [Color(white: 0.85), Color(white: 0.6)]
        case 3: return [Color(red: 0.85, green: 0.55, blue: 0.25), Color(red: 0.6, green: 0.35, blue: 0.15)]
        default: return [Color.white.opacity(0.22), Color.white.opacity(0.08)]
        }
    }

    private var valueText: String {
        switch metric {
        case .miles:
            if entry.value >= 100 {
                return String(format: "%.0f mi", entry.value)
            }
            return String(format: "%.1f mi", entry.value)
        case .streak:
            let days = Int(entry.value)
            return days == 1 ? "1 day" : "\(days) days"
        }
    }

    var body: some View {
        HStack(spacing: MADTheme.Spacing.md) {
            // Rank pill — top 3 get medal gradients, everyone else gets a muted disc.
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(colors: rankColors, startPoint: .top, endPoint: .bottom)
                    )
                    .frame(width: 32, height: 32)
                Text("\(entry.rank)")
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .foregroundColor(entry.rank <= 3 ? .black.opacity(0.7) : .white.opacity(0.75))
            }

            AvatarView(name: entry.displayName, imageURL: entry.profile_image_url, size: 36)
                .overlay(
                    Circle().strokeBorder(entry.is_current_user ? MADTheme.Colors.madRed : Color.clear, lineWidth: 1.5)
                )

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(entry.displayName)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
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
                if let username = entry.username, !username.isEmpty, username != entry.displayName {
                    Text("@\(username)")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.4))
                        .lineLimit(1)
                }
            }

            Spacer()

            Text(valueText)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(entry.rank <= 3 ? .yellow : .white.opacity(0.85))
        }
        .padding(.horizontal, MADTheme.Spacing.md)
        .padding(.vertical, MADTheme.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                .fill(entry.is_current_user ? MADTheme.Colors.madRed.opacity(0.08) : Color.white.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                        .strokeBorder(
                            entry.is_current_user ? MADTheme.Colors.madRed.opacity(0.3) : Color.white.opacity(0.05),
                            lineWidth: 1
                        )
                )
        )
    }
}
