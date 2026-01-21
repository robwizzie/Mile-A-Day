import SwiftUI

/// Main view for managing competitions
struct CompetitionsListView: View {
    @StateObject private var competitionService = CompetitionService()
    @State private var selectedTab = 0
    @State private var showingCreateCompetition = false
    @State private var selectedCompetition: Competition?

    var body: some View {
        VStack(spacing: 0) {
            // Tab Selector
            tabSelector

            // Content
            TabView(selection: $selectedTab) {
                // Competitions Tab
                competitionsTab
                    .tag(0)

                // Invites Tab
                invitesTab
                    .tag(1)
            }
            .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
        }
        .background(MADTheme.Colors.appBackgroundGradient)
        .navigationTitle("Competitions")
        .navigationBarTitleDisplayMode(.inline)
        // iOS 26: Liquid Glass is automatic - no toolbar modifiers needed
        .sheet(isPresented: $showingCreateCompetition) {
            CreateCompetitionView()
        }
        .sheet(item: $selectedCompetition) { competition in
            NavigationStack {
                CompetitionDetailView(competition: competition, competitionService: competitionService)
            }
        }
        .onAppear {
            Task {
                await competitionService.refreshAllData()
            }
        }
        .refreshable {
            await competitionService.refreshAllData()
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
                    action: { withAnimation { selectedTab = 0 } }
                )

                TabButton(
                    title: "Invites",
                    count: competitionService.invites.count,
                    isSelected: selectedTab == 1,
                    action: { withAnimation { selectedTab = 1 } }
                )
            }

            Spacer()

            Button(action: { showingCreateCompetition = true }) {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
                    .foregroundColor(MADTheme.Colors.madRed)
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
                CompetitionEmptyStateView(
                    title: "No Competitions Yet",
                    message: "Create a competition to challenge your friends!",
                    systemImage: "trophy",
                    actionTitle: "Create Competition",
                    action: { showingCreateCompetition = true }
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: MADTheme.Spacing.md) {
                        ForEach(competitionService.competitions) { competition in
                            CompetitionCard(
                                competition: competition,
                                action: {
                                    selectedCompetition = competition
                                }
                            )
                        }
                    }
                    .padding(MADTheme.Spacing.md)
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
                CompetitionEmptyStateView(
                    title: "No Invites",
                    message: "You don't have any pending competition invites at the moment.",
                    systemImage: "envelope.open"
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: MADTheme.Spacing.md) {
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
                    .padding(MADTheme.Spacing.md)
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
                // Handle error - could show an alert here
                print("Error accepting invite: \(error)")
            }
        }
    }

    private func handleDeclineInvite(_ competition: Competition) {
        Task {
            do {
                try await competitionService.declineInvite(competitionId: competition.competition_id)
            } catch {
                // Handle error
                print("Error declining invite: \(error)")
            }
        }
    }
}

// MARK: - Empty State View
struct CompetitionEmptyStateView: View {
    let title: String
    let message: String
    let systemImage: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: MADTheme.Spacing.xl) {
            Image(systemName: systemImage)
                .font(.system(size: 60))
                .foregroundStyle(
                    LinearGradient(
                        colors: [MADTheme.Colors.madRed, .orange],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .padding(MADTheme.Spacing.xl)
                .background(
                    Circle()
                        .fill(.ultraThinMaterial)
                )

            VStack(spacing: MADTheme.Spacing.sm) {
                Text(title)
                    .font(MADTheme.Typography.title2)
                    .foregroundColor(.white)

                Text(message)
                    .font(MADTheme.Typography.body)
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
            }

            if let actionTitle = actionTitle, let action = action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(MADTheme.Typography.callout)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .padding(.horizontal, MADTheme.Spacing.xl)
                        .padding(.vertical, MADTheme.Spacing.md)
                        .background(
                            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.pill)
                                .fill(MADTheme.Colors.primaryGradient)
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
