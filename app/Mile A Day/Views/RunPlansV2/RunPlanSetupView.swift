import SwiftUI

// Run Plans v2 setup (mockup screens 1–3): Goals → Effort + walk days →
// What I found (analysis, shoes, coach notes) → Build plan. The same step
// views edit a live plan from `RunPlanV2SettingsView`.

// MARK: - Model

@MainActor
@Observable
final class RunPlanSetupModel {
    struct DistanceGoal: Identifiable, Equatable {
        var distance: RunPlanV2GoalDistance
        /// Target time text "mm:ss" / "h:mm:ss" (empty = no target).
        var targetText: String = ""
        /// Custom distance only.
        var customMiles: Double = 2.0
        var id: String { distance.rawValue }
    }

    var distanceGoals: [DistanceGoal] = []
    var justImprove = false
    var burnCalories = false
    var burnStretch = false
    var hasTargetDate = false
    var targetDate: Date = Calendar.current.date(byAdding: .weekOfYear, value: 12, to: Date()) ?? Date()
    var runsPerWeek = 4
    var difficulty: RunPlanV2Difficulty = .steady
    var walkMode: RunPlanV2WalkMode = .builtIn
    /// 0 = Monday … 6 = Sunday.
    var fixedWalkDays: Set<Int> = [3, 6]
    var coachNotes = ""
    /// shoe run type → shoe id (nil = none).
    var shoes: [RunPlanV2ShoeRunType: String] = [:]

    var preview: RunPlanV2PlanWithDays?
    var previewError: String?
    var isBuilding = false
    var error: String?

    init() {}

    /// Seeds from a live plan (settings edit).
    init(plan: RunPlanV2Plan) {
        for g in plan.goals {
            switch g.goalType {
            case .justImprove: justImprove = true
            case .burnCalories:
                burnCalories = true
                burnStretch = (g.weekly_minutes ?? 150) >= 225
            case .distanceTime:
                var d = DistanceGoal(distance: g.goalDistance ?? .custom)
                d.targetText = g.target_s.map(RPV2Format.clock) ?? ""
                d.customMiles = g.distance_mi ?? 2
                distanceGoals.append(d)
            }
        }
        if let td = plan.target_date, let d = RunPlanV2Date.date(from: td) {
            hasTargetDate = true
            targetDate = d
        }
        runsPerWeek = plan.runs_per_week ?? 4
        difficulty = plan.difficultyLevel
        walkMode = plan.walkMode
        if !plan.fixed_walk_days.isEmpty { fixedWalkDays = Set(plan.fixed_walk_days) }
        coachNotes = plan.coach_notes ?? ""
        for t in RunPlanV2ShoeRunType.allCases {
            if let id = plan.shoeId(for: t) { shoes[t] = id }
        }
    }

    // MARK: Validation

    var walkDayCount: Int { 7 - runsPerWeek }

    var goals: [RunPlanV2Goal] {
        var out: [RunPlanV2Goal] = distanceGoals.map { d in
            RunPlanV2Goal(type: .distanceTime, distance: d.distance,
                          distanceMi: d.distance == .custom ? d.customMiles : d.distance.miles,
                          targetSeconds: Self.parseClock(d.targetText))
        }
        if justImprove { out.append(RunPlanV2Goal(type: .justImprove)) }
        if burnCalories { out.append(RunPlanV2Goal(type: .burnCalories, weeklyMinutes: burnStretch ? 225 : 150)) }
        return out
    }

    var goalsValid: Bool {
        let g = goals
        return !g.isEmpty && g.count <= 4
            && distanceGoals.allSatisfy { $0.targetText.isEmpty || Self.parseClock($0.targetText) != nil }
    }

    var effortValid: Bool {
        walkMode != .fixed || fixedWalkDays.count == walkDayCount
    }

    /// The earliest/latest target date the server accepts.
    var targetDateRange: ClosedRange<Date> {
        let cal = Calendar.current
        let lo = cal.date(byAdding: .day, value: 14, to: Date()) ?? Date()
        let hi = cal.date(byAdding: .weekOfYear, value: 52, to: Date()) ?? Date()
        return lo...hi
    }

    func toggle(_ d: RunPlanV2GoalDistance) {
        if let i = distanceGoals.firstIndex(where: { $0.distance == d }) {
            distanceGoals.remove(at: i)
        } else if goals.count < 4 {
            distanceGoals.append(DistanceGoal(distance: d))
            distanceGoals.sort { (RunPlanV2GoalDistance.allCases.firstIndex(of: $0.distance) ?? 0)
                < (RunPlanV2GoalDistance.allCases.firstIndex(of: $1.distance) ?? 0) }
        }
    }

    func setRuns(_ n: Int) {
        runsPerWeek = n
        // Keep the fixed days the right length: drop from the end, add from Sunday back.
        while fixedWalkDays.count > walkDayCount, let last = fixedWalkDays.sorted().last { fixedWalkDays.remove(last) }
        var candidate = 6
        while fixedWalkDays.count < walkDayCount, candidate >= 0 {
            fixedWalkDays.insert(candidate)
            candidate -= 2
            if candidate < 0, fixedWalkDays.count < walkDayCount {
                for d in 0..<7 where fixedWalkDays.count < walkDayCount { fixedWalkDays.insert(d) }
            }
        }
    }

