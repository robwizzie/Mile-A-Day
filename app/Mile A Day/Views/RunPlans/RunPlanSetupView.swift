import SwiftUI

// New plan: Goals (step 1) → Effort (step 2) → POST /run-plans.

// MARK: - Goal draft

/// What the Goals step edits. Targets are race times in seconds; nil = just
/// finish / keep improving.
struct RunPlanGoalDraft: Equatable {
    var selected: [RunPlanGoalType] = []
    var targets: [RunPlanGoalType: Double] = [:]
    var finishBy: Date? = nil

    init() {}

    init(plan: RunPlan) {
        for goal in plan.goals {
            guard let type = goal.goalType else { continue }
            selected.append(type)
            if let t = goal.target_seconds { targets[type] = t }
        }
        finishBy = plan.finish_by.flatMap(RunPlanDate.date(from:))
    }

    var goals: [RunPlanGoal] {
        selected.map { RunPlanGoal(type: $0, targetSeconds: targets[$0], distanceMiles: $0.raceMiles) }
    }

    var finishByKey: String? { finishBy.map(RunPlanDate.key(for:)) }

    /// Goals that take a target time.
    static func takesTime(_ type: RunPlanGoalType) -> Bool {
        switch type {
        case .fasterMile, .fiveK, .tenK, .half, .marathon: return true
        case .firstFiveK, .moreMiles: return false
        }
    }

    /// The two goals that start with a target set; the longer races start at "just finish".
    static func startsWithTime(_ type: RunPlanGoalType) -> Bool { type == .fasterMile || type == .fiveK }

    static func step(_ type: RunPlanGoalType) -> Double {
        switch type {
        case .fasterMile: return 5
        case .fiveK: return 15
        case .tenK: return 30
        case .half: return 60
        default: return 120
        }
    }

    /// Current race time from the fitness snapshot (Riegel from the best 5K
    /// or mile when there's no direct number).
    static func now(_ type: RunPlanGoalType, fitness: RunPlanFitness?) -> Double? {
        guard let fitness, let miles = type.raceMiles else { return nil }
        let mile = fitness.best_mile_90d_s ?? fitness.best_mile_s
        if type == .fasterMile { return mile }
        if let fiveK = fitness.best_5k_s {
            return riegel(fiveK, from: 3.10686, to: miles)
        }
        if let mile { return riegel(mile, from: 1, to: miles) }
        return nil
    }

    private static func riegel(_ t: Double, from d1: Double, to d2: Double) -> Double {
        t * pow(d2 / d1, 1.06)
    }

    /// A first target: a bit faster than now, on a round number.
    static func suggestedTarget(_ type: RunPlanGoalType, fitness: RunPlanFitness?) -> Double? {
        guard let current = Self.now(type, fitness: fitness) else { return nil }
        switch type {
        case .fasterMile:
            return max(240, (current - 30).rounded(.down))
        default:
            let goal = current * 0.92
            return max(60, (goal / 60).rounded(.down) * 60 - 1)
        }
    }
}

// MARK: - Flow

struct RunPlanSetupFlow: View {
    @ObservedObject private var store = RunPlanStore.shared
    @State private var step = 1
    @State private var draft = RunPlanGoalDraft()
    @State private var effort = 3
    @State private var hardDaysOverride: Int? = nil
    @State private var runDailyMile = true
    @State private var building = false
    @State private var errorText: String?

