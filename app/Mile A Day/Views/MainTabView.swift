import SwiftUI
import HealthKit
import UserNotifications

struct MainTabView: View {
    @Environment(\.appStateManager) var appStateManager
    @StateObject private var healthManager = HealthKitManager()
    @StateObject private var userManager = UserManager.shared
    @StateObject private var notificationService = MADNotificationService.shared
    @StateObject private var competitionService = CompetitionService()
    @StateObject private var friendService = FriendService()
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab = 0

    var body: some View {
        // iOS 26: Use native TabView for automatic Liquid Glass
        TabView(selection: $selectedTab) {
            Tab("Dashboard", systemImage: "house.fill", value: 0) {
                NavigationStack {
                    DashboardView(healthManager: healthManager, userManager: userManager)
                        .environmentObject(notificationService)
                }
            }
            
            Tab("Compete", systemImage: "trophy.fill", value: 1) {
                NavigationStack {
                    CompetitionsView(competitionService: competitionService)
                }
            }
            .badge(competitionService.invites.count)

            Tab("Friends", systemImage: "person.2.fill", value: 2) {
                NavigationStack {
                    FriendsListView(friendService: friendService)
                }
            }
            .badge(friendService.friendRequests.count)
            
            Tab("Profile", systemImage: "person.fill", value: 3) {
                NavigationStack {
                    ProfileView(userManager: userManager, healthManager: healthManager)
                        .environment(\.appStateManager, appStateManager)
                }
            }
        }
        .tint(MADTheme.Colors.madRed)
        .onAppear {
            initializeApp()
            handlePendingNotification()
        }
        .task {
            await competitionService.refreshAllData()
            await friendService.refreshAllData()
        }
        .onReceive(NotificationCenter.default.publisher(for: .didReceivePushNotification)) { notification in
            guard let type = notification.userInfo?["type"] as? String else { return }
            Task {
                switch type {
                case "friend_request":
                    await friendService.refreshAllData()
                case "competition_invite":
                    await competitionService.refreshAllData()
                default:
                    break
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .didTapPushNotification)) { notification in
            guard let type = notification.userInfo?["type"] as? String else { return }
            Task {
                switch type {
                case "friend_request", "friend_request_accepted":
                    await friendService.refreshAllData()
                    selectedTab = 2
                case "competition_invite", "competition_accepted", "competition_started",
                     "competition_finished", "competition_updates", "competition_nudge":
                    await competitionService.refreshAllData()
                    selectedTab = 1
                default:
                    break
                }
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task {
                    await competitionService.refreshAllData()
                    await friendService.refreshAllData()
                }
            }
        }
    }

    // MARK: - Configuration

    private func initializeApp() {
        // Reset daily notification tracking for new day
        notificationService.resetDailyNotificationTracking()

        // Request HealthKit permissions when app launches
        healthManager.requestAuthorization { success in
            if success {
                healthManager.fetchAllWorkoutData()

                // Check for retroactive badges after data is loaded
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                    userManager.checkForRetroactiveBadges()
                }
            }
        }

        // Request notification permissions and schedule smart daily reminder
        Task {
            await notificationService.requestAuthorization()

            // Use smart daily reminder with completion status
            let isCompleted = healthManager.todaysDistance >= userManager.currentUser.goalMiles
            notificationService.updateDailyReminder(
                isCompleted: isCompleted,
                currentMiles: healthManager.todaysDistance,
                goalMiles: userManager.currentUser.goalMiles
            )
        }

        // Sync widget data
        syncWidgetData()
    }

    private func handlePendingNotification() {
        guard let type = notificationService.pendingNotificationType else { return }
        Task {
            switch type {
            case "friend_request", "friend_request_accepted":
                await friendService.refreshAllData()
                selectedTab = 2
            case "competition_invite", "competition_accepted", "competition_started",
                 "competition_finished", "competition_updates", "competition_nudge":
                await competitionService.refreshAllData()
                selectedTab = 1
            default:
                notificationService.pendingNotificationType = nil
            }
        }
    }

    private func syncWidgetData() {
        WidgetDataStore.save(todayMiles: healthManager.todaysDistance, goal: userManager.currentUser.goalMiles)
        WidgetDataStore.save(streak: userManager.currentUser.streak)
    }
}

// MARK: - Stat Item (used by ProfileView)

struct StatItem: View {
    let title: String
    let value: String
    let icon: String
    let iconColor: Color
    
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(iconColor)
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    MainTabView()
}
