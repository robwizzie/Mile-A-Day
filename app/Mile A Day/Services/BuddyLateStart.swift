import CoreMotion
import Foundation

/// Credit a buddy walker for the ground they covered before their phone
/// started recording.
///
/// A guest's tracker starts only when their lobby is ON SCREEN at the moment
/// the shared countdown ends (`BuddyLobbyView.handOffIfStarted` runs on the
/// lobby's tick, which iOS stops when the phone locks). So the most ordinary
/// way to go on a walk with someone — tap Ready, lock the phone, pocket it,
/// walk — recorded nothing until the walker happened to open the app, and
/// then started from 0.00 a third of a mile in. The crew watched their tile
/// sit at zero the whole time.
///
/// The phone's motion coprocessor counted every one of those steps anyway.
/// `CMPedometer.queryPedometerData` reads them back (it keeps a week), so when
/// the hand-off lands late the tracker starts at the walk's own start time
/// with that distance already on it, and its clock and HealthKit workout span
/// the whole walk.
///
/// Only with Motion & Fitness already granted: this never raises the
/// permission prompt on its own (a sheet appearing as a workout starts would
/// read as the walk asking for something), and without it the walk simply
/// starts now, as it always did.
enum BuddyLateStart {
    /// The countdown hand-off is on a 0.1s tick, and a poll can be up to 5s
    /// behind: under this, a start is on time and nothing is back-filled.
    static let threshold: TimeInterval = 20
    /// Longer ago than this isn't one continuous walk we'd stand behind.
    static let maxLateness: TimeInterval = 2 * 60 * 60
    /// About 50 metres: less than that is shuffling at the meeting point.
    static let minimumMiles: Double = 0.03

    struct Seed: Equatable {
        /// The walk's shared start: the workout's clock starts here.
        let startDate: Date
        /// Distance the pedometer counted between `startDate` and now.
        let miles: Double
    }

    private static let pedometer = CMPedometer()

    /// Resolve the catch-up for a walk that started at `sessionStartedAt`.
    ///
    /// Calls `completion` on the main queue — SYNCHRONOUSLY when there is
    /// nothing to back-fill (on time, no permission, no pedometer), so the
    /// ordinary on-time start isn't delayed by a hop.
    static func resolve(
        sessionStartedAt: Date?,
        now: Date = Date(),
        completion: @escaping (Seed?) -> Void
    ) {
        guard let startedAt = sessionStartedAt else { return completion(nil) }
        let lateness = now.timeIntervalSince(startedAt)
        guard lateness >= threshold, lateness <= maxLateness,
              CMPedometer.isDistanceAvailable(),
              CMPedometer.authorizationStatus() == .authorized
        else { return completion(nil) }

        pedometer.queryPedometerData(from: startedAt, to: now) { data, error in
            let meters = data?.distance?.doubleValue ?? 0
            let miles = meters * 0.000621371
            DispatchQueue.main.async {
                // Nothing walked behind it means they really did set off
                // late (arrived after the start, stood waiting): start now,
                // as before. Backdating the clock with no distance would
                // only drag their pace.
                guard error == nil, miles.isFinite, miles >= minimumMiles else {
                    return completion(nil)
                }
                completion(Seed(startDate: startedAt, miles: miles))
            }
        }
    }
}
