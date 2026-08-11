import Foundation

// MARK: - Models (mirror the backend's gated streak_features payload)

/// One token's earn meter. Meters are server-derived; the client only renders.
struct StreakTokenMeter: Codable {
    let progress: Double
    let target: Double
    let held: Bool
    let last_used: String?

    /// 0…1 for progress rings.
    var fraction: Double {
        guard target > 0 else { return 0 }
        return min(max(progress / target, 0), 1)
    }

    /// Caption for the Streak Assist meter, which counts DAYS since the last
    /// one was spent rather than miles run. One helper because four surfaces
    /// (the token card and all three goal celebrations) print it, and they had
    /// already drifted into four copies of the same format string.
    var assistCaption: String {
        if held { return "Ready" }
        let daysLeft = Int(max(0, (target - progress).rounded(.up)))
        return daysLeft == 1 ? "1 day to go" : "\(daysLeft) days to go"
    }
}

/// A day the server says still counts (token-covered), with which token did it
/// and — for an assist — who. Optional/Equatable/Hashable because every
/// per-day surface indexes these (see SavedDayStyle); `source_username` is
/// absent on older servers and for non-assist kinds.
struct CoveredDate: Codable, Equatable, Hashable {
    let local_date: String
    let kind: String
    let source_username: String?
}

/// The gated `streak_features` object on getUserStats. Absent entirely until
/// the backend enables the feature for this user.
struct StreakFeaturesPayload: Codable {
    struct DoubleDownMeter: Codable {
        let progress: Double
        let target: Double
        let held: Bool
        let last_used: String?
        /// Today's total needed to complete a Double Down (2× goal − 0.05).
        let recover_miles: Double?

        var fraction: Double {
            guard target > 0 else { return 0 }
            return min(max(progress / target, 0), 1)
        }
    }

    let double_down: DoubleDownMeter
    let streak_save: StreakTokenMeter
    let streak_assist: StreakTokenMeter
    let frozen_dates: [CoveredDate]
    let natural_streak: Bool
    let streak_at_risk: Bool
    /// The user's OWN day a friend's donated mile could cover — only sent when
    /// they're holding the token that pays for it. This is the trigger for
    /// "ask a friend"; nothing else on the payload can tell whether one
    /// covered day would actually reconnect the streak.
    let my_savable_day: SavableDay?
}

/// A day an Assist could cover, and where the streak lands if it does.
struct SavableDay: Codable, Equatable {
    let local_date: String
    /// "missed" — already lost; "today" — still winnable by going for a run.
    let kind: String
    let restored_streak: Int

    var isToday: Bool { kind == "today" }
}

/// How many friends the user can cover today. One whole mile past your own
/// goal buys one — two friends means two miles past, and so on.
struct DonationBudget: Codable, Equatable {
    let goal_miles: Double
    let today_miles: Double
    let allowed: Int
    let used: Int
    let remaining: Int

    /// Miles still to run before the NEXT donation unlocks.
    var milesToNext: Double {
        max(0, goal_miles + Double(used + 1) - today_miles)
    }
}

/// An exchange waiting on this user's answer.
struct PendingAssistOffer: Codable, Identifiable, Equatable {
    let offer_id: String
    /// "donor" — they offered you a mile, you spend your token.
    /// "recipient" — they asked YOU for a mile.
    let initiator: String
    let user_id: String
    let username: String?
    let first_name: String?
    let profile_image_url: String?
    let target_date: String
    let restored_streak: Int
    let created_at: String?

    var id: String { offer_id }
    /// True when the ball is in this user's court to spend their own token.
    var isIncomingMile: Bool { initiator == "donor" }

    var displayName: String {
        if let username, !username.isEmpty { return username }
        if let first_name, !first_name.isEmpty { return first_name }
        return "A friend"
    }
}

/// A friend holding an Assist token with a day a donated mile could cover.
struct AssistableFriend: Codable, Identifiable {
    let user_id: String
    let username: String?
    let first_name: String?
    let last_name: String?
    let profile_image_url: String?
    let target_date: String
    /// "missed" — already lost; "today" — they can still go run it.
    let target_kind: String
    let prior_streak: Int
    /// What their streak becomes once the day is covered — the number the CTA
    /// promises. Optional so a backend that predates it still decodes.
    let restored_streak: Int?
    /// This user's standing offer to them: "none" | "pending" | "accepted".
    let offer_status: String?
    let offer_id: String?

