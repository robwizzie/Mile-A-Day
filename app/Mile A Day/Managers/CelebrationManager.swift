//
//  CelebrationManager.swift
//  Mile A Day
//

import Foundation
import SwiftUI

// MARK: - Workout Breakdown

/// Breakdown of a single workout type (e.g. all running, all walking) or a single workout
struct WorkoutBreakdown: Equatable {
    let type: String           // "running", "walking", "cycling", "hiking", "other"
    let distance: Double       // miles
    let duration: TimeInterval // seconds
    let displayName: String    // "Run", "Walk", "Cycle", "Hike"
    let icon: String           // SF Symbol: "figure.run", "figure.walk", etc.

    /// Formatted pace (minutes per mile)
    var pace: Double? {
        guard distance > 0 else { return nil }
        return (duration / 60.0) / distance
    }

    /// Formatted pace string (e.g., "8:32/mi")
    var formattedPace: String? {
        guard let pace = pace else { return nil }
        let minutes = Int(pace)
        let seconds = Int((pace - Double(minutes)) * 60)
        return String(format: "%d:%02d/mi", minutes, seconds)
    }

    /// Formatted duration string (e.g., "12:45")
    var formattedDuration: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// Formatted distance string (e.g., "1.25")
    var formattedDistance: String {
        String(format: "%.2f", distance)
    }
}

// MARK: - Goal Completion Stats

/// Stats displayed in the goal completion celebration
struct GoalCompletionStats: Equatable {
    let todaysDistance: Double
    let goalDistance: Double
    let currentStreak: Int
    let totalLifetimeMiles: Double
    let bestDayMiles: Double
    let todaysAveragePace: TimeInterval? // Average pace in minutes per mile from today's workouts
    let todaysFastestPace: TimeInterval? // Fastest pace from today's workouts
    let personalBestPace: TimeInterval? // All-time fastest pace
    let todaysTotalDuration: TimeInterval // Total workout duration in seconds
    let todaysCalories: Double // Total calories burned today
    let todaysWorkoutCount: Int // Number of workouts completed today
    let workoutBreakdowns: [WorkoutBreakdown] // Today's workouts grouped by type
    let latestWorkout: WorkoutBreakdown? // Most recent workout details
    /// Day-1 comeback framing ("96 days came before. Day 1 of the next run
    /// starts now.") — rendered by both goal celebration views when present.
    /// Defaulted so every existing construction site compiles unchanged.
    var comebackLine: String? = nil

    var percentOver: Double {
        guard goalDistance > 0 else { return 0 }
        return ((todaysDistance - goalDistance) / goalDistance) * 100
    }

    var isNewPersonalBest: Bool {
        todaysDistance > bestDayMiles && bestDayMiles > 0
    }

    /// Check if today's fastest pace is a new personal best
    var isPacePB: Bool {
        guard let todaysFastest = todaysFastestPace, let bestPace = personalBestPace, bestPace > 0 else { return false }
        return todaysFastest < bestPace
    }

    var streakMilestone: StreakMilestone? {
        StreakMilestone.allCases.first { $0.days == currentStreak }
    }

