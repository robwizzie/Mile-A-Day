import SwiftUI

/// Modal that lives behind the requests-badge button in the Friends header.
/// Combines the old Requests + Sent tabs into a single focused screen so the
/// main Friends view can stay on the social/activity surface.
struct FriendRequestsSheet: View {
    @ObservedObject var friendService: FriendService
    let onSelectUser: (BackendUser) -> Void
    // Async and returning an error message (nil on success). These used to be
    // fire-and-forget `(BackendUser) -> Void` whose callers swallowed every
    // error, so a failed accept looked like a dead button. The toast has to be
    // rendered HERE — this sheet covers FriendsListView, so feedback posted on
    // that view would be hidden behind this one.
    let onAccept: (BackendUser) async -> String?
    let onDecline: (BackendUser) async -> String?
    let onCancel: (BackendUser) async -> String?

    @Environment(\.dismiss) private var dismiss
    @State private var tab: Tab = .incoming
    @State private var feedback: NudgeFeedback?
    /// User ids with a request in flight — disables their buttons so a double
    /// tap can't fire two calls for the same person.
    @State private var inFlight: Set<String> = []

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

            if let feedback {
                VStack {
                    FriendRequestFeedbackBanner(feedback: feedback)
                        .padding(.horizontal, MADTheme.Spacing.md)
                        .padding(.top, MADTheme.Spacing.sm)
                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(100)
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

    // MARK: Actions

    /// Runs one request action, showing a toast if it fails. Success needs no
    /// toast — the row disappearing is the confirmation.
    private func run(
        _ user: BackendUser,
        _ action: @escaping (BackendUser) async -> String?
    ) {
        guard !inFlight.contains(user.user_id) else { return }
        inFlight.insert(user.user_id)
        Task {
            let errorMessage = await action(user)
            inFlight.remove(user.user_id)
            guard let errorMessage else { return }
            MADHaptics.error()
            withAnimation(.easeInOut(duration: 0.2)) {
                feedback = NudgeFeedback(
                    icon: "xmark.circle",
                    message: errorMessage,
                    isError: true
                )
            }
            try? await Task.sleep(nanoseconds: 2_800_000_000)
            withAnimation(.easeInOut(duration: 0.2)) { feedback = nil }
        }
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
                                    Button(action: { run(request, onAccept) }) {
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

                                    Button(action: { run(request, onDecline) }) {
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
                                .disabled(inFlight.contains(request.user_id))
                                .opacity(inFlight.contains(request.user_id) ? 0.5 : 1)
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
                                    action: { run(request, onCancel) }
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

/// Failure toast for the requests sheet. Mirrors the treatment of
/// FriendsListView's nudge banner (colored leading stripe over an
/// ultraThinMaterial card) so the two read as the same system toast — that one
/// is a private func on a view that this sheet covers, so it can't be reused
/// directly.
private struct FriendRequestFeedbackBanner: View {
    let feedback: NudgeFeedback

    var body: some View {
        let accent: Color = feedback.isError ? .red : .green
        return HStack(spacing: MADTheme.Spacing.sm) {
            RoundedRectangle(cornerRadius: 2)
                .fill(accent)
                .frame(width: 3, height: 28)
            Image(systemName: feedback.icon)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(accent)
            Text(feedback.message)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(MADTheme.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                        .strokeBorder(accent.opacity(0.35), lineWidth: 1)
                )
        )
    }
}
