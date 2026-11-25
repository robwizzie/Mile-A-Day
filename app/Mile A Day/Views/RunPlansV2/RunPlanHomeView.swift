import SwiftUI

// Plan home (mockup screens 4, 11, 12): the tier badge, goals line, pending-
// proposal banner, the week strip with walk days, today's card (shoe +
// treadmill chips, Flamey's note), walk-day suggestion cards, Start today's
// run, and Ask Flamey (AI tiers) or the formula-tier note.

struct RunPlanHomeView: View {
    @ObservedObject private var store = RunPlanV2Store.shared
    @ObservedObject private var analyzer = RunFitnessAnalyzer.shared
    @State private var showSetup = false
    @State private var showChat = false
    @State private var showConsent = false
    @State private var openProposal: RunPlanV2Proposal?
    @State private var showPreRun = false
    @State private var busyId: String?
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let current = store.current {
                    content(current)
                } else if store.loaded {
                    RunPlanEmptyState { showSetup = true }
                } else {
                    ProgressView().tint(.white).frame(maxWidth: .infinity).padding(.top, 60)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 28)
        }
        .background(Color.black.ignoresSafeArea())
        .navigationTitle(String(localized: "Your plan"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if store.hasPlan {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink { RunPlanV2SettingsView() } label: {
                        Image(systemName: "slider.horizontal.3")
                            .accessibilityLabel(String(localized: "Plan settings"))
                    }
                }
            }
        }
        .navigationDestination(item: $openProposal) { p in RunPlanProposalView(proposalId: p.id, initial: p) }
        .navigationDestination(isPresented: $showPreRun) { RunPlanPreRunView() }
        .fullScreenCover(isPresented: $showSetup) { RunPlanSetupView() }
        .sheet(isPresented: $showChat) { RunPlanChatView() }
        .sheet(isPresented: $showConsent) {
            RunPlanAnthropicConsentView { _ in showConsent = false }
        }
        .task {
            await store.refreshIfStale()
            if store.ai.needsAnthropicConsent, !RunPlanAnthropicConsentView.askedThisSession {
                RunPlanAnthropicConsentView.askedThisSession = true
                showConsent = true
            }
        }
        .refreshable { await store.refresh() }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private func content(_ current: RunPlanV2Current) -> some View {
        let tier = store.coachTier
        header(current.plan, ai: tier.isAI)
        if let notice = store.coachNotice {
            coachNotice(notice)
        }
        let pending = store.pendingProposals
        if !pending.isEmpty {
            Button { openFirst(pending) } label: { RPV2ProposalBanner(count: pending.count) }
                .buttonStyle(.plain)
        }
        RPV2WeekStrip(days: current.week, flagged: flaggedDates)
        ForEach(store.suggestions) { s in
            RunPlanWalkSuggestionCard(proposal: s, busy: busyId == s.id) { apply in
                Task { await decide(s, apply: apply) }
            }
        }
        if let error {
            RPV2Notice(icon: "exclamationmark.triangle.fill", text: error, tint: RPV2Colors.orange)
        }
        if let today = current.today {
            RPV2TodayCard(day: today, treadmill: (analyzer.profile?.treadmill_fraction ?? 0) >= 0.5)
            if today.isWalk {
                RunPlanWalkDayStepsCard()
            } else if !today.dayStatus.isComplete {
                RPV2Button(title: String(localized: "Start today's run"), icon: "play.fill") { showPreRun = true }
            } else if let id = today.completed?.workout_ids.first {
                NavigationLink { RunPlanPostRunView(workoutId: id) } label: {
                    RPV2SecondaryButtonLabel(title: String(localized: "See how it went"))
                }
                .buttonStyle(.plain)
            }
        } else if let next = current.next_run {
            nextRun(next)
        }
        if tier.isAI {
            Button { showChat = true } label: { askBar }
                .buttonStyle(.plain)
        } else {
            RPV2Notice(icon: "info.circle", text: formulaNote)
        }
        historyLink
    }

    private func header(_ plan: RunPlanV2Plan, ai: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                RPV2Eyebrow(text: String(localized: "Week \(plan.week_index ?? 1) · \(RPV2Format.phaseLabel(plan))"))
                Spacer(minLength: 4)
                RPV2TierBadge(ai: ai)
            }
            Text(RPV2Format.goalsLine(plan.goals))
                .madFont(size: 21, weight: .black, design: .rounded, maxScale: 1.5)
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            if let sub = subline(plan) {
                Text(sub)
                    .madFont(size: 12, weight: .bold, design: .rounded)
                    .foregroundStyle(.white.opacity(0.5))
                    .madBodyLines(2)
            }
        }
    }

    private func subline(_ plan: RunPlanV2Plan) -> String? {
        var parts: [String] = []
        if let cp = plan.checkpoints.first, let label = cp.label { parts.append(String(localized: "Next checkpoint: \(label)")) }
        if let w = plan.weekly_target_mi, w > 0 { parts.append(String(localized: "\(RPV2Format.distance(w)) this week")) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var flaggedDates: Set<String> {
        Set((store.pendingProposals + store.suggestions).flatMap { $0.changes.compactMap(\.local_date) })
    }

    private func nextRun(_ day: RunPlanV2Day) -> some View {
        RPV2Card {
            RPV2Eyebrow(text: String(localized: "Next run · \(RPV2Format.dayHeader(day.dateKey))"))
            Text(RPV2Format.title(day))
                .madFont(size: 24, weight: .black, design: .rounded, maxScale: 1.4)
                .padding(.top, 4)
            if let note = day.note, !note.isEmpty {
                FlameyNote(text: note, tag: FlameyNote.tag(for: day.note_source)).padding(.top, 10)
            }
        }
    }

    private func coachNotice(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            RPV2Notice(icon: "sparkles", text: text, tint: .white.opacity(0.75), fill: RPV2Colors.orange.opacity(0.10))
            HStack(spacing: 14) {
                if AppleCoach.shared.canSuggestMoreAllowance {
                    Button(String(localized: "More with iCloud+")) { AppleCoach.shared.showMoreAllowance() }
                }
                Button(String(localized: "OK")) { store.acknowledgeCoachNotice() }
            }
            .madFont(size: 13, weight: .black, design: .rounded)
            .foregroundStyle(RPV2Colors.orange)
            .padding(.leading, 4)
        }
    }

    private var askBar: some View {
        HStack(spacing: 8) {
            Text(String(localized: "Ask Flamey about your plan…"))
                .madFont(size: 13, design: .rounded)
                .foregroundStyle(.white.opacity(0.4))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Circle().fill(RPV2Colors.red).frame(width: 28, height: 28)
                .overlay(Image(systemName: "paperplane.fill").font(.system(size: 12, weight: .bold)).foregroundStyle(.white))
                .accessibilityHidden(true)
        }
        .padding(.leading, 16)
        .padding(.trailing, 6)
        .padding(.vertical, 7)
        .background(Capsule().fill(Color.white.opacity(0.06)).overlay(Capsule().strokeBorder(Color.white.opacity(0.1))))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "Ask Flamey about your plan"))
        .accessibilityAddTraits(.isButton)
    }

    private var formulaNote: String {
        var text = String(localized: "Your plan adjusts with set rules after each run, and asks before it changes anything.")
        if store.ai.effectiveProvider == .apple, !AppleCoach.isAvailable {
            text += " " + AppleCoach.unavailableReason
        }
        return text
    }

    private var historyLink: some View {
        NavigationLink { RunPlanHistoryView() } label: {
            HStack(spacing: 5) {
                Image(systemName: "clock.arrow.circlepath").accessibilityHidden(true)
                Text(String(localized: "Plan history"))
            }
            .madFont(size: 13, weight: .black, design: .rounded)
            .foregroundStyle(RPV2Colors.orange)
            .frame(maxWidth: .infinity)
            .padding(.top, 4)
        }
        .buttonStyle(.plain)
    }

    private func openFirst(_ pending: [RunPlanV2Proposal]) {
        let today = RunPlanV2Date.todayKey()
        openProposal = pending.first { $0.touches(today) } ?? pending.sorted { ($0.first_date ?? "") < ($1.first_date ?? "") }.first
    }

    private func decide(_ p: RunPlanV2Proposal, apply: Bool) async {
        busyId = p.id
        error = nil
        defer { busyId = nil }
        do {
            if apply { try await store.apply(p) } else { try await store.decline(p) }
            MADHaptics.success()
        } catch let e as RunPlanV2Error {
            error = e.message
            if e == .staleProposal { await store.refresh() }
        } catch {
            self.error = RunPlanV2Error.offline.message
        }
    }
}

