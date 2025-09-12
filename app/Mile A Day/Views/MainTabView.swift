import SwiftUI
import HealthKit
import UserNotifications

struct MainTabView: View {
    @Environment(\.appStateManager) var appStateManager
    @StateObject private var healthManager = HealthKitManager()
    @StateObject private var userManager = UserManager()
    @StateObject private var notificationService = MADNotificationService.shared
    
    var body: some View {
        TabView {
            NavigationStack {
                DashboardView(healthManager: healthManager, userManager: userManager)
                    .environmentObject(notificationService)
            }
            .tabItem {
                Label("Dashboard", systemImage: "house.fill")
            }
            
            NavigationStack {
                FriendsListView()
            }
            .tabItem {
                Label("Friends", systemImage: "person.2.fill")
            }
            
            NavigationStack {
                BadgesView(userManager: userManager)
            }
            .tabItem {
                Label("Badges", systemImage: "trophy.fill")
            }
            
            NavigationStack {
                StepsView(healthManager: healthManager, userManager: userManager)
            }
            .tabItem {
                Label("Calendar", systemImage: "calendar")
            }
            
            NavigationStack {
                ProfileView(userManager: userManager, healthManager: healthManager)
                    .environment(\.appStateManager, appStateManager)
            }
            .tabItem {
                Label("Profile", systemImage: "person.fill")
            }
        }
        .accentColor(nil) // Use the app's default accent color
        .background(Color(.systemBackground)) // Ensure background adapts to dark mode
        .onAppear {
            // Configure navigation bar appearance for dark mode
            let appearance = UINavigationBarAppearance()
            appearance.configureWithOpaqueBackground()
            appearance.backgroundColor = UIColor.systemBackground
            appearance.titleTextAttributes = [.foregroundColor: UIColor.label]
            appearance.largeTitleTextAttributes = [.foregroundColor: UIColor.label]
            
            UINavigationBar.appearance().standardAppearance = appearance
            UINavigationBar.appearance().compactAppearance = appearance
            UINavigationBar.appearance().scrollEdgeAppearance = appearance
            
            // Configure tab bar appearance for dark mode
            let tabBarAppearance = UITabBarAppearance()
            tabBarAppearance.configureWithOpaqueBackground()
            tabBarAppearance.backgroundColor = UIColor.systemBackground
            
            UITabBar.appearance().standardAppearance = tabBarAppearance
            UITabBar.appearance().scrollEdgeAppearance = tabBarAppearance
            // Reset daily notification tracking for new day
            notificationService.resetDailyNotificationTracking()
            
            // Request HealthKit permissions when app launches
            healthManager.requestAuthorization { success in
                if success {
                    healthManager.fetchAllWorkoutData()
                    
                    // Check for retroactive badges after data is loaded
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        userManager.checkForRetroactiveBadges()
                    }
                }
            }
            
            // Request notification permissions and schedule smart daily reminder
            Task {
                await notificationService.requestAuthorization()
            }
            
            // Use smart daily reminder with completion status
            let isCompleted = healthManager.todaysDistance >= userManager.currentUser.goalMiles
            notificationService.updateDailyReminder(
                isCompleted: isCompleted,
                currentMiles: healthManager.todaysDistance,
                goalMiles: userManager.currentUser.goalMiles
            )
            
            // Debug: Force widget data update
            print("[Debug] Forcing widget data update - Miles: \(healthManager.todaysDistance), Goal: \(userManager.currentUser.goalMiles), Streak: \(userManager.currentUser.streak)")
                            WidgetDataStore.save(todayMiles: healthManager.todaysDistance, goal: userManager.currentUser.goalMiles)
            WidgetDataStore.save(streak: userManager.currentUser.streak)
        }
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