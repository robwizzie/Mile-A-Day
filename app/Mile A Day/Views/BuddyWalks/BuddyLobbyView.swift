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
    @State private var qrImage: UIImage?
    @State private var didCopy = false
    @State private var showGhostSetup = false

    /// Ghost race arming for THIS buddy walk.
    ///
    /// The solo flow arms from a card on the location-picker screen — which a
    /// buddy session never renders, because the hand-off jumps straight to
    /// tracking. The lobby is the one screen every buddy session passes
    /// through (start sheet → lobby → tracker, and a pushed/deep-linked invite
    /// lands here too), so this is where the choice belongs.
    ///
    /// Stored rather than passed because the tracker is presented by
    /// `BuddyFlowModifier`, not by this view — there's no parameter to hand it
    /// through. It's re-decided every session since the lobby always runs
    /// first, so a stale `true` can't leak into a walk the user didn't arm.
    @AppStorage("buddyGhostArmedV1") private var buddyGhostArmed = false
    /// The SAME keys the solo path uses, so "race 12:00" means one thing
    /// everywhere rather than two settings that drift apart.
    @AppStorage("ghostTargetV1.running") private var runTargetStorage = ""
    @AppStorage("ghostTargetV1.walking") private var walkTargetStorage = ""

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

            inviteCard(session)

            ghostRaceRow(session)
                .padding(.horizontal, MADTheme.Spacing.md)

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

    // MARK: - Ghost race

    /// Race your own ghost alongside your buddies.
    ///
    /// Two different races at once, and they don't compete for attention: the
    /// roster answers "how am I doing against them", the delta chip answers
    /// "how am I doing against me". A buddy walk already feeds
    /// `BestEffortStore.recordFinish` — this just lets it race what it feeds.
    private func ghostRaceRow(_ session: BuddySessionState) -> some View {
        Button {
            MADHaptics.action()
            showGhostSetup = true
        } label: {
            HStack(spacing: MADTheme.Spacing.md) {
                ZStack {
                    Circle()
                        .fill(
                            buddyGhostArmed
                                ? session.accentColor.opacity(0.25)
                                : Color.white.opacity(0.10)
                        )
                        .frame(width: 34, height: 34)
                    GhostSprite(
                        size: 17,
                        color: buddyGhostArmed ? session.accentColor : .white.opacity(0.7),
                        floats: false,
                        glancesBack: true
                    )
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text("Race your ghost")
                        .font(MADTheme.Typography.smallBold)
                        .foregroundStyle(MADTheme.Colors.madWhite)
                    Text(ghostSubtitle(session))
                        .font(MADTheme.Typography.caption)
                        .foregroundStyle(MADTheme.Colors.madWhite.opacity(0.6))
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                if buddyGhostArmed, let ghost = resolvedGhost(session) {
                    Text(BestEffortStore.formatSeconds(ghost.effort.seconds))
                        .font(MADTheme.Typography.smallBold)
                        .monospacedDigit()
                        .foregroundStyle(session.accentColor)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(Capsule().fill(Color.white.opacity(0.08)))
            .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1))
        }
        .buttonStyle(.plain)
        // Its own presentation node: this view already owns a ShareLink and
        // the flow that presents it stacks covers elsewhere, and two sheets on
        // one node makes SwiftUI silently drop one.
        .background(
            Color.clear
                .sheet(isPresented: $showGhostSetup) {
                    GhostRaceSetupSheet(
                        activityKey: ghostActivityKey(session),
                        seedPaceSeconds: ghostSeedPaceSeconds,
                        current: buddyGhostArmed ? storedGhostTarget(session) : nil
                    ) { chosen in
                        if let chosen {
                            storeGhostTarget(chosen, session: session)
                            buddyGhostArmed = true
                        } else {
                            buddyGhostArmed = false
                        }
                        showGhostSetup = false
                    }
                }
        )
    }

    private func ghostActivityKey(_ session: BuddySessionState) -> String {
        session.isRunning ? "running" : "walking"
    }

    /// Backend fastest-mile PR (minutes/mile on the user model → seconds).
    private var ghostSeedPaceSeconds: Double? {
        let pace = UserManager.shared.currentUser.fastestMilePace
        return pace > 0 ? pace * 60 : nil
    }

    private func storedGhostTarget(_ session: BuddySessionState)
        -> BestEffortStore.GhostTarget?
    {
        let raw = ghostActivityKey(session) == "running"
            ? runTargetStorage : walkTargetStorage
        return BestEffortStore.GhostTarget(storage: raw)
    }

    private func storeGhostTarget(
        _ target: BestEffortStore.GhostTarget, session: BuddySessionState
    ) {
        if ghostActivityKey(session) == "running" {
            runTargetStorage = target.storage
        } else {
            walkTargetStorage = target.storage
        }
    }

    private func resolvedGhost(_ session: BuddySessionState)
        -> BestEffortStore.ResolvedGhost?
    {
        guard let target = storedGhostTarget(session) else { return nil }
        return BestEffortStore.resolve(
            target,
            activityKey: ghostActivityKey(session),
            seedPaceSecondsPerMile: ghostSeedPaceSeconds
        )
    }

    private func ghostSubtitle(_ session: BuddySessionState) -> String {
        guard buddyGhostArmed, let ghost = resolvedGhost(session) else {
            return "Chase your own time while you walk together"
        }
        return "Chasing \(ghost.shortName)"
    }

    /// The invite moment — the whole reason a lobby exists.
    ///
    /// This used to be the code as static text: nothing to tap, nothing to
    /// send, no way to get anyone in except reading six characters aloud. A
    /// lobby nobody can be invited to is a lobby nobody uses. Three ways in,
    /// covering the three real situations: standing next to them (scan), in a
    /// chat (share), on a call (read the code).
    private func inviteCard(_ session: BuddySessionState) -> some View {
        VStack(spacing: MADTheme.Spacing.sm) {
            if let qrImage {
                Image(uiImage: qrImage)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 132, height: 132)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 12).fill(.white))
                Text("Point a camera at this")
                    .font(MADTheme.Typography.caption)
                    .foregroundStyle(MADTheme.Colors.madWhite.opacity(0.5))
            }

            Button {
                UIPasteboard.general.string = session.joinCode
                MADHaptics.success()
                withAnimation(MADTheme.Animation.quick) { didCopy = true }
            } label: {
                VStack(spacing: 2) {
                    Text(didCopy ? "COPIED" : "OR SHARE THIS CODE")
                        .font(MADTheme.Typography.caption)
                        .foregroundStyle(
                            didCopy ? session.accentColor : MADTheme.Colors.madWhite.opacity(0.5))
                    Text(session.joinCode)
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .tracking(6)
                        .foregroundStyle(MADTheme.Colors.madWhite)
                }
            }
            .buttonStyle(.plain)

            if let url = DeepLinkRouter.buddyShareURL(code: session.joinCode) {
                ShareLink(
                    item: url,
                    message: Text(
                        "Walk with me on Mile A Day — join code \(session.joinCode)")
                ) {
                    Label("Invite a friend", systemImage: "square.and.arrow.up")
                        .font(MADTheme.Typography.bodyBold)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(Capsule().fill(session.accentColor))
                        .foregroundStyle(MADTheme.Colors.madWhite)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(MADTheme.Spacing.md)
        .frame(maxWidth: .infinity)
        .madLiquidGlassCard()
        .padding(.horizontal, MADTheme.Spacing.md)
        .task(id: session.joinCode) {
            qrImage = ShareProfileView.generateQRCode(
                from: DeepLinkRouter.buddyShareURL(code: session.joinCode)?.absoluteString
                    ?? session.joinCode
            )
            didCopy = false
        }
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
            if session.isScheduledPending {
                // A booked walk starts itself — the server promotes it on time
                // whether or not anyone has the app open. The host still gets
                // an override, because plans change and waiting for a clock you
                // set yourself is a strange thing to be forced into.
                scheduledPanel(session)
            } else if session.isHost(buddy.currentUserId) {
                Button {
                    Task {
                        MADHaptics.emphasis()
                        try? await buddy.start()
                    }
                } label: {
                    VStack(spacing: 1) {
                        Text(readyCount(session) > 1 ? "Start together" : "Start now")
                            .font(MADTheme.Typography.bodyBold)
                        if readyCount(session) < 2 {
                            Text("They can join once you're moving")
                                .font(MADTheme.Typography.caption)
                                .opacity(0.85)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, MADTheme.Spacing.sm + 2)
                    .background(Capsule().fill(session.accentColor))
                    .foregroundStyle(MADTheme.Colors.madWhite)
                }
                .buttonStyle(.plain)
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

    /// The waiting-for-a-booked-time state.
    ///
    /// Deliberately not a live-ticking countdown to the second: a walk booked
    /// for 6pm is minutes away, not seconds, and a seconds counter on a screen
    /// somebody leaves open for an hour is just a battery cost. The relative
    /// style updates itself.
    @ViewBuilder
    private func scheduledPanel(_ session: BuddySessionState) -> some View {
        if let when = session.scheduledStartAtDate {
            VStack(spacing: MADTheme.Spacing.xs) {
                Text("Starts \(when, style: .relative) from now")
                    .font(MADTheme.Typography.bodyBold)
                    .foregroundStyle(MADTheme.Colors.madWhite)
                Text(when, format: .dateTime.weekday(.wide).hour().minute())
                    .font(MADTheme.Typography.caption)
                    .foregroundStyle(MADTheme.Colors.madWhite.opacity(0.6))
                Text("We'll start it for everyone — no need to keep this open")
                    .font(MADTheme.Typography.caption)
                    .foregroundStyle(MADTheme.Colors.madWhite.opacity(0.45))
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, MADTheme.Spacing.sm + 2)
            .background(
                RoundedRectangle(
                    cornerRadius: MADTheme.CornerRadius.large, style: .continuous
                )
                .fill(Color.white.opacity(0.08))
            )

            if session.isHost(buddy.currentUserId) {
                Button {
                    Task {
                        MADHaptics.emphasis()
                        try? await buddy.start()
                    }
                } label: {
                    Text("Start now instead")
                        .font(MADTheme.Typography.smallBold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, MADTheme.Spacing.sm)
                        .background(Capsule().fill(session.accentColor))
                        .foregroundStyle(MADTheme.Colors.madWhite)
                }
                .buttonStyle(.plain)
            }
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
