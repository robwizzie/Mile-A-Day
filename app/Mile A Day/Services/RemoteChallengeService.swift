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

    private(set) var todayChallenge: DailyChallenge?
    private(set) var todayProgress: Double = 0
    private(set) var todayCompleted: Bool = false
    private(set) var todayLocalDate: String?
    private(set) var tomorrowChallenge: DailyChallenge?
    private(set) var tomorrowLocalDate: String?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.todayChallenge = nil
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
    func refreshToday(userId: String) async {
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
                self.saveTodaySnapshot(response: response)
                NotificationCenter.default.post(name: ChallengeService.changedNotification, object: nil)
            }
        } catch {
            print("[RemoteChallengeService] refreshToday failed: \(error)")
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
                    description: ""
                )
            }
            await MainActor.run {
                self.save(completions)
                NotificationCenter.default.post(name: ChallengeService.changedNotification, object: nil)
            }
        } catch {
            print("[RemoteChallengeService] refreshCompletions failed: \(error)")
        }
    }

    /// Completion status for a friend's today-challenge (friend profile view).
    static func fetchFriendToday(userId: String) async throws -> FriendTodayDTO {
        try await APIClient.fancyFetch(
            endpoint: "/users/\(userId)/challenges/today",
            responseType: FriendTodayDTO.self
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

    private func saveTodaySnapshot(response: TodayResponseDTO) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(response) {
            defaults.set(data, forKey: todayKey)
        }
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
            default: return .distance
            }
        }
    }

    struct TodayResponseDTO: Codable {
        let localDate: String
        let challenge: ChallengeDTO
        let progress: Double
        let completed: Bool
        let completedAt: Date?
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

    struct FriendTodayDTO: Codable {
        let userId: String
        let localDate: String
        let completed: Bool
        let challengeKey: String?
    }
}
