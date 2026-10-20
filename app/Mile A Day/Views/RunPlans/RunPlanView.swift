import SwiftUI

// MARK: - Entry

/// The dashboard card's destination: the plan when there is one, the setup
/// flow when there isn't, the paywall door when Plus has lapsed.
struct RunPlanScreen: View {
    /// A feeling chip tapped on the dashboard: checked in on arrival.
    var initialFeeling: RunPlanFeeling? = nil

    @ObservedObject private var store = RunPlanStore.shared
    @ObservedObject private var plus = PlusStore.shared
    @State private var showPaywall = false

    private var locked: Bool {
        store.plusRequired || (plus.status != nil && !plus.isPlus)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if locked {
                lockedView
            } else if store.plan != nil {
                RunPlanView(initialFeeling: initialFeeling)
            } else if store.loaded {
                RunPlanSetupFlow()
            } else {
                ProgressView().tint(.white)
            }
        }
        .navigationTitle(store.plan == nil ? "New plan" : "Your plan")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .preferredColorScheme(.dark)
        .madTypeCap(.madCardCap)
        .task { await store.refreshIfStale() }
        .sheet(isPresented: $showPaywall) {
            PlusPaywallView(context: .runPlans) { purchased in
                if purchased { Task { await store.refresh() } }
            }
        }
    }

    private var lockedView: some View {
        VStack(spacing: 14) {
            RunPlanCoachAvatar(size: 80)
            Text("Run plans are part of Mile A Day+")
                .madFont(size: 20, weight: .black, design: .rounded)
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
            Text("Your daily mile and streak stay free, forever.")
                .madFont(size: 14, weight: .medium, design: .rounded)
                .foregroundColor(.white.opacity(0.6))
                .multilineTextAlignment(.center)
            RunPlanPrimaryButton(title: "See Mile A Day+") { showPaywall = true }
                .padding(.top, 6)
        }
        .padding(24)
    }
}

// MARK: - Chat

struct RunPlanChatItem: Identifiable, Equatable {
    enum Kind: Equatable {
        case runner(String)
        case flamey(String)
        /// A proposal made in this session, by id (its state lives in the store).
        case proposal(String)
    }

    let id = UUID()
    let kind: Kind
}

// MARK: - Plan screen

struct RunPlanView: View {
    var initialFeeling: RunPlanFeeling? = nil

    @ObservedObject private var store = RunPlanStore.shared
    @State private var thread: [RunPlanChatItem] = []
    /// Session proposals decided here: id → applied?
    @State private var resolved: [String: Bool] = [:]
    @State private var draft = ""
    @State private var sending = false
    @State private var checkingIn = false
    @State private var pickedFeeling: RunPlanFeeling?
    @State private var painFlagged = false
    @State private var busyProposalId: String?
    @State private var showSettings = false
    @State private var errorText: String?
    @State private var consumedInitial = false
    @State private var availability = FlameyCoach.availability

    private var current: RunPlanCurrent? { store.current }

    private var todayCheckin: RunPlanCheckin? {
        guard let c = current?.latest_checkin, c.local_date == nil || c.local_date == RunPlanDate.todayKey() else { return nil }
        return c
    }

    private var showsDoctorLine: Bool {
        painFlagged || pickedFeeling == .sore || (pickedFeeling == nil && todayCheckin?.signalsPain == true)
    }

