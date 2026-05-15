import Foundation

/// Snapshot of the user's state at the moment they crossed a year boundary.
/// Lives in its own file so it can be a member of both the iOS and Watch
/// targets — the celebration view that consumes it is iOS-only.
struct YearlyMilestoneInfo: Equatable {
    let years: Int
    let totalMiles: Double
    let totalStreakDays: Int
    /// Approximate date the current streak began (today minus streak days).
    let streakStartDate: Date?
}