/// A secondary capsule as a label (for NavigationLinks).
struct RPV2SecondaryButtonLabel: View {
    let title: String

    var body: some View {
        Text(title)
            .madFont(size: 14, weight: .black, design: .rounded)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 40)
            .background(Capsule().fill(Color.white.opacity(0.08)))
    }
}

/// No plan yet: what it is, and the way in.
struct RunPlanEmptyState: View {
    let onStart: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                FlameyAvatar(size: 36)
                Text(String(localized: "A plan that fits your runs"))
                    .madFont(size: 22, weight: .black, design: .rounded)
            }
            .padding(.top, 8)
            Text(String(localized: "Tell me what you're training for. I'll read your runs, build a week of runs and walk days, and suggest changes as you go. Nothing changes without your yes."))
                .madFont(size: 14, design: .rounded)
                .foregroundStyle(.white.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
            RPV2Notice(icon: "figure.walk", text: String(localized: "Walk days still keep your streak: 1 mile or 10k steps."),
                       tint: RPV2Colors.mint, fill: RPV2Colors.green.opacity(0.12))
            RPV2Button(title: String(localized: "Build my plan"), icon: "sparkles", action: onStart)
        }
    }
}

// MARK: - Walk-day suggestions (screen 11)

/// "You've earned a walk day" (green) / "You're overdoing it" (orange).
struct RunPlanWalkSuggestionCard: View {
    let proposal: RunPlanV2Proposal
    var busy = false
    let onDecide: (Bool) -> Void