    /// Server-side pending proposals not already shown in this session's thread.
    private var waitingProposals: [RunPlanProposal] {
        let inThread = Set(thread.compactMap { item -> String? in
            if case .proposal(let id) = item.kind { return id }
            return nil
        })
        return store.pendingProposals.filter { !inThread.contains($0.id) }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    overview
                    checkinCard
                    if availability == .available { privacyLine }
                    if !waitingProposals.isEmpty { waitingSection }
                    threadView
                    if showsDoctorLine { RunPlanDoctorLine() }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: thread.count) {
                withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo("bottom", anchor: .bottom) }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    MADHaptics.tap()
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape.fill")
                        .foregroundColor(RunPlanColors.orange)
                }
                .accessibilityLabel("Plan settings")
            }
        }
        .sheet(isPresented: $showSettings) {
            RunPlanSettingsView()
                .madTypeCap(.madListCap)
        }
        .task {
            availability = FlameyCoach.availability
            if let initialFeeling, !consumedInitial {
                consumedInitial = true
                checkIn(initialFeeling)
            }
        }
        .alert("Something went wrong", isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorText ?? "")
        }
    }

    // MARK: Overview

    @ViewBuilder
    private var overview: some View {
        if let current, let plan = current.plan {
            (Text("\(RunPlanFormat.goalsLine(plan.goals)) · ")
             + Text("week \(RunPlanFormat.week(plan))").foregroundColor(.white)
             + Text(" · \(RunPlanFormat.distance(current.weekTotalMiles)) this week"))
                .madFont(size: 13, weight: .heavy, design: .rounded)
                .foregroundColor(.white.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)
            if let warning = current.warning, !warning.isEmpty {
                Text(warning)
                    .madFont(size: 12, weight: .semibold, design: .rounded)
                    .foregroundColor(Color(red: 1.0, green: 0.78, blue: 0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }
            let week = current.thisWeek
            if !week.isEmpty {
                RunPlanWeekStrip(days: week)
                if week.contains(where: \.wasMoved) { movedLegend }
            }
            if let today = current.today {
                RunPlanTodayCard(day: today, fallbackNote: fallbackNote(today))
            } else {
                Text("Today's run is on its way. Pull to refresh in a moment.")
                    .madFont(size: 14, weight: .semibold, design: .rounded)
                    .foregroundColor(.white.opacity(0.6))
                    .runPlanCard()
            }
        }
    }

    private var movedLegend: some View {
        HStack(spacing: 6) {
            Circle().fill(RunPlanColors.gold).frame(width: 5, height: 5)
            Text("changed")
                .madFont(size: 11, weight: .semibold, design: .rounded)
                .foregroundColor(.white.opacity(0.45))
        }
        .accessibilityHidden(true)
    }

    private func fallbackNote(_ day: RunPlanDay) -> String {
        switch day.dayKind {
        case .streak: return "Streak day. Any pace counts, walking included."
        case .easy: return "Easy means you could chat the whole way."
        case .intervals: return "Today's the fast one. Jog easy between reps."
        case .tempo: return "Comfortably hard: steady, not all out."
        case .long: return "Slow and steady. Time on your feet is the point."
        case .raceTest: return "A check on your progress. Warm up well first."
        }
    }

    // MARK: Check-in

    private var checkinCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("How are you feeling?")
                .madFont(size: 13, weight: .black, design: .rounded)
                .foregroundColor(.white)
            RunPlanFeelingChips(selected: pickedFeeling ?? todayCheckin?.feelingValue,
                                disabled: checkingIn || sending) { feeling in
                checkIn(feeling)
            }
            if availability == .available {
                composer
            } else {
                Text(FlameyCoach.unavailableNote(availability))
                    .madFont(size: 12, weight: .medium, design: .rounded)
                    .foregroundColor(.white.opacity(0.5))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.04)))
            }
        }
        .runPlanCard()
    }

    private var composer: some View {
        let canSend = !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !sending
        return HStack(alignment: .bottom, spacing: 8) {
            TextField("", text: $draft, prompt: Text(thread.isEmpty ? "Tell Flamey anything…" : "Reply to Flamey…")
                .foregroundColor(.white.opacity(0.35)), axis: .vertical)
                .madFont(size: 14, weight: .medium, design: .rounded)
                .foregroundColor(.white)
                .lineLimit(1...4)
                .padding(.vertical, 7)
            Button {
                send()
            } label: {
                ZStack {
                    Circle().fill(RunPlanColors.red.opacity(canSend || sending ? 1 : 0.45))
                    if sending {
                        ProgressView().tint(.white).scaleEffect(0.7)
                    } else {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
                .frame(width: 32, height: 32)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .accessibilityLabel("Send to Flamey")
            .padding(.vertical, -6)
            .padding(.trailing, -8)
        }
        .padding(.leading, 14)
        .padding(.trailing, 6)
        .padding(.vertical, 2)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.white.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
    }

    private var privacyLine: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "lock.fill")
                .madFont(size: 11, weight: .bold, maxScale: 1.3)
                .accessibilityHidden(true)
            Text("Flamey runs on Apple Intelligence. Check-ins are never sent to an outside AI company unless you connect Claude.")
                .madFont(size: 11, weight: .medium, design: .rounded)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundColor(.white.opacity(0.4))
        .padding(.horizontal, 4)
    }

    // MARK: Thread

    private var threadView: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(thread) { item in
                switch item.kind {
                case .runner(let text):
                    RunPlanRunnerBubble(text: text)
                case .flamey(let text):
                    RunPlanFlameyBubble(text: text)
                case .proposal(let id):
                    sessionProposal(id)
                }
            }
            if sending || checkingIn {
                RunPlanFlameyBubble(text: "…", typing: true)
            }
        }
    }

    @ViewBuilder
    private func sessionProposal(_ id: String) -> some View {
        if let proposal = store.pendingProposals.first(where: { $0.id == id }) {
            proposalCard(proposal)
        } else if let applied = resolved[id] {
            Label(applied ? "Plan updated" : "Kept your plan", systemImage: applied ? "checkmark.circle.fill" : "arrow.uturn.backward.circle")
                .madFont(size: 12, weight: .heavy, design: .rounded)
                .foregroundColor(applied ? RunPlanColors.green : .white.opacity(0.5))
                .padding(.leading, 32)
        }
    }

    private var waitingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("WAITING FOR YOU")
                .madFont(size: 11, weight: .black, design: .rounded, maxScale: 1.3)
                .tracking(1)
                .foregroundColor(.white.opacity(0.45))
            ForEach(waitingProposals) { proposal in
                proposalCard(proposal)
            }
        }
    }

    private func proposalCard(_ proposal: RunPlanProposal) -> some View {
        RunPlanProposalCard(proposal: proposal, busy: busyProposalId == proposal.id,
                            onApply: { decide(proposal, apply: true) },
                            onDecline: { decide(proposal, apply: false) })
    }

    // MARK: Actions

    private func checkIn(_ feeling: RunPlanFeeling) {
        guard !checkingIn else { return }
        pickedFeeling = feeling
        if feeling == .sore { painFlagged = true }
        thread.append(RunPlanChatItem(kind: .runner("\(feeling.emoji) \(feeling.label)")))
        checkingIn = true
        Task {
            defer { checkingIn = false }
            do {
                let result = try await store.checkIn(feeling: feeling, pain: feeling == .sore ? true : nil)
                thread.append(RunPlanChatItem(kind: .flamey(FlameyCoach.chipReply(for: feeling, proposal: result.proposal))))
                if let p = result.proposal, p.isPending {
                    thread.append(RunPlanChatItem(kind: .proposal(p.id)))
                }
            } catch {
                errorText = RunPlanError.from(error).message
            }
        }
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !sending, let current else { return }
        let history = thread.compactMap { item -> FlameyCoachTurn? in
            switch item.kind {
            case .runner(let t): return FlameyCoachTurn(fromRunner: true, text: t)
            case .flamey(let t): return FlameyCoachTurn(fromRunner: false, text: t)
            case .proposal: return nil
            }
        }
        let context = FlameyCoachContext(today: current.today, week: current.thisWeek, recentRuns: current.recent_runs,
                                         goals: current.plan?.goals ?? [], history: history)
        draft = ""
        thread.append(RunPlanChatItem(kind: .runner(text)))
        sending = true
        Task {
            defer { sending = false }
            guard let reply = await FlameyCoach.respond(to: text, context: context) else {
                let pain = FlameyCoach.mentionsPain(text)
                if pain { painFlagged = true }
                thread.append(RunPlanChatItem(kind: .flamey("I couldn't quite catch that one. The buttons above still adjust your plan.")))
                _ = try? await store.checkIn(feeling: nil, message: text, pain: pain)
                return
            }
            if reply.pain { painFlagged = true }
            thread.append(RunPlanChatItem(kind: .flamey(reply.reply)))
            // The message is the check-in; no feeling, so the server proposes
            // nothing on its own — Flamey's action is the proposal.
            _ = try? await store.checkIn(feeling: nil, message: text, pain: reply.pain)
            guard let action = reply.action else { return }
            do {
                let proposal = try await store.propose(action: action, summary: nil, rationale: reply.reply)
                if proposal.isPending {
                    thread.append(RunPlanChatItem(kind: .proposal(proposal.id)))
                } else if proposal.isApplied {
                    thread.append(RunPlanChatItem(kind: .flamey("Done. Your plan is updated.")))
                }
            } catch {
                thread.append(RunPlanChatItem(kind: .flamey("I couldn't change the plan just now. Try one of the buttons above.")))
            }
        }
    }

    private func decide(_ proposal: RunPlanProposal, apply: Bool) {
        guard busyProposalId == nil else { return }
        busyProposalId = proposal.id
        Task {
            defer { busyProposalId = nil }
            do {
                if apply {
                    try await store.apply(proposal)
                    MADHaptics.success()
                } else {
                    try await store.decline(proposal)
                }
                resolved[proposal.id] = apply
            } catch {
                errorText = RunPlanError.from(error).message
            }
        }
    }
}

