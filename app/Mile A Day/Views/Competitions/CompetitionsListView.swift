import SwiftUI

/// The Compete tab.
///
/// A shell: a header, a two-way segment picker, and the two content views.
/// It used to be a 970-line list with its own filter bar (All / Active /
/// Waiting / Finished) layered on top of a My Comps / Invites segment — two
/// overlapping ways to slice the same rows, neither of which gave the tab
/// anything to show before you had competitions.
///
/// Now: **Compete** is what's live and how to start something, **Record** is
/// your wins and losses. Invites are a section inside Compete rather than a
/// segment that's empty almost always.
struct CompetitionsListView: View {
    @ObservedObject var competitionService: CompetitionService
    @ObservedObject private var trophyService = TrophyService.shared

    @State private var selectedSegment: CompeteSegment = .compete
    /// Set when a `competition_invite` push wants the invites section on
    /// screen; `CompeteHomeView` consumes and clears it.
    @State private var scrollTarget: CompeteAnchor?

    @State private var createRequest: CreateRequest?
    @State private var explainerType: CompetitionType?
    /// The mode the explainer asked to start, held until that sheet has
    /// finished dismissing — presenting the create sheet while another is
    /// still going away drops one of them.
    @State private var pendingStartType: CompetitionType?

    @State private var selectedCompetition: Competition?
    @State private var showingTrophyCase = false
    @State private var competitionToEdit: Competition?
    @State private var actionError: String?

    @Environment(\.scenePhase) private var scenePhase

    enum CompeteSegment: Hashable { case compete, record }

    /// What to open the create sheet with. One item-driven sheet rather than a
    /// booleans-plus-payload pair, which races to a stale nil.
    struct CreateRequest: Identifiable {
        let id = UUID()
        // Defaulted so the three entry points can each name only what they
        // care about: blank, a preset, or a mode from the explainer.
        var preset: CompetitionPreset? = nil
        var type: CompetitionType? = nil
    }

