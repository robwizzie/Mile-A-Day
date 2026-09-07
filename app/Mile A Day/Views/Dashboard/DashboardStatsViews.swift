import SwiftUI
import HealthKit
import CoreLocation

// MARK: - Stats Grid Component with Toggle

struct StatsGridView: View {
    let user: User
    @ObservedObject var healthManager: HealthKitManager
    @Environment(\.colorScheme) var colorScheme
    @State private var selectedStatsView: UnifiedStatsGrid.StatsViewType = .allTime

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            // Toggle between All Time and Current Streak. The section title
            // comes from the collapsible wrapper on the dashboard, so no
            // duplicate "Your Stats" header here.
            Picker("Stats View", selection: $selectedStatsView) {
                ForEach(UnifiedStatsGrid.StatsViewType.allCases, id: \.self) { type in
                    Text(type.rawValue).tag(type)
                }
            }
            .pickerStyle(SegmentedPickerStyle())

            // Show unified stats view based on selection
            UnifiedStatsGrid(
                user: user,
                healthManager: healthManager,
                statsType: selectedStatsView
            )
        }
        .padding()
        .background(
            ZStack {
                // Liquid glass background
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)

                // Gradient overlay
                LinearGradient(
                    colors: [
                        Color.purple.opacity(0.05),
                        Color.clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .clipShape(RoundedRectangle(cornerRadius: 16))

                // Glass border
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(colorScheme == .dark ? 0.2 : 0.3),
                                Color.clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
        )
        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
    }
}

// MARK: - Stat Card Component

struct StatCard: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(.primary)
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Text(value)
                .font(.headline)
                .foregroundColor(.primary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlassCard()
    }
}

// MARK: - Recent Workouts Component

struct RecentWorkoutsView: View {
    let workouts: [HKWorkout]
    @EnvironmentObject var healthManager: HealthKitManager
    @State private var selectedWorkout: IdentifiableWorkout?
    @State private var displayCount: Int = 10
    /// workoutId → the run's linked post, resolved in ONE batched lookup for the
    /// whole list. Drives the "Photo" badge AND hands the detail its photo
    /// instantly (no per-row re-scan).
    @State private var postsByWorkout: [String: PostItem] = [:]
    /// Re-renders the Counted / Not counted chips when the user overrules a
    /// duplicate from the detail sheet.
    @ObservedObject private var dedupOverrides = WorkoutDedupOverrides.shared
    /// workoutId → its GPS trace, read here rather than by each card: a card
    /// that renders nothing until its own `.task` fills it in never gets one
    /// (ios.md's EmptyView-lifecycle trap). Only the visible prefix is read.
    @State private var routesByWorkout: [String: [CLLocationCoordinate2D]] = [:]

    private static let pageSize: Int = 10

    /// Which of these rows the daily totals actually count, and why not.
    private struct CountState {
        /// workout uuid → the recording that already covers it.
        var excludedBy: [String: String] = [:]
        /// workout uuid → why it isn't counted, so the row can say which.
        var reasons: [String: WorkoutDedup.ExclusionReason] = [:]
        /// Workouts on a day that contains a duplicate. Only these rows show a
        /// Counted / Not counted chip — on an ordinary day the chip would be
        /// on every row and mean nothing.
        var labeled: Set<String> = []
    }

    /// Duplicate detection is a PER-DAY rule, so this flat list has to be
    /// bucketed by local day before applying it — comparing a Tuesday walk
    /// against a Thursday one would pair two unrelated workouts.
    ///
    /// Buckets the whole list, not the visible prefix: a day split across the
    /// "show more" boundary would otherwise lose the partner that explains the
    /// exclusion, and the row would say "not counted" with nothing to point at.
    private var countState: CountState {
        var state = CountState()
        var byDay: [Date: [HKWorkout]] = [:]
        for workout in workouts {
            let day = healthManager.localDay(for: workout)
            byDay[day, default: []].append(workout)
        }
        for (_, dayWorkouts) in byDay {
            // One resolution for both answers — the reason and the recording it
            // points at have to come from the same pass or the label can name a
            // walk that is itself out of the total.
            let breakdown = WorkoutDedup.breakdown(in: dayWorkouts)
            let excluded = breakdown.reasons
            guard !excluded.isEmpty else { continue }
            for workout in dayWorkouts { state.labeled.insert(workout.uuid.uuidString) }
            for (index, reason) in excluded {
                state.reasons[dayWorkouts[index].uuid.uuidString] = reason
            }
            // Only a duplicate has a partner to name; a refused source doesn't.
            for (index, keeper) in breakdown.coveredBy {
                state.excludedBy[dayWorkouts[index].uuid.uuidString] =
                    WorkoutAttribution.sourceLabel(for: dayWorkouts[keeper])
            }
        }
        return state
    }