// MARK: - Bubbles

struct RunPlanRunnerBubble: View {
    let text: String

    var body: some View {
        HStack {
            Spacer(minLength: 48)
            Text(text)
                .madFont(size: 14, weight: .medium, design: .rounded)
                .foregroundColor(.white)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(UnevenRoundedRectangle(topLeadingRadius: 18, bottomLeadingRadius: 18,
                                                   bottomTrailingRadius: 6, topTrailingRadius: 18, style: .continuous)
                    .fill(RunPlanColors.red))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("You: \(text)")
    }
}

struct RunPlanFlameyBubble: View {
    let text: String
    var typing = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            RunPlanCoachAvatar(size: 24)
            Text(text)
                .madFont(size: 14, weight: .medium, design: .rounded)
                .foregroundColor(.white.opacity(typing ? 0.5 : 0.9))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(UnevenRoundedRectangle(topLeadingRadius: 6, bottomLeadingRadius: 18,
                                                   bottomTrailingRadius: 18, topTrailingRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.07)))
            Spacer(minLength: 24)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(typing ? "Flamey is thinking" : "Flamey: \(text)")
    }
}

// MARK: - Proposal card

struct RunPlanProposalCard: View {
    let proposal: RunPlanProposal
    var busy = false
    var applyTitle = "Swap"
    var declineTitle = "Keep plan"
    let onApply: () -> Void
    let onDecline: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(proposal.isFromClaude ? "CLAUDE SUGGESTS" : "PROPOSED CHANGE")
                .madFont(size: 11, weight: .black, design: .rounded, maxScale: 1.3)
                .tracking(1)
                .foregroundColor(RunPlanColors.gold)
            if let summary = proposal.summary, !summary.isEmpty, proposal.isFromClaude || (proposal.changes ?? []).isEmpty {
                Text(summary)
                    .madFont(size: 13, weight: .semibold, design: .rounded)
                    .foregroundColor(.white)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(proposal.changes ?? [], id: \.local_date) { change in
                changeRow(change)
            }
            if let note = proposal.cap_note, !note.isEmpty {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "shield.fill")
                        .madFont(size: 12, weight: .bold, maxScale: 1.3)
                        .foregroundColor(RunPlanColors.green)
                        .accessibilityHidden(true)
                    Text(note)
                        .madFont(size: 12, weight: .medium, design: .rounded)
                        .foregroundColor(.white.opacity(0.6))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.05)))
            }
            HStack(spacing: 8) {
                Button(action: onDecline) {
                    Text(declineTitle)
                        .madFont(size: 14, weight: .black, design: .rounded, maxScale: 1.4)
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Capsule().fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
                Button(action: onApply) {
                    ZStack {
                        Text(applyTitle)
                            .madFont(size: 14, weight: .black, design: .rounded, maxScale: 1.4)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .opacity(busy ? 0 : 1)
                        if busy { ProgressView().tint(.black) }
                    }
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Capsule().fill(RunPlanColors.orange))
                }
                .buttonStyle(.plain)
            }
            .disabled(busy)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(RunPlanColors.card))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(RunPlanColors.gold.opacity(0.35), lineWidth: 1))
    }

    private func changeRow(_ change: RunPlanChange) -> some View {
        let day = Text(RunPlanFormat.relativeDay(change.local_date))
            .madFont(size: 13, weight: .bold, design: .rounded)
            .foregroundColor(.white.opacity(0.6))
        let fromTo = HStack(spacing: 6) {
            Text(RunPlanFormat.summary(change.before))
                .madFont(size: 13, weight: .medium, design: .rounded)
                .foregroundColor(.white.opacity(0.45))
                .strikethrough(true, color: .white.opacity(0.45))
                .lineLimit(1)
            Image(systemName: "arrow.right")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.white.opacity(0.4))
                .accessibilityHidden(true)
            Text(RunPlanFormat.summary(change.after))
                .madFont(size: 13, weight: .black, design: .rounded)
                .foregroundColor(.white)
                .lineLimit(1)
        }
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                day.frame(width: 84, alignment: .leading)
                fromTo
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading, spacing: 2) {
                day
                fromTo
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(RunPlanFormat.relativeDay(change.local_date)): \(RunPlanFormat.summary(change.before)) becomes \(RunPlanFormat.summary(change.after))")
    }
}