    /// Formatted total duration string (e.g., "32:15")
    var formattedDuration: String {
        let minutes = Int(todaysTotalDuration) / 60
        let seconds = Int(todaysTotalDuration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// Formatted calories string
    var formattedCalories: String {
        if todaysCalories >= 1000 {
            return String(format: "%.1fk", todaysCalories / 1000)
        }
        return String(format: "%.0f", todaysCalories)
    }

    static var placeholder: GoalCompletionStats {
        GoalCompletionStats(
            todaysDistance: 1.5,
            goalDistance: 1.0,
            currentStreak: 7,
            totalLifetimeMiles: 150,
            bestDayMiles: 5.0,
            todaysAveragePace: 8.5,
            todaysFastestPace: 7.8,
            personalBestPace: 7.5,
            todaysTotalDuration: 765, // 12:45
            todaysCalories: 185,
            todaysWorkoutCount: 1,
            workoutBreakdowns: [
                WorkoutBreakdown(type: "running", distance: 1.2, duration: 600, displayName: "Run", icon: "figure.run"),
                WorkoutBreakdown(type: "walking", distance: 0.3, duration: 165, displayName: "Walk", icon: "figure.walk")
            ],
            latestWorkout: WorkoutBreakdown(type: "running", distance: 1.2, duration: 600, displayName: "Run", icon: "figure.run")
        )
    }
}

/// Milestone tier: mini milestones are frequent encouragement, major milestones get extra celebration
enum MilestoneTier {
    case mini
    case major
}

/// Streak milestones for celebration highlights
/// Mini milestones every ~50 days keep users motivated; major milestones get special treatment
enum StreakMilestone: CaseIterable {
    // Mini milestones (frequent encouragement)
    case week           // 7
    case twoWeeks       // 14
    case threeWeeks     // 21
    case month          // 30
    case fiftyDays      // 50
    case seventyFive    // 75
    // Major milestones (extra special)
    case hundredDays    // 100
    // Mini
    case oneFifty       // 150
    case twoHundred     // 200
    // Major
    case twoFifty       // 250
    case threeHundred   // 300
    // Major
    case year           // 365
    // Mini
    case fourHundred    // 400
    case fourFifty      // 450
    // Major
    case fiveHundred    // 500
    // Mini
    case sixHundred     // 600
    // Major
    case twoYears       // 730
    // Major
    case thousandDays   // 1000

    var days: Int {
        switch self {
        case .week: return 7
        case .twoWeeks: return 14
        case .threeWeeks: return 21
        case .month: return 30
        case .fiftyDays: return 50
        case .seventyFive: return 75
        case .hundredDays: return 100
        case .oneFifty: return 150
        case .twoHundred: return 200
        case .twoFifty: return 250
        case .threeHundred: return 300
        case .year: return 365
        case .fourHundred: return 400
        case .fourFifty: return 450
        case .fiveHundred: return 500
        case .sixHundred: return 600
        case .twoYears: return 730
        case .thousandDays: return 1000
        }
    }

    var tier: MilestoneTier {
        switch self {
        case .hundredDays, .twoFifty, .threeHundred, .year, .fiveHundred, .twoYears, .thousandDays:
            return .major
        default:
            return .mini
        }
    }

    var isMajor: Bool { tier == .major }

    var title: String {
        switch self {
        case .week: return "1 Week Streak!"
        case .twoWeeks: return "2 Week Streak!"
        case .threeWeeks: return "3 Week Streak!"
        case .month: return "1 Month Streak!"
        case .fiftyDays: return "50 Day Streak!"
        case .seventyFive: return "75 Day Streak!"
        case .hundredDays: return "100 Day Streak!"
        case .oneFifty: return "150 Day Streak!"
        case .twoHundred: return "200 Day Streak!"
        case .twoFifty: return "250 Day Streak!"
        case .threeHundred: return "300 Day Streak!"
        case .year: return "1 Year Streak!"
        case .fourHundred: return "400 Day Streak!"
        case .fourFifty: return "450 Day Streak!"
        case .fiveHundred: return "500 Day Streak!"
        case .sixHundred: return "600 Day Streak!"
        case .twoYears: return "2 Year Streak!"
        case .thousandDays: return "1,000 Day Streak!"
        }
    }

    var emoji: String {
        switch self {
        case .week: return "🔥"
        case .twoWeeks: return "💪"
        case .threeWeeks: return "⚡️"
        case .month: return "🏆"
        case .fiftyDays: return "🎯"
        case .seventyFive: return "✨"
        case .hundredDays: return "💎"
        case .oneFifty: return "🚀"
        case .twoHundred: return "⭐️"
        case .twoFifty: return "👑"
        case .threeHundred: return "🏅"
        case .year: return "🌟"
        case .fourHundred: return "🔥"
        case .fourFifty: return "💪"
        case .fiveHundred: return "🏆"
        case .sixHundred: return "⚡️"
        case .twoYears: return "💎"
        case .thousandDays: return "👑"
        }
    }

    /// Subtitle shown on major milestones
    var majorSubtitle: String {
        switch self {
        case .hundredDays: return "Triple digits! You're in the elite!"
        case .twoFifty: return "A quarter thousand days of dedication!"
        case .threeHundred: return "300 days of pure commitment!"
        case .year: return "365 days. One full year. Legendary!"
        case .fiveHundred: return "Half a thousand! Absolutely incredible!"
        case .twoYears: return "Two full years! You're unstoppable!"
        case .thousandDays: return "ONE THOUSAND DAYS. You are a legend!"
        default: return "Incredible dedication!"
        }
    }
}

/// The headline moment for a STREAK MILESTONE day (7, 30, 100, 500…).
///
/// It is its own celebration, right after the flame, because the flame is the
/// same screen every day: a 500-day streak landed on exactly the card a
/// 12-day one gets, and that was the report. Plain Foundation values only —
/// this file is also compiled into the Watch target.
///
/// `achievedOn` is the day the number was reached. Live it is today; a REPLAY
/// from the medal carries the medal's own date, so the screen can say "this
/// is how it looked on Sep 30" rather than pretending it happened now.
struct StreakMilestoneInfo: Equatable {
    let days: Int
    let achievedOn: Date
    /// Lifetime miles at the time, when known. A replay from a medal months
    /// later doesn't know it, and printing today's total under an old date
    /// would be a number that was never true on that day.
    let totalMiles: Double?
    let isReplay: Bool

    /// Which streak lengths earn this screen. The app's own `StreakMilestone`
    /// days plus every hundred — the same set the share studio's milestone card
    /// already treats as a milestone (`ShareMilestone.isMilestone`). Multiples
    /// of 365 belong to the yearly celebration, which is the bigger version of
    /// this same moment.
    static func isCelebrated(_ days: Int) -> Bool {
        guard days > 0, days % 365 != 0 else { return false }
        return StreakMilestone.allCases.contains { $0.days == days }
            || (days >= 100 && days % 100 == 0)
    }

    var milestone: StreakMilestone? {
        StreakMilestone.allCases.first { $0.days == days }
    }

    /// Big moments (100, 250, 500…) get the full show; the minis a lighter one.
    var isMajor: Bool {
        milestone?.isMajor ?? (days >= 100)
    }

    /// One-shot key: one moment per day it was reached, so a later streak
    /// that reaches 500 again gets its own.
    var oneShotKey: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.calendar = Calendar.current
        f.timeZone = TimeZone.current
        return "streak-milestone-\(days)-\(f.string(from: achievedOn))"
    }
}

// MARK: - Celebration Types

/// Payload for the daily-challenge completion celebration. Visuals (icon, gradient)
/// are resolved from today's challenge at enqueue time so the moment matches the card.
struct ChallengeCelebrationInfo: Equatable {
    let key: String
    let title: String
    let description: String
    let icon: String
    let gradient: [Color]
    let challengeStreak: Int
}

/// Payload for the ghost-race win.
///
/// Snapshotted at the 1.00-mile crossing, so the celebration can only ever
/// show the same numbers the live chip showed — the popup can't contradict
/// what the user watched happen.
struct GhostRaceWin: Equatable {
    /// Seconds the user finished AHEAD by. Always positive; a loss stays
    /// silent (the frozen chip already told that story).
    let marginSeconds: Double
    /// The user's time over the RACED distance, interpolated at the exact
    /// crossing. Named for the mile because that is what every ghost was when
    /// this shipped; `distanceMiles` is what says whether it still is.
    let mileSeconds: Double
    /// The ghost's time over the raced distance.
    let ghostSeconds: Double
    /// How the ghost was named in copy ("your best", "your PR", "your target").
    let ghostName: String
    /// "running" | "walking" — drives the verb and the accent.
    let activityKey: String
    /// Set when this mile ALSO became the new best to beat.
    let newRecordSeconds: Double?
    /// The friend whose mile this was, when the ghost was theirs. Carried onto
    /// the saved workout so the server can tell them they were caught.
    let friendUserId: String?
    /// Workout it belongs to, so the win can be attached to the post.
    let workoutId: String?
    /// How far the race actually was. Defaulted so every existing construction
    /// site (and the preview) keeps meaning the mile — this struct is plain
    /// Equatable, never Codable, so a default is safe here in a way it would
    /// not be on a persisted model.
    var distanceMiles: Double = 1.0
}

/// Types of celebrations that can be shown
enum CelebrationType: Identifiable, Equatable {
    case goalCompleted(stats: GoalCompletionStats)
    /// Duolingo-style "you moved up" today's-miles leaderboard among friends,
    /// shown right after the streak/fire celebration.
    case leaderboardMoveUp(stats: GoalCompletionStats)
    case postGoalWorkout(stats: GoalCompletionStats)
    case badgeUnlocked(badge: Badge)
    case milestone(title: String, description: String, icon: String)
    /// Headline yearly streak celebration — fired at every multiple of 365 days.
    case yearMilestone(info: YearlyMilestoneInfo)
    /// Headline streak-milestone day (7, 30, 100, 500…) — right after the flame.
    case streakMilestone(info: StreakMilestoneInfo)
    /// One-time welcome summary for a new account with historical data — shows
    /// the COUNT of badges unlocked instead of spamming a popup per badge.
    case badgeSummary(count: Int, badges: [Badge])
    /// Several medals arriving in ONE refresh, as one card instead of a popup
    /// each. `retroactive` = earned on EARLIER days (a server-side backfill
    /// such as the holiday medals, or medals earned while the app went
    /// unopened) — the card dates each one rather than calling it today's.
    case badgeBatch(badges: [Badge], retroactive: Bool)
    /// Rewarding moment when the user completes today's daily challenge.
    case challengeCompleted(info: ChallengeCelebrationInfo)
    /// BeReal-style prompt to add a photo to the just-finished mile.
    case postRunPhotoPrompt(workoutId: String, workoutType: String)
    /// Comeback arc: day 3 / day 7 of a new streak that started within 30 days
    /// of a broken run of 3+ days. (Day 1 rides inside goalCompleted via
    /// GoalCompletionStats.comebackLine instead of a second popup.)
    case comeback(day: Int, priorLength: Int, recordLength: Int, eraNumber: Int, eraStart: String)
    /// The current streak just PASSED the user's all-time record.
    case newRecordStreak(days: Int, previousBest: Int, eraStart: String)
    /// Beat the ghost you chose over the mile.
    case ghostBeaten(win: GhostRaceWin)
    /// New medals unlocked Flamey wardrobe items (catalog ids — plain
    /// strings, because this file is also a Watch member and the catalog
    /// isn't). One item or a batch; one card either way. Fun-only, decided by
    /// the enqueuer (`FlameyUnlocks`); stamped into `FlameyUnlockLedger` at
    /// dismissal.
    case flameyUnlocked(itemIds: [String])

