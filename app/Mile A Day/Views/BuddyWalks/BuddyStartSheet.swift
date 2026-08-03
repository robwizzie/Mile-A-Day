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
                        // Clears the sticky footer.
                        Color.clear.frame(height: 120)
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
                await buddy.loadCandidates()
            }
            .onChange(of: buddy.errorMessage) { _, newValue in
                guard let newValue else { return }
                errorText = newValue
                buddy.errorMessage = nil
            }
            .alert(
                "Couldn't start",
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
        friendSection
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
            withAnimation(MADTheme.Animation.quick) { lane = option }
            codeFocused = option == .join
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

    /// The candidate list is filtered to friends whose app build actually has
    /// Buddy Walks — so "nobody here" can mean "none of them have updated",
    /// which must not be phrased as a problem with their friend list.
    private var emptyFriendsCard: some View {
        VStack(spacing: MADTheme.Spacing.sm) {
            Image(systemName: "person.2.slash")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(MADTheme.Colors.madWhite.opacity(0.4))
            Text("No friends set up for buddy walks yet")
                .font(MADTheme.Typography.smallBold)
                .foregroundStyle(MADTheme.Colors.madWhite.opacity(0.85))
                .multilineTextAlignment(.center)
            Text("They'll appear once they update. You can still start one and share the code.")
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

            primaryButton
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

    /// Never mentions the share code. The old label — "Start with a share
    /// code" — read as an INPUT ("start by entering a code") and sat directly
    /// above the join button, which genuinely does take a code. The code is a
    /// consequence of starting, and the header sentence already says so.
    private var primaryTitle: String {
        if lane == .join { return isJoining ? "Joining…" : "Join walk" }
        if isCreating { return "Starting…" }
        let noun = isRun ? "run" : "walk"
        if selected.isEmpty { return "Start \(noun)" }
        return selected.count == 1 ? "Invite 1 & start" : "Invite \(selected.count) & start"
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

    private func create() async {
        guard !isCreating else { return }
        isCreating = true
        defer { isCreating = false }
        do {
            let state = try await buddy.createSession(
                mode: mode,
                goalValue: mode.needsGoal ? goal : nil,
                activityType: activityType,
                inviteUserIds: Array(selected)
            )
            MADHaptics.success()
            onCreated(state)
            dismiss()
        } catch {
            MADHaptics.error()
            errorText =
                (error as? LocalizedError)?.errorDescription ?? "Couldn't create the buddy walk."
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
