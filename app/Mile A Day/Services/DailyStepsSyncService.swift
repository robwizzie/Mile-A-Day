import Foundation
import HealthKit
import UserNotifications

/// Syncs today's HealthKit step count to the backend `daily_steps` table on a
/// throttled cadence, and fires a local notification when the user crosses 10k.
///
/// 10,000 steps completes the day for the streak ("1 mile OR 10,000 steps",
/// `ProgressCalculator.dailyStepGoal`). So this service also keeps
/// `StepGoalDayStore` — the goal-met days every local streak walk unions in —
/// and sends the step HISTORY up once per account (`syncStepGoalHistory`), so
/// the server can count days from before steps counted.
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
    private var stepGoal: Int { ProgressCalculator.dailyStepGoal }

    // Persisted state
    private let lastPostedStepsKey = "dailySteps.lastPostedSteps"
    private let lastPostTimestampKey = "dailySteps.lastPostTimestamp"
    private let lastPostedDateKey = "dailySteps.lastPostedDate"
    private let goalNotifiedDateKey = "dailySteps.goalNotifiedDate"
    /// Per account: the full step history has reached the server.
    private func historyUploadedKey(_ userId: String) -> String { "dailySteps.historyUploadedV1.\(userId)" }
    /// Last local day the recent window was re-read and sent.
    private let recentHistoryDayKey = "dailySteps.recentHistoryDayV1"

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
                // Step deliveries are the app's most frequent background wake.
                // If an earlier wake found HealthKit locked (a Watch walk
                // synced to a pocketed phone), this one finishes the widget's
                // today-refresh instead of leaving it stale until launch.
                await MADBackgroundService.shared.runPendingTodayRefreshIfPossible()
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
        let todayIsNewGoalDay = StepGoalDayStore.record(steps: todaySteps, on: now)

        // Day-rollover catch-up: post yesterday's final count once on the first sync of a new day.
        if let lastDate = UserDefaults.standard.string(forKey: lastPostedDateKey),
           lastDate != todayLocalDate {
            let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now) ?? now
            let yesterdayLocalDate = Self.localDateString(for: yesterday)
            if yesterdayLocalDate == lastDate {
                let yesterdaySteps = await fetchSteps(for: yesterday)
                if yesterdaySteps > 0 {
                    // A 10k crossed late last night (a locked phone can't be
                    // read) only reaches us now — and still counts. The post
                    // is what refreshes the server's streak, so stats after it.
                    let yesterdayIsNewGoalDay = StepGoalDayStore.record(steps: yesterdaySteps, on: yesterday)
                    _ = await post(userId: userId,
                                   localDate: yesterdayLocalDate,
                                   steps: yesterdaySteps)
                    if yesterdayIsNewGoalDay {
                        await Self.stepGoalDaysChanged()
                        await SelfStatsRefresher.refreshBackendStats(userManager: .shared)
                    }
                }
            }
        }

        // Goal crossing: highest priority — always post + maybe notify.
        let lastPosted = UserDefaults.standard.integer(forKey: lastPostedStepsKey)
        let lastPostedDate = UserDefaults.standard.string(forKey: lastPostedDateKey)
        let crossed = todaySteps >= stepGoal &&
                      (lastPostedDate != todayLocalDate || lastPosted < stepGoal)

        if crossed || todayIsNewGoalDay {
            // The server refreshes the stored streak on this crossing, so post
            // first, then pull the stats that now carry it.
            await postAndCommit(userId: userId,
                                localDate: todayLocalDate,
                                steps: todaySteps,
                                now: now)
            await Self.stepGoalDaysChanged(todaySteps: todaySteps)
            await SelfStatsRefresher.refreshBackendStats(userManager: .shared)
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

    /// Re-post the last `days` days of step counts so the backend can back-correct
    /// any day that was left partial. The live sync only ever finalizes today (and
    /// yesterday, once, at a day rollover); a day whose final steps reached
    /// HealthKit after its last post — a late Watch sync, or the app simply not
    /// being open that evening — stays stuck at the partial value forever. Apple
    /// Health holds the true daily totals and the backend upsert keeps the
    /// GREATEST, so re-querying and re-posting can only raise a stale day to its
    /// real count, never lower a correct one.
    ///
    /// Invoked by the "Recalibrate Streak" maintenance action, which runs in the
    /// foreground with the device unlocked so the step queries succeed. A 0 result
    /// (no data, or a locked-device query error that `fetchSteps` can't tell apart)
    /// is skipped, not posted: GREATEST means a 0 could never correct anything,
    /// only create empty rows.
    func backfillRecentDays(_ days: Int) async {
        guard AppStateManager.shared.isAuthenticated,
              let userId = UserManager.shared.currentUser.backendUserId else { return }

        let calendar = Calendar.current
        let today = Date()
        await withTaskGroup(of: Void.self) { group in
            for offset in 0..<max(days, 1) {
                guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
                group.addTask { [weak self] in
                    guard let self else { return }
                    let steps = await self.fetchSteps(for: day)
                    guard steps > 0 else { return }
                    _ = await self.post(userId: userId,
                                        localDate: Self.localDateString(for: day),
                                        steps: steps)
                }
            }
        }
    }

    // MARK: - Step history

    /// Read the step history from Apple Health, record its 10k days locally,
    /// and send them to the server in one batch.
    ///
    /// The FIRST run per account reads everything Health still has
    /// (`earliestPermittedSampleDate`) — "1 mile OR 10,000 steps" counts as
    /// far back as the data goes, and the server's own step table only starts
    /// in 2026. After that, a 14-day window once a day catches late Watch
    /// syncs. `force` re-reads the whole history (Recalibrate).
    ///
    /// Only goal days are sent: they are all the streak needs, and the live
    /// sync already finalizes today and yesterday for everything else. A
    /// query that fails (locked phone) sends nothing and marks nothing, so
    /// the next foreground tries again.
    func syncStepGoalHistory(force: Bool = false) async {
        guard AppStateManager.shared.isAuthenticated,
              let userId = UserManager.shared.currentUser.backendUserId else { return }

        let defaults = UserDefaults.standard
        let now = Date()
        let today = Self.localDateString(for: now)
        let fullDone = defaults.bool(forKey: historyUploadedKey(userId))
        let full = force || !fullDone
        if !full, defaults.string(forKey: recentHistoryDayKey) == today { return }

        let calendar = Calendar.current
        let start: Date
        if full {
            // Health's own floor, but never before HealthKit existed (iOS 8,
            // Sept 2014): the platform constraint can be far older, and the
            // collection query walks every day in the range.
            start = calendar.startOfDay(for: max(healthStore.earliestPermittedSampleDate(), Self.healthKitEpoch))
        } else {
            start = calendar.date(byAdding: .day, value: -14, to: calendar.startOfDay(for: now)) ?? now
        }
        guard let history = await fetchDailySteps(from: start, to: now) else { return }

        if !StepGoalDayStore.merge(history: history).isEmpty {
            await Self.stepGoalDaysChanged()
        }

        let goalDays = history
            .filter { $0.value >= stepGoal }
            .map { BatchDay(localDate: Self.localDateString(for: $0.key), steps: $0.value) }
            .sorted { $0.localDate < $1.localDate }
        var allSent = true
        var index = 0
        while index < goalDays.count {
            let chunk = Array(goalDays[index..<min(index + Self.batchChunk, goalDays.count)])
            if await postBatch(userId: userId, days: chunk) == nil { allSent = false }
            index += Self.batchChunk
        }
        guard allSent else { return }

        if full { defaults.set(true, forKey: historyUploadedKey(userId)) }
        defaults.set(today, forKey: recentHistoryDayKey)
        if !goalDays.isEmpty {
            await SelfStatsRefresher.refreshBackendStats(userManager: .shared)
        }
    }

    /// Below the server's 3,700-day cap with room to spare.
    private static let batchChunk = 3000

    /// Sept 1, 2014 — HealthKit shipped with iOS 8 that month.
    private static let healthKitEpoch: Date = {
        var c = DateComponents()
        c.year = 2014; c.month = 9; c.day = 1
        return Calendar(identifier: .gregorian).date(from: c) ?? .distantPast
    }()

    /// The goal days changed: redraw everything that judges a day done. The
    /// local streak walk reads `StepGoalDayStore`, so re-reading it from the
    /// index is what lets a steps-only day hold the streak on the phone (and
    /// stops `vettedHealthKitStreak` treating the server's higher number as a
    /// hole to rebuild). `todaySteps` also refreshes the hero's step bar from
    /// a background wake, where nothing else re-reads it.
    @MainActor
    private static func stepGoalDaysChanged(todaySteps: Int? = nil) {
        let hk = HealthKitManager.shared
        if let todaySteps {
            // A fresh read of TODAY (only passed on a crossing, so >= 10k) —
            // replaces whatever the property held, yesterday's count included.
            hk.todaysStepsDay = Calendar.current.startOfDay(for: Date())
            hk.todaysSteps = todaySteps
            WidgetDataStore.save(todaySteps: todaySteps, readOn: Date())
        }
        if StepGoalDayStore.isTodayMet() {
            // Today is safe: retire the lock screen's "streak at risk"
            // countdown now — from a background wake the dashboard that
            // normally ends it isn't on screen.
            StreakRiskActivityManager.sync(
                isAtRisk: false, isCompleted: true, streak: 0,
                goalMiles: 1, currentMiles: 0
            )
        }
        if let index = hk.workoutIndex {
            let streak = index.activeStreak()
            if hk.retroactiveStreak != streak { hk.retroactiveStreak = streak }
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

    private struct BatchDay: Encodable {
        let localDate: String
        let steps: Int
    }

    private struct BatchBody: Encodable {
        let days: [BatchDay]
        let timezoneOffset: Int
    }

    private struct BatchResponse: Decodable {
        let upserted: Int
        let newGoalDays: Int
        let streak: Int
    }

    /// PUT /users/:id/daily-steps/batch. Nil on failure.
    private func postBatch(userId: String, days: [BatchDay]) async -> BatchResponse? {
        let body = BatchBody(days: days, timezoneOffset: TimeZone.current.secondsFromGMT() / 60)
        do {
            let bodyData = try JSONEncoder().encode(body)
            return try await APIClient.fancyFetch(
                endpoint: "/users/\(userId)/daily-steps/batch",
                method: .PUT,
                body: bodyData,
                responseType: BatchResponse.self
            )
        } catch {
            print("[DailyStepsSyncService] Batch PUT failed (\(days.count) days): \(error)")
            return nil
        }
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

    /// Daily totals from `start` through `end`, keyed by each day's start.
    /// One statistics-collection query however long the range — the same
    /// cumulative sum `fetchSteps` takes for a single day, so a day reads the
    /// same number either way. Nil when the query fails (a locked phone), so
    /// callers can tell "no data" from "couldn't read".
    private func fetchDailySteps(from start: Date, to end: Date) async -> [Date: Int]? {
        guard let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount) else { return nil }
        let calendar = Calendar.current
        let anchor = calendar.startOfDay(for: start)
        let predicate = HKQuery.predicateForSamples(withStart: anchor, end: end, options: .strictStartDate)
        var interval = DateComponents()
        interval.day = 1

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsCollectionQuery(
                quantityType: stepType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum,
                anchorDate: anchor,
                intervalComponents: interval
            )
            query.initialResultsHandler = { _, results, error in
                guard let results, error == nil else {
                    continuation.resume(returning: nil)
                    return
                }
                var days: [Date: Int] = [:]
                results.enumerateStatistics(from: anchor, to: end) { stats, _ in
                    guard let sum = stats.sumQuantity() else { return }
                    days[calendar.startOfDay(for: stats.startDate)] = Int(sum.doubleValue(for: HKUnit.count()))
                }
                continuation.resume(returning: days)
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
        content.body = "That counts as today's goal — your streak is safe."
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

    /// The server's `local_date` for a date's local day: always Gregorian
    /// with ASCII digits (the server validates `^\d{4}-\d{2}-\d{2}$`).
    /// Without a calendar and locale this followed the device's, so a phone
    /// on the Buddhist calendar sent "2569-…" and Arabic-Indic digits failed
    /// validation outright. Cached — the history sync formats every day.
    private static let serverDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
    private static let serverDayLock = NSLock()

    private static func localDateString(for date: Date) -> String {
        serverDayLock.lock(); defer { serverDayLock.unlock() }
        serverDayFormatter.timeZone = TimeZone.current
        return serverDayFormatter.string(from: date)
    }
}
