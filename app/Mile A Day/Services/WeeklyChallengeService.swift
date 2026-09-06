import Foundation
import SwiftUI

/// Loads and caches the weekly challenge.
///
/// Snapshotted to UserDefaults, keyed by backend user id, so the Compete tab
/// and the Dashboard card have real content the instant they appear on a cold
/// launch instead of an empty box that fills in a second later. The snapshot is
/// week-stamped: a stale week is discarded rather than shown, because a target
/// and progress from last week are worse than nothing.
@MainActor
final class WeeklyChallengeService: ObservableObject {
    static let shared = WeeklyChallengeService()

    @Published private(set) var current: WeeklyChallengeResponse?
    @Published private(set) var history: [WeeklyChallengeHistoryResponse.Item] = []
    @Published private(set) var isLoading = false
    /// True once a load has finished, successfully or not — so a view can tell
    /// "still loading" from "genuinely unavailable".
    @Published private(set) var hasLoadedOnce = false
    /// The server has no weekly challenge for this user (older deploy, or an
    /// empty catalog) — a 404, and ONLY a 404. Views hide the feature.
    @Published private(set) var unavailable = false
    /// The last load failed for some other reason (offline, a 500, a decode).
    /// Distinct from `unavailable` because the two need opposite copy: one is
    /// "there isn't one this week", the other is "we couldn't fetch it" with a
    /// way to try again. Collapsing them is what let a dashboard card tell a
    /// user "a new one lands every Sunday" ON a Sunday, with a challenge
    /// waiting on the server the whole time.
    @Published private(set) var loadFailed = false

    private let defaults = UserDefaults.standard
    private let snapshotKey = "weeklyChallengeSnapshotV1"
    /// Which account the snapshot belongs to. Restoring another user's
    /// challenge state on a shared install must never happen.
    private let snapshotUserKey = "weeklyChallengeSnapshotUserV1"

    private var userId: String? {
        UserDefaults.standard.string(forKey: "backendUserId")
    }

    private init() {
        restoreSnapshot()
    }

    /// When the last successful load landed — the throttle behind
    /// `refreshIfStale`.
    private var lastLoadedAt: Date?

    /// A load the Dashboard can call on every appearance without hammering the
    /// endpoint. It fires on tab switches, and the read behind it is not
    /// cheap: a measure, a baseline, a friends leaderboard and last week's
    /// result. Pull-to-refresh and push taps still call `refresh()` directly —
    /// those are a user asking for fresh data, which is never stale.
    func refreshIfStale(maxAge: TimeInterval = 60) async {
        if current != nil, let lastLoadedAt,
           Date().timeIntervalSince(lastLoadedAt) < maxAge {
            return
        }
        await refresh()
    }

    func refresh() async {
        guard let userId else { return }
        isLoading = true
        defer {
            isLoading = false
            hasLoadedOnce = true
        }

        do {
            let response: WeeklyChallengeResponse = try await APIClient.fancyFetch(
                endpoint: "/users/\(userId)/weekly-challenge",
                responseType: WeeklyChallengeResponse.self
            )
            current = response
            unavailable = false
            loadFailed = false
            lastLoadedAt = Date()
            saveSnapshot(response)
        } catch APIError.notFound {
            // The expected answer from a server that predates the feature, or
            // one with an empty catalog. Genuinely "there isn't one".
            if current == nil { unavailable = true }
            loadFailed = false
        } catch {
            // Anything else is a failure to FETCH, not an absence. Keep
            // whatever we had and let the card offer a retry.
            print("[WeeklyChallenge] Load failed: \(error.localizedDescription)")
            loadFailed = current == nil
        }
    }

    func loadHistory() async {
        guard let userId else { return }
        do {
            let response: WeeklyChallengeHistoryResponse = try await APIClient.fancyFetch(
                endpoint: "/users/\(userId)/weekly-challenge/history?limit=26",
                responseType: WeeklyChallengeHistoryResponse.self
            )
            history = response.history
        } catch {
            print("[WeeklyChallenge] History failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Snapshot

    private func saveSnapshot(_ response: WeeklyChallengeResponse) {
        guard let userId, let data = try? JSONEncoder().encode(response) else { return }
        defaults.set(data, forKey: snapshotKey)
        defaults.set(userId, forKey: snapshotUserKey)
    }

    private func restoreSnapshot() {
        guard let userId,
              defaults.string(forKey: snapshotUserKey) == userId,
              let data = defaults.data(forKey: snapshotKey),
              let decoded = try? JSONDecoder().decode(WeeklyChallengeResponse.self, from: data)
        else { return }

        // Week-stamped: last week's target and progress would be actively
        // misleading, so a stale snapshot is dropped rather than displayed.
        guard decoded.week_start == Self.currentWeekStart() else { return }
        current = decoded
    }

    /// This device's Sunday, used only to decide whether a cached payload is
    /// still this week. The server is the authority on the actual window.
    ///
    /// Weeks run Sunday→Saturday. Derived by subtracting the weekday index
    /// rather than going through `yearForWeekOfYear` — that route depends on the
    /// calendar's `firstWeekday` and has awkward behaviour across year
    /// boundaries, and this only ever needs "the Sunday on or before today".
    private static func currentWeekStart() -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        let now = Date()
        // Gregorian weekday: 1 = Sunday, so subtracting (weekday - 1) days lands
        // on this week's Sunday, and on Sunday itself subtracts nothing.
        let weekday = calendar.component(.weekday, from: now)
        let start = calendar.date(
            byAdding: .day,
            value: -(weekday - 1),
            to: calendar.startOfDay(for: now)
        ) ?? now

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        return formatter.string(from: start)
    }
}
