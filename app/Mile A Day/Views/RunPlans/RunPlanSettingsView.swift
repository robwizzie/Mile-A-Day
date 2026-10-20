import SwiftUI

/// Plan settings (sheet from the plan's gear): effort, hard days, the daily
/// mile, goals, Connect Claude, end plan. Changes go out together on
/// "Save changes" so dragging the slider doesn't re-plan the week each step.
struct RunPlanSettingsView: View {
    @ObservedObject private var store = RunPlanStore.shared
    @Environment(\.dismiss) private var dismiss

    @State private var effort = 3
    @State private var hardDaysOverride: Int?
    @State private var runDailyMile = true
    @State private var seeded = false
    @State private var saving = false
    @State private var ending = false
    @State private var confirmEnd = false
    @State private var errorText: String?

    private var plan: RunPlan? { store.plan }

    private var dirty: Bool {
        guard let plan else { return false }
        return effort != plan.effort || hardDaysOverride != plan.hard_days || runDailyMile != (plan.run_daily_mile ?? true)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let plan {
                        effortCard
                        RunPlanDailyMileRows(runDailyMile: $runDailyMile)
                        RunPlanHardDaysPicker(effort: effort, hardDaysOverride: $hardDaysOverride)
                        if dirty {
                            RunPlanPrimaryButton(title: "Save changes", busy: saving, action: save)
                        }
                        linkRows(plan)
                        endButton
                    } else {
                        Text("No active plan.")
                            .madFont(size: 15, weight: .semibold, design: .rounded)
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
                .padding(16)
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("Plan settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(RunPlanColors.orange)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear(perform: seed)
        .confirmationDialog("End this plan?", isPresented: $confirmEnd, titleVisibility: .visible) {
            Button("End plan", role: .destructive, action: endPlan)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your runs and streak stay. You can build a new plan anytime.")
        }
        .alert("Something went wrong", isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorText ?? "")
        }
    }

    private var effortCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("EFFORT")
                .madFont(size: 11, weight: .black, design: .rounded, maxScale: 1.3)
                .tracking(1)
                .foregroundColor(.white.opacity(0.45))
            RunPlanEffortSlider(effort: $effort)
            RunPlanEffortDetails(effort: effort, hardDays: hardDaysOverride, weeklyMiles: store.fitness?.weekly_miles)
                .padding(.top, 4)
        }
        .runPlanCard(radius: 20)
    }

    private func linkRows(_ plan: RunPlan) -> some View {
        VStack(spacing: 0) {
            NavigationLink {
                RunPlanGoalsEditor()
            } label: {
                row(icon: "flag.fill", tint: RunPlanColors.orange, title: "Goals",
                    detail: RunPlanFormat.goalsLine(plan.goals) + (plan.finish_by.map { " · by \(RunPlanFormat.dayHeader($0))" } ?? ""))
            }
            .buttonStyle(.plain)
            Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1).padding(.leading, 44)
            NavigationLink {
                RunPlanClaudeView()
            } label: {
                row(icon: "sparkles", tint: RunPlanClaudeView.claudeColor, title: "Connect Claude",
                    detail: store.current?.claude?.connected == true ? "Connected" : "Optional deep review of your training")
            }
            .buttonStyle(.plain)
        }
        .runPlanCard(radius: 18, padding: 4)
    }

    private func row(icon: String, tint: Color, title: String, detail: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .madFont(size: 15, weight: .bold, maxScale: 1.3)
                .foregroundColor(tint)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .madFont(size: 15, weight: .bold, design: .rounded)
                    .foregroundColor(.white)
                Text(detail)
                    .madFont(size: 12, weight: .medium, design: .rounded)
                    .foregroundColor(.white.opacity(0.5))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .madFont(size: 12, weight: .bold, maxScale: 1.3)
                .foregroundColor(.white.opacity(0.3))
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    private var endButton: some View {
        Button {
            confirmEnd = true
        } label: {
            HStack {
                if ending { ProgressView().tint(RunPlanColors.red) }
                Text("End plan")
                    .madFont(size: 15, weight: .heavy, design: .rounded)
            }
            .foregroundColor(RunPlanColors.red)
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.plain)
        .disabled(ending)
        .padding(.top, 8)
    }

    private func seed() {
        guard !seeded, let plan else { return }
        seeded = true
        effort = min(4, max(1, plan.effort))
        hardDaysOverride = plan.hard_days
        runDailyMile = plan.run_daily_mile ?? true
        if !store.fitnessLoaded { Task { await store.loadFitness() } }
    }

    private func save() {
        guard let plan, !saving else { return }
        var update = RunPlanUpdate()
        if effort != plan.effort { update.effort = effort }
        if hardDaysOverride != plan.hard_days {
            if let hardDaysOverride { update.hard_days = hardDaysOverride } else { update.clearHardDays = true }
        }
        if runDailyMile != (plan.run_daily_mile ?? true) { update.run_daily_mile = runDailyMile }
        saving = true
        Task {
            defer { saving = false }
            do {
                try await store.update(update)
                MADHaptics.success()
            } catch {
                errorText = RunPlanError.from(error).message
            }
        }
    }

    private func endPlan() {
        ending = true
        Task {
            defer { ending = false }
            do {
                try await store.endPlan()
                dismiss()
            } catch {
                errorText = RunPlanError.from(error).message
            }
        }
    }
}

/// Settings › Goals: the Goals step, saving with PATCH.
struct RunPlanGoalsEditor: View {
    @ObservedObject private var store = RunPlanStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var draft = RunPlanGoalDraft()
    @State private var seeded = false
    @State private var saving = false
    @State private var errorText: String?

    var body: some View {
        ScrollView {
            RunPlanGoalsStep(draft: $draft, fitness: store.fitness, buttonTitle: "Save goals", busy: saving, onNext: save)
                .padding(16)
        }
        .background(Color.black.ignoresSafeArea())
        .navigationTitle("Goals")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard !seeded, let plan = store.plan else { return }
            seeded = true
            draft = RunPlanGoalDraft(plan: plan)
        }
        .alert("Couldn't save", isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorText ?? "")
        }
    }

    private func save() {
        guard !saving, !draft.selected.isEmpty else { return }
        var update = RunPlanUpdate()
        update.goals = draft.goals
        if let key = draft.finishByKey { update.finish_by = key } else { update.clearFinishBy = true }
        saving = true
        Task {
            defer { saving = false }
            do {
                try await store.update(update)
                MADHaptics.success()
                dismiss()
            } catch {
                errorText = RunPlanError.from(error).message
            }
        }
    }
}
