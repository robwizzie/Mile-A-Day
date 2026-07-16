import SwiftUI
import HealthKit

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

    private static let pageSize: Int = 10

    var body: some View {
        // Section title comes from the collapsible wrapper on the dashboard,
        // so no duplicate "Recent Workouts" header here.
        VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
            if workouts.isEmpty {
                Text("No recent workouts found")
                    .foregroundColor(.secondary)
                    .padding(.vertical)
            } else {
                LazyVStack(spacing: MADTheme.Spacing.md) {
                    ForEach(workouts.prefix(displayCount), id: \.uuid) { workout in
                        Button {
                            selectedWorkout = IdentifiableWorkout(workout: workout)
                        } label: {
                            WorkoutRow(
                                workout: workout,
                                showDate: true,
                                hasPhoto: hasRealPhoto(postsByWorkout[workout.uuid.uuidString])
                            )
                            .padding(MADTheme.Spacing.md)
                            .madLiquidGlass()
                        }
                        .buttonStyle(ScaleButtonStyle())
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
    }

    /// A post has a real photo when it carries a story picture or a deliberate
    /// (non-auto) photo — auto route/stats cards don't count.
    private func hasRealPhoto(_ post: PostItem?) -> Bool {
        guard let post else { return false }
        if post.storyPhotoURL != nil { return true }
        return post.is_auto != true && !post.media_url.isEmpty
    }

    /// One batched pass over the user's own recent posts, keyed by workout, so
    /// each row can badge a photo AND the detail can show it instantly. Best
    /// effort — failure leaves badges off and the detail falls back to its own
    /// fetch.
    private func loadLinkedPosts() async {
        guard postsByWorkout.isEmpty,
              let uid = UserManager.shared.currentUser.backendUserId else { return }

        var map: [String: PostItem] = [:]
        var before: String? = nil
        // Two pages (~48 posts) comfortably covers the recent-workouts window.
        for _ in 0..<2 {
            guard let page = try? await PostService.fetchUserPosts(
                userId: uid, before: before, includeStories: true
            ) else { break }
            for post in page.items {
                guard let wid = post.workout_id, map[wid] == nil else { continue }
                map[wid] = post
            }
            guard let next = page.next_before else { break }
            before = next
        }

        let resolved = map
        await MainActor.run { postsByWorkout = resolved }
    }
}

// MARK: - Recent Workouts Preview (dashboard)

/// Compact dashboard card: a peek at the few most-recent workouts with a
/// "See All" that opens the full Workouts screen (calendar + history + swipeable
/// detail). Replaces the old buried collapsible list.
struct RecentWorkoutsPreviewCard: View {
    @ObservedObject var healthManager: HealthKitManager
    @State private var showWorkouts = false

    private var preview: [HKWorkout] { Array(healthManager.recentWorkouts.prefix(3)) }

    var body: some View {
        Button {
            showWorkouts = true
        } label: {
            VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
                HStack {
                    HStack(spacing: 8) {
                        Image(systemName: "figure.run")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(MADTheme.Colors.redGradient)
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
                    }
                    .foregroundColor(MADTheme.Colors.madRed)
                }

                if preview.isEmpty {
                    Text("No recent workouts yet — log a run to see it here.")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(.secondary)
                        .padding(.vertical, MADTheme.Spacing.sm)
                } else {
                    VStack(spacing: MADTheme.Spacing.sm) {
                        ForEach(preview, id: \.uuid) { workout in
                            WorkoutRow(workout: workout, showDate: true)
                                .padding(MADTheme.Spacing.sm)
                                .background(Color.white.opacity(0.04))
                                .cornerRadius(MADTheme.CornerRadius.medium)
                        }
                    }
                }
            }
            .padding()
            .cardStyle()
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showWorkouts) {
            WorkoutsView(healthManager: healthManager)
        }
    }
}