    var body: some View {
        ScrollView {
            Group {
                if step == 1 {
                    RunPlanGoalsStep(draft: $draft, fitness: store.fitness, stepLabel: "Step 1 of 2",
                                     buttonTitle: "Next", busy: false) {
                        withAnimation(.easeOut(duration: 0.2)) { step = 2 }
                    }
                } else {
                    RunPlanEffortStep(effort: $effort, hardDaysOverride: $hardDaysOverride, runDailyMile: $runDailyMile,
                                      weeklyMiles: store.fitness?.weekly_miles, building: building, onBuild: build)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationBarBackButtonHidden(step == 2)
        .toolbar {
            if step == 2 {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        withAnimation(.easeOut(duration: 0.2)) { step = 1 }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 17, weight: .semibold))
                    }
                    .accessibilityLabel("Back to goals")
                }
            }
        }
        .task {
            if !store.fitnessLoaded { await store.loadFitness() }
            seedTargets()
        }
        .alert("Couldn't build your plan", isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorText ?? "")
        }
    }

    private func seedTargets() {
        for type in RunPlanGoalType.allCases where draft.targets[type] == nil && RunPlanGoalDraft.startsWithTime(type) {
            if let t = RunPlanGoalDraft.suggestedTarget(type, fitness: store.fitness) { draft.targets[type] = t }
        }
    }

    private func build() {
        guard !building, !draft.selected.isEmpty else { return }
        building = true
        let request = RunPlanCreateRequest(goals: draft.goals, effort: effort, hard_days: hardDaysOverride,
                                           finish_by: draft.finishByKey, run_daily_mile: runDailyMile,
                                           today: RunPlanDate.todayKey())
        Task {
            defer { building = false }
            do {
                try await store.create(request)
                MADHaptics.success()
            } catch let error as RunPlanError {
                errorText = error.message
            } catch {
                errorText = RunPlanError.from(error).message
            }
        }
    }
}

// MARK: - Shared step chrome

struct RunPlanStepHeader: View {
    let step: String?
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let step {
                Text(step.uppercased())
                    .madFont(size: 11, weight: .black, design: .rounded, maxScale: 1.3)
                    .tracking(1)
                    .foregroundColor(.white.opacity(0.45))
            }
            Text(title)
                .madFont(size: 24, weight: .black, design: .rounded, maxScale: 1.5)
                .foregroundColor(.white)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let subtitle {
                Text(subtitle)
                    .madFont(size: 13, weight: .medium, design: .rounded)
                    .foregroundColor(.white.opacity(0.5))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct RunPlanPrimaryButton: View {
    let title: String
    var busy = false
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button {
            MADHaptics.action()
            action()
        } label: {
            ZStack {
                Text(title)
                    .madFont(size: 16, weight: .black, design: .rounded, maxScale: 1.4)
                    .opacity(busy ? 0 : 1)
                if busy { ProgressView().tint(.black) }
            }
            .foregroundColor(.black)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(Capsule().fill(RunPlanColors.orange.opacity(enabled ? 1 : 0.4)))
        }
        .buttonStyle(.plain)
        .disabled(!enabled || busy)
    }
}

// MARK: - Step 1: Goals

struct RunPlanGoalsStep: View {
    @Binding var draft: RunPlanGoalDraft
    let fitness: RunPlanFitness?
    var stepLabel: String? = nil
    let buttonTitle: String
    var busy = false
    let onNext: () -> Void

    @State private var byDate = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            RunPlanStepHeader(step: stepLabel, title: "What do you want to get better at?", subtitle: "Pick as many as you like.")

            ForEach(draft.selected, id: \.self) { type in
                selectedCard(type)
            }

