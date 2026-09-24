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

    /// Every wardrobe item this user owns — from earned medals, plus the
    /// streak colours their longest streak implies (a gap-filler while the
    /// badge list loads; the server awards those medals from the same
    /// figure). Retroactive by construction.
    @MainActor
    static var ownedItems: Set<FlameyItem> {
        FlameyWardrobe.owned(earnedBadgeIds: earnedBadgeIds.union(FlameyWardrobe.impliedBadgeIds(longestStreak: longestStreak)))
    }

    // MARK: The Closet choice

    /// "<userId>" → the wire JSON (`{slot: id}`), keyed by account so a
    /// second account on this phone starts basic.
    private static let choiceKeyPrefix = "flameyLookChoiceV1|"

    /// What this user picked in the Closet. Absent = BASIC: he looks exactly
    /// as he did before the wardrobe existed until they pick something. A
    /// blob written by a build that had "auto" slots decodes with its picked
    /// items kept and every auto/none slot empty.
    @MainActor
    static var choice: FlameyLookChoice {
        guard let me = currentUserId,
              let data = UserDefaults.standard.data(forKey: choiceKeyPrefix + me),
              let decoded = try? JSONDecoder().decode(FlameyLookChoice.self, from: data) else { return .basic }
        return decoded
    }

    /// Stores the choice locally (the Closet PUTs it to the server itself —
    /// or hands the server's copy here via `applyServerChoice`) and mirrors
    /// it to the widget.
    @MainActor
    static func setChoice(_ choice: FlameyLookChoice) {
        guard let me = currentUserId else { return }
        if let data = try? JSONEncoder().encode(choice) {
            UserDefaults.standard.set(data, forKey: choiceKeyPrefix + me)
        }
        mirrorToWidget()
    }

    /// The server's copy (`GET /users/:id/flamey-closet` `look`) wins over
    /// the phone's — another device may have dressed him since.
    @MainActor
    static func applyServerChoice(_ choice: FlameyLookChoice) {
        guard choice != self.choice else { return }
        setChoice(choice)
    }

    /// What Flamey wears right now on a Fun surface, or nil on Modern (no
    /// Flamey feature exists there). `mood` adds its dressing (party hat /
    /// nightcap on the head, shades on bare eyes). `detail` is the SURFACE's
    /// size class: `.compact` for widgets, the friend card, the tracker and
    /// the Live Activity.
    @MainActor
    static func look(mood: FlameMood.Kind? = nil, date: Date = Date(),
                     detail: FlameyRenderDetail = .full) -> FlameyLook? {
        guard DashboardStylePreference.current == .fun else { return nil }
        let props = mood.map { FlameMood(kind: $0, streak: 0).props } ?? []
        return FlameyLook.resolve(
            owned: ownedItems,
            choice: choice,
            date: date,
            mood: props,
            signupDate: signupDate,
            detail: detail
        )
    }

    // MARK: Widget mirror

    /// Mirrors the facts the flame widget resolves his look from into the App
    /// Group (the widget can't see `UserDefaults.standard` or the user blob):
    /// the catalog's medals, the signup date and the Closet choice. Reloads
    /// the widget ONLY when that changes what he'd wear today or tomorrow —
    /// the rest is baked per entry by the widget itself, so a holiday rolls
    /// in at midnight with no reload spent.
    @MainActor
    static func mirrorToWidget() {
        let badges = earnedBadgeIds.intersection(FlameyWardrobe.catalogBadgeIds)
            .union(FlameyWardrobe.impliedBadgeIds(longestStreak: longestStreak))
        let signup = signupDate
        let longest = longestStreak
        let choice = self.choice

        let calendar = Calendar.current
        let days = [Date(), calendar.date(byAdding: .day, value: 1, to: Date()) ?? Date()]
        let before = days.map {
            FlameyLook.resolve(owned: WidgetDataStore.loadFlameyOwnedItems(),
                               choice: WidgetDataStore.loadFlameyChoice(),
                               date: $0, signupDate: WidgetDataStore.loadFlameySignupDate(), detail: .compact)
        }
        let after = days.map {
            FlameyLook.resolve(owned: FlameyWardrobe.owned(earnedBadgeIds: badges), choice: choice,
                               date: $0, signupDate: signup, detail: .compact)
        }
        WidgetDataStore.save(longestStreak: longest)
        WidgetDataStore.save(flameyChoice: choice)
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
