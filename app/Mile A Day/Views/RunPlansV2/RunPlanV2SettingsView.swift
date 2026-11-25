import SwiftUI

/// Plan settings: goals, effort + walk days, shoes, notes for the coach
/// (AI tiers), the AI Coach switch, end plan. The user's own edits apply
/// directly (`PATCH /run-plans/current`, recorded as source `user`).
/// Reached from plan home's toolbar and Settings › Workouts › Run plan.
struct RunPlanV2SettingsView: View {
    @ObservedObject private var store = RunPlanV2Store.shared
    @Environment(\.dismiss) private var dismiss
    @State private var confirmEnd = false
    @State private var busy = false
    @State private var error: String?
    @State private var coachOn = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let plan = store.plan {
                    planSection(plan)
                    if store.ai.mode != .off, store.ai.global_enabled != false { coachSection }
                    endSection
                } else {
                    Text(String(localized: "You don't have a run plan yet."))
                        .madFont(size: 15, design: .rounded)
                        .foregroundStyle(.secondary)
                }
                if let error {
                    RPV2Notice(icon: "exclamationmark.triangle.fill", text: error, tint: RPV2Colors.orange)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color.black.ignoresSafeArea())
        .navigationTitle(String(localized: "Plan settings"))
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        .onAppear { coachOn = !store.ai.optedOut }
        .confirmationDialog(String(localized: "End this plan?"), isPresented: $confirmEnd, titleVisibility: .visible) {
            Button(String(localized: "End plan"), role: .destructive) { Task { await endPlan() } }
        } message: {
            Text(String(localized: "Your streak and runs stay. The plan and its history are kept, and you can start a new one any time."))
        }
    }

    private func planSection(_ plan: RunPlanV2Plan) -> some View {
        SettingsSection("Your plan") {
            NavigationLink { RunPlanEditView(part: .goals) } label: {
                SettingsRow(icon: "target", title: String(localized: "Goals"),
                            subtitle: RPV2Format.goalsLine(plan.goals), tint: RPV2Colors.orange)
            }
            .buttonStyle(.plain)
            SettingsDivider()
            NavigationLink { RunPlanEditView(part: .effort) } label: {
                SettingsRow(icon: "figure.run", title: String(localized: "Effort and walk days"),
                            subtitle: effortSummary(plan), tint: RPV2Colors.red)
            }
            .buttonStyle(.plain)
            if !ShoeStore.shared.active.isEmpty || plan.shoe_assignments?.values.contains(where: { $0 != nil }) == true {
                SettingsDivider()
                NavigationLink { RunPlanEditView(part: .shoes) } label: {
                    SettingsRow(icon: ShoeSymbol.filled, title: String(localized: "Shoes for each run"),
                                subtitle: String(localized: "Loaded on each run for you"), tint: .orange)
                }
                .buttonStyle(.plain)
            }
            if store.coachTier.isAI {
                SettingsDivider()
                NavigationLink { RunPlanEditView(part: .notes) } label: {
                    SettingsRow(icon: "lock.fill", title: String(localized: "Notes for the coach"),
                                subtitle: (plan.coach_notes ?? "").isEmpty ? String(localized: "Only the coach reads them")
                                                                           : String((plan.coach_notes ?? "").prefix(60)),
                                tint: RPV2Colors.gold)
                }
                .buttonStyle(.plain)
            }
            SettingsDivider()
            NavigationLink { RunPlanHistoryView() } label: {
                SettingsRow(icon: "clock.arrow.circlepath", title: String(localized: "Plan history"),
                            subtitle: String(localized: "Every suggestion and what you decided"), tint: .secondary)
            }
            .buttonStyle(.plain)
        }
    }

    private func effortSummary(_ plan: RunPlanV2Plan) -> String {
        let runs = plan.runs_per_week ?? 0
        let mode: String
        switch plan.walkMode {
        case .builtIn: mode = String(localized: "walk days built in")
        case .fixed: mode = String(localized: "fixed walk days")
        case .flexible: mode = String(localized: "flexible walk days")
        }
        return String(localized: "\(runs) runs a week · \(RPV2Format.difficultyLabel(plan.difficultyLevel)) · \(mode)")
    }

    private var coachSection: some View {
        SettingsSection("AI Coach", footer: coachFooter) {
            SettingsToggleRow(icon: "sparkles", title: String(localized: "AI Coach"),
                              subtitle: coachOn ? String(localized: "Flamey designs and adjusts your plan")
                                                : String(localized: "Off. Your plan follows set rules"),
                              tint: RPV2Colors.orange, isOn: $coachOn)
                .disabled(busy)
                .onChange(of: coachOn) { _, on in
                    guard on == store.ai.optedOut else { return }
                    Task { await setCoach(on) }
                }
        }
    }

    private var coachFooter: String? {
        switch store.ai.mode {
        case .anthropic:
            return String(localized: "Your coach runs on Claude by Anthropic, who receive your plan, check-ins and a fitness summary.")
        case .apple:
            return AppleCoach.isAvailable ? String(localized: "Runs on Apple Intelligence. Nothing is stored by Apple.")
                                          : AppleCoach.unavailableReason
        case .off:
            return nil
        }
    }

    private var endSection: some View {
        SettingsSection {
            Button { confirmEnd = true } label: {
                SettingsRow(icon: "xmark.circle", title: String(localized: "End plan"), tint: .red,
                            titleColor: .red, accessory: .none)
            }
            .buttonStyle(.plain)
            .disabled(busy)
        }
    }

    private func setCoach(_ on: Bool) async {
        busy = true
        defer { busy = false }
        do {
            try await store.setCoachOptOut(!on)
        } catch let e as RunPlanV2Error {
            error = e.message
            coachOn = !store.ai.optedOut
        } catch {
            coachOn = !store.ai.optedOut
        }
    }

    private func endPlan() async {
        busy = true
        defer { busy = false }
        do {
            try await store.endPlan()
            dismiss()
        } catch let e as RunPlanV2Error {
            error = e.message
        } catch {
            self.error = RunPlanV2Error.offline.message
        }
    }
}