    var body: some View {
        // Section title comes from the collapsible wrapper on the dashboard,
        // so no duplicate "Recent Workouts" header here.
        VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
            if workouts.isEmpty {
                Text("No recent workouts found")
                    .foregroundColor(.secondary)
                    .padding(.vertical)
            } else {
                let counting = countState
                LazyVStack(spacing: MADTheme.Spacing.md) {
                    ForEach(workouts.prefix(displayCount), id: \.uuid) { workout in
                        workoutCard(workout, counting: counting)
                    }
                }

                if displayCount < workouts.count {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            displayCount = min(displayCount + Self.pageSize, workouts.count)
                        }
                    } label: {
                        Text("Load More")
                            .font(MADTheme.Typography.subheadline)
                            .foregroundColor(MADTheme.Colors.primary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, MADTheme.Spacing.sm)
                    }
                    .buttonStyle(ScaleButtonStyle())
                    .padding(.top, MADTheme.Spacing.xs)
                }
            }
        }
        .padding()
        .cardStyle()
        .sheet(item: $selectedWorkout) { identifiableWorkout in
            // Open a swipeable pager over the whole recent list, starting at the
            // tapped run — handing each page its already-fetched post.
            WorkoutPagerView(
                workouts: workouts,
                startIndex: workouts.firstIndex { $0.uuid == identifiableWorkout.workout.uuid } ?? 0,
                preloadedPosts: postsByWorkout
            )
        }
        .onChange(of: workouts.count) { _, _ in
            // Reset paging when the underlying list changes (e.g., refresh).
            if displayCount > max(Self.pageSize, workouts.count) {
                displayCount = Self.pageSize
            }
        }
        .task {
            await loadLinkedPosts()
        }
        // Only the rows on screen: "Load More" extends the prefix and re-keys
        // this, and the cache means the rows already read cost nothing.
        .task(id: "\(displayCount)-\(workouts.count)") {
            await WorkoutRouteCache.shared.loadTraces(
                for: Array(workouts.prefix(displayCount)),
                using: healthManager
            ) { id, coords in
                routesByWorkout[id] = coords
            }
        }
    }

    /// One row of the list: the workout, and — when it left a GPS trace — its
    /// map, with the flyover on it. Row and map are SIBLINGS inside the card
    /// rather than one button, because the map carries the FLYOVER chip and a
    /// button nested in another button's label doesn't reliably get its taps.
    private func workoutCard(_ workout: HKWorkout, counting: CountState) -> some View {
        let id = workout.uuid.uuidString
        let open = { selectedWorkout = IdentifiableWorkout(workout: workout) }
        return VStack(spacing: 10) {
            Button(action: open) {
                WorkoutRow(
                    workout: workout,
                    showDate: true,
                    hasPhoto: hasRealPhoto(postsByWorkout[id]),
                    isCounted: counting.reasons[id] == nil,
                    showsCountedState: counting.labeled.contains(id),
                    countedInstead: counting.excludedBy[id],
                    exclusionKind: counting.reasons[id]
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(ScaleButtonStyle())

            // A photo alone earns the card too — an indoor walk someone
            // photographed had nothing to show here before.
            let coords = routesByWorkout[id] ?? []
            let photo = WorkoutMediaPreviewCard.photoURL(for: postsByWorkout[id])
            if coords.count >= 2 || photo != nil {
                WorkoutMediaPreviewCard(
                    workout: workout,
                    coordinates: coords,
                    photoURL: photo,
                    onOpen: open
                )
            }
        }
        .padding(MADTheme.Spacing.md)
        .madLiquidGlass()
    }

    /// Same resolution the preview card uses, so a row badged "Photo" always
    /// has a picture under it.
    private func hasRealPhoto(_ post: PostItem?) -> Bool {
        WorkoutMediaPreviewCard.photoURL(for: post) != nil
    }

    /// One batched pass over the user's own recent posts, keyed by workout, so
    /// each row can badge a photo, preview it, AND hand the detail its picture
    /// instantly. Two pages (~48 posts) comfortably covers this window.
    private func loadLinkedPosts() async {
        guard postsByWorkout.isEmpty,
              let uid = UserManager.shared.currentUser.backendUserId else { return }
        let resolved = await PostService.fetchOwnPostsByWorkout(userId: uid, pages: 2)
        await MainActor.run { postsByWorkout = resolved }
    }
}

// MARK: - Recent Workouts Preview (dashboard)

/// Compact dashboard card: a peek at the few most-recent workouts — each with
/// its map or its photo — and a "See All" that PUSHES the full Workouts screen
/// (calendar + history + swipeable detail) as its own page.
///
/// The flag is owned by DashboardView so its `navigationDestination` can sit on
/// the stack root; this card only sets it.
///
/// NOT one big Button any more, and that is load-bearing rather than tidiness:
/// the media card carries the FLYOVER chip, and a Button nested in another
/// Button's label doesn't reliably get its taps (ios.md). The header and each
/// row are their own buttons instead, so every part of the card still opens
/// the Workouts screen exactly as it used to — and the chip on the map now
/// launches the flight instead of being swallowed.
struct RecentWorkoutsPreviewCard: View {
    @ObservedObject var healthManager: HealthKitManager
    @Binding var showWorkouts: Bool

    /// workoutId → its GPS trace / its post, read by the HOST for the same
    /// reason the other two lists do it: a card that draws nothing until its
    /// own `.task` fills it in never gets one (the EmptyView-lifecycle trap).
    @State private var routesByWorkout: [String: [CLLocationCoordinate2D]] = [:]
    @State private var postsByWorkout: [String: PostItem] = [:]

    private var preview: [HKWorkout] { Array(healthManager.recentWorkouts.prefix(3)) }

    /// Shorter than the full screen's 150: three maps stacked on a dashboard
    /// that already carries the hero, the day's cards and the medals is a lot
    /// of scroll, and this is a peek rather than the history.
    private static let mapHeight: CGFloat = 120

    var body: some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
            header
            content
        }
        .padding()
        .cardStyle()
        .task { await loadLinkedPosts() }
        // Keyed on the previewed workouts themselves: a sync landing while the
        // dashboard is open swaps one out, and a fixed key would leave the new
        // walk mapless until the next launch. Already-read traces cost nothing
        // (WorkoutRouteCache), so re-running is cheap.
        .task(id: preview.map { $0.uuid.uuidString }.joined(separator: ",")) {
            await WorkoutRouteCache.shared.loadTraces(
                for: preview,
                using: healthManager
            ) { id, coords in
                routesByWorkout[id] = coords
            }
        }
    }

    private var header: some View {
        Button {
            showWorkouts = true
        } label: {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "figure.run")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(MADTheme.Colors.redGradient)
                        .accessibilityHidden(true)
                    Text("Recent Workouts")
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                        .foregroundColor(.primary)
                }
                Spacer()
                HStack(spacing: 3) {
                    Text("See All")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .accessibilityHidden(true)
                }
                .foregroundColor(MADTheme.Colors.madRed)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Recent workouts, see all")
    }

    @ViewBuilder
    private var content: some View {
        if preview.isEmpty {
            if healthManager.hasLoadedRecentWorkoutsOnce {
                // A successful query genuinely returned nothing.
                Text("No recent workouts yet — log a run to see it here.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
                    .padding(.vertical, MADTheme.Spacing.sm)
            } else {
                // Not loaded yet (or a locked-device query is still retrying) —
                // show loading, never the "no workouts" copy, which read as
                // "your workouts vanished" on a cold launch.
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Loading recent workouts…")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, MADTheme.Spacing.sm)
            }
        } else {
            VStack(spacing: MADTheme.Spacing.sm) {
                ForEach(preview, id: \.uuid) { workout in
                    row(workout)
                }
            }
        }
    }

    /// One peeked workout: the row, and its media when there is any. A
    /// function, not inline in the `ForEach` — the same reason the other two
    /// lists extract theirs, which is that the type-checker gives up otherwise.
    private func row(_ workout: HKWorkout) -> some View {
        let id = workout.uuid.uuidString
        let coords = routesByWorkout[id] ?? []
        let photo = WorkoutMediaPreviewCard.photoURL(for: postsByWorkout[id])
        let open = { showWorkouts = true }
        return VStack(spacing: 8) {
            Button(action: open) {
                WorkoutRow(workout: workout, showDate: true, hasPhoto: photo != nil)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if coords.count >= 2 || photo != nil {
                WorkoutMediaPreviewCard(
                    workout: workout,
                    coordinates: coords,
                    photoURL: photo,
                    onOpen: open,
                    height: Self.mapHeight
                )
            }
        }
        .padding(MADTheme.Spacing.sm)
        .background(Color.white.opacity(0.04))
        .cornerRadius(MADTheme.CornerRadius.medium)
    }

    /// One page is enough for a three-row peek.
    private func loadLinkedPosts() async {
        guard postsByWorkout.isEmpty,
              let uid = UserManager.shared.currentUser.backendUserId else { return }
        let resolved = await PostService.fetchOwnPostsByWorkout(userId: uid, pages: 1)
        await MainActor.run { postsByWorkout = resolved }
    }
}
