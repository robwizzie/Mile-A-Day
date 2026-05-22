import SwiftUI

/// Modal that lives behind the requests-badge button in the Friends header.
/// Combines the old Requests + Sent tabs into a single focused screen so the
/// main Friends view can stay on the social/activity surface.
struct FriendRequestsSheet: View {
    @ObservedObject var friendService: FriendService
    let onSelectUser: (BackendUser) -> Void
    let onAccept: (BackendUser) -> Void
    let onDecline: (BackendUser) -> Void
    let onCancel: (BackendUser) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var tab: Tab = .incoming

    private enum Tab: String, CaseIterable, Identifiable {
        case incoming, sent
        var id: String { rawValue }
        var displayName: String { self == .incoming ? "Requests" : "Sent" }
    }

    var body: some View {
        ZStack {
            MADTheme.Colors.appBackgroundGradient
                .ignoresSafeArea()

            VStack(spacing: 0) {
                tabPicker

                Group {
                    switch tab {
                    case .incoming: incomingList
                    case .sent: sentList
                    }
                }
            }
        }
        .navigationTitle("Friend Requests")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
                    .foregroundColor(MADTheme.Colors.madRed)
                    .fontWeight(.semibold)
            }
        }
    }

    // MARK: Tab picker

    private var tabPicker: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases) { t in
                tabPill(t)
            }
        }
        .padding(3)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.06))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
        )
        .padding(.horizontal, MADTheme.Spacing.md)
        .padding(.top, MADTheme.Spacing.sm)
        .padding(.bottom, MADTheme.Spacing.sm)
    }

    private func tabPill(_ t: Tab) -> some View {
        let isSelected = tab == t
        let count = t == .incoming ? friendService.friendRequests.count : friendService.sentRequests.count
        return Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                tab = t
            }
        } label: {
            HStack(spacing: 6) {
                Text(t.displayName)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 10, weight: .heavy, design: .rounded))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(
                            Capsule()
                                .fill(isSelected ? Color.white.opacity(0.25) : MADTheme.Colors.madRed)
                        )
                }
            }
            .foregroundColor(isSelected ? .white : .white.opacity(0.5))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(
                Capsule()
                    .fill(isSelected ? MADTheme.Colors.madRed : Color.clear)
                    .shadow(color: isSelected ? MADTheme.Colors.madRed.opacity(0.35) : .clear, radius: 6, y: 2)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: Incoming requests

    @ViewBuilder
    private var incomingList: some View {
        if friendService.friendRequests.isEmpty {
            FriendEmptyStateView(
                title: "No Friend Requests",
                message: "You don't have any pending friend requests at the moment.",
                systemImage: "person.crop.circle.badge.exclamationmark"
            )
        } else {
            ScrollView {
                LazyVStack(spacing: MADTheme.Spacing.md) {
                    ForEach(friendService.friendRequests) { request in
                        UserProfileCard(
                            user: request,
                            showDetails: false,
                            onTap: { onSelectUser(request) },
                            actionButton: AnyView(
                                VStack(spacing: MADTheme.Spacing.sm) {
                                    Button(action: { onAccept(request) }) {
                                        HStack(spacing: MADTheme.Spacing.xs) {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 12, weight: .semibold))
                                            Text("Accept")
                                                .font(MADTheme.Typography.smallBold)
                                        }
                                        .foregroundColor(.white)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, MADTheme.Spacing.sm)
                                        .background(
                                            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.small)
                                                .fill(Color.green)
                                        )
                                    }
                                    .buttonStyle(.plain)

                                    Button(action: { onDecline(request) }) {
                                        HStack(spacing: MADTheme.Spacing.xs) {
                                            Image(systemName: "xmark")
                                                .font(.system(size: 12, weight: .semibold))
                                            Text("Decline")
                                                .font(MADTheme.Typography.smallBold)
                                        }
                                        .foregroundColor(.white.opacity(0.7))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, MADTheme.Spacing.sm)
                                        .background(
                                            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.small)
                                                .fill(Color.red.opacity(0.2))
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: MADTheme.CornerRadius.small)
                                                        .stroke(Color.red.opacity(0.4), lineWidth: 1)
                                                )
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                                .frame(width: 90)
                            )
                        )
                    }
                }
                .padding(MADTheme.Spacing.md)
            }
        }
    }

    // MARK: Sent requests

    @ViewBuilder
    private var sentList: some View {
        if friendService.sentRequests.isEmpty {
            FriendEmptyStateView(
                title: "No Sent Requests",
                message: "You haven't sent any friend requests yet.",
                systemImage: "paperplane"
            )
        } else {
            ScrollView {
                LazyVStack(spacing: MADTheme.Spacing.md) {
                    ForEach(friendService.sentRequests) { request in
                        UserProfileCard(
                            user: request,
                            onTap: { onSelectUser(request) },
                            actionButton: AnyView(
                                FriendActionButton(
                                    title: "Cancel",
                                    style: .secondary,
                                    action: { onCancel(request) }
                                )
                            )
                        )
                    }
                }
                .padding(MADTheme.Spacing.md)
            }
        }
    }
}