    // MARK: Requests

    var shoeAssignments: RunPlanV2ShoeAssignments? {
        guard !shoes.isEmpty else { return nil }
        var out: RunPlanV2ShoeAssignments = [:]
        for t in RunPlanV2ShoeRunType.allCases { out[t.rawValue] = shoes[t] }
        return out
    }

    func createRequest() -> RunPlanV2CreateRequest {
        RunPlanV2CreateRequest(
            today: RunPlanV2Date.todayKey(), goals: goals,
            target_date: hasTargetDate ? RunPlanV2Date.key(for: targetDate) : nil,
            runs_per_week: runsPerWeek, difficulty: difficulty.rawValue, walk_mode: walkMode.rawValue,
            fixed_walk_days: walkMode == .fixed ? fixedWalkDays.sorted() : [],
            coach_notes: String(coachNotes.prefix(2000)), shoe_assignments: shoeAssignments,
            start_date: nil, initial_days: nil, source: "formula")
    }

    func patch() -> RunPlanV2PlanPatch {
        var p = RunPlanV2PlanPatch()
        p.goals = goals
        p.target_date = .some(hasTargetDate ? RunPlanV2Date.key(for: targetDate) : nil)
        p.runs_per_week = runsPerWeek
        p.difficulty = difficulty.rawValue
        p.walk_mode = walkMode.rawValue
        p.fixed_walk_days = walkMode == .fixed ? fixedWalkDays.sorted() : []
        p.coach_notes = String(coachNotes.prefix(2000))
        p.shoe_assignments = shoeAssignments
        return p
    }

    private var previewTask: Task<Void, Never>?

    /// The formula draft for the current answers (hard-session count, ramp).
    func refreshPreview() {
        previewTask?.cancel()
        guard goalsValid, effortValid else { return }
        let request = createRequest()
        previewTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            do {
                preview = try await RunPlanV2Store.shared.preview(request)
                previewError = nil
            } catch let e as RunPlanV2Error {
                previewError = e.message
            } catch {
                previewError = nil
            }
        }
    }

    /// "6:47", "26:00", "1:52:10" → seconds.
    static func parseClock(_ text: String) -> Int? {
        let parts = text.trimmingCharacters(in: .whitespaces).split(separator: ":").map { Int($0) }
        guard !parts.isEmpty, parts.allSatisfy({ $0 != nil }) else { return nil }
        let n = parts.compactMap { $0 }
        let s: Int
        switch n.count {
        case 2: s = n[0] * 60 + n[1]
        case 3: s = n[0] * 3600 + n[1] * 60 + n[2]
        default: return nil
        }
        return s > 60 && s < 24 * 3600 ? s : nil
    }
}

// MARK: - Flow

/// Setup, presented full screen (from the dashboard card or plan entry).
struct RunPlanSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model = RunPlanSetupModel()
    @State private var step = 1
    @ObservedObject private var store = RunPlanV2Store.shared
    @ObservedObject private var analyzer = RunFitnessAnalyzer.shared
    @State private var showConsent = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    switch step {
                    case 1: RunPlanGoalsStep(model: model, profile: analyzer.profile)
                    case 2: RunPlanEffortStep(model: model, profile: analyzer.profile)
                    default: RunPlanFindingsStep(model: model, tier: store.coachTier)
                    }
                    if let error = model.error {
                        RPV2Notice(icon: "exclamationmark.triangle.fill", text: error, tint: RPV2Colors.orange)
                    }
                    actionButton
                        .padding(.top, 4)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color.black.ignoresSafeArea())
            .navigationTitle(String(localized: "New plan"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(step == 1 ? String(localized: "Cancel") : String(localized: "Back")) {
                        if step == 1 { dismiss() } else { withAnimation { step -= 1 } }
                    }
                    .foregroundStyle(RPV2Colors.orange)
                }
            }
            .sheet(isPresented: $showConsent) {
                RunPlanAnthropicConsentView { accepted in
                    showConsent = false
                    if accepted { Task { await build() } }
                }
            }
        }
        .preferredColorScheme(.dark)
        .task {
            // The goal rows' "Now" numbers come from the cached profile; refresh
            // quietly if there's none yet (no prompt: HR waits for step 3).
            if analyzer.profile == nil { await analyzer.analyze(upload: false) }
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        switch step {
        case 1:
            RPV2Button(title: String(localized: "Next")) { withAnimation { step = 2 }; model.refreshPreview() }
                .disabled(!model.goalsValid)
                .opacity(model.goalsValid ? 1 : 0.45)
        case 2:
            RPV2Button(title: String(localized: "Next")) { withAnimation { step = 3 } }
                .disabled(!model.effortValid)
                .opacity(model.effortValid ? 1 : 0.45)
        default:
            RPV2Button(title: String(localized: "Build plan"), icon: "sparkles", isBusy: model.isBuilding) {
                if store.ai.mode == .anthropic, !store.ai.hasAnthropicConsent {
                    showConsent = true
                } else {
                    Task { await build() }
                }
            }
            .disabled(analyzer.isAnalyzing)
        }
    }

    private func build() async {
        model.isBuilding = true
        model.error = nil
        defer { model.isBuilding = false }
        if let profile = analyzer.profile { await analyzer.uploadIfNeeded(profile, force: true) }
        do {
            try await RunPlanCoach.createPlan(model.createRequest(), profile: analyzer.profile)
            MADHaptics.success()
            dismiss()
        } catch let e as RunPlanV2Error {
            model.error = e.message
        } catch {
            model.error = RunPlanV2Error.offline.message
        }
    }
}

