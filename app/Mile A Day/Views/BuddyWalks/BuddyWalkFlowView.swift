import SwiftUI

/// Where a buddy flow starts.
///
/// Identifiable so hosts can present it with `.fullScreenCover(item:)` —
/// `isPresented` plus a separate `@State` for which screen to open races to a
/// stale value, the trap ios.md records for the post composer.
enum BuddyWalkFlowEntry: String, Identifiable, Hashable {
    /// Set one up from scratch.
    case setup
    /// Straight into a room that already exists — an accepted invite, a live
    /// session, a tapped push.
    case lobby

    var id: String { rawValue }
}

/// Which question the buddy setup is on.
///
/// Owned by the FLOW rather than by the setup steps themselves, because the
/// top bar is rendered once for the whole flow: it needs to know which segment
/// to fill, and Back has to be able to walk the steps from outside them.
enum BuddySetupStep: Equatable {
    case who, activity, plan, goal

    /// The goal is a SUB-step of the plan — it shares the third segment the
    /// way the solo flow's ghost options share its third.
    var indicator: Int {
        switch self {
        case .who: return 1
        case .activity: return 2
        case .plan, .goal: return 3
        }
    }
}

/// Setting up a buddy walk, from the first question to the shared countdown,
/// as ONE screen whose contents change.
///
/// This is the whole point of the file. Setup and the lobby used to be a
/// `.sheet` and a `.fullScreenCover` — two modals, in two visual languages,
/// stacked over the Start Mile wizard: tap "With a Buddy" and a card slid up
/// with its own chrome, tap a mode and that card was replaced by a dark
/// full-screen room with no progress bar, no back chevron, and activity-tinted
/// controls where every other pre-start screen is white on red. Three screens
/// to answer four questions, none of which looked like the one before it.
///
/// Now every stage is a step of the same wizard: one gradient, one top bar,
/// one palette, forward slides in from the trailing edge and Back from the
/// leading one. Nothing here is presented — the stages swap in place, exactly
/// the way choosing Run or Walk does — so from inside the Start Mile cover the
/// buddy flow IS the cover, and Back off the first question lands on the
/// activity step it came from rather than dismissing a card.
///
/// The one presentation left is the host's: from the dashboard (a push, a deep
/// link, the invite pill) there is no wizard to be a step of, so the caller
/// puts this in a full-screen cover — the same container the tracker itself
/// arrives in.
struct BuddyWalkFlowView: View {
    let entry: BuddyWalkFlowEntry
    /// Out of the flow entirely: back to the wizard step that opened it, or
    /// dismiss the cover. Never called with a session still to answer for —
    /// leaving and cancelling both run first.
    let onExit: () -> Void
    /// The shared countdown elapsed. Hand the session to the tracker.
    let onStart: (BuddySessionState) -> Void

    @ObservedObject private var buddy = BuddySessionService.shared

    /// Which stage is on screen. Setup's own four questions are `setupStep`;
    /// this is the coarse machine around them.
    private enum Stage: Equatable {
        case setup
        case lobby
        /// The host changing the plan of a room that already exists.
        case editPlan
        /// Arming a ghost for this walk — the lobby's sub-step, the same
        /// picker the solo wizard renders inline.
        case ghost
    }

    @State private var stage: Stage
    @State private var setupStep: BuddySetupStep = .who
    /// Set OUTSIDE the animated state change, or the enclosing transaction
    /// picks the edge before this has flipped (ios.md). Shared by the stage
    /// machine and the setup steps so one back tap can't slide two ways.
    @State private var goingBack = false
    @State private var confirmCancel = false
    @State private var errorText: String?

    /// Ghost race arming for THIS buddy walk.
    ///
    /// Lives on the flow rather than in the lobby because the picker is now a
    /// stage of the flow. Re-decided every session — the flow always runs
    /// before tracking — so a stale `true` can't leak into a walk nobody
    /// armed.
    @AppStorage(BuddyGhostArming.armedKey) private var buddyGhostArmed = false

    init(
        entry: BuddyWalkFlowEntry,
        onExit: @escaping () -> Void,
        onStart: @escaping (BuddySessionState) -> Void
    ) {
        self.entry = entry
        self.onExit = onExit
        self.onStart = onStart
        _stage = State(initialValue: entry == .lobby ? .lobby : .setup)
    }