            FlowLayout(spacing: 6) {
                ForEach(RunPlanGoalType.allCases.filter { !draft.selected.contains($0) }) { type in
                    Button {
                        MADHaptics.tap()
                        add(type)
                    } label: {
                        Text("\(RunPlanFormat.goalEmoji(type)) \(RunPlanFormat.goalName(type))")
                            .madFont(size: 13, weight: .heavy, design: .rounded, maxScale: 1.4)
                            .foregroundColor(.white.opacity(0.78))
                            .lineLimit(1)
                            .padding(.horizontal, 12)
                            .frame(minHeight: 34)
                            .background(Capsule().fill(Color.white.opacity(0.06)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add goal: \(RunPlanFormat.goalName(type))")
                }
            }

            finishLine

            if let note = flameyNote {
                RunPlanFlameyNote(text: note)
            }

            RunPlanPrimaryButton(title: buttonTitle, busy: busy, enabled: !draft.selected.isEmpty, action: onNext)
        }
        .onAppear { byDate = draft.finishBy != nil }
    }

    private func add(_ type: RunPlanGoalType) {
        withAnimation(.easeOut(duration: 0.15)) {
            draft.selected.append(type)
            if draft.targets[type] == nil, RunPlanGoalDraft.startsWithTime(type),
               let t = RunPlanGoalDraft.suggestedTarget(type, fitness: fitness) {
                draft.targets[type] = t
            }
        }
    }

    private func remove(_ type: RunPlanGoalType) {
        withAnimation(.easeOut(duration: 0.15)) { draft.selected.removeAll { $0 == type } }
    }

    private func selectedCard(_ type: RunPlanGoalType) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(RunPlanFormat.goalEmoji(type))
                    .font(.system(size: 18))
                    .accessibilityHidden(true)
                Text(RunPlanFormat.goalName(type))
                    .madFont(size: 15, weight: .black, design: .rounded)
                    .foregroundColor(.white)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                Button {
                    MADHaptics.tap()
                    remove(type)
                } label: {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .black))
                        .foregroundColor(.black)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(RunPlanColors.orange))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(-11)
                .accessibilityLabel("Remove goal: \(RunPlanFormat.goalName(type))")
            }
            if RunPlanGoalDraft.takesTime(type) {
                timeRow(type)
            } else {
                Text(type == .firstFiveK ? "Build up to running 5K without stopping." : "More miles each week, at a safe pace of growth.")
                    .madFont(size: 12, weight: .medium, design: .rounded)
                    .foregroundColor(.white.opacity(0.5))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if type == .fasterMile, let foot = bestMileFootnote {
                Text(foot)
                    .madFont(size: 11, weight: .medium, design: .rounded)
                    .foregroundColor(.white.opacity(0.4))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(RunPlanColors.orange.opacity(0.10)))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(RunPlanColors.orange, lineWidth: 2))
    }

    @ViewBuilder
    private func timeRow(_ type: RunPlanGoalType) -> some View {
        let now = RunPlanGoalDraft.now(type, fitness: fitness)
        let target = draft.targets[type]
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                nowLabel(now)
                Image(systemName: "arrow.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white.opacity(0.35))
                    .accessibilityHidden(true)
                targetControl(type, target: target, now: now)
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading, spacing: 6) {
                nowLabel(now)
                targetControl(type, target: target, now: now)
            }
        }
    }

    private func nowLabel(_ now: Double?) -> some View {
        Text(nowText(now))
            .madFont(size: 13, weight: .bold, design: .rounded)
            .foregroundColor(.white.opacity(0.55))
            .lineLimit(1)
            .fixedSize()
    }

    private func nowText(_ now: Double?) -> String {
        guard let now else { return "No timed runs yet" }
        // Race times past the mile are estimates from shorter efforts.
        let approx = now > 400 ? "~" : ""
        return "Now \(approx)\(RunPlanFormat.clock(now))"
    }

    @ViewBuilder
    private func targetControl(_ type: RunPlanGoalType, target: Double?, now: Double?) -> some View {
        if let target {
            HStack(spacing: 2) {
                stepButton("minus", label: "Faster") { draft.targets[type] = max(60, target - RunPlanGoalDraft.step(type)) }
                Text(type == .fasterMile ? "Beat \(RunPlanFormat.clock(target))" : RunPlanFormat.clock(target))
                    .madFont(size: 13, weight: .black, design: .rounded, monospacedDigit: true)
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 6)
                stepButton("plus", label: "Slower") { draft.targets[type] = target + RunPlanGoalDraft.step(type) }
                if !RunPlanGoalDraft.startsWithTime(type) {
                    Button("Just finish") { draft.targets[type] = nil }
                        .madFont(size: 12, weight: .heavy, design: .rounded)
                        .foregroundColor(RunPlanColors.orange)
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.leading, 6)
                }
            }
            .padding(.horizontal, 4)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.08)))
            .accessibilityElement(children: .contain)
        } else {
            Button {
                MADHaptics.tap()
                let base = now.map { ($0 / 60).rounded(.down) * 60 } ?? defaultTime(type)
                draft.targets[type] = base
            } label: {
                Text("Just finish · set a time")
                    .madFont(size: 13, weight: .heavy, design: .rounded)
                    .foregroundColor(RunPlanColors.orange)
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                    .frame(minHeight: 32)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.08)))
            }
            .buttonStyle(.plain)
        }
    }

    private func defaultTime(_ type: RunPlanGoalType) -> Double {
        switch type {
        case .fasterMile: return 480
        case .fiveK, .firstFiveK: return 1800
        case .tenK: return 3600
        case .half: return 7200
        case .marathon: return 16200
        case .moreMiles: return 0
        }
    }

    private func stepButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button {
            MADHaptics.tap()
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .black))
                .foregroundColor(.white.opacity(0.8))
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var bestMileFootnote: String? {
        guard let fitness, fitness.best_mile_s != nil, let raw = fitness.best_mile_date,
              let date = RunPlanDate.date(from: String(raw.prefix(10))) else { return nil }
        let when = date.formatted(.dateTime.month(.abbreviated).day())
        return "your best, \(when)\(fitness.best_mile_indoor == true ? " (treadmill)" : "")"
    }

    private var finishLine: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Finish line")
                .madFont(size: 13, weight: .bold, design: .rounded)
                .foregroundColor(.white)
            HStack(spacing: 0) {
                segment("Keep improving", on: !byDate) {
                    byDate = false
                    draft.finishBy = nil
                }
                segment("By a date", on: byDate) {
                    byDate = true
                    if draft.finishBy == nil {
                        draft.finishBy = Calendar.current.date(byAdding: .weekOfYear, value: 12, to: Date())
                    }
                }
            }
            .padding(4)
            .background(Capsule().fill(Color.white.opacity(0.06)))
            if byDate {
                DatePicker("Finish by",
                           selection: Binding(get: { draft.finishBy ?? Date() }, set: { draft.finishBy = $0 }),
                           in: minFinish...maxFinish, displayedComponents: .date)
                    .madFont(size: 14, weight: .semibold, design: .rounded)
                    .foregroundColor(.white)
                    .tint(RunPlanColors.orange)
            }
        }
    }

    private var minFinish: Date { Calendar.current.date(byAdding: .day, value: 21, to: Date()) ?? Date() }
    private var maxFinish: Date { Calendar.current.date(byAdding: .year, value: 2, to: Date()) ?? Date() }

    private func segment(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button {
            MADHaptics.tap()
            withAnimation(.easeOut(duration: 0.15)) { action() }
        } label: {
            Text(title)
                .madFont(size: 13, weight: .black, design: .rounded, maxScale: 1.4)
                .foregroundColor(on ? .black : .white.opacity(0.6))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: 34)
                .background(Capsule().fill(on ? RunPlanColors.orange : Color.clear))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    /// A big jump gets checkpoints; say so before they build.
    private var flameyNote: String? {
        for type in draft.selected {
            guard let target = draft.targets[type], let now = RunPlanGoalDraft.now(type, fitness: fitness),
                  now > 0, (now - target) / now > 0.1 else { continue }
            return "\(RunPlanFormat.clock(target)) from ~\(RunPlanFormat.clock(now)) is a big jump, so we'll get there in steps. Your plan sets checkpoints along the way."
        }
        return nil
    }
}

