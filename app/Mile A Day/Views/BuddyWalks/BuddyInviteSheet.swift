import SwiftUI

/// Invite friends into the walk you're already on.
///
/// Presented from the tracker's roster strip, which is the screen a walker is
/// actually looking at once a buddy walk has started. Until now the only
/// invite affordance was the lobby's tap-to-invite faces, and the lobby is
/// gone the instant the host presses Start — so mid-walk the feature reduced
/// to "text Sam and hope he finds the Join button".
///
/// Anyone in the walk can invite, not only the host: the server judges each
/// invitee against the person tapping (their friend, unblocked, opted in), so
/// a guest pulling in their own friend is exactly as valid as the host doing
/// it. Somebody already waiting at the door (a join request) is shown here
/// too and inviting them IS letting them in — the server folds that case.
///
/// Feedback renders INSIDE this sheet. A toast on the tracker beneath is
/// invisible while a sheet is up (ios.md).
struct BuddyInviteSheet: View {
    let session: BuddySessionState

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var buddy = BuddySessionService.shared
    @State private var invitingIds: Set<String> = []
    /// Sent this session. Optimistic: the roster's next poll confirms it, but
    /// a button that waits on a round trip reads as a dead tap.
    @State private var invitedIds: Set<String> = []
    @State private var errorText: String?

    /// The live roster if the service has it (it moves as people accept),
    /// else the snapshot this sheet was opened with.
    private var current: BuddySessionState {
        buddy.session?.id == session.id ? (buddy.session ?? session) : session
    }

    private var invitable: [BuddyCandidate] {
        let present = Set(current.lobbyParticipants.map(\.userId))
        return buddy.candidates.filter { !present.contains($0.userId) }
    }

    private var waiting: [BuddyJoinRequest] { current.pendingJoinRequests }

    var body: some View {
        NavigationStack {
            ZStack {
                MADTheme.Colors.appBackgroundGradient.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
                        Text(
                            current.status == .active
                                ? "They'll land straight on the walk when they accept."
                                : "They'll get an invite and can join the lobby."
                        )
                        .font(MADTheme.Typography.caption)
                        .foregroundStyle(MADTheme.Colors.madWhite.opacity(0.6))
                        .padding(.horizontal, MADTheme.Spacing.md)

                        if !waiting.isEmpty {
                            sectionLabel("Asked to join")
                            ForEach(waiting) { request in
                                row(
                                    name: request.displayName,
                                    imageURL: request.profileImageUrl,
                                    streak: nil,
                                    userId: request.userId,
                                    actionTitle: "Let in"
                                )
                            }
                        }

                        sectionLabel("Friends")
                        if invitable.isEmpty {
                            Text(
                                buddy.candidates.isEmpty
                                    ? "No friends available to invite right now. Friends need the latest Mile A Day and buddy invites turned on."
                                    : "Everyone you can invite is already in."
                            )
                            .font(MADTheme.Typography.caption)
                            .foregroundStyle(MADTheme.Colors.madWhite.opacity(0.5))
                            .padding(.horizontal, MADTheme.Spacing.md)
                        } else {
                            ForEach(invitable) { candidate in
                                row(
                                    name: candidate.displayName,
                                    imageURL: candidate.profileImageUrl,
                                    streak: candidate.currentStreak,
                                    userId: candidate.userId,
                                    actionTitle: "Invite"
                                )
                            }
                        }
                    }
                    .padding(.vertical, MADTheme.Spacing.md)
                }
            }
            .navigationTitle("Invite to this \(current.isRunning ? "run" : "walk")")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                }
            }
            .alert(
                "Couldn't invite",
                isPresented: Binding(
                    get: { errorText != nil },
                    set: { if !$0 { errorText = nil } }
                )
            ) {
                Button("OK", role: .cancel) { errorText = nil }
            } message: {
                Text(errorText ?? "")
            }
        }
        // The picker list is warmed by the dashboard, but this sheet can be
        // the first buddy surface opened after a cold launch into a recovered
        // workout — so it fetches too. Idempotent.
        .task { await buddy.loadCandidates() }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .heavy, design: .rounded))
            .tracking(1.2)
            .foregroundStyle(MADTheme.Colors.madWhite.opacity(0.5))
            .padding(.horizontal, MADTheme.Spacing.md)
    }

    private func row(
        name: String,
        imageURL: String?,
        streak: Int?,
        userId: String,
        actionTitle: String
    ) -> some View {
        let sending = invitingIds.contains(userId)
        let sent = invitedIds.contains(userId)
        return HStack(spacing: MADTheme.Spacing.md) {
            AvatarView(name: name, imageURL: imageURL, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(MADTheme.Typography.smallBold)
                    .foregroundStyle(MADTheme.Colors.madWhite)
                    .lineLimit(1)
                if let streak, streak > 0 {
                    StreakFlameChip(streak: streak)
                }
            }
            Spacer(minLength: MADTheme.Spacing.xs)
            Button {
                guard !sending, !sent else { return }
                MADHaptics.action()
                send(userId)
            } label: {
                Group {
                    if sending {
                        ProgressView().tint(MADTheme.Colors.madWhite)
                    } else {
                        Text(sent ? "Sent" : actionTitle)
                            .font(MADTheme.Typography.smallBold)
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 14)
                .frame(height: 34)
                .background(
                    Capsule().fill(
                        sent ? MADTheme.Colors.madWhite.opacity(0.12) : session.accentColor))
                .foregroundStyle(
                    sent ? MADTheme.Colors.madWhite.opacity(0.6) : MADTheme.Colors.madWhite)
            }
            .buttonStyle(.plain)
            .disabled(sending || sent)
            .fixedSize()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large, style: .continuous)
                .fill(MADTheme.Colors.madWhite.opacity(0.08))
        )
        .padding(.horizontal, MADTheme.Spacing.md)
    }

    private func send(_ userId: String) {
        invitingIds.insert(userId)
        Task {
            do {
                _ = try await buddy.invite(userIds: [userId], sessionId: session.id)
                MADHaptics.success()
                invitedIds.insert(userId)
            } catch {
                MADHaptics.error()
                errorText =
                    (error as? LocalizedError)?.errorDescription ?? "Couldn't invite them."
            }
            invitingIds.remove(userId)
        }
    }
}