    private var session: BuddySessionState? { buddy.session }

    private var isHost: Bool {
        session?.isHost(buddy.currentUserId) ?? false
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            // Rendered ONCE, under every stage. The gradient never re-renders
            // and never slides, which is what makes a stage change read as the
            // next question rather than the next app.
            WizardBackground()

            VStack(spacing: 0) {
                WizardTopBar(step: indicator, total: 4, backTitle: backTitle) { back() }

                // The outgoing and incoming stages OVERLAP in a ZStack. In a
                // VStack each would be allocated its own row mid-transition
                // and everything below would jump.
                ZStack {
                    stageContent
                        .id(stage)
                        .transition(WizardMotion.transition(goingBack: goingBack))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            // This flow is several taps in a row; warm the Taptic Engine so
            // the FIRST one lands as fast as the rest.
            MADHaptics.warmUp()
        }
        .onChange(of: buddy.errorMessage) { _, newValue in
            guard let newValue else { return }
            errorText = newValue
            buddy.errorMessage = nil
        }
        .alert(
            "Buddy Walk",
            isPresented: Binding(
                get: { errorText != nil },
                set: { if !$0 { errorText = nil } }
            )
        ) {
            Button("OK", role: .cancel) { errorText = nil }
        } message: {
            Text(errorText ?? "")
        }
        // Its own invisible node. An alert and a confirmation dialog on the
        // SAME node are two presentations competing for one slot, and SwiftUI
        // silently drops one — the same trap ios.md records for two sheets.
        .background(
            Color.clear
                .confirmationDialog(
                    "Cancel this buddy walk?",
                    isPresented: $confirmCancel,
                    titleVisibility: .visible
                ) {
                    Button("Cancel walk", role: .destructive) { cancelWalk() }
                    Button("Keep it", role: .cancel) {}
                } message: {
                    Text(
                        "Everyone you invited will be told it's off. Nobody's miles are affected."
                    )
                }
        )
    }

    @ViewBuilder
    private var stageContent: some View {
        switch stage {
        case .setup:
            BuddySetupStepsView(step: $setupStep, goingBack: $goingBack) { _ in
                advance(to: .lobby)
            }

        case .lobby:
            BuddyLobbyView(
                onStart: onStart,
                onLeave: { leaveOrCancel() },
                onClose: onExit,
                onEditPlan: { advance(to: .editPlan) },
                onArmGhost: { advance(to: .ghost) },
                // The countdown keeps ticking under "Cancel this buddy walk?",
                // and handing off mid-decision answers the question for them.
                holdHandOff: confirmCancel
            )

        case .editPlan:
            if let session {
                BuddyPlanEditorView(session: session) { retreat(to: .lobby) }
            } else {
                // Unreachable in practice — the Edit affordance only exists on
                // a loaded lobby — but a stage with nothing to edit must not
                // be a blank screen.
                Color.clear.onAppear { retreat(to: .lobby) }
            }

        case .ghost:
            ghostStage
        }
    }

    // MARK: - Chrome state

    private var indicator: Int {
        switch stage {
        case .setup: return setupStep.indicator
        // The plan editor is the plan question, reached from the far end.
        case .editPlan: return 3
        case .lobby, .ghost: return 4
        }
    }

    /// "Back" is a lie on the lobby: the room exists on the server, so there is
    /// no earlier step to return to — the only thing this chevron can do is
    /// take you out of the walk. It says which.
    private var backTitle: String {
        switch stage {
        case .lobby: return isHost ? "Cancel" : "Leave"
        case .setup, .editPlan, .ghost: return "Back"
        }
    }

    // MARK: - Navigation

    private func back() {
        switch stage {
        case .setup:
            switch setupStep {
            case .who: onExit()
            case .activity: retreat(setupTo: .who)
            case .plan: retreat(setupTo: .activity)
            case .goal: retreat(setupTo: .plan)
            }
        case .lobby:
            leaveOrCancel()
        case .editPlan, .ghost:
            retreat(to: .lobby)
        }
    }

    private func advance(to next: Stage) {
        MADHaptics.tap()
        goingBack = false
        withAnimation(MADTheme.Animation.standard) { stage = next }
    }

    private func retreat(to previous: Stage) {
        MADHaptics.tap()
        goingBack = true
        withAnimation(MADTheme.Animation.standard) { stage = previous }
    }

    private func retreat(setupTo previous: BuddySetupStep) {
        MADHaptics.tap()
        goingBack = true
        withAnimation(MADTheme.Animation.standard) { setupStep = previous }
    }

    // MARK: - Getting out

    /// The one control that means "not this". Cancel for the host — it closes
    /// the room for everybody — and Leave for everyone else, who can only take
    /// themselves out of a walk that isn't theirs to call off.
    ///
    /// Both the top bar's chevron and the lobby's own labelled button come
    /// through here, so the two can't drift into meaning different things.
    private func leaveOrCancel() {
        MADHaptics.tap()
        guard session != nil else { return onExit() }
        if isHost {
            confirmCancel = true
        } else {
            Task {
                await buddy.leave()
                onExit()
            }
        }
    }

    private func cancelWalk() {
        Task {
            do {
                try await buddy.cancel()
                MADHaptics.success()
                onExit()
            } catch {
                MADHaptics.error()
                errorText =
                    (error as? LocalizedError)?.errorDescription
                    ?? "Couldn't cancel that walk."
            }
        }
    }

    // MARK: - Ghost sub-step

    /// The picker, inline. The same content the solo wizard renders as its own
    /// fourth step — it just arrives from the lobby instead of the mode
    /// question, which is why it is a stage here rather than a sheet.
    private var ghostStage: some View {
        VStack(spacing: 0) {
            GhostRaceOptionsContent(
                activityKey: BuddyGhostArming.activityKey(session),
                seedPaceSeconds: BuddyGhostArming.seedPaceSeconds,
                current: buddyGhostArmed
                    ? BuddyGhostArming.target(for: BuddyGhostArming.activityKey(session))
                    : nil,
                // White, not the workout colour: this renders on the wizard's
                // red gradient, where a red CTA would vanish.
                accent: WizardPalette.accent,
                accentForeground: WizardPalette.onAccent,
                declineTitle: "Skip the race",
                onRace: { target in
                    BuddyGhostArming.store(target, for: BuddyGhostArming.activityKey(session))
                    buddyGhostArmed = true
                    retreat(to: .lobby)
                },
                onDecline: {
                    buddyGhostArmed = false
                    retreat(to: .lobby)
                }
            )
        }
    }
}

/// Reading and writing the armed ghost for a buddy walk.
///
/// The lobby draws what's armed and the flow's ghost step sets it, so the
/// storage can't live in either of them without the other reaching across. The
/// KEYS are the solo path's own, so "race 12:00" means one thing everywhere
/// rather than two settings that drift apart.
enum BuddyGhostArming {
    /// Read by `WorkoutTrackingView` at the buddy hand-off — the tracker skips
    /// the solo wizard entirely, so this flag is the only thing that can tell
    /// it a buddy walk is also a race.
    static let armedKey = "buddyGhostArmedV1"

    static func activityKey(_ session: BuddySessionState?) -> String {
        (session?.isRunning ?? false) ? "running" : "walking"
    }

    /// Backend fastest-mile PR (minutes/mile on the user model → seconds).
    static var seedPaceSeconds: Double? {
        let pace = UserManager.shared.currentUser.fastestMilePace
        return pace > 0 ? pace * 60 : nil
    }

    private static func storageKey(_ activityKey: String) -> String {
        "ghostTargetV1.\(activityKey)"
    }

    static func target(for activityKey: String) -> BestEffortStore.GhostTarget? {
        let raw = UserDefaults.standard.string(forKey: storageKey(activityKey)) ?? ""
        return BestEffortStore.GhostTarget(storage: raw)
    }

    static func store(_ target: BestEffortStore.GhostTarget, for activityKey: String) {
        UserDefaults.standard.set(target.storage, forKey: storageKey(activityKey))
    }

    static func resolved(_ session: BuddySessionState?) -> BestEffortStore.ResolvedGhost? {
        let key = activityKey(session)
        guard let target = target(for: key) else { return nil }
        return BestEffortStore.resolve(
            target,
            activityKey: key,
            seedPaceSecondsPerMile: seedPaceSeconds
        )
    }
}
