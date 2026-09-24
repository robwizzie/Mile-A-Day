import Foundation
import WidgetKit

/// The durable facts Flamey's look is DERIVED from — longest streak, earned
/// badges, the day he met you — and the one place the app turns them into a
/// `FlameyLook`. Nothing about what he wears is stored: switching dashboard
/// style, reinstalling or signing in on a new phone can never take gear away,
/// because it comes back from the same facts.
///
/// Fun-only: `look(mood:)` returns nil on Modern, which is what every renderer
/// treats as "no wardrobe at all".
enum FlameyFacts {
    // MARK: Signup date

    /// "<userId>|<epoch seconds>" — keyed by account so a second account on
    /// this phone doesn't inherit the first one's anniversary.
    private static let signupKey = "flameySignupV1"

    static var signupDate: Date? {
        guard let raw = UserDefaults.standard.string(forKey: signupKey) else { return nil }
        let parts = raw.split(separator: "|")
        guard parts.count == 2, let epoch = Double(parts[1]) else { return nil }
        if let me = currentUserId, String(parts[0]) != me { return nil }
        return Date(timeIntervalSince1970: epoch)
    }

    private static var currentUserId: String? {
        UserDefaults.standard.string(forKey: "backendUserId")
    }

    /// Records `users.created_at` from any backend user payload. Timestamps
    /// arrive WITH fractional seconds, which `.iso8601` can't parse.
    static func recordSignup(createdAt: String?, userId: String?) {
        guard let createdAt, let userId, let date = parseTimestamp(createdAt) else { return }
        let value = "\(userId)|\(date.timeIntervalSince1970)"
        guard UserDefaults.standard.string(forKey: signupKey) != value else { return }
        UserDefaults.standard.set(value, forKey: signupKey)
    }

    static func parseTimestamp(_ raw: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: raw) { return date }
        return ISO8601DateFormatter().date(from: raw)
    }

    private static var signupFetchAttempted = false

    /// Fetches the signup date ONCE per launch when we don't have it (the
    /// profile refresh records it too, but only runs when Profile is opened).
    @MainActor
    static func ensureSignupDate() async {
        guard signupDate == nil, !signupFetchAttempted, TokenStore.hasTokens,
              let userId = currentUserId, !userId.isEmpty else { return }
        signupFetchAttempted = true
        struct Row: Decodable { let created_at: String? }
        guard let row = try? await APIClient.fancyFetch(endpoint: "/users/\(userId)", responseType: Row.self) else { return }
        recordSignup(createdAt: row.created_at, userId: userId)
        mirrorToWidget()
    }

    // MARK: Facts → look

    @MainActor
    static var earnedBadgeIds: Set<String> {
        Set(UserManager.shared.currentUser.badges.filter { !$0.isLocked }.map(\.id))
    }

    @MainActor
    static var longestStreak: Int {
        let user = UserManager.shared.currentUser
        return max(user.longestStreak ?? 0, user.streak)
    }

    /// What Flamey wears right now on a Fun surface, or nil on Modern (no
    /// Flamey feature exists there). `mood` adds its props (shades / party
    /// hat / nightcap) under the day's outfit.
    @MainActor
    static func look(mood: FlameMood.Kind? = nil, date: Date = Date()) -> FlameyLook? {
        guard DashboardStylePreference.current == .fun else { return nil }
        let props = mood.map { FlameMood(kind: $0, streak: 0).props } ?? []
        return FlameyLook.resolve(
            longestStreak: longestStreak,
            earnedBadgeIds: earnedBadgeIds,
            signupDate: signupDate,
            date: date,
            moodProps: props
        )
    }

    // MARK: Widget mirror

    /// Mirrors the facts the flame widget resolves his look from into the App
    /// Group (the widget can't see `UserDefaults.standard` or the user blob).
    /// Reloads the widget ONLY when that changes what he'd wear today or
    /// tomorrow — the rest is baked per entry by the widget itself, so a
    /// holiday rolls in at midnight with no reload spent.
    @MainActor
    static func mirrorToWidget() {
        let catalogBadges = Set(FlameyCosmetic.catalog.compactMap { cosmetic -> String? in
            if case .badge(let id) = cosmetic.unlock { return id }
            return nil
        })
        let badges = earnedBadgeIds.intersection(catalogBadges)
        let signup = signupDate
        let longest = longestStreak

        let calendar = Calendar.current
        let days = [Date(), calendar.date(byAdding: .day, value: 1, to: Date()) ?? Date()]
        let before = days.map {
            FlameyLook.resolve(longestStreak: WidgetDataStore.loadLongestStreak(),
                               earnedBadgeIds: WidgetDataStore.loadFlameyBadgeIds(),
                               signupDate: WidgetDataStore.loadFlameySignupDate(), date: $0)
        }
        let after = days.map {
            FlameyLook.resolve(longestStreak: longest, earnedBadgeIds: badges, signupDate: signup, date: $0)
        }
        WidgetDataStore.save(longestStreak: longest)
        WidgetDataStore.save(flameyBadgeIds: Array(badges), signupDate: signup, reload: before != after)
    }
}

/// Tells the server which dashboard style this user runs (`PATCH /users/:id`
/// `{dashboard_style}`) — additive, and entirely best-effort: an older server
/// ignores or 400s the field, and either answer is swallowed. Reported when
/// the style changes and once per launch; a failure is simply retried at the
/// next launch or change.
enum DashboardStyleReporter {
    private static let reportedKey = "dashboardStyleReportedV1"
    private static var attemptedThisLaunch: String?

    @MainActor
    static func report() {
        // `fancyFetch` SIGNS THE USER OUT when there is no token, so a
        // fire-and-forget caller must check first and simply defer.
        guard TokenStore.hasTokens,
              let userId = UserDefaults.standard.string(forKey: "backendUserId"), !userId.isEmpty else { return }
        let style = DashboardStylePreference.current.rawValue
        let stamp = "\(userId)|\(style)"
        guard attemptedThisLaunch != stamp else { return }
        attemptedThisLaunch = stamp
        guard let body = try? JSONSerialization.data(withJSONObject: ["dashboard_style": style]) else { return }
        Task {
            struct Ack: Decodable { let created_at: String? }
            do {
                let ack = try await APIClient.fancyFetch(
                    endpoint: "/users/\(userId)", method: .PATCH, body: body, responseType: Ack.self)
                UserDefaults.standard.set(stamp, forKey: reportedKey)
                FlameyFacts.recordSignup(createdAt: ack.created_at, userId: userId)
            } catch {
                // Silent: an older server may reject the unknown field.
            }
        }
    }
}