// MARK: - Step 1 · Goals

struct RunPlanGoalsStep: View {
    @Bindable var model: RunPlanSetupModel
    let profile: RunPlanV2FitnessProfile?
    var showsHeader = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if showsHeader {
                RPV2StepHeader(step: String(localized: "Step 1 of 3"), title: String(localized: "What are you training for?"),
                               subtitle: String(localized: "Pick one or more."))
            }
            distanceCard
            toggleCard(on: model.justImprove, icon: "chart.line.uptrend.xyaxis", tint: RPV2Colors.green,
                       title: String(localized: "Just improve"),
                       text: String(localized: "4-week blocks that build, then a retest every 6 to 8 weeks.")) {
                model.justImprove.toggle()
            }
            toggleCard(on: model.burnCalories, icon: "flame.fill", tint: RPV2Colors.red,
                       title: String(localized: "Burn more calories"),
                       text: String(localized: "Plans around time on your feet: 150 min a week, stretch 225+. You can track your weight in the Health app. No diet advice.")) {
                model.burnCalories.toggle()
            }
            if model.burnCalories {
                Toggle(isOn: $model.burnStretch) {
                    Text(String(localized: "Stretch goal: 225+ minutes a week"))
                        .madFont(size: 13, weight: .bold, design: .rounded)
                }
                .tint(RPV2Colors.green)
                .padding(.horizontal, 4)
            }
            targetDate
            if let note = flameyNote {
                FlameyNote(text: note)
            }
        }
    }

    private var distanceOn: Bool { !model.distanceGoals.isEmpty }

    private var chipItems: [(id: String, label: String, on: Bool)] {
        RunPlanV2GoalDistance.allCases.map { d -> (id: String, label: String, on: Bool) in
            (id: d.rawValue, label: RPV2Format.distanceName(d == .custom ? nil : d, miles: nil),
             on: model.distanceGoals.contains { $0.distance == d })
        }
    }

    private var distanceCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "target").madFont(size: 16, weight: .bold, maxScale: 1.15)
                    .foregroundStyle(RPV2Colors.orange).accessibilityHidden(true)
                Text(String(localized: "Distance + time"))
                    .madFont(size: 15, weight: .black, design: .rounded)
                    .frame(maxWidth: .infinity, alignment: .leading)
                RPV2CheckDot(on: distanceOn)
            }
            RunPlanChipFlow(items: chipItems) { raw in
                if let d = RunPlanV2GoalDistance(rawValue: raw) { model.toggle(d) }
            }
            ForEach($model.distanceGoals) { $goal in
                RunPlanGoalTargetRow(goal: $goal, now: now(for: goal.distance), best: best(for: goal.distance))
            }
        }
        .padding(12)
        .background(selectedBackground(distanceOn))
    }

    private func toggleCard(on: Bool, icon: String, tint: Color, title: String, text: String,
                            action: @escaping () -> Void) -> some View {
        Button(action: { MADHaptics.tap(); action() }) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Image(systemName: icon).madFont(size: 16, weight: .bold, maxScale: 1.15)
                        .foregroundStyle(tint).accessibilityHidden(true)
                    Text(title)
                        .madFont(size: 15, weight: .black, design: .rounded)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    RPV2CheckDot(on: on)
                }
                Text(text)
                    .madFont(size: 12, design: .rounded)
                    .foregroundStyle(.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
            }
            .foregroundStyle(.white)
            .padding(12)
            .background(selectedBackground(on))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private var targetDate: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(String(localized: "Target date"))
                .madFont(size: 13, weight: .bold, design: .rounded)
            dateOption(on: !model.hasTargetDate, title: String(localized: "No date, keep improving")) { model.hasTargetDate = false }
            dateOption(on: model.hasTargetDate, title: String(localized: "By a date")) { model.hasTargetDate = true }
            if model.hasTargetDate {
                DatePicker(String(localized: "Date"), selection: $model.targetDate, in: model.targetDateRange,
                           displayedComponents: .date)
                    .madFont(size: 14, weight: .semibold, design: .rounded)
                    .tint(RPV2Colors.orange)
                    .padding(.horizontal, 12)
            }
        }
    }

    private func dateOption(on: Bool, title: String, action: @escaping () -> Void) -> some View {
        Button(action: { MADHaptics.tap(); action() }) {
            HStack(spacing: 8) {
                Image(systemName: on ? "checkmark" : "calendar")
                    .madFont(size: 14, weight: .black, maxScale: 1.15)
                    .foregroundStyle(on ? RPV2Colors.orange : .white.opacity(0.4))
                    .accessibilityHidden(true)
                Text(title)
                    .madFont(size: 14, weight: .heavy, design: .rounded)
                    .foregroundStyle(.white)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(selectedBackground(on, radius: 14))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func selectedBackground(_ on: Bool, radius: CGFloat = 18) -> some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(on ? RPV2Colors.orange.opacity(0.10) : RPV2Colors.card)
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(on ? RPV2Colors.orange : .clear, lineWidth: 2))
    }

    private func now(for d: RunPlanV2GoalDistance) -> Int? {
        profile?.race_estimates?.seconds(for: d)
    }

    private func best(for d: RunPlanV2GoalDistance) -> RunPlanV2BestEffort? {
        profile?.best_efforts.first { $0.distance == d.rawValue }
    }

    /// Checkpoints for a big jump (the server sets them; this says why).
    private var flameyNote: String? {
        for g in model.distanceGoals {
            guard let target = RunPlanSetupModel.parseClock(g.targetText), let now = now(for: g.distance) else { continue }
            if Double(now - target) / Double(now) > 0.12 {
                return String(localized: "That's a big jump from about \(RPV2Format.clock(now)), so we'll go in checkpoints and move the target as you get faster.")
            }
        }
        return nil
    }
}

