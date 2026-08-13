import Foundation

/// Which workouts already carry a deliberate post of this user's.
///
/// The SERVER has always known this — `createPost` allows exactly one live user
/// post per workout across the feed and story slots and throws
/// `workout_already_posted` for a second (postService.ts). The client had no
/// memory of it at all, and two surfaces need the answer *before* they ask:
///
///  - the post-run photo prompt, which is a fire-and-forget celebration: by the
///    time a 409 could teach it anything, it has already interrupted someone to
///    ask for a photo of a walk they just posted;
///  - the buddy recap's "Post this walk" CTA, which would otherwise stay lit
///    after the walk was posted and lead a second attempt into that 409.
///
/// Note what it does NOT gate: `RunPostService.autoPostMile`. A story-only
/// share consumes the run's user-post slot while leaving the FEED without a
/// card, which is precisely when the auto route card should still go up — and
/// the server already refuses to let one overwrite a deliberate post.
///
/// Keyed by HealthKit workout uuid, which is the same id the server stores as
/// `workouts.workout_id` and the same one the fresh window and the photo prompt
/// key on (ios.md: those three must agree or the dedup silently misses).
///
/// Persisted, because the thing it prevents happens ACROSS a relaunch: the
/// prompt's queue is in-memory and starts empty every cold launch. Bounded to
/// the most recent ids, newline-joined — same shape and reasoning as
/// `CelebrationManager.promptedPhotoWorkoutIdsV1`, which it sits beside.
///
/// Deliberately advisory, never authoritative: it can only be wrong in the safe
/// direction (a missing entry means someone gets asked, and the server still
/// refuses the duplicate). The one way to go stale is a post deleted on another
/// device, which `clear(_:)` fixes on this one whenever the feed sees it.
enum PostedWorkoutRegistry {
    private static let storageKey = "postedWorkoutIdsV1"
    private static let maxIds = 200

    static func hasPost(for workoutId: String) -> Bool {
        ids().contains(workoutId)
    }

    /// Record that `workoutId` now carries a real post. Idempotent.
    static func markPosted(_ workoutId: String) {
        guard !workoutId.isEmpty else { return }
        var current = ids()
        guard !current.contains(workoutId) else { return }
        current.append(workoutId)
        if current.count > maxIds { current = Array(current.suffix(maxIds)) }
        write(current)
    }

    /// The post was deleted, so the run's slot is free again and every surface
    /// above should offer it once more.
    static func clear(_ workoutId: String) {
        let current = ids()
        guard current.contains(workoutId) else { return }
        write(current.filter { $0 != workoutId })
    }

    private static func ids() -> [String] {
        (UserDefaults.standard.string(forKey: storageKey) ?? "")
            .split(separator: "\n")
            .map(String.init)
    }

    private static func write(_ ids: [String]) {
        UserDefaults.standard.set(ids.joined(separator: "\n"), forKey: storageKey)
    }
}
