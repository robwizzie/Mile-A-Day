import SwiftUI

/// Somewhere the tab can be told to scroll to. Push notifications land here.
enum CompeteAnchor: Hashable {
    case invites
}

/// The "Compete" segment — what's live, and how to start something.
///
/// The old tab was a filter bar over one flat list, which meant it had nothing
/// to show until you already had competitions. This is ordered by what a user
/// needs: what's waiting on you, what you're in, what just wrapped, and then
/// how to start something — the full catalogue when you have nothing, one
/// "Start a competition" button (→ `StartCompetitionSheet`) once you do.
///
/// Still a `List` rather than a `ScrollView`: `.swipeActions` (Delete / Edit /
/// Leave) and `.refreshable` only exist here, and `ScrollViewReader` drives the
/// invite anchor either way.
struct CompeteHomeView: View {
    @ObservedObject var competitionService: CompetitionService
    /// Passed in rather than reached for as a singleton, matching
    /// `CompeteRecordView` — both segments share the shell's instance.
    @ObservedObject var trophyService: TrophyService
    /// Set by a `competition_invite` push so the invites section scrolls into
    /// view. Cleared once consumed.
    @Binding var scrollTarget: CompeteAnchor?

    let onOpen: (Competition) -> Void
    let onExplainMode: (CompetitionType) -> Void
    let onStartPreset: (CompetitionPreset) -> Void
    let onCreateBlank: () -> Void
    let onEdit: (Competition) -> Void
    let onError: (String) -> Void
    /// No payload: the shell reads the same shared service when it presents,
    /// so handing it back a copy would just be a second source of truth.
    let onOpenWeekly: () -> Void

    /// The always-on half of the tab: there's a challenge every week whether or
    /// not anyone has started a competition. Defaulted rather than private so
    /// the memberwise init stays internal for the shell to call.
    @ObservedObject var weeklyService: WeeklyChallengeService = .shared

    @State private var pendingDeleteId: String?
    @State private var pendingLeaveId: String?
    /// An invite push arrived for an invite that is no longer pending.
    @State private var showInviteHandledNote = false
    /// The collapsed "Start a competition" button's sheet, and what was picked
    /// in it (acted on after dismissal).
    @State private var showStartSheet = false
    @State private var pendingStart: StartCompetitionSheet.Choice?

    private var currentUserId: String? {
        UserDefaults.standard.string(forKey: "backendUserId")
    }

