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
        ZStack {
            TabView(selection: $selectedTab) {
                NavigationStack {
                    DashboardView(healthManager: healthManager, userManager: userManager)
                        .environmentObject(notificationService)
                }
                .tag(0)

                NavigationStack {
                    FriendsListView()
                }
                .tag(1)

                NavigationStack {
                    CompetitionsView()
                }
                .tag(2)

                NavigationStack {
                    ProfileView(userManager: userManager, healthManager: healthManager)
                        .environment(\.appStateManager, appStateManager)
                }
                .tag(3)
            }
            .toolbar(.hidden, for: .tabBar) // Hide default tab bar

            // Custom floating tab bar
            VStack {
                Spacer()
                FloatingTabBar(selectedTab: $selectedTab)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }
        }
        .onAppear {
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
            WidgetDataStore.save(todayMiles: healthManager.todaysDistance, goal: userManager.currentUser.goalMiles)
            WidgetDataStore.save(streak: userManager.currentUser.streak)
        }
    }
}

// MARK: - Floating Tab Bar

struct FloatingTabBar: View {
    @Binding var selectedTab: Int
    @Environment(\.colorScheme) var colorScheme

    let tabs: [(icon: String, label: String)] = [
        ("house.fill", "Dashboard"),
        ("person.2.fill", "Friends"),
        ("trophy.fill", "Competitions"),
        ("person.fill", "Profile")
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<tabs.count, id: \.self) { index in
                TabBarItem(
                    icon: tabs[index].icon,
                    label: tabs[index].label,
                    isSelected: selectedTab == index
                )
                .onTapGesture {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        selectedTab = index
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 12)
        .background(
            ZStack {
                // Liquid glass material
                RoundedRectangle(cornerRadius: 24)
                    .fill(.ultraThinMaterial)

                // Subtle gradient overlay
                RoundedRectangle(cornerRadius: 24)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(colorScheme == .dark ? 0.05 : 0.1),
                                Color.clear
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                // Border stroke
                RoundedRectangle(cornerRadius: 24)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(colorScheme == .dark ? 0.2 : 0.3),
                                Color.white.opacity(colorScheme == .dark ? 0.1 : 0.15)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.5
                    )
            }
        )
        .shadow(color: .black.opacity(0.15), radius: 20, x: 0, y: 10)
        .overlay(
            // Inner shadow for depth
            RoundedRectangle(cornerRadius: 24)
                .stroke(Color.black.opacity(0.05), lineWidth: 1)
                .blur(radius: 1)
                .offset(y: 1)
                .mask(RoundedRectangle(cornerRadius: 24))
        )
    }
}

struct TabBarItem: View {
    let icon: String
    let label: String
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(
                    isSelected ?
                        LinearGradient(
                            colors: [Color(red: 217/255, green: 64/255, blue: 63/255), Color(red: 217/255, green: 64/255, blue: 63/255).opacity(0.8)],
                            startPoint: .top,
                            endPoint: .bottom
                        ) :
                        LinearGradient(
                            colors: [.secondary, .secondary],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                )
                .scaleEffect(isSelected ? 1.1 : 1.0)

            Text(label)
                .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
                .foregroundColor(isSelected ? Color(red: 217/255, green: 64/255, blue: 63/255) : .secondary)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
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