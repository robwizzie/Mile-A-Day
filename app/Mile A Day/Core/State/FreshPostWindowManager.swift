import Foundation
import SwiftUI

/// The 10-minute window that opens when a workout completes with the daily goal
/// met. It drives a post-run countdown and a ring on the compose affordances,
/// and it GATES posting: when it closes, the composer locks until the next
/// qualifying walk or run. Each additional qualifying workout opens its own
/// window, so a second walk earns a second photo.
///
/// It used to also award a "FRESH" chip to posts made while it was open. That
/// chip died with the gate: once a post can ONLY be made inside the window,
/// every post is fresh and the badge marks nothing. The server still stores
/// and serves `posted_fresh`/`is_fresh` for builds that predate the gate — they
/// can still post all day, so the flag stays meaningful for them.
///
/// That gate is the point of the feed. A photo posted six hours after the run
/// is a photo that has nothing to do with anyone moving, and an unbounded
/// composer turns the feed into a general-purpose photo stream that happens to
/// sit next to some mileage. The daily-goal gate (`SocialFeedView.mileDone` +
/// the server's `mile_not_completed` 403) still applies on top of it.
///
/// This is the UX half only. The authority is the server, which recomputes the
/// window from its own `workouts.feed_role` and rejects a late create with
/// `post_window_closed` — so a stale or tampered local window can't buy a post.
/// The two are kept in sync by `duration` here and `POST_WINDOW_MS` in
/// postService.ts; the server additionally allows a private grace on top, so a
/// client counting down to zero is never itself the reason a post is refused.
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

    /// Fires once, at the moment the window closes, purely so SwiftUI re-renders
    /// and the compose affordances lock themselves.
    ///
    /// Needed because `isOpen` reads the wall clock while the publishers only
    /// change on `open()` — nothing else would tell a view that time ran out,
    /// so the "+" would sit there unlocked until some unrelated state moved.
    /// The gate itself never depends on this: every caller that actually
    /// decides something reads `isOpen`, which is correct whether or not the
    /// timer fired. It's a re-render nudge, not a source of truth — which is
    /// also why a timer that didn't fire while backgrounded doesn't matter, as
    /// long as `refresh()` runs on foreground.
    private var expiryTimer: Timer?

    private let defaults = UserDefaults.standard
    private let openedAtKey = "fresh_window_opened_at"
    private let workoutIdKey = "fresh_window_workout_id"
    private let dayKey = "fresh_window_day"

    private init() {
        // Rehydrate only if the stored window is from today; a stale day reads
        // as closed (matches WidgetDataStore's day-stamp behavior).
        if defaults.string(forKey: dayKey) == Self.dayStamp(),
           let opened = defaults.object(forKey: openedAtKey) as? Date {
            windowOpenedAt = opened
            windowWorkoutId = defaults.string(forKey: workoutIdKey)
            scheduleExpiryTick()
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
        scheduleExpiryTick()
    }

    /// Adopt a window the SERVER says is open that this device doesn't have.
    ///
    /// The local window opens from a Dashboard observer watching HealthKit, so
    /// it misses a workout that landed while the app was closed and the user
    /// then opened straight to the Feed tab — the Dashboard's `.task` never
    /// ran, no window exists, and the composer sits locked during the ten
    /// minutes it should be the most inviting. The server computes the same
    /// window from its own `workouts.feed_role` and has no such blind spot.
    ///
    /// Never SHORTENS: an already-open window is left alone unless the server's
    /// anchor is strictly later (a newer workout this device hasn't seen).
    /// Without that, adopting an earlier anchor — the server's is usually a
    /// beat later, but a re-adopt or a second device can invert it — would clip
    /// time off a countdown the user is already watching.
    ///
    /// It also never CLOSES: that stays the local clock's job. The server
    /// carries a private grace, so its `open` outlives ours by design, and
    /// adopting a close would hand users a window that keeps re-opening.
    func adopt(workoutId: String, openedAt: Date) {
        guard Self.dayStamp(for: openedAt) == Self.dayStamp() else { return }
        guard openedAt.timeIntervalSinceNow > -Self.duration else { return }
        if isOpen, let local = windowOpenedAt, openedAt <= local { return }
        open(workoutId: workoutId, at: openedAt)
    }

    /// Re-publish so anything gated on `isOpen` re-evaluates. Call on
    /// foreground: an app that was backgrounded across the close has a timer
    /// that never fired, and would otherwise come back showing an unlocked
    /// composer that the server would then refuse.
    func refresh() {
        scheduleExpiryTick()
        objectWillChange.send()
    }

    private func scheduleExpiryTick() {
        // Always on the main run loop: `scheduledTimer` installs into the
        // CURRENT thread's run loop, and a background thread generally has none
        // running — the timer would simply never fire. `.shared` can be touched
        // first from anywhere, so don't assume the caller's thread.
        let arm = { [weak self] in
            guard let self else { return }
            self.expiryTimer?.invalidate()
            self.expiryTimer = nil
            let remaining = self.secondsRemaining
            guard remaining > 0 else { return }
            self.expiryTimer = Timer.scheduledTimer(
                withTimeInterval: remaining, repeats: false
            ) { [weak self] _ in
                self?.objectWillChange.send()
            }
        }
        if Thread.isMainThread { arm() } else { DispatchQueue.main.async(execute: arm) }
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

    #if DEBUG
    /// Test hook: force the window closed.
    func reset() {
        expiryTimer?.invalidate()
        expiryTimer = nil
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
