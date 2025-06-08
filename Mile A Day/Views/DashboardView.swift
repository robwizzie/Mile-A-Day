import SwiftUI
import HealthKit

struct DashboardView: View {
    @ObservedObject var healthManager: HealthKitManager
    @ObservedObject var userManager: UserManager
    @EnvironmentObject var notificationManager: NotificationManager
    
    @State private var showConfetti = false
    @State private var showGoalSheet = false
    @State private var newGoalMiles: Double = 1.0
    @State private var isRefreshing = false
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Streak card
                    StreakCard(streak: userManager.currentUser.streak, 
                              isActiveToday: userManager.currentUser.isStreakActiveToday,
                              isAtRisk: userManager.currentUser.isStreakAtRisk)
                    
                    // Today's progress
                    TodayProgressCard(
                        currentDistance: healthManager.todaysDistance,
                        goalDistance: userManager.currentUser.goalMiles,
                        didComplete: healthManager.hasCompletedMileToday(),
                        onRefresh: refreshData
                    )
                    
                    // Stats grid
                    StatsGridView(user: userManager.currentUser)
                    
                    // Recent workouts
                    RecentWorkoutsView(workouts: healthManager.recentWorkouts)
                }
                .padding()
            }
            .refreshable {
                await refreshDataAsync()
            }
            .navigationTitle("Mile A Day")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showGoalSheet = true
                    } label: {
                        Image(systemName: "gear")
                    }
                }
                
                ToolbarItem(placement: .topBarLeading) {
                    if userManager.hasNewBadges {
                        NavigationLink(destination: BadgesView(userManager: userManager)) {
                            Image(systemName: "trophy.fill")
                                .foregroundColor(.yellow)
                        }
                    }
                }
            }
            .onAppear {
                refreshData()
            }
            .sheet(isPresented: $showGoalSheet) {
                GoalSettingSheet(
                    currentGoal: userManager.currentUser.goalMiles,
                    newGoal: $newGoalMiles,
                    onSave: { miles in
                        userManager.setDailyGoal(miles: miles)
                        refreshData()
                    }
                )
            }
            .onChange(of: healthManager.todaysDistance) { oldValue, newValue in
                // Show confetti if the user just completed their goal
                if oldValue < userManager.currentUser.goalMiles && 
                   newValue >= userManager.currentUser.goalMiles {
                    showConfetti = true
                    
                    // Update user stats
                    userManager.completeRun(miles: newValue)
                    
                    // Send a notification
                    notificationManager.scheduleCompletionCongratulationsNotification()
                }
            }
        }
        .confetti(isShowing: $showConfetti)
    }
    
    private func refreshData() {
        isRefreshing = true
        
        // Request authorization if needed
        if !healthManager.isAuthorized {
            healthManager.requestAuthorization { success in
                if success {
                    fetchHealthData()
                }
                isRefreshing = false
            }
        } else {
            fetchHealthData()
            isRefreshing = false
        }
    }
    
    private func refreshDataAsync() async {
        isRefreshing = true
        
        // Create an awaitable wrapper for the authorization request
        if !healthManager.isAuthorized {
            let success = await withCheckedContinuation { continuation in
                healthManager.requestAuthorization { result in
                    continuation.resume(returning: result)
                }
            }
            
            if success {
                fetchHealthData()
            }
        } else {
            fetchHealthData()
        }
        
        isRefreshing = false
    }
    
    private func fetchHealthData() {
        healthManager.fetchTodaysDistance()
        healthManager.fetchRecentWorkouts()
        
        // If the user has completed a run today, update their streak
        if healthManager.hasCompletedMileToday() &&
           !userManager.currentUser.isStreakActiveToday {
            userManager.completeRun(miles: healthManager.todaysDistance)
        }
    }
}

// MARK: - Supporting Components

// Streak Card Component
struct StreakCard: View {
    let streak: Int
    let isActiveToday: Bool
    let isAtRisk: Bool
    
