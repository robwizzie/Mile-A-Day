import Combine
import SwiftUI

/// The waiting room: who's in, who's still deciding, and the host's start
/// button. Also renders the shared countdown once the host commits.
///
/// The countdown is driven by the server's `started_at`, which is stamped a few
/// seconds in the future — so every phone in the group hits zero on the same
/// wall-clock instant rather than whenever its own request happened to return.
struct BuddyLobbyView: View {
    /// Fires when the countdown reaches zero, handing the session to the
    /// tracker.
    let onStart: (BuddySessionState) -> Void

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var buddy = BuddySessionService.shared

    @State private var now = Date()
    @State private var hasHandedOff = false

    /// Drives the countdown text. Local ticking only — no network involved.
    private let tick = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    private var session: BuddySessionState? { buddy.session }

    var body: some View {
        ZStack {
            MADTheme.Colors.appBackgroundGradient.ignoresSafeArea()

            if let session {
                if let remaining = secondsUntilStart(session), remaining > 0 {
                    countdown(remaining: remaining, session: session)
                } else {
                    lobby(session)
                }
            } else {
                ProgressView().tint(MADTheme.Colors.madWhite)
            }
        }
        .onReceive(tick) { value in
            now = value
            handOffIfStarted()
        }
        .onAppear { buddy.startPolling() }
    }

    // MARK: - Countdown

    private func countdown(remaining: TimeInterval, session: BuddySessionState) -> some View {
        VStack(spacing: MADTheme.Spacing.lg) {
            Text("Starting together")
                .font(MADTheme.Typography.headline)
                .foregroundStyle(MADTheme.Colors.madWhite.opacity(0.8))

            Text("\(max(1, Int(remaining.rounded(.up))))")
                .font(.system(size: 120, weight: .bold, design: .rounded))
                .foregroundStyle(session.accentColor)
                .contentTransition(.numericText())
                .animation(MADTheme.Animation.quick, value: Int(remaining.rounded(.up)))

            Text(session.mode.title)
                .font(MADTheme.Typography.body)
                .foregroundStyle(MADTheme.Colors.madWhite.opacity(0.7))
        }
    }

    // MARK: - Lobby

    private func lobby(_ session: BuddySessionState) -> some View {
        VStack(spacing: MADTheme.Spacing.lg) {
            VStack(spacing: MADTheme.Spacing.xs) {
                Image(systemName: session.mode.icon)
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(session.accentColor)
                Text(session.mode.title)
                    .font(MADTheme.Typography.title2)
                    .foregroundStyle(MADTheme.Colors.madWhite)
                if let goal = session.goalValue {
                    Text(goalText(goal, mode: session.mode))
                        .font(MADTheme.Typography.body)
                        .foregroundStyle(MADTheme.Colors.madWhite.opacity(0.7))
                }
            }
            .padding(.top, MADTheme.Spacing.xl)

            joinCodeCard(session)

            ScrollView {
                VStack(spacing: MADTheme.Spacing.sm) {
                    ForEach(session.lobbyParticipants) { participant in
                        participantRow(participant, session: session)
                    }
                }
                .padding(.horizontal, MADTheme.Spacing.md)
            }

            Spacer(minLength: 0)

            actions(session)
                .padding(MADTheme.Spacing.md)
        }
    }

    private func joinCodeCard(_ session: BuddySessionState) -> some View {
        VStack(spacing: MADTheme.Spacing.xs) {
            Text("JOIN CODE")
                .font(MADTheme.Typography.caption)
                .foregroundStyle(MADTheme.Colors.madWhite.opacity(0.5))
            Text(session.joinCode)
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .tracking(6)
                .foregroundStyle(MADTheme.Colors.madWhite)
        }
        .padding(MADTheme.Spacing.md)
        .frame(maxWidth: .infinity)
        .madLiquidGlassCard()
        .padding(.horizontal, MADTheme.Spacing.md)
    }

