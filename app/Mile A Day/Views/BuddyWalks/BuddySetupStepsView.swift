import SwiftUI

/// Set up a buddy walk, and answer the ones you've been invited to.
///
/// There is no join code any more. Codes existed so you could pull in someone
/// the app couldn't name — but everyone you can walk with is already an
/// accepted friend, so the code was a second, weaker path to a thing the
/// friend list does better: it had to be read aloud or pasted, it could be
/// mistyped, and it put a text field on the screen that most people read as the
/// primary way in. Invites go out from the friend list; invites you receive
/// land at the top of the first step.
///
/// Opens on "Just Together" with no goal to set, so the common case — two
/// friends about to walk — is pick-a-friend-and-go.
///
/// CONTENT ONLY. The gradient, the top bar and the progress dots belong to
/// `BuddyWalkFlowView`, which renders them once for every stage including the
/// lobby — this was a `.sheet` with its own copy of them, so the wizard's own
/// chrome slid away and a card with a near-identical one slid up in its place.
/// `step` and `goingBack` are bindings for the same reason: the one back
/// chevron lives up there, so it has to be able to walk these questions from
/// outside them.
struct BuddySetupStepsView: View {
    @Binding var step: BuddySetupStep
    /// Which edge the next transition comes from. Owned by the flow so a back
    /// tap on the top bar and a forward tap on a card can't slide two ways.
    @Binding var goingBack: Bool
    /// Handed back so the flow can move on to the lobby.
    let onCreated: (BuddySessionState) -> Void

    @ObservedObject private var buddy = BuddySessionService.shared

    @State private var mode: BuddyMode = .together
    @State private var goal: Double = BuddyMode.together.defaultGoal
    @State private var isRun = false
    @State private var selected: Set<String> = []
    @State private var isCreating = false
    /// Book the walk for later instead of starting it from the lobby. Off by
    /// default — starting now is overwhelmingly the common case.
    @State private var isScheduled = false
    @State private var scheduledDate = Date().addingTimeInterval(60 * 60)
    /// Weekdays this walk repeats on, 0 = Sunday (matching the server's
    /// EXTRACT(DOW)). Empty = a one-off, which is the default.
    @State private var repeatDays: Set<Int> = []
    /// The archive of walks already taken, from the "You've walked with" header.
    @State private var showHistory = false
    /// A selected friend's already-open walk, offered before creating a
    /// second one beside it.
    @State private var pendingTwin: JoinableFriendSession?
    @State private var joiningId: String?

    /// Last setup, restored on open.
    ///
    /// Buddy walks are a habit with a fixed shape — the same person, the same
    /// activity, the same mode, most days. Re-picking all three every time was
    /// most of why setting one up "takes forever", and none of those taps ever
    /// carried information. Restored rather than hardcoded, so a first-time
    /// user still lands on the zero-config default (Just Together, walking).
    @AppStorage("buddyLastModeV1") private var lastModeRaw = BuddyMode.together.rawValue
    @AppStorage("buddyLastIsRunV1") private var lastIsRun = false
    // Invitees are deliberately NOT restored. They were, and "2 selected"
    // then meant a regular near the top plus last week's new friend ticked
    // way down the list — someone who wasn't there today, invited by
    // accident. Recent partners are one tap away in "You've walked with".
    /// One-shot: restoring must not fight the user's taps on a later re-render.
    @State private var didRestore = false

    private var activityType: String { isRun ? "running" : "walking" }

    /// White on the red gradient, like every other pre-start step. NOT the
    /// activity colour: `workoutColor("running")` is this gradient's own top
    /// stop, so a run's goal chips and check marks were red on red.
    private var accent: Color { WizardPalette.accent }

    /// Fixed so the segmented rows, the goal chips and the footer button all
    /// resolve to the same outer height.
    private static let controlHeight: CGFloat = WizardMetrics.controlHeight
    private static let chipHeight: CGFloat = controlHeight - 8

