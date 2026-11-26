import SwiftUI

/// After the run (mockup screen 10): the 0–100 grade ring with completion /
/// on target / consistency bars, distance · time · reps, How hard was it?
/// (`RunPlanEffortCard`), Flamey's summary, and proposals for the coming days.
///
/// Embeddable by the live run coach's finish screen: pass the HealthKit
/// workout UUID string the run synced as. The grade arrives a few seconds
/// after the upload (the server grades asynchronously), so this polls.
struct RunPlanPostRunView: View {
    let workoutId: String
    var onDone: (() -> Void)? = nil

    @ObservedObject private var store = RunPlanV2Store.shared
    @Environment(\.dismiss) private var dismiss
    @State private var day: RunPlanV2Day?
    @State private var aiSummary: String?
    @State private var polling = true
    @State private var busyId: String?
    @State private var error: String?
    @State private var effortModel: RunPlanEffortModel

    init(workoutId: String, onDone: (() -> Void)? = nil) {
        self.workoutId = workoutId
        self.onDone = onDone
        _effortModel = State(initialValue: RunPlanEffortModel(workoutId: workoutId))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let day {
                    gradeCard(day)
                    RunPlanEffortCard(model: effortModel)
                    if let summary = aiSummary ?? day.grade?.summary, !summary.isEmpty {
                        FlameyNote(text: summary, tag: aiSummary != nil ? FlameyNote.tag(for: "apple")
                                                                        : FlameyNote.tag(for: day.grade?.summary_source))
                    }
                    proposals
                    Text(String(localized: "Grade is how well you followed the plan, not raw speed. Running easy days too fast costs points."))
                        .madFont(size: 11, design: .rounded)
                        .foregroundStyle(.white.opacity(0.5))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 4)
                } else if polling {
                    VStack(spacing: 12) {
                        ProgressView().tint(.white)
                        Text(String(localized: "Grading your run…"))
                            .madFont(size: 14, weight: .bold, design: .rounded)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
                } else {
                    RPV2Notice(icon: "clock", text: String(localized: "Your grade will show on your plan once this run syncs."))
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(Color.black.ignoresSafeArea())
        .navigationTitle(String(localized: "Run complete"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let onDone {
                ToolbarItem(placement: .confirmationAction) { Button(String(localized: "Done")) { onDone() } }
            }
        }
        .preferredColorScheme(.dark)
        .task { await load() }
    }

    // MARK: Grade

    private func gradeCard(_ day: RunPlanV2Day) -> some View {
        let g = day.grade
        return RPV2Card(radius: 22, padding: 16) {
            RPV2Eyebrow(text: "\(RPV2Format.dayHeader(day.dateKey)) · \(RPV2Format.title(day))")
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 16) { ring(g); bars(g) }
                VStack(alignment: .leading, spacing: 12) { ring(g); bars(g) }
            }
            .padding(.top, 8)
            stats(day).padding(.top, 12)
        }
    }

