import SwiftUI

/// Lifecycle of the streak flame shared by both dashboard styles.
///
/// The flame is a day-long candle: full right after midnight, shrinking as the
/// day drains, and nothing at all at the stroke of midnight unless the mile
/// reignites it. With no living streak there is no flame — just a cold coal
/// waiting to be lit by the first mile.
enum StreakFlamePhase: Equatable {
    /// No living streak and no mile banked today — a cold coal.
    case coal
    /// Streak alive but today's mile not done — the flame burns down with the time left.
    case burning
    /// Today's mile is banked — full flame, nothing left to lose.
    case blazing

    /// Mirrors the trust rules of `FlameHealth.forState`: completion and
    /// streak-zero are only believed when today's distance is fresh, so a
    /// locked-device zero can never flash the coal at a streaking user.
    static func forState(isCompleted: Bool, distanceIsFresh: Bool, streak: Int) -> StreakFlamePhase {
        if isCompleted && distanceIsFresh { return .blazing }
        if streak == 0 && distanceIsFresh { return .coal }
        return .burning
    }
}

enum StreakFlameClock {
    static let dayLength: TimeInterval = 24 * 60 * 60

    static func nextLocalMidnight(after date: Date = Date()) -> Date {
        Calendar.current.nextDate(
            after: date,
            matching: DateComponents(hour: 0, minute: 0, second: 0),
            matchingPolicy: .nextTime
        ) ?? date.addingTimeInterval(dayLength)
    }

    /// Fraction of the day still available to run: 1 just after midnight, 0 at midnight.
    static func vigor(at date: Date, dayEnd: Date?) -> Double {
        let end = dayEnd ?? nextLocalMidnight(after: date)
        return min(max(end.timeIntervalSince(date) / dayLength, 0), 1)
    }

    /// Perceptual size of a burning flame — tracks the time left in the day as
    /// directly as possible. A near-linear descent (gentle 0.9 ease for a touch
    /// more body up top) so the flame shrinks a little every hour: full at the
    /// day's start, roughly half by midday, a thin wisp as the next midnight
    /// nears. It never hugs full size and then drops late — that read as a jump
    /// from normal to small. The flame keeps a small floor while burning so it
    /// never looks broken; the phase transition to coal renders the true "out"
    /// state at midnight.
    static func flameScale(vigor: Double) -> CGFloat {
        let v = min(max(vigor, 0), 1)
        let minScale = 0.08
        return CGFloat(minScale + (1 - minScale) * pow(v, 0.9))
    }
}

/// Continuous flame coloring: rich golden-orange with a full day ahead,
/// deepening toward starving ember-red as midnight nears. Always fully
/// saturated and opaque — a live flame is never washed out; it only shrinks.
enum FlamePalette {
    static func lerp(_ a: (Double, Double, Double), _ b: (Double, Double, Double), _ t: Double) -> Color {
        let clamped = min(max(t, 0), 1)
        return Color(
            red: a.0 + (b.0 - a.0) * clamped,
            green: a.1 + (b.1 - a.1) * clamped,
            blue: a.2 + (b.2 - a.2) * clamped
        )
    }

    static func outer(vigor: CGFloat) -> [Color] {
        let t = 1 - Double(min(max(vigor, 0), 1))
        return [
            lerp((1.00, 0.95, 0.32), (1.00, 0.66, 0.16), t),
            lerp((1.00, 0.58, 0.00), (0.97, 0.34, 0.10), t),
            lerp((1.00, 0.22, 0.10), (0.55, 0.08, 0.10), t)
        ]
    }

    static func inner(vigor: CGFloat) -> [Color] {
        let t = 1 - Double(min(max(vigor, 0), 1))
        return [
            lerp((1.00, 0.98, 0.44), (1.00, 0.78, 0.26), t),
            lerp((1.00, 0.65, 0.12), (0.92, 0.32, 0.10), t)
        ]
    }
}
