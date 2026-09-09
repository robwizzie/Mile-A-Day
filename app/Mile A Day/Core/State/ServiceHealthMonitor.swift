import Foundation
import SwiftUI

/// Is the app able to reach Mile A Day, and if not, why?
///
/// Fed by the ONE place every API call goes through (`APIClient.makeRequest`),
/// so nothing has to be instrumented per feature: whatever the user was doing
/// when the server went away is what trips this.
///
/// The human-readable reason comes from `mileaday.run/api/status`, which is on
/// the WEBSITE rather than the API — the API is the thing that goes down, so it
/// can't be the thing that reports being down. When even that is unreachable
/// the banner still appears, just with copy we wrote in advance.
@MainActor
final class ServiceHealthMonitor: ObservableObject {
    static let shared = ServiceHealthMonitor()

    enum Health: Equatable {
        case ok
        /// The phone has no working connection. Not our outage, and saying
        /// "Mile A Day is down" to someone in a lift is a lie that costs trust.
        case deviceOffline
        /// The phone is online and the server isn't answering.
        case serverUnreachable
    }

    struct Notice: Equatable {
        var title: String
        var message: String
        var until: Date?
    }

    @Published private(set) var health: Health = .ok
    /// What the status page says, once we've managed to ask it.
    @Published private(set) var notice: Notice?
    /// Hidden by the user for this episode. Cleared when service returns, so
    /// the next outage is announced again.
    @Published var isDismissed = false

    /// One failure is a blip — a tunnel, a lift, a radio waking up. Two
    /// consecutive ones with nothing succeeding in between is a pattern.
    private let failureThreshold = 2
    /// While down, re-ask the status page on this cadence so the banner can
    /// correct itself even if the user never triggers another API call.
    private let recheckInterval: TimeInterval = 30

    private var consecutiveFailures = 0
    private var lastStatusFetch: Date?
    private var statusTask: Task<Void, Never>?
    private var recheckTask: Task<Void, Never>?

    private static let statusURL = URL(string: "https://mileaday.run/api/status")!

    private init() {}

    var isDown: Bool { health != .ok }
    /// Should the banner be on screen right now?
    var showsBanner: Bool { isDown && !isDismissed }

    // MARK: - Fed by APIClient

    /// Any HTTP response at all — even a 500 — means we reached the server.
    func recordSuccess() {
        consecutiveFailures = 0
        guard health != .ok else { return }
        health = .ok
        notice = nil
        // Cleared so the NEXT outage is announced rather than inheriting a
        // dismissal from the last one.
        isDismissed = false
        statusTask?.cancel()
        statusTask = nil
        recheckTask?.cancel()
        recheckTask = nil
    }

    /// A request that never got a response. Only *connectivity* failures count:
    /// a decoding error or a cancelled task says nothing about the server.
    func recordFailure(_ error: Error) {
        guard let reason = Self.classify(error) else { return }
        consecutiveFailures += 1
        guard consecutiveFailures >= failureThreshold else { return }

        // Being offline outranks a server verdict: we genuinely cannot tell
        // whether the server is up from a phone with no connection.
        if reason == .deviceOffline {
            health = .deviceOffline
            notice = nil
            return
        }
        if health != .serverUnreachable {
            health = .serverUnreachable
        }
        refreshNoticeIfStale()
    }

    /// Called on foreground and by the banner's own timer.
    ///
    /// Asks the API directly whether it's back, because nothing else will: the
    /// banner is raised by failing API calls, and an app sitting behind an
    /// outage banner is precisely one that has stopped making them. Without
    /// this the banner clears only when the user happens to trigger a request
    /// that succeeds.
    func recheck() {
        guard isDown, recheckTask == nil else { return }
        recheckTask = Task { [weak self] in
            let reachable = await Self.apiIsReachable()
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self else { return }
                self.recheckTask = nil
                if reachable {
                    self.recordSuccess()
                } else {
                    self.refreshNoticeIfStale(force: true)
                }
            }
        }
    }

    /// The API's own unauthenticated health route, asked from THIS phone —
    /// which is the only test that matches what the user is experiencing. The
    /// website's verdict is about what Vercel can reach, not what they can.
    private static func apiIsReachable() async -> Bool {
        guard let url = URL(string: "\(AppConfig.baseURL)/status") else { return false }
        var request = URLRequest(url: url)
        request.timeoutInterval = 6
        request.cachePolicy = .reloadIgnoringLocalCacheData
        guard let (_, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse
        else { return false }
        return (200...499).contains(http.statusCode)
    }

    // MARK: - Status page

    private func refreshNoticeIfStale(force: Bool = false) {
        if !force, let last = lastStatusFetch,
           Date().timeIntervalSince(last) < recheckInterval { return }
        guard statusTask == nil || force else { return }
        lastStatusFetch = Date()
        statusTask?.cancel()
        statusTask = Task { [weak self] in
            let result = await Self.fetchStatus()
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.apply(result) }
        }
    }

    private func apply(_ status: StatusResponse?) {
        statusTask = nil
        guard let status else {
            // The status page is unreachable too. Most likely the phone's
            // connection, but we already ruled that out — so say the plain
            // thing rather than inventing a reason.
            notice = nil
            return
        }
        if status.ok == true {
            // The server answers the website but not us. Still an outage from
            // where the user is standing, so the banner stays — but there's no
            // announcement to show with it.
            notice = nil
            return
        }
        notice = Notice(
            title: status.title ?? "Mile A Day is down",
            message: status.message
                ?? "We're on it. Your walks are recorded on your phone and will sync as soon as we're back.",
            until: status.until.flatMap(Self.parseDate)
        )
    }

    /// Everything optional: this is served by a page that will change without
    /// the app changing, and a status check that fails to decode is a status
    /// check that doesn't work exactly when it's needed.
    private struct StatusResponse: Decodable {
        var ok: Bool?
        var title: String?
        var message: String?
        var until: String?
    }

    private static func fetchStatus() async -> StatusResponse? {
        var request = URLRequest(url: statusURL)
        request.timeoutInterval = 8
        // Never a cached "we're fine" from before the outage started.
        request.cachePolicy = .reloadIgnoringLocalCacheData
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200
        else { return nil }
        return try? JSONDecoder().decode(StatusResponse.self, from: data)
    }

    private static func parseDate(_ raw: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: raw) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: raw)
    }

    // MARK: - Classification

    private enum FailureKind { case deviceOffline, serverUnreachable }

    /// Which failures mean "couldn't reach the server", and which mean nothing.
    ///
    /// A cancelled request is the app's own doing (a view went away), and a
    /// decode failure means the server answered fine — counting either would
    /// put an outage banner over a working app.
    private static func classify(_ error: Error) -> FailureKind? {
        guard let urlError = error as? URLError else { return nil }
        switch urlError.code {
        case .notConnectedToInternet, .networkConnectionLost,
             .dataNotAllowed, .internationalRoamingOff:
            return .deviceOffline
        case .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed,
             .timedOut, .badServerResponse, .secureConnectionFailed,
             .resourceUnavailable:
            return .serverUnreachable
        default:
            return nil
        }
    }
}
