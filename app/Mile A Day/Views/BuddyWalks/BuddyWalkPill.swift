import SwiftUI

extension Notification.Name {
    /// Posted by `BuddyWalkPill`; consumed by `DashboardView`.
    ///
    /// Uses NotificationCenter rather than a binding because the pill renders
    /// inside two different dashboard styles (Modern and Fun), each several
    /// view layers below `DashboardView` — the same reason `MAD_SwitchTab` and
    /// `MAD_OpenWorkoutFromLiveActivity` exist.
    static let madStartBuddyWalk = Notification.Name("MAD_StartBuddyWalk")

    /// Posted after joining a friend's in-flight walk; DashboardView opens the
    /// lobby. Separate from `madStartBuddyWalk` because the session already
    /// exists — there is nothing left to configure.
    static let madOpenBuddyLobby = Notification.Name("MAD_OpenBuddyLobby")
}

/// An unanswered buddy invite, sitting under the start button.
///
/// This used to be the standing "Walk with a buddy" entry point. Starting one
/// now lives inside the Start Mile wizard, next to Run and Walk — which is both
/// more discoverable and, unlike this pill, present on BOTH dashboard styles.
///
/// What can't move is an INVITE. Someone waiting on an answer is time-critical
/// in a way that browsing to a feature isn't, and it would be invisible until
/// the user happened to tap Start Mile. So the pill survives for exactly that
/// case and renders nothing otherwise.
///
/// Three states, in priority order — the walk you are ALREADY in outranks an
/// invitation, which outranks a friend you could go and find:
///
///  1. **Live** — you're in a walk right now and this screen is not it. Closing
///     the tracker used to strand people: the session ran on, the roster was
///     nowhere, and the way back was to guess at Start Mile. This is the way
///     back.
///  2. **Invited** — someone is waiting on an answer, which is time-critical in
///     a way that browsing to a feature isn't.
///  3. **Friends out** — somebody is in a room with space right now. This is
///     the whole "they're doing it, go with them" moment, and it used to live
///     only on the Friends tab.
///
/// Hidden while a workout is in progress — but that is no longer because you
/// "cannot join mid-mile" (you can: `BuddyMidWalkJoinStrip` does exactly that).
/// It's because the tracker is the screen you're looking at then, and it
/// carries its own offer; two buttons for one action on two screens is how they
/// drift apart.
struct BuddyWalkPill: View {
    let hasActiveWorkout: Bool

    @ObservedObject private var buddy = BuddySessionService.shared

    /// Friends in a room with space left, right now.
    private var joinableCount: Int {
        buddy.friendsOutNow.filter(\.hasJoinableRoom).count
    }

    private var isLive: Bool { buddy.canReenterLiveSession }

    private var hasSomethingToShow: Bool {
        isLive || inviteCount > 0 || joinableCount > 0
    }

    var body: some View {
        if !hasActiveWorkout, hasSomethingToShow {
            Button {
                MADHaptics.tap()
                // One destination for all three states. `madStartBuddyWalk`
                // already routes a re-enterable session straight to the lobby
                // and everything else to the start sheet (BuddyFlowModifier),
                // so the pill does not need to know which it is.
                NotificationCenter.default.post(name: .madStartBuddyWalk, object: nil)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isLive ? "figure.walk.motion" : "figure.2")
                        .font(.system(size: 13, weight: .bold))

                    Text(title)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    // The count belongs to a WAITING thing — an invite, or a
                    // friend you could go and join. A walk you're already in is
                    // one walk; badging it "1" would read as a notification.
                    if let count = badgeCount {
                        Text("\(count)")
                            .font(.system(size: 11, weight: .black, design: .rounded))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(MADTheme.Colors.madRed))
                    }

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .background(
                    Capsule().fill(Color.white.opacity(0.10))
                )
                .overlay(
                    Capsule().stroke(Color.white.opacity(0.14), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var inviteCount: Int { buddy.invites.count }

    private var badgeCount: Int? {
        if isLive { return nil }
        if inviteCount > 0 { return inviteCount }
        return joinableCount > 0 ? joinableCount : nil
    }

    private var title: String {
        if isLive { return "Back to your walk" }
        if inviteCount > 0 {
            return inviteCount == 1 ? "Buddy walk invite" : "Buddy walk invites"
        }
        return joinableCount == 1 ? "A friend is out — join" : "Friends are out — join"
    }
}
