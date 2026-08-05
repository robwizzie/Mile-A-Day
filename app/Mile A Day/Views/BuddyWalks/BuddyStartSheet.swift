import SwiftUI

/// Start a buddy walk, or join one someone else started.
///
/// Start-vs-join is the FIRST thing the screen asks, as a segmented control at
/// the top. Earlier passes buried joining behind a "#" toolbar glyph (nobody
/// knew what it meant), then added a second join button in the footer — which
/// left the sheet with two ways in and, worse, a primary button reading "Start
/// with a share code" sitting directly above "Join with their code". Two
/// code-flavoured buttons, opposite meanings. One switch at the top removes the
/// ambiguity: pick a lane, then the rest of the screen is only about that lane.
///
/// Within the Start lane it opens on "Just Together" with no goal to set, so
/// the common case — two friends about to walk — is pick-a-friend-and-go.
struct BuddyStartSheet: View {
    /// Handed back so the caller can push straight into the lobby.
    let onCreated: (BuddySessionState) -> Void

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var buddy = BuddySessionService.shared

    private enum Lane: String, CaseIterable {
        case start, join
        var title: String { self == .start ? "Start one" : "Join one" }
        var icon: String { self == .start ? "plus.circle.fill" : "arrow.right.circle.fill" }
    }

    @State private var lane: Lane = .start
    @State private var mode: BuddyMode = .together
    @State private var goal: Double = BuddyMode.together.defaultGoal
    @State private var isRun = false
    @State private var selected: Set<String> = []
    @State private var isCreating = false
    @State private var joinCode = ""
    @State private var isJoining = false
    @FocusState private var codeFocused: Bool
    /// Errors are mirrored into LOCAL state. Driving `.alert(isPresented:)`
    /// straight off `buddy.errorMessage` meant the binding's setter wrote to an
    /// @Published from inside a view update — "Publishing changes from within
    /// view updates is not allowed". Local state has no such problem, and the
    /// mirror below runs after the update, not during it.
    @State private var errorText: String?
    /// Book the walk for later instead of starting it from the lobby. Off by
    /// default — starting now is overwhelmingly the common case.
    @State private var isScheduled = false
    @State private var scheduledDate = Date().addingTimeInterval(60 * 60)
    /// Weekdays this walk repeats on, 0 = Sunday (matching the server's
    /// EXTRACT(DOW)). Empty = a one-off, which is the default.
    @State private var repeatDays: Set<Int> = []

    /// Last setup, restored on open.
    ///
    /// Buddy walks are a habit with a fixed shape — the same person, the same
    /// activity, the same mode, most days. Re-picking all three every time was
    /// most of why setting one up "takes forever", and none of those taps ever
    /// carried information. Restored rather than hardcoded, so a first-time
    /// user still lands on the zero-config default (Just Together, walking).
    @AppStorage("buddyLastModeV1") private var lastModeRaw = BuddyMode.together.rawValue
    @AppStorage("buddyLastIsRunV1") private var lastIsRun = false
    @AppStorage("buddyLastInviteesV1") private var lastInvitees = ""
    /// One-shot: restoring must not fight the user's taps on a later re-render.
    @State private var didRestore = false

    private var activityType: String { isRun ? "running" : "walking" }
    private var accent: Color { MADTheme.workoutColor(activityType) }

    /// Every pill control on this screen resolves to the same outer height.
    /// A segmented capsule pads its chips by 4 on each side, so the chip is
    /// `controlHeight - 8` and the capsule around it lands back on
    /// `controlHeight` — that's what makes the two segmented rows and the
    /// footer button read as one family instead of three near-misses.
    private static let controlHeight: CGFloat = 52
    private static let chipHeight: CGFloat = controlHeight - 8
    /// Fixed so BOTH grid rows are equal — otherwise each row sizes to its
    /// tallest subtitle and the 2x2 comes out lopsided.
    private static let modeTileHeight: CGFloat = 108

