import SwiftUI

// Run Plans at run time: the "Today's plan" option on the tracker's mode step
// and the live interval card on the tracking screen. Both live here, not in
// WorkoutTrackingView, whose body is already at the type checker's limit.

// MARK: - Pre-run: Today's plan

/// The mode step's "Today's plan" option (Mile A Day+ with a plan). Shows the
/// session the engine planned, lets the runner adjust it (chips → the engine)
/// or talk it over with Flamey, and starts the run in plan mode.
/// Renders nothing when there's no plan run to offer.
struct RunPlanPreRunCard: View {
    let onStart: (RunPlanDay) -> Void

    @ObservedObject private var store = RunPlanStore.shared
    @ObservedObject private var plus = PlusStore.shared
    @State private var busy: RunPlanAction?
    @State private var errorText: String?
    @State private var showFlamey = false
    @State private var canTalk = FlameyCoach.isAvailable
    /// Adjusted here: keep showing the day even when "Just my mile" turned
    /// it into the streak mile, so the card doesn't vanish under the tap.
    @State private var adjustedDate: String?

    private var day: RunPlanDay? {
        guard plus.isPlus, !store.plusRequired, let today = store.today, !today.liveSegments.isEmpty else { return nil }
        guard today.offersPlanRun || today.local_date == adjustedDate else { return nil }
        return today
    }

    var body: some View {
        if let day {
            card(day)
                .task { await store.refreshIfStale() }
                .sheet(isPresented: $showFlamey) { flameySheet }
        }
    }

    private func card(_ day: RunPlanDay) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Text(RunPlanFormat.title(day))
                .madFont(size: 24, weight: .black, design: .rounded)
                .foregroundColor(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
            rows(day)
            chips(day)
            if let errorText {
                Text(errorText)
                    .madFont(size: 12, weight: .semibold, design: .rounded)
                    .foregroundColor(Color(red: 1.0, green: 0.85, blue: 0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if canTalk { talkButton }
            RunPlanPrimaryButton(title: "Start plan run", enabled: busy == nil) {
                onStart(day)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.black.opacity(0.28)))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(RunPlanColors.gold.opacity(0.85), lineWidth: 2))
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "calendar")
                .madFont(size: 13, weight: .black, maxScale: 1.3)
                .accessibilityHidden(true)
            Text("TODAY'S PLAN")
                .madFont(size: 11, weight: .black, design: .rounded, maxScale: 1.3)
                .tracking(1)
                .lineLimit(1)
            Spacer(minLength: 4)
            RunPlanPlusChip()
        }
        .foregroundColor(RunPlanColors.gold)
    }

    private func rows(_ day: RunPlanDay) -> some View {
        VStack(spacing: 4) {
            ForEach(RunPlanSessionRow.rows(for: day)) { row in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(row.label)
                        .foregroundColor(.white.opacity(0.7))
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    Text(row.value)
                        .foregroundColor(.white)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.trailing)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                }
                .madFont(size: 13, weight: .medium, design: .rounded)
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func chips(_ day: RunPlanDay) -> some View {
        FlowLayout(spacing: 6) {
            ForEach(RunPlanAction.dayAdjustments, id: \.self) { action in
                Button {
                    adjust(day, action)
                } label: {
                    ZStack {
                        Text(Self.chipTitle(action)).opacity(busy == action ? 0 : 1)
                        if busy == action { ProgressView().tint(.white).scaleEffect(0.7) }
                    }
                    .madFont(size: 12, weight: .heavy, design: .rounded, maxScale: 1.4)
                    .foregroundColor(.white.opacity(0.9))
                    .padding(.horizontal, 12)
                    .frame(minHeight: 32)
                    .background(Capsule().fill(Color.white.opacity(0.14)))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(busy != nil)
            }
        }
    }

    private var talkButton: some View {
        Button {
            MADHaptics.tap()
            showFlamey = true
        } label: {
            HStack(spacing: 8) {
                RunPlanCoachAvatar(size: 22)
                Text("Talk it over with Flamey…")
                    .madFont(size: 14, weight: .semibold, design: .rounded)
                    .foregroundColor(.white.opacity(0.75))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white.opacity(0.10)))
        }
        .buttonStyle(.plain)
    }

    /// The plan screen itself (chips, Flamey chat, proposal cards) in a
    /// sheet; whatever it changes lands in the store this card reads.
    private var flameySheet: some View {
        NavigationStack {
            RunPlanScreen()
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Done") { showFlamey = false }
                            .foregroundColor(.white)
                    }
                }
        }
        .madTypeCap(.madCardCap)
    }

    private func adjust(_ day: RunPlanDay, _ action: RunPlanAction) {
        guard busy == nil else { return }
        MADHaptics.tap()
        busy = action
        errorText = nil
        Task {
            do {
                try await store.adjust(date: day.local_date, action: action)
                adjustedDate = day.local_date
                MADHaptics.success()
            } catch {
                errorText = RunPlanError.from(error).message
            }
            busy = nil
        }
    }

    static func chipTitle(_ action: RunPlanAction) -> String {
        switch action {
        case .easier: return "Make it easier"
        case .shorter: return "Shorter today"
        case .justMile: return "Just my mile"
        default: return action.rawValue
        }
    }
}