/// One distance goal: "5K  Now ~26:00 → [19:59]".
struct RunPlanGoalTargetRow: View {
    @Binding var goal: RunPlanSetupModel.DistanceGoal
    let now: Int?
    let best: RunPlanV2BestEffort?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(RPV2Format.distanceName(goal.distance == .custom ? nil : goal.distance,
                                             miles: goal.distance == .custom ? goal.customMiles : nil))
                    .madFont(size: 13, weight: .black, design: .rounded)
                    .lineLimit(1)
                    .frame(minWidth: 56, alignment: .leading)
                if let now {
                    Text(String(localized: "Now ~\(RPV2Format.clock(now))"))
                        .madFont(size: 13, weight: .bold, design: .rounded)
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Image(systemName: "arrow.right").madFont(size: 12, maxScale: 1.15)
                    .foregroundStyle(.white.opacity(0.35)).accessibilityHidden(true)
                TextField(String(localized: "Target"), text: $goal.targetText)
                    .keyboardType(.numbersAndPunctuation)
                    .madFont(size: 13, weight: .black, design: .rounded)
                    .multilineTextAlignment(.center)
                    .frame(minWidth: 64, maxWidth: 90)
                    .padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.1)))
                    .accessibilityLabel(String(localized: "Target time"))
                Spacer(minLength: 0)
            }
            if goal.distance == .custom {
                Stepper(value: $goal.customMiles, in: 0.5...31.1, step: 0.5) {
                    Text(RPV2Format.distance(goal.customMiles))
                        .madFont(size: 12, weight: .bold, design: .rounded)
                }
            }
            Text(footnote)
                .madFont(size: 11, design: .rounded)
                .foregroundStyle(.white.opacity(0.5))
                .madBodyLines(2)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.black.opacity(0.3)))
    }

    private var footnote: String {
        if let best, let s = best.seconds {
            return String(localized: "Your best is \(RPV2Format.clock(s)). Type a target like 6:45, or leave it empty.")
        }
        if now != nil { return String(localized: "Estimated from your runs. Type a target like 24:00, or leave it empty.") }
        return String(localized: "Type a target like 24:00, or leave it empty.")
    }
}

/// Wrapping row of selectable chips.
struct RunPlanChipFlow: View {
    let items: [(id: String, label: String, on: Bool)]
    let onTap: (String) -> Void

    var body: some View {
        RunPlanFlowLayout(spacing: 5) {
            ForEach(items, id: \.id) { item in
                Button { MADHaptics.tap(); onTap(item.id) } label: {
                    Text(item.label)
                        .madFont(size: 12, weight: .heavy, design: .rounded)
                        .lineLimit(1)
                        .foregroundStyle(item.on ? .black : .white.opacity(0.75))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(item.on ? RPV2Colors.orange : Color.white.opacity(0.07)))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(item.on ? .isSelected : [])
            }
        }
    }
}

/// Minimal wrapping layout (iOS 16 `Layout`).
struct RunPlanFlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, maxX: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width { x = 0; y += rowH + spacing; rowH = 0 }
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
            rowH = max(rowH, size.height)
        }
        return CGSize(width: min(maxX, width), height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowH = max(rowH, size.height)
        }
    }
}

// MARK: - Step 2 · Effort + walk days

