import SwiftUI

/// Settings ▸ Privacy ▸ Blocked accounts — the one place a block can be SEEN
/// or UNDONE. Blocking happens from a post's or story's ••• menu; until this
/// screen existed there was no way back from it at all.
///
/// Unblocking doesn't restore the friendship the block removed (the server
/// tore it down), so the confirmation says so rather than letting someone
/// expect their friend back.
struct BlockedUsersView: View {
    @State private var users: [BlockService.BlockedUser] = []
    @State private var isLoading = true
    @State private var loadFailed = false
    @State private var pendingUnblock: BlockService.BlockedUser?
    @State private var unblockingId: String?
    @State private var errorMessage: String?

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f
    }()

    var body: some View {
        ZStack {
            MADTheme.Colors.appBackgroundGradient.ignoresSafeArea()

            if isLoading && users.isEmpty {
                ProgressView().tint(.white)
            } else if loadFailed && users.isEmpty {
                emptyState(
                    icon: "wifi.exclamationmark",
                    title: "Couldn't load your blocked accounts",
                    detail: "Check your connection and try again."
                ) {
                    Button("Try again") { Task { await load() } }
                        .madPrimaryButton()
                }
            } else if users.isEmpty {
                emptyState(
                    icon: "hand.raised",
                    title: "You haven't blocked anyone",
                    detail: "To block someone, use the ••• menu on their post or story. They won't be told, and they'll stop seeing your activity."
                ) { EmptyView() }
            } else {
                List {
                    Section {
                        ForEach(users) { user in row(user) }
                    } footer: {
                        Text("Blocked accounts can't see your workouts, posts or stories, and you won't see theirs. They aren't told.")
                    }
                }
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle("Blocked accounts")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
        .confirmationDialog(
            pendingUnblock.map { "Unblock \($0.displayName)?" } ?? "",
            isPresented: Binding(get: { pendingUnblock != nil }, set: { if !$0 { pendingUnblock = nil } }),
            titleVisibility: .visible,
            presenting: pendingUnblock
        ) { user in
            Button("Unblock") { unblock(user) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("They'll be able to see your public activity again. You won't be friends again unless one of you sends a new request.")
        }
        .alert("Couldn't unblock", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func row(_ user: BlockService.BlockedUser) -> some View {
        HStack(spacing: MADTheme.Spacing.md) {
            AvatarView(name: user.displayName, imageURL: user.profileImageUrl, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(user.displayName)
                    .madFont(size: 17, weight: .semibold, design: .rounded)
                    .madNameLines()
                if let subtitle = subtitle(user) {
                    Text(subtitle)
                        .madFont(size: 12, design: .rounded)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }
            Spacer(minLength: 0)
            Button {
                MADHaptics.tap()
                pendingUnblock = user
            } label: {
                Group {
                    if unblockingId == user.userId {
                        ProgressView()
                    } else {
                        Text("Unblock")
                    }
                }
                .madFont(size: 14, weight: .semibold, design: .rounded)
                .frame(minWidth: 76, minHeight: 32)
                .background(Capsule().fill(Color.white.opacity(0.12)))
            }
            .buttonStyle(.plain)
            .disabled(unblockingId != nil)
            .accessibilityLabel("Unblock \(user.displayName)")
        }
        .padding(.vertical, 4)
    }

    private func subtitle(_ user: BlockService.BlockedUser) -> String? {
        let handle = user.username.map { "@\($0)" }
        let date = user.blockedAt
            .flatMap { ISO8601DateFormatter().date(from: $0) }
            .map { "Blocked \(Self.dateFormatter.string(from: $0))" }
        let parts = [handle, date].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func emptyState<Action: View>(
        icon: String, title: String, detail: String, @ViewBuilder action: () -> Action
    ) -> some View {
        VStack(spacing: MADTheme.Spacing.md) {
            Image(systemName: icon)
                .madFont(size: 34, weight: .semibold, maxScale: 1.5)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(title)
                .madFont(size: 17, weight: .semibold, design: .rounded)
                .multilineTextAlignment(.center)
            Text(detail)
                .madFont(size: 12, design: .rounded)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            action()
        }
        .padding(MADTheme.Spacing.xl)
    }

    private func load() async {
        isLoading = true
        do {
            users = try await BlockService.list()
            loadFailed = false
        } catch {
            loadFailed = true
        }
        isLoading = false
    }

    private func unblock(_ user: BlockService.BlockedUser) {
        unblockingId = user.userId
        Task {
            do {
                try await BlockService.unblock(userId: user.userId)
                MADHaptics.success()
                withAnimation { users.removeAll { $0.userId == user.userId } }
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? "Please try again."
            }
            unblockingId = nil
        }
    }
}
