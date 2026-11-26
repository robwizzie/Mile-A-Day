import SwiftUI

// Run Plans v2 setup (mockup screens 1–3): Goals → Effort + walk days →
// What I found (analysis, shoes, coach notes) → Build plan. The same step
// views edit a live plan from `RunPlanV2SettingsView`.

// MARK: - Model

@MainActor
@Observable
final class RunPlanSetupModel {
    /// One goal being edited (primary or secondary).
    struct GoalDraft: Equatable {
        var type: RunPlanV2GoalType = .distanceTime
        var distance: RunPlanV2GoalDistance = .fiveK
        /// Target time text "mm:ss" / "h:mm:ss" (empty = no target).
        var targetText: String = ""
        /// Custom distance only.
        var customMiles: Double = 2.0
        /// burn_calories: 225+ minutes a week instead of 150.
        var burnStretch = false
        /// false = as soon as possible.
        var hasDate = false
        var date: Date = Calendar.current.date(byAdding: .weekOfYear, value: 12, to: Date()) ?? Date()

        init(distance: RunPlanV2GoalDistance = .fiveK) { self.distance = distance }

        init(goal: RunPlanV2Goal) {
            type = goal.goalType
            distance = goal.goalDistance ?? (goal.goalType == .distanceTime ? .custom : .fiveK)
            targetText = goal.target_s.map(RPV2Format.clock) ?? ""
            customMiles = goal.distance_mi ?? 2
            burnStretch = (goal.weekly_minutes ?? 150) >= 225
            if let key = goal.target_date, let d = RunPlanV2Date.date(from: key) {
                hasDate = true
                date = d
            }
        }

        var targetSeconds: Int? { RunPlanSetupModel.parseClock(targetText) }
        var miles: Double? { distance == .custom ? customMiles : distance.miles }
        var dateKey: String? { hasDate ? RunPlanV2Date.key(for: date) : nil }
        var isValid: Bool { type != .distanceTime || targetText.isEmpty || targetSeconds != nil }

        func goal(role: RunPlanV2GoalRole) -> RunPlanV2Goal {
            switch type {
            case .distanceTime:
                return RunPlanV2Goal(type: .distanceTime, distance: distance, distanceMi: miles,
                                     targetSeconds: targetSeconds, role: role, targetDate: dateKey)
            case .justImprove:
                return RunPlanV2Goal(type: .justImprove, role: role, targetDate: dateKey)
            case .burnCalories:
                return RunPlanV2Goal(type: .burnCalories, weeklyMinutes: burnStretch ? 225 : 150,
                                     role: role, targetDate: dateKey)
            }
        }

        /// Same goal as a served one (to pick its estimate).
        func matches(_ g: RunPlanV2Goal) -> Bool {
            guard g.goalType == type else { return false }
            guard type == .distanceTime else { return true }
            guard g.goalDistance == distance, g.target_s == targetSeconds else { return false }
            guard distance == .custom else { return true }
            return abs((g.distance_mi ?? 0) - customMiles) < 0.05
        }
    }

    var primary = GoalDraft()
    var secondary: GoalDraft?
    var runsPerWeek = 4
    var difficulty: RunPlanV2Difficulty = .steady
    var walkMode: RunPlanV2WalkMode = .builtIn
    /// 0 = Monday … 6 = Sunday.
    var fixedWalkDays: Set<Int> = [3, 6]
    var coachNotes = ""
    /// Run type → shoe id (nil = none). Never `walk`: walk days get no shoe.
    var shoes: [RunPlanV2ShoeRunType: String] = [:]

    var preview: RunPlanV2PlanWithDays?
    var previewError: String?
    /// A preview request is on its way (the goal cards say "Estimating").
    var isPreviewing = false
    var isBuilding = false
    var error: String?
    /// Settings edit: the live plan's goals (their estimates until a preview lands).
    private(set) var liveGoals: [RunPlanV2Goal] = []

    init() {}

    /// Seeds from a live plan (settings edit).
    init(plan: RunPlanV2Plan) {
        liveGoals = plan.goals
        if let p = plan.primaryGoal {
            primary = GoalDraft(goal: p)
            // Old plans carry the date on the plan only.
            if p.target_date == nil, let td = plan.target_date, let d = RunPlanV2Date.date(from: td) {
                primary.hasDate = true
                primary.date = d
            }
        }
        if let s = plan.secondaryGoal { secondary = GoalDraft(goal: s) }
        runsPerWeek = plan.runs_per_week ?? 4
        difficulty = plan.difficultyLevel
        walkMode = plan.walkMode
        if !plan.fixed_walk_days.isEmpty { fixedWalkDays = Set(plan.fixed_walk_days) }
        coachNotes = plan.coach_notes ?? ""
        for t in RunPlanV2ShoeRunType.runTypes {
            if let id = plan.shoeId(for: t) { shoes[t] = id }
        }
    }

