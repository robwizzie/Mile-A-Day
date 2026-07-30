//
//  StreakErasStore.swift
//  Mile A Day
//
//  Session cache of the signed-in user's streak-era history
//  (GET /workouts/:userId/streak-eras) plus the comeback / record
//  derivations the celebration flow and dashboard read.
//
//  Plain ObservableObject (not @MainActor) so synchronous readers like the
//  celebration enqueue helpers can call the derivations from any context —
//  matching UserManager's isolation style. @Published writes hop to main.
//

import Foundation

final class StreakErasStore: ObservableObject {
    static let shared = StreakErasStore()

    @Published private(set) var response: StreakErasResponse?
    private(set) var lastRefreshAt: Date?

    private init() {}

    var currentEra: StreakEraAPI? {
        response?.eras.first(where: { $0.is_current })
    }

    /// The era immediately before the current one (nil when the current run
    /// is the first ever). Eras arrive newest-first.
    var previousEra: StreakEraAPI? {
        guard let eras = response?.eras,
            let idx = eras.firstIndex(where: { $0.is_current }),
            idx + 1 < eras.count
        else { return nil }
        return eras[idx + 1]
    }

    /// Longest length among NON-current eras — the record the current run has
    /// to beat.
    var previousBest: Int {
        guard let eras = response?.eras else { return 0 }
        return eras.filter { !$0.is_current }.map(\.length).max() ?? 0
    }

    func refresh() async {
        guard let userId = UserDefaults.standard.string(forKey: "backendUserId") else { return }
        do {
            try await fetchAndStore(userId: userId)
        } catch {
            // Tolerated: comeback/record moments and the hall simply don't
            // render this session. Never block the goal celebration on this.
            print("[StreakErasStore] refresh failed: \(error)")
        }
    }

    /// `WorkoutService` is @MainActor, so it's built and called here rather than
    /// held as a stored property — the store itself stays nonisolated so the
    /// derivations below remain callable synchronously from any context.
    @MainActor
    private func fetchAndStore(userId: String) async throws {
        let fresh = try await WorkoutService().getStreakEras(userId: userId)
        response = fresh
        lastRefreshAt = Date()
    }

    func refreshIfStale(maxAge: TimeInterval = 300) async {
        if let at = lastRefreshAt, Date().timeIntervalSince(at) < maxAge, response != nil {
            return
        }
        await refresh()
    }

    // MARK: - Comeback / record derivations

    struct ComebackContext {
        let day: Int  // current era length (1, 3 and 7 are celebrated)
        let priorLength: Int  // the era that ended at the break
        let recordLength: Int  // longest ever, for "N to your record" copy
        let eraNumber: Int  // chronological index (Era 1 = first ever)
        let eraStart: String  // current era's start date — one-shot key basis
    }

    /// Non-nil while the current streak is a COMEBACK: a prior era of >= 3
    /// days ended at most 30 missed days before this run started. Beyond that
    /// gap a new streak reads as a fresh start, not a chapter two.
    func comebackContext() -> ComebackContext? {
        guard let response, let current = currentEra, let prior = previousEra else { return nil }
        guard prior.length >= 3 else { return nil }
        guard let gap = Self.daysBetween(prior.end_date, current.start_date),
            gap >= 1, gap - 1 <= 30
        else { return nil }
        let currentIndex = response.eras.firstIndex(where: { $0.is_current }) ?? 0
        return ComebackContext(
            day: current.length,
            priorLength: prior.length,
            recordLength: max(response.longest_streak, current.length),
            eraNumber: response.eras.count - currentIndex,
            eraStart: current.start_date
        )
    }

    struct RecordContext {
        let days: Int
        let previousBest: Int
        let eraStart: String
    }

    /// Non-nil once the current era has PASSED every previous era — and the
    /// old record was substantial (>= 7) so day-2 accounts don't get a
    /// "record" popup every morning.
    func recordContext() -> RecordContext? {
        guard let current = currentEra else { return nil }
        let prev = previousBest
        guard prev >= 7, current.length > prev else { return nil }
        return RecordContext(days: current.length, previousBest: prev, eraStart: current.start_date)
    }

    /// Whole days from `a` to `b`, both YYYY-MM-DD.
    static func daysBetween(_ a: String, _ b: String) -> Int? {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.timeZone = TimeZone(identifier: "UTC")
        guard let da = fmt.date(from: a), let db = fmt.date(from: b) else { return nil }
        return Int(round(db.timeIntervalSince(da) / 86400))
    }
}
