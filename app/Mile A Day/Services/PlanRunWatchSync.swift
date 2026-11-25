import Combine
import Foundation

/// Keeps the Watch's copy of the plan current (Run Plans v2). Follows
/// `RunPlanV2Store.current` (started once from the app root): whenever it
/// changes, the runnable days from TODAY on (a week) go into the persisted
/// `MADWatchBridge.planRunJSON`, so every later app-context push carries them
/// and the Watch still has today's session after midnight with the phone app
/// closed. The Watch picks the day dated today. A plan ending, Plus lapsing
/// or sign-out sets `current` to nil, which takes the key out of the context.
///
/// The week comes from `/current` (this week, today, next run) plus one
/// `/days` read for the seven days ahead, refreshed at most every 30 minutes
/// (it covers the Sunday-to-Monday rollover the current week can't).
@MainActor
enum PlanRunWatchSync {
    private static var subscription: AnyCancellable?
    private static var ahead: [RunPlanV2Day] = []
    private static var lastFetch: (day: String, at: Date)?
    private static let daysAhead = 7

    static func start() {
        guard subscription == nil else { return }
        subscription = RunPlanV2Store.shared.$current
            .receive(on: DispatchQueue.main)
            .sink { current in update(current: current) }
    }

    static func update(current: RunPlanV2Current?) {
        guard let current else {
            ahead = []
            lastFetch = nil
            set(nil)
            return
        }
        let todayKey = RunPlanV2Date.todayKey()
        let lastKey = RunPlanV2Date.addingDays(daysAhead - 1, to: todayKey) ?? todayKey
        var byDate: [String: RunPlanV2Day] = [:]
        // Later sources win: the /days read is older than /current's week.
        for day in ahead + current.week + [current.next_run].compactMap({ $0 }) where !day.dateKey.isEmpty {
            byDate[day.dateKey] = day
        }
        // The server's `today` only counts when it IS today (a cached read
        // after midnight is yesterday's).
        if let served = current.today, served.local_date == todayKey { byDate[todayKey] = served }
        let days = byDate.values
            .filter { $0.dateKey >= todayKey && $0.dateKey <= lastKey && $0.offersPlanRun }
            .sorted { $0.dateKey < $1.dateKey }
            .compactMap(\.planRunDay)
        set(PlanRunDay.json(days))
        fetchAheadIfStale(from: todayKey, to: lastKey)
    }

    private static func fetchAheadIfStale(from: String, to: String) {
        if let lastFetch, lastFetch.day == from, Date().timeIntervalSince(lastFetch.at) < 30 * 60 { return }
        lastFetch = (from, Date())
        Task { @MainActor in
            guard let days = try? await RunPlanV2Service.days(from: from, to: to) else { return }
            ahead = days
            update(current: RunPlanV2Store.shared.current)
        }
    }

    private static func set(_ json: String?) {
        let bridge = MADWatchBridge.shared
        guard bridge.planRunJSON != json else { return }
        bridge.planRunJSON = json
        bridge.pushSnapshotIfReady()
    }
}