    // MARK: Validation

    var walkDayCount: Int { 7 - runsPerWeek }

    var goals: [RunPlanV2Goal] {
        var out = [primary.goal(role: .primary)]
        if let secondary { out.append(secondary.goal(role: .secondary)) }
        return out
    }

    /// Why the secondary can't be saved as it is (nil = fine).
    var secondaryProblem: String? {
        guard let s = secondary else { return nil }
        if s.type == primary.type, s.type != .distanceTime {
            return String(localized: "Pick a different kind of goal for the secondary.")
        }
        if s.type == .distanceTime, primary.type == .distanceTime, s.distance == primary.distance, s.distance != .custom {
            return String(localized: "Pick a different distance for the secondary.")
        }
        return nil
    }

    var goalsValid: Bool {
        primary.isValid && (secondary?.isValid ?? true) && secondaryProblem == nil
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

    /// The server's estimate for a draft: the latest preview's, else the
    /// live plan's while the goal is unchanged. Nil = not known yet.
    func estimate(for role: RunPlanV2GoalRole) -> RunPlanV2GoalEstimate? {
        guard let draft = role == .primary ? primary : secondary else { return nil }
        let served = preview?.plan.goals ?? []
        if let g = served.first(where: { $0.goalRole == role }), draft.matches(g) { return g.estimate }
        if let g = liveGoals.first(where: { $0.goalRole == role }), draft.matches(g) { return g.estimate }
        return nil
    }

    func addSecondary() {
        var d = GoalDraft(distance: primary.distance == .fiveK ? .tenK : .fiveK)
        if primary.type != .distanceTime { d.type = .distanceTime }
        secondary = d
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
        for t in RunPlanV2ShoeRunType.runTypes { out[t.rawValue] = shoes[t] }
        return out
    }

    func createRequest() -> RunPlanV2CreateRequest {
        RunPlanV2CreateRequest(
            today: RunPlanV2Date.todayKey(), goals: goals,
            // Plan-level date = the primary's (they must match).
            target_date: primary.dateKey,
            runs_per_week: runsPerWeek, difficulty: difficulty.rawValue, walk_mode: walkMode.rawValue,
            fixed_walk_days: walkMode == .fixed ? fixedWalkDays.sorted() : [],
            coach_notes: String(coachNotes.prefix(2000)), shoe_assignments: shoeAssignments,
            start_date: nil, initial_days: nil, source: "formula")
    }

    func patch() -> RunPlanV2PlanPatch {
        var p = RunPlanV2PlanPatch()
        p.goals = goals
        p.target_date = .some(primary.dateKey)
        p.runs_per_week = runsPerWeek
        p.difficulty = difficulty.rawValue
        p.walk_mode = walkMode.rawValue
        p.fixed_walk_days = walkMode == .fixed ? fixedWalkDays.sorted() : []
        p.coach_notes = String(coachNotes.prefix(2000))
        p.shoe_assignments = shoeAssignments
        return p
    }

    private var previewTask: Task<Void, Never>?

    /// The formula draft for the current answers: goal estimates, the
    /// hard-session count and what the effort level means (`volume`).
    func refreshPreview() {
        previewTask?.cancel()
        guard goalsValid, effortValid else {
            isPreviewing = false
            return
        }
        let request = createRequest()
        isPreviewing = true
        previewTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            do {
                let fresh = try await RunPlanV2Store.shared.preview(request)
                guard !Task.isCancelled else { return }
                preview = fresh
                previewError = nil
            } catch let e as RunPlanV2Error {
                previewError = e.message
            } catch {
                previewError = nil
            }
            if !Task.isCancelled { isPreviewing = false }
        }
    }