    var id: String {
        switch self {
        case .goalCompleted:
            return "goal-completed-\(Date().timeIntervalSince1970)"
        case .leaderboardMoveUp:
            return "leaderboard-move-up"
        case .postGoalWorkout:
            return "post-goal-\(Date().timeIntervalSince1970)"
        case .badgeUnlocked(let badge):
            return "badge-\(badge.id)"
        case .milestone(let title, _, _):
            return "milestone-\(title)"
        case .yearMilestone(let info):
            return "year-milestone-\(info.years)"
        case .streakMilestone(let info):
            return info.oneShotKey
        case .badgeSummary:
            return "badge-summary"
        case .badgeBatch(let badges, let retroactive):
            return "badge-batch-\(retroactive ? "retro" : "today")-\(badges.map(\.id).sorted().joined(separator: ","))"
        case .challengeCompleted(let info):
            return "challenge-completed-\(info.key)"
        case .postRunPhotoPrompt(let workoutId, _):
            return "post-run-photo-\(workoutId)"
        case .comeback(let day, _, _, _, let eraStart):
            return "comeback-\(eraStart)-\(day)"
        case .newRecordStreak(_, _, let eraStart):
            return "record-\(eraStart)"
        case .ghostBeaten(let win):
            return "ghost-beaten-\(win.workoutId ?? "\(win.mileSeconds)")"
        case .flameyUnlocked(let ids):
            return "flamey-unlocked-\(ids.joined(separator: ","))"
        }
    }