    /// Live competitions, most urgent first. `TodayFocus` is the app's existing
    /// per-mode "what should I do right now?" model — the dashboard banner and
    /// the home-screen widget already sort by it, so this can't disagree with
    /// them. Ties break on whichever ends soonest.
    ///
    /// The focus key is computed once per competition, not twice per
    /// comparison — same keys, same comparator, same order.
    private var activeCompetitions: [Competition] {
        let userId = currentUserId
        return competitionService.competitions
            .filter { $0.status == .active }
            .map { ($0, TodayFocus.compute(for: $0, currentUserId: userId).level.sortKey) }
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 { return lhs.1 < rhs.1 }
                return (lhs.0.end_date ?? "9999") < (rhs.0.end_date ?? "9999")
            }
            .map(\.0)
    }

    /// Lobbies and scheduled starts — real commitments, but nothing to do yet.
    private var waitingCompetitions: [Competition] {
        competitionService.competitions
            .filter { $0.status == .lobby || $0.status == .scheduled }
    }

    /// Wrapped within the last week. A competition you were watching shouldn't
    /// vanish from the tab the moment it ends — the full history lives in
    /// the History segment.
    private var recentlyFinished: [Competition] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        return competitionService.competitions
            .filter { competition in
                guard competition.status == .finished,
                      let end = competition.endDateFormatted else { return false }
                return end >= cutoff
            }
            .sorted { ($0.end_date ?? "") > ($1.end_date ?? "") }
            .prefix(5)
            .map { $0 }
    }

    private var hasAnyCompetitions: Bool {
        !competitionService.competitions.isEmpty || !competitionService.invites.isEmpty
    }

    var body: some View {
        ScrollViewReader { proxy in
            List {
                let active = activeCompetitions
                if let weekly = weeklyService.current {
                    WeeklyChallengeHeroCard(response: weekly) { onOpenWeekly() }
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 10, leading: 14, bottom: 4, trailing: 14))
                }

                if showInviteHandledNote {
                    inviteHandledNote
                }

                if !competitionService.invites.isEmpty {
                    invitesSection
                }

                if !active.isEmpty {
                    section(title: "Active", icon: "bolt.fill", accent: .green) {
                        ForEach(active, id: \.competition_id) { competition in
                            competitionRow(competition)
                        }
                    }
                }

                if !waitingCompetitions.isEmpty {
                    section(title: "Waiting to start", icon: "hourglass", accent: .orange) {
                        ForEach(waitingCompetitions, id: \.competition_id) { competition in
                            competitionRow(competition)
                        }
                    }
                }

                if !recentlyFinished.isEmpty {
                    recentlyFinishedSection
                }

                startSection

                Color.clear
                    .frame(height: 24)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets())
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            // On the List, not the row: a presentation on a List row can be
            // dropped when the row is recycled.
            .sheet(isPresented: $showStartSheet, onDismiss: runPendingStart) {
                StartCompetitionSheet { pendingStart = $0 }
            }
            .environment(\.defaultMinListRowHeight, 0)
            .refreshable {
                await competitionService.refreshAllData()
                trophyService.updateTrophies(from: competitionService.competitions)
                await weeklyService.refresh()
            }
            .task {
                // The weekly challenge is served on read, so this is also what
                // stamps the user's row for the week if the Sunday cron hasn't.
                await weeklyService.refresh()
            }
            .onChange(of: scrollTarget) { _, _ in
                consumeScrollTarget(proxy)
            }
            // A cold-launch push sets the target while the skeleton is still on
            // screen, so this view doesn't exist yet and `onChange` never
            // fires. Consuming it on appear covers that path.
            .onAppear {
                consumeScrollTarget(proxy)
            }
        }
    }

    /// Scroll to a pending anchor and clear it. Deferred by a frame because on
    /// the appear path the rows haven't been laid out yet, and `scrollTo` on an
    /// id the list doesn't know about is a silent no-op.
    private func consumeScrollTarget(_ proxy: ScrollViewProxy) {
        guard let target = scrollTarget else { return }
        scrollTarget = nil

        // The invite may already have been accepted or declined on another
        // device, in which case there is no section to scroll to and the tap
        // would land on the top of the tab with no explanation.
        if target == .invites && competitionService.invites.isEmpty {
            withAnimation(.easeOut(duration: 0.2)) { showInviteHandledNote = true }
            return
        }

        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.35)) {
                proxy.scrollTo(target, anchor: .top)
            }
        }
    }

    // MARK: - Invites

    private var inviteHandledNote: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.green)

            Text("That invite has already been handled.")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.75))

            Spacer(minLength: 4)

            Button {
                withAnimation(.easeOut(duration: 0.2)) { showInviteHandledNote = false }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white.opacity(0.4))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, MADTheme.Spacing.md)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large, style: .continuous)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large, style: .continuous)
                        .strokeBorder(Color.green.opacity(0.25), lineWidth: 1)
                )
        )
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 12, leading: 14, bottom: 2, trailing: 14))
    }

    private var invitesSection: some View {
        Group {
            header(
                title: competitionService.invites.count == 1 ? "1 invite" : "\(competitionService.invites.count) invites",
                icon: "envelope.fill",
                accent: MADTheme.Colors.madRed
            )
            .id(CompeteAnchor.invites)

            ForEach(competitionService.invites, id: \.competition_id) { competition in
                InviteCard(
                    competition: competition,
                    onAccept: { handleAcceptInvite(competition) },
                    onDecline: { handleDeclineInvite(competition) }
                )
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 6, leading: 14, bottom: 6, trailing: 14))
            }
        }
    }

    // MARK: - Recently finished

    private var recentlyFinishedSection: some View {
        Group {
            header(title: "Just wrapped", icon: "flag.checkered", accent: .white.opacity(0.6))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(recentlyFinished, id: \.competition_id) { competition in
                        FinishedCompetitionRow(competition: competition, compact: true) {
                            onOpen(competition)
                        }
                    }
                }
                .padding(.horizontal, 14)
            }
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 6, trailing: 0))
        }
    }

    // MARK: - Start something

    /// Empty state: the full section — modes, presets, custom — because it is
    /// what teaches the feature. Once the user has competitions it collapses
    /// to ONE "Start a competition" button opening `StartCompetitionSheet`,
    /// which holds every one of those same paths; a tab already carrying live
    /// boards shouldn't scroll through a catalogue under them.
    @ViewBuilder
    private var startSection: some View {
        if hasAnyCompetitions {
            startButton
        } else {
            fullStartSection
        }
    }

    private var startButton: some View {
        Button { showStartSheet = true } label: {
            HStack(spacing: 10) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(MADTheme.Colors.madRed)
                    .accessibilityHidden(true)
                Text("Start a competition")
                    .font(CompeteDesign.name)
                    .foregroundColor(CompeteDesign.ink)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(CompeteDesign.inkFaint)
                    .accessibilityHidden(true)
            }
            .modifier(StartButtonSurface())
            .contentShape(RoundedRectangle(cornerRadius: CompeteDesign.radius, style: .continuous))
        }
        .buttonStyle(ScaleButtonStyle())
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 18, leading: 14, bottom: 4, trailing: 14))
    }

    /// Held until the sheet has finished dismissing: the shell presents the
    /// explainer / create form as sheets of its own, and those can't come up
    /// while this one is still on screen.
    private func runPendingStart() {
        guard let choice = pendingStart else { return }
        pendingStart = nil
        switch choice {
        case .preset(let preset): onStartPreset(preset)
        case .mode(let type): onExplainMode(type)
        case .blank: onCreateBlank()
        }
    }

    private var fullStartSection: some View {
        Group {
            header(
                title: "Start competing",
                icon: "plus.circle.fill",
                accent: MADTheme.Colors.madRed
            )

            Text("Pick a mode to see how it works, or start one of these in a couple of taps.")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 14)
                .padding(.bottom, 4)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets())

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(CompetitionType.allCases, id: \.self) { type in
                        ModeGalleryCard(type: type) { onExplainMode(type) }
                    }
                }
                .padding(.horizontal, 14)
            }
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 10, trailing: 0))

            header(title: "Quick start", icon: "bolt.horizontal.fill", accent: .white.opacity(0.6))

            ForEach(CompetitionPreset.all) { preset in
                PresetCard(preset: preset) { onStartPreset(preset) }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 4, leading: 14, bottom: 4, trailing: 14))
            }

            Button(action: onCreateBlank) {
                HStack(spacing: 6) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 12, weight: .bold))
                    Text("Build a custom competition")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                }
                .foregroundColor(MADTheme.Colors.madRed)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 4, leading: 14, bottom: 4, trailing: 14))
        }
    }

    // MARK: - Rows

    /// A live/waiting competition, or the inline confirmation that has replaced
    /// it while a destructive swipe is pending.
    @ViewBuilder
    private func competitionRow(_ competition: Competition) -> some View {
        Group {
            if pendingDeleteId == competition.competition_id {
                InlineConfirmBanner(
                    title: "Delete \"\(competition.competition_name)\"?",
                    subtitle: "Removes for everyone. Can't be undone.",
                    icon: "trash.fill",
                    confirmLabel: "Delete",
                    accent: .red,
                    onCancel: {
                        withAnimation(.easeOut(duration: 0.2)) { pendingDeleteId = nil }
                    },
                    onConfirm: { performDelete(competition) }
                )
            } else if pendingLeaveId == competition.competition_id {
                InlineConfirmBanner(
                    title: "Leave \"\(competition.competition_name)\"?",
                    subtitle: "You'll be removed from the standings.",
                    icon: "rectangle.portrait.and.arrow.right",
                    confirmLabel: "Leave",
                    accent: .orange,
                    onCancel: {
                        withAnimation(.easeOut(duration: 0.2)) { pendingLeaveId = nil }
                    },
                    onConfirm: { performLeave(competition) }
                )
            } else if competition.status == .active {
                ActiveCompetitionRow(competition: competition) { onOpen(competition) }
            } else {
                // Lobby / scheduled: no standings to lead with yet, so the
                // original card (name, type, participants) still reads best.
                CompetitionCard(competition: competition) { onOpen(competition) }
            }
        }
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 6, leading: 14, bottom: 6, trailing: 14))
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if competition.isOwner {
                Button(role: .destructive) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        pendingLeaveId = nil
                        pendingDeleteId = competition.competition_id
                    }
                } label: {
                    Label("Delete", systemImage: "trash.fill")
                }

                Button {
                    onEdit(competition)
                } label: {
                    Label("Edit", systemImage: "slider.horizontal.3")
                }
                .tint(.blue)
            } else {
                Button(role: .destructive) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        pendingDeleteId = nil
                        pendingLeaveId = competition.competition_id
                    }
                } label: {
                    Label("Leave", systemImage: "rectangle.portrait.and.arrow.right")
                }
            }
        }
    }

    // MARK: - Chrome

    @ViewBuilder
    private func section<Content: View>(
        title: String,
        icon: String,
        accent: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        header(title: title, icon: icon, accent: accent)
        content()
    }

    private func header(title: String, icon: String, accent: Color) -> some View {
        CompeteSectionHeader(title: title, systemImage: icon, accent: accent)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 18, leading: 14, bottom: 4, trailing: 14))
    }

    // MARK: - Actions

    private func handleAcceptInvite(_ competition: Competition) {
        Task {
            do {
                try await competitionService.acceptInvite(competitionId: competition.competition_id)
            } catch {
                onError("Couldn't accept this invite. \(error.localizedDescription)")
            }
        }
    }

    private func handleDeclineInvite(_ competition: Competition) {
        Task {
            do {
                try await competitionService.declineInvite(competitionId: competition.competition_id)
            } catch {
                onError("Couldn't decline this invite. \(error.localizedDescription)")
            }
        }
    }

    private func performDelete(_ competition: Competition) {
        let id = competition.competition_id
        withAnimation(.easeOut(duration: 0.2)) { pendingDeleteId = nil }
        Task { @MainActor in
            do {
                try await competitionService.deleteCompetition(id: id)
            } catch {
                onError("Couldn't delete this competition. \(error.localizedDescription)")
            }
        }
    }

    private func performLeave(_ competition: Competition) {
        guard let userId = currentUserId else {
            withAnimation(.easeOut(duration: 0.2)) { pendingLeaveId = nil }
            onError("You need to be signed in to leave a competition.")
            return
        }
        let competitionId = competition.competition_id
        withAnimation(.easeOut(duration: 0.2)) { pendingLeaveId = nil }
        Task { @MainActor in
            do {
                try await competitionService.removeUser(competitionId: competitionId, userId: userId)
            } catch {
                onError("Couldn't leave this competition. \(error.localizedDescription)")
            }
        }
    }
}

/// `CompeteSurface`'s fill + hairline, as a modifier so the whole card stays
/// the button's tappable label.
private struct StartButtonSurface: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: CompeteDesign.radius, style: .continuous)
                    .fill(CompeteDesign.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: CompeteDesign.radius, style: .continuous)
                    .strokeBorder(CompeteDesign.hairline, lineWidth: 1)
            )
    }
}
