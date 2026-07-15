import Foundation
import SwiftUI

/// The 10-minute "fresh window" that opens when a workout completes with the
/// daily goal met. It is a POSITIVE nudge to share in the moment — it drives a
/// post-run countdown, a ring on the compose affordances, and a "Fresh" badge
/// on posts made while it is open. It never BLOCKS posting: the daily-goal gate
/// (`SocialFeedView.mileDone` + the server's `mile_not_completed` 403) is the
/// only thing that gates the composer. When this window closes the user can
/// still post the rest of the day exactly as before — they just don't earn the
/// "Fresh" reward. Each additional qualifying walk/run opens its own window.
///
/// Anchored to OBSERVATION time (when the app first sees the finished workout),
/// never `HKWorkout.endDate`: a Watch run whose `endDate` is 20 min old still
/// gets a full window at the moment it syncs in, which is exactly when the user
/// can actually post it.
///
/// Persisted to plain `UserDefaults.standard` (NOT the `group.mileaday.shared`
/// App Group): no widget consumes it, and staying out of the group avoids
/// spending the rationed widget-reload budget. Day-stamped like `WidgetDataStore`
/// so a window left open across midnight reads as closed.
final class FreshPostWindowManager: ObservableObject {
    static let shared = FreshPostWindowManager()

    /// How long a fresh window stays open after a qualifying workout.
    static let duration: TimeInterval = 600 // 10 minutes

    /// Re-entrancy reconcile window: `open()` fires from several DashboardView
    /// observers in one tick, and an optional early stamp in WorkoutTrackingView
    /// lands ~500 ms before the Dashboard stamp. A window opened this recently
    /// (any id) is treated as the SAME finish event so the two form one
    /// continuous countdown instead of restarting it.
    private static let reconcile: TimeInterval = 3

    /// Published so SwiftUI re-renders when a window opens or resets. The
    /// per-second countdown itself is driven by the views (a gated 1 Hz tick /
    /// `Text(timerInterval:)`), since `secondsRemaining` reads the wall clock.
    @Published private(set) var windowOpenedAt: Date?
    @Published private(set) var windowWorkoutId: String?

    private let defaults = UserDefaults.standard
    private let openedAtKey = "fresh_window_opened_at"
    private let workoutIdKey = "fresh_window_workout_id"
    private let dayKey = "fresh_window_day"
    private let postedLiveKeysKey = "fresh_window_posted_live_keys"
    private let postedLiveDayKey = "fresh_window_posted_live_day"

    private init() {
        // Rehydrate only if the stored window is from today; a stale day reads
        // as closed (matches WidgetDataStore's day-stamp behavior).
        if defaults.string(forKey: dayKey) == Self.dayStamp(),
           let opened = defaults.object(forKey: openedAtKey) as? Date {
            windowOpenedAt = opened
            windowWorkoutId = defaults.string(forKey: workoutIdKey)
        }
    }

    /// Device-local day stamp, pinned to a Gregorian/POSIX formatter so a
    /// non-Gregorian device calendar can't emit keys that never match.
    private static func dayStamp(for date: Date = Date()) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    // MARK: - Open / reset

    /// Open (or reset) the fresh window for a completed qualifying workout.
    /// Idempotent for the SAME workout on the SAME day so the many re-entrant
    /// observers don't restart the countdown; a NEW `workoutId` resets to a
    /// full window so each extra qualifying walk/run earns its own 10 minutes.
    /// `at` defaults to now — the observation time, never a workout's `endDate`.
    func open(workoutId: String, at date: Date = Date()) {
        let today = Self.dayStamp(for: date)

        // Same workout, still today, still open → no-op (don't restart it).
        if defaults.string(forKey: dayKey) == today,
           windowWorkoutId == workoutId,
           let opened = windowOpenedAt,
           date.timeIntervalSince(opened) < Self.duration {
            return
        }

        // A window opened moments ago (any id) is the same finish event seen by
        // a second observer — keep its anchor, just record the real workout id.
        if defaults.string(forKey: dayKey) == today,
           let opened = windowOpenedAt,
           (0..<Self.reconcile).contains(date.timeIntervalSince(opened)) {
            windowWorkoutId = workoutId
            defaults.set(workoutId, forKey: workoutIdKey)
            return
        }

        // Fresh window.
        windowOpenedAt = date
        windowWorkoutId = workoutId
        defaults.set(date, forKey: openedAtKey)
        defaults.set(workoutId, forKey: workoutIdKey)
        defaults.set(today, forKey: dayKey)
    }

