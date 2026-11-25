import SwiftUI

// Suggested change (mockup screen 5): before/after per day, the reason, the
// goal impact, the server's safety check line, and Apply / Apply after
// today's run / Keep my plan. Undo for 24 h; plan history. Push taps
// (`run_plan_proposal`) land here through `NotificationDestination`.

struct RunPlanProposalView: View {
    let proposalId: String
    var initial: RunPlanV2Proposal? = nil
    var onDone: (() -> Void)? = nil

    @ObservedObject private var store = RunPlanV2Store.shared
    @Environment(\.dismiss) private var dismiss
    @State private var proposal: RunPlanV2Proposal?
    @State private var loadFailed = false
    @State private var busy: Action?
    @State private var error: String?
    @State private var applied: RunPlanV2Proposal?

    enum Action { case apply, after, keep, undo }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let p = applied ?? proposal {
                    RunPlanProposalCard(proposal: p, busy: busy, error: error, decide: decide)
                    footer(p)
                } else if loadFailed {
                    RPV2Notice(icon: "exclamationmark.triangle.fill", text: RunPlanV2Error.offline.message, tint: RPV2Colors.orange)
                } else {
                    ProgressView().tint(.white).frame(maxWidth: .infinity).padding(.top, 60)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(Color.black.ignoresSafeArea())
        .navigationTitle(String(localized: "Suggested change"))
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        .task { await load() }
    }

    private func footer(_ p: RunPlanV2Proposal) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { undoNote; Spacer(minLength: 6); historyLink }
                VStack(alignment: .leading, spacing: 8) { undoNote; historyLink }
            }
            if p.isPending {
                Text(String(localized: "Until you decide, your plan stays exactly as it is."))
                    .madFont(size: 11, design: .rounded)
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .padding(.horizontal, 4)
    }

    private var undoNote: some View {
        Label(String(localized: "Undo for 24 h after applying"), systemImage: "arrow.uturn.backward")
            .madFont(size: 12, design: .rounded)
            .foregroundStyle(.white.opacity(0.5))
    }

    private var historyLink: some View {
        NavigationLink { RunPlanHistoryView() } label: {
            Label(String(localized: "Plan history"), systemImage: "clock.arrow.circlepath")
                .madFont(size: 12, weight: .black, design: .rounded)
                .foregroundStyle(RPV2Colors.orange)
        }
        .buttonStyle(.plain)
    }

    private func load() async {
        if proposal == nil { proposal = initial ?? store.proposal(id: proposalId) }
        do {
            proposal = try await RunPlanV2Service.proposal(id: proposalId)
        } catch {
            if proposal == nil { loadFailed = true }
        }
    }

    private func decide(_ action: Action) {
        guard let p = applied ?? proposal, busy == nil else { return }
        busy = action
        error = nil
        Task {
            defer { busy = nil }
            do {
                switch action {
                case .apply:
                    try await store.apply(p)
                    applied = store.lastApplied ?? p
                    MADHaptics.success()
                case .after:
                    try await store.applyAfterRun(p)
                    MADHaptics.success()
                    finish()
                case .keep:
                    try await store.decline(p)
                    finish()
                case .undo:
                    try await store.undo(p)
                    applied = nil
                    finish()
                }
                if let fresh = try? await RunPlanV2Service.proposal(id: p.id) {
                    if action == .apply { applied = fresh } else { proposal = fresh }
                }
            } catch let e as RunPlanV2Error {
                error = e.message
                if case .proposalNotPending = e { await load() }
                if e == .staleProposal { await load() }
            } catch {
                self.error = RunPlanV2Error.offline.message
            }
        }
    }

    private func finish() {
        if let onDone { onDone() } else { dismiss() }
    }
}

/// The proposal card itself (also used inline after the run).
struct RunPlanProposalCard: View {
    let proposal: RunPlanV2Proposal
    var busy: RunPlanProposalView.Action? = nil
    var error: String? = nil
    var compact = false
    let decide: (RunPlanProposalView.Action) -> Void

    private var touchesToday: Bool { proposal.touches(RunPlanV2Date.todayKey()) }

