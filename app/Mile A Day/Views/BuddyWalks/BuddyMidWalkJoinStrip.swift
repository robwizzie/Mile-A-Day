import SwiftUI

/// One tap into a buddy walk, from inside a workout that's already running.
///
/// Joining used to be a thing you could only do BEFORE setting off:
/// `BuddyJoinFriendCard` hides its action behind `hasActiveWorkout` ("you
/// cannot join a walk during a walk") and lives on the Friends tab, which is
/// not somewhere anyone navigates to mid-run — the tracker is a
/// `fullScreenCover`, so reaching it meant dismissing the workout screen. And
/// leaving was a one-way door: the roster vanished and nothing offered a way
/// back.
///
/// Both are the same missed moment. Two people who set off separately and
/// meet at the park, or one who steps out at the corner and catches up again,
/// are exactly the walks this feature exists for.
///
/// Nothing here starts or stops a workout. Joining ADOPTS the session into the
/// run already being recorded — the distance, the timer and the streak carry on
/// untouched — which is also why rejoining resumes rather than restarts: the
/// participant row keeps `distance_miles` through a leave, and the server takes
/// `GREATEST(stored, reported)` on the next progress tick.
///
/// **This view does NOT refresh `friendsOutNow` itself, on purpose.** Its body
/// renders nothing when there is nobody to join, and a view whose body is empty
/// gets no lifecycle at all — `.task` never fires (ios.md). A fetch hosted here
/// would therefore only ever run once the offer it was meant to discover had
/// already appeared. The tracker owns the refresh instead.
struct BuddyMidWalkJoinStrip: View {
    /// Called with the session id once the join lands, so the tracker can adopt
    /// it into the workout in flight.
    let onJoined: (String) -> Void

    @ObservedObject private var buddy = BuddySessionService.shared
    @State private var isBusy = false

    /// The walk this user just stepped out of, if it's still fresh enough to
    /// be worth offering back.
    private var rejoinId: String? { buddy.rejoinableSessionId }

    /// Otherwise, the nearest friend already in a room with space.
    ///
    /// Deliberately ONE, not a list: this sits above the distance readout on a
    /// screen someone is looking at while moving, and a scrollable picker there
    /// is a worse version of the Friends tab. The best single offer is the
    /// friend closest to finishing — they have the least time left to share.
    private var offer: FriendOutNow? {
        guard buddy.session == nil, rejoinId == nil else { return nil }
        return buddy.friendsOutNow
            .filter { $0.hasJoinableRoom }
            .max { ($0.distanceMiles ?? 0) / $0.goal < ($1.distanceMiles ?? 0) / $1.goal }
    }

    var body: some View {
        if let rejoinId {
            strip(
                icon: "arrow.uturn.left",
                title: "Rejoin your walk",
                subtitle: "You'll pick up right where you left off",
                action: { await join(sessionId: rejoinId) }
            )
        } else if let offer, let sessionId = offer.buddySessionId {
            strip(
                icon: "person.2.fill",
                title: "Join \(offer.displayName)",
                subtitle: "Walk together from here — your miles keep counting",
                action: { await join(sessionId: sessionId) }
            )
        }
    }

    private func strip(
        icon: String,
        title: String,
        subtitle: String,
        action: @escaping () async -> Void
    ) -> some View {
        Button {
            MADHaptics.tap()
            Task { await action() }
        } label: {
            HStack(spacing: MADTheme.Spacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .bold))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .opacity(0.75)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                Spacer(minLength: MADTheme.Spacing.xs)
                if isBusy {
                    ProgressView().tint(.white).controlSize(.small)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .opacity(0.8)
                }
            }
            .foregroundColor(.white)
            .padding(.horizontal, MADTheme.Spacing.md)
            .padding(.vertical, MADTheme.Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large, style: .continuous)
                    .fill(Color.white.opacity(0.16))
            )
            .overlay(
                RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
    }

    private func join(sessionId: String) async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            try await buddy.join(sessionId: sessionId)
            MADHaptics.success()
            onJoined(sessionId)
        } catch {
            MADHaptics.error()
            // The offer is stale — the walk ended, filled up, or this user was
            // removed from it. Clearing it is the honest outcome: leaving a
            // button that just failed is how a screen starts lying.
            buddy.clearRejoinOffer()
            await buddy.refreshFriendsOutNow()
            buddy.errorMessage =
                (error as? LocalizedError)?.errorDescription ?? "Couldn't join that walk."
        }
    }
}
