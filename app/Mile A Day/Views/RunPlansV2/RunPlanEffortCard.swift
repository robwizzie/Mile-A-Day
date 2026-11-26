import SwiftUI

// After the run (mockup screen 10): "How hard was it?". The phone measured
// the run and made a raw guess (`RunEffortEstimator`); the server adds the
// runner's calibration and serves `guess`. Flamey says it in one line, the
// runner answers Right or picks 1–10, and the rating goes to
// `POST /run-plans/effort/:workoutId/rating` (which may create a proposal).

@MainActor
@Observable
final class RunPlanEffortModel {
    let workoutId: String
    private(set) var effort: RunPlanV2Effort?
    private(set) var calibration: [RunPlanV2Calibration] = []
    /// Flamey's own words for the reason (Apple model), when it wrote one.
    private(set) var phrasedReason: String?
    private(set) var confirmation: String?
    private(set) var busyRating: Int?
    private(set) var error: String?
    private(set) var loaded = false
    var adjusting = false

    init(workoutId: String) { self.workoutId = workoutId }

    private var reasonKey: String { "runPlanV2EffortReason|\(workoutId)" }

    /// The served effort, or (no guess on the server yet) the phone's guess
    /// posted now. Walk days have none.
    func load(day: RunPlanV2Day) async {
        guard !loaded, !day.isWalk else { return }
        loaded = true
        do {
            adopt(try await RunPlanV2Service.effort(workoutId: workoutId))
        } catch RunPlanV2Error.notFound(_) {
            await submitGuess(day: day)
        } catch {
            loaded = false
        }
        await phraseIfNeeded(day: day)
    }

    private func submitGuess(day: RunPlanV2Day) async {
        guard let date = day.local_date, Self.withinWeek(date) else { return }
        let profile = RunFitnessAnalyzer.shared.profile
        guard let e = await RunEffortEstimator.estimate(workoutId: workoutId, day: day, profile: profile) else { return }
        let upload = RunPlanV2EffortUpload(today: RunPlanV2Date.todayKey(), local_date: date, workout_id: workoutId,
                                           run_type: e.runType.rawValue, raw_guess: e.rawGuess, features: e.features)
        if let result = try? await RunPlanV2Store.shared.submitEffort(upload) { adopt(result) }
    }

    /// The contract takes efforts for the last 7 days only.
    private static func withinWeek(_ key: String) -> Bool {
        guard let floor = RunPlanV2Date.addingDays(-7, to: RunPlanV2Date.todayKey()) else { return false }
        return key >= floor
    }

    private func adopt(_ r: RunPlanV2EffortResult) {
        effort = r.effort
        if !r.calibration.isEmpty { calibration = r.calibration }
    }

    private func phraseIfNeeded(day: RunPlanV2Day) async {
        guard let effort, effort.guess != nil else { return }
        if let saved = UserDefaults.standard.string(forKey: reasonKey) {
            phrasedReason = saved
            return
        }
        guard RunPlanV2Store.shared.coachTier == .apple else { return }
        guard let text = await AppleCoach.shared.phraseEffortReason(effort, day: day) else { return }
        phrasedReason = text
        UserDefaults.standard.set(text, forKey: reasonKey)
    }

    // MARK: Rating

    func rate(_ value: Int) async {
        guard busyRating == nil else { return }
        busyRating = value
        error = nil
        defer { busyRating = nil }
        do {
            let result = try await RunPlanV2Store.shared.rateEffort(workoutId: workoutId, rating: value)
            if let e = result.effort { effort = e }
            if !result.calibration.isEmpty { calibration = result.calibration }
            adjusting = false
            confirmation = confirmationText(rating: value, proposals: result.proposals)
            MADHaptics.success()
        } catch let e as RunPlanV2Error {
            error = e.message
        } catch {
            self.error = RunPlanV2Error.offline.message
        }
    }

    private func confirmationText(rating: Int, proposals: [RunPlanV2Proposal]) -> String {
        if proposals.contains(where: { $0.proposalKind == .effortFatigue }) {
            return String(localized: "Harder than I guessed, so I suggested a lighter next hard day. You decide.")
        }
        if proposals.contains(where: { $0.proposalKind == .effortProgression }) {
            return String(localized: "Easier than I guessed again, so I suggested slightly faster paces. You decide.")
        }
        let guess = effort?.guess ?? rating
        let type = effort?.effortType ?? .easy
        let settled = calibration.first { $0.effort_type == type.rawValue }?.isApplied ?? false
        if rating == guess { return String(localized: "Got it. That's what I'll expect from runs like this.") }
        let harder = rating > guess
        switch (type, harder, settled) {
        case (.quality, true, true): return String(localized: "Got it. I'll read your interval and tempo days as a bit harder from now on.")
        case (.quality, false, true): return String(localized: "Got it. I'll read your interval and tempo days as a bit easier from now on.")
        case (.long, true, true): return String(localized: "Got it. I'll read your long runs as a bit harder from now on.")
        case (.long, false, true): return String(localized: "Got it. I'll read your long runs as a bit easier from now on.")
        case (.easy, true, true): return String(localized: "Got it. I'll read your easy runs as a bit harder from now on.")
        case (.easy, false, true): return String(localized: "Got it. I'll read your easy runs as a bit easier from now on.")
        case (_, true, false): return String(localized: "Got it, harder than I guessed. A few more answers and my guesses will fit you.")
        case (_, false, false): return String(localized: "Got it, easier than I guessed. A few more answers and my guesses will fit you.")
        }
    }
}

struct RunPlanEffortCard: View {
    @Bindable var model: RunPlanEffortModel