struct RunPlanEffortStep: View {
    @Bindable var model: RunPlanSetupModel
    let profile: RunPlanV2FitnessProfile?
    var showsHeader = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if showsHeader {
                RPV2StepHeader(step: String(localized: "Step 2 of 3"), title: String(localized: "How much, how hard?"))
            }
            runsCard
            difficultyCard
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "Walk days")).madFont(size: 13, weight: .bold, design: .rounded)
                Text(String(localized: "\"Walk it off\": the days you don't run."))
                    .madFont(size: 12, design: .rounded).foregroundStyle(.white.opacity(0.5))
            }
            walkOption(.builtIn, title: String(localized: "Built in"),
                       text: String(localized: "The coach places them around your hard runs."))
            walkOption(.fixed, title: String(localized: "Fixed days"), text: String(localized: "You pick the days."))
            walkOption(.flexible, title: String(localized: "Flexible"),
                       text: String(localized: "Walk when you want. I'll tell you when you've earned one, or when you need one."))
            RPV2Notice(icon: "figure.walk", text: String(localized: "Walk days still keep your streak: 1 mile or 10k steps."),
                       tint: RPV2Colors.mint, fill: RPV2Colors.green.opacity(0.12))
        }
        .onChange(of: model.runsPerWeek) { _, _ in model.refreshPreview() }
        .onChange(of: model.difficulty) { _, _ in model.refreshPreview() }
        .onChange(of: model.walkMode) { _, _ in model.refreshPreview() }
    }

    private var runsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) { runsTitle; Spacer(minLength: 6); runsCaption }
                VStack(alignment: .leading, spacing: 2) { runsTitle; runsCaption }
            }
            HStack(spacing: 4) {
                ForEach(1...7, id: \.self) { n in
                    Button { MADHaptics.tap(); model.setRuns(n) } label: {
                        Text("\(n)")
                            .madFont(size: 15, weight: .black, design: .rounded, maxScale: 1.3)
                            .foregroundStyle(n == model.runsPerWeek ? .black : .white)
                            .frame(maxWidth: .infinity, minHeight: 34)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(n == model.runsPerWeek ? RPV2Colors.orange : Color.white.opacity(0.06)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(String(localized: "\(n) runs a week"))
                    .accessibilityAddTraits(n == model.runsPerWeek ? .isSelected : [])
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(RPV2Colors.card))
    }

    private var runsTitle: some View {
        Text(String(localized: "Runs per week")).madFont(size: 13, weight: .bold, design: .rounded)
    }

    private var runsCaption: some View {
        Text(model.walkDayCount == 1
             ? String(localized: "\(model.runsPerWeek) runs, 1 walk day")
             : String(localized: "\(model.runsPerWeek) runs, \(model.walkDayCount) walk days"))
            .madFont(size: 11, weight: .heavy, design: .rounded)
            .foregroundStyle(.white.opacity(0.45))
    }

    private var difficultyCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "Difficulty")).madFont(size: 13, weight: .bold, design: .rounded)
            RunPlanDifficultySlider(value: $model.difficulty)
            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(effortLines.enumerated()), id: \.offset) { _, line in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: line.icon).madFont(size: 13, weight: .bold, maxScale: 1.15)
                            .foregroundStyle(line.tint).padding(.top, 2).accessibilityHidden(true)
                        Text(line.text)
                            .madFont(size: 13, design: .rounded)
                            .foregroundStyle(.white.opacity(0.75))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.top, 4)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(RPV2Colors.card))
    }

    private var effortLines: [(icon: String, tint: Color, text: String)] {
        var lines: [(icon: String, tint: Color, text: String)] = []
        if let hard = model.preview?.plan.hard_sessions_per_week {
            let text: String
            switch hard {
            case 0: text = String(localized: "No hard runs yet: easy running with a few strides while you build.")
            case 1: text = String(localized: "1 hard run a week, the rest easy.")
            default: text = String(localized: "\(hard) hard runs a week, the rest easy.")
            }
            lines.append(("bolt.fill", RPV2Colors.red, text))
        }
        if let base = profile?.weekly_miles_4w, base > 0 {
            lines.append(("waveform.path.ecg", RPV2Colors.orange,
                          String(localized: "Miles build from \(RPV2Format.distance(base)) a week, about 10% at a time.")))
        }
        if lines.isEmpty {
            lines.append(("bolt.fill", RPV2Colors.red,
                          String(localized: "Harder settings add hard runs and build your miles faster.")))
        }
        return lines
    }

    private func walkOption(_ mode: RunPlanV2WalkMode, title: String, text: String) -> some View {
        let on = model.walkMode == mode
        return VStack(alignment: .leading, spacing: 8) {
            Button { MADHaptics.tap(); model.walkMode = mode } label: {
                HStack(alignment: .top, spacing: 8) {
                    RPV2CheckDot(on: on)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).madFont(size: 14, weight: .black, design: .rounded)
                        Text(text).madFont(size: 12, design: .rounded).foregroundStyle(.white.opacity(0.55))
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 0)
                }
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(on ? .isSelected : [])
            if mode == .fixed, on { fixedDays }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(on ? RPV2Colors.orange.opacity(0.10) : RPV2Colors.card)
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(on ? RPV2Colors.orange : .clear, lineWidth: 1.5))
        )
    }

    private var fixedDays: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 3) {
                ForEach(0..<7, id: \.self) { d in
                    let on = model.fixedWalkDays.contains(d)
                    Button {
                        MADHaptics.tap()
                        if on { model.fixedWalkDays.remove(d) } else { model.fixedWalkDays.insert(d) }
                        model.refreshPreview()
                    } label: {
                        Text(Self.weekdayLetters[d])
                            .madFont(size: 11, weight: .black, design: .rounded, maxScale: 1.3)
                            .foregroundStyle(on ? .white : .white.opacity(0.45))
                            .frame(maxWidth: .infinity, minHeight: 28)
                            .background(RoundedRectangle(cornerRadius: 8).fill(on ? Color.white.opacity(0.18) : Color.white.opacity(0.05)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Self.weekdayNames[d])
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            if !model.effortValid {
                Text(model.walkDayCount == 1
                     ? String(localized: "Pick 1 walk day.")
                     : String(localized: "Pick \(model.walkDayCount) walk days."))
                    .madFont(size: 11, weight: .bold, design: .rounded)
                    .foregroundStyle(RPV2Colors.orange)
            }
        }
        .padding(.leading, 28)
    }

    /// Monday-first, localized.
    static let weekdayLetters: [String] = {
        let s = Calendar.current.veryShortStandaloneWeekdaySymbols
        return (0..<7).map { s[($0 + 1) % 7] }
    }()

    static let weekdayNames: [String] = {
        let s = Calendar.current.standaloneWeekdaySymbols
        return (0..<7).map { s[($0 + 1) % 7] }
    }()
}

/// The four-stop difficulty slider (Easy does it · Steady · Push · All in).
struct RunPlanDifficultySlider: View {
    @Binding var value: RunPlanV2Difficulty

    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { geo in
                let inset: CGFloat = 11
                let w = max(geo.size.width - inset * 2, 1)
                ZStack(alignment: .leading) {
                    Capsule().fill(RPV2Colors.difficulty).frame(height: 5).padding(.horizontal, inset)
                    ForEach(RunPlanV2Difficulty.allCases, id: \.rawValue) { d in
                        let i = CGFloat(d.rawValue - 1)
                        let on = d == value
                        Circle()
                            .fill(on ? Color.white : RPV2Colors.card)
                            .overlay(Circle().strokeBorder(on ? Color.white : Color.white.opacity(0.3), lineWidth: 3))
                            .frame(width: on ? 23 : 15, height: on ? 23 : 15)
                            .position(x: inset + w * i / 3, y: 15)
                    }
                }
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                    let i = Int(((g.location.x - inset) / w * 3).rounded())
                    if let d = RunPlanV2Difficulty(rawValue: min(max(i, 0), 3) + 1), d != value {
                        MADHaptics.tap()
                        value = d
                    }
                })
            }
            .frame(height: 30)
            HStack(spacing: 0) {
                ForEach(RunPlanV2Difficulty.allCases, id: \.rawValue) { d in
                    Text(RPV2Format.difficultyLabel(d))
                        .madFont(size: 11, weight: .black, design: .rounded, maxScale: 1.4)
                        .foregroundStyle(d == value ? RPV2Colors.orange : .white.opacity(0.45))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "Difficulty"))
        .accessibilityValue(RPV2Format.difficultyLabel(value))
        .accessibilityAdjustableAction { dir in
            switch dir {
            case .increment: if let d = RunPlanV2Difficulty(rawValue: value.rawValue + 1) { value = d }
            case .decrement: if let d = RunPlanV2Difficulty(rawValue: value.rawValue - 1) { value = d }
            @unknown default: break
            }
        }
    }
}

