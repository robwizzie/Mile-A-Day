import Foundation
import SwiftUI

/// Server-authoritative implementation of `ChallengeServiceProtocol` backed by the
/// backend `/users/:userId/challenges/*` endpoints.
///
/// State is mirrored in memory + UserDefaults so the sync methods of the protocol
/// (`allCompletions`, `completion(on:)`, `currentChallengeStreak`) stay drop-in replacements
/// for existing callers. Async `refresh*` methods pull fresh server state and post
/// `ChallengeService.changedNotification` on update.
final class RemoteChallengeService: ChallengeServiceProtocol {

    // MARK: - Cache storage

    private let defaults: UserDefaults
    private let completionsKey = "remoteChallengeCompletionsV1"
    private let todayKey = "remoteChallengeTodayV1"
    /// Backend user the `todayKey` snapshot belongs to — restoring another
    /// account's challenge state on a shared install must never happen.
    private let todayUserKey = "remoteChallengeTodayUserV1"
    private let matchupsKey = "remoteChallengeMatchupsV1"
    /// Same shared-install guard as `todayUserKey`, for the matchup snapshot.
    private let matchupsUserKey = "remoteChallengeMatchupsUserV1"

    private(set) var todayChallenge: DailyChallenge?
    private(set) var todayProgress: Double = 0
    private(set) var todayCompleted: Bool = false
    private(set) var todayLocalDate: String?
    private(set) var tomorrowChallenge: DailyChallenge?
    private(set) var tomorrowLocalDate: String?
    /// Today's Head-to-Head rival, if the challenge is `head_to_head`.
    private(set) var todayOpponent: ChallengeOpponent?
    /// Past Head-to-Head duels + all-time records. Unlike the today snapshot
    /// this has no date gate — yesterday's history is still true today.
    private(set) var matchupHistory: MatchupHistoryDTO?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Restore the last server snapshot so the dashboard has a challenge to show
        // immediately (and offline) instead of a loading placeholder until the
        // network round-trip completes.
        loadTodaySnapshot()
        loadMatchupsSnapshot()
    }

    // MARK: - ChallengeServiceProtocol (sync)

    func recordCompletion(_ completion: ChallengeCompletion) {
        var completions = allCompletions()
        if completions.contains(where: { Calendar.current.isDate($0.date, inSameDayAs: completion.date) }) {
            return
        }
        completions.append(completion)
        save(completions)
        NotificationCenter.default.post(name: ChallengeService.changedNotification, object: nil)
    }

    func allCompletions() -> [ChallengeCompletion] {
        guard let data = defaults.data(forKey: completionsKey) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([ChallengeCompletion].self, from: data)) ?? []
    }

    func completion(on date: Date) -> ChallengeCompletion? {
        let target = Calendar.current.startOfDay(for: date)
        return allCompletions().first { Calendar.current.isDate($0.date, inSameDayAs: target) }
    }

    func currentChallengeStreak() -> Int {
        let completions = allCompletions()
        guard !completions.isEmpty else { return 0 }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let days = Set(completions.map { calendar.startOfDay(for: $0.date) })
        var cursor: Date
        if days.contains(today) {
            cursor = today
        } else if let yesterday = calendar.date(byAdding: .day, value: -1, to: today), days.contains(yesterday) {
            cursor = yesterday
        } else {
            return 0
        }
        var streak = 0
        while days.contains(cursor) {
            streak += 1
            guard let prev = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = prev
        }
        return streak
    }

    // MARK: - Async refreshers

    /// Fetch today's challenge + progress + completion status for the given user.
    /// Transient failures (timeouts, flaky connections) are retried twice with
    /// backoff so a single dropped request doesn't strand the dashboard card.
    func refreshToday(userId: String, attempt: Int = 0) async {
        do {
            let response: TodayResponseDTO = try await APIClient.fancyFetch(
                endpoint: "/users/\(userId)/challenges/today",
                responseType: TodayResponseDTO.self
            )
            let challenge = response.challenge.toDailyChallenge()
            let tomorrow = response.tomorrowChallenge?.toDailyChallenge()
            await MainActor.run {
                self.todayChallenge = challenge
                self.todayProgress = response.progress
                self.todayCompleted = response.completed
                self.todayLocalDate = response.localDate
                self.tomorrowChallenge = tomorrow
                self.tomorrowLocalDate = response.tomorrowLocalDate
                self.todayOpponent = response.opponent?.toOpponent()
                self.saveTodaySnapshot(response: response, userId: userId)
                NotificationCenter.default.post(name: ChallengeService.changedNotification, object: nil)
            }
        } catch is CancellationError {
            // Hosting task was cancelled (view disappeared / userId changed) —
            // an obsolete request must not retry and overwrite fresher state.
        } catch {
            if (error as? URLError)?.code == .cancelled { return }
            print("[RemoteChallengeService] refreshToday failed (attempt \(attempt + 1)): \(error)")
            if attempt < 2 {
                // A throwing sleep means we were cancelled during backoff — bail.
                guard (try? await Task.sleep(nanoseconds: UInt64(attempt + 1) * 2_000_000_000)) != nil,
                      !Task.isCancelled else { return }
                await refreshToday(userId: userId, attempt: attempt + 1)
            }
        }
    }

    /// Fetch the full completion history from the server and replace the local cache.
    func refreshCompletions(userId: String) async {
        do {
            let response: CompletionsResponseDTO = try await APIClient.fancyFetch(
                endpoint: "/users/\(userId)/challenges",
                responseType: CompletionsResponseDTO.self
            )
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withFullDate]
            let completions: [ChallengeCompletion] = response.completions.compactMap { item in
                guard let date = iso.date(from: item.localDate) ?? Self.parseYmd(item.localDate) else { return nil }
                return ChallengeCompletion(
                    date: date,
                    challengeKey: item.challengeKey,
                    title: item.title,
                    icon: item.icon,
                    description: "",
                    localDate: item.localDate
                )
            }
            await MainActor.run {
                self.save(completions)
                NotificationCenter.default.post(name: ChallengeService.changedNotification, object: nil)
            }
        } catch is CancellationError {
            // Hosting task was cancelled (view disappeared / userId changed).
        } catch {
            // Same guard refreshToday uses: a cancelled URL task is not a
            // failure, and logging it as one filled the console with
            // NSURLErrorCancelled -999 blocks that read like a bug.
            if (error as? URLError)?.code == .cancelled { return }
            print("[RemoteChallengeService] refreshCompletions failed: \(error)")
        }
    }

    /// Fetch the Head-to-Head duel history (past matchups + all-time records).
    func refreshMatchups(userId: String) async {
        do {
            let response: MatchupHistoryDTO = try await APIClient.fancyFetch(
                endpoint: "/users/\(userId)/challenges/matchups",
                responseType: MatchupHistoryDTO.self
            )
            await MainActor.run {
                self.matchupHistory = response
                self.saveMatchupsSnapshot(response: response, userId: userId)
                NotificationCenter.default.post(name: ChallengeService.changedNotification, object: nil)
            }
        } catch is CancellationError {
            // Hosting task was cancelled (view disappeared / userId changed).
        } catch {
            if (error as? URLError)?.code == .cancelled { return }
            print("[RemoteChallengeService] refreshMatchups failed: \(error)")
        }
    }

    /// Completion status for a friend's today-challenge (friend profile view).
    static func fetchFriendToday(userId: String) async throws -> FriendTodayDTO {
        try await APIClient.fancyFetch(
            endpoint: "/users/\(userId)/challenges/today",
            responseType: FriendTodayDTO.self
        )
    }

    /// How a past completion was earned (duel scores, the shared photo, hyped
    /// friends, pace/steps numbers). Fetched lazily when a completion sheet
    /// opens; the sheet degrades to its generic layout when this fails.
    static func fetchCompletionDetail(userId: String, localDate: String) async throws -> CompletionDetailDTO {
        try await APIClient.fancyFetch(
            endpoint: "/users/\(userId)/challenges/\(localDate)/detail",
            responseType: CompletionDetailDTO.self
        )
    }

    // MARK: - Cache helpers

    private func save(_ completions: [ChallengeCompletion]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(completions) {
            defaults.set(data, forKey: completionsKey)
        }
    }

    private func saveTodaySnapshot(response: TodayResponseDTO, userId: String) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(response) {
            defaults.set(data, forKey: todayKey)
            defaults.set(userId, forKey: todayUserKey)
        }
    }

    /// Restore the last `/challenges/today` response, but only if it's still for
    /// today's local date — yesterday's challenge must never masquerade as
    /// today's — AND it belongs to the currently signed-in backend user, so a
    /// second account on the same install never sees the previous account's
    /// challenge progress.
    private func loadTodaySnapshot() {
        guard let data = defaults.data(forKey: todayKey) else { return }
        guard let snapshotUser = defaults.string(forKey: todayUserKey),
              let currentUser = defaults.string(forKey: "backendUserId"),
              snapshotUser == currentUser else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let response = try? decoder.decode(TodayResponseDTO.self, from: data),
              response.localDate == Self.currentLocalDateString() else { return }
        todayChallenge = response.challenge.toDailyChallenge()
        todayProgress = response.progress
        todayCompleted = response.completed
        todayLocalDate = response.localDate
        tomorrowChallenge = response.tomorrowChallenge?.toDailyChallenge()
        tomorrowLocalDate = response.tomorrowLocalDate
        todayOpponent = response.opponent?.toOpponent()
    }

    private func saveMatchupsSnapshot(response: MatchupHistoryDTO, userId: String) {
        if let data = try? JSONEncoder().encode(response) {
            defaults.set(data, forKey: matchupsKey)
            defaults.set(userId, forKey: matchupsUserKey)
        }
    }

    /// Restore the last matchup-history response for the signed-in user so the
    /// record card renders instantly (and offline). History only grows, so a
    /// stale snapshot is merely incomplete, never wrong-day like `todayKey`.
    private func loadMatchupsSnapshot() {
        guard let data = defaults.data(forKey: matchupsKey) else { return }
        guard let snapshotUser = defaults.string(forKey: matchupsUserKey),
              let currentUser = defaults.string(forKey: "backendUserId"),
              snapshotUser == currentUser else { return }
        matchupHistory = try? JSONDecoder().decode(MatchupHistoryDTO.self, from: data)
    }

    private static func currentLocalDateString() -> String {
        let fmt = DateFormatter()
        fmt.calendar = Calendar(identifier: .gregorian)
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: Date())
    }

    private static func parseYmd(_ s: String) -> Date? {
        let fmt = DateFormatter()
        fmt.calendar = Calendar(identifier: .gregorian)
        fmt.timeZone = TimeZone(secondsFromGMT: 0)
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.date(from: s)
    }

    // MARK: - DTOs

    struct ChallengeDTO: Codable {
        let key: String
        let title: String
        let description: String
        let icon: String
        let gradientStart: String
        let gradientEnd: String
        let type: String

        func toDailyChallenge() -> DailyChallenge {
            DailyChallenge(
                key: key,
                title: title,
                description: description,
                icon: icon,
                gradient: [Color(hex: gradientStart), Color(hex: gradientEnd)],
                type: Self.parseType(type)
            )
        }

        private static func parseType(_ s: String) -> DailyChallenge.ChallengeType {
            switch s {
            case "pace": return .pace
            case "distance": return .distance
            case "time": return .time
            case "activity": return .activity
            case "steps": return .steps
            case "social": return .social
            default: return .distance
            }
        }
    }

    /// Head-to-Head rival payload (present only when today's challenge is `head_to_head`).
    struct OpponentDTO: Codable {
        let userId: String
        let username: String?
        let profileImageUrl: String?
        let miles: Double
        let myMiles: Double
        // Optional: older server builds don't send it.
        let mutual: Bool?
        /// Others who pinned the viewer as THEIR rival today. Optional for the
        /// same reason — a server that predates it simply sends no list, and
        /// the strip doesn't render.
        let challengers: [ChallengerDTO]?

        func toOpponent() -> ChallengeOpponent {
            ChallengeOpponent(
                userId: userId,
                username: username,
                profileImageUrl: profileImageUrl,
                miles: miles,
                myMiles: myMiles,
                mutual: mutual ?? false,
                challengers: (challengers ?? []).map {
                    ChallengeChallenger(
                        userId: $0.userId,
                        username: $0.username,
                        profileImageUrl: $0.profileImageUrl,
                        miles: $0.miles
                    )
                }
            )
        }
    }

    /// One of the people racing the viewer today without being their matchup.
    struct ChallengerDTO: Codable {
        let userId: String
        let username: String?
        let profileImageUrl: String?
        let miles: Double
    }

    struct TodayResponseDTO: Codable {
        let localDate: String
        let challenge: ChallengeDTO
        let progress: Double
        let completed: Bool
        let completedAt: Date?
        // Present only for the Head-to-Head challenge; nil otherwise.
        let opponent: OpponentDTO?
        // Older server builds may not return tomorrow yet; keep optional for backward compat.
        let tomorrowChallenge: ChallengeDTO?
        let tomorrowLocalDate: String?
    }

    struct CompletionItemDTO: Codable {
        let localDate: String
        let challengeKey: String
        let title: String
        let icon: String
        let completingWorkoutId: String?
        let completedAt: Date
    }

    struct CompletionsResponseDTO: Codable {
        let totalCompleted: Int
        let currentStreak: Int
        let completions: [CompletionItemDTO]
    }

    // MARK: Matchup history (past Head-to-Head duels)

    struct MatchupRivalDTO: Codable, Equatable {
        let userId: String
        let username: String?
        let profileImageUrl: String?

        var displayName: String { username ?? "A friend" }
    }

    /// One finished duel. `result` is the race (who logged more miles);
    /// `completed` is whether the day's challenge was actually awarded
    /// (winning also required hitting your own goal).
    struct MatchupItemDTO: Codable, Equatable, Identifiable {
        let localDate: String
        let rival: MatchupRivalDTO
        let myMiles: Double
        let rivalMiles: Double
        let result: String   // "won" | "lost" | "tied"
        let mutual: Bool
        let completed: Bool

        var id: String { localDate }
        var won: Bool { result == "won" }
        var tied: Bool { result == "tied" }
    }

    /// All-time record against one rival.
    struct MatchupRivalRecordDTO: Codable, Equatable, Identifiable {
        let userId: String
        let username: String?
        let profileImageUrl: String?
        let wins: Int
        let losses: Int
        let ties: Int
        let lastLocalDate: String

        var id: String { userId }
        var displayName: String { username ?? "A friend" }
        var total: Int { wins + losses + ties }
    }

    struct MatchupRecordDTO: Codable, Equatable {
        let wins: Int
        let losses: Int
        let ties: Int
        let total: Int
    }

    struct MatchupHistoryDTO: Codable, Equatable {
        let record: MatchupRecordDTO
        let currentWinStreak: Int
        let bestWinStreak: Int
        let rivals: [MatchupRivalRecordDTO]
        let matchups: [MatchupItemDTO]
        /// TRUE when the server capped the window (aggregates aren't all-time).
        /// Optional: a server predating the field simply doesn't send it.
        let truncated: Bool?
    }

    struct FriendTodayDTO: Codable {
        let userId: String
        let localDate: String
        let completed: Bool
        let challengeKey: String?
        // Enriched by the server so a friend's profile renders the right challenge
        // without relying on a hardcoded client catalog. Optional for back-compat
        // with older server builds.
        let challengeTitle: String?
        let challengeIcon: String?
        let gradientStart: String?
        let gradientEnd: String?
        let opponent: OpponentDTO?
    }

    // MARK: Completion detail (how a past challenge was completed)

    /// Minimal user reference inside a completion detail.
    struct CompletionFriendDTO: Codable {
        let userId: String
        let username: String?
        let profileImageUrl: String?

        var displayName: String { username ?? "A friend" }
    }

    struct CompletionH2hRecordDTO: Codable {
        let wins: Int
        let losses: Int
        let ties: Int
    }

    /// The finished duel behind a head_to_head completion.
    struct CompletionH2hDTO: Codable {
        let rival: CompletionFriendDTO
        let myMiles: Double
        let rivalMiles: Double
        let result: String   // "won" | "lost" | "tied"
        let mutual: Bool
        /// All-time resolved-duel record against this rival.
        let record: CompletionH2hRecordDTO
    }

    /// The photo post behind a share_journey completion (`mediaUrl` is signed).
    struct CompletionPostDTO: Codable {
        let postId: String
        let mediaUrl: String
        let caption: String?
        // Backend timestamptz carries fractional seconds the shared .iso8601
        // decoder can't parse — keep it a String and parse via BuddyDate.
        let createdAt: String?
    }

    /// Who was hyped (hype_squad) or nudged (wingman) that day.
    struct CompletionSocialDTO: Codable {
        let friends: [CompletionFriendDTO]
        /// Total hypes/nudges sent; can exceed `friends.count` (repeats, cap).
        let totalActions: Int
    }

    struct CompletionStepsDTO: Codable {
        let steps: Int
        let goalSteps: Int
    }

    struct CompletionPaceDTO: Codable {
        let bestPaceSecondsPerMile: Double?
        let targetPaceSecondsPerMile: Double?
    }

    struct CompletionDistanceDTO: Codable {
        let miles: Double
        let targetMiles: Double
        /// "walking" when only walk miles counted (walk_it_out); else "all".
        let scope: String?
    }

    struct CompletionTimeWindowDTO: Codable {
        let window: String   // "early" | "late"
        /// Wall-clock finish in the workout's own timezone, "HH:MM" 24h.
        let finishedLocalTime: String?
        let qualifyingMiles: Double?
    }

    struct CompletionActivityDTO: Codable {
        let workoutCount: Int
        let runMiles: Double
        let walkMiles: Double
        let variant: String?   // cross_train only: "walk_today" | "run_today" | "mixed"
    }

    /// `GET /users/:id/challenges/:localDate/detail` — at most one section is
    /// populated, matching the challenge family. Sections re-derive from live
    /// rows server-side, so any of them can be nil (deleted post, blocked
    /// rival) even for a real completion.
    struct CompletionDetailDTO: Codable {
        let localDate: String
        let challengeKey: String
        let title: String
        let description: String?
        let icon: String
        let gradientStart: String?
        let gradientEnd: String?
        // String for the same fractional-seconds reason as CompletionPostDTO.
        let completedAt: String?
        let h2h: CompletionH2hDTO?
        let post: CompletionPostDTO?
        let social: CompletionSocialDTO?
        let steps: CompletionStepsDTO?
        let pace: CompletionPaceDTO?
        let distance: CompletionDistanceDTO?
        let timeWindow: CompletionTimeWindowDTO?
        let activity: CompletionActivityDTO?
        let friend: CompletionFriendDTO?
    }
}
