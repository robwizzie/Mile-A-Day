import SwiftUI

/// Change a lobby's plan before it starts, and pull more people in.
///
/// The lobby used to be read-only: the settings you picked at creation were
/// final, so "actually let's make it two miles" or "wait, Sam's coming too"
/// meant abandoning the room and building a new one — which also invalidated
/// the code you'd already sent. That's the whole reason this exists.
///
/// Deliberately NOT sharing controls with `BuddyStartSheet`. That screen is a
/// guided first-run flow with a live summary sentence and a lane picker; this is
/// a compact edit form over an object that already exists. The overlap is the
/// vocabulary (modes, goals, walk/run), not the layout, and the two have
/// genuinely different jobs — a shared component would end up with a `isEditing`
/// flag threaded through every branch. What must not drift is the RULES, and
/// those live server-side in `validateGoal`, which both paths post through.
///
/// Everything here is host-only; non-hosts never see the entry point, and the
/// server enforces it anyway (`not_host`).
struct BuddyLobbySettingsSheet: View {
    let session: BuddySessionState

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var buddy = BuddySessionService.shared

    @State private var mode: BuddyMode
    @State private var goal: Double
    @State private var isRun: Bool
    @State private var isScheduled: Bool
    @State private var scheduledDate: Date
    @State private var newInvites: Set<String> = []
    @State private var isSaving = false
    @State private var errorText: String?

    private static let controlHeight: CGFloat = 48

    init(session: BuddySessionState) {
        self.session = session
        _mode = State(initialValue: session.mode)
        // A goal-less mode still needs a sensible number parked behind it, so
        // switching TO a scored mode doesn't land on 0 and fail validation.
        _goal = State(initialValue: session.goalValue ?? (session.mode == .raceTime ? 20 : 1))
        _isRun = State(initialValue: session.isRunning)
        _isScheduled = State(initialValue: session.scheduledStartAtDate != nil)
        _scheduledDate = State(
            initialValue: session.scheduledStartAtDate ?? Date().addingTimeInterval(30 * 60))
    }

    private var accent: Color {
        isRun ? MADTheme.workoutColor("running") : MADTheme.workoutColor("walking")
    }

