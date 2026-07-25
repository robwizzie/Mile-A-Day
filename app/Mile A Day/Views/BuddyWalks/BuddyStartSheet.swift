import SwiftUI

/// Create a buddy walk: pick a mode, a goal, and who's coming.
///
/// Deliberately opens on "Just Together" with no goal to set, so the common
/// case — two friends about to walk — is pick-a-friend-and-go. The competitive
/// modes are one tap away rather than in the way.
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

    private var activityType: String { isRun ? "running" : "walking" }
    private var accent: Color { MADTheme.workoutColor(activityType) }

    var body: some View {
        NavigationStack {
            ZStack {
                MADTheme.Colors.appBackgroundGradient.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: MADTheme.Spacing.lg) {
                        activityToggle
                        modePicker
                        if mode.needsGoal { goalPicker }
                        friendPicker
                        Color.clear.frame(height: 80)
                    }
                    .padding(MADTheme.Spacing.md)
                }

                VStack {
                    Spacer()
                    startButton
                        .padding(MADTheme.Spacing.md)
                }
            }
            .navigationTitle("Buddy Walk")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Join code") { showJoinByCode = true }
                }
            }
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
            .alert(
                "Couldn't start",
                isPresented: Binding(
                    get: { buddy.errorMessage != nil },
                    set: { if !$0 { buddy.errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) { buddy.errorMessage = nil }
            } message: {
                Text(buddy.errorMessage ?? "")
            }
        }
    }

    // MARK: - Sections

    private var activityToggle: some View {
        HStack(spacing: 0) {
            ForEach([false, true], id: \.self) { run in
                Button {
                    MADHaptics.tap()
                    withAnimation(MADTheme.Animation.quick) { isRun = run }
                } label: {
                    Text(run ? "Run" : "Walk")
                        .font(MADTheme.Typography.bodyBold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, MADTheme.Spacing.sm)
                        .background(
                            Capsule().fill(
                                isRun == run
                                    ? MADTheme.workoutColor(run ? "running" : "walking")
                                    : Color.clear)
                        )
                        .foregroundStyle(
                            isRun == run
                                ? MADTheme.Colors.madWhite
                                : MADTheme.Colors.madWhite.opacity(0.6))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Capsule().fill(MADTheme.Colors.madWhite.opacity(0.1)))
    }

    private var modePicker: some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.sm) {
            sectionTitle("How are we doing this?")

            ForEach(BuddyMode.allCases) { option in
                Button {
                    MADHaptics.tap()
                    withAnimation(MADTheme.Animation.quick) {
                        mode = option
                        goal = option.defaultGoal
                    }
                } label: {
                    HStack(spacing: MADTheme.Spacing.md) {
                        Image(systemName: option.icon)
                            .font(.system(size: 18, weight: .semibold))
                            .frame(width: 28)
                            .foregroundStyle(mode == option ? accent : .secondary)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(option.title)
                                .font(MADTheme.Typography.bodyBold)
                                .foregroundStyle(MADTheme.Colors.madWhite)
                            Text(option.subtitle)
                                .font(MADTheme.Typography.caption)
                                .foregroundStyle(MADTheme.Colors.madWhite.opacity(0.6))
                                .multilineTextAlignment(.leading)
                        }

                        Spacer()

                        if mode == option {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(accent)
                        }
                    }
                    .padding(MADTheme.Spacing.md)
                    .madLiquidGlass(cornerRadius: MADTheme.CornerRadius.large)
                    .overlay(
                        RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                            .stroke(mode == option ? accent : Color.clear, lineWidth: 2)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var goalPicker: some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.sm) {
            sectionTitle(mode == .raceTime ? "For how long?" : "How far?")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: MADTheme.Spacing.sm) {
                    ForEach(mode.goalOptions, id: \.self) { value in
                        Button {
                            MADHaptics.tap()
                            goal = value
                        } label: {
                            Text(goalLabel(value))
                                .font(MADTheme.Typography.smallBold)
                                .padding(.horizontal, MADTheme.Spacing.md)
                                .padding(.vertical, MADTheme.Spacing.sm)
                                .background(
                                    Capsule().fill(
                                        goal == value ? accent : MADTheme.Colors.madWhite.opacity(0.1))
                                )
                                .foregroundStyle(MADTheme.Colors.madWhite)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 2)
            }
        }
    }

    private var friendPicker: some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.sm) {
            sectionTitle("Who's coming?")

            if buddy.candidates.isEmpty {
                // The candidate list is filtered to friends whose app build
                // actually has Buddy Walks — so "no friends yet" here can mean
                // "none of them have updated", which we must not phrase as a
                // problem with their friend list.
                Text("No friends are set up for buddy walks yet. They'll show up here once they update.")
                    .font(MADTheme.Typography.footnote)
                    .foregroundStyle(MADTheme.Colors.madWhite.opacity(0.6))
                    .padding(MADTheme.Spacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .madLiquidGlass(cornerRadius: MADTheme.CornerRadius.large)
            } else {
                ForEach(buddy.candidates) { candidate in
                    Button {
                        MADHaptics.tap()
                        if selected.contains(candidate.userId) {
                            selected.remove(candidate.userId)
                        } else {
                            selected.insert(candidate.userId)
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
                            Image(
                                systemName: selected.contains(candidate.userId)
                                    ? "checkmark.circle.fill" : "circle"
                            )
                            .foregroundStyle(
                                selected.contains(candidate.userId)
                                    ? accent : MADTheme.Colors.madWhite.opacity(0.3))
                        }
                        .padding(MADTheme.Spacing.sm)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var startButton: some View {
        Button {
            Task { await create() }
        } label: {
            HStack {
                if isCreating {
                    ProgressView().tint(MADTheme.Colors.madWhite)
                } else {
                    Image(systemName: "figure.2")
                    Text(selected.isEmpty ? "Create with a code" : "Invite \(selected.count)")
                }
            }
            .font(MADTheme.Typography.bodyBold)
            .frame(maxWidth: .infinity)
            .padding(.vertical, MADTheme.Spacing.md)
            .background(Capsule().fill(accent))
            .foregroundStyle(MADTheme.Colors.madWhite)
        }
        .buttonStyle(.plain)
        .disabled(isCreating)
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(MADTheme.Typography.headline)
            .foregroundStyle(MADTheme.Colors.madWhite)
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
            buddy.errorMessage =
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

    var body: some View {
        NavigationStack {
            ZStack {
                MADTheme.Colors.appBackgroundGradient.ignoresSafeArea()

                VStack(spacing: MADTheme.Spacing.lg) {
                    Text("Enter the host's code")
                        .font(MADTheme.Typography.headline)
                        .foregroundStyle(MADTheme.Colors.madWhite)

                    TextField("ABC123", text: $code)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .multilineTextAlignment(.center)
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(MADTheme.Colors.madWhite)
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
