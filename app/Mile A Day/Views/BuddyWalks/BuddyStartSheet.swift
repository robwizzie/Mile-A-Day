import SwiftUI

/// Create a buddy walk: pick a mode, a goal, and who's coming.
///
/// Deliberately opens on "Just Together" with no goal to set, so the common
/// case — two friends about to walk — is pick-a-friend-and-go. The competitive
/// modes are one tap away rather than in the way.
///
/// The layout answers "what am I about to start?" before it asks anything: the
/// header restates the current choices as a sentence that updates live, so the
/// mode tiles and goal chips below read as adjustments to a real thing rather
/// than as a form to fill in.
struct BuddyStartSheet: View {
    /// Handed back so the caller can push straight into the lobby.
    let onCreated: (BuddySessionState) -> Void

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var buddy = BuddySessionService.shared

    @State private var mode: BuddyMode = .together
    @State private var goal: Double = BuddyMode.together.defaultGoal
    @State private var isRun = false
    @State private var selected: Set<String> = []
    @State private var isCreating = false
    @State private var showJoinByCode = false
    /// Errors are mirrored into LOCAL state. Driving `.alert(isPresented:)`
    /// straight off `buddy.errorMessage` meant the binding's setter wrote to an
    /// @Published from inside a view update — "Publishing changes from within
    /// view updates is not allowed". Local state has no such problem, and the
    /// mirror below runs after the update, not during it.
    @State private var errorText: String?

    private var activityType: String { isRun ? "running" : "walking" }
    private var accent: Color { MADTheme.workoutColor(activityType) }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                MADTheme.Colors.appBackgroundGradient.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: MADTheme.Spacing.lg) {
                        summaryHeader
                        activityToggle
                        modeSection
                        if mode.needsGoal { goalSection }
                        friendSection
                        // Clears the sticky footer.
                        Color.clear.frame(height: 96)
                    }
                    .padding(.horizontal, MADTheme.Spacing.md)
                    .padding(.top, MADTheme.Spacing.sm)
                }

                footer
            }
            .navigationTitle("Buddy Walk")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .sheet(isPresented: $showJoinByCode) {
                BuddyJoinSheet { state in
                    showJoinByCode = false
                    onCreated(state)
                    // Joining by code replaces creating one — close this sheet
                    // too so the user lands straight in the lobby.
                    dismiss()
                }
            }
            .task { await buddy.loadCandidates() }
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

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .primaryAction) {
            Button {
                MADHaptics.tap()
                showJoinByCode = true
            } label: {
                Label("Join code", systemImage: "number")
                    .font(MADTheme.Typography.smallBold)
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
                    .frame(width: 76, height: 76)
                Circle()
                    .strokeBorder(accent.opacity(0.5), lineWidth: 1.5)
                    .frame(width: 76, height: 76)
                Image(systemName: mode.icon)
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(accent)
            }
            .animation(MADTheme.Animation.quick, value: mode)
            .animation(MADTheme.Animation.quick, value: isRun)

            Text(summaryTitle)
                .font(MADTheme.Typography.title2)
                .foregroundStyle(MADTheme.Colors.madWhite)
                .multilineTextAlignment(.center)

            Text(summarySubtitle)
                .font(MADTheme.Typography.subheadline)
                .foregroundStyle(MADTheme.Colors.madWhite.opacity(0.65))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, MADTheme.Spacing.lg)
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

    private var summarySubtitle: String {
        guard !selected.isEmpty else {
            return "Nobody invited yet — you'll get a code to share"
        }
        let names = buddy.candidates
            .filter { selected.contains($0.userId) }
            .map(\.displayName)
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
            .padding(.vertical, 10)
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
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: option.icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(isOn ? accent : MADTheme.Colors.madWhite.opacity(0.55))
                    Spacer()
                    if isOn {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(accent)
                    }
                }
                Text(option.title)
                    .font(MADTheme.Typography.smallBold)
                    .foregroundStyle(MADTheme.Colors.madWhite)
                Text(option.subtitle)
                    .font(MADTheme.Typography.caption)
                    .foregroundStyle(MADTheme.Colors.madWhite.opacity(0.6))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 108, alignment: .topLeading)
            .padding(MADTheme.Spacing.md)
            .madLiquidGlass(cornerRadius: MADTheme.CornerRadius.large)
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
            .padding(.vertical, 10)
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
                .madLiquidGlass(cornerRadius: MADTheme.CornerRadius.large)
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
            Text("They'll appear here once they update. You can still start one and share the code.")
                .font(MADTheme.Typography.caption)
                .foregroundStyle(MADTheme.Colors.madWhite.opacity(0.6))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(MADTheme.Spacing.lg)
        .madLiquidGlass(cornerRadius: MADTheme.CornerRadius.large)
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

    private var footer: some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [.clear, MADTheme.Colors.madBlack.opacity(0.85)],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: 24)
            .allowsHitTesting(false)

            startButton
                .padding(.horizontal, MADTheme.Spacing.md)
                .padding(.bottom, MADTheme.Spacing.sm)
                .background(MADTheme.Colors.madBlack.opacity(0.85))
        }
    }

    private var startButton: some View {
        Button {
            MADHaptics.action()
            Task { await create() }
        } label: {
            HStack(spacing: 8) {
                if isCreating {
                    ProgressView().tint(MADTheme.Colors.madWhite)
                } else {
                    Image(systemName: selected.isEmpty ? "number" : "figure.2")
                        .font(.system(size: 16, weight: .semibold))
                }
                Text(startButtonTitle)
            }
            .font(MADTheme.Typography.bodyBold)
            .frame(maxWidth: .infinity)
            .padding(.vertical, MADTheme.Spacing.md)
            .background(Capsule().fill(accent))
            .foregroundStyle(MADTheme.Colors.madWhite)
        }
        .buttonStyle(.plain)
        .disabled(isCreating)
        .opacity(isCreating ? 0.7 : 1)
    }

    private var startButtonTitle: String {
        if isCreating { return "Starting…" }
        if selected.isEmpty { return "Start with a share code" }
        return selected.count == 1 ? "Invite 1 friend" : "Invite \(selected.count) friends"
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
}