    static func == (lhs: CelebrationType, rhs: CelebrationType) -> Bool {
        switch (lhs, rhs) {
        case (.goalCompleted, .goalCompleted):
            return true // Only one goal completion per day
        case (.leaderboardMoveUp, .leaderboardMoveUp):
            return true
        case (.postGoalWorkout, .postGoalWorkout):
            return true
        case (.badgeUnlocked(let b1), .badgeUnlocked(let b2)):
            return b1.id == b2.id
        case (.milestone(let t1, _, _), .milestone(let t2, _, _)):
            return t1 == t2
        case (.yearMilestone(let i1), .yearMilestone(let i2)):
            return i1.years == i2.years
        case (.streakMilestone(let i1), .streakMilestone(let i2)):
            return i1.days == i2.days
        case (.badgeSummary, .badgeSummary):
            return true // only one welcome summary
        case (.badgeBatch(let b1, let r1), .badgeBatch(let b2, let r2)):
            return r1 == r2 && Set(b1.map(\.id)) == Set(b2.map(\.id))
        case (.challengeCompleted(let i1), .challengeCompleted(let i2)):
            return i1.key == i2.key // one celebration per challenge per day
        case (.postRunPhotoPrompt(let w1, _), .postRunPhotoPrompt(let w2, _)):
            return w1 == w2 // one prompt per workout
        case (.comeback(let d1, _, _, _, let s1), .comeback(let d2, _, _, _, let s2)):
            return d1 == d2 && s1 == s2 // one per era-day
        case (.newRecordStreak(_, _, let s1), .newRecordStreak(_, _, let s2)):
            return s1 == s2 // one record moment per era
        case (.ghostBeaten(let w1), .ghostBeaten(let w2)):
            return w1.workoutId == w2.workoutId // one win per raced workout
        case (.flameyUnlocked, .flameyUnlocked):
            return true // one wardrobe card at a time; the rest waits for its stamp
        default:
            return false
        }
    }
}

/// Actions that can be triggered when dismissing a celebration
enum CelebrationDismissAction: Equatable {
    case none
    case viewBadges
}

// MARK: - Posted Workout Registry

/// Which workouts already carry a deliberate post of this user's.
///
/// The SERVER has always known this — `createPost` allows exactly one live user
/// post per workout across the feed and story slots and throws
/// `workout_already_posted` for a second (postService.ts). The client had no
/// memory of it at all, and two surfaces need the answer *before* they ask:
///
///  - the post-run photo prompt, which is a fire-and-forget celebration: by the
///    time a 409 could teach it anything, it has already interrupted someone to
///    ask for a photo of a walk they just posted;
///  - the buddy recap's "Post this walk" CTA, which would otherwise stay lit
///    after the walk was posted and lead a second attempt into that 409.
///
/// Note what it does NOT gate: `RunPostService.autoPostMile`. A story-only
/// share consumes the run's user-post slot while leaving the FEED without a
/// card, which is precisely when the auto route card should still go up — and
/// the server already refuses to let one overwrite a deliberate post.
///
/// Keyed by HealthKit workout uuid, which is the same id the server stores as
/// `workouts.workout_id` and the same one the fresh window and the photo prompt
/// key on (ios.md: those three must agree or the dedup silently misses).
///
/// Persisted, because the thing it prevents happens ACROSS a relaunch: the
/// prompt's queue is in-memory and starts empty every cold launch. Bounded to
/// the most recent ids, newline-joined — same shape and reasoning as
/// `promptedPhotoWorkoutIdsV1` below, which is why it lives in THIS file rather
/// than one of its own: `addCelebration` reads it, and this file is a member of
/// the Watch target, which a file under `Services/` never joins.
///
/// Deliberately advisory, never authoritative: it can only be wrong in the safe
/// direction (a missing entry means someone gets asked, and the server still
/// refuses the duplicate). The one way to go stale is a post deleted on another
/// device, which `clear(_:)` fixes on this one whenever the feed sees it.
/// Which Flamey wardrobe items this account has been told about (the
/// "New for Flamey" card). Lives HERE, dependency-free, because this file is
/// also compiled into the Watch target and `markConsumed` stamps it; the iOS
/// side (`FlameyUnlocks`) reads it to decide what's news. Absent = never
/// seeded (the first reconcile seeds it silently).
enum FlameyUnlockLedger {
    private static let prefix = "flameyAnnouncedItemsV1|"

    private static var key: String? {
        guard let me = UserDefaults.standard.string(forKey: "backendUserId"), !me.isEmpty else { return nil }
        return prefix + me
    }

    static func announced() -> Set<String>? {
        guard let key, let raw = UserDefaults.standard.stringArray(forKey: key) else { return nil }
        return Set(raw)
    }

    static func markAnnounced(_ ids: Set<String>) {
        guard let key else { return }
        let union = (announced() ?? []).union(ids)
        UserDefaults.standard.set(union.sorted(), forKey: key)
    }
}

enum PostedWorkoutRegistry {
    private static let storageKey = "postedWorkoutIdsV1"
    private static let maxIds = 200

    static func hasPost(for workoutId: String) -> Bool {
        ids().contains(workoutId)
    }

    /// Record that `workoutId` now carries a real post. Idempotent.
    static func markPosted(_ workoutId: String) {
        guard !workoutId.isEmpty else { return }
        var current = ids()
        guard !current.contains(workoutId) else { return }
        current.append(workoutId)
        if current.count > maxIds { current = Array(current.suffix(maxIds)) }
        write(current)
    }

    /// The post was deleted, so the run's slot is free again and every surface
    /// above should offer it once more.
    static func clear(_ workoutId: String) {
        let current = ids()
        guard current.contains(workoutId) else { return }
        write(current.filter { $0 != workoutId })
    }

    private static func ids() -> [String] {
        (UserDefaults.standard.string(forKey: storageKey) ?? "")
            .split(separator: "\n")
            .map(String.init)
    }

