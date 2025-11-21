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
        ZStack(alignment: .bottom) {
            // App-wide gradient background (extends to ALL edges including dynamic island)
            MADTheme.Colors.appBackgroundGradient
                .ignoresSafeArea(.all)

            TabView(selection: $selectedTab) {
                NavigationStack {
                    DashboardView(healthManager: healthManager, userManager: userManager)
                        .environmentObject(notificationService)
                        .background(Color.clear)
                }
                .tag(0)

                NavigationStack {
                    FriendsListView()
                        .background(Color.clear)
                }
                .tag(1)

                NavigationStack {
                    CompetitionsView()
                        .background(Color.clear)
                }
                .tag(2)

                NavigationStack {
                    ProfileView(userManager: userManager, healthManager: healthManager)
                        .environment(\.appStateManager, appStateManager)
                        .background(Color.clear)
                }
                .tag(3)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .background(Color.clear)
            .safeAreaInset(edge: .bottom) {
                // Reserve space for floating tab bar
                Color.clear.frame(height: 80)
            }

            // Apple HIG Floating Liquid Glass Tab Bar
            FloatingTabBar(selectedTab: $selectedTab)
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .preferredColorScheme(.dark)
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

// MARK: - Apple HIG Floating Liquid Glass Tab Bar

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
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        selectedTab = index
                        // Haptic feedback for tab selection
                        let impact = UIImpactFeedbackGenerator(style: .light)
                        impact.impactOccurred()
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background {
            // Liquid glass material with blur
            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.ultraThinMaterial)

                // Subtle highlight gradient for glass effect
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.1),
                                Color.white.opacity(0.05)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                // Border for definition
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.3),
                                Color.white.opacity(0.1)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
            }
        }
        .shadow(color: .black.opacity(0.2), radius: 16, x: 0, y: 8)
        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
    }
}

struct TabBarItem: View {
    let icon: String
    let label: String
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 24, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(
                    isSelected
                        ? AnyShapeStyle(Color(red: 217/255, green: 64/255, blue: 63/255))
                        : AnyShapeStyle(.secondary)
                )
                .scaleEffect(isSelected ? 1.0 : 0.9)

            // Always show label per Apple HIG guidelines
            Text(label)
                .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
                .foregroundColor(
                    isSelected
                        ? Color(red: 217/255, green: 64/255, blue: 63/255)
                        : .secondary
                )
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .animation(.easeInOut(duration: 0.2), value: isSelected)
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