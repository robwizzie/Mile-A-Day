import Foundation
import SwiftUI

/// What a finished walk or run unlocks for photos, in TWO tiers.
///
///  - **The camera tier** (`isCameraOpen`): ten minutes from the moment a
///    qualifying workout lands. Taking a photo says "this is happening now",
///    and that claim expires — so the in-app camera does too, with a visible
///    countdown while it's live.
///  - **The day tier** (`canPostToday`): the rest of the day, once any
///    qualifying walk or run has landed. A photo the user already TOOK on the
///    walk is proven to belong to it by when it was shot, not by how quickly
///    they got back to their phone — so picking one out of the camera roll
///    isn't on a clock. Neither is promoting a story they already posted.
///
/// Both tiers still need the walk. Doing nothing all day unlocks nothing, which
/// is the rule that actually keeps this feed about moving; the ten minutes were
/// never carrying that weight on their own. What they were doing was making
/// people choose between their cooldown and their photo, and losing.
///
/// The window used to also award a "FRESH" chip to posts made while it was
/// open. That chip died with the gate: once a post could ONLY be made inside
/// the window, every post was fresh and the badge marked nothing. The server
/// still stores and serves `posted_fresh`/`is_fresh` for builds that predate
/// the gate — they can still post all day, so the flag stays meaningful there.
///
/// The daily-goal gate (`SocialFeedView.mileDone` + the server's
/// `mile_not_completed` 403) applies on top of both tiers.
///
/// This is the UX half only. The authority is the server, which recomputes both
/// tiers from its own `workouts.feed_role` and rejects a late create with
/// `post_window_closed` — so a stale or tampered local window can't buy a post.
/// `duration` here and `POST_WINDOW_MS` in postService.ts must stay equal; the
/// server additionally allows a private grace on top, so a client counting down
/// to zero is never itself the reason a post is refused.
///
/// Anchored to OBSERVATION time (when the app first sees the finished workout),
/// never `HKWorkout.endDate`: a Watch run whose `endDate` is 20 min old still
/// gets a full camera window at the moment it syncs in, which is exactly when
/// the user could first have used it.
///
/// Persisted to plain `UserDefaults.standard` (NOT the `group.mileaday.shared`
/// App Group): no widget consumes it, and staying out of the group avoids
/// spending the rationed widget-reload budget. Day-stamped like `WidgetDataStore`
/// so both tiers read as closed once the day rolls over.
final class FreshPostWindowManager: ObservableObject {
    static let shared = FreshPostWindowManager()

    /// How long the CAMERA stays open after a qualifying workout.
    static let duration: TimeInterval = 600 // 10 minutes

    /// Re-entrancy reconcile window: `open()` fires from several DashboardView
    /// observers in one tick, and an optional early stamp in WorkoutTrackingView
    /// lands ~500 ms before the Dashboard stamp. A window opened this recently
    /// (any id) is treated as the SAME finish event so the two form one
    /// continuous countdown instead of restarting it.
    private static let reconcile: TimeInterval = 3

    /// Published so SwiftUI re-renders when a window opens or resets. The
    /// per-second countdown itself is driven by the views (a gated 1 Hz tick /
    /// `Text(timerInterval:)`), since `cameraSecondsRemaining` reads the wall
    /// clock.
    @Published private(set) var windowOpenedAt: Date?
    @Published private(set) var windowWorkoutId: String?

    /// The day tier: the most recent qualifying walk/run seen TODAY, which
    /// stays set long after its camera window lapses. This is what a
    /// camera-roll pick and a story promotion are allowed against, and it's
    /// the id the composer attaches such a post to.
    @Published private(set) var todaysWorkoutId: String?

    /// Fires once, at the moment the CAMERA window closes, purely so SwiftUI
    /// re-renders and the capture affordances retire themselves.
    ///
    /// Needed because `isCameraOpen` reads the wall clock while the publishers
    /// only change on `open()` — nothing else would tell a view that time ran
    /// out, so a "Take a photo" button would sit there live until some
    /// unrelated state moved. The gate itself never depends on this: every
    /// caller that actually decides something reads `isCameraOpen`, which is
    /// correct whether or not the timer fired. It's a re-render nudge, not a
    /// source of truth — which is also why a timer that didn't fire while
    /// backgrounded doesn't matter, as long as `refresh()` runs on foreground.
    private var expiryTimer: Timer?

