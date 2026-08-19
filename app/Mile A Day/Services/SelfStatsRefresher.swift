import Foundation

/// The "refresh MY numbers" path — the signed-in user's own backend stats.
///
/// This logic lived only inside `DashboardView`, so any other tab rendering the
/// same numbers had no way to move them. The Friends hero card shows today's
/// miles and the streak, but its pull-to-refresh re-fetched the friend graph
/// only — so those two values sat frozen at whatever the Dashboard last wrote,
/// and a trip to the Dashboard and back "fixed" the page. That is what made the
/// tab's two refresh paths look inconsistent.
///
/// Extracted rather than copied, because none of these applies is a plain
/// assignment: `updateStreakFromBackend` only ever RAISES (the displayed streak
/// deliberately lags a real break until it's verified) and `applyStatsPayload`
/// must only ever see the CURRENT user's response, never a friend's.
@MainActor
enum SelfStatsRefresher {
    /// Fetch `/workouts/:id/stats` for the signed-in user and apply every
    /// authoritative value on it: streak (raise-only), the gated streak-features
    /// payload, fastest mile pace, longest streak.
    ///
    /// Returns the decoded response so a caller can layer its own follow-up on
    /// top — the Dashboard repairs a stale WorkoutIndex from the streak it gets
    /// back. Silent on failure: every value here has a cached fallback, so a
    /// dropped request is a no-op rather than a UI error.
    @discardableResult
    static func refreshBackendStats(userManager: UserManager) async -> UserStatsAPIResponse? {
        guard let userId = UserDefaults.standard.string(forKey: "backendUserId") else { return nil }
        do {
            let stats = try await WorkoutService().getUserStats(userId: userId)
            // Rescues the streak on first login / before HealthKit indexes
            // locally. Raise-only, so it can't clobber a higher
            // HealthKit-computed streak from a later refresh.
            userManager.updateStreakFromBackend(stats.streak)
            // Syncs the streak-token state (meters + covered days) from the
            // gated payload — this is OUR stats call, never a friend's.
            StreakFeatureService.applyStatsPayload(stats.streakFeatures)
            if let bestSplitSeconds = stats.bestSplitTimeSeconds, bestSplitSeconds > 0 {
                userManager.updateFastestPaceFromBackend(bestSplitSeconds / 60.0)
            }
            if let longest = stats.longestStreak {
                userManager.updateLongestStreakFromBackend(longest)
            }
            return stats
        } catch {
            print("[SelfStats] ⚠️ Failed to fetch stats from backend: \(error)")
            return nil
        }
    }
}