    /// Friends not already in the room. Someone who declined or left is
    /// excluded too — re-inviting them from here would be nagging, and the
    /// server's `ON CONFLICT DO NOTHING` would drop it anyway.
    private var invitable: [BuddyCandidate] {
        let present = Set(session.participants.map(\.userId))
        return buddy.candidates.filter { !present.contains($0.userId) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                MADTheme.Colors.appBackgroundGradient.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: MADTheme.Spacing.lg) {
                        activityToggle
                        modeSection
                        if mode.needsGoal { goalSection }
                        scheduleSection
                        if !invitable.isEmpty { inviteSection }
                        Color.clear.frame(height: 8)
                    }
                    .padding(.horizontal, MADTheme.Spacing.md)
                    .padding(.top, MADTheme.Spacing.sm)
                }
            }
            .navigationTitle("Edit lobby")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Save") { Task { await save() } }
                        .font(MADTheme.Typography.bodyBold)
                        .disabled(isSaving)
                }
            }
            .task { await buddy.loadCandidates() }
            .alert(
                "Couldn't save",
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

    // MARK: - Sections

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
                Image(systemName: icon).font(.system(size: 13, weight: .semibold))
                Text(label).font(MADTheme.Typography.bodyBold)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .background(Capsule().fill(isOn ? accent : .clear))
            .foregroundStyle(
                isOn ? MADTheme.Colors.madWhite : MADTheme.Colors.madWhite.opacity(0.6))
        }
        .buttonStyle(.plain)
    }

    private var modeSection: some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.sm) {
            sectionTitle("Mode")
            VStack(spacing: 0) {
                ForEach(Array(BuddyMode.allCases.enumerated()), id: \.element) { index, option in
                    if index > 0 {
                        Divider().background(MADTheme.Colors.madWhite.opacity(0.08))
                    }
                    modeRow(option)
                }
            }
            .background(card())
        }
    }

    private func modeRow(_ option: BuddyMode) -> some View {
        let isOn = mode == option
        return Button {
            MADHaptics.tap()
            withAnimation(MADTheme.Animation.quick) {
                mode = option
                // Coming from a mode with a different unit, the stored number
                // is meaningless — 20 miles, or a 1-minute race. Reset to the
                // unit's own sensible default rather than carrying it across.
                if option == .raceTime, goal > 180 || goal < 5 { goal = 20 }
                if option != .raceTime, goal > 50 { goal = 2 }
            }
        } label: {
            HStack(spacing: MADTheme.Spacing.md) {
                Image(systemName: option.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isOn ? accent : MADTheme.Colors.madWhite.opacity(0.5))
                    .frame(width: 26)

                VStack(alignment: .leading, spacing: 2) {
                    Text(option.title)
                        .font(MADTheme.Typography.bodyBold)
                        .foregroundStyle(MADTheme.Colors.madWhite)
                    Text(option.subtitle)
                        .font(MADTheme.Typography.caption)
                        .foregroundStyle(MADTheme.Colors.madWhite.opacity(0.55))
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: MADTheme.Spacing.sm)

                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(isOn ? accent : MADTheme.Colors.madWhite.opacity(0.25))
            }
            .padding(MADTheme.Spacing.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var goalSection: some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.sm) {
            sectionTitle(mode == .raceTime ? "How long?" : "How far?")
            HStack(spacing: MADTheme.Spacing.md) {
                stepButton(systemName: "minus", enabled: goal > goalRange.lowerBound) {
                    goal = max(goalRange.lowerBound, goal - goalStep)
                }
                Text(goalLabel)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(MADTheme.Colors.madWhite)
                    .frame(maxWidth: .infinity)
                stepButton(systemName: "plus", enabled: goal < goalRange.upperBound) {
                    goal = min(goalRange.upperBound, goal + goalStep)
                }
            }
            .padding(MADTheme.Spacing.md)
            .background(card())
        }
    }

    private func stepButton(
        systemName: String, enabled: Bool, action: @escaping () -> Void
    ) -> some View {
        Button {
            MADHaptics.tap()
            withAnimation(MADTheme.Animation.quick) { action() }
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .bold))
                .frame(width: 40, height: 40)
                .background(Circle().fill(MADTheme.Colors.madWhite.opacity(0.10)))
                .foregroundStyle(MADTheme.Colors.madWhite)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
    }

    /// Mirrors the server's ceilings in `validateGoal` (200 miles / 24 hours) at
    /// a scale a person would actually pick, so the stepper can't compose a
    /// request the API will reject.
    private var goalRange: ClosedRange<Double> {
        mode == .raceTime ? 5...180 : 0.5...26
    }

    private var goalStep: Double { mode == .raceTime ? 5 : 0.5 }

    private var goalLabel: String {
        if mode == .raceTime { return "\(Int(goal)) min" }
        return goal == goal.rounded()
            ? "\(Int(goal)) mi" : String(format: "%.1f mi", goal)
    }

    private var scheduleSection: some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.sm) {
            sectionTitle("Start time")
            VStack(spacing: MADTheme.Spacing.sm) {
                Toggle(isOn: $isScheduled.animation(MADTheme.Animation.quick)) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Book it for later")
                            .font(MADTheme.Typography.bodyBold)
                            .foregroundStyle(MADTheme.Colors.madWhite)
                        Text("We start it for everyone, even with the app closed")
                            .font(MADTheme.Typography.caption)
                            .foregroundStyle(MADTheme.Colors.madWhite.opacity(0.55))
                    }
                }
                .tint(accent)

                if isScheduled {
                    DatePicker(
                        "Starts",
                        selection: $scheduledDate,
                        in: Date().addingTimeInterval(5 * 60)...Date().addingTimeInterval(
                            60 * 60 * 24 * 13),
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .datePickerStyle(.compact)
                    .tint(accent)
                    .foregroundStyle(MADTheme.Colors.madWhite)
                }
            }
            .padding(MADTheme.Spacing.md)
            .background(card())
        }
    }

    private var inviteSection: some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.sm) {
            HStack {
                sectionTitle("Add more people")
                Spacer()
                if !newInvites.isEmpty {
                    Text("\(newInvites.count) selected")
                        .font(MADTheme.Typography.caption)
                        .foregroundStyle(accent)
                }
            }
            VStack(spacing: 0) {
                ForEach(Array(invitable.enumerated()), id: \.element.id) { index, candidate in
                    if index > 0 {
                        Divider().background(MADTheme.Colors.madWhite.opacity(0.08))
                    }
                    inviteRow(candidate)
                }
            }
            .background(card())
        }
    }

    private func inviteRow(_ candidate: BuddyCandidate) -> some View {
        let isOn = newInvites.contains(candidate.userId)
        return Button {
            MADHaptics.tap()
            withAnimation(MADTheme.Animation.quick) {
                if isOn {
                    newInvites.remove(candidate.userId)
                } else {
                    newInvites.insert(candidate.userId)
                }
            }
        } label: {
            HStack(spacing: MADTheme.Spacing.md) {
                AvatarView(
                    name: candidate.displayName,
                    imageURL: candidate.profileImageUrl,
                    size: 36
                )
                Text(candidate.displayName)
                    .font(MADTheme.Typography.body)
                    .foregroundStyle(MADTheme.Colors.madWhite)
                Spacer()
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(isOn ? accent : MADTheme.Colors.madWhite.opacity(0.25))
            }
            .padding(MADTheme.Spacing.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(MADTheme.Typography.headline)
            .foregroundStyle(MADTheme.Colors.madWhite)
    }

    private func card(_ radius: CGFloat = MADTheme.CornerRadius.large) -> some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(MADTheme.Colors.madWhite.opacity(0.06))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(MADTheme.Colors.madWhite.opacity(0.10), lineWidth: 1)
            )
    }

    // MARK: - Save

    private func save() async {
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            _ = try await buddy.updateSession(
                mode: mode,
                // Always sent for a scored mode, because the server re-validates
                // mode and goal together — a mode change with no goal is a
                // `goal_required` 400 by design.
                goalValue: mode.needsGoal ? goal : nil,
                activityType: isRun ? "running" : "walking",
                // Double optional: `.some(date)` books it, `.some(nil)` cancels
                // an existing booking. Never `nil` here — this screen always has
                // an opinion about the schedule.
                scheduledStartAt: .some(isScheduled ? scheduledDate : nil),
                inviteUserIds: newInvites.isEmpty ? nil : Array(newInvites)
            )
            MADHaptics.success()
            dismiss()
        } catch {
            MADHaptics.error()
            errorText =
                (error as? LocalizedError)?.errorDescription ?? "Couldn't save those changes."
        }
    }
}