// MARK: - Step 2: Effort

struct RunPlanEffortStep: View {
    @Binding var effort: Int
    @Binding var hardDaysOverride: Int?
    @Binding var runDailyMile: Bool
    let weeklyMiles: Double?
    var stepLabel: String? = "Step 2 of 2"
    var buttonTitle: String = "Build my plan"
    let building: Bool
    let onBuild: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            RunPlanStepHeader(step: stepLabel, title: "How hard do you want to go?")

            VStack(alignment: .leading, spacing: 10) {
                RunPlanEffortSlider(effort: $effort)
                Text(effort == 4 ? "All in 🔥" : RunPlanFormat.effortLabel(effort))
                    .madFont(size: 20, weight: .black, design: .rounded)
                    .foregroundColor(.white)
                    .padding(.top, 6)
                RunPlanEffortDetails(effort: effort, hardDays: hardDaysOverride, weeklyMiles: weeklyMiles)
            }
            .runPlanCard(radius: 20)

            RunPlanDailyMileRows(runDailyMile: $runDailyMile)

            RunPlanHardDaysPicker(effort: effort, hardDaysOverride: $hardDaysOverride)

            RunPlanPrimaryButton(title: buttonTitle, busy: building, action: onBuild)
        }
    }
}

struct RunPlanEffortSlider: View {
    @Binding var effort: Int

    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { geo in
                let inset: CGFloat = 12
                let width = max(1, geo.size.width - inset * 2)
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(RunPlanColors.effortGradient)
                        .frame(height: 5)
                        .padding(.horizontal, inset)
                    ForEach(1...4, id: \.self) { i in
                        let on = i == effort
                        Circle()
                            .fill(on ? Color.white : RunPlanColors.card)
                            .overlay(Circle().strokeBorder(on ? Color.white : Color.white.opacity(0.3), lineWidth: 3))
                            .frame(width: on ? 24 : 17, height: on ? 24 : 17)
                            .position(x: inset + width * CGFloat(i - 1) / 3, y: geo.size.height / 2)
                    }
                }
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                    let fraction = min(1, max(0, (value.location.x - inset) / width))
                    let next = Int((fraction * 3).rounded()) + 1
                    if next != effort {
                        MADHaptics.tap()
                        effort = next
                    }
                })
            }
            .frame(height: 34)

            HStack(spacing: 0) {
                ForEach(1...4, id: \.self) { i in
                    Text(RunPlanFormat.effortLabel(i))
                        .madFont(size: 11, weight: .black, design: .rounded, maxScale: 1.3)
                        .foregroundColor(i == effort ? (i == 4 ? RunPlanColors.red : .white) : .white.opacity(0.45))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Effort")
        .accessibilityValue(RunPlanFormat.effortLabel(effort))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: effort = min(4, effort + 1)
            case .decrement: effort = max(1, effort - 1)
            @unknown default: break
            }
        }
    }
}