/// One line of the pre-run summary ("Warm up · 0.5 mi easy").
struct RunPlanSessionRow: Identifiable {
    let id: Int
    let label: String
    let value: String

    static func rows(for day: RunPlanDay) -> [RunPlanSessionRow] {
        let segments = day.liveSegments
        var out: [(String, String)] = []
        if let warmup = segments.first(where: \.isWarmup) {
            out.append(("Warm up", "\(amount(warmup)) easy"))
        }
        if let steady = segments.first(where: { $0.kind == "steady" }) {
            out.append(("Run", "\(amount(steady)) · \(steady.targetPace.map(RunPlanFormat.pace) ?? "any pace")"))
        }
        let work = segments.filter(\.isWork)
        if let first = work.first {
            let label = work.count > 1 ? "\(work.count) × \(RunPlanCue.short(first))" : "Main set \(amount(first))"
            out.append((label, workValue(first)))
            if work.count > 1, let recover = segments.first(where: \.isRecover) {
                out.append(("Between", "\(RunPlanCue.short(recover)) jog"))
            }
        }
        if let cooldown = segments.first(where: \.isCooldown) {
            out.append(("Cool down", "\(amount(cooldown)) easy"))
        }
        return out.enumerated().map { RunPlanSessionRow(id: $0.offset, label: $0.element.0, value: $0.element.1) }
    }

    /// "0.5 mi", "400m", "5:00".
    private static func amount(_ segment: RunPlanLiveSegment) -> String {
        if segment.isDistanceBased, let mi = segment.distanceMiles {
            return mi < 0.45 ? RunPlanFormat.repLength(mi) : RunPlanFormat.distance(mi)
        }
        return RunPlanCue.short(segment)
    }

    /// "1:40 each (6:40/mi)" for a sub-mile rep, else the pace.
    private static func workValue(_ segment: RunPlanLiveSegment) -> String {
        guard let pace = segment.targetPace else { return "strong" }
        if let mi = segment.distanceMiles, mi > 0, mi < 0.95 {
            return "\(RunPlanFormat.clock(pace * mi)) each (\(RunPlanFormat.pace(pace)))"
        }
        return RunPlanFormat.pace(pace)
    }
}

// MARK: - Live: the interval card

/// The tracking screen's plan card: segment, countdown, progress, rep dots,
/// pace vs target, what's next. Renders nothing unless a plan run is live.
/// No heart rate on the phone: the iPhone tracker has no HR source.
struct RunPlanLiveCard: View {
    private let coach = PlanRunCoach.shared
    /// The voice's mute switch. When muted, the card carries the plan's last
    /// line itself (the tracker's echo only shows what was spoken).
    @AppStorage(GhostCoach.enabledKey) private var coachEnabled = true

