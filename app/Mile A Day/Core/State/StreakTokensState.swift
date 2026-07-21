import Foundation
import SwiftUI

/// A coverage event worth telling the user about: a token fired on their
/// behalf (their own Save/Double Down, or a friend's Assist landing on them).
struct TokenStoryEvent: Equatable {
    /// Coverage kind: "streak_save" | "double_down_recover" | "streak_assist".
    let kind: String
    /// The covered local day, "yyyy-MM-dd".
    let localDate: String
}

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
    /// Tokens that just flipped to EARNED (raw kinds: "double_down",
    /// "streak_save", "streak_assist") — drives the unlock celebration.
    /// Cleared by the overlay's dismiss.
    @Published var newlyEarned: [String] = []
    /// Transient "+1 run day" chips per raw kind — set when a fresh payload
    /// moves a meter forward within a session, auto-cleared a few seconds
    /// later. Purely celebratory; nothing reads it for logic.
    @Published var meterGains: [String: String] = [:]
    private var gainsClearTask: Task<Void, Never>?
    /// A token just fired (save auto-covered a day / Double Down completed /
    /// a friend's Assist landed) — drives the story overlay. Cleared on
    /// dismiss; each coverage row tells its story exactly once (persisted).
    @Published var storyEvent: TokenStoryEvent?

    var isActive: Bool { payload != nil }

    private static let heldFlagsKey = "streakTokenHeldFlags"

    /// Single entry point for a fresh (or absent) payload: diffs meters for
    /// the gain chips, publishes the payload, and diffs held flags for the
    /// unlock celebration. Callers go through
    /// `StreakFeatureService.applyStatsPayload`, which also syncs the
    /// coverage store.
    @MainActor
    func apply(_ new: StreakFeaturesPayload?) {
        if let new, let old = payload {
            noteMeterGains(old: old, new: new)
        }
        payload = new
        if let new {
            registerHeldStates(from: new)
            detectCoverageStories(in: new)
        }
        // Mirror the held count to the streak widget and the watch. Both
        // sinks dedupe (no-op write skip / stable-hash), so calling on every
        // payload is free.
        let ready = new.map {
            [$0.double_down.held, $0.streak_save.held, $0.streak_assist.held]
                .filter { $0 }.count
        } ?? 0
        WidgetDataStore.save(tokensReady: ready)
        MADWatchBridge.shared.pushSnapshotIfReady()
    }

    /// Meter deltas → short gain chips ("+1 day", "+0.8 mi"). Held meters are
    /// skipped — the unlock overlay owns that bigger moment.
    @MainActor
    private func noteMeterGains(old: StreakFeaturesPayload, new: StreakFeaturesPayload) {
        var gains: [String: String] = [:]
        if !new.double_down.held {
            let d = Int(new.double_down.progress) - Int(old.double_down.progress)
            if d > 0 { gains["double_down"] = "+\(d) day\(d == 1 ? "" : "s")" }
        }
        if !new.streak_save.held {
            let d = Int(new.streak_save.progress) - Int(old.streak_save.progress)
            if d > 0 { gains["streak_save"] = "+\(d) run day\(d == 1 ? "" : "s")" }
        }
        if !new.streak_assist.held {
            let d = new.streak_assist.progress - old.streak_assist.progress
            if d >= 0.05 { gains["streak_assist"] = String(format: "+%.1f mi", d) }
        }
        guard !gains.isEmpty else { return }
        meterGains = gains
        gainsClearTask?.cancel()
        gainsClearTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            self?.meterGains = [:]
        }
    }

    private static let seenCoverageKey = "streakTokenSeenCoverage"

    /// Coverage rows are the receipts of tokens FIRING. Any row we haven't
    /// seen before (persisted set) is a story to tell — but only recent ones:
    /// a months-old row appearing on a reinstall isn't a moment. The very
    /// first payload baselines silently so existing coverage can't storm.
    @MainActor
    private func detectCoverageStories(in payload: StreakFeaturesPayload) {
        let keys = payload.frozen_dates.map { "\($0.kind):\($0.local_date)" }
        guard UserDefaults.standard.object(forKey: Self.seenCoverageKey) != nil else {
            UserDefaults.standard.set(keys, forKey: Self.seenCoverageKey)
            return
        }
        var seen = Set(UserDefaults.standard.stringArray(forKey: Self.seenCoverageKey) ?? [])
        let fresh = payload.frozen_dates.filter { !seen.contains("\($0.kind):\($0.local_date)") }
        guard !fresh.isEmpty else { return }
        keys.forEach { seen.insert($0) }
        UserDefaults.standard.set(Array(seen), forKey: Self.seenCoverageKey)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let recent = fresh.filter {
            guard let d = formatter.date(from: $0.local_date) else { return false }
            return d >= cutoff
        }
        // One story at a time — the most recent covered day wins.
        if let latest = recent.max(by: { $0.local_date < $1.local_date }) {
            storyEvent = TokenStoryEvent(kind: latest.kind, localDate: latest.local_date)
        }
    }

    /// Diff the held flags against the last seen set (persisted, so the
    /// celebration fires exactly once per earn — including the very first
    /// payload after enrollment backfill, the "you start fully loaded" moment).
    @MainActor
    func registerHeldStates(from payload: StreakFeaturesPayload) {
        let previous =
            UserDefaults.standard.dictionary(forKey: Self.heldFlagsKey) as? [String: Bool] ?? [:]
        let current: [String: Bool] = [
            "double_down": payload.double_down.held,
            "streak_save": payload.streak_save.held,
            "streak_assist": payload.streak_assist.held,
        ]
        let earned = current
            .filter { $0.value && previous[$0.key] != true }
            .map { $0.key }
            .sorted()
        UserDefaults.standard.set(current, forKey: Self.heldFlagsKey)
        if !earned.isEmpty {
            newlyEarned = earned
        }
    }

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
            assistableFriends = status.assistable_friends ?? []
            // Route through applyStatsPayload → apply() so the payload is
            // published, held flags are diffed, gain chips fire, and the
            // coverage store stays in sync — one path for every payload.
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
