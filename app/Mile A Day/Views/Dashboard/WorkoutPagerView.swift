import SwiftUI
import HealthKit

/// Swipe horizontally to move between workouts — each page is a full
/// `WorkoutDetailView`. Used wherever a list of workouts is already in context
/// (the recent list, a calendar day) so tapping one lets you flick through the
/// rest without backing out to the list each time.
struct WorkoutPagerView: View {
    let workouts: [HKWorkout]
    /// workoutId → its already-fetched linked post, so the photo shows instantly
    /// instead of re-scanning pages of posts inside the detail.
    let preloadedPosts: [String: PostItem]
    @State private var index: Int

    init(
        workouts: [HKWorkout],
        startIndex: Int,
        preloadedPosts: [String: PostItem] = [:]
    ) {
        self.workouts = workouts
        self.preloadedPosts = preloadedPosts
        let safe = workouts.isEmpty ? 0 : min(max(startIndex, 0), workouts.count - 1)
        self._index = State(initialValue: safe)
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
