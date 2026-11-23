import ActivityKit
import Foundation

/// Owns the buddy walk's lock-screen card (`BuddyWalkLiveActivity`).
///
/// Driven entirely by `BuddySessionService.apply`: every snapshot of the walk
/// this user is in lands here, and the card follows it.
///
///  - **In the lobby, not recording, not the host** → a card exists for this
///    walk ("Waiting for Rob to start", or the countdown once it started),
///    requested with `pushType: .token` so the SERVER can push the countdown
///    onto a locked phone (`buddyLiveActivityService`). Its push token is
///    handed to `POST /buddy/sessions/:id/live-activity`.
///  - **Recording, finished, left, cancelled, a different walk** → ended.
///
/// The host gets no card: they tap Start themselves, looking at the screen.
/// Activities can only be REQUESTED with the app in the foreground, which is
/// exactly when a guest is in the lobby; updates and the end work any time.
@MainActor
final class BuddyWalkActivityManager {
    static let shared = BuddyWalkActivityManager()
    private init() {}

    private var activity: Activity<BuddyWalkActivityAttributes>?
    private var tokenTask: Task<Void, Never>?
    /// The last state written, so an unchanged poll writes nothing.
    private var lastState: BuddyWalkActivityAttributes.ContentState?

    func sync(session: BuddySessionState?, currentUserId: String?) {
        guard let session, let want = wantedState(session, currentUserId: currentUserId) else {
            endAll()
            return
        }
        if let activity, activity.attributes.sessionId == session.id {
            guard want != lastState else { return }
            lastState = want
            Task { await activity.update(ActivityContent(state: want, staleDate: Self.staleDate)) }
            return
        }
        // After a relaunch the reference is gone but the card isn't: adopt it
        // (and listen for its token again) instead of replacing it.
        if let existing = Activity<BuddyWalkActivityAttributes>.activities
            .first(where: { $0.attributes.sessionId == session.id }) {
            activity = existing
            lastState = nil
            observeToken(existing, sessionId: session.id)
            sync(session: session, currentUserId: currentUserId)
            return
        }
        endAll()
        start(session: session, state: want)
    }

    private func observeToken(_ card: Activity<BuddyWalkActivityAttributes>, sessionId: String) {
        tokenTask?.cancel()
        tokenTask = Task {
            for await data in card.pushTokenUpdates {
                let hex = data.map { String(format: "%02x", $0) }.joined()
                await BuddySessionService.shared.registerLiveActivity(
                    sessionId: sessionId, pushToken: hex)
            }
        }
    }

    /// The walk started on THIS phone: the workout's own Live Activity takes
    /// over, so this card goes now rather than at the next snapshot.
    func endForRecording() {
        endAll()
    }

    // MARK: - Private

    private static var staleDate: Date { Date().addingTimeInterval(2 * 60 * 60) }

    private func wantedState(
        _ session: BuddySessionState, currentUserId: String?
    ) -> BuddyWalkActivityAttributes.ContentState? {
        guard session.status == .lobby || session.status == .active else { return nil }
        guard !session.isHost(currentUserId), let me = session.me(currentUserId) else { return nil }
        guard me.status == .joined || me.status == .ready || me.status == .active else { return nil }
        // Already recording here, or on their Watch: nothing left to prompt.
        if InProgressWorkoutStore.load()?.isActive == true { return nil }
        if me.lastHeardSeconds != nil { return nil }
        let crew = session.participants.filter {
            $0.status == .joined || $0.status == .ready || $0.status == .active || $0.status == .finished
        }.count
        if session.status == .active, let starts = session.startedAtDate {
            return .init(
                phase: starts > Date() ? "countdown" : "started",
                startsAtUnix: starts.timeIntervalSince1970,
                crewCount: crew)
        }
        return .init(phase: "waiting", startsAtUnix: nil, crewCount: crew)
    }

    private func start(session: BuddySessionState, state: BuddyWalkActivityAttributes.ContentState) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let host = session.participants.first { session.isHost($0.userId) }
        let attributes = BuddyWalkActivityAttributes(
            sessionId: session.id,
            hostName: host?.displayName ?? String(localized: "Your friend"),
            isRun: session.activityType == "running",
            isHost: false)
        do {
            let started = try Activity.request(
                attributes: attributes,
                content: ActivityContent(state: state, staleDate: Self.staleDate),
                pushType: .token)
            activity = started
            lastState = state
            observeToken(started, sessionId: session.id)
        } catch {
            // Live Activities off, too many running, or backgrounded: the
            // in-app banner and the pushes still cover it.
            print("[BuddyWalkActivity] request failed: \(error)")
        }
    }

    private func endAll() {
        tokenTask?.cancel()
        tokenTask = nil
        activity = nil
        lastState = nil
        // Every buddy card, including one left behind by a relaunch (the
        // reference above doesn't survive one; the system's list does).
        let running = Activity<BuddyWalkActivityAttributes>.activities
        guard !running.isEmpty else { return }
        Task {
            for card in running {
                await card.end(nil, dismissalPolicy: .immediate)
            }
        }
    }
}
