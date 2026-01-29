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

            // Content - Use conditional rendering instead of TabView for better performance
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
        // iOS 26: Liquid Glass is automatic - no toolbar modifiers needed
        .sheet(isPresented: $showingCreateCompetition) {
            CreateCompetitionView()
        }
        .sheet(item: $selectedCompetition) { competition in
            NavigationStack {
                CompetitionDetailView(competition: competition, competitionService: competitionService)
            }
        }
        .task {
            // Only load once when view first appears
            if competitionService.competitions.isEmpty && competitionService.invites.isEmpty {
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
