import Foundation
import ActivityKit

/// Owns the at-risk Live Activity's lifecycle. Idempotent `sync` is safe to
/// call from every state change the dashboard sees:
/// - starts the activity when the evening turns at-risk (setting on, goal
///   unmet, streak worth saving, no workout activity already live)
/// - updates miles-to-go if it's already running
/// - ends it the moment the mile lands, the risk passes, or the user turns
///   the setting off.
/// The countdown itself is system-rendered from `deadline`, so the activity
/// needs no ticking updates; `staleDate` at midnight lets iOS clean up a
/// leftover on its own if the app never gets the chance.
enum StreakRiskActivityManager {
    private static let enabledKey = "streakRiskLiveActivityEnabled"

    /// User toggle (Notifications settings) — default ON; the activity only
    /// ever appears when the streak is genuinely about to die.
    static var isEnabled: Bool {
        get {
            UserDefaults.standard.object(forKey: enabledKey) == nil
                ? true
                : UserDefaults.standard.bool(forKey: enabledKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    static func sync(
        isAtRisk: Bool,
        isCompleted: Bool,
        streak: Int,
        goalMiles: Double,
        currentMiles: Double
    ) {
        guard #available(iOS 16.2, *) else { return }

        let calendar = Calendar.current
        let midnight = calendar.date(
            byAdding: .day, value: 1, to: calendar.startOfDay(for: Date())
        ) ?? Date().addingTimeInterval(3600)

        let shouldRun = isEnabled
            && isAtRisk
            && !isCompleted
            && streak > 0
            && midnight.timeIntervalSinceNow > 60
            // A live workout already owns the lock screen — don't double up.
            && Activity<WorkoutActivityAttributes>.activities.isEmpty
            && ActivityAuthorizationInfo().areActivitiesEnabled

        let existing = Activity<StreakRiskActivityAttributes>.activities

        guard shouldRun else {
            for activity in existing {
                Task { await activity.end(nil, dismissalPolicy: .immediate) }
            }
            return
        }

        let state = StreakRiskActivityAttributes.ContentState(
            milesToGo: max(goalMiles - currentMiles, 0),
            deadline: midnight
        )
        let content = ActivityContent(state: state, staleDate: midnight)

        if let activity = existing.first {
            Task { await activity.update(content) }
            return
        }

        do {
            _ = try Activity.request(
                attributes: StreakRiskActivityAttributes(
                    streak: streak,
                    goalMiles: goalMiles,
                    funStyle: DashboardStylePreference.current == .fun
                ),
                content: content
            )
            print("[StreakRiskActivity] started — day \(streak), \(String(format: "%.2f", state.milesToGo)) mi to go")
        } catch {
            print("[StreakRiskActivity] request failed: \(error.localizedDescription)")
        }
    }
}