    var body: some View {
        if let effort = model.effort, let guess = effort.guess {
            RPV2Card(radius: 18, padding: 12) {
                header(effort, guess: guess)
                message(effort, guess: guess)
                    .padding(.top, 8)
                RunPlanEffortScale(guess: guess, rating: effort.user_rating, busy: model.busyRating) { n in
                    Task { await model.rate(n) }
                }
                .padding(.top, 12)
                footer(effort, guess: guess)
                    .padding(.top, 10)
            }
        }
    }

    private func header(_ e: RunPlanV2Effort, guess: Int) -> some View {
        HStack(spacing: 8) {
            RPV2Eyebrow(text: String(localized: "How hard was it?"), color: .white.opacity(0.5))
            Spacer(minLength: 6)
            Text(e.user_rating.map { String(localized: "Flamey \(guess) · You \($0)") } ?? String(localized: "Flamey \(guess)"))
                .madFont(size: 11, weight: .heavy, design: .rounded)
                .foregroundStyle(.white.opacity(0.45))
                .lineLimit(1)
                .fixedSize()
        }
    }

    private func message(_ e: RunPlanV2Effort, guess: Int) -> some View {
        HStack(alignment: .top, spacing: 10) {
            FlameyAvatar(size: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(String(localized: "Felt like a \(guess)/10: \(label(e, guess: guess)). Right?"))
                    .madFont(size: 13, weight: .bold, design: .rounded)
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                if let reason = reason(e) {
                    (Text(String(localized: "Why")).foregroundColor(.white.opacity(0.65)).fontWeight(.heavy)
                     + Text(" " + reason).foregroundColor(.white.opacity(0.5)))
                        .madFont(size: 12, design: .rounded)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    private func label(_ e: RunPlanV2Effort, guess: Int) -> String {
        if let l = e.guess_label, !l.isEmpty { return l }
        return RunEffortEstimator.label(guess)
    }

    private func reason(_ e: RunPlanV2Effort) -> String? {
        if let p = model.phrasedReason { return p }
        if let r = e.reason, !r.isEmpty { return r }
        return e.features.map(RunEffortEstimator.reason)
    }

    @ViewBuilder
    private func footer(_ e: RunPlanV2Effort, guess: Int) -> some View {
        if let error = model.error {
            RPV2Notice(icon: "exclamationmark.triangle.fill", text: error, tint: RPV2Colors.orange)
        }
        if e.isRated {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "checkmark").madFont(size: 12, weight: .black, maxScale: 1.15)
                    .foregroundStyle(RPV2Colors.green).padding(.top, 2).accessibilityHidden(true)
                Text(model.confirmation ?? String(localized: "Thanks. Tap another number to change it."))
                    .madFont(size: 12, design: .rounded)
                    .foregroundStyle(.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else if model.adjusting {
            Text(String(localized: "Tap the number that fits how it felt."))
                .madFont(size: 12, weight: .bold, design: .rounded)
                .foregroundStyle(RPV2Colors.orange)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            HStack(spacing: 8) {
                RPV2Button(title: String(localized: "Right"), isBusy: model.busyRating == guess) {
                    Task { await model.rate(guess) }
                }
                RPV2SecondaryButton(title: String(localized: "Adjust")) { model.adjusting = true }
            }
        }
    }
}

/// The 1–10 row: Flamey's guess outlined, the runner's answer filled, the
/// numbers up to it tinted. "Very easy" … "Max" under the ends.
struct RunPlanEffortScale: View {
    let guess: Int
    let rating: Int?
    let busy: Int?
    let onPick: (Int) -> Void

    var body: some View {
        VStack(spacing: 5) {
            HStack(spacing: 3) {
                ForEach(1...10, id: \.self) { n in cell(n) }
            }
            HStack {
                Text(String(localized: "Very easy"))
                Spacer(minLength: 6)
                Text(String(localized: "Max"))
            }
            .madFont(size: 10, weight: .bold, design: .rounded)
            .foregroundStyle(.white.opacity(0.4))
            .accessibilityHidden(true)
        }
    }

    private func cell(_ n: Int) -> some View {
        let picked = rating ?? guess
        let selected = rating == n
        let isGuess = n == guess && !selected
        return Button { MADHaptics.tap(); onPick(n) } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous).fill(fill(n, picked: picked, selected: selected))
                if isGuess {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(RPV2Colors.orange.opacity(0.55), lineWidth: 1.5)
                }
                if busy == n {
                    ProgressView().controlSize(.mini).tint(selected ? .black : .white)
                } else {
                    Text("\(n)")
                        .font(.system(size: 12, weight: .black, design: .rounded))
                        .minimumScaleFactor(0.7)
                        .foregroundStyle(textColor(n, picked: picked, selected: selected, isGuess: isGuess))
                }
            }
            .frame(maxWidth: .infinity, minHeight: 30)
        }
        .buttonStyle(.plain)
        .disabled(busy != nil)
        .accessibilityLabel(String(localized: "\(n) of 10, \(RunEffortEstimator.label(n))"))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityHint(isGuess ? String(localized: "Flamey's guess") : "")
    }

    private func fill(_ n: Int, picked: Int, selected: Bool) -> Color {
        if selected { return RPV2Colors.orange }
        return n <= picked ? RPV2Colors.orange.opacity(0.12) : Color.white.opacity(0.06)
    }

    private func textColor(_ n: Int, picked: Int, selected: Bool, isGuess: Bool) -> Color {
        if selected { return .black }
        if isGuess { return .white }
        return n <= picked ? .white.opacity(0.7) : .white.opacity(0.4)
    }
}
