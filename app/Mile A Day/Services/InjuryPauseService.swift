import Foundation
import SwiftUI

/// Injury pause ("Recovery Mode") — the long-absence counterpart to the
/// single-day streak tokens.
///
/// The server owns every rule; this type deliberately stores NO thresholds of
/// its own. `InjuryPauseStatus` carries `min_streak` / `min_days` / `max_days`
/// / `max_backdate_days` / `reearn_target` on the wire precisely so the copy
/// can't drift from what the backend will actually enforce — if a limit is
/// ever retuned, the app follows without a release.
enum InjuryPauseAPI {
    static func status() async throws -> InjuryPauseStatus {
        try await APIClient.fancyFetch(
            endpoint: "/streak/pause",
            responseType: InjuryPauseStatus.self
        )
    }

    /// `startedOn` is a YYYY-MM-DD local date, up to `max_backdate_days` back.
    /// Nil means "today" — resolved server-side, since only the server knows
    /// the user's local day the same way the streak walk files it.
    static func start(startedOn: String?) async throws -> InjuryPauseStatus {
        var body: Data? = nil
        if let startedOn {
            body = try JSONEncoder().encode(["started_on": startedOn])
        }
        return try await APIClient.fancyFetch(
            endpoint: "/streak/pause",
            method: .POST,
            body: body,
            responseType: InjuryPauseStatus.self
        )
    }

    static func end() async throws -> InjuryPauseStatus {
        try await APIClient.fancyFetch(
            endpoint: "/streak/pause",
            method: .DELETE,
            responseType: InjuryPauseStatus.self
        )
    }
}

// MARK: - Live state

/// Shared, observable pause state for every surface that has to know.
///
/// Plain `ObservableObject` matching StreakTokensState / UserManager — NOT
/// `@Observable` and not a `@MainActor` type: the views hold it as an
/// `@ObservedObject` stored property, and every mutation is annotated below.
final class InjuryPauseState: ObservableObject {
    static let shared = InjuryPauseState()

    @Published private(set) var status: InjuryPauseStatus?
    @Published private(set) var isLoading = false
    @Published var lastError: String?

    /// DEBUG PREVIEW — see `InjuryPausePreview`. Published so flipping the
    /// toggle repaints the dashboard immediately.
    @Published var previewEnabled = InjuryPausePreview.isOn

    private init() {}

    /// Fed from the user's OWN gated stats payload, which already carries
    /// `injury_pause` — so the dashboard learns it's paused with no extra
    /// request. A nil payload means the server isn't offering the feature;
    /// that must clear the state rather than strand a stale pause on screen.
    @MainActor
    func apply(_ payload: StreakFeaturesPayload?) {
        status = payload?.injury_pause
    }

    /// Per-USER state on a process-lifetime singleton, so it has to be dropped
    /// when the session does. A same-process account switch would otherwise
    /// leave the next user looking at the previous one's frozen streak — and,
    /// if their first stats read failed, keep it there indefinitely.
    @MainActor
    func reset() {
        status = nil
        lastError = nil
    }

    /// What every surface should read. Returns the fake status while preview is
    /// on so the paused UI can be inspected without actually pausing a streak.
    ///
    /// The `isDevelopment` half is load-bearing, not belt-and-braces: the flag
    /// lives in UserDefaults, which SURVIVES a Debug → TestFlight upgrade of
    /// the same install. Without it, anyone who left the toggle on would get a
    /// production dashboard insisting their streak was frozen at 412 days, with
    /// the switch to turn it off now hidden.
    var effective: InjuryPauseStatus? {
        (previewEnabled && AppEnvironment.isDevelopment) ? InjuryPausePreview.sample : status
    }

    var isPaused: Bool { effective?.isPaused ?? false }

    @MainActor
    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            status = try await InjuryPauseAPI.status()
            lastError = nil
        } catch {
            // A failed read must not claim the user is un-paused — leave the
            // last known status in place and let the surfaces keep drawing it.
            lastError = error.localizedDescription
        }
    }

    /// Returns nil on success, or a user-facing message on failure.
    @MainActor
    func start(startedOn: String?) async -> String? {
        do {
            status = try await InjuryPauseAPI.start(startedOn: startedOn)
            lastError = nil
            return nil
        } catch {
            let message = Self.message(for: error)
            lastError = message
            return message
        }
    }

    @MainActor
    func end() async -> String? {
        do {
            let ended = try await InjuryPauseAPI.end()
            lastError = nil
            // ORDER MATTERS. The inactive status carries no frozen_streak, so
            // the moment it lands the hero falls back to currentUser.streak —
            // which is still 0 from the injury days the pause was covering.
            // Holding the ACTIVE status across the refresh keeps the frozen
            // number on screen until the real one arrives; assigning first
            // would flash a zero for the length of the request, and leave it
            // there for good if the request failed.
            await SelfStatsRefresher.refreshBackendStats(userManager: .shared)
            status = ended
            return nil
        } catch {
            let message = Self.message(for: error)
            lastError = message
            return message
        }
    }

    /// The server's machine-readable `error` strings, turned into copy. Falls
    /// back to the raw description so an unmapped case is still debuggable
    /// rather than silently generic.
    private static func message(for error: Error) -> String {
        let raw = "\(error)"
        if raw.contains("streak_too_short") { return "Your streak isn't long enough to pause yet." }
        if raw.contains("rebuilding") { return "You're still rebuilding since your last pause." }
        if raw.contains("already_paused") { return "Your streak is already paused." }
        if raw.contains("minimum_not_reached") { return "It's too early to end this pause." }
        if raw.contains("backdate_too_far") { return "That's further back than a pause can start." }
        if raw.contains("started_on_in_future") { return "That date hasn't happened yet." }
        if raw.contains("invalid_started_on") { return "That date isn't valid." }
        if raw.contains("not_paused") { return "Your streak isn't paused." }
        if raw.contains("not_enrolled") { return "Recovery Mode isn't available on this account yet." }
        if raw.contains("injury_pause_disabled") { return "Recovery Mode is temporarily unavailable." }
        return error.localizedDescription
    }
}

// MARK: - Preview harness (TEMPORARY)

/// ⚠️ DELETE ME — a way to look at the paused UI without actually pausing a
/// streak. Toggle lives at the bottom of Settings.
///
/// Everything for this lives in this one enum plus `InjuryPauseState.effective`
/// and one Settings row, so removing it is: delete this enum, delete the
/// `previewEnabled`/`effective` members above, point the surfaces back at
/// `status`, delete the Settings row. Search `InjuryPausePreview`.
enum InjuryPausePreview {
    static let key = "injuryPausePreviewV1_DELETE_ME"

    static var isOn: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    /// A plausible mid-recovery pause: 23 days into a 412-day streak, one week
    /// short of being allowed to end it.
    static let sample = InjuryPauseStatus(
        active: .init(
            id: "preview",
            started_on: "2026-07-31",
            frozen_streak: 412,
            paused_days: 23,
            can_end: false,
            expires_on: "2027-01-26"
        ),
        eligible: false,
        reason: "already_paused",
        reearn_progress: 0,
        reearn_target: 90,
        min_streak: 90,
        min_days: 30,
        max_days: 180,
        max_backdate_days: 7
    )
}
