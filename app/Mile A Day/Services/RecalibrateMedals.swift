import Foundation

/// What every Recalibrate surface does once the server has answered: the
/// server may have just awarded medals, so pull the shelf AND the stats beside
/// it (a screen refreshing badges must refresh stats, or "500 mi · 27 to go"
/// sits under a freshly awarded 500 Mile Club). A burst above three is told in
/// the confirmation line instead of one unlock popup per medal.
enum RecalibrateMedals {
    static let celebrateIndividuallyUpTo = 3

    @MainActor
    static func refresh(userManager: UserManager, newBadgeIds: [String]) async {
        await userManager.refreshBadgesFromServer(
            celebrateNew: newBadgeIds.count <= celebrateIndividuallyUpTo
        )
        await SelfStatsRefresher.refreshBackendStats(userManager: userManager)
    }

    /// A sentence for the result alert naming what the recalibrate found; nil for none.
    static func sentence(for newBadgeIds: [String]) -> String? {
        switch newBadgeIds.count {
        case 0: return nil
        case 1: return "We also found a medal you'd already earned — it's on your shelf now."
        default: return "We also found \(newBadgeIds.count) medals you'd already earned — they're on your shelf now."
        }
    }
}