    /// "6:47", "26:00", "1:52:10" → seconds.
    nonisolated static func parseClock(_ text: String) -> Int? {
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
                RPV2StepHeader(step: String(localized: "Step 2 of 3"), title: String(localized: "How often, how much?"))
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
            hardSessionsLine
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(RPV2Colors.card))
    }

    private var runsTitle: some View {
        Text(String(localized: "Runs per week")).madFont(size: 13, weight: .bold, design: .rounded)
    }

    private var runsCaption: some View {
        Text(model.walkDayCount == 1
             ? String(localized: "1 walk day")
             : String(localized: "\(model.walkDayCount) walk days"))
            .madFont(size: 11, weight: .heavy, design: .rounded)
            .foregroundStyle(.white.opacity(0.45))
    }

    /// "4 runs → 2 hard sessions a week. The rest stay easy (about 80% of
    /// your running)." Runs per week (plus experience) sets the hard days;
    /// effort never does.
    private var hardSessionsLine: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "bolt.fill").madFont(size: 13, weight: .bold, maxScale: 1.15)
                .foregroundStyle(RPV2Colors.red).padding(.top, 2).accessibilityHidden(true)
            (Text(hardSessionsBold).foregroundColor(.white).bold()
             + Text(" " + hardSessionsRest).foregroundColor(.white.opacity(0.65)))
                .madFont(size: 12, design: .rounded)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 2)
    }

    private var hardSessions: Int {
        RunPlanEffortMapping.hardSessions(runs: model.runsPerWeek, preview: model.preview?.plan,
                                          experience: profile?.experience,
                                          calorieGoal: model.primary.type == .burnCalories)
    }

    private var hardSessionsBold: String {
        let n = model.runsPerWeek
        let runs = n == 1 ? String(localized: "1 run") : String(localized: "\(n) runs")
        switch hardSessions {
        case 0: return String(localized: "\(runs) → no hard sessions yet.")
        case 1: return String(localized: "\(runs) → 1 hard session a week.")
        default: return String(localized: "\(runs) → \(hardSessions) hard sessions a week.")
        }
    }

    private var hardSessionsRest: String {
        hardSessions == 0
            ? String(localized: "Easy running with a few strides while you build.")
            : String(localized: "The rest stay easy (about 80% of your running).")
    }

    private var difficultyCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) { effortTitle; Spacer(minLength: 6); effortCaption }
                VStack(alignment: .leading, spacing: 2) { effortTitle; effortCaption }
            }
            RunPlanDifficultySlider(value: $model.difficulty)
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "waveform.path.ecg").madFont(size: 13, weight: .bold, maxScale: 1.15)
                    .foregroundStyle(RPV2Colors.orange).padding(.top, 2).accessibilityHidden(true)
                (Text(volume.bold).foregroundColor(.white).bold()
                 + Text(volume.rest.isEmpty ? "" : " " + volume.rest).foregroundColor(.white.opacity(0.7)))
                    .madFont(size: 13, design: .rounded)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 4)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(RPV2Colors.card))
    }

    private var effortTitle: some View {
        Text(String(localized: "Effort")).madFont(size: 13, weight: .bold, design: .rounded)
    }

    private var effortCaption: some View {
        Text(String(localized: "sets volume, not hard days"))
            .madFont(size: 11, weight: .heavy, design: .rounded)
            .foregroundStyle(.white.opacity(0.45))
    }

    /// What this effort level means: the preview's `volume` when it is for
    /// this level, else the documented per-level description.
    private var volume: (bold: String, rest: String) {
        let level = model.difficulty
        let served = model.preview?.plan.volume
        let current = served?.difficulty == level.rawValue ? served : nil
        return (RunPlanEffortMapping.headline(level), RunPlanEffortMapping.detail(level, volume: current))
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
        .accessibilityLabel(String(localized: "Effort"))
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

/// Runs per week → hard sessions, and what each effort level means (contract
/// §3, Nov 25 evening). The server's numbers win; these are the documented
/// fallbacks while a preview is on its way.
enum RunPlanEffortMapping {
    /// 1–3 runs → 1, 4–5 → 2, 6–7 → 2 (3 when experienced); new → 0,
    /// novice → ≤ 1, a calorie primary → ≤ 1.
    static func hardSessions(runs: Int, preview: RunPlanV2Plan?, experience: String?, calorieGoal: Bool) -> Int {
        if let plan = preview, plan.runs_per_week == runs, let served = plan.hard_sessions_per_week { return served }
        var n: Int
        switch runs {
        case ...3: n = 1
        case 4...5: n = 2
        default: n = experience == "experienced" ? 3 : 2
        }
        if experience == "new" { n = 0 }
        if experience == "novice" || calorieGoal { n = min(n, 1) }
        return n
    }

    static func headline(_ level: RunPlanV2Difficulty) -> String {
        switch level {
        case .easy: return String(localized: "Easy does it: a smaller version of the same week.")
        case .steady: return String(localized: "Steady: the same week at a steady build.")
        case .push: return String(localized: "Push: a bigger version of the same week.")
        case .allIn: return String(localized: "All in: the biggest version of the same week.")
        }
    }

    /// From the served `volume` (distances in the display unit), else the
    /// documented growth step per level.
    static func detail(_ level: RunPlanV2Difficulty, volume: RunPlanV2Volume?) -> String {
        guard let v = volume else { return fallback(level) }
        var parts: [String] = []
        if let g = v.weekly_growth_pct {
            parts.append(String(localized: "Weekly distance grows up to ~\(percent(g)) a week"))
        }
        if let l = v.long_run_target_mi, l > 0 {
            parts.append(String(localized: "long run builds to \(RPV2Format.distance(l))"))
        }
        if v.easy_day_mi.count == 2 {
            let lo = RPV2Format.number(v.easy_day_mi[0]), hi = RPV2Format.distance(v.easy_day_mi[1])
            parts.append(String(localized: "easy days \(lo)–\(hi)"))
        }
        if let r = v.interval_reps, r > 0 {
            parts.append(String(localized: "\(r) reps on interval days"))
        } else if let t = v.tempo_work_mi, t > 0 {
            parts.append(String(localized: "\(RPV2Format.distance(t)) of tempo work"))
        }
        if parts.isEmpty { return v.text ?? fallback(level) }
        return parts.joined(separator: ", ") + "."
    }

    private static func fallback(_ level: RunPlanV2Difficulty) -> String {
        switch level {
        case .easy: return String(localized: "Weekly distance grows up to ~5% a week, with shorter long runs and fewer reps.")
        case .steady: return String(localized: "Weekly distance grows up to ~7.5% a week.")
        case .push: return String(localized: "Weekly distance grows up to ~10% a week, with a longer long run and more reps.")
        case .allIn: return String(localized: "Weekly distance grows up to ~10% a week, with the longest long run and the most reps.")
        }
    }

    private static func percent(_ x: Double) -> String {
        abs(x - x.rounded()) < 0.05 ? "\(Int(x.rounded()))%" : String(format: "%.1f%%", x)
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
            RunPlanShoeRows(model: model)
            Text(String(localized: "Loaded on each run for you. Walk days don't need a shoe."))
                .madFont(size: 11, design: .rounded).foregroundStyle(.white.opacity(0.5))
                .padding(.top, 4)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(RPV2Colors.card))
    }

    /// Defaults: the running default for every run type. Walk days get none.
    private func seedShoes() {
        guard model.shoes.isEmpty else { return }
        if let run = shoeStore.defaultShoe(for: .running) {
            for t in RunPlanV2ShoeRunType.runTypes { model.shoes[t] = run.shoe_id }
        }
    }

    // MARK: Coach notes (AI only)

    private var notesCard: some View {
        RunPlanCoachNotesEditor(text: $model.coachNotes)
    }
}