    var body: some View {
        RPV2Card(stroke: RPV2Colors.gold.opacity(0.33), radius: 22, padding: 16) {
            if !compact { header }
            VStack(spacing: 8) {
                ForEach(Array(proposal.changes.enumerated()), id: \.offset) { _, c in RPV2ChangeRow(change: c) }
            }
            .padding(.top, compact ? 0 : 12)
            if let reason = proposal.reason, !reason.isEmpty {
                Text(reason)
                    .madFont(size: 14, design: .rounded)
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 12)
            }
            if let impact = impactText {
                RPV2Notice(icon: "chart.line.uptrend.xyaxis", text: impact, tint: RPV2Colors.mint, fill: RPV2Colors.green.opacity(0.12))
                    .padding(.top, 8)
            }
            if let check = proposal.checks?.text, !check.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "checkmark.shield.fill").madFont(size: 12, maxScale: 1.15)
                        .foregroundStyle(RPV2Colors.green).padding(.top, 1).accessibilityHidden(true)
                    Text(check).madFont(size: 11, design: .rounded).foregroundStyle(.white.opacity(0.5))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 8)
            }
            if let error {
                RPV2Notice(icon: "exclamationmark.triangle.fill", text: error, tint: RPV2Colors.orange).padding(.top, 8)
            }
            actions.padding(.top, 14)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            FlameyAvatar(size: 28)
            VStack(alignment: .leading, spacing: 1) {
                RPV2Eyebrow(text: proposal.isPending ? String(localized: "Suggested change") : statusLabel, color: RPV2Colors.gold)
                Text([sourceLabel, RPV2Format.when(proposal.created_at)].filter { !$0.isEmpty }.joined(separator: " · "))
                    .madFont(size: 11, design: .rounded)
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
    }

    private var sourceLabel: String {
        switch proposal.proposalSource {
        case .apple, .anthropic: return String(localized: "AI Coach")
        case .formula: return String(localized: "Run Plan")
        case .overseer, .userClaude: return String(localized: "Claude")
        case .user: return String(localized: "You")
        case .none: return ""
        }
    }

    private var statusLabel: String {
        switch proposal.proposalStatus {
        case .applied: return String(localized: "Applied")
        case .scheduled: return String(localized: "Applies after today's run")
        case .declined: return String(localized: "Kept your plan")
        case .undone: return String(localized: "Undone")
        case .superseded: return String(localized: "Replaced by a newer suggestion")
        case .expired: return String(localized: "Expired")
        case .pending: return String(localized: "Suggested change")
        }
    }

    private var impactText: String? {
        guard let g = proposal.goal_impact, let label = g.label, let b = g.before_s, let a = g.after_s, a != b else { return nil }
        return "\(label) \(RPV2Format.clock(b)) → \(RPV2Format.clock(a))"
    }

    @ViewBuilder
    private var actions: some View {
        switch proposal.proposalStatus {
        case .pending:
            VStack(spacing: 8) {
                if compact {
                    HStack(spacing: 8) {
                        RPV2Button(title: String(localized: "Apply"), isBusy: busy == .apply) { decide(.apply) }
                        RPV2SecondaryButton(title: String(localized: "Keep my plan"), isBusy: busy == .keep) { decide(.keep) }
                    }
                } else {
                    RPV2Button(title: String(localized: "Apply"), isBusy: busy == .apply) { decide(.apply) }
                    if touchesToday {
                        RPV2SecondaryButton(title: String(localized: "Apply after today's run"), isBusy: busy == .after) { decide(.after) }
                    }
                    Button { MADHaptics.tap(); decide(.keep) } label: {
                        Text(String(localized: "Keep my plan"))
                            .madFont(size: 14, weight: .black, design: .rounded)
                            .foregroundStyle(.white.opacity(0.6))
                            .frame(maxWidth: .infinity, minHeight: 36)
                    }
                    .buttonStyle(.plain)
                    .disabled(busy != nil)
                }
            }
        case .applied where proposal.canUndo():
            VStack(alignment: .leading, spacing: 8) {
                RPV2Notice(icon: "checkmark.circle.fill", text: String(localized: "Applied. Your plan is updated."),
                           tint: RPV2Colors.mint, fill: RPV2Colors.green.opacity(0.12))
                RPV2SecondaryButton(title: String(localized: "Undo"), isBusy: busy == .undo) { decide(.undo) }
            }
        default:
            EmptyView()
        }
    }
}

// MARK: - Plan history

struct RunPlanHistoryView: View {
    @State private var entries: [RunPlanV2HistoryEntry] = []
    @State private var loaded = false
    @State private var failed = false
    @State private var loadingMore = false
    @State private var exhausted = false