    /// The plain card behind repeated elements.
    ///
    /// `madLiquidGlass` is a REAL blur (`glassEffect`, or `.ultraThinMaterial`
    /// pre-iOS 26), and the friend list plus the partner rows meant several
    /// blurred surfaces recompositing on every selection tap, animated — which
    /// is what made this screen feel sluggish. A flat fill is visually
    /// indistinguishable on this background and costs nothing.
    private func panel(_ radius: CGFloat = 20) -> some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(Color.white.opacity(0.10))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
            )
    }

    private var hasFooter: Bool { step == .who || step == .goal }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .bottom) {
            GeometryReader { geo in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 28) {
                        Spacer(minLength: 8)

                        // Both animated regions sit in a ZStack so the outgoing
                        // and incoming copies OVERLAP. In a VStack they'd each
                        // be allocated their own row mid-transition and
                        // everything below would jump.
                        ZStack {
                            WizardHeader(
                                glyph: stepGlyph,
                                title: stepTitle,
                                subtitle: stepSubtitle
                            )
                            .id(step)
                            // Crossfades in place rather than sliding: the
                            // question is part of the frame, so moving it is
                            // what made the whole screen feel like it swapped.
                            .transition(.opacity)
                        }

                        ZStack {
                            VStack(spacing: 16) { stepContent }
                                .id(step)
                                .transition(WizardMotion.transition(goingBack: goingBack))
                        }
                        .padding(.horizontal, 20)

                        Spacer(minLength: 8)

                        // Clears the pinned footer on the steps that have one.
                        if hasFooter {
                            Color.clear.frame(height: WizardMetrics.footerClearance)
                        }
                    }
                    .frame(minHeight: geo.size.height)
                }
            }

            if hasFooter { footer }
        }
        .task {
            restoreLastSetup()
            // Both already prefetched on the dashboard, so this opens
            // populated and these are a refresh, not a blocking load. Run
            // concurrently — they have nothing to do with each other.
            async let candidates: Void = buddy.loadCandidates()
            async let routines: Void = buddy.loadRoutines()
            async let partners: Void = buddy.loadPartners()
            async let sessions: Void = buddy.refreshMySessions()
            _ = await (candidates, routines, partners, sessions)
            // Friends' walks starting right now — offered at the top so two
            // people standing together end up in ONE walk.
            await buddy.refreshJoinableFriendSessions()
        }
        .confirmationDialog(
            pendingTwin.map { "\($0.hostDisplayName) already started a \($0.isRunning ? "run" : "walk")" } ?? "",
            isPresented: Binding(get: { pendingTwin != nil }, set: { if !$0 { pendingTwin = nil } }),
            titleVisibility: .visible,
            presenting: pendingTwin
        ) { twin in
            Button("Join \(twin.hostDisplayName)'s \(twin.isRunning ? "run" : "walk")") {
                join(twin)
            }
            Button("Start my own anyway") { Task { await create() } }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Join theirs and you'll walk together in one group instead of two.")
        }
        .sheet(isPresented: $showHistory) {
            // "Walk with Sam again" from inside the setup flow means exactly
            // "tick Sam", not "open another setup flow".
            BuddyWalksHistoryView(onWalkAgain: { userId in
                guard let userId,
                    buddy.candidates.contains(where: { $0.userId == userId })
                else { return }
                selected.insert(userId)
            })
        }
    }

    // MARK: - Per-step content

    private var stepGlyph: WizardGlyph {
        switch step {
        case .who: return .symbol("person.2.fill")
        case .activity: return .symbol("figure.walk")
        // The plan step's glyph is the two figures, not a mode's icon: every
        // mode is one of the answers, and putting one above the question
        // pre-announces it.
        case .plan: return .symbol("figure.2")
        case .goal: return .symbol(mode.icon)
        }
    }

    private var stepTitle: String {
        switch step {
        case .who: return "Who's Coming?"
        case .activity: return "Choose Activity Type"
        case .plan: return "Choose Your Mode"
        case .goal: return mode == .raceTime ? "For How Long?" : "How Far?"
        }
    }

    private var stepSubtitle: String {
        switch step {
        case .who:
            return "Pick who's in, or make the lobby and invite from there."
        // Word for word the solo wizard's line, on purpose.
        case .activity: return "Select how you'll complete your mile"
        case .plan: return "Just move together, or make it a race."
        case .goal: return "One target for everyone."
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .who:
            startingNowSection
            invitesSection
            partnersSection
            friendSection
            routinesSection

        case .activity:
            WizardOptionCard(
                leading: { WizardOptionGlyph(icon: "figure.walk") },
                title: "Walk",
                subtitle: "Track as a walking workout",
                accessory: { choiceAccessory(remembered: !isRun) }
            ) { choose(run: false) }
            WizardOptionCard(
                leading: { WizardOptionGlyph(icon: "figure.run") },
                title: "Run",
                subtitle: "Track as a running workout",
                accessory: { choiceAccessory(remembered: isRun) }
            ) { choose(run: true) }

        case .plan:
            ForEach(BuddyMode.allCases) { option in
                WizardOptionCard(
                    leading: { WizardOptionGlyph(icon: option.icon) },
                    title: option.title,
                    subtitle: option.subtitle,
                    accessory: { choiceAccessory(remembered: mode == option) }
                ) { choose(mode: option) }
            }
            // Starting later is a setting on the plan, not a step of its own:
            // set it, then tap the mode that commits. Collapsed to one row
            // until it's wanted.
            scheduleSection
                .padding(.top, 4)
            // The single most important sentence on this screen. A mode card
            // CREATES the lobby, and every earlier label said "start" —
            // people backed out rather than find out.
            Text("Tapping a mode makes the lobby. Nobody moves until you start it.")
                .font(MADTheme.Typography.caption)
                .foregroundStyle(Color.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

        case .goal:
            goalSection
        }
    }

    /// Last time's answer wears a check instead of a chevron. The card still
    /// advances on a tap — this is a hint, not a selection, because restoring
    /// the previous setup can't skip a question in a wizard the way it could
    /// pre-fill a form.
    @ViewBuilder
    private func choiceAccessory(remembered: Bool) -> some View {
        if remembered {
            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .foregroundColor(.white.opacity(0.9))
        } else {
            WizardOptionChevron()
        }
    }

    private func choose(run: Bool) {
        isRun = run
        advance(to: .plan)
    }

    private func choose(mode option: BuddyMode) {
        MADHaptics.tap()
        mode = option
        goal = option.defaultGoal
        if option.needsGoal {
            advance(to: .goal)
        } else {
            Task { await create() }
        }
    }

    private func advance(to next: BuddySetupStep) {
        MADHaptics.tap()
        goingBack = false
        withAnimation(MADTheme.Animation.standard) { step = next }
    }

    // MARK: - Invitations

    /// Walks you've been asked to join, at the very top.
    ///
    /// This is the piece that was missing entirely. `buddy.invites` has always
    /// been fetched and stored, but the ONLY thing that ever read it was a count
    /// badge on the dashboard pill — there was no list anywhere in the app. So a
    /// buddy_invite push landed, the tap routed to the Dashboard, and the invite
    /// was a number on a pill that opened a screen which didn't mention it. The
    /// honest description of that is: you could be invited, and you could not
    /// accept.
    @ViewBuilder
    private var invitesSection: some View {
        if !buddy.invites.isEmpty {
            VStack(alignment: .leading, spacing: MADTheme.Spacing.sm) {
                sectionTitle(
                    buddy.invites.count == 1
                        ? "You've been invited" : "\(buddy.invites.count) invites")
                VStack(spacing: MADTheme.Spacing.sm) {
                    ForEach(buddy.invites) { invite in
                        inviteRow(invite)
                    }
                }
            }
        }
    }

    private func inviteRow(_ invite: BuddySessionState) -> some View {
        let host = invite.participants.first(where: { $0.isHost })

        return VStack(alignment: .leading, spacing: MADTheme.Spacing.sm) {
            HStack(spacing: MADTheme.Spacing.md) {
                AvatarView(
                    name: host?.displayName ?? "Friend",
                    imageURL: host?.profileImageUrl,
                    size: 44
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(host?.displayName ?? "A friend") invited you")
                        .font(MADTheme.Typography.bodyBold)
                        .foregroundStyle(Color.white)
                        .lineLimit(1)
                    Text(inviteDetail(invite))
                        .font(MADTheme.Typography.caption)
                        .foregroundStyle(Color.white.opacity(0.6))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: MADTheme.Spacing.sm) {
                Button {
                    MADHaptics.action()
                    Task {
                        do {
                            try await buddy.join(sessionId: invite.id)
                            if let joined = buddy.session {
                                onCreated(joined)
                            }
                        } catch {
                            buddy.errorMessage =
                                (error as? LocalizedError)?.errorDescription
                                ?? "Couldn't join that walk."
                        }
                    }
                } label: {
                    Text("Join")
                        .font(MADTheme.Typography.bodyBold)
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                        .background(Capsule().fill(WizardPalette.accent))
                        .foregroundStyle(WizardPalette.onAccent)
                }
                .buttonStyle(.plain)

                Button {
                    MADHaptics.tap()
                    Task { await buddy.decline(sessionId: invite.id) }
                } label: {
                    Text("Not now")
                        .font(MADTheme.Typography.body)
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                        .background(Capsule().fill(Color.white.opacity(0.12)))
                        .foregroundStyle(Color.white.opacity(0.75))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(MADTheme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white.opacity(0.15))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.45), lineWidth: 2)
                )
        )
    }

    private func inviteDetail(_ invite: BuddySessionState) -> String {
        let activity = invite.isRunning ? "Run" : "Walk"
        if let goal = invite.goalValue, goal > 0 {
            let unit = invite.mode == .raceTime ? "min" : "mi"
            let number =
                goal == goal.rounded()
                ? "\(Int(goal))" : String(format: "%.1f", goal)
            return "\(invite.mode.title) · \(number) \(unit) · \(activity)"
        }
        return "\(invite.mode.title) · \(activity)"
    }

    // MARK: - Starting now

    /// Friends' walks open right now that this user isn't already invited to
    /// (those show as invites below) — the Spotify-Jam door: join theirs
    /// rather than starting a second walk a metre away.
    private var startingNow: [JoinableFriendSession] {
        let invited = Set(buddy.invites.map(\.id))
        return buddy.joinableFriendSessions.filter {
            !invited.contains($0.sessionId) && ($0.hostIsFriend ?? true)
        }
    }

    @ViewBuilder
    private var startingNowSection: some View {
        if !startingNow.isEmpty {
            VStack(alignment: .leading, spacing: MADTheme.Spacing.sm) {
                sectionTitle("Starting now")
                VStack(spacing: 0) {
                    ForEach(Array(startingNow.prefix(3).enumerated()), id: \.element.id) { index, open in
                        if index > 0 { Divider().background(Color.white.opacity(0.12)) }
                        startingNowRow(open)
                    }
                }
                .background(panel())
            }
        }
    }

    private func startingNowRow(_ open: JoinableFriendSession) -> some View {
        HStack(spacing: MADTheme.Spacing.md) {
            AvatarView(name: open.hostDisplayName, imageURL: open.hostProfileImageUrl, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(open.hostDisplayName)'s \(open.isRunning ? "run" : "walk")")
                    .font(MADTheme.Typography.bodyBold)
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                Text(open.status == .active
                     ? "Out now · \(open.participantCount) in"
                     : "Waiting to start · \(open.participantCount) in")
                    .font(MADTheme.Typography.caption)
                    .foregroundStyle(Color.white.opacity(0.6))
            }
            Spacer(minLength: 0)
            Button {
                MADHaptics.action()
                join(open)
            } label: {
                Group {
                    if joiningId == open.sessionId {
                        ProgressView().tint(WizardPalette.onAccent)
                    } else {
                        Text("Join")
                    }
                }
                .font(MADTheme.Typography.smallBold)
                .frame(width: 72, height: 36)
                .background(Capsule().fill(WizardPalette.accent))
                .foregroundStyle(WizardPalette.onAccent)
            }
            .buttonStyle(.plain)
            .disabled(joiningId != nil)
        }
        .padding(.horizontal, MADTheme.Spacing.md)
        .padding(.vertical, MADTheme.Spacing.sm + 2)
    }

    private func join(_ open: JoinableFriendSession) {
        guard joiningId == nil else { return }
        joiningId = open.sessionId
        Task {
            do {
                try await buddy.join(sessionId: open.sessionId)
                if let joined = buddy.session { onCreated(joined) }
            } catch {
                buddy.errorMessage =
                    (error as? LocalizedError)?.errorDescription ?? "Couldn't join that walk."
            }
            joiningId = nil
        }
    }

    /// An open walk hosted by someone you've ticked — create would make a
    /// second walk beside theirs.
    private var twinForSelection: JoinableFriendSession? {
        startingNow.first { selected.contains($0.hostUserId) }
    }

    // MARK: - Inviting tray

    private var selectedPeople: [BuddyCandidate] {
        buddy.candidates.filter { selected.contains($0.userId) }
    }

    /// "Aaron", "Aaron & Jess", "Aaron, Jess & 2 more" — names, not a count,
    /// so the button says exactly who'll be invited.
    private var selectedNamesText: String {
        let names = selectedPeople.map(\.displayName)
        switch names.count {
        case 0: return "\(selected.count)"
        case 1: return names[0]
        case 2: return "\(names[0]) & \(names[1])"
        default: return "\(names[0]), \(names[1]) & \(names.count - 2) more"
        }
    }

    private var invitingTray: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Text("Inviting")
                    .font(MADTheme.Typography.caption)
                    .foregroundStyle(Color.white.opacity(0.6))
                ForEach(selectedPeople) { person in
                    Button {
                        MADHaptics.tap()
                        withAnimation(MADTheme.Animation.quick) { _ = selected.remove(person.userId) }
                    } label: {
                        HStack(spacing: 6) {
                            AvatarView(name: person.displayName, imageURL: person.profileImageUrl, size: 22)
                            Text(person.displayName)
                                .font(MADTheme.Typography.smallBold)
                                .lineLimit(1)
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .heavy))
                                .foregroundStyle(Color.white.opacity(0.6))
                                .accessibilityHidden(true)
                        }
                        .foregroundStyle(Color.white)
                        .padding(.leading, 3)
                        .padding(.trailing, 10)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.white.opacity(0.14)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove \(person.displayName)")
                }
            }
            .padding(.horizontal, 2)
        }
        .frame(height: 30)
    }

    // MARK: - Partners

    /// Miles you've actually put in together.
    ///
    /// The retention line. Nothing in the app recorded that two people had
    /// walked forty miles across twelve walks, which is the number that turns a
    /// shared habit into a thing you have rather than one you keep
    /// re-arranging. Hidden until there IS a history — an empty "0 walks" panel
    /// on someone's first day is discouraging, not motivating.
    @ViewBuilder
    private var partnersSection: some View {
        if !buddy.partners.isEmpty {
            VStack(alignment: .leading, spacing: MADTheme.Spacing.sm) {
                HStack {
                    sectionTitle("You've walked with")
                    Spacer()
                    // The counts below are a summary of an archive that, until
                    // this link, had nowhere to be opened from.
                    Button {
                        MADHaptics.tap()
                        showHistory = true
                    } label: {
                        HStack(spacing: 3) {
                            Text("See all")
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .bold))
                        }
                        .font(MADTheme.Typography.caption)
                        .foregroundStyle(Color.white.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                }
                VStack(spacing: 0) {
                    ForEach(Array(buddy.partners.prefix(5).enumerated()), id: \.element.id) {
                        index, partner in
                        if index > 0 {
                            Divider().background(Color.white.opacity(0.12))
                        }
                        partnerRow(partner)
                    }
                }
                .background(panel())
            }
        }
    }

    /// Tapping a partner picks them for THIS walk — the stat and the action are
    /// the same gesture, so "we've walked 14 miles together" is one tap from
    /// "let's go again".
    private func partnerRow(_ partner: BuddyPartner) -> some View {
        let canPick = buddy.candidates.contains { $0.userId == partner.userId }
        return Button {
            guard canPick else { return }
            MADHaptics.tap()
            withAnimation(MADTheme.Animation.quick) {
                if selected.contains(partner.userId) {
                    selected.remove(partner.userId)
                } else {
                    selected.insert(partner.userId)
                }
            }
        } label: {
            HStack(spacing: MADTheme.Spacing.md) {
                AvatarView(
                    name: partner.displayName,
                    imageURL: partner.profileImageUrl,
                    size: 36
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(partner.displayName)
                        .font(MADTheme.Typography.smallBold)
                        .foregroundStyle(Color.white)
                    Text(partner.summary)
                        .font(MADTheme.Typography.caption)
                        .foregroundStyle(Color.white.opacity(0.6))
                }
                Spacer(minLength: 0)
                if canPick {
                    Image(
                        systemName: selected.contains(partner.userId)
                            ? "checkmark.circle.fill" : "circle"
                    )
                    .font(.system(size: 18))
                    .foregroundStyle(
                        selected.contains(partner.userId)
                            ? accent : Color.white.opacity(0.3))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!canPick)
    }

    // MARK: - Goal

    private var goalSection: some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.sm) {
            sectionTitle(mode == .raceTime ? "For how long?" : "How far?")
            HStack(spacing: MADTheme.Spacing.sm) {
                ForEach(mode.goalOptions, id: \.self) { value in
                    goalChip(value)
                }
            }
        }
    }

    private func goalChip(_ value: Double) -> some View {
        let isOn = goal == value
        return Button {
            MADHaptics.tap()
            withAnimation(MADTheme.Animation.quick) { goal = value }
        } label: {
            VStack(spacing: 1) {
                Text(shortGoalNumber(value))
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                Text(mode.goalUnitLabel)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .opacity(0.7)
            }
            .frame(maxWidth: .infinity)
            .frame(height: Self.controlHeight)
            .background(
                RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                    .fill(isOn ? accent : Color.white.opacity(0.12))
            )
            .foregroundStyle(isOn ? WizardPalette.onAccent : Color.white.opacity(0.8))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Schedule

    /// "Now" vs "Later" for the walk's start.
    ///
    /// Off by default and collapsed to a single row, because the overwhelmingly
    /// common case is starting immediately and a date picker sitting open in
    /// that path is pure noise. When it's on, the server owns the start — it
    /// promotes the session on time whether or not anyone has the app open,
    /// which is the whole point of booking one.
    private var scheduleSection: some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.sm) {
            Button {
                MADHaptics.tap()
                isScheduled.toggle()
                if isScheduled {
                    // Round up to the next 5 minutes so the default reads as a
                    // plan ("6:15") rather than a timestamp ("6:12").
                    let soon = Date().addingTimeInterval(60 * 60)
                    let step: TimeInterval = 300
                    scheduledDate = Date(
                        timeIntervalSince1970:
                            (soon.timeIntervalSince1970 / step).rounded(.up) * step)
                }
            } label: {
                HStack(spacing: MADTheme.Spacing.sm) {
                    Image(systemName: isScheduled ? "calendar.badge.clock" : "bolt.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.white.opacity(isScheduled ? 1 : 0.7))
                    Text(isScheduled ? "Starting later" : "Starting now")
                        .font(MADTheme.Typography.smallBold)
                        .foregroundStyle(Color.white)
                    Spacer(minLength: 0)
                    Text(isScheduled ? "Change" : "Schedule it")
                        .font(MADTheme.Typography.caption)
                        .foregroundStyle(Color.white.opacity(0.8))
                }
                .padding(.horizontal, 14)
                .frame(height: Self.chipHeight)
                .frame(maxWidth: .infinity)
                .background(panel(MADTheme.CornerRadius.medium))
            }
            .buttonStyle(.plain)

            if isScheduled {
                DatePicker(
                    "Starts at",
                    selection: $scheduledDate,
                    in: Date().addingTimeInterval(120)...Date().addingTimeInterval(60 * 60 * 24 * 14),
                    displayedComponents: [.date, .hourAndMinute]
                )
                .datePickerStyle(.compact)
                .tint(accent)
                .padding(.horizontal, 14)
                .frame(height: Self.chipHeight)
                .frame(maxWidth: .infinity)
                .background(panel(MADTheme.CornerRadius.medium))
                .foregroundStyle(Color.white)

                repeatRow
            }
        }
    }

    /// Make it a habit.
    ///
    /// Offered only once a time is set, because that's the moment it becomes a
    /// plan rather than an impulse — and because the routine's time IS this
    /// picker's time-of-day. Picking no days is the normal case and costs
    /// nothing; picking some creates a standing walk alongside this one.
    private var repeatRow: some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.xs) {
            HStack(spacing: 6) {
                Image(systemName: "repeat")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.white.opacity(repeatDays.isEmpty ? 0.6 : 1))
                Text("Repeat weekly")
                    .font(MADTheme.Typography.smallBold)
                    .foregroundStyle(Color.white)
                Spacer(minLength: 0)
                if !repeatDays.isEmpty {
                    Text(scheduledDate, format: .dateTime.hour().minute())
                        .font(MADTheme.Typography.caption)
                        .foregroundStyle(Color.white.opacity(0.85))
                }
            }

            HStack(spacing: 4) {
                // 0 = Sunday, matching the server's EXTRACT(DOW).
                ForEach(0..<7, id: \.self) { day in
                    dayChip(day)
                }
            }

            Text(
                repeatDays.isEmpty
                    ? "Just this once."
                    : "We'll set this up every week and invite the same people."
            )
            .font(MADTheme.Typography.caption)
            .foregroundStyle(Color.white.opacity(0.55))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(panel(MADTheme.CornerRadius.medium))
    }

    private func dayChip(_ day: Int) -> some View {
        // Single letters, Sunday-first. Deliberately not localized weekday
        // symbols: those are 3 letters in most locales and seven of them will
        // not fit a phone width.
        let letters = ["S", "M", "T", "W", "T", "F", "S"]
        let isOn = repeatDays.contains(day)
        return Button {
            MADHaptics.tap()
            withAnimation(MADTheme.Animation.quick) {
                if isOn { repeatDays.remove(day) } else { repeatDays.insert(day) }
            }
        } label: {
            Text(letters[day])
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .frame(maxWidth: .infinity)
                .frame(height: 34)
                .background(Circle().fill(isOn ? accent : Color.white.opacity(0.12)))
                .foregroundStyle(isOn ? WizardPalette.onAccent : Color.white.opacity(0.7))
        }
        .buttonStyle(.plain)
    }

    /// Standing walks already set up, so this step is also where you turn one
    /// off. Hidden entirely when there are none — an empty list here would just
    /// be noise on the screen someone opens to start walking.
    @ViewBuilder
    private var routinesSection: some View {
        if !buddy.routines.isEmpty {
            VStack(alignment: .leading, spacing: MADTheme.Spacing.sm) {
                sectionTitle("Your routines")
                VStack(spacing: 0) {
                    ForEach(Array(buddy.routines.enumerated()), id: \.element.id) { index, routine in
                        if index > 0 {
                            Divider().background(Color.white.opacity(0.12))
                        }
                        routineRow(routine)
                    }
                }
                .background(panel())
            }
        }
    }

    private func routineRow(_ routine: BuddyRecurringWalk) -> some View {
        HStack(spacing: MADTheme.Spacing.md) {
            Image(systemName: routine.isRunning ? "figure.run" : "figure.walk")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.white.opacity(routine.isActive ? 1 : 0.4))
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(routine.daysText) · \(routine.timeText)")
                    .font(MADTheme.Typography.smallBold)
                    .foregroundStyle(Color.white.opacity(routine.isActive ? 1 : 0.5))
                Text(routine.mode.title)
                    .font(MADTheme.Typography.caption)
                    .foregroundStyle(Color.white.opacity(0.55))
            }

            Spacer(minLength: MADTheme.Spacing.sm)

            Toggle(
                "",
                isOn: Binding(
                    get: { routine.isActive },
                    set: { on in Task { await buddy.setRoutineActive(routine.id, isActive: on) } }
                )
            )
            .labelsHidden()
            .tint(accent)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        // Delete lives in a context menu rather than a visible button: it's
        // rare, destructive, and the toggle beside it already covers "not this
        // week" without losing the setup.
        .contextMenu {
            Button(role: .destructive) {
                Task { await buddy.deleteRoutine(routine.id) }
            } label: {
                Label("Delete routine", systemImage: "trash")
            }
        }
    }

    // MARK: - Friends

    private var friendSection: some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.sm) {
            HStack {
                sectionTitle("Who's coming?")
                Spacer()

            }

            if buddy.candidates.isEmpty {
                emptyFriendsCard
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(buddy.candidates.enumerated()), id: \.element.id) { index, candidate in
                        if index > 0 {
                            Divider().background(Color.white.opacity(0.12))
                        }
                        friendRow(candidate)
                    }
                }
                .background(panel())
            }
        }
    }

    /// The candidate list is filtered to friends whose build has Buddy Walks and
    /// who haven't opted out — so "nobody here" can mean "none of them have
    /// updated", which must never be phrased as a problem with their friend
    /// list. It must also not be a dead end: making the lobby anyway and
    /// inviting from there is a completely normal path, so it's stated as the
    /// next step rather than left as a consolation prize.
    private var emptyFriendsCard: some View {
        VStack(spacing: MADTheme.Spacing.sm) {
            Image(systemName: "person.2")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.8))
                .accessibilityHidden(true)
            Text("Nobody to invite from here yet")
                .font(MADTheme.Typography.smallBold)
                .foregroundStyle(Color.white.opacity(0.9))
                .multilineTextAlignment(.center)
            Text(
                "Friends show up once they're on a build with buddy walks. Make the lobby anyway — you can invite them from there the moment they update."
            )
            .font(MADTheme.Typography.caption)
            .foregroundStyle(Color.white.opacity(0.65))
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(MADTheme.Spacing.lg)
        .background(panel())
    }

    private func friendRow(_ candidate: BuddyCandidate) -> some View {
        let isOn = selected.contains(candidate.userId)
        return Button {
            MADHaptics.tap()
            withAnimation(MADTheme.Animation.quick) {
                if isOn { selected.remove(candidate.userId) } else { selected.insert(candidate.userId) }
            }
        } label: {
            HStack(spacing: MADTheme.Spacing.md) {
                AvatarView(
                    name: candidate.displayName,
                    imageURL: candidate.profileImageUrl,
                    size: 40
                )
                Text(candidate.displayName)
                    .font(MADTheme.Typography.body)
                    .foregroundStyle(Color.white)
                Spacer()
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(isOn ? accent : Color.white.opacity(0.3))
            }
            .padding(.horizontal, MADTheme.Spacing.md)
            .padding(.vertical, MADTheme.Spacing.sm + 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Footer

    /// ONE action, on the two steps that need one: Next on Who (multi-select
    /// can't advance on a tap) and Create on the goal sub-step.
    private var footer: some View {
        WizardFooter {
            // Everyone who'll be invited, always on screen — however far down
            // the list they were ticked. Tap ✕ to drop one.
            if !selected.isEmpty { invitingTray }
            WizardPrimaryButton(
                title: primaryTitle,
                icon: step == .who ? "arrow.right" : "figure.2",
                isBusy: isCreating
            ) {
                MADHaptics.action()
                if step == .who {
                    advance(to: .activity)
                } else if let twin = twinForSelection {
                    // Someone you're inviting already has a walk open —
                    // the "we both pressed start" case, caught before it
                    // happens.
                    pendingTwin = twin
                } else {
                    Task { await create() }
                }
            }
            Text(footerCaption)
                .font(MADTheme.Typography.caption)
                .foregroundStyle(Color.white.opacity(0.6))
        }
    }

    private var footerCaption: String {
        switch step {
        case .who: return "You can invite more people from the lobby too."
        default: return "Nobody moves until you start it."
        }
    }

    /// Says CREATE, never START.
    ///
    /// This button has always opened a lobby — the walk doesn't begin until the
    /// host taps Start in there — but every label it has worn said "start", so
    /// the screen promised something it didn't do. "Create lobby" describes the
    /// actual outcome, and the caption under the button closes the gap.
    private var primaryTitle: String {
        if isCreating { return "Creating…" }
        if step == .who {
            return selected.isEmpty ? "Next" : "Next with \(selectedNamesText)"
        }
        return selected.isEmpty ? "Create lobby" : "Create & invite \(selectedNamesText)"
    }

    // MARK: - Helpers

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(MADTheme.Typography.headline)
            .foregroundStyle(Color.white)
    }

    /// "2" / "1.5" — the unit is rendered separately in the chip.
    private func shortGoalNumber(_ value: Double) -> String {
        value == value.rounded() ? "\(Int(value))" : String(format: "%.1f", value)
    }

    /// Put back the mode and activity from last time. Friends are restored
    /// separately, because they can only be re-selected once the candidate
    /// list exists.
    private func restoreLastSetup() {
        guard !didRestore else { return }
        didRestore = true
        if let saved = BuddyMode(rawValue: lastModeRaw) {
            mode = saved
            if saved.needsGoal { goal = saved.defaultGoal }
        }
        isRun = lastIsRun
    }

    private func rememberSetup() {
        lastModeRaw = mode.rawValue
        lastIsRun = isRun
    }

    private func create() async {
        guard !isCreating else { return }
        isCreating = true
        defer { isCreating = false }
        do {
            let state = try await buddy.createSession(
                mode: mode,
                goalValue: mode.needsGoal ? goal : nil,
                activityType: activityType,
                inviteUserIds: Array(selected),
                // Nobody picked = a room made to invite from. That's a
                // genuinely different intent from inviting named friends, and
                // telling them apart is the whole point of tracking origin.
                origin: selected.isEmpty ? .code : .invite,
                scheduledStartAt: isScheduled ? scheduledDate : nil
            )
            // The routine is a SEPARATE object, created after the session and
            // deliberately not inside its failure path: if this throws, the
            // walk they just made still exists and still opens. Losing the
            // repeat is recoverable; losing the walk is not.
            if isScheduled, !repeatDays.isEmpty {
                try? await buddy.createRoutine(
                    mode: mode,
                    goalValue: mode.needsGoal ? goal : nil,
                    activityType: activityType,
                    inviteUserIds: Array(selected),
                    daysOfWeek: Array(repeatDays),
                    at: scheduledDate
                )
            }
            rememberSetup()
            MADHaptics.success()
            onCreated(state)
        } catch {
            MADHaptics.error()
            // Reported through the service so the ONE alert the flow owns is
            // the only place an error can appear. A local alert here couldn't
            // be raised at all once this stopped being a sheet with its own
            // presentation context.
            buddy.errorMessage =
                (error as? LocalizedError)?.errorDescription ?? "Couldn't create the lobby."
        }
    }
}