    var body: some View {
        if let status = coach.status {
            VStack(alignment: .leading, spacing: 8) {
                segmentPanel(status)
                HStack(spacing: 8) {
                    paceTile(status)
                    nextTile(status)
                }
                if !coachEnabled, let line = coach.line {
                    RunPlanFlameyNote(text: line)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    // MARK: Segment

    private func segmentPanel(_ status: RunPlanLiveStatus) -> some View {
        let tint = Self.tint(status)
        let big = Self.bigNumber(status)
        return VStack(alignment: .leading, spacing: 6) {
            Text(RunPlanCue.header(status))
                .madFont(size: 11, weight: .black, design: .rounded, maxScale: 1.3)
                .tracking(1)
                .foregroundColor(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                // Live number: fixed size, like the tracker's own time/distance.
                Text(big.value)
                    .font(.system(size: 48, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Spacer(minLength: 6)
                Text(big.caption)
                    .madFont(size: 13, weight: .heavy, design: .rounded, maxScale: 1.3)
                    .foregroundColor(.white.opacity(0.75))
                    .lineLimit(1)
            }
            progressBar(status.progress, tint: tint)
            if status.workCount > 1 {
                repDots(status)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.black.opacity(0.3)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(RunPlanCue.header(status).capitalized), \(big.value) \(big.caption)")
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

    private func repDots(_ status: RunPlanLiveStatus) -> some View {
        HStack(spacing: 4) {
            ForEach(1...status.workCount, id: \.self) { n in
                Capsule()
                    .fill(Color.white.opacity(Self.dotOpacity(n, status: status)))
                    .frame(height: 5)
            }
        }
    }

    private static func dotOpacity(_ n: Int, status: RunPlanLiveStatus) -> Double {
        if n <= status.workDone { return 1 }
        if status.segment.isWork, !status.finished, n == status.workNumber { return 0.6 }
        return 0.2
    }

    // MARK: Tiles

    private func paceTile(_ status: RunPlanLiveStatus) -> some View {
        let note = Self.paceNote(status, recent: coach.recentPace)
        return tile(title: "PACE") {
            Text(coach.recentPace.map(RunPlanCue.paceClock) ?? "--:--")
                .font(.system(size: 26, weight: .black, design: .rounded))
                .monospacedDigit()
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(note.text)
                .madFont(size: 11.5, weight: .heavy, design: .rounded, maxScale: 1.3)
                .foregroundColor(note.color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    private func nextTile(_ status: RunPlanLiveStatus) -> some View {
        tile(title: "NEXT") {
            Text(RunPlanCue.next(status))
                .madFont(size: 15, weight: .black, design: .rounded, maxScale: 1.3)
                .foregroundColor(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func tile<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .madFont(size: 10, weight: .black, design: .rounded, maxScale: 1.3)
                .tracking(1)
                .foregroundColor(.white.opacity(0.5))
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 78, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.black.opacity(0.3)))
        .accessibilityElement(children: .combine)
    }

    // MARK: Values

    private struct Big {
        let value: String
        let caption: String
    }

    /// Time left (duration segments) or distance left (distance segments).
    private static func bigNumber(_ status: RunPlanLiveStatus) -> Big {
        if status.finished { return Big(value: "Done", caption: "nice work") }
        if let seconds = status.remainingSeconds {
            return Big(value: RunPlanFormat.clock(seconds), caption: "left")
        }
        if let miles = status.remainingMiles {
            if (status.segment.distanceMiles ?? 0) < 0.95 {
                let meters = Int((miles * 1609.344 / 10).rounded()) * 10
                return Big(value: "\(meters)", caption: "m left")
            }
            return Big(value: miles.distanceToGoText, caption: "\(RunPlanFormat.unit) left")
        }
        return Big(value: RunPlanFormat.clock(status.segmentSeconds), caption: "so far")
    }

    private struct Note {
        let text: String
        let color: Color
    }

    private static func paceNote(_ status: RunPlanLiveStatus, recent: Double?) -> Note {
        guard let target = status.segment.targetPace else {
            return Note(text: "easy effort", color: .white.opacity(0.55))
        }
        let goal = RunPlanCue.paceClock(target)
        guard let call = RunPlanPaceCall.judge(recent: recent, target: target) else {
            return Note(text: "target \(goal)", color: .white.opacity(0.55))
        }
        switch call {
        case .onPace:
            return Note(text: "on pace · \(goal)", color: RunPlanColors.green)
        case .fast(let drift):
            return Note(text: "\(RunPlanCue.secondsShort(drift)) fast vs \(goal)", color: RunPlanColors.gold)
        case .slow(let drift):
            return Note(text: "\(RunPlanCue.secondsShort(drift)) slow vs \(goal)", color: RunPlanColors.orange)
        }
    }

    private static func tint(_ status: RunPlanLiveStatus) -> Color {
        if status.finished { return RunPlanColors.green }
        switch status.segment.kind {
        case "work": return RunPlanColors.gold
        case "recover": return RunPlanColors.green
        case "warmup", "cooldown": return RunPlanColors.blue
        default: return .white
        }
    }
}