    private static func write(_ ids: [String]) {
        UserDefaults.standard.set(ids.joined(separator: "\n"), forKey: storageKey)
    }
}

/// Manages queuing and displaying celebration screens
class CelebrationManager: ObservableObject {
    static let shared = CelebrationManager()

    /// Posted when queued celebrations are DROPPED without being seen (the
    /// navigate-away clear in dismissWithAction, a replay reset). userInfo
    /// carries "ids": [String]. Enqueue-side session stamps — DashboardView's
    /// goalCelebrationEnqueuedDay — listen and reset, so a flame that was
    /// queued behind a badge popup and then cleared by "View badges" can
    /// re-fire from the next level-trigger instead of being lost until the
    /// next cold launch (hasShownGoalCelebrationToday never stamped, but the
    /// session gate blocked every re-check).
    static let droppedUnseenNotification = Notification.Name("MAD_CelebrationsDroppedUnseen")

    private func reportDroppedUnseen(_ dropped: [CelebrationType]) {
        guard !dropped.isEmpty else { return }
        NotificationCenter.default.post(
            name: Self.droppedUnseenNotification,
            object: nil,
            userInfo: ["ids": dropped.map(\.id)]
        )
    }

    @Published private(set) var celebrationQueue: [CelebrationType] = []
    @Published var currentCelebration: CelebrationType?
    @Published var isShowingCelebration = false
    @Published var pendingAction: CelebrationDismissAction = .none

    /// Whether the app is currently in the foreground and visible to the user.
    /// Celebrations are deferred until this is true so animations aren't wasted in the background.
    @Published var appIsActive: Bool = true

    /// Tracks whether goal completion has been shown today (to prevent duplicates)
    @AppStorage("lastGoalCelebrationDate") private var lastGoalCelebrationDateString: String = ""

    /// Workout ids that have already been offered the post-run photo prompt.
    /// Persisted (newline-joined) so a cold relaunch — which starts with an empty
    /// in-memory queue and can't dedup against it — never re-prompts for a mile
    /// already handled. Bounded to the most recent `maxPromptedPhotoIds`.
    @AppStorage("promptedPhotoWorkoutIdsV1") private var promptedPhotoWorkoutIdsRaw: String = ""
    private let maxPromptedPhotoIds = 200

    private func hasPromptedPhoto(for workoutId: String) -> Bool {
        promptedPhotoWorkoutIdsRaw.split(separator: "\n").contains(where: { String($0) == workoutId })
    }

    private func markPromptedPhoto(for workoutId: String) {
        var ids = promptedPhotoWorkoutIdsRaw.split(separator: "\n").map(String.init)
        guard !ids.contains(workoutId) else { return }
        ids.append(workoutId)
        if ids.count > maxPromptedPhotoIds { ids = Array(ids.suffix(maxPromptedPhotoIds)) }
        promptedPhotoWorkoutIdsRaw = ids.joined(separator: "\n")
    }

    /// Comeback + record one-shots (keys "comeback-<eraStart>-<day>" and
    /// "record-<eraStart>"). Persisted newline-joined like the photo-prompt
    /// ids, stamped at DISMISSAL in markConsumed() — a moment the user never
    /// saw is never spent. Bounded; each era contributes at most 3 keys.
    @AppStorage("comebackRecordShownKeysV1") private var comebackRecordShownKeysRaw: String = ""
    private let maxComebackRecordKeys = 60

    func hasShownComebackOrRecord(id: String) -> Bool {
        comebackRecordShownKeysRaw.split(separator: "\n").contains(where: { String($0) == id })
    }

    private func markComebackOrRecordShown(id: String) {
        var ids = comebackRecordShownKeysRaw.split(separator: "\n").map(String.init)
        guard !ids.contains(id) else { return }
        ids.append(id)
        if ids.count > maxComebackRecordKeys { ids = Array(ids.suffix(maxComebackRecordKeys)) }
        comebackRecordShownKeysRaw = ids.joined(separator: "\n")
    }

    /// Backing store for the extra-mile workout-count baseline. Scoped to a single
    /// day via `lastPostGoalDateString` — see `lastPostGoalWorkoutCount`.
    @AppStorage("lastPostGoalWorkoutCount") private var storedPostGoalWorkoutCount: Int = 0
    @AppStorage("lastPostGoalDate") private var lastPostGoalDateString: String = ""

    /// Workout-count baseline above which an extra-mile ("Extra mile") celebration
    /// fires. Resets to 0 at the start of each calendar day so a baseline carried
    /// over from a previous day can't suppress today's celebration — the bug where
    /// the extra-mile screen "sometimes" didn't show. The getter returns 0 whenever
    /// the stored date isn't today; the setter always stamps today's date.
    var lastPostGoalWorkoutCount: Int {
        get {
            lastPostGoalDateString == formatDate(Date()) ? storedPostGoalWorkoutCount : 0
        }
        set {
            storedPostGoalWorkoutCount = newValue
            lastPostGoalDateString = formatDate(Date())
        }
    }

    private init() {
        // Migration for installs created before the per-day baseline date existed.
        // If the goal was already celebrated today under the old logic, adopt today's
        // date so the legacy `storedPostGoalWorkoutCount` keeps gating extra-mile
        // celebrations for the rest of today exactly as before — instead of the new
        // getter reading 0 and possibly firing a spurious Extra Mile without a new
        // workout. From the next calendar day on, the day-scoped reset takes over.
        if lastPostGoalDateString.isEmpty && hasShownGoalCelebrationToday {
            lastPostGoalDateString = formatDate(Date())
        }
    }
    
