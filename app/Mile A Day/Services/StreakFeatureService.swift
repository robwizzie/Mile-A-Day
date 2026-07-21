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
}

/// A day the server says still counts (token-covered), with which token did it.
struct CoveredDate: Codable {
    let local_date: String
    let kind: String
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
}

/// A friend whose just-broken streak the user can rescue right now.
struct AssistableFriend: Codable, Identifiable {
    let user_id: String
    let username: String?
    let first_name: String?
    let last_name: String?
    let profile_image_url: String?
    let broke_date: String
    let prior_streak: Int

    var id: String { user_id }

    var displayName: String {
        if let username, !username.isEmpty { return username }
        if let first_name, !first_name.isEmpty { return first_name }
        return "A friend"
    }
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
    let assistable_friends: [AssistableFriend]?
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

    struct AssistResponse: Decodable {
        let ok: Bool?
        let restored_streak: Int?
    }

    /// Spend a held Streak Assist to restore a friend's just-broken streak.
    static func assist(friendId: String) async throws -> AssistResponse {
        try await APIClient.fancyFetch(
            endpoint: "/users/streak-features/assist/\(friendId)",
            method: .POST,
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
            StreakTokensState.shared.payload = payload
            if let payload {
                StreakTokensState.shared.registerHeldStates(from: payload)
            }
        }
    }
}
