import Foundation

// Run Plans → live coaching shapes. The wire DTOs (`RunPlanDay`,
// `RunPlanSegment`) are iPhone-only; the live shapes (`RunPlanLiveSegment`,
// `WatchRunPlan`) live in HealthKitManager.swift so the Watch compiles them
// too. This file is the one bridge between the two.

extension RunPlanSegment {
    var live: RunPlanLiveSegment {
        RunPlanLiveSegment(kind: kind, distanceMiles: distance_mi, durationSeconds: duration_s,
                           targetPace: target_pace_s, rep: rep, reps: reps)
    }
}

extension RunPlanDay {
    /// Segments the live coach can walk (each needs a distance or a time;
    /// an open-ended one is kept only as the last).
    var liveSegments: [RunPlanLiveSegment] {
        let all = (segments ?? []).map(\.live)
        return all.enumerated().filter { pair in
            pair.element.isDistanceBased || pair.element.isDurationBased || pair.offset == all.count - 1
        }.map(\.element)
    }

    /// Worth a "Today's plan" run: a real session (not the streak mile) with
    /// something to coach.
    var offersPlanRun: Bool {
        dayKind != .streak && !liveSegments.isEmpty && !isDone
    }

    var watchPayload: WatchRunPlan {
        WatchRunPlan(date: local_date, title: RunPlanFormat.title(self), segments: liveSegments)
    }
}

/// Keeps the Watch's copy of the plan current. Called from `RunPlanStore`
/// whenever `current` changes (and on sign-out via `clear()`). Sends the
/// runnable days from TODAY on (up to a week), keyed by `local_date`, so the
/// Watch still has today's session after midnight with the phone app closed;
/// the Watch picks the day dated today. The JSON is persisted by
/// `MADWatchBridge.runPlanJSON`, so every later push carries it. Plus is the
/// server's gate: a lapsed account's 403 clears `current`, which clears this.
@MainActor
enum RunPlanWatchSync {
    /// Days pushed ahead of today (a week: covers the Sunday→Monday rollover).
    private static let daysAhead = 7

    static func update(current: RunPlanCurrent?) {
        let todayKey = RunPlanDate.todayKey()
        let lastKey = RunPlanDate.addingDays(daysAhead - 1, to: todayKey) ?? todayKey
        var byDate: [String: RunPlanDay] = [:]
        for day in current?.days ?? [] { byDate[day.local_date] = day }
        // The server's `today` only counts when it IS today (it can be
        // yesterday's from a cache read after midnight).
        if let served = current?.todayDay, served.local_date == todayKey { byDate[todayKey] = served }
        let days = byDate.values
            .filter { $0.local_date >= todayKey && $0.local_date <= lastKey && $0.offersPlanRun }
            .sorted { $0.local_date < $1.local_date }
            .map(\.watchPayload)
        set(WatchRunPlan.json(days))
    }

    /// Sign-out: the plan belongs to the account we're leaving.
    static func clear() {
        set(nil)
    }

    private static func set(_ json: String?) {
        let bridge = MADWatchBridge.shared
        guard bridge.runPlanJSON != json else { return }
        bridge.runPlanJSON = json
        bridge.pushSnapshotIfReady()
    }
}
