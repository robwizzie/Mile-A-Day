import SwiftUI
import Combine

/// The buddy walk that needs you, on every tab.
///
/// Buddy walks only ever asked for attention in two places: a push (gone the
/// moment it's swiped away) and a grey capsule under Home's Start button. So a
/// walker who opened the app from its icon, onto the Feed or Friends, saw no
/// sign of the walk they were on, and an invite nobody tapped the push for was
/// effectively invisible. Worse, the guest whose phone was locked at the
/// countdown — and so was recording NOTHING (`BuddyLobbyView.handOffIfStarted`
/// only fires with the lobby on screen) — had no way to find out.
///
/// One card, above the tab bar, on whichever tab is showing. Highest stakes
/// first:
///
///  1. **Not recording.** You're on a walk that has started and this phone
///     isn't tracking it. Red, because every step now is being lost — and the
///     tap hands off with `BuddyLateStart` crediting the ground already
///     walked.
///  2. **Waiting in a lobby** you joined (it's counting down or the host
///     hasn't started yet).
///  3. **An invite.** Named, with the host's face and one Join button; "Later"
///     tucks that one invite away until the app is next opened.
///
/// Hidden while this phone is recording (`InProgressWorkoutBanner` is the way
/// back then, and the tracker carries the roster), so the two never stack.
struct BuddyAttentionBanner: View {
    /// `WorkoutLocationManager.isTracking`, from `MainTabView`.
    let isTracking: Bool
    /// Bring Home forward: the buddy flow is the Dashboard's to present.
    let onOpen: () -> Void

    @ObservedObject private var buddy = BuddySessionService.shared
    @Environment(\.scenePhase) private var scenePhase
    /// Invites put off with "Later", this launch only.
    @State private var snoozedInviteIds: Set<String> = []
    /// Moves the "has it started yet" line over the countdown.
    @State private var now = Date()
    private let tick = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    private enum Need: Equatable {
        case notRecording(BuddySessionState)
        case lobby(BuddySessionState)
        case invite(BuddySessionState)

        var session: BuddySessionState {
            switch self {
            case .notRecording(let s), .lobby(let s), .invite(let s): return s
            }
        }
    }

    private var need: Need? {
        // "Am I walking" is the persisted workout, not a view flag.
        guard !isTracking, InProgressWorkoutStore.load()?.isActive != true else { return nil }
        if buddy.canReenterLiveSession, let session = buddy.session {
            if session.status == .active, let started = session.startedAtDate, started <= now {
                return .notRecording(session)
            }
            return .lobby(session)
        }
        if let invite = buddy.invites.first(where: {
            !snoozedInviteIds.contains($0.id) && $0.status != .cancelled
        }) {
            return .invite(invite)
        }
        return nil
    }

    var body: some View {
        Group {
            if let need {
                card(need)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(MADTheme.Animation.standard, value: need)
        .onReceive(tick) { now = $0 }
        // Invites used to be fetched once, when Home first mounted: coming
        // back to the app, or an invite landing while it was open, changed
        // nothing on screen.
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await buddy.refreshMySessions() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .didReceivePushNotification)) { note in
            guard let type = note.userInfo?["type"] as? String, type.hasPrefix("buddy_") else { return }
            Task { await buddy.refreshMySessions() }
        }
    }

    // MARK: - Card

    private func card(_ need: Need) -> some View {
        let session = need.session
        let host = session.participants.first { session.isHost($0.userId) }
        return HStack(spacing: 12) {
            AvatarWithRing(
                name: host?.displayName ?? "",
                imageURL: host?.profileImageUrl,
                progress: 0,
                size: 42,
                accent: tint(need)
            )
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title(need, host: host))
                    .madFont(size: 15, weight: .bold, design: .rounded)
                    .foregroundStyle(.white)
                    .madBodyLines(2)
                Text(subtitle(need))
                    .madFont(size: 12, weight: .semibold)
                    .foregroundStyle(.white.opacity(0.75))
                    .madBodyLines(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 6) {
                Button {
                    MADHaptics.emphasis()
                    open(session)
                } label: {
                    Text(actionTitle(need))
                        .madFont(size: 14, weight: .heavy, design: .rounded)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .foregroundStyle(actionForeground(need))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(Capsule().fill(Color.white))
                }
                .buttonStyle(.plain)

                if case .invite = need {
                    Button {
                        MADHaptics.tap()
                        snoozedInviteIds.insert(session.id)
                    } label: {
                        Text("Later")
                            .madFont(size: 12, weight: .bold)
                            .foregroundStyle(.white.opacity(0.75))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                    }
                    .buttonStyle(.plain)
                }
            }
            .fixedSize()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(tint(need))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
        .contentShape(Rectangle())
        // The whole card opens it too: a big target is the point of the card.
        .onTapGesture { open(session) }
        .accessibilityElement(children: .contain)
    }

    private func open(_ session: BuddySessionState) {
        DeepLinkRouter.shared.requestOpenBuddySession(sessionId: session.id)
        onOpen()
    }

    // MARK: - Copy

    private func tint(_ need: Need) -> Color {
        switch need {
        case .notRecording: return MADTheme.Colors.madRed
        case .lobby, .invite: return Color(red: 0.16, green: 0.42, blue: 0.95)
        }
    }

    private func actionForeground(_ need: Need) -> Color {
        tint(need)
    }

    private func title(_ need: Need, host: BuddyParticipant?) -> String {
        let walkNoun = need.session.activityType == "running"
            ? String(localized: "buddy run") : String(localized: "buddy walk")
        switch need {
        case .notRecording:
            return String(localized: "Your \(walkNoun) has started")
        case .lobby(let session):
            if session.status == .active {
                return String(localized: "Your \(walkNoun) is starting")
            }
            return String(localized: "You're in a \(walkNoun) lobby")
        case .invite:
            guard let host else { return String(localized: "You're invited to a \(walkNoun)") }
            return String(localized: "\(host.displayName) invited you to a \(walkNoun)")
        }
    }

    private func subtitle(_ need: Need) -> String {
        switch need {
        case .notRecording:
            return String(localized: "Your phone isn't recording it yet. Tap to start — steps you've already taken get added.")
        case .lobby(let session):
            if session.status == .active {
                return String(localized: "Open it so your phone starts with everyone.")
            }
            let others = session.participants.filter {
                $0.userId != buddy.currentUserId
                    && ($0.status == .joined || $0.status == .ready || $0.status == .active)
            }
            if others.isEmpty { return String(localized: "Waiting for friends to join.") }
            return others.count == 1
                ? String(localized: "\(others[0].displayName) is in. Keep the app open when it starts.")
                : String(localized: "\(others.count) friends are in. Keep the app open when it starts.")
        case .invite(let session):
            let others = session.participants.filter {
                !session.isHost($0.userId) && $0.userId != buddy.currentUserId
                    && ($0.status == .joined || $0.status == .ready || $0.status == .active)
            }
            let base = session.status == .active
                ? String(localized: "They're out now — join and walk together.")
                : String(localized: "Join so you start together.")
            guard !others.isEmpty else { return base }
            return others.count == 1
                ? String(localized: "\(others[0].displayName) is going too. \(base)")
                : String(localized: "\(others.count) others are going. \(base)")
        }
    }

    private func actionTitle(_ need: Need) -> String {
        switch need {
        case .notRecording: return String(localized: "Start")
        case .lobby: return String(localized: "Open")
        case .invite: return String(localized: "Join")
        }
    }
}
