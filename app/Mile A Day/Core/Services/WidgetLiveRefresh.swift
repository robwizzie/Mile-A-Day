import Foundation
import UIKit
import WidgetKit

/// The two widget snapshots that describe OTHER people — competition standings
/// and today's friends leaderboard — and the silent push that keeps them live.
///
/// Every other widget shows the owner's own numbers, which only change when
/// this phone records something, so the app writing the App Group as it runs
/// is enough. These two change when a FRIEND walks, i.e. while this app is
/// asleep, and used to reach the home screen whenever the owner next opened
/// the app. The server now sends a `widget_refresh` silent push (content-
/// available, background type) when a friend passes you in a competition, in
/// today's head-to-head, or moves on today's leaderboard; `AppDelegate` hands
/// it to `handleRefreshPush`, which refetches and rewrites the snapshot.
///
/// The builders used to be private to MainTabView, which a background wake
/// never constructs — they live here now so both paths write identical rows.
@MainActor
enum WidgetLiveRefresh {

    static let competitionKind = "CompetitionWidget"
    static let leaderboardKind = "DailyLeaderboardWidget"
    /// Kinds whose data a friend's activity can move. Order is the fallback
    /// refresh order when a push names no reason we recognise.
    static let liveKinds = [competitionKind, leaderboardKind]

    /// Hard wall-clock budget for one wake. iOS allows ~30s before it kills a
    /// background-launched app that hasn't called its completion handler, and
    /// an app that runs over is woken less often afterwards.
    static let pushBudgetSeconds: TimeInterval = 24

    // MARK: - Snapshot builders (shared with MainTabView)

    /// Mirror the most urgent active competition into the App Group for the
    /// Competition widget — same focus/sort logic as the dashboard cards.
    /// Returns whether the stored snapshot changed (and so was reloaded).
    @discardableResult
    static func saveCompetitionSnapshot(_ competitions: [Competition]) -> Bool {
        let active = competitions.filter { $0.status == .active }
        guard !active.isEmpty else {
            return WidgetDataStore.clearCompetitionSummary()
        }

        let userId = UserDefaults.standard.string(forKey: "backendUserId")
        guard let top = active.min(by: { a, b in
            TodayFocus.compute(for: a, currentUserId: userId).level.sortKey
                < TodayFocus.compute(for: b, currentUserId: userId).level.sortKey
        }) else { return false }

        let focus = TodayFocus.compute(for: top, currentUserId: userId)

        let ranked = top.acceptedRanked
        // On a team competition the TEAM is the competitor, so the widget
        // ranks teams and names mine — a member's own rank among people is a
        // fact about a leaderboard the competition isn't scored on.
        let myTeam: CompetitionTeam? = userId.flatMap { top.hasTeams ? top.team(for: $0) : nil }
        let rankedTeams = top.rankedTeams
        var rankText = ""
        if let myTeam, let index = rankedTeams.firstIndex(where: { $0.id == myTeam.id }) {
            rankText = "\(myTeam.teamLabel) · \(ActiveCompetitionRow.ordinal(index + 1)) of \(rankedTeams.count)"
        } else if let uid = userId, let index = ranked.firstIndex(where: { $0.user_id == uid }) {
            rankText = "\(ActiveCompetitionRow.ordinal(index + 1)) of \(ranked.count)"
        }

        let urgency: String
        switch focus.level {
        case .urgent: urgency = "urgent"
        case .behind: urgency = "behind"
        case .neutral: urgency = "neutral"
        case .winning: urgency = "winning"
        }

        // Top players (me always included) as a mini-leaderboard for the
        // widget. Same summary the post sticker draws (`stickerSummary`), so
        // the place a photo claims and the place the widget shows can't drift
        // apart — they were separate arithmetic that happened to agree.
        let standings: [WidgetDataStore.StandingRow] = top.standingsPodium(for: userId)
            .map { WidgetDataStore.StandingRow(name: $0.name, valueText: $0.score, isMe: $0.isMe) }

        return WidgetDataStore.save(
            competitionId: top.competition_id,
            competitionName: top.competition_name,
            pill: focus.pill,
            detail: focus.detail,
            rankText: rankText,
            urgency: urgency,
            standings: standings
        )
    }

