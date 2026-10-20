import SwiftUI
import HealthKit

/// Swipe horizontally to move between workouts — each page is a full
/// `WorkoutDetailView`. Used wherever a list of workouts is already in context
/// (the recent list, a calendar day) so tapping one lets you flick through the
/// rest without backing out to the list each time.
struct WorkoutPagerView: View {
    /// The pages, snapshotted once when the pager opens and deduped by uuid.
    /// HealthKit republishes its lists with fresh `HKWorkout` objects (and,
    /// around a sync, the same walk twice); feeding that straight into a
    /// page-style TabView made it rebuild or double a page, and the detail
    /// flickered between its loaded and never-loaded copies.
    @State private var workouts: [HKWorkout]
    /// workoutId → its already-fetched linked post, so the photo shows instantly
    /// instead of re-scanning pages of posts inside the detail.
    let preloadedPosts: [String: PostItem]
    @State private var index: Int

    init(
        workouts: [HKWorkout],
        startIndex: Int,
        preloadedPosts: [String: PostItem] = [:]
    ) {
        var seen = Set<UUID>()
        let unique = workouts.filter { seen.insert($0.uuid).inserted }
        self._workouts = State(initialValue: unique)
        self.preloadedPosts = preloadedPosts
        // The start index was computed against the caller's list; find the
        // same workout in the deduped one.
        let start = workouts.indices.contains(startIndex) ? workouts[startIndex].uuid : nil
        let mapped = start.flatMap { id in unique.firstIndex { $0.uuid == id } } ?? 0
        self._index = State(initialValue: unique.isEmpty ? 0 : min(max(mapped, 0), unique.count - 1))
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $index) {
                ForEach(Array(workouts.enumerated()), id: \.element.uuid) { i, workout in
                    WorkoutDetailView(
                        workout: workout,
                        preloadedPost: preloadedPosts[workout.uuid.uuidString],
                        isActive: i == index
                    )
                    .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()

            // A quiet position hint so the swipe is discoverable without a row
            // of dots (there can be dozens of workouts).
            if workouts.count > 1 {
                Text("\(index + 1) of \(workouts.count)")
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.black.opacity(0.45)))
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.15), lineWidth: 1))
                    .padding(.bottom, 6)
                    .allowsHitTesting(false)
            }
        }
    }
}
