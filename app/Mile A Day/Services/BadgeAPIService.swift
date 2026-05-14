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
        let isHidden: Bool
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
        let isHidden: Bool
        let earnedAt: Date
        let isNew: Bool
        let pinSlot: Int?
        let triggeringWorkoutId: String?
    }

    private struct CatalogResponse: Codable { let badges: [CatalogBadgeDTO] }
    private struct UserBadgesResponse: Codable { let userId: String; let badges: [UserBadgeDTO] }
    private struct MarkViewedResponse: Codable { let updated: Int }
    private struct SetPinsRequest: Codable { let pinnedBadgeIds: [String] }

    // MARK: - API

    /// Public endpoint — no auth required, but APIClient still attaches Bearer since this endpoint
    /// also works authenticated. Returns catalog minus hidden badges.
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
            isHidden: isHidden,
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
            isLocked: true,
            isHidden: isHidden
        )
    }
}
