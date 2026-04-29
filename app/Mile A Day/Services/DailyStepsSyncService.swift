import Foundation
import HealthKit
import UserNotifications

/// Syncs today's HealthKit step count to the backend `daily_steps` table on a
/// throttled cadence, and fires a local notification when the user crosses 10k.
///
/// Triggers (see plan + spec for full reasoning):
///   - HKObserverQuery wake-ups (background delivery)
///   - Foreground app activation (always posts today)
///   - First foreground after a day rollover (also posts yesterday once)
///   - Post-workout-sync hook (called by WorkoutSyncService)
///
/// Throttle (background only): post if Δsteps ≥ 500, OR ≥ 15 min since last post,
/// OR threshold crossed, OR new local date.
final class DailyStepsSyncService {

    static let shared = DailyStepsSyncService()

    private let healthStore = HKHealthStore()
    private let stepGoal = 10_000

    // Persisted state
    private let lastPostedStepsKey = "dailySteps.lastPostedSteps"
    private let lastPostTimestampKey = "dailySteps.lastPostTimestamp"
    private let lastPostedDateKey = "dailySteps.lastPostedDate"
    private let goalNotifiedDateKey = "dailySteps.goalNotifiedDate"

    private var observerQuery: HKObserverQuery?

    // MARK: - Lifecycle

    /// Call once at app launch (after HealthKit authorization is requested).
    func start() {
        guard let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount) else { return }

        let query = HKObserverQuery(sampleType: stepType, predicate: nil) { [weak self] _, completionHandler, error in
            if let error = error {
                print("[DailyStepsSyncService] Observer error: \(error.localizedDescription)")
                completionHandler()
                return
            }
            Task { [weak self] in
                await self?.syncNow(force: false)
                completionHandler()
            }
        }
        healthStore.execute(query)
        observerQuery = query

        healthStore.enableBackgroundDelivery(for: stepType, frequency: .immediate) { success, error in
            if let error = error {
                print("[DailyStepsSyncService] enableBackgroundDelivery failed: \(error.localizedDescription)")
            } else if !success {
                print("[DailyStepsSyncService] enableBackgroundDelivery returned false")
            }
        }
    }

    /// Call from `scenePhase == .active` and from `WorkoutSyncService` post-success.
    /// `force = true` skips the throttle (always posts).
    func syncNow(force: Bool) async {
        guard AppStateManager.shared.isAuthenticated,
              let userId = UserManager.shared.currentUser.backendUserId else { return }

        let now = Date()
        let todayLocalDate = Self.localDateString(for: now)
        let todaySteps = await fetchSteps(for: now)

        // Day-rollover catch-up: post yesterday's final count once on the first sync of a new day.
        if let lastDate = UserDefaults.standard.string(forKey: lastPostedDateKey),
           lastDate != todayLocalDate {
            let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now) ?? now
            let yesterdayLocalDate = Self.localDateString(for: yesterday)
            if yesterdayLocalDate == lastDate {
                let yesterdaySteps = await fetchSteps(for: yesterday)
                if yesterdaySteps > 0 {
                    _ = await post(userId: userId,
                                   localDate: yesterdayLocalDate,
                                   steps: yesterdaySteps)
                }
            }
        }

        // Goal crossing: highest priority — always post + maybe notify.
        let lastPosted = UserDefaults.standard.integer(forKey: lastPostedStepsKey)
        let lastPostedDate = UserDefaults.standard.string(forKey: lastPostedDateKey)
        let crossed = todaySteps >= stepGoal &&
                      (lastPostedDate != todayLocalDate || lastPosted < stepGoal)

        if crossed {
            await postAndCommit(userId: userId,
                                localDate: todayLocalDate,
                                steps: todaySteps,
                                now: now)
            maybeFireGoalNotification(localDate: todayLocalDate)
            return
        }

        if force || shouldPost(currentSteps: todaySteps,
                               todayLocalDate: todayLocalDate,
                               now: now) {
            await postAndCommit(userId: userId,
                                localDate: todayLocalDate,
                                steps: todaySteps,
                                now: now)
        }
    }

    // MARK: - Throttle

    private func shouldPost(currentSteps: Int, todayLocalDate: String, now: Date) -> Bool {
        let lastPosted = UserDefaults.standard.integer(forKey: lastPostedStepsKey)
        let lastTimestamp = UserDefaults.standard.object(forKey: lastPostTimestampKey) as? Date
        let lastDate = UserDefaults.standard.string(forKey: lastPostedDateKey)

        if lastDate != todayLocalDate { return true }
        if currentSteps - lastPosted >= 500 { return true }
        if let ts = lastTimestamp,
           now.timeIntervalSince(ts) >= 15 * 60,
           currentSteps != lastPosted { return true }
        return false
    }

    // MARK: - Network

    private struct UpsertResponse: Decodable {
        let steps: Int
        let updatedAt: String
    }

    private struct UpsertBody: Encodable {
        let localDate: String
        let steps: Int
        let timezoneOffset: Int
    }

    private func post(userId: String, localDate: String, steps: Int) async -> Bool {
        let timezoneOffset = TimeZone.current.secondsFromGMT() / 60
        let body = UpsertBody(localDate: localDate, steps: steps, timezoneOffset: timezoneOffset)
        do {
            let bodyData = try JSONEncoder().encode(body)
            let _: UpsertResponse = try await APIClient.fancyFetch(
                endpoint: "/users/\(userId)/daily-steps",
                method: .PUT,
                body: bodyData,
                responseType: UpsertResponse.self
            )
            return true
        } catch {
            print("[DailyStepsSyncService] POST failed for \(localDate): \(error)")
            return false
        }
    }

    private func postAndCommit(userId: String, localDate: String, steps: Int, now: Date) async {
        let ok = await post(userId: userId, localDate: localDate, steps: steps)
        guard ok else { return }
        UserDefaults.standard.set(steps, forKey: lastPostedStepsKey)
        UserDefaults.standard.set(now, forKey: lastPostTimestampKey)
        UserDefaults.standard.set(localDate, forKey: lastPostedDateKey)
    }

    // MARK: - HealthKit query

    private func fetchSteps(for date: Date) async -> Int {
        guard let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount) else { return 0 }
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else { return 0 }
        let upperBound = min(endOfDay, Date())
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: upperBound, options: .strictStartDate)

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: stepType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, result, _ in
                if let sum = result?.sumQuantity() {
                    continuation.resume(returning: Int(sum.doubleValue(for: HKUnit.count())))
                } else {
                    continuation.resume(returning: 0)
                }
            }
            self.healthStore.execute(query)
        }
    }

    // MARK: - Goal notification

    private func maybeFireGoalNotification(localDate: String) {
        let alreadyNotified = UserDefaults.standard.string(forKey: goalNotifiedDateKey)
        guard alreadyNotified != localDate else { return }

        let prefs = NotificationPreferences.load()
        guard prefs.stepGoalEnabled else {
            UserDefaults.standard.set(localDate, forKey: goalNotifiedDateKey)
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "🎉 You hit 10,000 steps!"
        content.body = "Daily step goal complete — keep moving!"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "step-goal-\(localDate)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("[DailyStepsSyncService] Notification add failed: \(error.localizedDescription)")
            }
        }
        UserDefaults.standard.set(localDate, forKey: goalNotifiedDateKey)
    }

    // MARK: - Helpers

    private static func localDateString(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current
        return formatter.string(from: date)
    }
}