// MARK: - Step 3 · What I found

struct RunPlanFindingsStep: View {
    @Bindable var model: RunPlanSetupModel
    let tier: RunPlanV2CoachTier
    @ObservedObject private var analyzer = RunFitnessAnalyzer.shared
    private var shoeStore: ShoeStore { ShoeStore.shared }
    @State private var started = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            RPV2StepHeader(step: String(localized: "Step 3 of 3"), title: String(localized: "What I found"))
            if analyzer.profile == nil && (analyzer.isAnalyzing || !started) {
                analyzing
            } else if let p = analyzer.profile {
                RunPlanFindingsCard(profile: p)
                calibration(p)
            } else {
                RPV2Notice(icon: "heart.text.square", text: String(localized: "I couldn't read your runs from Apple Health. Your plan starts from a short test run instead."))
            }
            if !shoeStore.active.isEmpty { shoesCard }
            if tier.isAI { notesCard }
        }
        .task {
            await shoeStore.refreshIfStale()
            guard !started else { return }
            if !analyzer.hasAskedForAccess { await analyzer.requestAccess() }
            started = true
            await analyzer.analyze(upload: false)
            seedShoes()
        }
    }

    private var analyzing: some View {
        RPV2Card {
            HStack(spacing: 10) {
                FlameyAvatar(size: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "Reading your last 100 runs…"))
                        .madFont(size: 15, weight: .black, design: .rounded)
                    Text(String(localized: "Only steady running counts, not walk breaks. Your runs stay on this iPhone."))
                        .madFont(size: 12, design: .rounded).foregroundStyle(.white.opacity(0.55))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                ProgressView().tint(.white)
            }
        }
    }

    @ViewBuilder
    private func calibration(_ p: RunPlanV2FitnessProfile) -> some View {
        if p.needsCalibration {
            RPV2Notice(icon: "timer", text: calibrationText(p.calibration_kind), tint: .white.opacity(0.75),
                       fill: RPV2Colors.orange.opacity(0.10))
        } else {
            RPV2Notice(icon: "checkmark.circle.fill", text: String(localized: "No calibration runs needed"),
                       tint: RPV2Colors.mint, fill: RPV2Colors.green.opacity(0.12))
        }
    }

    private func calibrationText(_ kind: String?) -> String {
        switch kind {
        case "mile_tt_talk_test":
            return String(localized: "Need 2 calibration runs: a 1-mile time trial and an easy run where you can still talk. They're the first runs in your plan.")
        case "3k":
            return String(localized: "Need 1 calibration run: a 3K at a hard, even effort. It's the first run in your plan.")
        case "lthr_30min":
            return String(localized: "Need 1 calibration run: 30 minutes at a hard, even effort with your Apple Watch. It's the first run in your plan.")
        default:
            return String(localized: "Need 1 calibration run: a 5K at a hard, even effort. It's the first run in your plan.")
        }
    }

    // MARK: Shoes (only for users with shoes in the app)

    private var shoesCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: ShoeSymbol.filled).madFont(size: 14, weight: .bold, maxScale: 1.15)
                    .foregroundStyle(RPV2Colors.orange).accessibilityHidden(true)
                Text(String(localized: "Shoes for each run")).madFont(size: 13, weight: .bold, design: .rounded)
            }
            .padding(.bottom, 4)
            shoeRow(String(localized: "Easy & long"), types: [.easy, .long, .race])
            Divider().overlay(Color.white.opacity(0.07))
            shoeRow(String(localized: "Intervals & tempo"), types: [.intervals, .tempo])
            Divider().overlay(Color.white.opacity(0.07))
            shoeRow(String(localized: "Walk days"), types: [.walk])
            Text(String(localized: "Loaded on each run for you."))
                .madFont(size: 11, design: .rounded).foregroundStyle(.white.opacity(0.5))
                .padding(.top, 4)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(RPV2Colors.card))
    }

    private func shoeRow(_ title: String, types: [RunPlanV2ShoeRunType]) -> some View {
        let current = types.first.flatMap { model.shoes[$0] }
        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                RPV2Eyebrow(text: title, color: .white.opacity(0.45))
                Text(shoeStore.shoe(id: current).map(shoeName) ?? String(localized: "None"))
                    .madFont(size: 14, weight: .heavy, design: .rounded)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            Menu {
                Button(String(localized: "None")) { types.forEach { model.shoes[$0] = nil } }
                ForEach(shoeStore.active) { shoe in
                    Button(shoeName(shoe)) { types.forEach { model.shoes[$0] = shoe.shoe_id } }
                }
            } label: {
                Text(String(localized: "Change"))
                    .madFont(size: 13, weight: .black, design: .rounded)
                    .foregroundStyle(RPV2Colors.orange)
            }
        }
        .padding(.vertical, 8)
    }

    private func shoeName(_ shoe: Shoe) -> String {
        [shoe.brand, shoe.name].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// Defaults: running default for runs, walking default for walk days.
    private func seedShoes() {
        guard model.shoes.isEmpty else { return }
        if let run = shoeStore.defaultShoe(for: .running) {
            for t in [RunPlanV2ShoeRunType.easy, .long, .race, .intervals, .tempo] { model.shoes[t] = run.shoe_id }
        }
        if let walk = shoeStore.defaultShoe(for: .walking) { model.shoes[.walk] = walk.shoe_id }
    }

    // MARK: Coach notes (AI only)

    private var notesCard: some View {
        RunPlanCoachNotesEditor(text: $model.coachNotes)
    }
}

