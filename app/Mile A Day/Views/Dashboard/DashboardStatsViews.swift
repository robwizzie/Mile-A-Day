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
    /// Workout IDs that have a real linked photo, resolved in ONE batched
    /// lookup for the whole list (never per row).
    @State private var photoWorkoutIds: Set<String> = []

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
                                hasPhoto: photoWorkoutIds.contains(workout.uuid.uuidString)
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
            WorkoutDetailView(workout: identifiableWorkout.workout)
        }
        .onChange(of: workouts.count) { _, _ in
            // Reset paging when the underlying list changes (e.g., refresh).
            if displayCount > max(Self.pageSize, workouts.count) {
                displayCount = Self.pageSize
            }
        }
        .task {
            await loadPhotoFlags()
        }
    }

    /// One batched pass over the user's own recent posts builds the set of
    /// workout IDs that have a real photo, so each row can show a "Photo" chip
    /// without its own network call. Best-effort — failure just leaves chips off.
    private func loadPhotoFlags() async {
        guard photoWorkoutIds.isEmpty,
              let uid = UserManager.shared.currentUser.backendUserId else { return }

        var ids = Set<String>()
        var before: String? = nil
        // Two pages (~48 posts) comfortably covers the recent-workouts window.
        for _ in 0..<2 {
            guard let page = try? await PostService.fetchUserPosts(
                userId: uid, before: before, includeStories: true
            ) else { break }
            for post in page.items {
                guard let wid = post.workout_id else { continue }
                let hasRealPhoto = post.storyPhotoURL != nil
                    || (post.is_auto != true && !post.media_url.isEmpty)
                if hasRealPhoto { ids.insert(wid) }
            }
            guard let next = page.next_before else { break }
            before = next
        }

        let resolved = ids
        await MainActor.run { photoWorkoutIds = resolved }
    }
}
