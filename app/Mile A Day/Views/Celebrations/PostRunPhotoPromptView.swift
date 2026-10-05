import SwiftUI

/// The solo finale after a walk or run: the shared `PhotoPromptView`, shown
/// as the LAST celebration in the queue.
///
/// Everything you see is `PhotoPromptView` (the buddy walk's post step draws
/// the same view). What's particular to this door is what an outcome MEANS:
/// skipping — or sharing the photo to a story only — hands the walk to
/// `RunPostService.autoPostMile`, which posts the route/stats card when the
/// "Post my route when I skip" setting says so; either way the walk's
/// mid-run snaps are spent and the celebration is dismissed.
struct PostRunPhotoPromptView: View {
    let workoutId: String
    let workoutType: String

    @ObservedObject private var manager = CelebrationManager.shared
    /// The same figures the card bakes, resolved once for this presentation.
    @State private var stats: RunStatsInput?

    var body: some View {
        PhotoPromptView(
            workoutId: workoutId,
            workoutType: workoutType,
            stats: stats ?? RunPostService.todayStats(workoutId: workoutId),
            skipTitle: "Skip",
            // Read so the note can't promise something the setting turned off.
            skipNote: NotificationPreferences.load().autoPostWithoutPhoto
                ? "Your route and stats will still post" : nil,
            onEngage: { manager.photoPromptEngaged = true },
            onFinish: { outcome in
                switch outcome {
                case .skipped, .published(toFeed: false):
                    // No feed photo — the feed still gets the walk's card.
                    Task { await RunPostService.autoPostMile(workoutId: workoutId, workoutType: workoutType) }
                case .published:
                    break
                }
                // The run's snaps are one-shot offers: whatever wasn't chosen
                // is gone once the prompt resolves (posted, skipped, story-only).
                MidRunPhotoStash.clear()
                manager.dismissCurrentCelebration()
            }
        )
        .onAppear {
            if stats == nil { stats = RunPostService.todayStats(workoutId: workoutId) }
        }
    }
}
