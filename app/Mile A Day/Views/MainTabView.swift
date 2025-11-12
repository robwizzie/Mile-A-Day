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
        TabView(selection: $selectedTab) {
            NavigationStack {
                DashboardView(healthManager: healthManager, userManager: userManager)
                    .environmentObject(notificationService)
            }
            .tabItem {
                Label("Dashboard", systemImage: "house.fill")
            }
            .tag(0)

            NavigationStack {
                FriendsListView()
            }
            .tabItem {
                Label("Friends", systemImage: "person.2.fill")
            }
            .tag(1)

            NavigationStack {
                CompetitionsView()
            }
            .tabItem {
                Label("Competitions", systemImage: "trophy.fill")
            }
            .tag(2)

            NavigationStack {
                ProfileView(userManager: userManager, healthManager: healthManager)
                    .environment(\.appStateManager, appStateManager)
            }
            .tabItem {
                Label("Profile", systemImage: "person.fill")
            }
            .tag(3)
        }
        // Apply liquid glass material to tab bar (iOS 18+ HIG)
        .toolbarBackground(.ultraThinMaterial, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .toolbarColorScheme(.dark, for: .tabBar)
        .tint(Color(red: 217/255, green: 64/255, blue: 63/255)) // MAD red for selected items
        .onAppear {
            configureTabBarAppearance()
            initializeApp()
        }
    }

    // MARK: - Configuration

    private func configureTabBarAppearance() {
        // Configure UITabBar appearance for enhanced liquid glass effect
        let appearance = UITabBarAppearance()
        appearance.configureWithDefaultBackground()

        // Apply subtle background effect
        appearance.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.8)

        // Selected item color (MAD red)
        let selectedColor = UIColor(red: 217/255, green: 64/255, blue: 63/255, alpha: 1.0)
        appearance.stackedLayoutAppearance.selected.iconColor = selectedColor
        appearance.stackedLayoutAppearance.selected.titleTextAttributes = [
            .foregroundColor: selectedColor,
            .font: UIFont.systemFont(ofSize: 10, weight: .semibold)
        ]

        // Unselected item color (secondary gray)
        let unselectedColor = UIColor.secondaryLabel
        appearance.stackedLayoutAppearance.normal.iconColor = unselectedColor
        appearance.stackedLayoutAppearance.normal.titleTextAttributes = [
            .foregroundColor: unselectedColor,
            .font: UIFont.systemFont(ofSize: 10, weight: .regular)
        ]

        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }

    private func initializeApp() {
        // Reset daily notification tracking for new day
        notificationService.resetDailyNotificationTracking()

        // Request HealthKit permissions when app launches
        healthManager.requestAuthorization { success in
            if success {
                healthManager.fetchAllWorkoutData()

                // Check for retroactive badges after data is loaded
                // Using Task instead of DispatchQueue for better performance
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

// ProfileView moved to separate file

// MostMilesDetailView moved to separate file

// FastestPaceDetailView moved to separate file

// Stat item for profile view
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