    /// Check if goal celebration has already been shown today
    var hasShownGoalCelebrationToday: Bool {
        let today = formatDate(Date())
        return lastGoalCelebrationDateString == today
    }
    
    /// Mark goal celebration as shown for today
    func markGoalCelebrationShown() {
        lastGoalCelebrationDateString = formatDate(Date())
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.calendar = Calendar.current
        formatter.timeZone = TimeZone.current
        return formatter.string(from: date)
    }

    /// Add a celebration to the queue
    func addCelebration(_ celebration: CelebrationType) {
        // Special handling for goal completion - only allow once per day
        if case .goalCompleted = celebration {
            guard !hasShownGoalCelebrationToday else {
                print("[CelebrationManager] ⏭️  Goal celebration already shown today (\(lastGoalCelebrationDateString)), skipping")
                return
            }
            print("[CelebrationManager] ✅ Goal celebration queued (last shown: \(lastGoalCelebrationDateString.isEmpty ? "never" : lastGoalCelebrationDateString), today: \(formatDate(Date())))")
            // Note: markGoalCelebrationShown() is called in showNextCelebration() when it's actually displayed,
            // not here, to prevent marking as "shown" while the app is in the background.
        }

        // One photo prompt per workout, ever — persisted so a relaunch can't
        // re-offer it for a mile already handled (the id is marked as shown in
        // showNextCelebration(), same as the goal celebration).
        if case .postRunPhotoPrompt(let workoutId, _) = celebration {
            guard !hasPromptedPhoto(for: workoutId) else {
                print("[CelebrationManager] ⏭️  Photo prompt already shown for workout \(workoutId), skipping")
                return
            }
            // ...and never for a walk that has ALREADY been posted through some
            // other door. "Prompted" and "posted" are different facts, and the
            // buddy recap is the door that made the difference visible: its
            // wizard publishes a real collab post, then this prompt — queued
            // behind the goal celebration, and sitting UNDER the recap sheet
            // the whole time — surfaced as the sheet dismissed and asked for a
            // photo of the walk that had just been posted with one.
            guard !PostedWorkoutRegistry.hasPost(for: workoutId) else {
                print("[CelebrationManager] ⏭️  Workout \(workoutId) is already posted, skipping photo prompt")
                return
            }
        }

        // Comeback day-3/7, record and streak-milestone moments fire once
        // per era/day, ever.
        switch celebration {
        case .comeback, .newRecordStreak, .streakMilestone:
            guard !hasShownComebackOrRecord(id: celebration.id) else {
                print("[CelebrationManager] ⏭️  \(celebration.id) already shown, skipping")
                return
            }
        default:
            break
        }

        // Avoid duplicates in queue
        guard !celebrationQueue.contains(where: { $0 == celebration }) else {
            print("[CelebrationManager] ⏭️  Celebration already in queue, skipping")
            return
        }
        guard currentCelebration != celebration else {
            print("[CelebrationManager] ⏭️  Celebration already showing, skipping")
            return
        }

        // The milestone screen carries its own medal, so the separate unlock
        // popup for the SAME streak medal would announce it twice.
        if case .streakMilestone(let info) = celebration {
            let medalId = "streak_\(info.days)"
            celebrationQueue.removeAll { queued in
                if case .badgeUnlocked(let badge) = queued { return badge.id == medalId }
                return false
            }
        }

        print("[CelebrationManager] 🎉 Adding celebration to queue: \(celebration.id)")
        celebrationQueue.append(celebration)
        // Stable by arrival within a priority — Swift's sort isn't, and two
        // equal-priority medals swapping places between enqueues reads as the
        // app not knowing its own order.
        celebrationQueue = celebrationQueue.enumerated()
            .sorted { a, b in
                let pa = priority(of: a.element), pb = priority(of: b.element)
                return pa != pb ? pa < pb : a.offset < b.offset
            }
            .map(\.element)

        // A photo prompt nobody has touched yet gives way to anything that
        // belongs before it. That's the "the flame showed up after the photo
        // prompt" report: the prompt was on screen first, and the queue's
        // order only ever applied to what was still waiting. Once they've
        // opened the camera or the library it's theirs and it stays.
        if let current = currentCelebration,
           case .postRunPhotoPrompt = current,
           !photoPromptEngaged,
           priority(of: celebration) < priority(of: current) {
            print("[CelebrationManager] ↩️ Photo prompt yields to \(celebration.id)")
            celebrationQueue.append(current)
            currentCelebration = nil
            isShowingCelebration = false
        }

        // Settle before showing: celebrations arrive in BURSTS (the flame,
        // the record, the leaderboard and the prompt in one pass; a medal
        // refresh a beat later), and showing the first arrival immediately is
        // how a low-priority item claimed the screen ahead of the headline.
        if !isShowingCelebration {
            scheduleShowNext(after: settleDelay)
        }
    }

    /// How long a burst gets to finish arriving before the first one shows.
    private let settleDelay: TimeInterval = 0.4

    private var pendingShowWork: DispatchWorkItem?

    private func scheduleShowNext(after delay: TimeInterval) {
        pendingShowWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.showNextCelebration() }
        pendingShowWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    // MARK: - When the screen isn't ours

    /// Something is covering the root overlay — the workout tracker's cover,
    /// the buddy recap sheet. A celebration "shown" under one plays to nobody
    /// and then sits there, out of order, the moment the cover goes away (a
    /// ghost win from the tracker landed before the flame that way). Keyed by
    /// reason so two covers can't release each other.
    @Published private(set) var obscuredBy: Set<String> = []