    var body: some View {
        List {
            if loaded, entries.isEmpty {
                Text(String(localized: "Nothing yet. Every suggestion and what you decided shows up here."))
                    .madFont(size: 14, design: .rounded)
                    .foregroundStyle(.secondary)
            }
            ForEach(entries) { e in
                row(e)
                    .onAppear { if e.id == entries.last?.id { Task { await more() } } }
            }
            if failed {
                Text(RunPlanV2Error.offline.message).madFont(size: 13, design: .rounded).foregroundStyle(.orange)
            }
        }
        .listStyle(.plain)
        .overlay { if !loaded { ProgressView() } }
        .navigationTitle(String(localized: "Plan history"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .preferredColorScheme(.dark)
    }

    private func row(_ e: RunPlanV2HistoryEntry) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon(e.event))
                .madFont(size: 14, weight: .bold, maxScale: 1.15)
                .foregroundStyle(tint(e.event))
                .frame(width: 22)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(e.summary ?? eventLabel(e.event))
                    .madFont(size: 14, weight: .semibold, design: .rounded)
                    .fixedSize(horizontal: false, vertical: true)
                Text([eventLabel(e.event), RPV2Format.when(e.at)].filter { !$0.isEmpty }.joined(separator: " · "))
                    .madFont(size: 12, design: .rounded)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private func eventLabel(_ event: String?) -> String {
        switch event {
        case "plan_created": return String(localized: "Plan started")
        case "settings_changed": return String(localized: "You changed settings")
        case "proposal_created": return String(localized: "Suggested")
        case "proposal_applied": return String(localized: "Applied")
        case "proposal_scheduled": return String(localized: "Applies after the run")
        case "proposal_declined": return String(localized: "Kept your plan")
        case "proposal_superseded": return String(localized: "Replaced")
        case "proposal_undone": return String(localized: "Undone")
        case "proposal_expired": return String(localized: "Expired")
        case "overseer_set_plan": return String(localized: "Changed with Claude")
        case "plan_archived": return String(localized: "Plan ended")
        default: return ""
        }
    }

    private func icon(_ event: String?) -> String {
        switch event {
        case "proposal_applied", "overseer_set_plan": return "checkmark.circle.fill"
        case "proposal_declined": return "xmark.circle"
        case "proposal_undone": return "arrow.uturn.backward.circle"
        case "proposal_created": return "sparkles"
        case "plan_created": return "flag.fill"
        case "plan_archived": return "archivebox"
        default: return "circle"
        }
    }

    private func tint(_ event: String?) -> Color {
        switch event {
        case "proposal_applied", "overseer_set_plan": return RPV2Colors.green
        case "proposal_created": return RPV2Colors.gold
        default: return .secondary
        }
    }

    private func load() async {
        do {
            entries = try await RunPlanV2Store.shared.history()
            failed = false
            exhausted = entries.count < 50
        } catch {
            failed = true
        }
        loaded = true
    }

    private func more() async {
        guard !loadingMore, !exhausted, let last = entries.last?.at else { return }
        loadingMore = true
        defer { loadingMore = false }
        if let next = try? await RunPlanV2Store.shared.history(before: last) {
            let known = Set(entries.map(\.id))
            entries += next.filter { !known.contains($0.id) }
            exhausted = next.count < 50
        }
    }
}

// MARK: - Anthropic consent (App Review 5.1.2(i))

/// One-time consent before the server sends this user's coaching data to
/// Anthropic. Only shown when the admin site switched this user to Claude.
struct RunPlanAnthropicConsentView: View {
    let onDone: (Bool) -> Void
    @State private var busy = false
    @State private var error: String?

    /// Asked at most once per launch from plan home.
    static var askedThisSession = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 10) {
                        FlameyAvatar(size: 36)
                        Text(String(localized: "Your AI Coach uses Claude"))
                            .madFont(size: 22, weight: .black, design: .rounded)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text(String(localized: "Your coach runs on Claude, an AI model made by Anthropic. To plan and adjust your runs, Mile A Day sends Anthropic:"))
                        .madFont(size: 14, design: .rounded)
                        .foregroundStyle(.white.opacity(0.8))
                        .fixedSize(horizontal: false, vertical: true)
                    VStack(alignment: .leading, spacing: 8) {
                        bullet(String(localized: "Your plan, goals and the notes you write for the coach"))
                        bullet(String(localized: "A fitness summary from your runs: paces, distances, heart-rate zones, resting heart rate"))
                        bullet(String(localized: "Your check-ins before runs and your messages to Flamey"))
                    }
                    Text(String(localized: "Anthropic doesn't get your name, email, location or raw workout data. Mile A Day's team may review coaching conversations to improve the coach. You can turn the AI Coach off any time in plan settings."))
                        .madFont(size: 13, design: .rounded)
                        .foregroundStyle(.white.opacity(0.6))
                        .fixedSize(horizontal: false, vertical: true)
                    if let error {
                        RPV2Notice(icon: "exclamationmark.triangle.fill", text: error, tint: RPV2Colors.orange)
                    }
                    RPV2Button(title: String(localized: "Allow"), isBusy: busy) { Task { await answer(true) } }
                    RPV2SecondaryButton(title: String(localized: "Not now")) { onDone(false) }
                }
                .padding(20)
            }
            .background(Color.black.ignoresSafeArea())
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.large])
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle().fill(RPV2Colors.orange).frame(width: 6, height: 6).padding(.top, 6)
            Text(text).madFont(size: 14, design: .rounded).foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func answer(_ accepted: Bool) async {
        busy = true
        defer { busy = false }
        do {
            try await RunPlanV2Store.shared.setAnthropicConsent(accepted)
            onDone(accepted)
        } catch let e as RunPlanV2Error {
            error = e.message
        } catch {
            self.error = RunPlanV2Error.offline.message
        }
    }
}
