import Foundation
import SwiftUI

/// Observable snapshot of the user's streak-token state (meters, natural
/// streak, at-risk), refreshed whenever the user's OWN gated stats payload
/// arrives. `payload == nil` means the feature is off server-side — every
/// token surface hides, so older behavior is untouched.
/// Plain ObservableObject (matching UserManager/CelebrationManager); all
/// mutations happen on the main actor via the annotated method below.
final class StreakTokensState: ObservableObject {
    static let shared = StreakTokensState()
    private init() {}

    @Published var payload: StreakFeaturesPayload?
    /// Friends the user can rescue right now (from the status endpoint).
    @Published var assistableFriends: [AssistableFriend] = []
    /// DEBUG preview: while true, refreshStatus() is a no-op so server state
    /// can't clobber the injected sample data. Never persisted.
    @Published var isPreviewingSampleData = false

    var isActive: Bool { payload != nil }

    /// Refresh meters + rescuable friends from the status endpoint (used by
    /// surfaces that need fresher data than the last stats fetch, e.g. the
    /// friends page assist banner).
    @MainActor
    func refreshStatus() async {
        guard !isPreviewingSampleData else { return }
        do {
            let status = try await StreakFeatureService.fetchStatus()
            guard status.active,
                  let dd = status.double_down,
                  let save = status.streak_save,
                  let assist = status.streak_assist
            else {
                payload = nil
                assistableFriends = []
                StreakFeatureService.applyStatsPayload(nil)
                return
            }
            let fresh = StreakFeaturesPayload(
                double_down: dd,
                streak_save: save,
                streak_assist: assist,
                frozen_dates: status.frozen_dates ?? [],
                natural_streak: status.natural_streak ?? true,
                streak_at_risk: status.streak_at_risk ?? false
            )
            payload = fresh
            assistableFriends = status.assistable_friends ?? []
            StreakFeatureService.applyStatsPayload(fresh)
        } catch {
            // Keep last known state on transient failures.
            print("[StreakTokens] status refresh failed: \(error.localizedDescription)")
        }
    }

    #if DEBUG
    /// Inject rich sample data so every token surface (StreakCard row, the
    /// explainer sheet, the friends-page rescue banner, the Pure Flame badge)
    /// is visible WITHOUT any backend — pure UI/UX review mode. Session-only.
    @MainActor
    func enableSamplePreview() {
        isPreviewingSampleData = true
        payload = StreakFeaturesPayload(
            double_down: .init(
                progress: 9, target: 14, held: false, last_used: nil,
                recover_miles: 1.95
            ),
            streak_save: StreakTokenMeter(
                progress: 7, target: 7, held: true, last_used: nil
            ),
            streak_assist: StreakTokenMeter(
                progress: 12.5, target: 20, held: true, last_used: nil
            ),
            frozen_dates: [],
            natural_streak: true,
            streak_at_risk: true
        )
        assistableFriends = [
            AssistableFriend(
                user_id: "preview-friend",
                username: "davey",
                first_name: "Dave",
                last_name: nil,
                profile_image_url: nil,
                broke_date: "2026-07-20",
                prior_streak: 42
            )
        ]
    }

    @MainActor
    func disableSamplePreview() {
        isPreviewingSampleData = false
        payload = nil
        assistableFriends = []
        Task { await refreshStatus() }
    }
    #endif
}