/// "Notes for the coach" (AI tiers only; read by the coach model only).
struct RunPlanCoachNotesEditor: View {
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(String(localized: "Notes for the coach"))
                    .madFont(size: 13, weight: .bold, design: .rounded)
                    .frame(maxWidth: .infinity, alignment: .leading)
                RPV2TierBadge(ai: true)
            }
            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text(String(localized: "Anything the coach should know (health, schedule, preferences)…"))
                        .madFont(size: 13, design: .rounded)
                        .foregroundStyle(.white.opacity(0.35))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 10)
                        .allowsHitTesting(false)
                }
                TextField("", text: $text, axis: .vertical)
                    .madFont(size: 13, design: .rounded)
                    .lineLimit(3...8)
                    .padding(10)
                    .onChange(of: text) { _, new in if new.count > 2000 { text = String(new.prefix(2000)) } }
                    .accessibilityLabel(String(localized: "Notes for the coach"))
            }
            .frame(minHeight: 64, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.04))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.white.opacity(0.1)))
            )
            HStack(spacing: 6) {
                Image(systemName: "lock.fill").madFont(size: 10, maxScale: 1.15).accessibilityHidden(true)
                Text(String(localized: "Only the coach reads this."))
                    .madFont(size: 11, design: .rounded)
            }
            .foregroundStyle(.white.opacity(0.5))
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(RPV2Colors.card))
    }
}