/// Edits one part of the live plan with the setup step views.
struct RunPlanEditView: View {
    enum Part { case goals, effort, shoes, notes }
    let part: Part

    @ObservedObject private var store = RunPlanV2Store.shared
    @ObservedObject private var analyzer = RunFitnessAnalyzer.shared
    @Environment(\.dismiss) private var dismiss
    @State private var model: RunPlanSetupModel?
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let model {
                    editor(model)
                    if part == .goals || part == .effort {
                        Text(String(localized: "Saving rebuilds your plan from tomorrow. Today stays as it is."))
                            .madFont(size: 12, design: .rounded)
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    if let error { RPV2Notice(icon: "exclamationmark.triangle.fill", text: error, tint: RPV2Colors.orange) }
                    RPV2Button(title: String(localized: "Save"), isBusy: saving) { Task { await save(model) } }
                        .disabled(!valid(model))
                        .opacity(valid(model) ? 1 : 0.45)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color.black.ignoresSafeArea())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        .onAppear {
            if model == nil, let plan = store.plan { model = RunPlanSetupModel(plan: plan) }
        }
    }

    private var title: String {
        switch part {
        case .goals: return String(localized: "Goals")
        case .effort: return String(localized: "Effort and walk days")
        case .shoes: return String(localized: "Shoes for each run")
        case .notes: return String(localized: "Notes for the coach")
        }
    }

    @ViewBuilder
    private func editor(_ model: RunPlanSetupModel) -> some View {
        switch part {
        case .goals: RunPlanGoalsStep(model: model, profile: analyzer.profile, showsHeader: false)
        case .effort: RunPlanEffortStep(model: model, profile: analyzer.profile, showsHeader: false)
        case .shoes: RunPlanShoesEditor(model: model)
        case .notes: RunPlanCoachNotesEditor(text: Binding(get: { model.coachNotes }, set: { model.coachNotes = $0 }))
        }
    }

    private func valid(_ m: RunPlanSetupModel) -> Bool {
        switch part {
        case .goals: return m.goalsValid
        case .effort: return m.effortValid
        default: return true
        }
    }

    private func save(_ m: RunPlanSetupModel) async {
        saving = true
        error = nil
        defer { saving = false }
        let full = m.patch()
        var p = RunPlanV2PlanPatch()
        switch part {
        case .goals:
            p.goals = full.goals
            p.target_date = full.target_date
        case .effort:
            p.runs_per_week = full.runs_per_week
            p.difficulty = full.difficulty
            p.walk_mode = full.walk_mode
            p.fixed_walk_days = full.fixed_walk_days
        case .shoes:
            var all: RunPlanV2ShoeAssignments = [:]
            for t in RunPlanV2ShoeRunType.allCases { all[t.rawValue] = m.shoes[t] }
            p.shoe_assignments = all
        case .notes:
            p.coach_notes = full.coach_notes ?? ""
        }
        do {
            try await store.update(p)
            MADHaptics.success()
            dismiss()
        } catch let e as RunPlanV2Error {
            error = e.message
        } catch {
            self.error = RunPlanV2Error.offline.message
        }
    }
}

/// Shoe per run type, for the settings editor.
struct RunPlanShoesEditor: View {
    @Bindable var model: RunPlanSetupModel
    private var shoeStore: ShoeStore { ShoeStore.shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(RunPlanV2ShoeRunType.allCases, id: \.rawValue) { t in
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 1) {
                        RPV2Eyebrow(text: label(t), color: .white.opacity(0.45))
                        Text(shoeStore.shoe(id: model.shoes[t]).map(name) ?? String(localized: "None"))
                            .madFont(size: 14, weight: .heavy, design: .rounded)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 6)
                    Menu {
                        Button(String(localized: "None")) { model.shoes[t] = nil }
                        ForEach(shoeStore.active) { shoe in
                            Button(name(shoe)) { model.shoes[t] = shoe.shoe_id }
                        }
                    } label: {
                        Text(String(localized: "Change"))
                            .madFont(size: 13, weight: .black, design: .rounded)
                            .foregroundStyle(RPV2Colors.orange)
                    }
                }
                .padding(.vertical, 9)
                if t != RunPlanV2ShoeRunType.allCases.last { Divider().overlay(Color.white.opacity(0.07)) }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(RPV2Colors.card))
        .task { await shoeStore.refreshIfStale() }
    }

    private func label(_ t: RunPlanV2ShoeRunType) -> String {
        switch t {
        case .easy: return String(localized: "Easy")
        case .long: return String(localized: "Long")
        case .tempo: return String(localized: "Tempo")
        case .intervals: return String(localized: "Intervals")
        case .race: return String(localized: "Race")
        case .walk: return String(localized: "Walk days")
        }
    }

    private func name(_ shoe: Shoe) -> String {
        [shoe.brand, shoe.name].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
    }
}

/// Settings › Workouts › Run plan: plan home (its toolbar holds the plan
/// settings). Always the same view, so `hasPlan` flipping mid-setup never
/// tears down the setup cover it presents.
struct RunPlanSettingsEntry: View {
    var body: some View { RunPlanHomeView() }
}