    var id: String { user_id }
    var alreadyOffered: Bool { offer_status == "pending" || offer_status == "accepted" }
    var isToday: Bool { target_kind == "today" }

    var displayName: String {
        if let username, !username.isEmpty { return username }
        if let first_name, !first_name.isEmpty { return first_name }
        return "A friend"
    }

    /// Days the friend ends up on. Falls back to the pre-break run + the
    /// covered day when the server didn't send a projection.
    var streakAfterSave: Int { restored_streak ?? (prior_streak + 1) }
}

/// GET /users/streak-features/rescue/:friendId — everything one friend's
/// profile needs to render (or explain the absence of) the Donate a Mile CTA.
///
/// An Assist needs BOTH halves, so `available` false is usually "which half is
/// missing", not "nothing here": `friend_no_token` (they haven't banked 20
/// extra miles) and `no_miles` (you haven't run one past your goal today) both
/// still carry the day and the projection, so the button can say what to do.
struct FriendRescueStatus: Codable {
    let available: Bool
    let target_date: String?
    let target_kind: String?
    let prior_streak: Int?
    let restored_streak: Int?
    let self_recovery: String?
    let friend_holds_assist: Bool
    let viewer_budget: DonationBudget?
    let offer_status: String?
    let offer_id: String?
    let reason: String?

    var streakAfterSave: Int { restored_streak ?? ((prior_streak ?? 0) + 1) }
    var isToday: Bool { target_kind == "today" }
    var alreadyOffered: Bool { offer_status == "pending" || offer_status == "accepted" }

    /// The friend hasn't got the token-capable build, so nothing can be done
    /// for them yet — worth saying out loud rather than showing nothing.
    var friendNotEnrolled: Bool { reason == "friend_not_enrolled" }
    /// They have a day in play but haven't banked an Assist to spend on it.
    var friendHasNoToken: Bool { reason == "friend_no_token" }
    /// The user hasn't run their spare mile yet today.
    var needsMoreMiles: Bool { reason == "no_miles" }
}

/// GET /users/streak-features/status. `active` false = feature off server-side
/// (env switch off or not enrolled) → hide every token surface.
struct StreakFeaturesStatus: Codable {
    let active: Bool
    let streak: Int?
    let double_down: StreakFeaturesPayload.DoubleDownMeter?
    let streak_save: StreakTokenMeter?
    let streak_assist: StreakTokenMeter?
    let frozen_dates: [CoveredDate]?
    let natural_streak: Bool?
    let streak_at_risk: Bool?
    let my_savable_day: SavableDay?
    let assistable_friends: [AssistableFriend]?
    let donation_budget: DonationBudget?
    let pending_offers: [PendingAssistOffer]?
}

// MARK: - Service

/// Streak tokens API: enrollment, status (meters + rescuable friends), and
/// spending a Streak Assist on a friend. Everything is server-gated — until
/// the backend turns the feature on, status returns {active:false}, stats omit
/// the payload, and this build shows nothing.
enum StreakFeatureService {
    /// Once-per-process latch. Deliberately NOT persisted: a stored "already
    /// enrolled" flag is per-install while enrollment is per-BACKEND, so an
    /// enroll against a dev backend would permanently skip enrolling against
    /// production. The endpoint is COALESCE-idempotent — one tiny request per
    /// launch is the correct price for self-healing.
    private static var enrolledThisLaunch = false

    /// Idempotent enrollment stamp — fire-and-forget on launch (mirrors device
    /// token registration). Marks this account as token-UI-capable; the server
    /// decides everything else.
    static func enrollIfNeeded() {
        // Keychain-backed token check (the UserDefaults mirror can be missing
        // on installs that authed before the mirror existed).
        guard TokenStore.accessToken != nil else { return }
        guard !enrolledThisLaunch else { return }
        enrolledThisLaunch = true
        Task {
            struct EnrollResponse: Decodable { let enrolled: Bool }
            do {
                let resp: EnrollResponse = try await APIClient.fancyFetch(
                    endpoint: "/users/streak-features/enable",
                    method: .POST,
                    responseType: EnrollResponse.self
                )
                if resp.enrolled {
                    // Light the token surfaces up on THIS launch instead of
                    // waiting for the next stats fetch.
                    await StreakTokensState.shared.refreshStatus()
                }
            } catch {
                // Non-fatal, but retry next call — the latch shouldn't stick
                // on a failed request.
                enrolledThisLaunch = false
                print("[StreakFeatures] enroll failed: \(error.localizedDescription)")
            }
        }
    }

