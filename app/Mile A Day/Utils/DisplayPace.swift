import Foundation

/// The ONE rule for turning a workout's distance and time into the pace a
/// user reads.
///
/// Two decisions live here because they were made independently in five
/// places and disagreed with each other on the same card:
///
///  1. **Which clock divides.** The tracker records `movingSeconds` so a wait
///     at a light doesn't drag the number down, and every surface preferred
///     it whenever it was present. But the moving clock can only report what
///     it WITNESSED, and a witness gap (thin GPS, a batched locked-phone
///     delivery, an old build's per-segment cap) leaves a real workout
///     carrying a moving time that covers a fraction of it. Dividing by that
///     prints a pace nobody ran: a 34:18 walk of 1.03 mi came back with 8.7
///     minutes of moving time and a card reading "8:25 /mi" directly above
///     its own splits, which said 33:05. So moving time only divides while
///     it covers most of the session; short of that it isn't a measurement
///     of the walk and elapsed time — always the honest floor — takes over.
///     Erring toward elapsed can only ever report a pace SLOWER than the
///     truth, which is the safe direction for a number people compare.
///
///  2. **What counts as a pace at all.** The band used to end at 30 min/mile,
///     which is fine for runs and wrong for the app's actual median activity:
///     it rejected that walk's honest 33:05 while happily printing the 8:25.
enum DisplayPace {
    /// Share of elapsed time the moving clock must account for before it is
    /// allowed to divide. Below this the clock lost the session rather than
    /// the walker standing still for most of it — and even a genuinely
    /// stop-heavy walk keeps moving for more of itself than this.
    static let minimumMovingCoverage: Double = 0.5

    /// Fastest pace that can be a real on-foot figure (2:00 /mi).
    static let fastestPlausibleSecondsPerMile: Double = 120
    /// Slowest — 60:00 /mi is 1 mph. Slower than this is a workout that
    /// mostly wasn't moving, and a pace for it means nothing.
    static let slowestPlausibleSecondsPerMile: Double = 3600

    /// The seconds a displayed pace divides by: moving time when it covers
    /// enough of the workout, elapsed otherwise. Nil when neither is usable.
    static func divisor(movingSeconds: Double?, elapsedSeconds: Double?) -> Double? {
        guard let elapsed = elapsedSeconds, elapsed > 0 else {
            // No elapsed time to check against — a moving figure is all
            // there is, and it's still better than nothing.
            guard let moving = movingSeconds, moving > 0 else { return nil }
            return moving
        }
        guard let moving = movingSeconds, moving > 0,
              moving <= elapsed,
              moving >= elapsed * minimumMovingCoverage
        else { return elapsed }
        return moving
    }

    /// Seconds per mile for display, or nil when the workout can't honestly
    /// state one.
    static func secondsPerMile(
        distanceMiles: Double,
        movingSeconds: Double?,
        elapsedSeconds: Double?
    ) -> Double? {
        guard distanceMiles > 0,
              let divisor = divisor(movingSeconds: movingSeconds, elapsedSeconds: elapsedSeconds)
        else { return nil }
        let pace = divisor / distanceMiles
        guard pace >= fastestPlausibleSecondsPerMile,
              pace <= slowestPlausibleSecondsPerMile else { return nil }
        return pace
    }
}