    private let defaults = UserDefaults.standard
    private let openedAtKey = "fresh_window_opened_at"
    private let workoutIdKey = "fresh_window_workout_id"
    private let dayKey = "fresh_window_day"
    private let dayWorkoutIdKey = "post_day_workout_id"
    private let anchoredIdsKey = "post_camera_anchored_ids"

    private init() {
        // Rehydrate only if the stored state is from today; a stale day reads
        // as closed (matches WidgetDataStore's day-stamp behavior).
        guard defaults.string(forKey: dayKey) == Self.dayStamp() else { return }
        todaysWorkoutId = defaults.string(forKey: dayWorkoutIdKey)
        if let opened = defaults.object(forKey: openedAtKey) as? Date {
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

    /// Record a completed qualifying workout: opens the day tier, and opens (or
    /// resets) the camera countdown.
    ///
    /// Idempotent for the SAME workout on the SAME day so the many re-entrant
    /// observers don't restart the countdown; a NEW `workoutId` resets to a
    /// full ten minutes, so each extra qualifying walk/run earns its own
    /// camera window. `at` defaults to now — the observation time, never a
    /// workout's `endDate`.
    func open(workoutId: String, at date: Date = Date()) {
        let today = Self.dayStamp(for: date)
        let isToday = defaults.string(forKey: dayKey) == today
        if !isToday { resetDay(to: today) }

        // Day tier first: it's unconditional, and it must survive even when
        // the camera anchor below is deliberately skipped.
        if todaysWorkoutId != workoutId {
            todaysWorkoutId = workoutId
            defaults.set(workoutId, forKey: dayWorkoutIdKey)
        }

        // A workout that already had its ten minutes today never gets them
        // again. The Dashboard observers re-fire on every HealthKit refresh, so
        // without this a workout seen again an hour later would silently
        // resurrect a camera window the user already watched close.
        guard !anchoredIds.contains(workoutId) else { return }

        // A window opened moments ago (any id) is the same finish event seen by
        // a second observer — keep its anchor, just record the real workout id.
        if let opened = windowOpenedAt,
           (0..<Self.reconcile).contains(date.timeIntervalSince(opened)) {
            windowWorkoutId = workoutId
            defaults.set(workoutId, forKey: workoutIdKey)
            rememberAnchored(workoutId)
            return
        }

        // Fresh camera window.
        windowOpenedAt = date
        windowWorkoutId = workoutId
        defaults.set(date, forKey: openedAtKey)
        defaults.set(workoutId, forKey: workoutIdKey)
        rememberAnchored(workoutId)
        scheduleExpiryTick()
    }

    /// Clear yesterday's state and stamp the new day. Without this the day tier
    /// would inherit a stale `todaysWorkoutId` from the last time the app ran.
    private func resetDay(to day: String) {
        windowOpenedAt = nil
        windowWorkoutId = nil
        todaysWorkoutId = nil
        defaults.removeObject(forKey: openedAtKey)
        defaults.removeObject(forKey: workoutIdKey)
        defaults.removeObject(forKey: dayWorkoutIdKey)
        defaults.removeObject(forKey: anchoredIdsKey)
        defaults.set(day, forKey: dayKey)
    }

    /// Workout ids that have already spent their camera window today.
    private var anchoredIds: [String] {
        defaults.stringArray(forKey: anchoredIdsKey) ?? []
    }

    private func rememberAnchored(_ workoutId: String) {
        var ids = anchoredIds
        guard !ids.contains(workoutId) else { return }
        // Bounded: a day of legs plus imports, never unbounded growth.
        ids.append(workoutId)
        if ids.count > 40 { ids.removeFirst(ids.count - 40) }
        defaults.set(ids, forKey: anchoredIdsKey)
    }

    /// Adopt what the SERVER knows about today that this device doesn't.
    ///
    /// Local state opens from a Dashboard observer watching HealthKit, so it
    /// misses a workout that landed while the app was closed and the user then
    /// opened straight to the Feed tab — the Dashboard's `.task` never ran,
    /// nothing is recorded, and the composer sits locked on a day the user
    /// definitely walked. The server derives both tiers from its own
    /// `workouts.feed_role` and has no such blind spot.
    ///
    /// The DAY tier is adopted whenever the server reports a qualifying workout
    /// for today — that's the common case here, and the one the old
    /// window-only adopt couldn't express: a walk from this morning unlocks
    /// nothing on the camera but everything on the camera roll.
    ///
    /// The CAMERA tier is adopted only when the server says it's genuinely
    /// live. It never SHORTENS (an already-open countdown is left alone unless
    /// the server's anchor is strictly later — a newer workout this device
    /// hasn't seen; adopting an earlier anchor would clip time off a countdown
    /// the user is already watching) and it never CLOSES (that stays the local
    /// clock's job — the server carries a private grace, so its answer outlives
    /// ours by design, and adopting a close would hand users a window that
    /// keeps re-opening).
    func adopt(workoutId: String, openedAt: Date, cameraOpen: Bool) {
        guard Self.dayStamp(for: openedAt) == Self.dayStamp() else { return }

        // Day tier: unconditional for a workout dated today.
        if defaults.string(forKey: dayKey) != Self.dayStamp() {
            resetDay(to: Self.dayStamp())
        }
        if todaysWorkoutId != workoutId {
            todaysWorkoutId = workoutId
            defaults.set(workoutId, forKey: dayWorkoutIdKey)
        }

        // Camera tier: only while the server agrees it's still running and the
        // anchor is inside our own duration (the server's grace is its own).
        guard cameraOpen, openedAt.timeIntervalSinceNow > -Self.duration else { return }
        if isCameraOpen, let local = windowOpenedAt, openedAt <= local { return }
        open(workoutId: workoutId, at: openedAt)
    }

    /// Re-publish so anything gated on either tier re-evaluates. Call on
    /// foreground: an app that was backgrounded across the camera close has a
    /// timer that never fired, and would otherwise come back offering a capture
    /// the server would then refuse. It also catches the midnight rollover,
    /// which closes the day tier too.
    func refresh() {
        if defaults.string(forKey: dayKey) != Self.dayStamp() {
            resetDay(to: Self.dayStamp())
        }
        scheduleExpiryTick()
        objectWillChange.send()
    }

    /// Re-arm the camera-close nudge. Reads `cameraSecondsRemaining`, so it is
    /// a no-op once the window has already lapsed.
    private func scheduleExpiryTick() {
        // Always on the main run loop: `scheduledTimer` installs into the
        // CURRENT thread's run loop, and a background thread generally has none
        // running — the timer would simply never fire. `.shared` can be touched
        // first from anywhere, so don't assume the caller's thread.
        let arm = { [weak self] in
            guard let self else { return }
            self.expiryTimer?.invalidate()
            self.expiryTimer = nil
            let remaining = self.cameraSecondsRemaining
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

    /// The DAY tier: a qualifying walk or run has landed today, so a photo
    /// from it can still be posted. Gate every compose affordance on this —
    /// only the live camera answers to the countdown.
    var canPostToday: Bool {
        defaults.string(forKey: dayKey) == Self.dayStamp() && todaysWorkoutId != nil
    }

    /// The CAMERA tier: the ten minutes are still running. Gate capture — and
    /// only capture — on this.
    var isCameraOpen: Bool { cameraSecondsRemaining > 0 }

    var cameraSecondsRemaining: TimeInterval {
        guard defaults.string(forKey: dayKey) == Self.dayStamp(),
              let opened = windowOpenedAt else { return 0 }
        return max(0, Self.duration - Date().timeIntervalSince(opened))
    }

    /// End instant for `Text(timerInterval:)`. Falls back to now when closed.
    var windowEndDate: Date {
        (windowOpenedAt ?? Date()).addingTimeInterval(Self.duration)
    }

    /// True when the camera window is open AND scoped to this specific workout
    /// — used to scope the post-run prompt's countdown to the run that just
    /// finished.
    func isCameraOpen(forWorkout id: String) -> Bool {
        isCameraOpen && windowWorkoutId == id
    }

    #if DEBUG
    /// Test hook: force both tiers closed.
    func reset() {
        expiryTimer?.invalidate()
        expiryTimer = nil
        windowOpenedAt = nil
        windowWorkoutId = nil
        todaysWorkoutId = nil
        defaults.removeObject(forKey: openedAtKey)
        defaults.removeObject(forKey: workoutIdKey)
        defaults.removeObject(forKey: dayWorkoutIdKey)
        defaults.removeObject(forKey: anchoredIdsKey)
        defaults.removeObject(forKey: dayKey)
    }
    #endif
}

/// A thin countdown ring drawn around content (the compose FAB, a story "+"
/// cell) for as long as the CAMERA window runs. Self-ticks via `TimelineView`
/// from `openedAt`, so it needs no parent timer and stops the moment it's
/// unmounted. Once the window elapses the trim reaches 0 and nothing is drawn,
/// so it also self-hides even before the parent re-renders — which is what
/// makes the affordance underneath quietly go from "camera" to "camera roll"
/// rather than locking.
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
