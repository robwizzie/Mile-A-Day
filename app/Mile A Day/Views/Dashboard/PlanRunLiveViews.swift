import SwiftUI

// Run Plans v2 at run time, on the tracker: the start wizard's "Run plan"
// option, the live plan card, and the recap's grade row. All three live here,
// not in WorkoutTrackingView, whose body is at the type checker's limit; the
// tracker only places them. The pre-run check-in (`RunPlanPreRunView`) and
// the post-run grade screen (`RunPlanPostRunView`) are the plan screens'
// (Views/RunPlansV2/); these views only present them.

/// Accents for the plan card, readable on the tracker's red gradient.
enum PlanRunPalette {
    static let gold = Color(red: 1.0, green: 0.82, blue: 0.36)
    static let green = Color(red: 0.42, green: 0.92, blue: 0.55)
    static let blue = Color(red: 0.5, green: 0.78, blue: 1.0)
    static let orange = Color(red: 1.0, green: 0.62, blue: 0.3)
    static let panel = Color.black.opacity(0.3)

    static func tint(_ segment: PlanRunSegment, finished: Bool) -> Color {
        if finished { return green }
        switch segment.kind {
        case "work": return gold
        case "recover", "walk": return green
        case "warmup", "cooldown": return blue
        default: return segment.quotedPace == nil ? green : orange
        }
    }
}

// MARK: - Start wizard: Run plan

/// The mode step's "Run plan" option (Mile A Day+, a plan, a run planned
/// today). Opens the pre-run check-in; its Start arms the coach and goes.
/// A plan already armed from the plan screen ("Start today's run") skips the
/// check-in. Renders nothing when there's no plan run to offer.
struct PlanRunModeOption: View {
    let isRunning: Bool
    /// Arms nothing itself: the coach is armed when this fires.
    let onStart: () -> Void

    @ObservedObject private var store = RunPlanV2Store.shared
    @State private var showPreRun = false

    /// Today's plan day, when it can be run now. The server's `today` only
    /// counts when it IS today (a cached read after midnight is yesterday's).
    private var day: RunPlanV2Day? {
        guard isRunning, store.isPlus, let today = store.today,
              today.local_date == RunPlanV2Date.todayKey(), today.offersPlanRun else { return nil }
        return today
    }

    /// Kicks the plan read from the always-present Just Track It card: this
    /// one renders nothing (no lifecycle) until a plan is cached. Plus only,
    /// so a free account doesn't earn a 403 on every wizard.
    @MainActor
    static func refreshIfPlus() async {
        guard PlusStore.shared.isPlus else { return }
        await RunPlanV2Store.shared.refreshIfStale()
    }

    var body: some View {
        if let day {
            WizardOptionCard(
                leading: { WizardOptionGlyph(icon: "calendar", width: 46) },
                title: "Run plan",
                subtitle: subtitle(day),
                badge: "PLUS",
                accessory: { WizardOptionChevron() }
            ) {
                MADHaptics.tap()
                if PlanRunCoachV2.shared.armedDay?.date == day.local_date {
                    onStart()
                } else {
                    showPreRun = true
                }
            }
            .sheet(isPresented: $showPreRun) {
                NavigationStack {
                    // Its Start fires after the check-in's proposal was
                    // applied or kept, so the store's `today` is the final day.
                    RunPlanPreRunView(onStart: startFromPreRun)
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                Button("Cancel") { showPreRun = false }
                            }
                        }
                }
                .madTypeCap(.madCardCap)
            }
        }
    }

    private func startFromPreRun() {
        guard let today = store.today, today.local_date == RunPlanV2Date.todayKey(),
              PlanRunCoachV2.shared.arm(day: today) else {
            showPreRun = false
            return
        }
        showPreRun = false
        // After the sheet is gone, so the wizard's slide is seen.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { onStart() }
    }

    private func subtitle(_ day: RunPlanV2Day) -> String {
        let title = day.title ?? "Today's run"
        if let shoe = day.shoe?.name, !shoe.isEmpty { return "\(title) · \(shoe)" }
        return title
    }
}

// MARK: - Live: the plan card

/// The tracking screen's plan card (mockup screens 8–9): segment, countdown,
/// progress, rep dots, pace vs target, belt speed on a treadmill, heart rate
/// (or "No heart rate" and how it should feel), what's next. Renders nothing
/// unless a plan run is live.
struct PlanRunLiveCard: View {
    private let coach = PlanRunCoachV2.shared
    @AppStorage(PlanRunCoachV2.fewerCuesKey) private var fewerCues = false

