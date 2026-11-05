import Foundation

/// When an edit to a recorded workout is flagged, and how.
///
/// ONE rule for every edit screen (the workout edit sheet and the recap's
/// treadmill card used to carry their own 25% copies). It is deliberately
/// LENIENT: phones and treadmills are routinely wrong — a 7:30 mile the phone
/// clocked at 8:30, a treadmill walk the pedometer under-read by half — and a
/// user fixing that is not entering a fake workout. So a correction is saved
/// unflagged (`.healthkit`), and only an edit that is TOTALLY off what the
/// device saw is flagged `.manual`. Nothing here emits `.edited` any more:
/// a time or type fix used to wear an "Edited" badge forever, which read as an
/// accusation for doing exactly what the edit screen is for.
///
/// Every check is against what the DEVICE recorded (`recordedDistance` /
/// `recordedDuration`), never the last edit, so allowances can't be stacked
/// one save at a time. Competitions never see the typed number either way —
/// the server credits `LEAST(distance, original_distance)`.
enum WorkoutEditPolicy {
    /// Outdoor: GPS + pedometer can be off, but not by half.
    static let outdoorDistanceFactor = 1.5
    static let outdoorDistanceAllowance = 0.5 // miles
    /// Indoor: the phone has no GPS and a treadmill console is the better
    /// witness, so far more room.
    static let indoorDistanceFactor = 2.0
    static let indoorDistanceAllowance = 1.0 // miles
    /// Indoor: the recorded time supports at least this pace's worth of
    /// distance (5:00 /mi), whatever the phone counted.
    static let indoorSupportedSecondsPerMile: Double = 300
    /// A time cut by more than this share of what was recorded is not a
    /// clock correction (8:30 → 7:30 is 12%).
    static let maxDurationCut = 0.4
    /// Faster than this (3:00 /mi) is not an on-foot pace at all.
    static let fastestPlausibleSecondsPerMile: Double = 180

    enum Reason {
        case distance
        case duration
        case pace
    }

    /// Why this edit is totally off, or nil when it is a plausible correction.
    static func flagReason(
        recordedDistance: Double,
        recordedDuration: TimeInterval,
        newDistance: Double,
        newDuration: TimeInterval,
        isIndoor: Bool
    ) -> Reason? {
        if newDistance > maxUnflaggedDistance(
            recordedDistance: recordedDistance,
            recordedDuration: recordedDuration,
            isIndoor: isIndoor
        ) {
            return .distance
        }
        if recordedDuration > 0, newDuration < recordedDuration * (1 - maxDurationCut) {
            return .duration
        }
        if newDistance >= 0.1, newDuration > 0,
           newDuration / newDistance < fastestPlausibleSecondsPerMile {
            return .pace
        }
        return nil
    }

    static func source(
        recordedDistance: Double,
        recordedDuration: TimeInterval,
        newDistance: Double,
        newDuration: TimeInterval,
        isIndoor: Bool
    ) -> WorkoutSource {
        flagReason(
            recordedDistance: recordedDistance,
            recordedDuration: recordedDuration,
            newDistance: newDistance,
            newDuration: newDuration,
            isIndoor: isIndoor
        ) == nil ? .healthkit : .manual
    }

    /// The most distance an edit can claim before it's flagged.
    static func maxUnflaggedDistance(
        recordedDistance: Double,
        recordedDuration: TimeInterval,
        isIndoor: Bool
    ) -> Double {
        let recorded = max(0, recordedDistance)
        if isIndoor {
            let supportedByTime = recordedDuration > 0
                ? recordedDuration / indoorSupportedSecondsPerMile
                : 0
            return max(
                recorded * indoorDistanceFactor,
                recorded + indoorDistanceAllowance,
                supportedByTime
            )
        }
        return max(
            recorded * outdoorDistanceFactor,
            recorded + outdoorDistanceAllowance
        )
    }

    /// One sentence for the confirmation alert.
    static func explanation(for reason: Reason) -> String {
        switch reason {
        case .distance:
            return "This is far more distance than the device recorded, so it will show as a manual entry."
        case .duration:
            return "This is much faster than the time the device recorded, so it will show as a manual entry."
        case .pace:
            return "That pace is faster than anyone can run, so it will show as a manual entry."
        }
    }
}
