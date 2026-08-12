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
/// Still hidden while a workout is in progress: you cannot join a buddy walk
/// mid-mile, and the single-workout lock would refuse.
struct BuddyWalkPill: View {
    let hasActiveWorkout: Bool

    @ObservedObject private var buddy = BuddySessionService.shared

    var body: some View {
        if !hasActiveWorkout, inviteCount > 0 {
            Button {
                MADHaptics.tap()
                NotificationCenter.default.post(name: .madStartBuddyWalk, object: nil)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "figure.2")
                        .font(.system(size: 13, weight: .bold))

                    Text(title)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    Text("\(inviteCount)")
                        .font(.system(size: 11, weight: .black, design: .rounded))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(MADTheme.Colors.madRed))

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

    private var title: String {
        inviteCount == 1 ? "Buddy walk invite" : "Buddy walk invites"
    }
}
