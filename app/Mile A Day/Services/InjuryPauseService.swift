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

    var isPaused: Bool { status?.isPaused ?? false }

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
