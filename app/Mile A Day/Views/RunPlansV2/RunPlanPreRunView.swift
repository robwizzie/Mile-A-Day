import SwiftUI

/// Coach mode (spoken cues during a plan run), remembered across runs. The
/// live run coach reads `RunPlanCoachMode.isOn`.
enum RunPlanCoachMode {
    static let key = "runPlanV2CoachModeOn"
    static var isOn: Bool {
        UserDefaults.standard.object(forKey: key) == nil ? true : UserDefaults.standard.bool(forKey: key)
    }
}

/// Before the run (mockup screen 7): today's run with Flamey's note and the
/// pre-loaded shoe; an optional check-in (time, energy, soreness, go further,
/// text for the AI coach); the resulting proposal for today; coach mode;
/// Start run.
///
/// Embeddable: the start wizard's "Run plan" door shows this with its own
/// `onStart` (which should then read `RunPlanV2Store.shared.today` for the
/// segments and shoe). Without one it opens the tracker for a run.
struct RunPlanPreRunView: View {
    var onStart: (() -> Void)? = nil
    /// Hide the nav title when the host draws its own chrome.
    var showsNavigationTitle = true

    @ObservedObject private var store = RunPlanV2Store.shared
    @AppStorage(RunPlanCoachMode.key) private var coachMode = true
    @State private var timeMin: Int?
    @State private var energy: Double = 5
    @State private var soreness: Double = 2
    @State private var touchedEnergy = false
    @State private var touchedSoreness = false
    @State private var goFurther: Double?
    @State private var text = ""
    @State private var checkingIn = false
    @State private var outcome: RunPlanCoach.CheckinOutcome?
    @State private var deciding: RunPlanProposalView.Action?
    @State private var decided = false
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let today = store.today {
                    todayCard(today)
                    RPV2Eyebrow(text: String(localized: "Check in · all optional"))
                    checkinCard(today)
                    if let reply = outcome?.reply, !reply.isEmpty { FlameyNote(text: reply) }
                    if let p = outcome?.proposal, !decided, p.isPending { proposalCard(p, today: today) }
                    if let error { RPV2Notice(icon: "exclamationmark.triangle.fill", text: error, tint: RPV2Colors.orange) }
                    if hasCheckinInput, outcome == nil {
                        RPV2SecondaryButton(title: store.coachTier.isAI ? String(localized: "Ask Flamey for today's version")
                                                                       : String(localized: "Fit today's run to this"),
                                            isBusy: checkingIn) { Task { await checkIn(today) } }
                    }
                    RPV2Button(title: String(localized: "Start run"), icon: "play.fill") { start() }
                } else {
                    RPV2Notice(icon: "calendar", text: String(localized: "No plan run today. Any run still counts for your streak."))
                    RPV2Button(title: String(localized: "Start run"), icon: "play.fill") { start() }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color.black.ignoresSafeArea())
        .navigationTitle(showsNavigationTitle ? String(localized: "Before your run") : "")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        .task { await store.refreshIfStale() }
    }

    // MARK: Today

    private func todayCard(_ day: RunPlanV2Day) -> some View {
        RPV2Card {
            HStack(spacing: 8) {
                RPV2Eyebrow(text: String(localized: "Today · \(RPV2Format.dayHeader(day.dateKey))"))
                Spacer(minLength: 4)
                RPV2KindPill(kind: day.dayKind)
            }
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 8) { bigTitle(day); paceLine(day) }
                VStack(alignment: .leading, spacing: 2) { bigTitle(day); paceLine(day) }
            }
            .padding(.top, 4)
            if let shoe = day.shoe?.name {
                RPV2Chip(icon: ShoeSymbol.filled, label: shoe, color: RPV2Colors.orange).padding(.top, 8)
            }
            if let note = day.note, !note.isEmpty {
                FlameyNote(text: note, tag: FlameyNote.tag(for: day.note_source)).padding(.top, 8)
            }
        }
    }

    private func bigTitle(_ day: RunPlanV2Day) -> some View {
        Text(day.dayKind == .easy || day.dayKind == .long ? RPV2Format.distance(day.miles) : RPV2Format.title(day))
            .madFont(size: 30, weight: .black, design: .rounded, maxScale: 1.4)
            .lineLimit(2)
            .minimumScaleFactor(0.7)
    }

    @ViewBuilder
    private func paceLine(_ day: RunPlanV2Day) -> some View {
        if let seg = day.segments.first(where: { $0.hasPaceBand }), let lo = seg.pace_low_s, let hi = seg.pace_high_s {
            Text(String(localized: "at \(RPV2Format.paceRange(lo, hi))"))
                .madFont(size: 13, weight: .heavy, design: .rounded)
                .foregroundStyle(.white.opacity(0.55))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        } else if let sub = day.subtitle {
            Text(sub).madFont(size: 13, weight: .heavy, design: .rounded).foregroundStyle(.white.opacity(0.55))
        }
    }

    // MARK: Check-in

    private var hasCheckinInput: Bool {
        timeMin != nil || touchedEnergy || touchedSoreness || goFurther != nil
            || !text.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func checkinCard(_ day: RunPlanV2Day) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            timeChips
            slider(String(localized: "Energy"), value: $energy, left: String(localized: "Drained"),
                   right: String(localized: "Energized"), tint: RPV2Colors.green) { touchedEnergy = true; outcome = nil }
            slider(String(localized: "Soreness"), value: $soreness, left: String(localized: "None"),
                   right: String(localized: "Very sore"), tint: RPV2Colors.orange) { touchedSoreness = true; outcome = nil }
            if !day.isWalk, day.miles > 0 { goFurtherRow(day) }
            if store.coachTier.isAI { textBox }
            coachToggle
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(RPV2Colors.card))
    }

    private var timeChips: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "Time available")).madFont(size: 13, weight: .bold, design: .rounded)
            HStack(spacing: 5) {
                ForEach([20, 30, 45, 240], id: \.self) { t in
                    let on = timeMin == t
                    Button {
                        MADHaptics.tap()
                        timeMin = on ? nil : t
                        outcome = nil
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 2) {
                            Text(t == 240 ? "60+" : "\(t)")
                                .madFont(size: 13, weight: .black, design: .rounded, maxScale: 1.3)
                            Text(String(localized: "min"))
                                .madFont(size: 10, weight: .heavy, design: .rounded, maxScale: 1.3)
                                .opacity(0.7)
                        }
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .foregroundStyle(on ? .black : .white)
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(on ? RPV2Colors.orange : Color.white.opacity(0.06)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(t == 240 ? String(localized: "60 minutes or more") : String(localized: "\(t) minutes"))
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
        }
    }

    private func slider(_ title: String, value: Binding<Double>, left: String, right: String, tint: Color,
                        onEdit: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).madFont(size: 13, weight: .bold, design: .rounded)
            Slider(value: value, in: 0...10, step: 1) { editing in if editing { onEdit() } }
                .tint(tint)
                .accessibilityLabel(title)
                .accessibilityValue("\(Int(value.wrappedValue)) / 10")
            HStack {
                Text(left)
                Spacer()
                Text(right)
            }
            .madFont(size: 11, weight: .heavy, design: .rounded)
            .foregroundStyle(.white.opacity(0.45))
        }
    }

    private func goFurtherRow(_ day: RunPlanV2Day) -> some View {
        let planned = day.miles
        let current = goFurther ?? planned
        return VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "Go further")).madFont(size: 13, weight: .bold, design: .rounded)
            HStack(spacing: 8) {
                roundButton("minus", enabled: current > planned, fill: Color.white.opacity(0.08), glyph: .white) {
                    let next = max(planned, current - 0.5)
                    goFurther = next <= planned + 0.001 ? nil : next
                    outcome = nil
                }
                .accessibilityLabel(String(localized: "Shorter"))
                HStack(spacing: 8) {
                    if goFurther != nil {
                        Text(RPV2Format.distance(planned)).strikethrough().foregroundStyle(.white.opacity(0.4))
                        Image(systemName: "arrow.right").foregroundStyle(.white.opacity(0.4)).accessibilityHidden(true)
                    }
                    Text(RPV2Format.distance(current)).foregroundStyle(.white)
                }
                .madFont(size: 15, weight: .black, design: .rounded)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity)
                roundButton("plus", enabled: current + 0.5 <= planned * 2 + 0.001, fill: RPV2Colors.orange, glyph: .black) {
                    goFurther = min(planned * 2, current + 0.5)
                    outcome = nil
                }
                .accessibilityLabel(String(localized: "Longer"))
            }
        }
    }

    private func roundButton(_ icon: String, enabled: Bool, fill: Color, glyph: Color,
                             action: @escaping () -> Void) -> some View {
        Button { MADHaptics.tap(); action() } label: {
            Circle().fill(fill).frame(width: 34, height: 34)
                .overlay(Image(systemName: icon).font(.system(size: 14, weight: .black)).foregroundStyle(glyph))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
    }

    private var textBox: some View {
        TextField(String(localized: "Anything else for the coach?"), text: $text, axis: .vertical)
            .madFont(size: 13, design: .rounded)
            .lineLimit(2...5)
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.04))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.white.opacity(0.1)))
            )
            .onChange(of: text) { _, new in
                if new.count > 1000 { text = String(new.prefix(1000)) }
                outcome = nil
            }
    }

    private var coachToggle: some View {
        Toggle(isOn: $coachMode) {
            HStack(spacing: 12) {
                Image(systemName: "speaker.wave.2.fill").madFont(size: 16, maxScale: 1.15)
                    .foregroundStyle(RPV2Colors.orange).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(String(localized: "Coach mode")).madFont(size: 14, weight: .bold, design: .rounded)
                    Text(String(localized: "Spoken cues during the run"))
                        .madFont(size: 11, design: .rounded).foregroundStyle(.white.opacity(0.5))
                }
            }
        }
        .tint(RPV2Colors.green)
    }

    // MARK: Proposal

    private func proposalCard(_ p: RunPlanV2Proposal, today: RunPlanV2Day) -> some View {
        RPV2Card(stroke: RPV2Colors.gold.opacity(0.33), radius: 18, padding: 12) {
            HStack(alignment: .top, spacing: 10) {
                FlameyAvatar(size: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(p.title ?? String(localized: "A different run today?"))
                        .madFont(size: 14, weight: .black, design: .rounded)
                        .fixedSize(horizontal: false, vertical: true)
                    if let reason = p.reason ?? p.checks?.text {
                        Text(reason).madFont(size: 12, design: .rounded).foregroundStyle(.white.opacity(0.55))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            HStack(spacing: 8) {
                RPV2Button(title: String(localized: "Apply"), isBusy: deciding == .apply) { Task { await decide(p, apply: true) } }
                RPV2SecondaryButton(title: String(localized: "Keep \(RPV2Format.distance(today.miles))"),
                                    isBusy: deciding == .keep) { Task { await decide(p, apply: false) } }
            }
            .padding(.top, 12)
        }
    }

    private func checkIn(_ day: RunPlanV2Day) async {
        checkingIn = true
        error = nil
        defer { checkingIn = false }
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let request = RunPlanV2CheckinRequest(
            local_date: day.dateKey,
            time_available_min: timeMin,
            energy: touchedEnergy ? Int(energy) : nil,
            soreness: touchedSoreness ? Int(soreness) : nil,
            go_further_mi: goFurther.map { ($0 * 100).rounded() / 100 },
            text: t.isEmpty ? nil : t,
            coach_mode: coachMode)
        do {
            outcome = try await RunPlanCoach.checkIn(request)
            decided = false
            if outcome?.proposal == nil, outcome?.reply == nil {
                outcome?.reply = String(localized: "Today's run fits. Go get it.")
            }
        } catch let e as RunPlanV2Error {
            error = e.message
        } catch {
            self.error = RunPlanV2Error.offline.message
        }
    }

    private func decide(_ p: RunPlanV2Proposal, apply: Bool) async {
        deciding = apply ? .apply : .keep
        defer { deciding = nil }
        do {
            if apply { try await store.apply(p) } else { try await store.decline(p) }
            decided = true
            MADHaptics.success()
        } catch let e as RunPlanV2Error {
            error = e.message
        } catch {
            self.error = RunPlanV2Error.offline.message
        }
    }

    private func start() {
        // A check-in typed but never sent still reaches the coach (formula tweak only, no wait).
        if let onStart { onStart() } else { DeepLinkRouter.shared.requestOpenTracker(activity: .run) }
    }
}