struct RunPlanEffortDetails: View {
    let effort: Int
    let hardDays: Int?
    let weeklyMiles: Double?

    var body: some View {
        let n = hardDays ?? RunPlanFormat.hardDays(forEffort: effort)
        let cap = RunPlanFormat.growthCap(forEffort: effort)
        VStack(alignment: .leading, spacing: 8) {
            row("bolt.fill", tint: RunPlanColors.red,
                bold: n == 1 ? "1 hard workout a week:" : "\(n) hard workouts a week:",
                rest: hardDetail(n))
            row("chart.line.uptrend.xyaxis", tint: RunPlanColors.orange,
                bold: weeklyMiles.map { "Miles build from your ~\(RunPlanFormat.distance($0)) a week now," } ?? "Miles build gradually,",
                rest: "no faster than \(cap)% a week")
            row("moon.fill", tint: RunPlanColors.blue, bold: "Easy days are truly easy.", rest: "That's where the speed comes from.")
        }
    }

    private func hardDetail(_ n: Int) -> String {
        var text: String
        switch n {
        case 1: text = "one quality session, the rest easy"
        case 2: text = "intervals and one longer run"
        case 3: text = "intervals, tempo, one longer run"
        default: text = "intervals, tempo, longer runs"
        }
        if effort == 4 { text += ", plus strides on easy days" }
        return text
    }

