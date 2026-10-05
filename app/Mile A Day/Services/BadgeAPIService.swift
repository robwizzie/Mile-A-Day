import Foundation

/// Network client for the server-authoritative badge system.
///
/// All badge evaluation lives on the backend; this client just reads the user's earned
/// badges + the full catalog so the UI can render grids and "locked" states.
enum BadgeAPIService {
    // MARK: - DTOs (match backend src/types/badge.ts)

    struct CatalogBadgeDTO: Codable {
        let badgeId: String
        let category: String
        let name: String
        let description: String
        let icon: String
        let rarity: String
        let requirement: Double?
        let sortOrder: Int
    }

    struct UserBadgeDTO: Codable {
        let badgeId: String
        let category: String
        let name: String
        let description: String
        let icon: String
        let rarity: String
        let requirement: Double?
        let earnedAt: Date
        let isNew: Bool
        let pinSlot: Int?
        let triggeringWorkoutId: String?
        /// HOW it was earned (additive; absent on older servers). Decoded
        /// LENIENTLY under either casing, so a malformed detail can never
        /// fail the whole badge list.
        let earned_detail: EarnedDetailDTO?
        let earnedDetail: EarnedDetailDTO?

        var detail: EarnedDetailDTO? { earned_detail ?? earnedDetail }
    }

    /// `earned_detail: {summary, date, value, unit, workout_id}` — every
    /// field optional, and a wrong-typed one is simply nil.
    struct EarnedDetailDTO: Codable, Equatable {
        var summary: String?
        /// "YYYY-MM-DD", the user's calendar day.
        var date: String?
        var value: Double?
        var unit: String?
        var workoutId: String?

        private enum Keys: String, CodingKey {
            case summary, date, value, unit
            case workout_id, workoutId
        }

        init(summary: String? = nil, date: String? = nil, value: Double? = nil, unit: String? = nil,
             workoutId: String? = nil) {
            self.summary = summary
            self.date = date
            self.value = value
            self.unit = unit
            self.workoutId = workoutId
        }

        init(from decoder: Decoder) throws {
            guard let c = try? decoder.container(keyedBy: Keys.self) else { return }
            summary = try? c.decodeIfPresent(String.self, forKey: .summary)
            date = try? c.decodeIfPresent(String.self, forKey: .date)
            value = try? c.decodeIfPresent(Double.self, forKey: .value)
            unit = try? c.decodeIfPresent(String.self, forKey: .unit)
            workoutId = (try? c.decodeIfPresent(String.self, forKey: .workout_id))
                ?? (try? c.decodeIfPresent(String.self, forKey: .workoutId))
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: Keys.self)
            try c.encodeIfPresent(summary, forKey: .summary)
            try c.encodeIfPresent(date, forKey: .date)
            try c.encodeIfPresent(value, forKey: .value)
            try c.encodeIfPresent(unit, forKey: .unit)
            try c.encodeIfPresent(workoutId, forKey: .workout_id)
        }
    }

    private struct CatalogResponse: Codable { let badges: [CatalogBadgeDTO] }
    private struct UserBadgesResponse: Codable { let userId: String; let badges: [UserBadgeDTO] }
    private struct MarkViewedResponse: Codable { let updated: Int }
    private struct SetPinsRequest: Codable { let pinnedBadgeIds: [String] }

    // MARK: - API

    /// Public endpoint — no auth required, but APIClient still attaches Bearer since this endpoint
    /// also works authenticated.
    static func fetchCatalog() async throws -> [CatalogBadgeDTO] {
        let response: CatalogResponse = try await APIClient.fancyFetch(
            endpoint: "/badges/catalog",
            responseType: CatalogResponse.self
        )
        return response.badges
    }

    static func fetchUserBadges(userId: String) async throws -> [UserBadgeDTO] {
        let response: UserBadgesResponse = try await APIClient.fancyFetch(
            endpoint: "/users/\(userId)/badges",
            responseType: UserBadgesResponse.self
        )
        // Your own medals: remember HOW each was earned, for the medal detail
        // and Flamey's Closet (the `Badge` blob is persisted and stays as is).
        if userId == UserDefaults.standard.string(forKey: "backendUserId") {
            BadgeEarnedDetails.record(response.badges, userId: userId)
        }
        return response.badges
    }

    @discardableResult
    static func markViewed(userId: String) async throws -> Int {
        let response: MarkViewedResponse = try await APIClient.fancyFetch(
            endpoint: "/users/\(userId)/badges/mark-viewed",
            method: .POST,
            responseType: MarkViewedResponse.self
        )
        return response.updated
    }

    /// Replace the user's pinned badges. Order in `badgeIds` becomes pin slot 0..2.
    static func setPinnedBadges(userId: String, badgeIds: [String]) async throws -> [UserBadgeDTO] {
        let bodyData = try JSONEncoder().encode(SetPinsRequest(pinnedBadgeIds: badgeIds))
        let response: UserBadgesResponse = try await APIClient.fancyFetch(
            endpoint: "/users/\(userId)/badges/pins",
            method: .PUT,
            body: bodyData,
            responseType: UserBadgesResponse.self
        )
        return response.badges
    }
}

// MARK: - How each medal was earned

/// HOW this account earned each medal, by badge id: the server's
/// `earned_detail` (summary, day, workout), falling back to the long-standing
/// `triggeringWorkoutId` for the workout. Kept beside — never inside — the
/// persisted `Badge` blob, per account, so an older server (no detail) or a
/// decode hiccup simply means the medal's requirement is shown instead.
enum BadgeEarnedDetails {
    struct Entry: Codable, Equatable {
        var summary: String?
        var date: String?
        var workoutId: String?
    }

    private static let prefix = "badgeEarnedDetailsV1|"

    static func record(_ badges: [BadgeAPIService.UserBadgeDTO], userId: String) {
        var out: [String: Entry] = [:]
        for badge in badges {
            let detail = badge.detail
            let workout = detail?.workoutId ?? badge.triggeringWorkoutId
            let summary = detail?.summary?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard (summary?.isEmpty == false) || workout != nil || detail?.date != nil else { continue }
            out[badge.badgeId] = Entry(summary: summary?.isEmpty == false ? summary : nil,
                                       date: detail?.date, workoutId: workout)
        }
        guard let data = try? JSONEncoder().encode(out) else { return }
        UserDefaults.standard.set(data, forKey: prefix + userId)
    }

    /// This account's details (empty before the first fetch).
    static func all() -> [String: Entry] {
        guard let me = UserDefaults.standard.string(forKey: "backendUserId"), !me.isEmpty,
              let data = UserDefaults.standard.data(forKey: prefix + me),
              let decoded = try? JSONDecoder().decode([String: Entry].self, from: data) else { return [:] }
        return decoded
    }

    static func entry(for badgeId: String) -> Entry? { all()[badgeId] }
}

// MARK: - DTO → client-model conversion

extension BadgeAPIService.UserBadgeDTO {
    /// Convert to the existing `Badge` struct used across the iOS UI.
    func toBadge() -> Badge {
        Badge(
            id: badgeId,
            name: name,
            description: description,
            dateAwarded: earnedAt,
            isNew: isNew,
            isLocked: false,
            pinSlot: pinSlot
        )
    }
}

extension BadgeAPIService.CatalogBadgeDTO {
    /// Convert to a locked-state `Badge` for the grid.
    func toLockedBadge() -> Badge {
        Badge(
            id: badgeId,
            name: name,
            description: description,
            dateAwarded: Date.distantFuture,
            isNew: false,
            isLocked: true
        )
    }
}