    /// The plain card behind repeated elements.
    ///
    /// `madLiquidGlass` is a REAL blur (`glassEffect`, or `.ultraThinMaterial`
    /// pre-iOS 26). Four mode tiles plus the friend list meant 5+ blurred
    /// surfaces recompositing on every selection tap, animated — which is what
    /// made this screen feel sluggish. The hero card keeps its glass; the
    /// things you tap repeatedly get a flat fill that is visually
    /// indistinguishable on this background and costs nothing.
    private func plainCard(_ radius: CGFloat = MADTheme.CornerRadius.large) -> some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(MADTheme.Colors.madWhite.opacity(0.06))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(MADTheme.Colors.madWhite.opacity(0.10), lineWidth: 1)
            )
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                MADTheme.Colors.appBackgroundGradient.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: MADTheme.Spacing.lg) {
                        lanePicker
                        if lane == .start { startLane } else { joinLane }
                        // Clears the sticky footer (button + the reassurance
                        // line under it, which the join lane doesn't render).
                        Color.clear.frame(height: 140)
                    }
                    .padding(.horizontal, MADTheme.Spacing.md)
                    .padding(.top, MADTheme.Spacing.sm)
                }

                footer
            }
            .navigationTitle(isRun ? "Buddy Run" : "Buddy Walk")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task {
                // This screen is several taps in a row; warm the Taptic Engine
                // so the FIRST one lands as fast as the rest.
                MADHaptics.warmUp()
                restoreLastSetup()
                // Both already prefetched on the dashboard, so the sheet opens
                // populated and these are a refresh, not a blocking load. Run
                // concurrently — they have nothing to do with each other.
                async let candidates: Void = buddy.loadCandidates()
                async let routines: Void = buddy.loadRoutines()
                _ = await (candidates, routines)
                // Re-run once the list has landed: a cold launch can open this
                // sheet before the prefetch finishes, and a remembered friend
                // can only be re-selected once they're actually in the list.
                restoreInvitees()
            }
            .onChange(of: buddy.errorMessage) { _, newValue in
                guard let newValue else { return }
                errorText = newValue
                buddy.errorMessage = nil
            }
            .alert(
                "Couldn't create lobby",
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
    }

    @ViewBuilder
    private var startLane: some View {
        summaryHeader
        activityToggle
        modeSection
        if mode.needsGoal { goalSection }
        scheduleSection
        friendSection
        routinesSection
    }

    // MARK: - Lane picker

    private var lanePicker: some View {
        HStack(spacing: 4) {
            ForEach(Lane.allCases, id: \.self) { option in
                laneChip(option)
            }
        }
        .padding(4)
        .background(Capsule().fill(MADTheme.Colors.madWhite.opacity(0.10)))
    }

    private func laneChip(_ option: Lane) -> some View {
        let isOn = lane == option
        return Button {
            MADHaptics.tap()
            // No withAnimation and no focus write here, deliberately. Animating
            // this cross-fades two whole subtrees, and toggling focus from the
            // chip drove a keyboard present/dismiss cycle on every tap — both
            // land as input lag. The join lane focuses itself once it exists.
            lane = option
        } label: {
            HStack(spacing: 6) {
                Image(systemName: option.icon).font(.system(size: 13, weight: .semibold))
                Text(option.title).font(MADTheme.Typography.bodyBold)
            }
            .frame(maxWidth: .infinity)
            .frame(height: Self.chipHeight)
            .background(Capsule().fill(isOn ? accent : .clear))
            .foregroundStyle(
                isOn ? MADTheme.Colors.madWhite : MADTheme.Colors.madWhite.opacity(0.6))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Join lane

    private var joinLane: some View {
        VStack(spacing: MADTheme.Spacing.lg) {
            VStack(spacing: MADTheme.Spacing.sm) {
                ZStack {
                    Circle().fill(accent.opacity(0.18)).frame(width: 72, height: 72)
                    Image(systemName: "number")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(accent)
                }
                Text("Enter their code")
                    .font(MADTheme.Typography.title3)
                    .foregroundStyle(MADTheme.Colors.madWhite)
                Text("Six characters, shown on the host's screen while they wait.")
                    .font(MADTheme.Typography.subheadline)
                    .foregroundStyle(MADTheme.Colors.madWhite.opacity(0.65))
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, MADTheme.Spacing.lg)
            .padding(.horizontal, MADTheme.Spacing.md)
            .madLiquidGlass(cornerRadius: MADTheme.CornerRadius.extraLarge)

            TextField("ABC123", text: $joinCode)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .multilineTextAlignment(.center)
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .tracking(8)
                .foregroundStyle(MADTheme.Colors.madWhite)
                .focused($codeFocused)
                .padding(MADTheme.Spacing.md)
                .madLiquidGlass(cornerRadius: MADTheme.CornerRadius.large)
                .onChange(of: joinCode) { _, newValue in
                    joinCode = String(newValue.uppercased().prefix(6))
                }
                .onAppear { codeFocused = true }
        }
    }

    // MARK: - Summary header

    /// The whole setup, restated as one sentence. This is the piece that makes
    /// the screen self-explanatory: every control below visibly changes it, so
    /// nobody has to hold four separate choices in their head.
    private var summaryHeader: some View {
        VStack(spacing: MADTheme.Spacing.sm) {
            ZStack {
                Circle()
                    .fill(accent.opacity(0.18))
                    .frame(width: 72, height: 72)
                Circle()
                    .strokeBorder(accent.opacity(0.5), lineWidth: 1.5)
                    .frame(width: 72, height: 72)
                Image(systemName: mode.icon)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(accent)
            }
            .animation(MADTheme.Animation.quick, value: mode)

            Text(summaryTitle)
                .font(MADTheme.Typography.title2)
                .foregroundStyle(MADTheme.Colors.madWhite)
                .multilineTextAlignment(.center)

            Text(summarySubtitle)
                .font(MADTheme.Typography.subheadline)
                .foregroundStyle(MADTheme.Colors.madWhite.opacity(0.65))
                .multilineTextAlignment(.center)

            if !selectedCandidates.isEmpty { selectedAvatars }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, MADTheme.Spacing.md)
        .padding(.horizontal, MADTheme.Spacing.md)
        .madLiquidGlass(cornerRadius: MADTheme.CornerRadius.extraLarge)
    }

    private var summaryTitle: String {
        let verb = isRun ? "Run" : "Walk"
        switch mode {
        case .together: return "\(verb) together"
        case .coopGoal: return "\(goalLabel(goal)) together"
        case .raceGoal: return "Race to \(goalLabel(goal))"
        case .raceTime: return "Furthest in \(goalLabel(goal))"
        }
    }

    private var selectedCandidates: [BuddyCandidate] {
        buddy.candidates.filter { selected.contains($0.userId) }
    }

    /// Faces, not just a count — the header should feel like the walk is
    /// already half real. Overlap is built with negative HStack spacing rather
    /// than `.offset`, which draws outside layout bounds and would measure the
    /// stack wrong (ios.md).
    private var selectedAvatars: some View {
        HStack(spacing: -10) {
            ForEach(selectedCandidates.prefix(5)) { candidate in
                AvatarView(
                    name: candidate.displayName,
                    imageURL: candidate.profileImageUrl,
                    size: 30
                )
                .overlay(
                    Circle().strokeBorder(MADTheme.Colors.madBlack.opacity(0.85), lineWidth: 2)
                )
            }
            if selectedCandidates.count > 5 {
                Text("+\(selectedCandidates.count - 5)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(MADTheme.Colors.madWhite.opacity(0.8))
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(MADTheme.Colors.madWhite.opacity(0.15)))
                    .padding(.leading, 10)
            }
        }
        .padding(.top, 2)
    }

    private var summarySubtitle: String {
        guard !selected.isEmpty else {
            return "Nobody invited yet — you'll get a code to share"
        }
        let names = selectedCandidates.map(\.displayName)
        switch names.count {
        case 0: return "with \(selected.count) friends"
        case 1: return "with \(names[0])"
        case 2: return "with \(names[0]) and \(names[1])"
        default: return "with \(names[0]) and \(names.count - 1) others"
        }
    }

    // MARK: - Activity

    private var activityToggle: some View {
        HStack(spacing: 4) {
            activityChip(run: false, icon: "figure.walk", label: "Walk")
            activityChip(run: true, icon: "figure.run", label: "Run")
        }
        .padding(4)
        .background(Capsule().fill(MADTheme.Colors.madWhite.opacity(0.10)))
    }

    private func activityChip(run: Bool, icon: String, label: String) -> some View {
        let isOn = isRun == run
        return Button {
            MADHaptics.tap()
            withAnimation(MADTheme.Animation.quick) { isRun = run }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 14, weight: .semibold))
                Text(label).font(MADTheme.Typography.bodyBold)
            }
            .frame(maxWidth: .infinity)
            .frame(height: Self.chipHeight)
            .background(
                Capsule().fill(
                    isOn ? MADTheme.workoutColor(run ? "running" : "walking") : .clear)
            )
            .foregroundStyle(
                isOn ? MADTheme.Colors.madWhite : MADTheme.Colors.madWhite.opacity(0.6))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Mode

    private var modeSection: some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.sm) {
            sectionTitle("How are we doing this?")
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: MADTheme.Spacing.sm),
                          GridItem(.flexible(), spacing: MADTheme.Spacing.sm)],
                spacing: MADTheme.Spacing.sm
            ) {
                ForEach(BuddyMode.allCases) { option in
                    modeTile(option)
                }
            }
        }
    }

    private func modeTile(_ option: BuddyMode) -> some View {
        let isOn = mode == option
        return Button {
            MADHaptics.tap()
            withAnimation(MADTheme.Animation.quick) {
                mode = option
                goal = option.defaultGoal
            }
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 0) {
                    Image(systemName: option.icon)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(isOn ? accent : MADTheme.Colors.madWhite.opacity(0.55))
                    Spacer(minLength: 0)
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(accent)
                        .opacity(isOn ? 1 : 0)
                }
                Text(option.title)
                    .font(MADTheme.Typography.smallBold)
                    .foregroundStyle(MADTheme.Colors.madWhite)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Text(option.subtitle)
                    .font(MADTheme.Typography.caption)
                    .foregroundStyle(MADTheme.Colors.madWhite.opacity(0.6))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(12)
            .frame(height: Self.modeTileHeight, alignment: .topLeading)
            .background(plainCard())
            .overlay(
                RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                    .stroke(isOn ? accent : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
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
                    .fill(isOn ? accent : MADTheme.Colors.madWhite.opacity(0.10))
            )
            .foregroundStyle(
                isOn ? MADTheme.Colors.madWhite : MADTheme.Colors.madWhite.opacity(0.75))
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
                        .foregroundStyle(isScheduled ? accent : MADTheme.Colors.madWhite.opacity(0.7))
                    Text(isScheduled ? "Starting later" : "Starting now")
                        .font(MADTheme.Typography.smallBold)
                        .foregroundStyle(MADTheme.Colors.madWhite)
                    Spacer(minLength: 0)
                    Text(isScheduled ? "Change" : "Schedule it")
                        .font(MADTheme.Typography.caption)
                        .foregroundStyle(accent)
                }
                .padding(.horizontal, 14)
                .frame(height: Self.chipHeight)
                .frame(maxWidth: .infinity)
                .background(plainCard(MADTheme.CornerRadius.medium))
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
                .background(plainCard(MADTheme.CornerRadius.medium))
                .foregroundStyle(MADTheme.Colors.madWhite)

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
                    .foregroundStyle(
                        repeatDays.isEmpty ? MADTheme.Colors.madWhite.opacity(0.6) : accent)
                Text("Repeat weekly")
                    .font(MADTheme.Typography.smallBold)
                    .foregroundStyle(MADTheme.Colors.madWhite)
                Spacer(minLength: 0)
                if !repeatDays.isEmpty {
                    Text(scheduledDate, format: .dateTime.hour().minute())
                        .font(MADTheme.Typography.caption)
                        .foregroundStyle(accent)
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
            .foregroundStyle(MADTheme.Colors.madWhite.opacity(0.5))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(plainCard(MADTheme.CornerRadius.medium))
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
                .background(
                    Circle().fill(isOn ? accent : MADTheme.Colors.madWhite.opacity(0.10))
                )
                .foregroundStyle(
                    isOn ? MADTheme.Colors.madWhite : MADTheme.Colors.madWhite.opacity(0.65))
        }
        .buttonStyle(.plain)
    }

    /// Standing walks already set up, so the sheet is also where you turn one
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
                            Divider().background(MADTheme.Colors.madWhite.opacity(0.08))
                        }
                        routineRow(routine)
                    }
                }
                .background(plainCard())
            }
        }
    }

    private func routineRow(_ routine: BuddyRecurringWalk) -> some View {
        HStack(spacing: MADTheme.Spacing.md) {
            Image(systemName: routine.isRunning ? "figure.run" : "figure.walk")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(
                    routine.isActive
                        ? MADTheme.workoutColor(routine.activityType)
                        : MADTheme.Colors.madWhite.opacity(0.35)
                )
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(routine.daysText) · \(routine.timeText)")
                    .font(MADTheme.Typography.smallBold)
                    .foregroundStyle(
                        MADTheme.Colors.madWhite.opacity(routine.isActive ? 1 : 0.5))
                Text(routine.mode.title)
                    .font(MADTheme.Typography.caption)
                    .foregroundStyle(MADTheme.Colors.madWhite.opacity(0.5))
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
                if !selected.isEmpty {
                    Text("\(selected.count) invited")
                        .font(MADTheme.Typography.caption)
                        .foregroundStyle(accent)
                }
            }

            if buddy.candidates.isEmpty {
                emptyFriendsCard
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(buddy.candidates.enumerated()), id: \.element.id) { index, candidate in
                        if index > 0 {
                            Divider().background(MADTheme.Colors.madWhite.opacity(0.08))
                        }
                        friendRow(candidate)
                    }
                }
                .background(plainCard())
            }
        }
    }

    /// The candidate list is filtered to friends whose build has Buddy Walks and
    /// who haven't opted out — so "nobody here" can mean "none of them have
    /// updated", which must never be phrased as a problem with their friend
    /// list.
    ///
    /// It must also not be a dead end. The old copy mentioned the share code in
    /// passing, at the bottom, in the dimmest text on the card — so the one
    /// thing you CAN still do read as a consolation prize. Creating the lobby
    /// anyway and sending the code is a completely normal path (it's how you
    /// walk with someone who hasn't updated), so it's stated as the next step.
    private var emptyFriendsCard: some View {
        VStack(spacing: MADTheme.Spacing.sm) {
            Image(systemName: "qrcode")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(accent)
            Text("Nobody to invite from here yet")
                .font(MADTheme.Typography.smallBold)
                .foregroundStyle(MADTheme.Colors.madWhite.opacity(0.85))
                .multilineTextAlignment(.center)
            Text(
                "Friends show up once they're on a build with buddy walks. Create the lobby anyway — you'll get a code and a QR to send them."
            )
            .font(MADTheme.Typography.caption)
            .foregroundStyle(MADTheme.Colors.madWhite.opacity(0.6))
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(MADTheme.Spacing.lg)
        .background(plainCard())
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
                    .foregroundStyle(MADTheme.Colors.madWhite)
                Spacer()
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(isOn ? accent : MADTheme.Colors.madWhite.opacity(0.25))
            }
            .padding(.horizontal, MADTheme.Spacing.md)
            .padding(.vertical, MADTheme.Spacing.sm + 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Footer

    /// ONE action, whichever lane you're in. The scrim is opaque enough that
    /// the list underneath reads as "behind" rather than as clipped content.
    private var footer: some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [MADTheme.Colors.madBlack.opacity(0), MADTheme.Colors.madBlack],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: 28)
            .allowsHitTesting(false)

            VStack(spacing: 6) {
                primaryButton
                // The single most important sentence on this screen. Every
                // earlier label said "start", so tapping it felt like committing
                // to walking RIGHT NOW — people backed out rather than find out.
                // Nothing about the flow changed; it always opened a lobby.
                if lane == .start {
                    Text("Nobody moves until you start it.")
                        .font(MADTheme.Typography.caption)
                        .foregroundStyle(MADTheme.Colors.madWhite.opacity(0.5))
                }
            }
            .padding(.horizontal, MADTheme.Spacing.md)
            .padding(.bottom, MADTheme.Spacing.sm)
            .background(MADTheme.Colors.madBlack)
        }
    }

    private var primaryButton: some View {
        Button {
            MADHaptics.action()
            Task { lane == .start ? await create() : await join() }
        } label: {
            HStack(spacing: 8) {
                if isCreating || isJoining {
                    ProgressView().tint(MADTheme.Colors.madWhite)
                } else {
                    Image(systemName: lane == .start ? "figure.2" : "arrow.right.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                }
                Text(primaryTitle)
            }
            .font(MADTheme.Typography.bodyBold)
            .frame(maxWidth: .infinity)
            .frame(height: Self.controlHeight)
            .background(Capsule().fill(accent))
            .foregroundStyle(MADTheme.Colors.madWhite)
        }
        .buttonStyle(.plain)
        .disabled(primaryDisabled)
        .opacity(primaryDisabled ? 0.5 : 1)
    }

    private var primaryDisabled: Bool {
        if lane == .join { return joinCode.count < 6 || isJoining }
        return isCreating
    }

    /// Says CREATE, never START.
    ///
    /// This button has always opened a lobby — the walk doesn't begin until the
    /// host taps Start in there — but every label it has worn said "start", so
    /// the screen promised something it didn't do. "Create lobby" describes the
    /// actual outcome, and the caption under the button closes the gap.
    ///
    /// It also never mentions the share code: an earlier label ("Start with a
    /// share code") read as an INPUT and sat directly above the join field,
    /// which genuinely does take one. The code is a consequence of creating.
    private var primaryTitle: String {
        if lane == .join { return isJoining ? "Joining…" : "Join walk" }
        if isCreating { return "Creating…" }
        if selected.isEmpty { return "Create lobby" }
        return selected.count == 1 ? "Create & invite 1" : "Create & invite \(selected.count)"
    }

    // MARK: - Helpers

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(MADTheme.Typography.headline)
            .foregroundStyle(MADTheme.Colors.madWhite)
    }

    /// "2" / "1.5" — the unit is rendered separately in the chip.
    private func shortGoalNumber(_ value: Double) -> String {
        value == value.rounded() ? "\(Int(value))" : String(format: "%.1f", value)
    }

    private func goalLabel(_ value: Double) -> String {
        mode == .raceTime
            ? "\(Int(value)) min"
            : (value == value.rounded()
                ? "\(Int(value)) mi" : String(format: "%.1f mi", value))
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
        restoreInvitees()
    }

    /// Re-select whoever you walked with last time — but ONLY if they're still
    /// an eligible candidate. Someone who has since unfriended, opted out or
    /// dropped off a buddy-capable build must not silently reappear in the
    /// invite list, where the server would drop them anyway and the host would
    /// never learn why.
    private func restoreInvitees() {
        guard selected.isEmpty, !lastInvitees.isEmpty, !buddy.candidates.isEmpty else {
            return
        }
        let remembered = Set(lastInvitees.split(separator: ",").map(String.init))
        let stillThere = Set(buddy.candidates.map(\.userId))
        selected = remembered.intersection(stillThere)
    }

    private func rememberSetup() {
        lastModeRaw = mode.rawValue
        lastIsRun = isRun
        lastInvitees = selected.sorted().joined(separator: ",")
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
                // Nobody picked = a room made to share a code. That's a
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
            dismiss()
        } catch {
            MADHaptics.error()
            errorText =
                (error as? LocalizedError)?.errorDescription ?? "Couldn't create the lobby."
        }
    }

    private func join() async {
        guard !isJoining else { return }
        isJoining = true
        defer { isJoining = false }
        do {
            try await buddy.join(code: joinCode)
            if let session = buddy.session {
                MADHaptics.success()
                onCreated(session)
                dismiss()
            }
        } catch {
            MADHaptics.error()
            errorText =
                (error as? LocalizedError)?.errorDescription ?? "Couldn't join that walk."
        }
    }
}