    // MARK: - Queries

    var isOpen: Bool { secondsRemaining > 0 }

    var secondsRemaining: TimeInterval {
        guard defaults.string(forKey: dayKey) == Self.dayStamp(),
              let opened = windowOpenedAt else { return 0 }
        return max(0, Self.duration - Date().timeIntervalSince(opened))
    }

    /// End instant for `Text(timerInterval:)`. Falls back to now when closed.
    var windowEndDate: Date {
        (windowOpenedAt ?? Date()).addingTimeInterval(Self.duration)
    }

    /// True when the window is open AND scoped to this specific workout — used
    /// to scope the post-run prompt's pill to the run that just finished.
    func isOpen(forWorkout id: String) -> Bool {
        isOpen && windowWorkoutId == id
    }

    // MARK: - "Posted live" reward (client-only for v1)

    /// Keys (post ids AND workout ids) posted while the window was open today.
    /// Day-stamped so yesterday's "Fresh" badges don't linger into a new day.
    private var postedLiveKeys: Set<String> {
        guard defaults.string(forKey: postedLiveDayKey) == Self.dayStamp(),
              let arr = defaults.array(forKey: postedLiveKeysKey) as? [String] else {
            return []
        }
        return Set(arr)
    }

    /// Record a just-published post as "fresh" when it went out during the
    /// window. Stores the post id AND the linked workout id, so the feed can
    /// match either (a raw-workout entry replaced by a post keys on workout id).
    func markPostedLive(postId: String?, workoutId: String?) {
        guard isOpen else { return }
        var keys = postedLiveKeys
        if let postId, !postId.isEmpty { keys.insert(postId) }
        if let workoutId, !workoutId.isEmpty { keys.insert(workoutId) }
        defaults.set(Array(keys), forKey: postedLiveKeysKey)
        defaults.set(Self.dayStamp(), forKey: postedLiveDayKey)
        objectWillChange.send()
    }

    /// Whether a feed entry (matched by post id or workout id) was posted live
    /// today — drives the "Fresh" badge on the poster's own cards.
    func wasPostedLive(postId: String?, workoutId: String?) -> Bool {
        let keys = postedLiveKeys
        if let postId, keys.contains(postId) { return true }
        if let workoutId, keys.contains(workoutId) { return true }
        return false
    }

    #if DEBUG
    /// Test hook: force the window closed.
    func reset() {
        windowOpenedAt = nil
        windowWorkoutId = nil
        defaults.removeObject(forKey: openedAtKey)
        defaults.removeObject(forKey: workoutIdKey)
        defaults.removeObject(forKey: dayKey)
    }
    #endif
}

/// A thin countdown ring drawn around content (the compose FAB, a story "+"
/// cell). Self-ticks via `TimelineView` from `openedAt`, so it needs no parent
/// timer and stops the moment it's unmounted (i.e. when the window closes and
/// the parent stops showing it). Once the window elapses the trim reaches 0 and
/// nothing is drawn, so it also self-hides even before the parent re-renders.
/// Decoupled from the manager — callers pass a plain `openedAt`, not the
/// singleton — so components like `StoriesRailView` stay independent.
struct FreshWindowRing: View {
    let openedAt: Date
    var duration: TimeInterval = FreshPostWindowManager.duration
    var color: Color = .white
    var lineWidth: CGFloat = 3

    var body: some View {
        TimelineView(.periodic(from: openedAt, by: 1)) { context in
            let remaining = max(0, duration - context.date.timeIntervalSince(openedAt))
            let fraction = duration > 0 ? remaining / duration : 0
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}
