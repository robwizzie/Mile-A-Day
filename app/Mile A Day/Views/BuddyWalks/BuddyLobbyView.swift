import Combine
import SwiftUI

/// The waiting room: who's in, who's still deciding, and the host's start
/// button. Also renders the shared countdown once the host commits.
///
/// The countdown is driven by the server's `started_at`, which is stamped a few
/// seconds in the future — so every phone in the group hits zero on the same
/// wall-clock instant rather than whenever its own request happened to return.
///
/// CONTENT ONLY, and drawn in the pre-start wizard's own language: the
/// gradient, the top bar and the progress dots come from `BuddyWalkFlowView`,
/// which renders them once for the setup questions and this alike. It used to
/// be a `.fullScreenCover` on the app's dark gradient with activity-tinted
/// controls — so answering three questions in white-on-red handed you a room
/// that looked like a different app, and `workoutColor("running")` IS that
/// gradient's top stop, which left a run lobby's countdown red on red.
struct BuddyLobbyView: View {
    /// Fires when the countdown reaches zero, handing the session to the
    /// tracker.
    let onStart: (BuddySessionState) -> Void
    /// The one control that means "not this". Cancel for the host, Leave for
    /// everyone else — the flow owns which, so the top bar's chevron and the
    /// button at the bottom of this screen can't drift apart.
    let onLeave: () -> Void
    /// Get out with nothing to answer for: the walk is already called off.
    let onClose: () -> Void
    /// Host only — change the plan of a room that already exists.
    let onEditPlan: () -> Void
    /// Open the ghost picker, which is a step of the flow rather than a sheet.
    let onArmGhost: () -> Void
    /// True while the flow is asking "cancel this walk?". The countdown keeps
    /// ticking under that dialog, and handing off mid-decision means the
    /// screen answers the question for them.
    var holdHandOff: Bool = false

    @ObservedObject private var buddy = BuddySessionService.shared

    @State private var now = Date()
    @State private var hasHandedOff = false
    /// Friends with an invite request in flight, so their tile can show it.
    @State private var invitingIds: Set<String> = []
    /// Join requests being answered, so a double tap can't answer twice.
    @State private var answeringIds: Set<String> = []

    /// Nil until the first snapshot lands; then TRUE only for someone who
    /// arrived at a walk that was already moving.
    ///
    /// This screen is the one every buddy session passes through, and it hands
    /// off to the tracker the instant `started_at` is in the past — which for a
    /// late joiner is immediately, on the first 0.1s tick. That's correct for
    /// the person who was standing in the lobby when the host pressed Start,
    /// and wrong for someone who just tapped Join on a walk an hour deep: they
    /// get no lobby at all, so there is nowhere to ask them the one question
    /// that decides whether their phone can measure them (treadmill or street).
    /// So the hand-off waits on an explicit tap for them, and only for them.
    @State private var needsJoinConfirm: Bool?

    /// Optimistic copy of this user's own indoor/outdoor answer.
    ///
    /// The server value arrives on the response, which is a round trip after
    /// the tap; without this the segmented control sits on the old choice for
    /// long enough to read as a dead control. Never overwritten by a poll —
    /// it's this user's own answer, and nothing else can contradict it.
    @State private var pendingLocation: BuddyLocationType?

    /// Who was already in when this screen last looked, so an arrival is a
    /// DIFF rather than a state. Nil until the first snapshot has been seen —
    /// the people already standing in the room when you open the door are
    /// not arriving, and announcing them would greet the host with a cascade
    /// of "joined" for a walk they set up.
    @State private var seenInIds: Set<String>?
    /// "Sam joined" — the banner at the top, cleared on a timer.
    @State private var arrivalToast: String?
    /// Tiles mid-bounce. An arrival is the one thing in this lobby that
    /// happens on somebody ELSE's phone, and the poll used to surface it as an
    /// avatar going from dim to lit — a change you notice only if you happen
    /// to be looking at that tile at that moment.
    @State private var pulsingIds: Set<String> = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Whether a ghost is armed for this walk. The picker is a step of the
    /// flow (`onArmGhost`); this is only the readout.
    @AppStorage(BuddyGhostArming.armedKey) private var buddyGhostArmed = false

    /// Drives the countdown text. Local ticking only — no network involved.
    private let tick = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    private var session: BuddySessionState? { buddy.session }

    /// One accent for every pre-start screen — see `WizardPalette`.
    private var accent: Color { WizardPalette.accent }