    private var earned: Bool { proposal.proposalKind == .walkDayEarned }
    private var tint: Color { earned ? RPV2Colors.green : RPV2Colors.orange }

    var body: some View {
        RPV2Card(stroke: tint.opacity(0.4), radius: 20, padding: 16) {
            HStack(spacing: 10) {
                Circle().fill(tint).frame(width: 30, height: 30)
                    .overlay(Image(systemName: earned ? "figure.walk" : "exclamationmark.triangle.fill")
                        .font(.system(size: 14, weight: .bold)).foregroundStyle(.black))
                    .accessibilityHidden(true)
                Text(proposal.title ?? (earned ? String(localized: "You've earned a walk day") : String(localized: "You're overdoing it")))
                    .madFont(size: 16, weight: .black, design: .rounded)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let reason = proposal.reason {
                Text(reason)
                    .madFont(size: 13, design: .rounded)
                    .foregroundStyle(.white.opacity(0.65))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
            }
            HStack(spacing: 8) {
                RPV2Button(title: earned ? String(localized: "Take it today") : String(localized: "Apply"),
                           fill: earned ? RPV2Colors.green : RPV2Colors.red, text: earned ? .black : .white,
                           isBusy: busy) { onDecide(true) }
                RPV2SecondaryButton(title: earned ? String(localized: "Keep running") : String(localized: "Keep")) { onDecide(false) }
            }
            .padding(.top, 12)
        }
    }
}

/// On a walk day: today's steps toward 10k (the streak's other door).
struct RunPlanWalkDayStepsCard: View {
    @ObservedObject private var health = HealthKitManager.shared

