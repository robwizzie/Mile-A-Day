import SwiftUI
import HealthKit
import UserNotifications

struct MainTabView: View {
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
                LeaderboardView(userManager: userManager, healthManager: healthManager)
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
                ProfileView(userManager: userManager, healthManager: healthManager)
            }
            .tabItem {
                Label("Profile", systemImage: "person.fill")
            }
        }
        .onAppear {
            // Reset daily notification tracking for new day
            notificationService.resetDailyNotificationTracking()
            
            // Request HealthKit permissions when app launches
            healthManager.requestAuthorization { success in
                if success {
                    healthManager.fetchAllWorkoutData()
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

// Basic profile view to be expanded later
struct ProfileView: View {
    @ObservedObject var userManager: UserManager
    @ObservedObject var healthManager: HealthKitManager
    @State private var isEditingName = false
    @State private var newName = ""
    
    @State private var showingMostMilesDetail = false
    @State private var showingFastestPaceDetail = false
    
    // Helper to format pace in minutes:seconds per mile
    private func formatPace(_ pace: TimeInterval) -> String {
        guard pace > 0 else { return "Not set" }
        
        let totalSeconds = Int(pace * 60)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        
        return String(format: "%d:%02d /mi", minutes, seconds)
    }
    
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
                    Button {
                        showingFastestPaceDetail = true
                    } label: {
                        StatItem(
                            title: "Fastest Mile", 
                            value: formatPace(userManager.currentUser.fastestMilePace), 
                            icon: "hare.fill", 
                            iconColor: .green
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    Divider()
                    
                    Button {
                        showingMostMilesDetail = true
                    } label: {
                        StatItem(
                            title: "Most in One Day", 
                            value: userManager.currentUser.mostMilesInOneDay.milesFormatted, 
                            icon: "calendar.badge.clock", 
                            iconColor: .purple
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(15)
            .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
            
            NavigationLink(destination: NotificationSettingsView()) {
                Text("Notification Settings")
                    .font(.headline)
                    .foregroundColor(Color("appPrimary"))
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color("appSecondary").opacity(0.1))
                    .cornerRadius(12)
            }
            Spacer()
        }
        .padding()
        .navigationTitle("Profile")
        .sheet(isPresented: $showingMostMilesDetail) {
            MostMilesDetailView(miles: userManager.currentUser.mostMilesInOneDay, healthManager: healthManager)
        }
        .sheet(isPresented: $showingFastestPaceDetail) {
            FastestPaceDetailView(pace: userManager.currentUser.fastestMilePace)
        }
    }
}

// Detail view for Most Miles in One Day
struct MostMilesDetailView: View {
    let miles: Double
    @ObservedObject var healthManager: HealthKitManager
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 30) {
                    // Top banner
                    VStack(spacing: 10) {
                        Text("Personal Record")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        
                        Text("Most Miles in One Day")
                            .font(.title)
                            .fontWeight(.bold)
                        
                        Text(miles.milesFormatted)
                            .font(.system(size: 48, weight: .bold, design: .rounded))
                            .foregroundColor(.purple)
                            .padding(.top, 5)
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.purple.opacity(0.1))
                    .cornerRadius(15)
                    
                    // Stats grid
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 20) {
                        StatBox(title: "Distance", value: miles.milesFormatted, icon: "map.fill", color: .purple)
                        StatBox(title: "Steps", value: String(format: "%.0f steps", miles * 2000), icon: "figure.walk", color: .green)
                        StatBox(title: "Calories Burned", value: String(format: "%.0f calories", miles * 100), icon: "flame.fill", color: .orange)
                    }
                    .padding()
                    
                    // Workouts that contributed to the record
                    if !healthManager.mostMilesWorkouts.isEmpty {
                        VStack(alignment: .leading, spacing: 15) {
                            Text("Workouts")
                                .font(.headline)
                            
                            ForEach(healthManager.mostMilesWorkouts, id: \.uuid) { workout in
                                WorkoutRow(workout: workout)
                                    .padding()
                                    .background(Color(.systemBackground))
                                    .cornerRadius(12)
                                    .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
                            }
                        }
                        .padding()
                    }
                    
                    // Tips and achievements
                    VStack(alignment: .leading, spacing: 15) {
                        Text("Achievements")
                            .font(.headline)
                        
                        HStack(spacing: 20) {
                            Image(systemName: "trophy.fill")
                                .font(.largeTitle)
                                .foregroundColor(.yellow)
                            
                            VStack(alignment: .leading) {
                                Text("Distance Record!")
                                    .font(.headline)
                                
                                Text("You've covered \(miles.milesFormatted) in a single day. Amazing achievement!")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding()
                        .background(Color(.systemBackground))
                        .cornerRadius(12)
                        .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
                        
                        // Tips for improving distance
                        HStack(spacing: 20) {
                            Image(systemName: "figure.run")
                                .font(.largeTitle)
                                .foregroundColor(.green)
                            
                            VStack(alignment: .leading) {
                                Text("Build Endurance!")
                                    .font(.headline)
                                
                                Text("Gradually increase your daily distance and incorporate long runs into your training.")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding()
                        .background(Color(.systemBackground))
                        .cornerRadius(12)
                        .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
                    }
                    .padding()
                }
                .padding()
            }
            .navigationTitle("Distance Record")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// Detail view for Fastest Pace
struct FastestPaceDetailView: View {
    let pace: TimeInterval
    @Environment(\.dismiss) private var dismiss
    
    var formattedPace: String {
        guard pace > 0 else { return "Not yet recorded" }
        
        let totalSeconds = Int(pace * 60)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        
        return String(format: "%d:%02d /mi", minutes, seconds)
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 30) {
                    // Top banner
                    VStack(spacing: 10) {
                        Text("Personal Record")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        
                        Text("Fastest Mile Pace")
                            .font(.title)
                            .fontWeight(.bold)
                        
                        Text(formattedPace)
                            .font(.system(size: 48, weight: .bold, design: .rounded))
                            .foregroundColor(.green)
                            .padding(.top, 5)
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(15)
                    
                    // Stats grid
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 20) {
                        StatBox(title: "Pace", value: formattedPace, icon: "hare.fill", color: .green)
                        StatBox(title: "Speed", value: String(format: "%.1f mph", 60 / pace), icon: "speedometer", color: .blue)
                    }
                    .padding()
                    
                    // Tips and achievements
                    VStack(alignment: .leading, spacing: 15) {
                        Text("Achievements")
                            .font(.headline)
                        
                        HStack(spacing: 20) {
                            Image(systemName: "stopwatch.fill")
                                .font(.largeTitle)
                                .foregroundColor(.orange)
                            
                            VStack(alignment: .leading) {
                                Text("Your fastest pace!")
                                    .font(.headline)
                                
                                Text("You've run a mile at \(formattedPace). Great job!")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding()
                        .background(Color(.systemBackground))
                        .cornerRadius(12)
                        .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
                        
                        // Tips for improving pace
                        HStack(spacing: 20) {
                            Image(systemName: "bolt.fill")
                                .font(.largeTitle)
                                .foregroundColor(.yellow)
                            
                            VStack(alignment: .leading) {
                                Text("Improve your pace!")
                                    .font(.headline)
                                
                                Text("Try interval training and tempo runs to increase your speed over time.")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding()
                        .background(Color(.systemBackground))
                        .cornerRadius(12)
                        .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
                    }
                    .padding()
                }
                .padding()
            }
            .navigationTitle("Pace Record")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
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