    var body: some View {
        Group {
            if let session {
                if session.status == .cancelled {
                    // A cancel arrives through the POLL on everybody else's
                    // phone, and `apply` keeps the session so the status is
                    // readable — so without this branch a guest sits under
                    // "Waiting for the host to start…" for a walk that no
                    // longer exists, forever, since polling has stopped too.
                    cancelledPanel(session)
                } else if let remaining = secondsUntilStart(session), remaining > 0 {
                    countdown(remaining: remaining, session: session)
                } else {
                    lobby(session)
                }
            } else {
                ProgressView().tint(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onReceive(tick) { value in
            now = value
            if let session {
                seedJoinGate(session)
                seedArrivals(session)
            }
            handOffIfStarted()
        }
        // Keyed on the SET of people who are in, not on the participant count:
        // an invite that went out and a friend who arrived both change the
        // count, and only one of them is news.
        .onChange(of: currentInIds) { _, newIds in
            announceArrivals(newIds)
        }
        // Rendered HERE: the buddy flow is presented over MainTabView's global
        // banner overlay (or inside the tracker's own cover), so a toast
        // anywhere else is invisible from in here.
        .overlay(alignment: .top) { arrivalToastView }
        .onAppear { buddy.startPolling() }
    }

    /// Decide ONCE, on the first snapshot, whether this user arrived late.
    ///
    /// Latched rather than derived, because the answer must not change when the
    /// host presses Start while somebody is looking at the lobby — that person
    /// was here first and should flow straight into the countdown.
    private func seedJoinGate(_ session: BuddySessionState) {
        guard needsJoinConfirm == nil else { return }
        needsJoinConfirm =
            session.status == .active
            && (session.startedAtDate.map { $0 <= Date() } ?? true)
    }

    // MARK: - Arrivals

    /// Everyone in the room right now, except you — you can't join your own
    /// lobby. Sorted so the array compares by CONTENT for `onChange`.
    private var currentInIds: [String] {
        guard let session else { return [] }
        return inIds(session).sorted()
    }

    private func inIds(_ session: BuddySessionState) -> Set<String> {
        Set(
            session.lobbyParticipants
                .filter {
                    $0.status == .joined || $0.status == .ready || $0.status == .active
                }
                .map(\.userId)
                .filter { $0 != buddy.currentUserId }
        )
    }

    /// The tick seeds because `onChange` cannot: a host who opens the lobby
    /// alone starts at `[]`, the first snapshot is also `[]`, so nothing
    /// changes and nothing seeds — and the first friend to arrive would then
    /// be swallowed as the baseline instead of announced.
    private func seedArrivals(_ session: BuddySessionState) {
        guard seenInIds == nil else { return }
        seenInIds = inIds(session)
    }

    private func announceArrivals(_ newIds: [String]) {
        let now = Set(newIds)
        // A guest opening a room the host is already in gets the roster as a
        // baseline on this same change — the snapshot arrives before the tick.
        guard let seen = seenInIds else {
            seenInIds = now
            return
        }
        seenInIds = now
        let arrived = now.subtracting(seen)
        guard !arrived.isEmpty, let session else { return }

        let names = arrived.compactMap { id in
            session.participants.first(where: { $0.userId == id })?.displayName
        }
        guard !names.isEmpty else { return }

        // The haptic is the part that works while the phone is in a pocket.
        MADHaptics.success()

        let line: String
        switch names.count {
        case 1: line = "\(names[0]) joined"
        case 2: line = "\(names[0]) and \(names[1]) joined"
        default: line = "\(names[0]) and \(names.count - 1) others joined"
        }
        withAnimation(.spring(response: 0.35)) { arrivalToast = line }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) {
            // Only clear our own line — a second arrival may have replaced it.
            if arrivalToast == line {
                withAnimation(.easeOut(duration: 0.25)) { arrivalToast = nil }
            }
        }

        pulsingIds.formUnion(arrived)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            pulsingIds.subtract(arrived)
        }
    }

    /// "Sam joined", over the top of whatever the lobby is showing. Same quiet
    /// shape as the tracker's mid-walk hype toast.
    @ViewBuilder
    private var arrivalToastView: some View {
        if let text = arrivalToast {
            HStack(spacing: 8) {
                Image(systemName: "person.crop.circle.badge.checkmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.white)
                    .accessibilityHidden(true)
                Text(text)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(Color.black.opacity(0.5))
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.45), lineWidth: 1))
            )
            .padding(.top, 12)
            .transition(.move(edge: .top).combined(with: .opacity))
            .allowsHitTesting(false)
        }
    }

    // MARK: - Cancelled

    /// Where a called-off walk ends. Deliberately a screen with a button rather
    /// than an automatic dismissal: a lobby that evaporates while you're
    /// looking at it reads as a crash, and this is the only place the reason
    /// gets said.
    private func cancelledPanel(_ session: BuddySessionState) -> some View {
        VStack(spacing: MADTheme.Spacing.md) {
            Spacer(minLength: 0)

            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.12))
                    .frame(width: 76, height: 76)
                Image(systemName: "xmark")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.8))
            }

            Text("Walk called off")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(Color.white)

            Text(
                session.isHost(buddy.currentUserId)
                    ? "You cancelled this walk. Nobody's miles were affected."
                    : "The host cancelled this walk before it started."
            )
            .font(MADTheme.Typography.body)
            .foregroundStyle(Color.white.opacity(0.75))
            .multilineTextAlignment(.center)
            .padding(.horizontal, MADTheme.Spacing.lg)

            Spacer(minLength: 0)

            WizardPrimaryButton(title: "Done") {
                MADHaptics.tap()
                // Clears the terminal session so the dashboard stops offering
                // it as something to re-enter.
                buddy.clearFinishedSession()
                onClose()
            }
            .padding(.horizontal, MADTheme.Spacing.md)
            .padding(.bottom, MADTheme.Spacing.md)
        }
    }

    // MARK: - Countdown

    /// The shared countdown — the way out of it, and the way through it.
    ///
    /// It used to be an eight-second commitment with no brakes: once Start was
    /// tapped there was no control on the screen at all, and the walk began.
    /// "Wait, no" happens in exactly this window (wrong mode, wrong friend,
    /// pressed by accident), so the host can call the whole thing off and
    /// everyone else can step out — both of which the server still allows right
    /// up until `started_at` passes, and both of which the flow's own back
    /// chevron still offers while this is on screen.
    ///
    /// The other thing that happens in this window is that you are already
    /// walking. Eight seconds of staring at a number is the whole cost of a
    /// synced start, and it is only worth paying when there is somebody to sync
    /// WITH — so "Start now" spends it, for this phone. See `startNow`.
    private func countdown(remaining: TimeInterval, session: BuddySessionState) -> some View {
        // Anyone else actually in the walk. Solo there is nobody for the
        // caption below to be about, and it would read as a bug.
        let others = session.activeParticipants.contains { $0.userId != buddy.currentUserId }

        return VStack(spacing: MADTheme.Spacing.lg) {
            Spacer(minLength: 0)

            Text("Starting together")
                .font(MADTheme.Typography.headline)
                .foregroundStyle(Color.white.opacity(0.85))

            Text("\(max(1, Int(remaining.rounded(.up))))")
                .font(.system(size: 120, weight: .bold, design: .rounded))
                .foregroundStyle(Color.white)
                .contentTransition(.numericText())
                .animation(MADTheme.Animation.quick, value: Int(remaining.rounded(.up)))

            Text(session.mode.title)
                .font(MADTheme.Typography.body)
                .foregroundStyle(Color.white.opacity(0.75))

            Spacer(minLength: 0)

            VStack(spacing: MADTheme.Spacing.sm) {
                WizardPrimaryButton(title: "Start now") { startNow(session) }

                // Says what the button does NOT do. It moves this phone only —
                // `started_at` is untouched — so under a heading that reads
                // "Starting together" the label alone would promise the whole
                // group, and the walk would look broken to the person who
                // tapped it and then watched nobody else appear.
                if others {
                    Text("Everyone else starts when it hits zero.")
                        .font(MADTheme.Typography.small)
                        .foregroundStyle(Color.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, MADTheme.Spacing.lg)
                }

                exitButton(session)
                    .padding(.top, MADTheme.Spacing.xs)
            }
            .padding(.horizontal, MADTheme.Spacing.md)
            .padding(.bottom, MADTheme.Spacing.md)
        }
    }

    /// The labelled way out, under the primary action. The top bar's chevron
    /// does the same thing — both call the flow's `onLeave`, which is where
    /// host-vs-guest and the confirmation live.
    private func exitButton(_ session: BuddySessionState) -> some View {
        let isHost = session.isHost(buddy.currentUserId)
        return Button(action: onLeave) {
            Text(isHost ? "Cancel walk" : "Leave")
                .font(MADTheme.Typography.smallBold)
                .foregroundStyle(Color.white.opacity(0.8))
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(Capsule().fill(Color.white.opacity(0.12)))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Lobby

    /// The waiting room.
    ///
    /// Ordering is the whole design here, and an early one was backwards. The
    /// roster used to be the ONLY flexible child — a `ScrollView` under a fixed
    /// header, a QR card and the ghost row — so on a real phone it collapsed to
    /// a ~60pt sliver with the first participant sliced in half. The single most
    /// important question a lobby answers ("who's actually here?") was the one
    /// thing you couldn't see.
    ///
    /// So: the plan reads as this step's question, who's here comes first at a
    /// size you can read across the room, and the friends you could still add
    /// sit in the same card. One scroll view wraps the lot so nothing can be
    /// squeezed by its neighbours, and the actions stay pinned outside it
    /// because Start must never scroll away.
    private func lobby(_ session: BuddySessionState) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: MADTheme.Spacing.lg) {
                    planHeader(session)
                    peopleCard(session)
                    locationCard(session)
                        .padding(.horizontal, MADTheme.Spacing.md)
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

            WizardFooter { actions(session) }
        }
    }

    // MARK: - Plan header

    /// What this room is, and — for the host — the way to change it.
    ///
    /// Drawn as the wizard's own header, because that is what it is: the
    /// glyph-over-question block every step before this one wore, answering
    /// "what did we just set up". Being able to edit the plan is what turns a
    /// lobby into a waiting room rather than a receipt: plans change between
    /// "let's walk" and "everyone's here", and the only way to act on that used
    /// to be abandoning the room and rebuilding it.
    ///
    /// Non-hosts see the same summary with no affordance. The server enforces
    /// host-only anyway (`not_host`), so this is about not offering something
    /// that would just fail.
    private func planHeader(_ session: BuddySessionState) -> some View {
        VStack(spacing: MADTheme.Spacing.sm) {
            WizardHeader(
                glyph: .symbol(session.mode.icon),
                title: session.mode.title,
                subtitle: planLine(session)
            )
            // Keyed on the plan so a change the HOST made animates on every
            // other phone too, when the poll brings it in.
            .animation(MADTheme.Animation.quick, value: session.mode)

            if session.isHost(buddy.currentUserId) {
                Button {
                    MADHaptics.tap()
                    onEditPlan()
                } label: {
                    Label("Edit", systemImage: "slider.horizontal.3")
                        .font(MADTheme.Typography.caption)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.white.opacity(0.15)))
                        .foregroundStyle(Color.white.opacity(0.9))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, MADTheme.Spacing.md)
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
    private func droppedInviteeText(_ names: [String]) -> String {
        let who: String
        switch names.count {
        case 1: who = names[0]
        case 2: who = "\(names[0]) and \(names[1])"
        default: who = "\(names[0]) and \(names.count - 1) others"
        }
        return "Couldn't invite \(who) — they'll need the latest Mile A Day to join buddy walks."
    }

    private func peopleCard(_ session: BuddySessionState) -> some View {
        let people = session.lobbyParticipants
        let here = people.filter {
            $0.status == .joined || $0.status == .ready || $0.status == .active
        }.count
        let present = Set(people.map(\.userId))
        let invitable = buddy.candidates.filter { !present.contains($0.userId) }
        let isHost = session.isHost(buddy.currentUserId)
        // Inviting is for everyone who is IN, not only the host: the server's
        // invite endpoint judges eligibility against whoever taps, so a guest
        // pulling their own friend in is exactly as valid as the host doing it.
        let amIn = people.contains {
            $0.userId == buddy.currentUserId
                && ($0.status == .joined || $0.status == .ready || $0.status == .active)
        }

        return WizardPanel {
            VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
                HStack {
                    Text("Who's here")
                        .font(MADTheme.Typography.headline)
                        .foregroundStyle(Color.white)
                    Spacer()
                    Text(waitingText(here: here, total: people.count))
                        .font(MADTheme.Typography.caption)
                        .foregroundStyle(Color.white.opacity(here == people.count ? 0.95 : 0.6))
                }

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 68), spacing: MADTheme.Spacing.sm)],
                    spacing: MADTheme.Spacing.md
                ) {
                    ForEach(people) { participant in
                        rosterTile(participant)
                    }
                }

                // Someone tapped who never made the roster. The server drops an
                // invitee it can't reach without an error, so without this the
                // host counted faces and found one missing with no explanation.
                if isHost, !buddy.droppedInviteeNames.isEmpty {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.circle")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(MADTheme.Colors.warning)
                            .accessibilityHidden(true)
                        Text(droppedInviteeText(buddy.droppedInviteeNames))
                            .font(MADTheme.Typography.caption)
                            .foregroundStyle(Color.white.opacity(0.75))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if !session.pendingJoinRequests.isEmpty {
                    Divider().background(Color.white.opacity(0.2))
                    joinRequestsSection(session)
                }

                if amIn, !invitable.isEmpty {
                    Divider().background(Color.white.opacity(0.2))

                    Text("Tap to invite")
                        .font(MADTheme.Typography.smallBold)
                        .foregroundStyle(Color.white.opacity(0.8))

                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 68), spacing: MADTheme.Spacing.sm)],
                        spacing: MADTheme.Spacing.md
                    ) {
                        ForEach(invitable) { candidate in
                            inviteTile(candidate)
                        }
                    }
                }

                if amIn, invitable.isEmpty, people.count <= 1 {
                    // Host, alone, with nobody left to ask. Say so plainly
                    // instead of leaving a card that looks like it's still
                    // loading.
                    Text("No friends available to invite right now.")
                        .font(MADTheme.Typography.caption)
                        .foregroundStyle(Color.white.opacity(0.55))
                }
            }
        }
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
    private func rosterTile(_ participant: BuddyParticipant) -> some View {
        let isIn = participant.status == .joined || participant.status == .ready
            || participant.status == .active
        let name =
            participant.userId == buddy.currentUserId ? "You" : participant.displayName
        let justArrived = pulsingIds.contains(participant.userId)

        return VStack(spacing: 6) {
            AvatarView(
                name: participant.displayName,
                imageURL: participant.profileImageUrl,
                size: 54
            )
            .overlay(
                Circle()
                    .strokeBorder(
                        isIn ? accent : Color.clear,
                        // A thicker ring for the moment of arrival, then the
                        // ordinary one — so the tile itself says "new" even
                        // if the toast was missed.
                        lineWidth: justArrived ? 4 : 2.5)
            )
            .opacity(isIn ? 1 : 0.4)
            // One bounce, not a loop, so it needs no Reduce Motion guard on
            // the animation itself — but the scale is skipped under it all
            // the same, and the ring + toast + haptic carry the news.
            .scaleEffect(justArrived && !reduceMotion ? 1.14 : 1)
            .animation(.spring(response: 0.35, dampingFraction: 0.55), value: justArrived)
            .overlay(alignment: .bottomTrailing) {
                if participant.isHost {
                    Image(systemName: "star.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(WizardPalette.onAccent)
                        .padding(4)
                        .background(Circle().fill(accent))
                        .accessibilityLabel("Host")
                }
            }

            Text(name)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(isIn ? 1 : 0.5))
                .lineLimit(1)

            // "Joined", not "In": the word under a face is the one place the
            // arrival is spelled out, and "In" reads as a fragment.
            Text(isIn ? "Joined" : statusWord(participant.status))
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(Color.white.opacity(isIn ? 0.95 : 0.45))
        }
        // The poll is what surfaces an arrival, so this keys on the value that
        // changed rather than an onAppear that already ran.
        .animation(MADTheme.Animation.standard, value: participant.status)
    }

    /// A friend who isn't in yet. Tapping sends the invite immediately — the
    /// endpoint already exists and is idempotent, so there is nothing to
    /// confirm.
    private func inviteTile(_ candidate: BuddyCandidate) -> some View {
        let sending = invitingIds.contains(candidate.userId)
        return Button {
            guard !sending else { return }
            MADHaptics.action()
            invite(candidate)
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
                        Circle().fill(accent).frame(width: 20, height: 20)
                        if sending {
                            ProgressView()
                                .controlSize(.mini)
                                .tint(WizardPalette.onAccent)
                        } else {
                            Image(systemName: "plus")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(WizardPalette.onAccent)
                        }
                    }
                }

                Text(candidate.displayName)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.9))
                    .lineLimit(1)

                Text(sending ? "Inviting…" : "Invite")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.8))
            }
        }
        .buttonStyle(.plain)
        .disabled(sending)
    }

    private func invite(_ candidate: BuddyCandidate) {
        invitingIds.insert(candidate.userId)
        Task {
            // The response carries the new roster, so the tile moves from the
            // invite row to the roster on its own — no local bookkeeping, and
            // no chance of the two rows disagreeing. The invite endpoint
            // rather than the lobby PATCH: that one is host-only.
            do {
                _ = try await buddy.invite(userIds: [candidate.userId])
            } catch {
                buddy.errorMessage =
                    (error as? LocalizedError)?.errorDescription ?? "Couldn't invite them."
            }
            invitingIds.remove(candidate.userId)
        }
    }

    // MARK: - At the door

    /// People asking to be let in — friends of somebody here, not of the host.
    ///
    /// Answerable by the host and by whichever member they're friends with;
    /// everyone else sees who is waiting and on whom. The card says WHO
    /// vouches for them, because "someone you don't know wants in" is a
    /// question the host can't answer and "Sam's friend wants in" is one they
    /// can.
    private func joinRequestsSection(_ session: BuddySessionState) -> some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.sm) {
            Text(session.pendingJoinRequests.count == 1 ? "Wants to join" : "Want to join")
                .font(MADTheme.Typography.smallBold)
                .foregroundStyle(MADTheme.Colors.warning)

            ForEach(session.pendingJoinRequests) { request in
                joinRequestRow(request, session: session)
            }
        }
    }

    private func joinRequestRow(_ request: BuddyJoinRequest, session: BuddySessionState)
        -> some View
    {
        let canAnswer = session.canAnswerJoinRequest(request, as: buddy.currentUserId)
        let busy = answeringIds.contains(request.userId)
        return HStack(spacing: MADTheme.Spacing.sm) {
            AvatarView(
                name: request.displayName,
                imageURL: request.profileImageUrl,
                size: 40
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(request.displayName)
                    .font(MADTheme.Typography.smallBold)
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                Text(vouchText(request, session: session, canAnswer: canAnswer))
                    .font(MADTheme.Typography.caption)
                    .foregroundStyle(Color.white.opacity(0.65))
                    .lineLimit(2)
            }
            Spacer(minLength: MADTheme.Spacing.xs)
            if canAnswer {
                HStack(spacing: 6) {
                    answerButton("Not now", filled: false, busy: busy) {
                        answer(request, accept: false)
                    }
                    answerButton("Let in", filled: true, busy: busy) {
                        answer(request, accept: true)
                    }
                }
                .fixedSize()
            }
        }
        .padding(.vertical, 4)
    }

    /// "Friends with Sam" — or, for the person who can't answer, who can.
    private func vouchText(
        _ request: BuddyJoinRequest, session: BuddySessionState, canAnswer: Bool
    ) -> String {
        let names = request.friendUserIds.compactMap { id -> String? in
            if id == buddy.currentUserId { return "you" }
            return session.participants.first { $0.userId == id }?.displayName
        }
        let with: String
        switch names.count {
        case 0: with = "A friend of the group"
        case 1: with = "Friends with \(names[0])"
        case 2: with = "Friends with \(names[0]) and \(names[1])"
        default: with = "Friends with \(names[0]) and \(names.count - 1) others"
        }
        return canAnswer ? with : "\(with) — the host or they can let them in"
    }

    private func answerButton(
        _ title: String, filled: Bool, busy: Bool, action: @escaping () -> Void
    ) -> some View {
        Button {
            guard !busy else { return }
            MADHaptics.action()
            action()
        } label: {
            Text(title)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(filled ? MADTheme.Colors.madBlack : Color.white)
                .padding(.horizontal, 12)
                .frame(height: 32)
                .background(
                    Capsule().fill(
                        filled ? MADTheme.Colors.warning : Color.white.opacity(0.15)))
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .opacity(busy ? 0.5 : 1)
    }

    private func answer(_ request: BuddyJoinRequest, accept: Bool) {
        answeringIds.insert(request.userId)
        Task {
            do {
                try await buddy.respondToJoinRequest(userId: request.userId, accept: accept)
                if accept { MADHaptics.success() }
            } catch {
                buddy.errorMessage =
                    (error as? LocalizedError)?.errorDescription ?? "Couldn't answer that."
            }
            answeringIds.remove(request.userId)
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

    // MARK: - Where am I?

    /// This user's own indoor/outdoor answer.
    ///
    /// The buddy hand-off used to write `.outdoor` unconditionally, and that is
    /// not a cosmetic default: it selects the INSTRUMENT. Outdoor measures with
    /// GPS, and GPS indoors never returns a fix that clears the 50m accuracy
    /// gate — so joining a shared walk from a treadmill meant watching your own
    /// distance sit at 0.00 for the whole session while everyone else's climbed,
    /// with the tracker looking perfectly alive the entire time.
    ///
    /// PER PERSON, and everyone sees it. The group's plan doesn't decide where
    /// each of them is standing, and knowing that the friend whose pace looks
    /// strange is on a treadmill is the difference between a bug and a fact.
    private func locationCard(_ session: BuddySessionState) -> some View {
        WizardPanel {
            VStack(alignment: .leading, spacing: MADTheme.Spacing.sm) {
                HStack {
                    Text("Where are you?")
                        .font(MADTheme.Typography.smallBold)
                        .foregroundStyle(Color.white)
                    Spacer()
                    Text("Just for you")
                        .font(MADTheme.Typography.caption)
                        .foregroundStyle(Color.white.opacity(0.55))
                }

                HStack(spacing: 4) {
                    ForEach(BuddyLocationType.allCases) { option in
                        locationChip(option)
                    }
                }
                .padding(4)
                .background(Capsule().fill(Color.white.opacity(0.12)))

                Text(selectedLocation.subtitle)
                    .font(MADTheme.Typography.caption)
                    .foregroundStyle(Color.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// The answer to act on: this user's own tap if they've made one, otherwise
    /// what the server has for them, otherwise the one they gave last time.
    private var selectedLocation: BuddyLocationType {
        pendingLocation ?? buddy.myLocationType
    }

    private func locationChip(_ option: BuddyLocationType) -> some View {
        let isOn = selectedLocation == option
        return Button {
            guard !isOn else { return }
            MADHaptics.tap()
            withAnimation(MADTheme.Animation.quick) { pendingLocation = option }
            Task { await buddy.setLocationType(option) }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: option.icon)
                    .font(.system(size: 13, weight: .semibold))
                Text(option.title)
                    .font(MADTheme.Typography.smallBold)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .background(Capsule().fill(isOn ? accent : .clear))
            .foregroundStyle(isOn ? WizardPalette.onAccent : Color.white.opacity(0.7))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Ghost race

    /// Race your own ghost alongside your buddies.
    ///
    /// Two different races at once, and they don't compete for attention: the
    /// roster answers "how am I doing against them", the delta chip answers
    /// "how am I doing against me". A buddy walk already feeds
    /// `BestEffortStore.recordFinish` — this just lets it race what it feeds.
    ///
    /// The picker it opens is a STEP of the flow (`onArmGhost`), the same
    /// inline screen the solo wizard shows after "Ghost Race" — it was a sheet
    /// over a full-screen cover, which is two modal layers deep for a choice
    /// the solo path makes in the flow itself.
    private func ghostRaceRow(_ session: BuddySessionState) -> some View {
        Button {
            MADHaptics.action()
            onArmGhost()
        } label: {
            HStack(spacing: MADTheme.Spacing.md) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(buddyGhostArmed ? 0.9 : 0.12))
                        .frame(width: 34, height: 34)
                    GhostSprite(
                        size: 17,
                        color: buddyGhostArmed ? WizardPalette.onAccent : .white.opacity(0.8),
                        floats: false,
                        glancesBack: true
                    )
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text("Race your ghost")
                        .font(MADTheme.Typography.smallBold)
                        .foregroundStyle(Color.white)
                    Text(ghostSubtitle(session))
                        .font(MADTheme.Typography.caption)
                        .foregroundStyle(Color.white.opacity(0.65))
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                if buddyGhostArmed, let ghost = BuddyGhostArming.resolved(session) {
                    Text(BestEffortStore.formatSeconds(ghost.effort.seconds))
                        .font(MADTheme.Typography.smallBold)
                        .monospacedDigit()
                        .foregroundStyle(Color.white)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(Capsule().fill(Color.white.opacity(0.10)))
            .overlay(Capsule().stroke(Color.white.opacity(0.18), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func ghostSubtitle(_ session: BuddySessionState) -> String {
        guard buddyGhostArmed, let ghost = BuddyGhostArming.resolved(session) else {
            return "Chase your own time while you walk together"
        }
        return "Chasing \(ghost.shortName)"
    }

    // MARK: - Actions

    @ViewBuilder
    private func actions(_ session: BuddySessionState) -> some View {
        if needsJoinConfirm == true {
            // Arrived at a walk already in progress. There is no Start to
            // wait for and no countdown to share — the only thing left is
            // this person saying they're ready, which is also what keeps
            // them on this screen long enough to answer the indoor/outdoor
            // question above.
            joinNowPanel(session)
        } else if session.isScheduledPending {
            // A booked walk starts itself — the server promotes it on time
            // whether or not anyone has the app open. The host still gets
            // an override, because plans change and waiting for a clock you
            // set yourself is a strange thing to be forced into.
            scheduledPanel(session)
        } else if session.isHost(buddy.currentUserId) {
            WizardPrimaryButton(
                title: readyCount(session) > 1 ? "Start together" : "Start now",
                icon: "figure.2"
            ) {
                MADHaptics.emphasis()
                Task { try? await buddy.start() }
            }
            if let note = startNote(session) {
                Text(note)
                    .font(MADTheme.Typography.caption)
                    .foregroundStyle(Color.white.opacity(0.6))
                    .multilineTextAlignment(.center)
            }
        } else {
            Text("Waiting for the host to start…")
                .font(MADTheme.Typography.body)
                .foregroundStyle(Color.white.opacity(0.75))
                .frame(maxWidth: .infinity)
                .padding(.vertical, MADTheme.Spacing.sm)
        }

        exitButton(session)
            .padding(.top, 2)
    }

    /// The late arrival's Start button.
    @ViewBuilder
    private func joinNowPanel(_ session: BuddySessionState) -> some View {
        WizardPrimaryButton(
            title: session.isRunning ? "Start my run" : "Start my walk",
            icon: "figure.2"
        ) {
            MADHaptics.emphasis()
            // Nothing to call: the join already landed this user 'active'
            // server-side. All this releases is the hand-off gate.
            needsJoinConfirm = false
        }
        Text(alreadyMovingNote(session))
            .font(MADTheme.Typography.caption)
            .foregroundStyle(Color.white.opacity(0.6))
            .multilineTextAlignment(.center)
    }

    /// "Sam is already out — you'll start from here." Names who, because the
    /// reason this person tapped Join was a specific friend.
    private func alreadyMovingNote(_ session: BuddySessionState) -> String {
        let others = session.activeParticipants
            .filter { $0.userId != buddy.currentUserId }
        guard let first = others.first else {
            return "You'll start from here"
        }
        let who = others.count == 1
            ? first.displayName
            : "\(first.displayName) and \(others.count - 1) more"
        return "\(who) already out — you'll start from here"
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
                    .foregroundStyle(Color.white)
                Text(when, format: .dateTime.weekday(.wide).hour().minute())
                    .font(MADTheme.Typography.caption)
                    .foregroundStyle(Color.white.opacity(0.7))
                Text("We'll start it for everyone — no need to keep this open")
                    .font(MADTheme.Typography.caption)
                    .foregroundStyle(Color.white.opacity(0.55))
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, MADTheme.Spacing.sm)

            if session.isHost(buddy.currentUserId) {
                WizardPrimaryButton(title: "Start now instead") {
                    MADHaptics.emphasis()
                    Task { try? await buddy.start() }
                }
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
        // Cheap early-out first: this runs ten times a second. The status and
        // already-finished checks are `performHandOff`'s, not restated here.
        guard !hasHandedOff, let session else { return }
        // Don't drop somebody into a workout while they're staring at "Cancel
        // this buddy walk?". The countdown keeps ticking under the dialog, and
        // handing off mid-decision means the screen answers the question for
        // them. The server's own window is what decides whether the cancel
        // actually lands; this only stops the UI racing the user.
        guard !holdHandOff else { return }
        // A late arrival taps their way in — see `needsJoinConfirm`. Nil means
        // no snapshot has landed yet, so nothing has been decided.
        guard needsJoinConfirm == false else { return }
        guard let startedAt = session.startedAtDate, startedAt <= now else { return }
        performHandOff(session)
    }

    /// Skip the wait, for this phone only.
    ///
    /// Safe to hand off before `started_at`, because the countdown is the only
    /// thing still in the future: `activateSession` already flipped the session
    /// AND every lobby participant to `active` when Start was pressed, so the
    /// server accepts this user's progress immediately — `recordProgress` even
    /// clamps its speed ceiling with a `GREATEST(..., 1)` written for exactly
    /// this case, "the pre-start countdown, when started_at is still in the
    /// future". Nothing downstream needs the clock to have run out either: the
    /// tracker's `startBuddyWorkoutIfReady` keys off the session id alone, the
    /// race-time progress bar floors elapsed at 0, and sync reconciliation
    /// matches on the workout's END date, which only moves later.
    ///
    /// It does NOT move `started_at`, so it starts nobody else — that would be
    /// a server change, and at a 5s poll it would still leave the others most
    /// of the countdown. The caption says so rather than letting the button
    /// imply it.
    private func startNow(_ session: BuddySessionState) {
        // No tap haptic — `performHandOff` fires .success() either way, and
        // back-to-back buzzes on one press read as a stutter.
        performHandOff(session)
    }

    /// The one place the lobby ever hands a session to the tracker. Both the
    /// countdown elapsing and an explicit "Start now" come through here so the
    /// once-only latch and the never-restart-a-finished-walk guard can't be
    /// written twice and drift.
    private func performHandOff(_ session: BuddySessionState) {
        guard !hasHandedOff, session.status == .active else { return }
        guard session.me(buddy.currentUserId)?.status != .finished else { return }
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