    func setObscured(_ reason: String, _ obscured: Bool) {
        if obscured {
            obscuredBy.insert(reason)
        } else if obscuredBy.remove(reason) != nil, obscuredBy.isEmpty, !isShowingCelebration {
            scheduleShowNext(after: settleDelay)
        }
    }

    /// The flame's sequence is being built (it awaits the streak and the
    /// era history first). Anything that arrives meanwhile — a medal from the
    /// same upload — must wait for it instead of opening the show. Bounded,
    /// so a hung fetch can never strand the queue.
    private var holdUntil: Date?

    func holdForGoalSequence(seconds: TimeInterval = 8) {
        holdUntil = Date().addingTimeInterval(seconds)
        scheduleShowNext(after: seconds + 0.05)
    }

    func releaseGoalHold() {
        guard holdUntil != nil else { return }
        holdUntil = nil
        if !isShowingCelebration { scheduleShowNext(after: settleDelay) }
    }

    private var isHeld: Bool {
        guard let until = holdUntil else { return false }
        if until <= Date() { holdUntil = nil; return false }
        return true
    }

    /// Set by the photo prompt the moment the user opens the camera, the
    /// library or a snap — after that it is never preempted.
    @Published var photoPromptEngaged = false

    /// Calm = nothing on screen, nothing waiting, nothing being built. What a
    /// surface that should come AFTER the celebrations (the buddy recap) waits
    /// for.
    var isCalm: Bool {
        !isShowingCelebration && celebrationQueue.isEmpty && !isHeld
    }

    /// Is a milestone moment for this streak length queued, on screen, or
    /// already seen? The medal refresh asks, so the milestone's own medal
    /// isn't announced a second time by a popup.
    func isCelebratingStreakMilestone(days: Int) -> Bool {
        let matches: (CelebrationType) -> Bool = {
            if case .streakMilestone(let info) = $0 { return info.days == days }
            if case .yearMilestone(let info) = $0 { return info.years * 365 == days }
            return false
        }
        if let current = currentCelebration, matches(current) { return true }
        if celebrationQueue.contains(where: matches) { return true }
        // Seen TODAY only: a medal that lands days after its milestone screen
        // played (a late sync) is news in its own right and gets its popup.
        let todayKey = "streak-milestone-\(days)-\(formatDate(Date()))"
        return comebackRecordShownKeysRaw.split(separator: "\n").contains { $0 == todayKey }
    }

    /// User-initiated replay. Skips the "already shown today" dedup gate so the
    /// user can re-watch (and re-share) the same celebration from anywhere in the app.
    /// Clears any pending queue first so the replay shows immediately.
    func replayCelebration(_ celebration: CelebrationType) {
        let dropped = celebrationQueue
        celebrationQueue.removeAll()
        currentCelebration = nil
        isShowingCelebration = false
        reportDroppedUnseen(dropped)

        print("[CelebrationManager] 🔁 Replay requested: \(celebration.id)")
        holdUntil = nil
        pendingShowWork?.cancel()
        // Straight onto the screen: a replay is the user asking for it right
        // now, so none of the automatic gates (settling, covers, the goal
        // hold) apply to it.
        currentCelebration = celebration
        isShowingCelebration = true
    }

    /// Replay several moments back to back, in the order given — the day's
    /// flame and then its milestone, exactly as they first played.
    func replaySequence(_ celebrations: [CelebrationType]) {
        guard let first = celebrations.first else { return }
        replayCelebration(first)
        celebrationQueue.append(contentsOf: celebrations.dropFirst())
    }

    /// Hosts that render celebrations somewhere other than the root overlay
    /// (a medal replay from a screen that may itself be a sheet, where the
    /// root overlay would play underneath it). While one is up the root
    /// container draws nothing, so nothing plays twice.
    @Published private(set) var detachedHostCount = 0

    func attachDetachedHost() { detachedHostCount += 1 }
    func detachDetachedHost() { detachedHostCount = max(0, detachedHostCount - 1) }

    /// Record a celebration's one-shot flags once the user has actually SEEN it
    /// (i.e. they dismissed it). Marking used to happen in showNextCelebration(),
    /// but "shown" there only meant "the overlay rendered somewhere" — when the
    /// container lived on a hidden tab (or behind a cover) the flame + photo
    /// prompt were consumed invisibly and could never fire again that day.
    /// Marking on dismissal means a moment the user never saw is never spent;
    /// worst case (force-quit mid-celebration) it simply replays next launch.
    private func markConsumed(_ celebration: CelebrationType?) {
        guard let celebration else { return }
        if case .goalCompleted = celebration {
            markGoalCelebrationShown()
        }
        if case .postRunPhotoPrompt(let workoutId, _) = celebration {
            markPromptedPhoto(for: workoutId)
        }
        if case .flameyUnlocked(let ids) = celebration {
            FlameyUnlockLedger.markAnnounced(Set(ids))
        }
        if case .postRunPhotoPrompt = celebration {
            photoPromptEngaged = false
        }
        switch celebration {
        case .comeback, .newRecordStreak, .streakMilestone:
            markComebackOrRecordShown(id: celebration.id)
        default:
            break
        }
    }