    /// Step-by-step diagnostic for Developer Settings — pinpoints WHERE the
    /// chain breaks (wrong API target, backend missing the endpoints because a
    /// deploy didn't land, kill switch on, or not enrolled) instead of the
    /// surfaces just silently showing nothing.
    static func diagnose() async -> String {
        var lines = ["API: \(AppConfig.baseURL)"]
        guard TokenStore.accessToken != nil else {
            return lines.joined(separator: "\n") + "\nNo auth token — sign in first."
        }
        struct EnrollResponse: Decodable { let enrolled: Bool }
        do {
            _ = try await APIClient.fancyFetch(
                endpoint: "/users/streak-features/enable",
                method: .POST,
                responseType: EnrollResponse.self
            )
            lines.append("Enroll: OK (stamp written)")
        } catch {
            lines.append("Enroll FAILED: \(error.localizedDescription)")
            lines.append("→ If this is a 404, this backend doesn't have the streak endpoints — the deploy didn't land.")
            return lines.joined(separator: "\n")
        }
        do {
            let status = try await fetchStatus()
            if status.active {
                lines.append("Status: ACTIVE — meters loaded. UI should be visible everywhere.")
                await StreakTokensState.shared.refreshStatus()
            } else {
                lines.append("Status: inactive — enrolled, but the server gate is off (STREAK_FEATURES_DISABLED is set, or this backend predates the gate inversion).")
            }
        } catch {
            lines.append("Status FAILED: \(error.localizedDescription)")
        }
        return lines.joined(separator: "\n")
    }

    /// Meters + rescuable friends for the token surfaces.
    static func fetchStatus() async throws -> StreakFeaturesStatus {
        try await APIClient.fancyFetch(
            endpoint: "/users/streak-features/status",
            responseType: StreakFeaturesStatus.self
        )
    }

    /// Can the caller rescue THIS friend right now, and if not, why not. Cheap
    /// per-friend read — the status endpoint only lists rescuable friends when
    /// the caller already holds an Assist, which is exactly the case where a
    /// profile can't explain why its CTA is missing.
    static func rescueStatus(friendId: String) async throws -> FriendRescueStatus {
        try await APIClient.fancyFetch(
            endpoint: "/users/streak-features/rescue/\(friendId)",
            responseType: FriendRescueStatus.self
        )
    }

    struct AssistResponse: Decodable {
        let ok: Bool?
        let offer_id: String?
        let target_date: String?
        let restored_streak: Int?
        /// False for a pending offer, true once coverage was actually written.
        let applied: Bool?
    }

    /// Donate one of today's miles past goal to a friend. This does NOT cover
    /// anything yet — the token that pays for the coverage is theirs, so they
    /// get the last word.
    static func offerAssist(friendId: String) async throws -> AssistResponse {
        try await APIClient.fancyFetch(
            endpoint: "/users/streak-features/assist/\(friendId)",
            method: .POST,
            responseType: AssistResponse.self
        )
    }

    /// Ask a friend to run you a mile. Costs them nothing until they accept.
    static func requestAssist(friendId: String) async throws -> AssistResponse {
        try await APIClient.fancyFetch(
            endpoint: "/users/streak-features/assist-request/\(friendId)",
            method: .POST,
            responseType: AssistResponse.self
        )
    }

    /// Answer the half of an exchange waiting on you. Accepting is what writes
    /// the coverage row and spends the recipient's token.
    static func respondToOffer(offerId: String, accept: Bool) async throws -> AssistResponse {
        try await APIClient.fancyFetch(
            endpoint: "/users/streak-features/assist-offers/\(offerId)",
            method: .POST,
            body: try JSONSerialization.data(withJSONObject: ["accept": accept]),
            responseType: AssistResponse.self
        )
    }

    /// Apply the CURRENT USER's fresh gated stats payload: sync the coverage
    /// store the three client streak walks union in, and the observable UI
    /// state. Pass nil when the response had no payload (feature off) so stale
    /// coverage can't linger. NEVER call this with a FRIEND's stats response.
    static func applyStatsPayload(_ payload: StreakFeaturesPayload?) {
        if let payload {
            StreakCoverageStore.update(
                coveredDates: payload.frozen_dates.map { $0.local_date }
            )
        } else if StreakCoverageStore.isActive {
            StreakCoverageStore.deactivate()
        }
        Task { @MainActor in
            StreakTokensState.shared.apply(payload)
        }
    }
}