    var body: some View {
        VStack(spacing: 0) {
            MADTabHeader(title: "Compete", actions: headerActions)

            MADPillPicker(
                selection: $selectedSegment,
                options: [
                    .init(
                        id: .compete,
                        title: "Compete",
                        systemImage: "bolt.fill",
                        badgeCount: competitionService.invites.count
                    ),
                    .init(
                        id: .record,
                        title: "Record",
                        systemImage: "trophy.fill",
                        badgeCount: 0
                    )
                ]
            )
            .padding(.horizontal, MADTheme.Spacing.md)
            .padding(.top, MADTheme.Spacing.xs)
            .padding(.bottom, MADTheme.Spacing.sm)

            Group {
                switch selectedSegment {
                case .compete:
                    // Skeletons only while there is genuinely nothing to show.
                    // Keying on isLoading alone swapped the live list out on
                    // every background refresh, which also cancelled
                    // pull-to-refresh mid-flight.
                    if competitionService.competitions.isEmpty
                        && competitionService.invites.isEmpty
                        && !competitionService.hasLoadedOnce {
                        loadingView
                    } else {
                        CompeteHomeView(
                            competitionService: competitionService,
                            trophyService: trophyService,
                            scrollTarget: $scrollTarget,
                            onOpen: { selectedCompetition = $0 },
                            onExplainMode: { explainerType = $0 },
                            onStartPreset: { createRequest = CreateRequest(preset: $0) },
                            onCreateBlank: { createRequest = CreateRequest() },
                            onEdit: { competitionToEdit = $0 },
                            onError: { actionError = $0 }
                        )
                        .id("compete-segment")
                    }
                case .record:
                    CompeteRecordView(
                        competitionService: competitionService,
                        trophyService: trophyService,
                        onOpen: { selectedCompetition = $0 },
                        onOpenTrophyCase: { showingTrophyCase = true }
                    )
                    .id("record-segment")
                }
            }
            // Deliberately attached HERE and not to the VStack below: stacking
            // every presentation on one node is how a sheet silently fails to
            // show. The two content-driven ones live on the content.
            .sheet(item: $explainerType, onDismiss: {
                guard let type = pendingStartType else { return }
                pendingStartType = nil
                createRequest = CreateRequest(type: type)
            }) { type in
                NavigationStack {
                    ModeExplainerSheet(type: type) { started in
                        // Held rather than acted on: the create sheet can't be
                        // presented until this one has finished dismissing.
                        pendingStartType = started
                    }
                }
            }
            .sheet(item: $competitionToEdit) { competition in
                EditCompetitionWrapper(initial: competition, service: competitionService)
            }
        }
        .background(MADTheme.Colors.appBackgroundGradient)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $createRequest) { request in
            CreateCompetitionView(
                onCreated: { createdId in
                    Task {
                        await competitionService.refreshAllData()
                        if let competition = competitionService.competitions.first(where: { $0.id == createdId }) {
                            selectedCompetition = competition
                        }
                    }
                },
                preset: request.preset,
                initialType: request.type,
                // A preset has already answered every option, so the only
                // question left is who to invite.
                startsCollapsed: request.preset != nil
            )
        }
        .sheet(item: $selectedCompetition) { competition in
            NavigationStack {
                CompetitionDetailView(competition: competition, competitionService: competitionService)
            }
        }
        .sheet(isPresented: $showingTrophyCase) {
            NavigationStack {
                TrophyCaseView(trophyService: trophyService, competitionService: competitionService)
            }
        }
        .alert("Couldn't complete action", isPresented: Binding(
            get: { actionError != nil },
            set: { if !$0 { actionError = nil } }
        )) {
            Button("OK", role: .cancel) { actionError = nil }
        } message: {
            Text(actionError ?? "")
        }
        .task {
            // Cold-launch deep link. Separate code path from the live tap
            // below — dropping either silently kills the push for that case.
            if MADNotificationService.shared.pendingNotificationType == "competition_invite" {
                focusInvites()
                MADNotificationService.shared.pendingNotificationType = nil
            }
        }
        .onAppear {
            Task {
                await competitionService.refreshAllData()
                trophyService.updateTrophies(from: competitionService.competitions)
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            Task {
                await competitionService.refreshAllData()
                trophyService.updateTrophies(from: competitionService.competitions)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .didTapPushNotification)) { notification in
            guard let type = notification.userInfo?["type"] as? String else { return }
            if type == "competition_invite" {
                focusInvites()
            }
        }
        .onChange(of: createRequest?.id) { _, _ in
            // Refresh after the create sheet closes.
            guard createRequest == nil else { return }
            Task { await competitionService.refreshAllData() }
        }
    }

    /// Put the invites section on screen. The Invites segment no longer
    /// exists, so an invite push selects Compete and scrolls to the section —
    /// which renders an "already handled" note when the invite was accepted on
    /// another device, rather than scrolling to nothing.
    private func focusInvites() {
        selectedSegment = .compete
        scrollTarget = .invites
    }

    // MARK: - Header Actions

    private var headerActions: [MADHeaderAction] {
        var actions: [MADHeaderAction] = []
        if trophyService.wins > 0 {
            // Achievement style: gold pill with the win count. Reads as a flex,
            // not an alert — distinct from notification-style red badges.
            actions.append(
                MADHeaderAction(
                    id: "record",
                    systemImage: "trophy.fill",
                    style: .achievement(count: trophyService.wins)
                ) { selectedSegment = .record }
            )
        }
        // CTA style: filled red circle so "create new competition" stands out
        // as the primary action on the page.
        actions.append(
            MADHeaderAction(
                id: "create",
                systemImage: "plus",
                style: .cta
            ) { createRequest = CreateRequest() }
        )
        return actions
    }