/// The two shoe rows (contract run types only; walk days never get a shoe):
/// Easy & long (easy, long, race) and Intervals & tempo (intervals, tempo).
struct RunPlanShoeRows: View {
    @Bindable var model: RunPlanSetupModel
    private var shoeStore: ShoeStore { ShoeStore.shared }

    static let groups: [(title: String, types: [RunPlanV2ShoeRunType])] = [
        (String(localized: "Easy & long"), [.easy, .long, .race]),
        (String(localized: "Intervals & tempo"), [.intervals, .tempo]),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(Self.groups.enumerated()), id: \.offset) { i, g in
                if i > 0 { Divider().overlay(Color.white.opacity(0.07)) }
                row(g.title, types: g.types)
            }
        }
    }

    private func row(_ title: String, types: [RunPlanV2ShoeRunType]) -> some View {
        let current = types.first.flatMap { model.shoes[$0] }
        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                RPV2Eyebrow(text: title, color: .white.opacity(0.45))
                Text(shoeStore.shoe(id: current).map(Self.name) ?? String(localized: "None"))
                    .madFont(size: 14, weight: .heavy, design: .rounded)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            Menu {
                Button(String(localized: "None")) { types.forEach { model.shoes[$0] = nil } }
                ForEach(shoeStore.active) { shoe in
                    Button(Self.name(shoe)) { types.forEach { model.shoes[$0] = shoe.shoe_id } }
                }
            } label: {
                Text(String(localized: "Change"))
                    .madFont(size: 13, weight: .black, design: .rounded)
                    .foregroundStyle(RPV2Colors.orange)
            }
            .accessibilityLabel(String(localized: "Change shoe for \(title)"))
        }
        .padding(.vertical, 8)
    }

    static func name(_ shoe: Shoe) -> String {
        [shoe.brand, shoe.name].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
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
