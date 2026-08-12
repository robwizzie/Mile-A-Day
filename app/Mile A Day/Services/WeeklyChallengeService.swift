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
    /// empty catalog). Views hide the feature rather than showing an error.
    @Published private(set) var unavailable = false

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
            saveSnapshot(response)
        } catch {
            // A 404 is the expected answer from a server that predates the
            // feature — not an error worth showing. Keep whatever we had.
            print("[WeeklyChallenge] Load failed: \(error.localizedDescription)")
            if current == nil { unavailable = true }
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

    /// This device's Monday, used only to decide whether a cached payload is
    /// still this week. The server is the authority on the actual window.
    private static func currentWeekStart() -> String {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone.current
        let now = Date()
        let components = calendar.dateComponents(
            [.yearForWeekOfYear, .weekOfYear],
            from: now
        )
        let monday = calendar.date(from: components) ?? now

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        return formatter.string(from: monday)
    }
}
