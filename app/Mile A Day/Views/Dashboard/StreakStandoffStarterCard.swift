import SwiftUI

/// A brand-new user's one nudge toward the social loop: "Start a Streak
/// Standoff with a friend", with the two doors that get them there —
/// invite someone who isn't on the app yet, or pick a friend who is and land
/// on the Streak Standoff form with the preset applied (next tap: Create).
///
/// Mounted above the getting-started checklist, under the same new-account
/// gate (`DashboardView.gettingStartedSection`), and only while the user has
/// no competitions. Never blocking: the ✕ hides it for good, and so does
/// creating a standoff from it (`doneKey`).
///
/// Owns its own sheet so `DashboardView.body` gains no presentation modifier;
/// the card stays mounted while that sheet is up even if it would otherwise
/// hide, so the sheet is never torn down mid-create.
struct StreakStandoffStarterCard: View {
    /// Brand-new account with no competition yet (decided by the dashboard).
    let eligible: Bool
    let style: DashboardStyle
    /// The user's own handle, for the invite link. No handle, no invite door.
    let username: String?
    let friends: [BackendUser]
    /// No friends yet: "Find a friend" takes them to the Friends tab instead.
    let onFindFriends: () -> Void

    static let doneKey = "streakStandoffStarterDoneV1"
    @AppStorage(Self.doneKey) private var done = false
    @State private var createRequest: CreateRequest?

    struct CreateRequest: Identifiable {
        let id = UUID()
        /// The friend to pre-select when there is exactly one; otherwise the
        /// form opens straight onto its friend picker.
        let friend: BackendUser?
    }

    var body: some View {
        if (eligible && !done) || createRequest != nil {
            card
                .sheet(item: $createRequest) { request in
                    CreateCompetitionView(
                        onCreated: { id in
                            done = true
                            DeepLinkRouter.shared.requestOpenCompetitionAfterDismiss(id: id)
                        },
                        preselectedFriend: request.friend,
                        preset: .streakStandoff,
                        startsCollapsed: true,
                        opensFriendPicker: request.friend == nil
                    )
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "flame.fill")
                    .madFont(size: 18, weight: .bold, maxScale: 1.3)
                    .foregroundColor(MADTheme.Colors.madRed)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Start a Streak Standoff with a friend")
                        .madFont(size: 15, weight: .bold, design: .rounded)
                        .foregroundColor(.white)
                        .madBodyLines(2)
                    Text("A mile a day, three lives each. Last one standing wins.")
                        .madFont(size: 12, weight: .medium, design: .rounded)
                        .foregroundColor(.white.opacity(0.65))
                        .madBodyLines(3)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    withAnimation(.easeInOut(duration: 0.25)) { done = true }
                } label: {
                    Image(systemName: "xmark")
                        .madFont(size: 11, weight: .bold, maxScale: 1.3)
                        .foregroundColor(.white.opacity(0.55))
                        .padding(8)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Dismiss"))
            }

            // Side by side when both labels fit (most phones), stacked at
            // 320pt with large text — never a squeezed or truncated label.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { actions }
                VStack(spacing: 8) { actions }
            }
        }
        .padding(DashboardCardSurface.padding)
        .background(DashboardCardSurface(style: style))
    }

    @ViewBuilder
    private var actions: some View {
        if let username, !username.isEmpty {
            ShareLink(
                item: ReferralInvite.url(username: username),
                message: Text(ReferralInvite.message(username: username))
            ) {
                pill(String(localized: "Invite a friend"), icon: "square.and.arrow.up", filled: false)
            }
            .buttonStyle(.plain)
        }

        if friends.isEmpty {
            Button {
                MADHaptics.tap()
                onFindFriends()
            } label: {
                pill(String(localized: "Find a friend"), icon: "person.badge.plus", filled: true)
            }
            .buttonStyle(.plain)
        } else {
            Button {
                MADHaptics.tap()
                createRequest = CreateRequest(friend: friends.count == 1 ? friends.first : nil)
            } label: {
                pill(String(localized: "Pick a friend"), icon: "flame.fill", filled: true)
            }
            .buttonStyle(.plain)
        }
    }

    private func pill(_ title: String, icon: String, filled: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .madFont(size: 12, weight: .bold, maxScale: 1.3)
                .accessibilityHidden(true)
            Text(title)
                .madFont(size: 14, weight: .bold, design: .rounded)
                .lineLimit(1)
        }
        .foregroundColor(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity)
        .background(
            Capsule()
                .fill(filled ? MADTheme.Colors.madRed : Color.white.opacity(0.08))
        )
        .contentShape(Capsule())
    }
}
