import SwiftUI

/// Main view for managing competitions
struct CompetitionsListView: View {
    @StateObject private var competitionService = CompetitionService()
    @ObservedObject private var trophyService = TrophyService.shared
    @State private var selectedTab = 0
    @State private var showingCreateCompetition = false
    @State private var selectedCompetition: Competition?
    @State private var showingTrophyCase = false
    @State private var activeExpanded = true
    @State private var waitingExpanded = true
    @State private var finishedExpanded = false

    var body: some View {
        VStack(spacing: 0) {
            // Tab Selector
            tabSelector

            // Content
            Group {
                if selectedTab == 0 {
                    competitionsTab
                        .id("competitions-tab")
                } else {
                    invitesTab
                        .id("invites-tab")
                }
            }
        }
        .background(MADTheme.Colors.appBackgroundGradient)
        .navigationTitle("Competitions")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingCreateCompetition) {
            CreateCompetitionView()
        }
        .sheet(item: $selectedCompetition) { competition in
            NavigationStack {
                CompetitionDetailView(competition: competition, competitionService: competitionService)
            }
        }
        .sheet(isPresented: $showingTrophyCase) {
            NavigationStack {
                TrophyCaseView(trophyService: trophyService)
            }
        }
        .task {
            if competitionService.competitions.isEmpty && competitionService.invites.isEmpty {
                await competitionService.refreshAllData()
            }
            trophyService.updateTrophies(from: competitionService.competitions)
        }
        .refreshable {
            await competitionService.refreshAllData()
            trophyService.updateTrophies(from: competitionService.competitions)
        }
        .onChange(of: showingCreateCompetition) { _, isPresented in
            if !isPresented {
                // Refresh after creating a competition
                Task {
                    await competitionService.refreshAllData()
                }
            }
        }
    }

    // MARK: - Tab Selector
    private var tabSelector: some View {
        HStack {
            HStack(spacing: 0) {
                TabButton(
                    title: "My Competitions",
                    count: competitionService.competitions.count,
                    isSelected: selectedTab == 0,
                    action: { selectedTab = 0 }
                )

                TabButton(
                    title: "Invites",
                    count: competitionService.invites.count,
                    isSelected: selectedTab == 1,
                    action: { selectedTab = 1 }
                )
            }

            Spacer()

            HStack(spacing: MADTheme.Spacing.md) {
                if trophyService.totalCompetitions > 0 {
                    Button(action: { showingTrophyCase = true }) {
                        HStack(spacing: 4) {
                            Image(systemName: "trophy.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [.yellow, .orange],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                            Text("\(trophyService.totalCompetitions)")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundColor(.white.opacity(0.7))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(Color.white.opacity(0.08))
                        )
                    }
                }

                Button(action: { showingCreateCompetition = true }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundColor(MADTheme.Colors.madRed)
                }
            }
        }
        .padding(.horizontal, MADTheme.Spacing.md)
        .padding(.vertical, MADTheme.Spacing.sm)
        .background(Color.clear)
    }

    // MARK: - Competitions Tab
    private var competitionsTab: some View {
        Group {
            if competitionService.isLoading {
                loadingView
            } else if competitionService.competitions.isEmpty {
                ScrollView {
                    CompetitionEmptyStateView(
                        title: "No Competitions Yet",
                        message: "Create a competition to challenge your friends!",
                        systemImage: "trophy",
                        actionTitle: "Create Competition",
                        action: { showingCreateCompetition = true }
                    )
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: MADTheme.Spacing.sm) {
                        // Active section (priority)
                        let activeComps = competitionService.competitions.filter { $0.status == .active }
                        if !activeComps.isEmpty {
                            CollapsibleSection(
                                title: "Active",
                                icon: "bolt.fill",
                                count: activeComps.count,
                                iconColor: .green,
                                isExpanded: $activeExpanded
                            ) {
                                ForEach(activeComps) { competition in
                                    CompetitionCard(competition: competition, action: {
                                        selectedCompetition = competition
                                    })
                                }
                            }
                        }

                        // Waiting to start section
                        let lobbyComps = competitionService.competitions.filter { $0.status == .lobby || $0.status == .scheduled }
                        if !lobbyComps.isEmpty {
                            CollapsibleSection(
                                title: "Waiting to Start",
                                icon: "hourglass",
                                count: lobbyComps.count,
                                iconColor: .orange,
                                isExpanded: $waitingExpanded
                            ) {
                                ForEach(lobbyComps) { competition in
                                    CompetitionCard(competition: competition, action: {
                                        selectedCompetition = competition
                                    })
                                }
                            }
                        }

                        // Finished section
                        let finishedComps = competitionService.competitions.filter { $0.status == .finished }
                        if !finishedComps.isEmpty {
                            CollapsibleSection(
                                title: "Finished",
                                icon: "checkmark.circle",
                                count: finishedComps.count,
                                iconColor: .gray,
                                isExpanded: $finishedExpanded
                            ) {
                                ForEach(finishedComps) { competition in
                                    CompetitionCard(competition: competition, action: {
                                        selectedCompetition = competition
                                    })
                                }
                            }
                        }
                    }
                    .padding(.horizontal, MADTheme.Spacing.md)
                    .padding(.vertical, MADTheme.Spacing.md)
                }
            }
        }
    }

    // MARK: - Invites Tab
    private var invitesTab: some View {
        Group {
            if competitionService.isLoading {
                loadingView
            } else if competitionService.invites.isEmpty {
                ScrollView {
                    CompetitionEmptyStateView(
                        title: "No Invites",
                        message: "You don't have any pending competition invites at the moment.",
                        systemImage: "envelope.open"
                    )
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: MADTheme.Spacing.lg) {
                        ForEach(competitionService.invites) { competition in
                            InviteCard(
                                competition: competition,
                                onAccept: {
                                    handleAcceptInvite(competition)
                                },
                                onDecline: {
                                    handleDeclineInvite(competition)
                                }
                            )
                        }
                    }
                    .padding(.horizontal, MADTheme.Spacing.md)
                    .padding(.vertical, MADTheme.Spacing.lg)
                }
            }
        }
    }

    // MARK: - Loading View
    private var loadingView: some View {
        VStack(spacing: MADTheme.Spacing.lg) {
            ProgressView()
                .scaleEffect(1.5)
                .progressViewStyle(CircularProgressViewStyle(tint: MADTheme.Colors.madRed))

            Text("Loading...")
                .font(MADTheme.Typography.body)
                .foregroundColor(MADTheme.Colors.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helper Methods
    private func handleAcceptInvite(_ competition: Competition) {
        Task {
            do {
                try await competitionService.acceptInvite(competitionId: competition.competition_id)
            } catch {
                print("Error accepting invite: \(error)")
            }
        }
    }

    private func handleDeclineInvite(_ competition: Competition) {
        Task {
            do {
                try await competitionService.declineInvite(competitionId: competition.competition_id)
            } catch {
                print("Error declining invite: \(error)")
            }
        }
    }
}

// MARK: - Collapsible Section

struct CollapsibleSection<Content: View>: View {
    let title: String
    let icon: String
    let count: Int
    let iconColor: Color
    @Binding var isExpanded: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: MADTheme.Spacing.sm) {
            // Tappable header
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: MADTheme.Spacing.sm) {
                    Image(systemName: icon)
                        .font(.caption)
                        .foregroundColor(iconColor)

                    Text(title)
                        .font(MADTheme.Typography.headline)
                        .foregroundColor(.white.opacity(0.85))

                    Text("\(count)")
                        .font(MADTheme.Typography.caption)
                        .foregroundColor(.white.opacity(0.4))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(Color.white.opacity(0.08))
                        )

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white.opacity(0.3))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding(.horizontal, MADTheme.Spacing.sm)
                .padding(.vertical, MADTheme.Spacing.sm)
            }
            .buttonStyle(.plain)

            // Collapsible content
            if isExpanded {
                content()
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.top, MADTheme.Spacing.xs)
    }
}

