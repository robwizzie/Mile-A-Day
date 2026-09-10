import SwiftUI

/// Change a lobby's plan before it starts.
///
/// The lobby used to be read-only: the settings you picked at creation were
/// final, so "actually let's make it two miles" meant abandoning the room and
/// building a new one. That's the whole reason this exists.
///
/// A STEP of `BuddyWalkFlowView`, not a sheet. It was a `NavigationStack` in a
/// `.sheet` over a `.fullScreenCover` — a third visual language, with a
/// navigation bar and Cancel/Save toolbar buttons, two modal layers deep,
/// reached from a wizard that has neither. Now it is the plan question again,
/// arrived at from the far end: same gradient, same top bar, and Back is the
/// same chevron every other step wears.
///
/// Deliberately NOT sharing controls with `BuddySetupStepsView`. That is a
/// guided first-run flow of one-tap questions; this is a compact edit form
/// over an object that already exists, where nothing may commit until Save.
/// The overlap is the vocabulary (modes, goals, walk/run), not the layout, and
/// a shared component would end up with an `isEditing` flag threaded through
/// every branch of the path people actually use. What must not drift is the
/// RULES, and those live server-side in `validateGoal`, which both post
/// through.
///
/// "Add more people" is gone from here: the lobby's own tap-to-invite faces
/// cover exactly the same candidates, in the place you are already looking at
/// the roster.
///
/// Everything here is host-only; non-hosts never see the entry point, and the
/// server enforces it anyway (`not_host`).
struct BuddyPlanEditorView: View {
    let session: BuddySessionState
    /// Saved — back to the lobby.
    let onSaved: () -> Void

    @ObservedObject private var buddy = BuddySessionService.shared

    @State private var mode: BuddyMode
    @State private var goal: Double
    @State private var isRun: Bool
    @State private var isScheduled: Bool
    @State private var scheduledDate: Date
    @State private var isSaving = false

    init(session: BuddySessionState, onSaved: @escaping () -> Void) {
        self.session = session
        self.onSaved = onSaved
        _mode = State(initialValue: session.mode)
        // A goal-less mode still needs a sensible number parked behind it, so
        // switching TO a scored mode doesn't land on 0 and fail validation.
        _goal = State(initialValue: session.goalValue ?? (session.mode == .raceTime ? 20 : 1))
        _isRun = State(initialValue: session.isRunning)
        _isScheduled = State(initialValue: session.scheduledStartAtDate != nil)
        _scheduledDate = State(
            initialValue: session.scheduledStartAtDate ?? Date().addingTimeInterval(30 * 60))
    }

    /// White on the red gradient, like every other pre-start step.
    private var accent: Color { WizardPalette.accent }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(spacing: 24) {
                    WizardHeader(
                        glyph: .symbol(mode.icon),
                        title: "Change the Plan",
                        subtitle: "Nobody's been told yet — this updates the lobby for everyone."
                    )

                    VStack(spacing: MADTheme.Spacing.lg) {
                        activityToggle
                        modeSection
                        if mode.needsGoal { goalSection }
                        scheduleSection
                    }
                    .padding(.horizontal, MADTheme.Spacing.md)

                    Color.clear.frame(height: WizardMetrics.footerClearance)
                }
                .padding(.top, MADTheme.Spacing.md)
            }

            WizardFooter {
                WizardPrimaryButton(
                    title: isSaving ? "Saving…" : "Save changes",
                    icon: "checkmark",
                    isBusy: isSaving
                ) {
                    MADHaptics.action()
                    Task { await save() }
                }
                Text("Everyone in the lobby sees the new plan.")
                    .font(MADTheme.Typography.caption)
                    .foregroundStyle(Color.white.opacity(0.6))
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
        .background(Capsule().fill(Color.white.opacity(0.12)))
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
            .frame(height: 44)
            .background(Capsule().fill(isOn ? accent : .clear))
            .foregroundStyle(isOn ? WizardPalette.onAccent : Color.white.opacity(0.7))
        }
        .buttonStyle(.plain)
    }

    private var modeSection: some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.sm) {
            sectionTitle("Mode")
            WizardPanel(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(BuddyMode.allCases.enumerated()), id: \.element) { index, option in
                        if index > 0 {
                            Divider().background(Color.white.opacity(0.2))
                        }
                        modeRow(option)
                    }
                }
            }
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
                    .foregroundStyle(Color.white.opacity(isOn ? 1 : 0.55))
                    .frame(width: 26)

                VStack(alignment: .leading, spacing: 2) {
                    Text(option.title)
                        .font(MADTheme.Typography.bodyBold)
                        .foregroundStyle(Color.white)
                    Text(option.subtitle)
                        .font(MADTheme.Typography.caption)
                        .foregroundStyle(Color.white.opacity(0.6))
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: MADTheme.Spacing.sm)

                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(isOn ? accent : Color.white.opacity(0.3))
            }
            .padding(MADTheme.Spacing.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var goalSection: some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.sm) {
            sectionTitle(mode == .raceTime ? "How long?" : "How far?")
            WizardPanel {
                HStack(spacing: MADTheme.Spacing.md) {
                    stepButton(systemName: "minus", enabled: goal > goalRange.lowerBound) {
                        goal = max(goalRange.lowerBound, goal - goalStep)
                    }
                    Text(goalLabel)
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity)
                    stepButton(systemName: "plus", enabled: goal < goalRange.upperBound) {
                        goal = min(goalRange.upperBound, goal + goalStep)
                    }
                }
            }
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
                .background(Circle().fill(Color.white.opacity(0.15)))
                .foregroundStyle(Color.white)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
        .accessibilityLabel(systemName == "minus" ? "Decrease" : "Increase")
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
            WizardPanel {
                VStack(spacing: MADTheme.Spacing.sm) {
                    Toggle(isOn: $isScheduled.animation(MADTheme.Animation.quick)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Book it for later")
                                .font(MADTheme.Typography.bodyBold)
                                .foregroundStyle(Color.white)
                            Text("We start it for everyone, even with the app closed")
                                .font(MADTheme.Typography.caption)
                                .foregroundStyle(Color.white.opacity(0.6))
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
                        .foregroundStyle(Color.white)
                    }
                }
            }
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(MADTheme.Typography.headline)
            .foregroundStyle(Color.white)
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
                inviteUserIds: nil
            )
            MADHaptics.success()
            onSaved()
        } catch {
            MADHaptics.error()
            // Reported through the service so the ONE alert the flow owns is
            // the only place an error can appear — this step has no
            // presentation context of its own any more.
            buddy.errorMessage =
                (error as? LocalizedError)?.errorDescription ?? "Couldn't save those changes."
        }
    }
}
