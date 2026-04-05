import SwiftUI

struct CompetitionDetailView: View {
    @State var competition: Competition
    @ObservedObject var competitionService: CompetitionService
    @Environment(\.dismiss) var dismiss
    @StateObject private var friendService = FriendService()

    @State var showingInviteFriend = false
    @State var showingEditSettings = false
    @State var isStarting = false
    @State var isDeleting = false
    @State var showError = false
    @State var errorMessage = ""
    @State var showDeleteConfirmation = false
    @State var selectedIntervalDate: Date = Date()
    @State var showCelebration = false
    @State var podiumAnimated = false
    @State var heartsAnimated = false
    @State var raceAnimated = false

    // Flex/Nudge state
    @State var showNudgeConfirm = false
    @State var nudgeTargetUser: CompetitionUser?
    @State var isSendingAction = false
    @State var actionFeedback: ActionFeedback?

    // Remove user
    @State var showRemoveConfirmation = false
    @State var removeTargetUser: CompetitionUser?

    // Settings dropdown
    @State var showSettings = false

    // Leaderboard animation
    @State var leaderboardAnimated = false

    // Hero count-up animation
    @State var heroAnimated = false

    var body: some View {
        ZStack {
            MADTheme.Colors.appBackgroundGradient
                .ignoresSafeArea(.all)

            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: MADTheme.Spacing.xl) {
                    // Header (shared across all states)
                    headerSection

                    // Status-specific content
                    switch competition.status {
                    case .lobby, .scheduled:
                        lobbyContent
                    case .active:
                        activeContent
                    case .finished:
                        finishedContent
                    }
                }
                .padding(MADTheme.Spacing.md)
                .padding(.bottom, MADTheme.Spacing.xxl)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .navigationTitle(competition.competition_name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .sheet(isPresented: $showingInviteFriend) {
            InviteFriendView(
                competition: competition,
                competitionService: competitionService,
                friendService: friendService
            )
        }
        .sheet(isPresented: $showingEditSettings) {
            EditCompetitionSettingsView(
                competition: $competition,
                competitionService: competitionService
            )
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
        .confirmationDialog("Delete Competition?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { deleteCompetition() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This action cannot be undone.")
        }
        .alert(
            "Remove \(removeTargetUser?.displayName ?? "user")?",
            isPresented: $showRemoveConfirmation
        ) {
            Button("Remove", role: .destructive) { confirmRemoveUser() }
            Button("Cancel", role: .cancel) { removeTargetUser = nil }
        } message: {
            Text("They will be removed from the competition.")
        }
        .task {
            await refreshCompetition()
        }
        .refreshable {
            await refreshCompetition()
        }
        .onAppear {
            Task {
                await friendService.refreshAllData()
            }
        }
    }

    // MARK: - Header Section
    private var headerSection: some View {
        VStack(spacing: MADTheme.Spacing.lg) {
            // Type icon (compact for active competitions since hero shows status)
            if competition.status != .active {
                Image(systemName: competition.type.icon)
                    .font(.system(size: 60))
                    .foregroundStyle(
                        LinearGradient(
                            colors: competition.type.gradient.map { Color(hex: $0) },
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 120, height: 120)
                    .background(
                        Circle()
                            .fill(Color(hex: competition.type.gradient[0]).opacity(0.15))
                    )
            }

            VStack(spacing: MADTheme.Spacing.sm) {
                HStack(spacing: MADTheme.Spacing.sm) {
                    if competition.status == .active {
                        Image(systemName: competition.type.icon)
                            .font(.system(size: 16))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: competition.type.gradient.map { Color(hex: $0) },
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }

                    Text(competition.type.displayName)
                        .font(MADTheme.Typography.title3)
                        .foregroundColor(.white.opacity(0.7))

                    if competition.isWinner {
                        Image(systemName: "crown.fill")
                            .font(.caption)
                            .foregroundColor(.yellow)
                    }

                    // Status badge
                    HStack(spacing: 4) {
                        Circle()
                            .fill(competition.status.color)
                            .frame(width: 6, height: 6)
                        Text(competition.status.displayName)
                            .font(MADTheme.Typography.caption)
                            .foregroundColor(competition.status.color)
                    }
                    .padding(.horizontal, MADTheme.Spacing.sm)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(competition.status.color.opacity(0.15))
                    )
                }

                if competition.status != .active {
                    Text(competition.type.description)
                        .font(MADTheme.Typography.callout)
                        .foregroundColor(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, MADTheme.Spacing.xl)
                }
            }
        }
    }

    // MARK: - Rank Ordinal Helper
    func rankOrdinal(_ rank: Int) -> String {
        switch rank {
        case 1: return "1st"
        case 2: return "2nd"
        case 3: return "3rd"
        default: return "\(rank)th"
        }
    }
}