    /// Mirror today's friends leaderboard into the App Group for the Daily
    /// Leaderboard widget — the same standings the post-mile celebration
    /// shows. `myMiles`/`myGoal` are passed in because the foreground path
    /// has a live HealthKit figure and a background wake may not.
    @discardableResult
    static func saveLeaderboardSnapshot(
        friends items: [FriendActivityItem],
        myName: String,
        myMiles: Double,
        myGoal: Double
    ) -> Bool {
        let myId = UserDefaults.standard.string(forKey: "backendUserId")
        var rows: [WidgetDataStore.LeaderboardRow] = items
            .filter { $0.user_id != myId }
            .map {
                WidgetDataStore.LeaderboardRow(
                    name: $0.displayName,
                    miles: $0.today_miles,
                    isMe: false,
                    completed: $0.completed_today
                )
            }
        rows.append(WidgetDataStore.LeaderboardRow(
            name: myName,
            miles: myMiles,
            isMe: true,
            completed: ProgressCalculator.isGoalCompleted(
                current: myMiles, goal: max(myGoal, 0.01)
            )
        ))
        rows.sort { $0.miles > $1.miles }
        return WidgetDataStore.save(leaderboardRows: rows)
    }

    // MARK: - Silent push

    /// Refresh what a `widget_refresh` push is about. The reason orders the
    /// work — `competition` → the Competition widget, `h2h`/`leaderboard` →
    /// the Daily Leaderboard — and then the OTHER live snapshot is refreshed
    /// too if its widget is installed, because the server coalesces to one
    /// push per user per window and a dropped event has no second chance.
    /// Unchanged snapshots are never written, so the extra fetch costs no
    /// widget reload budget.
    ///
    /// Never touches UI, and only shared singletons: a background wake that
    /// builds its own `UserManager()` re-persists a frozen copy of the user.
    /// Keychain tokens are AfterFirstUnlock, so before the first unlock every
    /// request fails and this reports `.failed` without writing anything.
    static func handleRefreshPush(reason: String?) async -> UIBackgroundFetchResult {
        guard UserDefaults.standard.string(forKey: "backendUserId") != nil else {
            return .noData
        }

        let primary: String?
        switch reason {
        case "competition": primary = competitionKind
        case "h2h", "leaderboard": primary = leaderboardKind
        default: primary = nil
        }
        let installed = await installedKinds()
        var order: [String] = []
        if let primary { order.append(primary) }
        for kind in liveKinds where !order.contains(kind) {
            // No answer from WidgetCenter ⇒ only the kind the push named.
            if installed?.contains(kind) ?? (primary == nil) { order.append(kind) }
        }

        var changed = false
        var failed = false
        for kind in order {
            if Task.isCancelled { break }
            switch await refresh(kind: kind) {
            case .newData: changed = true
            case .failed: failed = true
            default: break
            }
        }
        if changed { return .newData }
        return failed ? .failed : .noData
    }

    private static func refresh(kind: String) async -> UIBackgroundFetchResult {
        switch kind {
        case competitionKind:
            // Throwaway instance: MainTabView's service may not exist in a
            // background launch, and its didSet only feeds the static mirror.
            let service = CompetitionService()
            do {
                try await service.loadCompetitions()
            } catch {
                return .failed
            }
            return saveCompetitionSnapshot(service.competitions) ? .newData : .noData

        case leaderboardKind:
            let service = FriendService()
            guard let items = try? await service.fetchFriendsActivityToday() else {
                return .failed
            }
            let user = UserManager.shared.currentUser
            // A background launch may not have read HealthKit yet (and can't
            // while locked), so take the larger of the live figure and what
            // the app last stored for today — both are today-scoped, and
            // neither may read a failed query as 0 miles.
            let myMiles = max(HealthKitManager.shared.todaysDistance, WidgetDataStore.load().miles)
            let changed = saveLeaderboardSnapshot(
                friends: items,
                myName: user.username ?? user.name,
                myMiles: myMiles,
                myGoal: user.goalMiles
            )
            return changed ? .newData : .noData

        default:
            return .noData
        }
    }

    // MARK: - Installed widgets

    /// The widget kinds on this device's home/lock screen, or nil when
    /// WidgetKit can't say. Reported at device registration so the server
    /// only pushes devices that have a widget the push would move.
    static func installedKinds() async -> [String]? {
        await withCheckedContinuation { continuation in
            WidgetCenter.shared.getCurrentConfigurations { result in
                switch result {
                case .success(let infos):
                    continuation.resume(returning: Array(Set(infos.map(\.kind))).sorted())
                case .failure:
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}

/// A one-shot latch for a completion handler raced by a timeout: whichever
/// side claims it first calls the handler, the other does nothing. iOS treats
/// a second call as a programming error.
final class OneShotLatch: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if claimed { return false }
        claimed = true
        return true
    }
}
