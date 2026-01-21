import SwiftUI
import HealthKit
import UserNotifications

struct MainTabView: View {
    @Environment(\.appStateManager) var appStateManager
    @StateObject private var healthManager = HealthKitManager()
    @StateObject private var userManager = UserManager()
    @StateObject private var notificationService = MADNotificationService.shared
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
            
            Tab("Friends", systemImage: "person.2.fill", value: 1) {
                NavigationStack {
                    FriendsListView()
                }
            }
            
            Tab("Compete", systemImage: "trophy.fill", value: 2) {
                NavigationStack {
                    CompetitionsView()
                }
            }
            
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
