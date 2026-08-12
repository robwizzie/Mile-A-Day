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
    @State private var showGhostSetup = false
    @State private var showSettings = false
    /// Friends with an invite request in flight, so their tile can show it.
    @State private var invitingIds: Set<String> = []

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

    /// The waiting room.
    ///
    /// Ordering is the whole design here, and the previous one was backwards.
    /// The roster used to be the ONLY flexible child — a `ScrollView` under a
    /// fixed header, a 132pt QR card and the ghost row — so on a real phone it
    /// collapsed to a ~60pt sliver with the first participant sliced in half.
    /// The single most important question a lobby answers ("who's actually
    /// here?") was the one thing you couldn't see.
    ///
    /// So: who's here comes FIRST, at a size you can read across the room, with
    /// the friends you could still add in the same card. One scroll view wraps
    /// the lot so nothing can be squeezed by its neighbours, and the actions
    /// stay pinned outside it because Start must never scroll away.
    private func lobby(_ session: BuddySessionState) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: MADTheme.Spacing.lg) {
                    planHeader(session)
                    peopleCard(session)
                    ghostRaceRow(session)
                        .padding(.horizontal, MADTheme.Spacing.md)
                    Color.clear.frame(height: 4)
                }
            }
            .task {
                // A lobby reached by push or deep link never passed through the
                // dashboard prefetch, so the friend row would be empty exactly
                // when someone is trying to pull people in.
                await buddy.loadCandidates()
            }

            actions(session)
                .padding(MADTheme.Spacing.md)
                .background(.ultraThinMaterial)
        }
    }

    // MARK: - Plan header

    /// What this room is, and — for the host — the way to change it.
    ///
    /// Being able to edit the plan is what turns a lobby into a waiting room
    /// rather than a receipt: plans change between "let's walk" and "everyone's
    /// here", and the only way to act on that used to be abandoning the room and
    /// rebuilding it.
    ///
    /// Non-hosts see the same summary with no affordance. The server enforces
    /// host-only anyway (`not_host`), so this is about not offering something
    /// that would just fail.
    private func planHeader(_ session: BuddySessionState) -> some View {
        VStack(spacing: MADTheme.Spacing.xs) {
            ZStack {
                Circle()
                    .fill(session.accentColor.opacity(0.18))
                    .frame(width: 76, height: 76)
                Circle()
                    .strokeBorder(session.accentColor.opacity(0.45), lineWidth: 1.5)
                    .frame(width: 76, height: 76)
                Image(systemName: session.mode.icon)
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(session.accentColor)
            }
            // Keyed on the plan so a change the HOST made animates on every
            // other phone too, when the poll brings it in.
            .animation(MADTheme.Animation.quick, value: session.mode)

            Text(session.mode.title)
                .font(MADTheme.Typography.title2)
                .foregroundStyle(MADTheme.Colors.madWhite)

            Text(planLine(session))
                .font(MADTheme.Typography.body)
                .foregroundStyle(MADTheme.Colors.madWhite.opacity(0.7))
                .multilineTextAlignment(.center)

            if session.isHost(buddy.currentUserId) {
                Button {
                    MADHaptics.tap()
                    showSettings = true
                } label: {
                    Label("Edit", systemImage: "slider.horizontal.3")
                        .font(MADTheme.Typography.caption)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(MADTheme.Colors.madWhite.opacity(0.10)))
                        .foregroundStyle(MADTheme.Colors.madWhite.opacity(0.85))
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
        }
        .padding(.top, MADTheme.Spacing.xl)
        // Its own presentation node: this view also carries the ghost-setup
        // sheet, and two sheets on ONE node makes SwiftUI silently drop one.
        .background(
            Color.clear
                .sheet(isPresented: $showSettings) {
                    BuddyLobbySettingsSheet(session: session)
                }
        )
    }

    /// "2.0 miles · Walk" — the plan as one line, so the goal and the activity
    /// aren't two separate things to hold in your head.
    private func planLine(_ session: BuddySessionState) -> String {
        let activity = session.isRunning ? "Run" : "Walk"
        guard let goal = session.goalValue else { return activity }
        return "\(goalText(goal, mode: session.mode)) · \(activity)"
    }

    // MARK: - People

    /// Everyone in one card: who's here, and — one tap away — who else could be.
    ///
    /// This replaces a roster card sitting above a separate "invite" card whose
    /// only real control was a ShareLink. That arrangement meant the ONLY
    /// visible way to invite someone was to send them a link, while inviting an
    /// actual Mile A Day friend was buried behind the Edit button under a
    /// heading called "Add more people". Nobody found it, and the reasonable
    /// conclusion from looking at the screen was that the feature didn't exist.
    ///
    /// So the friends row lives here, in the same card as the roster, as
    /// tappable faces: one tap invites, no sheet, no navigation. The join code
    /// and QR that used to sit here are gone entirely — everyone you can walk
    /// with is already an accepted friend, so a code was a second, weaker path
    /// to a thing this row does better.
    ///
    /// Host-only, because the server is (`not_host`). A guest sees the roster,
    /// which is everything they can act on.
    private func peopleCard(_ session: BuddySessionState) -> some View {
        let people = session.lobbyParticipants
        let here = people.filter {
            $0.status == .joined || $0.status == .ready || $0.status == .active
        }.count
        let present = Set(people.map(\.userId))
        let invitable = buddy.candidates.filter { !present.contains($0.userId) }
        let isHost = session.isHost(buddy.currentUserId)

        return VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
            HStack {
                Text("Who's here")
                    .font(MADTheme.Typography.headline)
                    .foregroundStyle(MADTheme.Colors.madWhite)
                Spacer()
                Text(waitingText(here: here, total: people.count))
                    .font(MADTheme.Typography.caption)
                    .foregroundStyle(
                        here == people.count
                            ? session.accentColor
                            : MADTheme.Colors.madWhite.opacity(0.55))
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 68), spacing: MADTheme.Spacing.sm)],
                spacing: MADTheme.Spacing.md
            ) {
                ForEach(people) { participant in
                    rosterTile(participant, session: session)
                }
            }

            if isHost, !invitable.isEmpty {
                Divider().background(MADTheme.Colors.madWhite.opacity(0.10))

                Text("Tap to invite")
                    .font(MADTheme.Typography.smallBold)
                    .foregroundStyle(MADTheme.Colors.madWhite.opacity(0.75))

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 68), spacing: MADTheme.Spacing.sm)],
                    spacing: MADTheme.Spacing.md
                ) {
                    ForEach(invitable) { candidate in
                        inviteTile(candidate, session: session)
                    }
                }
            }

            if isHost, invitable.isEmpty, people.count <= 1 {
                // Host, alone, with nobody left to ask. Say so plainly instead
                // of leaving a card that looks like it's still loading.
                Text("No friends available to invite right now.")
                    .font(MADTheme.Typography.caption)
                    .foregroundStyle(MADTheme.Colors.madWhite.opacity(0.5))
            }
        }
        .padding(MADTheme.Spacing.md)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(
                cornerRadius: MADTheme.CornerRadius.extraLarge, style: .continuous
            )
            .fill(MADTheme.Colors.madWhite.opacity(0.06))
        )
        .padding(.horizontal, MADTheme.Spacing.md)
        .animation(MADTheme.Animation.standard, value: session.participants.count)
    }

    /// "Everyone's in" is wrong when you're on your own — there is no everyone
    /// yet, and the phrase reads as though the walk is ready to go when the
    /// whole point of the screen is that nobody has been asked.
    private func waitingText(here: Int, total: Int) -> String {
        if total <= 1 { return "Just you so far" }
        if here == total { return "Everyone's in" }
        return "\(here) of \(total)"
    }

    /// One face. Presence is carried by the avatar — ringed and full strength
    /// once they're in, dimmed while the invite is still outstanding — with the
    /// word underneath only for the states a ring can't spell.
    private func rosterTile(_ participant: BuddyParticipant, session: BuddySessionState)
        -> some View
    {
        let isIn = participant.status == .joined || participant.status == .ready
            || participant.status == .active
        let name =
            participant.userId == buddy.currentUserId ? "You" : participant.displayName

        return VStack(spacing: 6) {
            AvatarView(
                name: participant.displayName,
                imageURL: participant.profileImageUrl,
                size: 54
            )
            .overlay(
                Circle()
                    .strokeBorder(isIn ? session.accentColor : Color.clear, lineWidth: 2.5)
            )
            .opacity(isIn ? 1 : 0.4)
            .overlay(alignment: .bottomTrailing) {
                if participant.isHost {
                    Image(systemName: "star.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(MADTheme.Colors.madBlack)
                        .padding(4)
                        .background(Circle().fill(session.accentColor))
                }
            }

            Text(name)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(MADTheme.Colors.madWhite.opacity(isIn ? 1 : 0.5))
                .lineLimit(1)

            Text(isIn ? "In" : statusWord(participant.status))
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(
                    isIn ? session.accentColor : MADTheme.Colors.madWhite.opacity(0.4))
        }
        // The poll is what surfaces an arrival, so this keys on the value that
        // changed rather than an onAppear that already ran.
        .animation(MADTheme.Animation.standard, value: participant.status)
    }

    /// A friend who isn't in yet. Tapping sends the invite immediately — the
    /// PATCH already exists and is idempotent, so there is nothing to confirm.
    private func inviteTile(_ candidate: BuddyCandidate, session: BuddySessionState)
        -> some View
    {
        let sending = invitingIds.contains(candidate.userId)
        return Button {
            guard !sending else { return }
            MADHaptics.action()
            invite(candidate, session: session)
        } label: {
            VStack(spacing: 6) {
                AvatarView(
                    name: candidate.displayName,
                    imageURL: candidate.profileImageUrl,
                    size: 54
                )
                .opacity(sending ? 0.45 : 0.8)
                .overlay(alignment: .bottomTrailing) {
                    ZStack {
                        Circle().fill(session.accentColor).frame(width: 20, height: 20)
                        if sending {
                            ProgressView()
                                .controlSize(.mini)
                                .tint(MADTheme.Colors.madWhite)
                        } else {
                            Image(systemName: "plus")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(MADTheme.Colors.madWhite)
                        }
                    }
                }

                Text(candidate.displayName)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(MADTheme.Colors.madWhite.opacity(0.85))
                    .lineLimit(1)

                Text(sending ? "Inviting…" : "Invite")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(session.accentColor)
            }
        }
        .buttonStyle(.plain)
        .disabled(sending)
    }

    private func invite(_ candidate: BuddyCandidate, session: BuddySessionState) {
        invitingIds.insert(candidate.userId)
        Task {
            // The response carries the new roster, so the tile moves from the
            // invite row to the roster on its own — no local bookkeeping, and
            // no chance of the two rows disagreeing.
            _ = try? await buddy.updateSession(inviteUserIds: [candidate.userId])
            invitingIds.remove(candidate.userId)
        }
    }

    private func statusWord(_ status: BuddyParticipantStatus) -> String {
        switch status {
        case .invited: return "Invited"
        case .joined: return "In"
        case .ready: return "Ready"
        case .active: return "Moving"
        case .finished: return "Done"
        case .left, .declined: return "Out"
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
                        if let note = startNote(session) {
                            Text(note)
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

    /// The line under Start, which has to mean something in all three states.
    ///
    /// "They can join once you're moving" was shown whenever fewer than two
    /// people were ready — including when you were alone in a room you'd invited
    /// nobody to, where "they" referred to nobody at all and read as though the
    /// app was waiting on someone you'd forgotten about.
    private func startNote(_ session: BuddySessionState) -> String? {
        let others = session.lobbyParticipants.filter { $0.userId != buddy.currentUserId }
        if others.isEmpty { return "Invite someone above, or head out on your own" }
        if readyCount(session) < 2 { return "They can join once you're moving" }
        return nil
    }

    private func readyCount(_ session: BuddySessionState) -> Int {
        session.participants.filter { $0.status == .joined || $0.status == .ready }.count
    }

    private func secondsUntilStart(_ session: BuddySessionState) -> TimeInterval? {
        guard session.status == .active, let startedAt = session.startedAtDate else { return nil }
        return startedAt.timeIntervalSince(now)
    }

    /// Hand the session to the tracker exactly once, the instant the shared
    /// countdown elapses.
    ///
    /// Never for a participant who already FINISHED: the session stays
    /// `active` while friends are still walking, so any route that lands a
    /// finished user back in this lobby (a buddy push, the invite pill, the
    /// wizard card) would otherwise hand them straight into a brand-new
    /// tracking session for a mile they already ended.
    private func handOffIfStarted() {
        guard !hasHandedOff, let session, session.status == .active else { return }
        guard session.me(buddy.currentUserId)?.status != .finished else { return }
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
