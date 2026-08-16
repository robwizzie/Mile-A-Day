import ActivityKit
import Foundation

/// Keeps the workout Live Activity fresh while the app is alive but the
/// tracker VIEW isn't driving updates.
///
/// Every Live Activity push carries `staleDate = now + 180s`, and the only
/// periodic pusher used to be the tracker view's 1 Hz timer — which stops in
/// the two most ordinary situations of a real walk: the phone locks (view
/// timers suspend in the background; ios.md), or the user dismisses the
/// tracker to look at the dashboard (`.onDisappear` invalidates it). Three
/// minutes later the lock screen flipped to TRACKING INTERRUPTED while the
/// workout underneath was accruing perfectly — read by users as a connection
/// problem the app didn't have.
///
/// So the keep-alive rides `WorkoutLocationManager`'s pause heartbeat — the
/// same background-alive driver as the movement witnesses, running for both
/// outdoor and indoor sessions — and re-pushes the activity's own current
/// content with just the live fields refreshed. Fields this helper can't
/// recompute (ghost delta, hypes, streak) carry over unchanged; the view's
/// richer 1 Hz path overwrites them whenever it's running.
///
/// The stale flip still fires when it should: if iOS kills the app, this dies
/// with it, no push lands, and INTERRUPTED is then the truth (layered with
/// the dead-man watchdog notification).
///
/// Main thread only — called from the heartbeat timer and self-throttled, so
/// foreground overlap with the view's 30s pushes is a harmless duplicate.
enum WorkoutLiveActivityKeepAlive {
    private static var lastBeatAt = Date.distantPast
    /// Half the stale margin: one dropped beat still leaves one more chance
    /// to renew before the system dims the activity.
    private static let beatInterval: TimeInterval = 60
    /// Matches the margin the view's pushes carry.
    private static let staleMargin: TimeInterval = 180

    static func beat() {
        let now = Date()
        guard now.timeIntervalSince(lastBeatAt) >= beatInterval else { return }
        // Only while a workout is genuinely in progress: the finish path pushes
        // its own final content (staleDate nil) and clears the store, and a
        // beat racing that must not resurrect a live-looking card.
        guard let saved = InProgressWorkoutStore.load(), saved.isActive else { return }
        guard let activity = Activity<WorkoutActivityAttributes>.activities.first else {
            return
        }
        lastBeatAt = now

        let manager = WorkoutLocationManager.shared
        // Start from what's already on screen, refresh only what this layer
        // can measure. `liveDistance` is THE workout number everywhere.
        var state = activity.content.state
        state.distance = manager.liveDistance
        state.totalDailyDistance = saved.startingDistance + manager.liveDistance
        // Pause-excluded, and the anchor is DROPPED while paused. This beat
        // rides the manager's heartbeat, which keeps running through a pause —
        // re-stamping a live anchor here would restart the system-rendered
        // clock on the lock screen a minute after the user froze the workout.
        let elapsed = max(0, now.timeIntervalSince(saved.startTime) - manager.pausedSeconds)
        state.elapsedTime = elapsed
        state.timerStartDate = manager.isPaused ? nil : now.addingTimeInterval(-elapsed)
        state.movingSeconds = manager.movingSeconds
        state.isAutoPaused = manager.isAutoPaused
        state.isPaused = manager.isPaused

        let content = ActivityContent(
            state: state, staleDate: now.addingTimeInterval(staleMargin))
        Task {
            await activity.update(content)
        }
    }
}
