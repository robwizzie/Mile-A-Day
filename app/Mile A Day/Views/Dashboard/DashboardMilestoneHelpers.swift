import Foundation

extension StreakMilestone {
    static let displayLadder: [Int] = Array(Set([3, 5] + allCases.map(\.days))).sorted()

    static func next(after streak: Int) -> (value: Int, progress: Double, daysToGo: Int)? {
        guard let value = displayLadder.first(where: { streak < $0 }) else { return nil }
        return (
            value: value,
            progress: max(0, min(Double(streak) / Double(value), 1)),
            daysToGo: value - streak
        )
    }

    /// The rung the streak last crossed (0 before the first), so a bar can run
    /// milestone → milestone instead of 0 → milestone.
    static func previous(before streak: Int) -> Int {
        displayLadder.last(where: { $0 <= streak }) ?? 0
    }

    static func nextMajor(after streak: Int) -> StreakMilestone? {
        allCases
            .filter { $0.isMajor && $0.days > streak }
            .sorted { $0.days < $1.days }
            .first
    }
}
