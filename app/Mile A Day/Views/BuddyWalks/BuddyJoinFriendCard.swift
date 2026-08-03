import SwiftUI

/// "Alex is walking right now."
///
/// The permission-free stand-in for ambient proximity sensing. Detecting nearby
/// friends in the background would need CoreBluetooth background advertising —
/// unreliable, battery-hungry, and a heavy privacy/App Review surface — and it
/// would only ever work for people physically next to you. This produces the
/// same "they're doing it, go with them" moment at any distance, for remote
/// friends too, and costs nothing but one pull on the dashboard.
///
/// It reads LIVE PRESENCE rather than buddy rooms. That distinction is the
/// whole point: the earlier version could only see friends already inside a
/// buddy session, so a friend out walking on their own — the single best person
/// to start a walk with — didn't appear at all. Now both show up, with the
/// action that fits:
///   - already in a room → **Join**
///   - out on their own  → **Ask to walk** (starts a session and invites them)
///
/// Renders nothing when nobody is out, so it never occupies dashboard space
/// speculatively.
struct BuddyJoinFriendCard: View {
    let hasActiveWorkout: Bool
    /// Called after a successful join so the dashboard can open the lobby.
    let onJoined: () -> Void

    @ObservedObject private var buddy = BuddySessionService.shared
    @State private var busyUserId: String?
    /// Friends we've already invited this session — the row stays, because they
    /// are still out and that's still true, but the button must not read as
    /// though nothing happened.
    @State private var askedUserIds: Set<String> = []

    var body: some View {
        if !hasActiveWorkout, !buddy.friendsOutNow.isEmpty {
            VStack(spacing: MADTheme.Spacing.sm) {
                ForEach(buddy.friendsOutNow) { friend in
                    row(friend)
                }
            }
        }
    }

    private func row(_ friend: FriendOutNow) -> some View {
        HStack(spacing: MADTheme.Spacing.md) {
            AvatarView(
                name: friend.displayName,
                imageURL: friend.profileImageUrl,
                size: 40
            )
            .overlay(alignment: .bottomTrailing) {
                Circle()
                    .fill(MADTheme.Colors.success)
                    .frame(width: 12, height: 12)
                    .overlay(Circle().stroke(MADTheme.Colors.madBlack, lineWidth: 2))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("\(friend.displayName) is \(friend.isRunning ? "running" : "walking")")
                    .font(MADTheme.Typography.smallBold)
                    .foregroundStyle(MADTheme.Colors.madWhite)
                    .lineLimit(1)

                Text(subtitle(friend))
                    .font(MADTheme.Typography.caption)
                    .foregroundStyle(MADTheme.Colors.madWhite.opacity(0.6))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            action(friend)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(Capsule().fill(Color.white.opacity(0.10)))
        .overlay(Capsule().stroke(Color.white.opacity(0.14), lineWidth: 1))
    }

    @ViewBuilder
    private func action(_ friend: FriendOutNow) -> some View {
        if busyUserId == friend.userId {
            ProgressView().tint(MADTheme.Colors.madWhite)
        } else if askedUserIds.contains(friend.userId) {
            Text("Invited")
                .font(MADTheme.Typography.smallBold)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Capsule().fill(Color.white.opacity(0.12)))
                .foregroundStyle(MADTheme.Colors.madWhite.opacity(0.7))
        } else {
            Button {
                Task { await act(friend) }
            } label: {
                Text(friend.hasJoinableRoom ? "Join" : "Ask to walk")
                    .font(MADTheme.Typography.smallBold)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(friend.accentColor))
                    .foregroundStyle(MADTheme.Colors.madWhite)
            }
            .buttonStyle(.plain)
            .disabled(busyUserId != nil)
        }
    }

    private func subtitle(_ friend: FriendOutNow) -> String {
        guard friend.hasJoinableRoom else {
            return "On their own — ask them to team up"
        }
        let others = max(0, (friend.buddyParticipantCount ?? 1) - 1)
        let people = others == 0
            ? "on their own"
            : (others == 1 ? "with 1 other" : "with \(others) others")
        let mode = friend.buddyMode?.title ?? "Buddy walk"
        return "\(mode) · \(people)"
    }

    private func act(_ friend: FriendOutNow) async {
        guard busyUserId == nil else { return }
        busyUserId = friend.userId
        defer { busyUserId = nil }

        do {
            if let sessionId = friend.buddySessionId {
                try await buddy.join(sessionId: sessionId)
                MADHaptics.success()
                // The offer is consumed either way — leaving it on screen reads
                // as though the tap did nothing.
                await buddy.refreshFriendsOutNow()
                onJoined()
            } else {
                try await buddy.askFriendToWalk(friend)
                MADHaptics.success()
                askedUserIds.insert(friend.userId)
                // Straight into the lobby: they've been invited, and the host
                // has nothing left to configure.
                onJoined()
            }
        } catch {
            MADHaptics.error()
            buddy.errorMessage =
                (error as? LocalizedError)?.errorDescription ?? "Couldn't do that."
            await buddy.refreshFriendsOutNow()
        }
    }
}
