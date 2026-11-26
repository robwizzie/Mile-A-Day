import SwiftUI

// Setup step 1 (mockup screen 1): a primary goal that shapes the plan and an
// optional secondary that gets one speed session a week. Each card has its
// type, target, date (or as soon as possible) and the server's estimate
// (`POST /run-plans/preview` → `plan.goals[].estimate`: limiter, projected
// date, checkpoints). Also the Goals editor in plan settings.

struct RunPlanGoalsStep: View {
    @Bindable var model: RunPlanSetupModel
    let profile: RunPlanV2FitnessProfile?
    var showsHeader = true
    @State private var editing: RunPlanV2GoalRole?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if showsHeader {
                RPV2StepHeader(step: String(localized: "Step 1 of 3"), title: String(localized: "What are you training for?"),
                               subtitle: String(localized: "One primary goal. A secondary one if you want it."))
            }
            RunPlanGoalCard(role: .primary, draft: $model.primary, estimate: model.estimate(for: .primary),
                            estimating: estimating, profile: profile, dateRange: model.targetDateRange,
                            editing: editingBinding(.primary))
            secondaryCard
            if let problem = model.secondaryProblem {
                RPV2Notice(icon: "exclamationmark.triangle.fill", text: problem, tint: RPV2Colors.orange)
            }
            RPV2Notice(icon: "info.circle",
                       text: String(localized: "Your primary goal shapes the plan. Your secondary gets one speed session a week. When you hit the primary, the plan offers to swap."))
        }
        .onAppear {
            if showsHeader, editing == nil, model.preview == nil { editing = .primary }
            model.refreshPreview()
        }
        .onChange(of: model.primary) { _, _ in model.refreshPreview() }
        .onChange(of: model.secondary) { _, _ in model.refreshPreview() }
    }

    /// A preview is on its way (the card shows "Estimating").
    private var estimating: Bool { model.isPreviewing }

    @ViewBuilder
    private var secondaryCard: some View {
        if model.secondary != nil {
            RunPlanGoalCard(role: .secondary, draft: secondaryBinding, estimate: model.estimate(for: .secondary),
                            estimating: estimating, profile: profile, dateRange: model.targetDateRange,
                            editing: editingBinding(.secondary)) {
                withAnimation { model.secondary = nil }
                editing = nil
            }
        } else {
            Button {
                MADHaptics.tap()
                withAnimation { model.addSecondary() }
                editing = .secondary
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill").madFont(size: 16, weight: .bold, maxScale: 1.15)
                        .foregroundStyle(RPV2Colors.orange).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(String(localized: "Add a secondary goal"))
                            .madFont(size: 14, weight: .black, design: .rounded)
                        Text(String(localized: "Optional. It gets one speed session a week."))
                            .madFont(size: 12, design: .rounded)
                            .foregroundStyle(.white.opacity(0.5))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .foregroundStyle(.white)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.2), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var secondaryBinding: Binding<RunPlanSetupModel.GoalDraft> {
        Binding(get: { model.secondary ?? RunPlanSetupModel.GoalDraft() },
                set: { model.secondary = $0 })
    }

    private func editingBinding(_ role: RunPlanV2GoalRole) -> Binding<Bool> {
        Binding(get: { editing == role },
                set: { on in withAnimation { editing = on ? role : nil } })
    }
}

// MARK: - One goal card

struct RunPlanGoalCard: View {
    let role: RunPlanV2GoalRole
    @Binding var draft: RunPlanSetupModel.GoalDraft
    let estimate: RunPlanV2GoalEstimate?
    let estimating: Bool
    let profile: RunPlanV2FitnessProfile?
    let dateRange: ClosedRange<Date>
    @Binding var editing: Bool
    var onRemove: (() -> Void)? = nil

    private var prominent: Bool { role == .primary }
    private var goal: RunPlanV2Goal { draft.goal(role: role) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            headerRow
            titleRow
            if editing { RunPlanGoalEditor(draft: $draft, profile: profile, dateRange: dateRange) }
            if !editing { dateSummary }
            RunPlanGoalEstimateLine(estimate: estimate, estimating: estimating && draft.isValid)
            if editing, let onRemove {
                Button { MADHaptics.tap(); onRemove() } label: {
                    Text(String(localized: "Remove secondary goal"))
                        .madFont(size: 13, weight: .black, design: .rounded)
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(maxWidth: .infinity, minHeight: 32)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(background)
    }

    private var background: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(prominent ? RPV2Colors.orange.opacity(0.10) : RPV2Colors.card)
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(prominent ? RPV2Colors.orange : Color.white.opacity(0.08), lineWidth: prominent ? 2 : 1))
    }

    private var headerRow: some View {
        HStack(spacing: 8) {
            RPV2Eyebrow(text: prominent ? String(localized: "Primary goal") : String(localized: "Secondary goal · optional"),
                        color: prominent ? RPV2Colors.orange : .white.opacity(0.45))
            Spacer(minLength: 6)
            Button { MADHaptics.tap(); editing.toggle() } label: {
                Text(editing ? String(localized: "Done") : String(localized: "Edit"))
                    .madFont(size: 13, weight: .black, design: .rounded)
                    .foregroundStyle(RPV2Colors.orange)
                    .lineLimit(1)
                    .fixedSize()
            }
            .buttonStyle(.plain)
            .accessibilityLabel(editing ? String(localized: "Done editing goal") : String(localized: "Edit goal"))
        }
    }

    private var titleRow: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .madFont(size: prominent ? 17 : 15, weight: .bold, maxScale: 1.15)
                .foregroundStyle(prominent ? RPV2Colors.orange : RPV2Colors.red)
                .padding(.top, 2)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(RPV2Format.goalTitle(goal))
                    .madFont(size: prominent ? 17 : 15, weight: .black, design: .rounded, maxScale: 1.4)
                    .fixedSize(horizontal: false, vertical: true)
                Text(RPV2Format.goalSubtitle(goal))
                    .madFont(size: 12, weight: .heavy, design: .rounded)
                    .foregroundStyle(.white.opacity(0.5))
                    .madBodyLines(2)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
    }

    private var icon: String {
        switch draft.type {
        case .distanceTime: return prominent ? "target" : "bolt.fill"
        case .justImprove: return "chart.line.uptrend.xyaxis"
        case .burnCalories: return "flame.fill"
        }
    }

    private var dateSummary: some View {
        HStack(spacing: 8) {
            Image(systemName: "calendar").madFont(size: 13, maxScale: 1.15)
                .foregroundStyle(.white.opacity(0.4)).accessibilityHidden(true)
            Text(String(localized: "Target date"))
                .foregroundStyle(.white.opacity(0.55))
                .lineLimit(1)
                .fixedSize()
            Spacer(minLength: 6)
            Text(draft.hasDate ? RPV2Format.dayHeader(RunPlanV2Date.key(for: draft.date)) : String(localized: "As soon as possible"))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .madFont(size: 12, weight: .heavy, design: .rounded)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.black.opacity(0.3)))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Editor (type, distance, target, date)

struct RunPlanGoalEditor: View {
    @Binding var draft: RunPlanSetupModel.GoalDraft
    let profile: RunPlanV2FitnessProfile?
    let dateRange: ClosedRange<Date>

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            RunPlanChipFlow(items: typeItems) { raw in
                if let t = RunPlanV2GoalType(rawValue: raw) { draft.type = t }
            }
            switch draft.type {
            case .distanceTime: distanceEditor
            case .justImprove:
                note(String(localized: "4-week blocks that build, then a retest every 6 to 8 weeks."))
            case .burnCalories:
                note(String(localized: "Plans around time on your feet: 150 min a week, stretch 225+. You can track your weight in the Health app. No diet advice."))
                Toggle(isOn: $draft.burnStretch) {
                    Text(String(localized: "Stretch goal: 225+ minutes a week"))
                        .madFont(size: 13, weight: .bold, design: .rounded)
                }
                .tint(RPV2Colors.green)
            }
            dateEditor
        }
    }

    private var typeItems: [(id: String, label: String, on: Bool)] {
        [(RunPlanV2GoalType.distanceTime.rawValue, String(localized: "Distance + time"), draft.type == .distanceTime),
         (RunPlanV2GoalType.justImprove.rawValue, String(localized: "Just improve"), draft.type == .justImprove),
         (RunPlanV2GoalType.burnCalories.rawValue, String(localized: "Burn more calories"), draft.type == .burnCalories)]
    }

    private var distanceItems: [(id: String, label: String, on: Bool)] {
        RunPlanV2GoalDistance.allCases.map { d -> (id: String, label: String, on: Bool) in
            (id: d.rawValue, label: RPV2Format.distanceName(d == .custom ? nil : d, miles: nil), on: draft.distance == d)
        }
    }

    private var distanceEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            RunPlanChipFlow(items: distanceItems) { raw in
                if let d = RunPlanV2GoalDistance(rawValue: raw) { draft.distance = d }
            }
            RunPlanGoalTargetRow(draft: $draft, now: now, best: best)
        }
    }

    private var now: Int? { profile?.race_estimates?.seconds(for: draft.distance) }
    private var best: RunPlanV2BestEffort? { profile?.best_efforts.first { $0.distance == draft.distance.rawValue } }

    private var dateEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(String(localized: "Target date"))
                .madFont(size: 13, weight: .bold, design: .rounded)
            dateOption(on: !draft.hasDate, title: String(localized: "As soon as possible")) { draft.hasDate = false }
            dateOption(on: draft.hasDate, title: String(localized: "By a date")) {
                draft.hasDate = true
                draft.date = min(max(draft.date, dateRange.lowerBound), dateRange.upperBound)
            }
            if draft.hasDate {
                DatePicker(String(localized: "Date"), selection: $draft.date, in: dateRange, displayedComponents: .date)
                    .madFont(size: 14, weight: .semibold, design: .rounded)
                    .tint(RPV2Colors.orange)
                    .padding(.horizontal, 4)
            }
        }
    }

    private func dateOption(on: Bool, title: String, action: @escaping () -> Void) -> some View {
        Button(action: { MADHaptics.tap(); action() }) {
            HStack(spacing: 8) {
                Image(systemName: on ? "checkmark" : "calendar")
                    .madFont(size: 13, weight: .black, maxScale: 1.15)
                    .foregroundStyle(on ? RPV2Colors.orange : .white.opacity(0.4))
                    .accessibilityHidden(true)
                Text(title)
                    .madFont(size: 13, weight: .heavy, design: .rounded)
                    .foregroundStyle(.white)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(on ? RPV2Colors.orange.opacity(0.12) : Color.black.opacity(0.3)))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .madFont(size: 12, design: .rounded)
            .foregroundStyle(.white.opacity(0.55))
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// One distance goal's target: "5K  Now ~26:00 → [19:59]".
struct RunPlanGoalTargetRow: View {
    @Binding var draft: RunPlanSetupModel.GoalDraft
    let now: Int?
    let best: RunPlanV2BestEffort?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                if let now {
                    Text(String(localized: "Now ~\(RPV2Format.clock(now))"))
                        .madFont(size: 13, weight: .bold, design: .rounded)
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Image(systemName: "arrow.right").madFont(size: 12, maxScale: 1.15)
                        .foregroundStyle(.white.opacity(0.35)).accessibilityHidden(true)
                }
                TextField(String(localized: "Target"), text: $draft.targetText)
                    .keyboardType(.numbersAndPunctuation)
                    .madFont(size: 13, weight: .black, design: .rounded)
                    .multilineTextAlignment(.center)
                    .frame(minWidth: 64, maxWidth: 90)
                    .padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.1)))
                    .accessibilityLabel(String(localized: "Target time"))
                Spacer(minLength: 0)
            }
            if draft.distance == .custom {
                Stepper(value: $draft.customMiles, in: 0.5...31.1, step: 0.5) {
                    Text(RPV2Format.distance(draft.customMiles))
                        .madFont(size: 12, weight: .bold, design: .rounded)
                }
            }
            Text(footnote)
                .madFont(size: 11, design: .rounded)
                .foregroundStyle(draft.isValid ? .white.opacity(0.5) : RPV2Colors.orange)
                .madBodyLines(2)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.black.opacity(0.3)))
    }

    private var footnote: String {
        if !draft.isValid { return String(localized: "Type a time like 24:00 or 1:52:10.") }
        if let best, let s = best.seconds {
            return String(localized: "Your best is \(RPV2Format.clock(s)). Type a target like 6:45, or leave it empty.")
        }
        if now != nil { return String(localized: "Estimated from your runs. Type a target like 24:00, or leave it empty.") }
        return String(localized: "Type a target like 24:00, or leave it empty.")
    }
}