    private func participantRow(_ participant: BuddyParticipant, session: BuddySessionState)
        -> some View
    {
        HStack(spacing: MADTheme.Spacing.md) {
            AvatarView(
                name: participant.displayName,
                imageURL: participant.profileImageUrl,
                size: 40
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(
                    participant.userId == buddy.currentUserId
                        ? "You" : participant.displayName
                )
                .font(MADTheme.Typography.bodyBold)
                .foregroundStyle(MADTheme.Colors.madWhite)

                if participant.isHost {
                    Text("Host")
                        .font(MADTheme.Typography.caption)
                        .foregroundStyle(session.accentColor)
                }
            }

            Spacer()

            statusChip(participant.status, accent: session.accentColor)
        }
        .padding(MADTheme.Spacing.sm)
        .madLiquidGlass(cornerRadius: MADTheme.CornerRadius.medium)
    }

    private func statusChip(_ status: BuddyParticipantStatus, accent: Color) -> some View {
        let (label, color): (String, Color) = {
            switch status {
            case .invited: return ("Invited", MADTheme.Colors.madWhite.opacity(0.4))
            case .joined: return ("In", accent)
            case .ready: return ("Ready", MADTheme.Colors.success)
            case .active: return ("Moving", MADTheme.Colors.success)
            case .finished: return ("Done", MADTheme.Colors.success)
            case .left, .declined: return ("Out", MADTheme.Colors.madWhite.opacity(0.3))
            }
        }()

        return Text(label)
            .font(MADTheme.Typography.caption)
            .padding(.horizontal, MADTheme.Spacing.sm)
            .padding(.vertical, 4)
            .background(Capsule().fill(color.opacity(0.2)))
            .foregroundStyle(color)
    }

    private func actions(_ session: BuddySessionState) -> some View {
        VStack(spacing: MADTheme.Spacing.sm) {
            if session.isHost(buddy.currentUserId) {
                Button {
                    Task {
                        MADHaptics.emphasis()
                        try? await buddy.start()
                    }
                } label: {
                    Text(readyCount(session) > 1 ? "Start together" : "Waiting for others…")
                        .font(MADTheme.Typography.bodyBold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, MADTheme.Spacing.md)
                        .background(Capsule().fill(session.accentColor))
                        .foregroundStyle(MADTheme.Colors.madWhite)
                }
                .buttonStyle(.plain)
                .disabled(readyCount(session) < 2)
                .opacity(readyCount(session) < 2 ? 0.5 : 1)
            } else {
                Text("Waiting for the host to start…")
                    .font(MADTheme.Typography.body)
                    .foregroundStyle(MADTheme.Colors.madWhite.opacity(0.7))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, MADTheme.Spacing.md)
            }

            Button("Leave") {
                Task {
                    await buddy.leave()
                    dismiss()
                }
            }
            .font(MADTheme.Typography.body)
            .foregroundStyle(MADTheme.Colors.madWhite.opacity(0.6))
        }
    }

    // MARK: - Helpers

    private func readyCount(_ session: BuddySessionState) -> Int {
        session.participants.filter { $0.status == .joined || $0.status == .ready }.count
    }

    private func secondsUntilStart(_ session: BuddySessionState) -> TimeInterval? {
        guard session.status == .active, let startedAt = session.startedAtDate else { return nil }
        return startedAt.timeIntervalSince(now)
    }

    /// Hand the session to the tracker exactly once, the instant the shared
    /// countdown elapses.
    private func handOffIfStarted() {
        guard !hasHandedOff, let session, session.status == .active else { return }
        guard let startedAt = session.startedAtDate, startedAt <= now else { return }
        hasHandedOff = true
        MADHaptics.success()
        onStart(session)
    }

    private func goalText(_ goal: Double, mode: BuddyMode) -> String {
        mode == .raceTime
            ? "\(Int(goal)) minutes"
            : String(format: "%.1f miles", goal)
    }
}