    var body: some View {
        VStack(spacing: 15) {
            HStack {
                Image(systemName: "flame.fill")
                    .foregroundColor(.orange)
                Text("Current Streak")
                    .font(.headline)
                Spacer()
            }
            
            Text("\(streak)")
                .font(.system(size: 50, weight: .bold, design: .rounded))
                .foregroundColor(isAtRisk ? .red : .primary)
            
            Text("\(streak == 1 ? "Day" : "Days")")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            HStack {
                Image(systemName: isActiveToday ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .foregroundColor(isActiveToday ? .green : isAtRisk ? .red : .orange)
                
                Text(isActiveToday ? 
                     "Completed Today!" : 
                     isAtRisk ? "Streak at risk! Complete a mile today!" : "Complete a mile to continue your streak!")
                    .font(.caption)
                    .foregroundColor(isActiveToday ? .green : isAtRisk ? .red : .orange)
            }
        }
        .padding()
        .cardStyle()
    }
}

// Today's Progress Card
struct TodayProgressCard: View {
    let currentDistance: Double
    let goalDistance: Double
    let didComplete: Bool
    let onRefresh: () -> Void
    
    var progress: Double {
        min(currentDistance / goalDistance, 1.0)
    }
    
    var body: some View {
        VStack(spacing: 15) {
            HStack {
                Image(systemName: "figure.run")
                    .foregroundColor(.primary)
                Text("Today's Progress")
                    .font(.headline)
                Spacer()
                
                Button(action: onRefresh) {
                    Image(systemName: "arrow.clockwise")
                        .foregroundColor(.secondary)
                }
            }
            
            ProgressBar(progress: progress)
                .frame(height: 20)
                .padding(.vertical, 5)
            
            HStack {
                Text(currentDistance.milesFormatted)
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("of")
                
                Text(goalDistance.milesFormatted)
                    .font(.title2)
            }
            
            if didComplete {
                Label("Goal complete!", systemImage: "star.fill")
                    .foregroundColor(.green)
                    .font(.subheadline)
            } else {
                Text("\(((goalDistance - currentDistance) * 1609.34).formatted(.number.precision(.fractionLength(0)))) meters to go")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .cardStyle()
    }
}

// Progress Bar Component
struct ProgressBar: View {
    var progress: Double
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: geometry.size.width, height: geometry.size.height)
                
                RoundedRectangle(cornerRadius: 10)
                    .fill(progress < 1.0 ? Color("appPrimary") : Color.green)
                    .frame(width: min(CGFloat(progress) * geometry.size.width, geometry.size.width), height: geometry.size.height)
                    .animation(.easeInOut, value: progress)
            }
        }
    }
}

// Stats Grid Component
struct StatsGridView: View {
    let user: User
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your Stats")
                .font(.headline)
            
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 15) {
                StatCard(title: "Total Miles", value: user.totalMiles.milesFormatted, icon: "map.fill")
                StatCard(title: "Personal Record", value: user.personalRecord.milesFormatted, icon: "trophy.fill")
            }
        }
        .padding()
        .cardStyle()
    }
}

// Stat Card Component
struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(.primary)
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Text(value)
                .font(.headline)
                .foregroundColor(.primary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(10)
    }
}

// Recent Workouts Component
struct RecentWorkoutsView: View {
    let workouts: [HKWorkout]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recent Workouts")
                .font(.headline)
            
            if workouts.isEmpty {
                Text("No recent workouts found")
                    .foregroundColor(.secondary)
                    .padding(.vertical)
            } else {
                ForEach(workouts, id: \.uuid) { workout in
                    WorkoutRow(workout: workout)
                }
            }
        }
        .padding()
        .cardStyle()
    }
}

// Workout Row Component
struct WorkoutRow: View {
    let workout: HKWorkout
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("Run")
                    .font(.headline)
                Text(workout.formattedDate)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 3) {
                Text(workout.formattedDistance)
                    .font(.headline)
                
                Text("\(workout.formattedDuration) (\(workout.pace))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 5)
    }
}

// Goal Setting Sheet
struct GoalSettingSheet: View {
    let currentGoal: Double
    @Binding var newGoal: Double
    let onSave: (Double) -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Daily Goal") {
                    Stepper(value: $newGoal, in: 0.1...26.2, step: 0.1) {
                        HStack {
                            Text("Miles:")
                            Text(newGoal.milesFormatted)
                                .fontWeight(.bold)
                        }
                    }
                }
                
                Section("Common Goals") {
                    Button("1 mile") { newGoal = 1.0 }
                    Button("5K (3.1 miles)") { newGoal = 3.1 }
                    Button("10K (6.2 miles)") { newGoal = 6.2 }
                }
            }
            .navigationTitle("Set Daily Goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(newGoal)
                        dismiss()
                    }
                }
            }
            .onAppear {
                newGoal = currentGoal
            }
        }
    }
} 