    // MARK: - Loading View
    /// Skeleton card list — mirrors the Friends-home loading state so both
    /// tabs share the same perceived-performance treatment instead of a bare
    /// spinner. Renders 3 placeholder competition cards while the real list
    /// fetches.
    private var loadingView: some View {
        ScrollView {
            VStack(spacing: MADTheme.Spacing.md) {
                ForEach(0..<3, id: \.self) { _ in competitionSkeletonCard }
            }
            .padding(.horizontal, MADTheme.Spacing.md)
            .padding(.top, MADTheme.Spacing.md)
        }
        .scrollIndicators(.hidden)
    }

    private var competitionSkeletonCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: MADTheme.Spacing.md) {
                Circle()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 48, height: 48)
                    .shimmer()
                VStack(alignment: .leading, spacing: 6) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 140, height: 14)
                        .shimmer()
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.06))
                        .frame(width: 80, height: 10)
                        .shimmer()
                }
                Spacer()
            }
            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { _ in
                    Capsule()
                        .fill(Color.white.opacity(0.06))
                        .frame(width: 60, height: 24)
                        .shimmer()
                }
                Spacer()
            }
            HStack(spacing: -8) {
                ForEach(0..<3, id: \.self) { _ in
                    Circle()
                        .fill(Color.white.opacity(0.06))
                        .frame(width: 28, height: 28)
                        .overlay(Circle().strokeBorder(MADTheme.Colors.madBlack, lineWidth: 2))
                        .shimmer()
                }
                Spacer()
                Capsule()
                    .fill(Color.white.opacity(0.06))
                    .frame(width: 80, height: 22)
                    .shimmer()
            }
        }
        .padding(MADTheme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
                )
        )
    }
}

/// `sheet(item:)` needs an identity for the mode being explained.
extension CompetitionType: Identifiable {
    var id: String { rawValue }
}

// MARK: - Inline Confirm Banner

/// Replaces the row's card with an inline confirmation prompt when a destructive
/// swipe action fires. No detached popup — the confirmation lives in the row.
struct InlineConfirmBanner: View {
    let title: String
    let subtitle: String
    let icon: String
    let confirmLabel: String
    let accent: Color
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(accent)
                .frame(width: 36, height: 36)
                .background(
                    Circle()
                        .fill(accent.opacity(0.18))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(subtitle)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.62))
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            Button(action: onCancel) {
                Text("Cancel")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.75))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        Capsule().fill(Color.white.opacity(0.1))
                    )
            }
            .buttonStyle(.plain)

            Button(action: onConfirm) {
                Text(confirmLabel)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [accent, accent.opacity(0.82)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .shadow(color: accent.opacity(0.45), radius: 6, x: 0, y: 3)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                        .fill(Color.black.opacity(0.2))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                        .strokeBorder(accent.opacity(0.45), lineWidth: 1.5)
                )
                .shadow(color: accent.opacity(0.25), radius: 10, x: 0, y: 6)
        )
        .transition(.asymmetric(
            insertion: .scale(scale: 0.96).combined(with: .opacity),
            removal: .opacity
        ))
    }
}

// MARK: - Edit Competition Wrapper
// `EditCompetitionSettingsView` needs a `Binding<Competition>`; this wrapper owns
// the mutable state so we can present the edit sheet inline from a swipe action.

struct EditCompetitionWrapper: View {
    @State private var competition: Competition
    let service: CompetitionService

    init(initial: Competition, service: CompetitionService) {
        _competition = State(initialValue: initial)
        self.service = service
    }

    var body: some View {
        EditCompetitionSettingsView(
            competition: $competition,
            competitionService: service
        )
        // Form sheet — an accidental slide-down would silently discard edits.
        // Cancel/Save in the toolbar are the explicit exits.
        .interactiveDismissDisabled()
    }
}

#Preview {
    NavigationStack {
        CompetitionsListView(competitionService: CompetitionService())
    }
}