    /// A real post just landed for `workoutId` — retire its photo prompt,
    /// wherever that prompt currently is.
    ///
    /// The `addCelebration` guard alone is not enough, because the prompt is
    /// usually ALREADY in flight by the time a post is made. The goal-completion
    /// sequence enqueues it (priority 9, last) the moment the tracker cover
    /// dismisses, while the buddy recap that leads to the post is a `.sheet`
    /// presented over MainTabView — so the prompt sits fully rendered UNDERNEATH
    /// the recap, and is revealed the instant the sheet goes away. That is the
    /// "it asked for a photo after I'd already posted one" report: the prompt
    /// was never re-shown, it had been waiting there all along.
    ///
    /// Deliberately does NOT go through `reportDroppedUnseen`: that notification
    /// resets DashboardView's enqueue stamp so a cleared sequence can re-fire,
    /// and re-firing here would replay the flame and the leaderboard for a goal
    /// the user already celebrated.
    func resolvePhotoPrompt(forWorkout workoutId: String) {
        // Belt and braces with the registry: this survives even if the
        // persisted list is trimmed past this id later.
        markPromptedPhoto(for: workoutId)

        celebrationQueue.removeAll { queued in
            if case .postRunPhotoPrompt(let id, _) = queued { return id == workoutId }
            return false
        }

        if let current = currentCelebration,
           case .postRunPhotoPrompt(let id, _) = current, id == workoutId {
            dismissCurrentCelebration()
        }
    }

    /// Dismiss the current celebration and show the next one if available
    func dismissCurrentCelebration() {
        markConsumed(currentCelebration)
        isShowingCelebration = false
        currentCelebration = nil

        // Small delay before showing next celebration for better UX
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.showNextCelebration()
        }
    }

    /// Dismiss the current celebration with a specific action
    func dismissWithAction(_ action: CelebrationDismissAction) {
        markConsumed(currentCelebration)
        // Clear remaining queue when user wants to navigate away — but report
        // what was dropped, so still-unseen one-shots can re-arm.
        if action != .none {
            let dropped = celebrationQueue
            celebrationQueue.removeAll()
            reportDroppedUnseen(dropped)
        }

        isShowingCelebration = false
        currentCelebration = nil

        // Set the pending action after a brief delay for animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.pendingAction = action
        }
    }
    
    /// Clear the pending action (should be called after handling it)
    func clearPendingAction() {
        pendingAction = .none
    }

    /// Priority for ordering celebrations: lower = shown first.
    ///
    /// ONE running order, the same every day, told as a story: the day (the
    /// flame), what the day MEANT (a milestone, a record, a comeback), the
    /// walk itself (a ghost beaten, where you landed among friends, an extra
    /// mile), the rewards it unlocked (medals, then what Flamey can wear with
    /// them), the side quests (PRs, the daily challenge), and finally the
    /// photo of it — the one step that asks something of you, so it goes last.
    ///
    /// Exhaustive on purpose — a new celebration must be given a deliberate
    /// place in the running order, not silently land wherever a `default`
    /// happened to put it.
    private func priority(of celebration: CelebrationType) -> Int {
        switch celebration {
        case .badgeSummary: return -1 // one-time welcome for a new account
        case .goalCompleted: return 0
        // Directly after the flame: the flame counts the streak up to the
        // number, and this is the number getting its moment.
        case .yearMilestone: return 1
        case .streakMilestone: return 1
        case .newRecordStreak: return 2
        case .comeback: return 3
        case .ghostBeaten: return 4
        case .leaderboardMoveUp: return 5
        case .postGoalWorkout: return 6
        case .badgeUnlocked: return 7
        case .badgeBatch: return 7
        // Right after the medal popups that caused it: the medal is the news,
        // the thing Flamey can wear is the reward.
        case .flameyUnlocked: return 8
        case .milestone: return 9
        case .challengeCompleted: return 10
        case .postRunPhotoPrompt: return 11 // the very last step
        }
    }

    /// Show the next celebration in the queue (only when app is active/visible)
    private func showNextCelebration() {
        guard !isShowingCelebration else { return }
        guard !celebrationQueue.isEmpty else { return }
        guard appIsActive else {
            print("[CelebrationManager] ⏸️ App is not active, deferring celebration until foreground")
            return
        }
        guard obscuredBy.isEmpty else {
            print("[CelebrationManager] ⏸️ Covered by \(obscuredBy.sorted()), deferring")
            return
        }
        // While the flame's sequence is being built, only what belongs
        // before it (the one-time welcome) may go first.
        if isHeld, let first = celebrationQueue.first, priority(of: first) > priority(of: .goalCompleted(stats: .placeholder)) {
            print("[CelebrationManager] ⏸️ Holding for the goal sequence")
            // Never strand the queue: come back when the hold runs out, even
            // if nothing releases it.
            if let until = holdUntil {
                scheduleShowNext(after: max(0.05, until.timeIntervalSinceNow + 0.05))
            }
            return
        }

        let next = celebrationQueue.removeFirst()

        // One-shot flags (goal shown today / photo prompted for this workout)
        // are stamped in markConsumed() at DISMISSAL — not here. Displaying is
        // not seeing: an overlay on a hidden tab or behind a full-screen cover
        // "showed" without the user ever seeing it, permanently eating the
        // flame + photo prompt for that day/workout.
        currentCelebration = next
        isShowingCelebration = true
    }

    /// Called when the app returns to the foreground. Resumes showing any queued celebrations.
    func onAppBecameActive() {
        appIsActive = true
        if !isShowingCelebration {
            showNextCelebration()
        }
    }

    /// Called when the app goes to the background. Prevents new celebrations from being shown.
    func onAppResignedActive() {
        appIsActive = false
    }

    /// Clear all celebrations (useful for testing or reset)
    func clearAll() {
        holdUntil = nil
        celebrationQueue.removeAll()
        currentCelebration = nil
        isShowingCelebration = false
        pendingAction = .none
    }
    
    /// Reset daily tracking (for testing)
    func resetDailyTracking() {
        lastGoalCelebrationDateString = ""
        storedPostGoalWorkoutCount = 0
        lastPostGoalDateString = ""
    }
}