    var body: some View {
        let steps = health.todaysSteps
        let goal = 10_000
        let frac = min(Double(steps) / Double(goal), 1)
        return RPV2Card(radius: 16, padding: 12) {
            HStack {
                Label(String(localized: "Streak today"), systemImage: "figure.walk")
                    .foregroundStyle(.white)
                Spacer(minLength: 6)
                Text(String(localized: "\(steps.formatted()) / \(goal.formatted()) steps"))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .madFont(size: 12, weight: .heavy, design: .rounded)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.1))
                    Capsule().fill(RPV2Colors.green).frame(width: g.size.width * frac)
                }
            }
            .frame(height: 6)
            .padding(.top, 8)
            Text(String(localized: "Walk days still keep your streak: 1 mile or 10k steps."))
                .madFont(size: 11, design: .rounded)
                .foregroundStyle(.white.opacity(0.5))
                .padding(.top, 8)
        }
    }
}

// MARK: - Ask Flamey

struct RunPlanChatView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var messages: [RunPlanChatMessage] = []
    @State private var draft = ""
    @State private var sending = false
    @ObservedObject private var store = RunPlanV2Store.shared

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        FlameyNote(text: String(localized: "Ask me anything about your plan: why a run is there, moving a day, how a run went. If something should change, I'll suggest it and you decide."))
                        ForEach(messages) { m in bubble(m).id(m.id) }
                        if sending {
                            HStack(spacing: 8) { FlameyAvatar(size: 22); ProgressView().tint(.white) }
                        }
                        if !store.pendingProposals.isEmpty {
                            RPV2Notice(icon: "sparkles", text: String(localized: "Suggested changes wait on your plan. Nothing changes until you decide."),
                                       tint: RPV2Colors.gold, fill: RPV2Colors.gold.opacity(0.1))
                        }
                    }
                    .padding(16)
                }
                .onChange(of: messages.count) { _, _ in
                    if let last = messages.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                }
            }
            .safeAreaInset(edge: .bottom) { composer }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle(String(localized: "Ask Flamey"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button(String(localized: "Done")) { dismiss() } }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func bubble(_ m: RunPlanChatMessage) -> some View {
        HStack(alignment: .top, spacing: 8) {
            if m.role == .flamey { FlameyAvatar(size: 22) } else { Spacer(minLength: 40) }
            Text(m.text)
                .madFont(size: 14, design: .rounded)
                .foregroundStyle(.white)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(m.role == .user ? RPV2Colors.red.opacity(0.35) : Color.white.opacity(0.07)))
                .fixedSize(horizontal: false, vertical: true)
            if m.role == .flamey { Spacer(minLength: 24) }
        }
    }

    private var composer: some View {
        HStack(spacing: 8) {
            TextField(String(localized: "Ask Flamey about your plan…"), text: $draft, axis: .vertical)
                .madFont(size: 14, design: .rounded)
                .lineLimit(1...4)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(Capsule().fill(Color.white.opacity(0.08)))
            Button { send() } label: {
                Circle().fill(RPV2Colors.red).frame(width: 34, height: 34)
                    .overlay(Image(systemName: "paperplane.fill").font(.system(size: 14, weight: .bold)).foregroundStyle(.white))
            }
            .accessibilityLabel(String(localized: "Send"))
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sending)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.black)
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""
        let history = messages
        messages.append(RunPlanChatMessage(role: .user, text: text))
        sending = true
        Task {
            let reply = await RunPlanCoach.ask(text, history: history)
            sending = false
            messages.append(RunPlanChatMessage(role: .flamey, text: reply
                ?? String(localized: "I can't answer right now. Your plan is still on, and the rules keep it safe.")))
        }
    }
}
