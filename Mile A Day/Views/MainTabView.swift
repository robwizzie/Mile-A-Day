import SwiftUI

struct MainTabView: View {
    @StateObject private var healthManager = HealthKitManager()
    @StateObject private var userManager = UserManager()
    @StateObject private var notificationManager = NotificationManager()
    
    var body: some View {
        TabView {
            NavigationStack {
                DashboardView(healthManager: healthManager, userManager: userManager)
                    .environmentObject(notificationManager)
            }
            .tabItem {
                Label("Dashboard", systemImage: "house.fill")
            }
            
            NavigationStack {
                LeaderboardView(userManager: userManager)
            }
            .tabItem {
                Label("Leaderboard", systemImage: "list.number")
            }
            
            NavigationStack {
                BadgesView(userManager: userManager)
            }
            .tabItem {
                Label("Badges", systemImage: "trophy.fill")
            }
            
            NavigationStack {
                ProfileView(userManager: userManager)
            }
            .tabItem {
                Label("Profile", systemImage: "person.fill")
            }
        }
        .onAppear {
            // Request HealthKit permissions when app launches
            healthManager.requestAuthorization { success in
                if success {
                    healthManager.fetchTodaysDistance()
                    healthManager.fetchRecentWorkouts()
                }
            }
            
            // Request notification permissions
            notificationManager.requestPermission()
            notificationManager.scheduleStreakReminderNotification()
        }
    }
}

// Basic profile view to be expanded later
struct ProfileView: View {
    @ObservedObject var userManager: UserManager
    @State private var isEditingName = false
    @State private var newName = ""
    
    var body: some View {
        VStack(spacing: 20) {
            // Profile header
            VStack(spacing: 15) {
                Image(systemName: "person.circle.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.primary)
                
                if isEditingName {
                    TextField("Your name", text: $newName)
                        .textFieldStyle(.roundedBorder)
                        .padding(.horizontal, 50)
                        .onSubmit {
                            if !newName.isEmpty {
                                userManager.currentUser.name = newName
                                userManager.saveUserData()
                            }
                            isEditingName = false
                        }
                } else {
                    Text(userManager.currentUser.name)
                        .font(.title)
                        .fontWeight(.bold)
                        .onTapGesture {
                            newName = userManager.currentUser.name
                            isEditingName = true
                        }
                }
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(15)
            
            // Stats summary
            VStack(alignment: .leading, spacing: 15) {
                Text("Stats Summary")
                    .font(.headline)
                
                HStack {
                    StatItem(title: "Current Streak", value: "\(userManager.currentUser.streak)", icon: "flame.fill", iconColor: .orange)
                    
                    Divider()
                    
                    StatItem(title: "Total Miles", value: userManager.currentUser.totalMiles.milesFormatted, icon: "map.fill", iconColor: .blue)
                }
                
                Divider()
                
                HStack {
                    StatItem(title: "Personal Record", value: userManager.currentUser.personalRecord.milesFormatted, icon: "trophy.fill", iconColor: .yellow)
                    
                    Divider()
                    
                    StatItem(title: "Badges Earned", value: "\(userManager.currentUser.badges.count)", icon: "star.fill", iconColor: .purple)
                }
            }
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(15)
            .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
            
            Spacer()
        }
        .padding()
        .navigationTitle("Profile")
    }
}

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