    private func ring(_ g: RunPlanV2Grade?) -> some View {
        let score = g?.score
        let frac = Double(score ?? 0) / 100
        return ZStack {
            Circle().stroke(Color.white.opacity(0.1), lineWidth: 11)
            Circle()
                .trim(from: 0, to: frac)
                .stroke(tint(score), style: StrokeStyle(lineWidth: 11, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text(score.map(String.init) ?? "–")
                    .font(.system(size: 36, weight: .black, design: .rounded))
                    .minimumScaleFactor(0.6)
                Text(String(localized: "of 100"))
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .frame(width: 120, height: 120)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "Grade"))
        .accessibilityValue(score.map { String(localized: "\($0) of 100") } ?? String(localized: "Not graded yet"))
    }

    private func bars(_ g: RunPlanV2Grade?) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            bar(String(localized: "Completion"), g?.completion)
            bar(String(localized: "On target"), g?.on_target)
            bar(String(localized: "Consistency"), g?.consistency)
        }
        .frame(maxWidth: .infinity)
    }

    private func bar(_ label: String, _ value: Int?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(label).foregroundStyle(.white.opacity(0.65))
                Spacer(minLength: 4)
                Text(value.map(String.init) ?? "–").foregroundStyle(.white)
            }
            .madFont(size: 12, weight: .heavy, design: .rounded)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.1))
                    Capsule().fill(tint(value)).frame(width: geo.size.width * Double(value ?? 0) / 100)
                }
            }
            .frame(height: 6)
        }
        .accessibilityElement(children: .combine)
    }

    private func tint(_ score: Int?) -> Color {
        guard let score else { return .white.opacity(0.3) }
        if score >= 80 { return RPV2Colors.green }
        if score >= 60 { return RPV2Colors.gold }
        return RPV2Colors.orange
    }

    private func stats(_ day: RunPlanV2Day) -> some View {
        let c = day.completed
        var items: [(String, String)] = []
        if let mi = c?.distance_mi { items.append((RPV2Format.distance(mi), String(localized: "distance"))) }
        if let s = c?.duration_s { items.append((RPV2Format.clock(s), String(localized: "time"))) }
        let reps = day.workSegments.first?.reps ?? 0
        if reps > 0 {
            let done = (day.grade?.completion ?? 0) >= 100 ? reps : Int((Double(reps) * Double(day.grade?.completion ?? 0) / 100).rounded())
            items.append(("\(done) / \(reps)", String(localized: "reps")))
        } else if let p = c?.avg_pace_s {
            items.append((RPV2Format.pace(p), String(localized: "pace")))
        }
        return HStack(spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                VStack(spacing: 1) {
                    Text(item.0).madFont(size: 15, weight: .black, design: .rounded, maxScale: 1.4)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Text(item.1).madFont(size: 11, weight: .bold, design: .rounded).foregroundStyle(.white.opacity(0.45))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.05)))
                .accessibilityElement(children: .combine)
            }
        }
    }

    // MARK: Proposals for the coming days

    private var upcoming: [RunPlanV2Proposal] {
        let today = RunPlanV2Date.todayKey()
        return store.pendingProposals.filter { ($0.first_date ?? $0.changes.first?.local_date ?? "") >= today }
    }

    @ViewBuilder
    private var proposals: some View {
        let list = upcoming
        if !list.isEmpty {
            RPV2Eyebrow(text: String(localized: "Changes for the next days"))
            ForEach(list) { p in
                RunPlanProposalCard(proposal: p, busy: busyId == p.id ? .apply : nil,
                                    error: busyId == nil ? nil : error, compact: true) { action in
                    Task { await decide(p, action) }
                }
            }
        }
        if let error, busyId == nil {
            RPV2Notice(icon: "exclamationmark.triangle.fill", text: error, tint: RPV2Colors.orange)
        }
    }

    private func decide(_ p: RunPlanV2Proposal, _ action: RunPlanProposalView.Action) async {
        busyId = p.id
        error = nil
        defer { busyId = nil }
        do {
            switch action {
            case .apply: try await store.apply(p)
            case .keep: try await store.decline(p)
            default: break
            }
            MADHaptics.success()
        } catch let e as RunPlanV2Error {
            error = e.message
        } catch {
            self.error = RunPlanV2Error.offline.message
        }
    }

    // MARK: Load

    private func find() -> RunPlanV2Day? {
        let all = [store.today].compactMap { $0 } + store.week
        return all.first { $0.completed?.workout_ids.contains(workoutId) == true }
    }

    private func load() async {
        defer { polling = false }
        for attempt in 0..<6 {
            if attempt > 0 { try? await Task.sleep(nanoseconds: 3_000_000_000) }
            await store.refreshQuietly()
            if let found = find() {
                day = found
                if found.grade?.score != nil { break }
            } else if attempt == 2 {
                // Older than this week: look back a fortnight.
                let today = RunPlanV2Date.todayKey()
                if let from = RunPlanV2Date.addingDays(-14, to: today),
                   let days = try? await RunPlanV2Service.days(from: from, to: today),
                   let hit = days.first(where: { $0.completed?.workout_ids.contains(workoutId) == true }) {
                    day = hit
                    if hit.grade?.score != nil { break }
                }
            }
        }
        if let day { await effortModel.load(day: day) }
        await writeSummaryIfNeeded()
    }

    /// The Apple coach rewrites a template summary in Flamey's words once.
    private func writeSummaryIfNeeded() async {
        guard let day, let grade = day.grade, grade.score != nil, store.coachTier == .apple,
              grade.summary_source == nil || grade.summary_source == "template" else { return }
        let key = "runPlanV2Summary|\(workoutId)"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        aiSummary = await AppleCoach.shared.writePostRunSummary(day: day, grade: grade)
    }
}
