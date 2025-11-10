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
    @Namespace private var tabSelection

    let tabs: [(icon: String, label: String)] = [
        ("house.fill", "Dashboard"),
        ("person.2.fill", "Friends"),
        ("trophy.fill", "Competitions"),
        ("person.fill", "Profile")
    ]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<tabs.count, id: \.self) { index in
                TabSegmentItem(
                    icon: tabs[index].icon,
                    label: tabs[index].label,
                    isSelected: selectedTab == index,
                    namespace: tabSelection
                )
                .onTapGesture {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                        selectedTab = index
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(6)
        .background(
            ZStack {
                // Liquid glass material background
                Capsule()
                    .fill(.ultraThinMaterial)

                // Subtle gradient overlay
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(colorScheme == .dark ? 0.03 : 0.08),
                                Color.clear
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                // Border stroke
                Capsule()
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(colorScheme == .dark ? 0.15 : 0.25),
                                Color.white.opacity(colorScheme == .dark ? 0.08 : 0.12)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.5
                    )
            }
        )
        .shadow(color: .black.opacity(0.12), radius: 16, x: 0, y: 8)
        .overlay(
            // Inner shadow for depth
            Capsule()
                .stroke(Color.black.opacity(0.04), lineWidth: 1)
                .blur(radius: 0.5)
                .offset(y: 1)
                .mask(Capsule())
        )
    }
}

struct TabSegmentItem: View {
    let icon: String
    let label: String
    let isSelected: Bool
    let namespace: Namespace.ID
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        ZStack {
            // Sliding background indicator for selected tab
            if isSelected {
                Capsule()
                    .fill(
                        colorScheme == .dark ?
                            Color.white.opacity(0.15) :
                            Color.white.opacity(0.8)
                    )
                    .matchedGeometryEffect(id: "selectedTab", in: namespace)
                    .shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 2)
            }

            // Tab content
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: isSelected ? .semibold : .medium))
                    .foregroundColor(
                        isSelected ?
                            Color(red: 217/255, green: 64/255, blue: 63/255) :
                            (colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.6))
                    )

                if isSelected {
                    Text(label)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color(red: 217/255, green: 64/255, blue: 63/255))
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, isSelected ? 16 : 12)
            .padding(.vertical, 10)
        }
        .contentShape(Capsule())
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