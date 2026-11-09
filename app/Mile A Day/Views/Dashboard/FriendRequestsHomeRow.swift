import SwiftUI

/// Pending friend requests on Home, one line, UNDER the day's Start button.
/// It used to lead the attention slot above the hero, which on a short
/// screen pushed Start under the tab bar: the day's action now comes first
/// and the inbox right after it. Draws nothing when there are no requests
/// (a bare conditional, never an empty stack, so it costs no gap).
struct FriendRequestsHomeRow: View {
    @ObservedObject var friendService: FriendService

    var body: some View {
        let requests = friendService.friendRequests
        if !requests.isEmpty {
            Button {
                // Park the intent BEFORE switching tabs: FriendsListView may
                // not exist yet, and reads the flag in .task when it mounts.
                DeepLinkRouter.shared.requestOpenFriendRequests()
                NotificationCenter.default.post(
                    name: NSNotification.Name("MAD_SwitchTab"),
                    object: nil,
                    userInfo: ["tab": 3]
                )
            } label: {
                HStack(spacing: MADTheme.Spacing.sm) {
                    // SF Symbols 1 name: newer ones render blank on iOS 17.
                    Image(systemName: "person.crop.circle.badge.plus")
                        .madFont(size: 15, weight: .bold, maxScale: 1.15)
                        .foregroundColor(MADTheme.Colors.madRed)
                        .accessibilityHidden(true)
                    Group {
                        if requests.count == 1 { Text("Friend request") } else { Text("\(requests.count) friend requests") }
                    }
                    .madFont(size: 14, weight: .bold, design: .rounded)
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .layoutPriority(1)
                    if requests.count == 1, let name = requests.first?.displayName {
                        Text(verbatim: "· \(name)")
                            .madFont(size: 13, weight: .medium, design: .rounded)
                            .foregroundColor(.white.opacity(0.55))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .madFont(size: 11, weight: .bold, maxScale: 1.15)
                        .foregroundColor(.white.opacity(0.4))
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, MADTheme.Spacing.md)
                .frame(minHeight: 44)
                .background(
                    RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                        .fill(Color.white.opacity(0.04))
                        .overlay(
                            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                                .strokeBorder(MADTheme.Colors.madRed.opacity(0.3), lineWidth: 1)
                        )
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens your friend requests")
        }
    }
}
