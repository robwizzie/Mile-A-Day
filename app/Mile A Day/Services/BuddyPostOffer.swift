import Foundation

/// A buddy walk the poster left WITHOUT posting it — closed the recap, or
/// backed out of its post step — remembered for ten minutes so that, if they
/// go to post anyway (the feed's +, the stories rail, a snap), the composer
/// asks "Post this with Alex & Sam?" instead of quietly making a solo post.
/// Backing out is easy to do by accident; this is the way back in.
///
/// Recorded by `BuddyRecapView` as it closes, read once by
/// `PostComposerView` on open, and cleared by any successful publish or by
/// the answer itself, so it's asked at most once. Persisted (UserDefaults) so
/// a relaunch inside the window still asks; scoped to the user who recorded
/// it.
struct BuddyPostOffer: Codable, Equatable {
    let userId: String
    let sessionId: String
    /// This user's workout for the walk, when the device had resolved it by
    /// then. nil = not yet (HealthKit trails the walk), and the offer then
    /// applies to whatever today's post is.
    let workoutId: String?
    /// Everyone else on the walk, in the order the post wizard credits them.
    let crewIds: [String]
    let crewNames: [String]
    let recordedAt: Date

    /// How long after backing out the composer still asks.
    static let window: TimeInterval = 10 * 60
    private static let key = "buddy.post.offer.v1"

    /// "Alex", "Alex & Sam", "Alex, Sam & 2 more".
    var crewText: String {
        switch crewNames.count {
        case 0: return "your crew"
        case 1: return crewNames[0]
        case 2: return "\(crewNames[0]) & \(crewNames[1])"
        default: return "\(crewNames[0]), \(crewNames[1]) & \(crewNames.count - 2) more"
        }
    }

    /// Does this offer belong to a post of `workoutId`? A post linked to a
    /// DIFFERENT workout (another walk since) is not this walk's.
    func applies(toWorkout workoutId: String?) -> Bool {
        guard let mine = self.workoutId, let workoutId else { return true }
        return mine == workoutId
    }

    /// The live offer for this user, if any. An expired or foreign one is
    /// dropped on read.
    static func current(for userId: String?) -> BuddyPostOffer? {
        guard let userId,
              let data = UserDefaults.standard.data(forKey: key),
              let offer = try? JSONDecoder().decode(BuddyPostOffer.self, from: data)
        else { return nil }
        guard offer.userId == userId,
              Date().timeIntervalSince(offer.recordedAt) < window,
              !offer.crewIds.isEmpty
        else {
            clear()
            return nil
        }
        return offer
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
