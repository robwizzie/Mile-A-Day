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

/// Keeps the Watch's copy of today's plan current. Called from
/// `RunPlanStore` whenever `current` changes. Plus is the server's gate: a
/// lapsed account's 403 clears `current`, which clears the Watch too.
@MainActor
enum RunPlanWatchSync {
    static func update(today: RunPlanDay?) {
        let json: String?
        if let today, today.offersPlanRun {
            json = today.watchPayload.json()
        } else {
            json = nil
        }
        let bridge = MADWatchBridge.shared
        guard bridge.runPlanJSON != json else { return }
        bridge.runPlanJSON = json
        bridge.pushSnapshotIfReady()
    }
}