/// Join an existing walk with the 6-character code the host is reading aloud.
struct BuddyJoinSheet: View {
    let onJoined: (BuddySessionState) -> Void

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var buddy = BuddySessionService.shared
    @State private var code = ""
    @State private var isJoining = false
    @State private var error: String?
    @FocusState private var codeFocused: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                MADTheme.Colors.appBackgroundGradient.ignoresSafeArea()

                VStack(spacing: MADTheme.Spacing.lg) {
                    VStack(spacing: MADTheme.Spacing.xs) {
                        Image(systemName: "number.circle.fill")
                            .font(.system(size: 40, weight: .semibold))
                            .foregroundStyle(MADTheme.Colors.madRed)
                        Text("Enter the host's code")
                            .font(MADTheme.Typography.title3)
                            .foregroundStyle(MADTheme.Colors.madWhite)
                        Text("Six characters, shown on their screen")
                            .font(MADTheme.Typography.footnote)
                            .foregroundStyle(MADTheme.Colors.madWhite.opacity(0.6))
                    }
                    .padding(.top, MADTheme.Spacing.lg)

                    TextField("ABC123", text: $code)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .multilineTextAlignment(.center)
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .tracking(6)
                        .foregroundStyle(MADTheme.Colors.madWhite)
                        .focused($codeFocused)
                        .padding(MADTheme.Spacing.md)
                        .madLiquidGlass(cornerRadius: MADTheme.CornerRadius.large)
                        .onChange(of: code) { _, newValue in
                            code = String(newValue.uppercased().prefix(6))
                        }

                    if let error {
                        Text(error)
                            .font(MADTheme.Typography.footnote)
                            .foregroundStyle(MADTheme.Colors.error)
                            .multilineTextAlignment(.center)
                    }

                    Button {
                        Task { await join() }
                    } label: {
                        HStack {
                            if isJoining { ProgressView().tint(MADTheme.Colors.madWhite) }
                            Text("Join")
                        }
                        .font(MADTheme.Typography.bodyBold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, MADTheme.Spacing.md)
                        .background(Capsule().fill(MADTheme.Colors.madRed))
                        .foregroundStyle(MADTheme.Colors.madWhite)
                    }
                    .buttonStyle(.plain)
                    .disabled(code.count < 6 || isJoining)
                    .opacity(code.count < 6 ? 0.5 : 1)

                    Spacer()
                }
                .padding(MADTheme.Spacing.md)
            }
            .navigationTitle("Join a walk")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear { codeFocused = true }
        }
    }

    private func join() async {
        guard !isJoining else { return }
        isJoining = true
        defer { isJoining = false }
        error = nil
        do {
            try await buddy.join(code: code)
            if let session = buddy.session {
                MADHaptics.success()
                onJoined(session)
                dismiss()
            }
        } catch {
            MADHaptics.error()
            self.error =
                (error as? LocalizedError)?.errorDescription ?? "Couldn't join that walk."
        }
    }
}
