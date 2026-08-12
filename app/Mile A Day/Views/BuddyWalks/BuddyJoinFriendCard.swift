import SwiftUI

/// "Alex is walking right now — 0.62 of 1 mi."
///
/// The permission-free stand-in for ambient proximity sensing. Detecting nearby
/// friends in the background would need CoreBluetooth background advertising —
/// unreliable, battery-hungry, and a heavy privacy/App Review surface — and it
/// would only ever work for people physically next to you. This produces the
/// same "they're doing it, go with them" moment at any distance, for remote
/// friends too, and costs nothing but one pull.
///
/// It reads LIVE PRESENCE rather than buddy rooms, so a friend out walking on
/// their own — the single best person to start a walk with — appears alongside
/// one already in a room, each with the action that fits.
///
/// **Density.** A popular user can have a dozen friends out at once, and twelve
/// full-width rows is a wall that buries whatever was below it. Past
/// `collapseThreshold` the list shows the closest-to-finishing few and folds the
/// rest behind one line, because "who is nearly done" is the group most worth
/// cheering and the one where a hype lands while it still counts.
struct BuddyJoinFriendCard: View {
    /// Hides the Join/Ask action — you cannot join a walk during a walk. The
    /// rows still render: seeing a friend is out is useful mid-workout too,
    /// and hyping them from there is the whole point of the tracker's sheet.
    let hasActiveWorkout: Bool
    /// Called after a successful join so the host surface can open the lobby.
    let onJoined: () -> Void

    @ObservedObject private var buddy = BuddySessionService.shared
    @State private var busyUserId: String?
    /// Friends we've already invited — the row stays, because they are still
    /// out and that's still true, but the button must not read as though
    /// nothing happened.
    @State private var askedUserIds: Set<String> = []
    @State private var hypedUserIds: Set<String> = []
    @State private var sendingHypeUserIds: Set<String> = []
    @State private var expanded = false

    private static let collapseThreshold = 3

    /// Closest to finishing first. Someone at 0.9 mi is minutes from a
    /// celebration; someone at 0.05 has half an hour to go.
    private var ordered: [FriendOutNow] {
        buddy.friendsOutNow.sorted {
            ($0.distanceMiles ?? 0) / $0.goal > ($1.distanceMiles ?? 0) / $1.goal
        }
    }

    private var visible: [FriendOutNow] {
        guard ordered.count > Self.collapseThreshold, !expanded else { return ordered }
        return Array(ordered.prefix(Self.collapseThreshold))
    }

    var body: some View {
        if !buddy.friendsOutNow.isEmpty {
            VStack(spacing: MADTheme.Spacing.sm) {
                ForEach(visible) { friend in
                    row(friend)
                }

                if ordered.count > Self.collapseThreshold {
                    Button {
                        MADHaptics.tap()
                        withAnimation(MADTheme.Animation.standard) { expanded.toggle() }
                    } label: {
                        HStack(spacing: 6) {
                            Text(
                                expanded
                                    ? "Show fewer"
                                    : "\(ordered.count - Self.collapseThreshold) more out right now"
                            )
                            Image(systemName: expanded ? "chevron.up" : "chevron.down")
                                .font(.system(size: 10, weight: .bold))
                        }
                        .font(MADTheme.Typography.caption)
                        .foregroundStyle(MADTheme.Colors.madWhite.opacity(0.6))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func row(_ friend: FriendOutNow) -> some View {
        FriendOutLiveRow(
            name: friend.displayName,
            imageURL: friend.profileImageUrl,
            isRunning: friend.isRunning,
            distanceMiles: friend.distanceMiles,
            goalMiles: friend.goal,
            subtitle: subtitle(friend),
            canJoin: !hasActiveWorkout && !askedUserIds.contains(friend.userId),
            joinTitle: friend.hasJoinableRoom ? "Join" : "Ask to walk",
            onJoin: { Task { await act(friend) } },
            onHype: { Task { await hype(friend) } },
            hyped: hypedUserIds.contains(friend.userId),
            hypeBusy: sendingHypeUserIds.contains(friend.userId),
            busy: busyUserId == friend.userId
        )
    }

    private func subtitle(_ friend: FriendOutNow) -> String {
        if askedUserIds.contains(friend.userId) { return "Invited — waiting on them" }
        let elapsed = FriendOutTime.elapsed(since: friend.startedAt)
        guard friend.hasJoinableRoom else {
            return elapsed ?? "On their own"
        }
        let others = max(0, (friend.buddyParticipantCount ?? 1) - 1)
        let people = others == 0
            ? "on their own"
            : (others == 1 ? "with 1 other" : "with \(others) others")
        return [friend.buddyMode?.title ?? "Buddy walk", people].joined(separator: " · ")
    }

    /// Hype a friend mid-walk.
    ///
    /// Uses the SAME 'mile' composite the rest of the app does
    /// (`<userId>:<localDate>`) rather than a bespoke context, so it dedupes
    /// against a hype sent from the feed for the same day and lands on their
    /// tracking screen through LivePresenceService's hype poll. The local_date
    /// has to be THEIRS, not the viewer's — the server keys on the walker's day.
    private func hype(_ friend: FriendOutNow) async {
        guard !hypedUserIds.contains(friend.userId),
              !sendingHypeUserIds.contains(friend.userId) else { return }
        // Optimistic: a clap that waits on the network reads as a dead button,
        // and the failure path below puts it back.
        hypedUserIds.insert(friend.userId)
        sendingHypeUserIds.insert(friend.userId)
        MADHaptics.success()
        defer { sendingHypeUserIds.remove(friend.userId) }
        do {
            if let localDate = friend.localDate {
                _ = try await HypeService.sendHype(
                    targetUserId: friend.userId,
                    context: HypeContext(
                        contextType: "mile",
                        contextId: "\(friend.userId):\(localDate)",
                        contextLabel: friend.isRunning ? "run" : "walk"
                    )
                )
            } else {
                // Older server build with no local_date on the wire. The
                // context-less path still reaches them.
                _ = try await HypeService.sendHype(targetUserId: friend.userId)
            }
        } catch APIError.conflict {
            // Already hyped this live mile today. Keep the button locked so a
            // refresh or re-render cannot turn the conflict into a spam button.
            hypedUserIds.insert(friend.userId)
        } catch {
            hypedUserIds.remove(friend.userId)
            MADHaptics.error()
            buddy.errorMessage =
                (error as? LocalizedError)?.errorDescription ?? "Couldn't send that."
        }
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