/// "I read your last 100 runs" + the six numbers + treadmill / steady lines.
struct RunPlanFindingsCard: View {
    let profile: RunPlanV2FitnessProfile

    var body: some View {
        RPV2Card {
            HStack(spacing: 10) {
                FlameyAvatar(size: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text(profile.runs_analyzed == 1
                         ? String(localized: "I read your last run")
                         : String(localized: "I read your last \(profile.runs_analyzed ?? 0) runs"))
                        .madFont(size: 15, weight: .black, design: .rounded)
                    Text(subtitle)
                        .madFont(size: 12, design: .rounded).foregroundStyle(.white.opacity(0.55))
                        .madBodyLines(2)
                }
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
                ForEach(Array(tiles.enumerated()), id: \.offset) { _, t in
                    tile(t.label, t.value, t.sub)
                }
            }
            .padding(.top, 12)
            VStack(alignment: .leading, spacing: 8) {
                if let t = profile.treadmill_fraction, t >= 0.3, let n = profile.runs_analyzed, n > 0 {
                    line(icon: "figure.run.treadmill", tint: RPV2Colors.green,
                         bold: String(localized: "\(Int((t * Double(n)).rounded())) of your \(n) runs were on the treadmill."),
                         rest: String(localized: "I'll give those targets as belt speeds."))
                }
                line(icon: "figure.walk", tint: RPV2Colors.orange, bold: nil,
                     rest: String(localized: "I only used steady running, not walk breaks."))
                if !profile.hasHeartRate {
                    line(icon: "heart.slash", tint: .white.opacity(0.6), bold: nil,
                         rest: String(localized: "No heart rate in your runs, so I'll describe how each run should feel instead of zones."))
                }
            }
            .padding(.top, 12)
        }
    }

    private var subtitle: String {
        var parts: [String] = []
        if let d = profile.first_run_date { parts.append(String(localized: "Since \(RPV2Format.dayHeader(d))")) }
        if let m = profile.total_miles { parts.append(RPV2Format.distance(m)) }
        if let w = profile.weekly_miles_4w { parts.append(String(localized: "\(RPV2Format.distance(w))/week lately")) }
        return parts.joined(separator: " · ")
    }

    private var tiles: [(label: String, value: String, sub: String?)] {
        var out: [(label: String, value: String, sub: String?)] = []
        if let s = profile.race_estimates?.five_k_s { out.append((String(localized: "Est. 5K"), RPV2Format.clock(s), nil)) }
        if let mile = profile.best_efforts.first(where: { $0.distance == "mile" }), let s = mile.seconds {
            out.append((String(localized: "Best mile"), RPV2Format.clock(s), mile.date.map(RPV2Format.dayHeader)))
        }
        if let z2 = profile.zones.first(where: { $0.zone == 2 }), let lo = z2.low, let hi = z2.high {
            out.append((String(localized: "Zone 2"), "\(lo)–\(hi)",
                        profile.zone2_pace_s.map { String(localized: "bpm · about \(RPV2Format.pace($0))") } ?? String(localized: "bpm")))
        } else if let e = profile.easy_pace_s {
            out.append((String(localized: "Easy pace"), RPV2Format.pace(e), nil))
        }
        if let l = profile.longest_run_mi { out.append((String(localized: "Longest run"), RPV2Format.distance(l), nil)) }
        if let m = profile.max_hr {
            out.append((String(localized: "Max HR"), "\(m)",
                        profile.max_hr_source == "observed" ? String(localized: "observed") : String(localized: "estimated from age")))
        }
        if let r = profile.resting_hr { out.append((String(localized: "Resting HR"), "\(r)", String(localized: "from Health"))) }
        return out
    }

    private func tile(_ label: String, _ value: String, _ sub: String?) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            RPV2Eyebrow(text: label, color: .white.opacity(0.5))
            Text(value)
                .madFont(size: 19, weight: .black, design: .rounded, maxScale: 1.5)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let sub {
                Text(sub).madFont(size: 11, design: .rounded).foregroundStyle(.white.opacity(0.5)).lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.05)))
        .accessibilityElement(children: .combine)
    }

    private func line(icon: String, tint: Color, bold: String?, rest: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon).madFont(size: 13, weight: .semibold, maxScale: 1.15)
                .foregroundStyle(tint).padding(.top, 1).accessibilityHidden(true)
            (Text(bold.map { $0 + " " } ?? "").foregroundColor(.white).bold() + Text(rest).foregroundColor(.white.opacity(0.7)))
                .madFont(size: 12, design: .rounded)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