    var body: some View {
        if let status = coach.status {
            VStack(alignment: .leading, spacing: 8) {
                topRow
                segmentPanel(status)
                tiles(status)
                if coach.heartRate == nil, !status.finished, !status.segment.isWork {
                    feelCard(status.segment)
                }
                if !coach.lineWasSpoken, let line = coach.line {
                    unspokenLine(line)
                }
                if coach.onTreadmill {
                    Label("You set the belt. The app reads it and never changes it.", systemImage: "info.circle")
                        .madFont(size: 11, weight: .medium, design: .rounded, maxScale: 1.4)
                        .foregroundColor(.white.opacity(0.55))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    // MARK: Top row

    private var topRow: some View {
        HStack(spacing: 8) {
            Text(coach.day?.title.uppercased() ?? "RUN PLAN")
                .madFont(size: 11, weight: .black, design: .rounded, maxScale: 1.3)
                .tracking(1)
                .foregroundColor(.white.opacity(0.75))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 6)
            Button {
                MADHaptics.tap()
                fewerCues.toggle()
                PlanRunCoachV2.setFewerCues(fewerCues)
            } label: {
                Label("Fewer cues", systemImage: "slider.horizontal.3")
                    .madFont(size: 11, weight: .heavy, design: .rounded, maxScale: 1.3)
                    .foregroundColor(fewerCues ? .black : .white.opacity(0.8))
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 10)
                    .frame(minHeight: 30)
                    .background(Capsule().fill(fewerCues ? PlanRunPalette.gold : Color.white.opacity(0.14)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(fewerCues ? "Fewer cues, on" : "Fewer cues, off")
        }
    }

    // MARK: Segment

    private func segmentPanel(_ status: PlanRunStatus) -> some View {
        let tint = PlanRunPalette.tint(status.segment, finished: status.finished)
        let big = bigNumber(status)
        return VStack(alignment: .leading, spacing: 6) {
            Text(header(status))
                .madFont(size: 11, weight: .black, design: .rounded, maxScale: 1.3)
                .tracking(1)
                .foregroundColor(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                // Live number: fixed size, like the tracker's own time/distance.
                Text(big.value)
                    .font(.system(size: 46, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Spacer(minLength: 6)
                Text(big.caption)
                    .madFont(size: 13, weight: .heavy, design: .rounded, maxScale: 1.3)
                    .foregroundColor(.white.opacity(0.8))
                    .multilineTextAlignment(.trailing)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            if let next = coach.countingDownTo {
                countdownChips(status, next: next)
            }
            if status.workCount > 1 {
                repDots(status, tint: tint)
            } else {
                progressBar(status.progress, tint: tint)
            }
            if let target = targetLine(status) {
                Text(target)
                    .madFont(size: 12, weight: .heavy, design: .rounded, maxScale: 1.4)
                    .foregroundColor(.white.opacity(0.8))
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(PlanRunPalette.panel))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2).fill(tint).frame(width: 4).padding(.vertical, 18)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(header(status).capitalized), \(big.value) \(big.caption)")
    }

    private func countdownChips(_ status: PlanRunStatus, next: PlanRunSegment) -> some View {
        let left = secondsToChange(status)
        let lit: Int? = left.map { Int($0.rounded(.up)) }
        return HStack(spacing: 6) {
            ForEach(["3", "2", "1", next.isWork ? "Go" : "Ease"], id: \.self) { label in
                let on = (Int(label) != nil && Int(label) == lit) || (Int(label) == nil && (lit ?? 9) <= 0)
                Text(label)
                    .madFont(size: 12, weight: .black, design: .rounded, maxScale: 1.3)
                    .foregroundColor(on ? .black : .white.opacity(0.65))
                    .padding(.horizontal, 8)
                    .frame(minWidth: 28, minHeight: 26)
                    .background(Capsule().fill(on ? PlanRunPalette.orange : Color.white.opacity(0.12)))
            }
        }
        .accessibilityHidden(true)
    }

    private func progressBar(_ progress: Double, tint: Color) -> some View {
        Capsule()
            .fill(Color.white.opacity(0.2))
            .frame(height: 6)
            .overlay(alignment: .leading) {
                GeometryReader { geo in
                    Capsule()
                        .fill(tint)
                        .frame(width: geo.size.width * CGFloat(min(max(progress, 0), 1)))
                }
            }
            .clipShape(Capsule())
            .animation(.linear(duration: 0.9), value: progress)
    }

    private func repDots(_ status: PlanRunStatus, tint: Color) -> some View {
        HStack(spacing: 4) {
            ForEach(1...status.workCount, id: \.self) { n in
                Capsule()
                    .fill(n <= status.workDone ? tint
                          : (status.segment.isWork && !status.finished && n == status.workNumber)
                          ? tint.opacity(0.55) : Color.white.opacity(0.2))
                    .frame(height: 5)
            }
        }
    }

    // MARK: Tiles

    private func tiles(_ status: PlanRunStatus) -> some View {
        let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]
        return LazyVGrid(columns: columns, spacing: 8) {
            if coach.onTreadmill { beltTile(status) }
            paceTile(status)
            heartTile(status)
            nextTile(status)
        }
    }

    private func beltTile(_ status: PlanRunStatus) -> some View {
        let target = PlanRunLines.speed(of: coach.countingDownTo ?? status.segment)
        let note = target.map { "Set \(PlanRunLines.speedNumber($0))" + (coach.countingDownTo != nil ? " at go" : "") }
            ?? "From the treadmill"
        return tile(title: "BELT SPEED",
                    value: coach.beltMph.map(PlanRunLines.speedNumber) ?? "--",
                    unit: PlanRunLines.speedUnit,
                    note: note, noteColor: PlanRunPalette.green)
    }

    private func paceTile(_ status: PlanRunStatus) -> some View {
        let unit = DistanceUnits.current.paceSuffix
        let value = coach.pace.map(PlanRunLines.paceClock) ?? "--:--"
        let note = paceNote(status)
        return tile(title: "PACE", value: value, unit: unit, note: note.text, noteColor: note.color)
    }

    @ViewBuilder
    private func heartTile(_ status: PlanRunStatus) -> some View {
        if let bpm = coach.heartRate {
            let ceiling = status.segment.hrHigh
            let over = ceiling.map { bpm > $0 + 3 } ?? false
            tile(title: "HEART RATE", value: "\(Int(bpm.rounded()))", unit: "bpm",
                 note: ceiling.map { over ? "Over \(Int($0))" : "Under \(Int($0))" } ?? "Apple Watch",
                 noteColor: over ? PlanRunPalette.orange : PlanRunPalette.green)
        } else {
            VStack(alignment: .leading, spacing: 3) {
                Label("HEART RATE", systemImage: "heart.slash")
                    .madFont(size: 10, weight: .black, design: .rounded, maxScale: 1.3)
                    .tracking(1)
                    .foregroundColor(.white.opacity(0.5))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text("No heart rate")
                    .madFont(size: 13, weight: .black, design: .rounded, maxScale: 1.4)
                    .foregroundColor(.white.opacity(0.85))
                Text("Cues use pace and feel.")
                    .madFont(size: 11, weight: .medium, design: .rounded, maxScale: 1.4)
                    .foregroundColor(.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 84, alignment: .topLeading)
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.22), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            )
            .accessibilityElement(children: .combine)
        }
    }

    private func nextTile(_ status: PlanRunStatus) -> some View {
        let next = nextText(status)
        return tile(title: "NEXT", value: next.value, unit: next.unit, note: next.note, noteColor: .white.opacity(0.55))
    }

    private func tile(title: String, value: String, unit: String, note: String, noteColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .madFont(size: 10, weight: .black, design: .rounded, maxScale: 1.3)
                .tracking(1)
                .foregroundColor(.white.opacity(0.5))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 26, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                if !unit.isEmpty {
                    Text(unit)
                        .madFont(size: 12, weight: .heavy, design: .rounded, maxScale: 1.3)
                        .foregroundColor(.white.opacity(0.55))
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            Text(note)
                .madFont(size: 11, weight: .heavy, design: .rounded, maxScale: 1.4)
                .foregroundColor(noteColor)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 84, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(PlanRunPalette.panel))
        .accessibilityElement(children: .combine)
    }

    private func feelCard(_ segment: PlanRunSegment) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("HOW IT SHOULD FEEL")
                .madFont(size: 10, weight: .black, design: .rounded, maxScale: 1.3)
                .tracking(1)
                .foregroundColor(.white.opacity(0.5))
            Text(segment.feel ?? PlanRunLines.defaultFeel(segment, day: coach.day))
                .madFont(size: 13, weight: .medium, design: .rounded)
                .foregroundColor(.white.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(PlanRunPalette.panel))
        .accessibilityElement(children: .combine)
    }

    /// Voice muted or coach mode off: the tracker's echo only shows what was
    /// SPOKEN, so the plan's line is shown here instead.
    private func unspokenLine(_ line: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "text.bubble.fill")
                .madFont(size: 13, weight: .bold, maxScale: 1.3)
                .foregroundColor(PlanRunPalette.gold)
                .accessibilityHidden(true)
            Text(line)
                .madFont(size: 13, weight: .semibold, design: .rounded)
                .foregroundColor(.white.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
                .id(line)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.1)))
    }

    // MARK: Values

    private struct Big {
        let value: String
        let caption: String
    }

    private func secondsToChange(_ status: PlanRunStatus) -> Double? {
        if let seconds = status.remainingSeconds { return seconds }
        if let miles = status.remainingMiles, let pace = coach.pace ?? status.segment.quotedPace {
            return miles * pace
        }
        return nil
    }

    private func bigNumber(_ status: PlanRunStatus) -> Big {
        if status.finished { return Big(value: "Done", caption: "nice work") }
        if coach.countingDownTo != nil, let left = secondsToChange(status) {
            return Big(value: PlanRunFormat.clock(left), caption: "until it starts")
        }
        if let seconds = status.remainingSeconds {
            return Big(value: PlanRunFormat.clock(seconds), caption: "left")
        }
        if let miles = status.remainingMiles {
            if (status.segment.distanceMiles ?? 0) < 0.95 {
                let meters = Int((miles * 1609.344 / 10).rounded()) * 10
                return Big(value: "\(meters)", caption: "m left")
            }
            let total = (status.segment.distanceMiles ?? 0)
            let done = max(0, total - miles)
            return Big(value: done.distanceText, caption: "of \(total.distanceFormatted)")
        }
        return Big(value: PlanRunFormat.clock(status.segmentSeconds), caption: "so far")
    }

    /// "INTERVAL 3 OF 5 · 400M", "RECOVER · JOG", "EASY RUN · 4 MI".
    private func header(_ status: PlanRunStatus) -> String {
        if status.finished { return "PLAN DONE" }
        let segment = status.segment
        let length = PlanRunLines.short(segment).uppercased()
        let suffix = length.isEmpty ? "" : " · \(length)"
        switch segment.kind {
        case "warmup": return "WARM UP\(suffix)"
        case "recover": return "RECOVER · JOG\(suffix)"
        case "cooldown": return "COOL DOWN\(suffix)"
        case "walk": return "WALK\(suffix)"
        case "work":
            if status.workCount > 1, let n = status.workNumber { return "INTERVAL \(n) OF \(status.workCount)\(suffix)" }
            return "MAIN SET\(suffix)"
        default:
            return segment.quotedPace == nil || coach.day?.isEasyDay == true ? "EASY RUN\(suffix)" : "STEADY\(suffix)"
        }
    }

    /// "Target 9.0 mph · 1:40 for the rep", "Range 11:30–12:15".
    private func targetLine(_ status: PlanRunStatus) -> String? {
        guard !status.finished else { return nil }
        let segment = coach.countingDownTo ?? status.segment
        var parts: [String] = []
        if coach.onTreadmill, let mph = PlanRunLines.speed(of: segment) {
            parts.append("Target \(PlanRunLines.speedText(mph))")
        } else if let low = segment.paceLow, let high = segment.paceHigh, high > low {
            parts.append("Range \(PlanRunLines.paceClock(low))–\(PlanRunLines.paceClock(high))")
        } else if let pace = segment.quotedPace {
            parts.append("Target \(PlanRunLines.paceClock(pace))\(DistanceUnits.current.paceSuffix)")
        }
        if segment.isWork, let mi = segment.distanceMiles, mi < 0.95, let pace = segment.quotedPace {
            parts.append("\(PlanRunFormat.clock(mi * pace)) for the rep")
        }
        if parts.isEmpty, coach.heartRate == nil, !segment.isWork {
            return "Conversational effort"
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private struct Note {
        let text: String
        let color: Color
    }

    private func paceNote(_ status: PlanRunStatus) -> Note {
        let segment = status.segment
        guard let target = segment.quotedPace else {
            return Note(text: segment.isRecover ? "Recovering" : "Easy effort", color: .white.opacity(0.55))
        }
        let goal = PlanRunLines.paceClock(target)
        guard let call = PlanRunPaceCall.judge(pace: coach.pace, segment: segment) else {
            return Note(text: "Target \(goal)", color: .white.opacity(0.55))
        }
        let short: (Double) -> String = { "\(max(1, Int($0.pacePerDisplayUnit.rounded())))s" }
        switch call {
        case .onTarget: return Note(text: "On pace · \(goal)", color: PlanRunPalette.green)
        case .fast(let drift): return Note(text: "\(short(drift)) fast vs \(goal)", color: PlanRunPalette.gold)
        case .slow(let drift): return Note(text: "\(short(drift)) slow vs \(goal)", color: PlanRunPalette.orange)
        }
    }

    private func nextText(_ status: PlanRunStatus) -> (value: String, unit: String, note: String) {
        guard let next = status.next else {
            return status.finished ? ("Done", "", "Keep going or end") : ("Finish", "", "Last block")
        }
        let length = PlanRunLines.short(next)
        let note: String
        switch next.kind {
        case "work":
            let name = status.workCount > 1 ? "Interval \(status.upcomingWorkNumber)" : "Main set"
            if coach.onTreadmill, let mph = PlanRunLines.speed(of: next) {
                note = "\(name) · belt to \(PlanRunLines.speedNumber(mph))"
            } else if let pace = next.quotedPace {
                note = "\(name) · \(PlanRunLines.paceClock(pace)) pace"
            } else {
                note = name
            }
        case "recover":
            if coach.onTreadmill, let mph = PlanRunLines.speed(of: next) {
                note = "Belt back to \(PlanRunLines.speedNumber(mph))"
            } else {
                note = "Jog"
            }
        case "cooldown": note = "Cool down"
        case "warmup": note = "Warm up"
        case "walk": note = "Walk"
        default: note = next.quotedPace == nil ? "Easy running" : "Steady"
        }
        return (length.isEmpty ? "--" : length, "", note)
    }
}

// MARK: - Recap: the plan grade

/// On the recap of a plan run: "Grading your plan run" until the workout
/// syncs and the phone's segment stats are uploaded, then the grade, which
/// opens `RunPlanPostRunView` (opened once on its own when the grade lands
/// while the recap is up). Renders nothing for any other workout.
struct PlanRunRecapCard: View {
    let workoutId: String

    private let coach = PlanRunCoachV2.shared
    @State private var showPostRun = false
    @State private var autoOpened = false

    private var run: PlanRunCoachV2.FinishedRun? {
        guard let run = coach.finishedRun, run.workoutId == workoutId else { return nil }
        return run
    }

    var body: some View {
        if let run {
            Button {
                MADHaptics.tap()
                showPostRun = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "calendar.badge.checkmark")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(PlanRunPalette.gold)
                        .frame(width: 34)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("RUN PLAN")
                            .madFont(size: 10, weight: .heavy, design: .rounded, maxScale: 1.3)
                            .tracking(0.8)
                            .foregroundColor(.white.opacity(0.6))
                        Text(headline(run))
                            .madFont(size: 15, weight: .semibold, design: .rounded)
                            .foregroundColor(.white)
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                    }
                    Spacer(minLength: 8)
                    if run.state == .waiting {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white.opacity(0.7))
                            .accessibilityHidden(true)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.12)))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onChange(of: run.state) { _, state in
                if case .graded = state, !autoOpened {
                    autoOpened = true
                    showPostRun = true
                }
            }
            .sheet(isPresented: $showPostRun) {
                // It polls for the grade itself, so it opens fine while
                // the upload is still on its way.
                NavigationStack {
                    RunPlanPostRunView(workoutId: workoutId, onDone: { showPostRun = false })
                }
                .madTypeCap(.madCardCap)
            }
        }
    }

    private func headline(_ run: PlanRunCoachV2.FinishedRun) -> String {
        switch run.state {
        case .waiting: return "Grading \(run.title)…"
        case .graded(let score):
            if let score { return "Plan grade \(score) of 100 · See how you did" }
            return "See how you did"
        case .serverGrades: return "Your grade shows once this run syncs"
        }
    }
}