// MARK: - Empty State View
struct CompetitionEmptyStateView: View {
    let title: String
    let message: String
    let systemImage: String
    var actionTitle: String?
    var action: (() -> Void)?

    @State private var iconScale: CGFloat = 0.8
    @State private var glowOpacity: Double = 0.3

    var body: some View {
        VStack(spacing: MADTheme.Spacing.xl) {
            // Animated icon with glow effect
            ZStack {
                // Outer glow rings
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .stroke(
                            MADTheme.Colors.madRed.opacity(glowOpacity * (0.3 - Double(index) * 0.1)),
                            lineWidth: 2
                        )
                        .frame(width: 140 + CGFloat(index * 20), height: 140 + CGFloat(index * 20))
                        .scaleEffect(iconScale)
                }

                // Icon container
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    MADTheme.Colors.madRed.opacity(0.3),
                                    MADTheme.Colors.madRed.opacity(0.1),
                                    Color.clear
                                ],
                                center: .center,
                                startRadius: 30,
                                endRadius: 70
                            )
                        )
                        .frame(width: 140, height: 140)

                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 100, height: 100)

                    Image(systemName: systemImage)
                        .font(.system(size: 50, weight: .medium))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [MADTheme.Colors.madRed, .orange],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                .scaleEffect(iconScale)
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                    iconScale = 1.1
                    glowOpacity = 0.6
                }
            }

            VStack(spacing: MADTheme.Spacing.md) {
                Text(title)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)

                Text(message)
                    .font(MADTheme.Typography.body)
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, MADTheme.Spacing.lg)
            }

            if let actionTitle = actionTitle, let action = action {
                Button(action: action) {
                    HStack(spacing: MADTheme.Spacing.sm) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                        Text(actionTitle)
                            .font(MADTheme.Typography.callout)
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, MADTheme.Spacing.xl)
                    .padding(.vertical, MADTheme.Spacing.md)
                    .background(
                        RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                            .fill(MADTheme.Colors.primaryGradient)
                            .shadow(color: MADTheme.Colors.madRed.opacity(0.4), radius: 15, x: 0, y: 8)
                    )
                }
                .buttonStyle(ScaleButtonStyle())
            }
        }
        .padding(MADTheme.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    NavigationStack {
        CompetitionsListView()
    }
}
