import SwiftUI

/// "Alex is walking right now — join?"
///
/// The permission-free stand-in for ambient proximity sensing. Detecting nearby
/// friends in the background would need CoreBluetooth background advertising —
/// unreliable, battery-hungry, and a heavy privacy/App Review surface — and it
/// would only ever work for people physically next to you. This produces the
/// same "they're doing it, join them" moment at any distance, for remote
/// friends too, and costs nothing but one pull on the dashboard.
///
/// Renders nothing when no friend is mid-walk, so it never occupies dashboard
/// space speculatively.
struct BuddyJoinFriendCard: View {
    let hasActiveWorkout: Bool
    /// Called after a successful join so the dashboard can open the lobby.
    let onJoined: () -> Void

    @ObservedObject private var buddy = BuddySessionService.shared
    @State private var joiningSessionId: String?

    var body: some View {
        if !hasActiveWorkout, !buddy.joinableFriendSessions.isEmpty {
            VStack(spacing: MADTheme.Spacing.sm) {
                ForEach(buddy.joinableFriendSessions) { session in
                    row(session)
                }
            }
        }
    }

    private func row(_ session: JoinableFriendSession) -> some View {
        Button {
            Task { await join(session) }
        } label: {
            HStack(spacing: MADTheme.Spacing.md) {
                AvatarView(
                    name: session.hostDisplayName,
                    imageURL: session.hostProfileImageUrl,
                    size: 40
                )
                .overlay(alignment: .bottomTrailing) {
                    Circle()
                        .fill(MADTheme.Colors.success)
                        .frame(width: 12, height: 12)
                        .overlay(Circle().stroke(MADTheme.Colors.madBlack, lineWidth: 2))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(session.hostDisplayName) is \(session.isRunning ? "running" : "walking")")
                        .font(MADTheme.Typography.smallBold)
                        .foregroundStyle(MADTheme.Colors.madWhite)
                        .lineLimit(1)

                    Text(subtitle(session))
                        .font(MADTheme.Typography.caption)
                        .foregroundStyle(MADTheme.Colors.madWhite.opacity(0.6))
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                if joiningSessionId == session.sessionId {
                    ProgressView().tint(MADTheme.Colors.madWhite)
                } else {
                    Text("Join")
                        .font(MADTheme.Typography.smallBold)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(session.accentColor))
                        .foregroundStyle(MADTheme.Colors.madWhite)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(Capsule().fill(Color.white.opacity(0.10)))
            .overlay(Capsule().stroke(Color.white.opacity(0.14), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(joiningSessionId != nil)
    }

    private func subtitle(_ session: JoinableFriendSession) -> String {
        let others = max(0, session.participantCount - 1)
        let people = others == 0
            ? "on their own"
            : (others == 1 ? "with 1 other" : "with \(others) others")
        return session.status == .lobby
            ? "Waiting to start · \(people)"
            : "\(session.mode.title) · \(people)"
    }

    private func join(_ session: JoinableFriendSession) async {
        guard joiningSessionId == nil else { return }
        joiningSessionId = session.sessionId
        defer { joiningSessionId = nil }
        do {
            try await buddy.join(sessionId: session.sessionId)
            MADHaptics.success()
            // The offer is consumed either way — leave it on screen and it
            // reads as though the tap did nothing.
            await buddy.refreshJoinableFriendSessions()
            onJoined()
        } catch {
            MADHaptics.error()
            buddy.errorMessage =
                (error as? LocalizedError)?.errorDescription ?? "Couldn't join."
            await buddy.refreshJoinableFriendSessions()
        }
    }
}