    private func row(_ icon: String, tint: Color, bold: String, rest: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .madFont(size: 13, weight: .bold, maxScale: 1.3)
                .foregroundColor(tint)
                .frame(width: 18)
                .padding(.top, 2)
                .accessibilityHidden(true)
            (Text(bold).foregroundColor(.white).bold() + Text(" " + rest).foregroundColor(.white.opacity(0.7)))
                .madFont(size: 13, weight: .medium, design: .rounded)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

struct RunPlanDailyMileRows: View {
    @Binding var runDailyMile: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "shield.fill")
                    .madFont(size: 16, weight: .bold, maxScale: 1.3)
                    .foregroundColor(RunPlanColors.green)
                    .frame(width: 22)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text("At least 1 mile, every day")
                        .madFont(size: 14, weight: .bold, design: .rounded)
                        .foregroundColor(.white)
                    Text("Always on. The plan never asks you to skip.")
                        .madFont(size: 12, weight: .medium, design: .rounded)
                        .foregroundColor(.white.opacity(0.45))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                Image(systemName: "lock.fill")
                    .madFont(size: 13, weight: .bold, maxScale: 1.3)
                    .foregroundColor(.white.opacity(0.35))
                    .accessibilityLabel("Always on")
            }
            .accessibilityElement(children: .combine)
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 1)
                .padding(.leading, 34)
                .padding(.vertical, 10)
            Toggle(isOn: $runDailyMile) {
                HStack(spacing: 12) {
                    Image(systemName: "figure.run")
                        .madFont(size: 16, weight: .bold, maxScale: 1.3)
                        .foregroundColor(RunPlanColors.orange)
                        .frame(width: 22)
                        .accessibilityHidden(true)
                    Text("Run the daily mile, don't walk it")
                        .madFont(size: 14, weight: .bold, design: .rounded)
                        .foregroundColor(.white)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .tint(RunPlanColors.green)
        }
        .runPlanCard(radius: 18, padding: 12)
    }
}

struct RunPlanHardDaysPicker: View {
    let effort: Int
    @Binding var hardDaysOverride: Int?

    var body: some View {
        let chosen = hardDaysOverride ?? RunPlanFormat.hardDays(forEffort: effort)
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack {
                    title
                    Spacer(minLength: 4)
                    caption
                }
                VStack(alignment: .leading, spacing: 2) {
                    title
                    caption
                }
            }
            HStack(spacing: 5) {
                ForEach(1...7, id: \.self) { n in
                    let on = n == chosen
                    Button {
                        MADHaptics.tap()
                        // Tapping the effort's own number (or the override again) clears the override.
                        if n == RunPlanFormat.hardDays(forEffort: effort) || n == hardDaysOverride {
                            hardDaysOverride = nil
                        } else {
                            hardDaysOverride = n
                        }
                    } label: {
                        Text("\(n)")
                            .madFont(size: 15, weight: .black, design: .rounded, maxScale: 1.3)
                            .foregroundColor(on ? .black : .white)
                            .frame(maxWidth: .infinity, minHeight: 40)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(on ? RunPlanColors.orange : Color.white.opacity(0.06)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(n) hard day\(n == 1 ? "" : "s") a week")
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            if chosen >= 5 {
                Text("That's a lot of hard days. Most runners improve faster with more easy ones, and the plan keeps your weekly growth capped either way.")
                    .madFont(size: 12, weight: .semibold, design: .rounded)
                    .foregroundColor(Color(red: 1.0, green: 0.78, blue: 0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var title: some View {
        Text("Hard days per week")
            .madFont(size: 13, weight: .bold, design: .rounded)
            .foregroundColor(.white)
    }

    private var caption: some View {
        Text(hardDaysOverride == nil ? "set by effort · tap to override" : "your pick · tap again to reset")
            .madFont(size: 11, weight: .heavy, design: .rounded)
            .foregroundColor(.white.opacity(0.4))
            .lineLimit(1)
    }
}