// MARK: - The server's estimate

/// "Your speed is already there … About 5–7 weeks." plus chips: what limits
/// it (speed / distance), the projected date, how it fits a set date, and
/// the checkpoints. Every number is the server's (code, never a model).
struct RunPlanGoalEstimateLine: View {
    let estimate: RunPlanV2GoalEstimate?
    var estimating = false

    var body: some View {
        if let e = estimate {
            VStack(alignment: .leading, spacing: 6) {
                if let text = e.text, !text.isEmpty {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .madFont(size: 13, weight: .bold, maxScale: 1.15)
                            .foregroundStyle(RPV2Colors.green)
                            .padding(.top, 1)
                            .accessibilityHidden(true)
                        Text(text)
                            .madFont(size: 12, design: .rounded)
                            .foregroundStyle(.white.opacity(0.72))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                RunPlanFlowLayout(spacing: 5) {
                    ForEach(Array(chips(e).enumerated()), id: \.offset) { _, c in
                        RPV2Chip(icon: c.icon, label: c.label, color: c.tint)
                    }
                }
                // The server's `text` already names the checkpoints and how the
                // date fits; spell them out only without it.
                if !hasText(e), let cp = RPV2Format.checkpointsLine(e) {
                    Text(cp)
                        .madFont(size: 11, weight: .heavy, design: .rounded)
                        .foregroundStyle(.white.opacity(0.5))
                        .madBodyLines(2)
                }
            }
        } else if estimating {
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini).tint(.white.opacity(0.6))
                Text(String(localized: "Estimating from your runs…"))
                    .madFont(size: 11, weight: .bold, design: .rounded)
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
    }

    private func hasText(_ e: RunPlanV2GoalEstimate) -> Bool { !(e.text ?? "").isEmpty }

    private func chips(_ e: RunPlanV2GoalEstimate) -> [(icon: String, label: String, tint: Color)] {
        var out: [(icon: String, label: String, tint: Color)] = []
        if let c = RPV2Format.estimateChip(e) {
            out.append((e.isAchieved ? "checkmark.circle.fill" : "calendar", c.text, c.tint))
        }
        if !e.isAchieved, let l = e.limiterKind {
            out.append((l == .speed ? "bolt.fill" : "figure.run", RPV2Format.limiterLabel(l), .white.opacity(0.75)))
        }
        if !hasText(e), let f = e.feasibilityKind, f != .achieved {
            let tint: Color = f == .onTrack ? RPV2Colors.green : (f == .stretch ? RPV2Colors.gold : RPV2Colors.orange)
            out.append(("flag.fill", RPV2Format.feasibilityLabel(f), tint))
        }
        return out
    }
}

// MARK: - Plan home header (mockup screens 4 and 12)

/// Both goals with their estimate chips: the primary large with its
/// projected date, the secondary smaller with its date and next checkpoint.
struct RunPlanGoalsHeader: View {
    let plan: RunPlanV2Plan

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let p = plan.primaryGoal {
                primaryRow(p)
            } else {
                Text(RPV2Format.goalsLine(plan.goals))
                    .madFont(size: 21, weight: .black, design: .rounded, maxScale: 1.5)
            }
            if let s = plan.secondaryGoal { secondaryRow(s) }
        }
        .foregroundStyle(.white)
    }

    private func primaryRow(_ g: RunPlanV2Goal) -> some View {
        let title = Text(RPV2Format.goalTitle(g))
            .madFont(size: 21, weight: .black, design: .rounded, maxScale: 1.5)
            .fixedSize(horizontal: false, vertical: true)
        return ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                title.lineLimit(1)
                chip(g.estimate, prominent: true)
            }
            VStack(alignment: .leading, spacing: 4) {
                title
                chip(g.estimate, prominent: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibility(g, primary: true))
    }

    private func secondaryRow(_ g: RunPlanV2Goal) -> some View {
        let label = Text(String(localized: "Secondary").uppercased())
            .madFont(size: 10, weight: .black, design: .rounded)
            .tracking(0.8)
            .foregroundStyle(.white.opacity(0.4))
            .lineLimit(1)
            .fixedSize()
        let name = Text(RPV2Format.goalTitle(g))
            .madFont(size: 13, weight: .heavy, design: .rounded)
            .foregroundStyle(.white.opacity(0.75))
        return ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                label
                name.lineLimit(1)
                chip(g.estimate, prominent: false)
                nextCheckpoint(g.estimate)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) { label; name.lineLimit(2) }
                HStack(spacing: 6) { chip(g.estimate, prominent: false); nextCheckpoint(g.estimate) }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibility(g, primary: false))
    }

    @ViewBuilder
    private func chip(_ e: RunPlanV2GoalEstimate?, prominent: Bool) -> some View {
        if let e, let c = RPV2Format.estimateChip(e) {
            Text(c.text)
                .madFont(size: prominent ? 12 : 11, weight: .black, design: .rounded)
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(prominent ? c.tint : .white.opacity(0.6))
                .padding(.horizontal, prominent ? 8 : 7)
                .padding(.vertical, prominent ? 2 : 1)
                .background(Capsule().fill(prominent ? c.tint.opacity(0.14) : Color.white.opacity(0.07)))
        }
    }

    @ViewBuilder
    private func nextCheckpoint(_ e: RunPlanV2GoalEstimate?) -> some View {
        if let e, !e.isAchieved, let label = e.nextCheckpoint?.label, !label.isEmpty {
            Text(String(localized: "· next: \(label)"))
                .madFont(size: 12, weight: .bold, design: .rounded)
                .foregroundStyle(.white.opacity(0.4))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    private func accessibility(_ g: RunPlanV2Goal, primary: Bool) -> String {
        var parts = [primary ? String(localized: "Primary goal") : String(localized: "Secondary goal"), RPV2Format.goalTitle(g)]
        if let e = g.estimate {
            if e.isAchieved {
                parts.append(String(localized: "reached"))
            } else if let d = e.projected_date {
                parts.append(String(localized: "estimated \(RPV2Format.projected(d))"))
            }
            if !e.isAchieved, let cp = e.nextCheckpoint?.label { parts.append(String(localized: "next checkpoint \(cp)")) }
        }
        return parts.joined(separator: ", ")
    }
}
