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
                    StatsGridView(user: userManager.currentUser, healthManager: healthManager)
                    
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
                    
                    // Update user stats with comprehensive HealthKit data
                    userManager.updateUserWithHealthKitData(
                        retroactiveStreak: healthManager.retroactiveStreak,
                        currentMiles: newValue,
                        totalMiles: healthManager.totalLifetimeMiles,
                        fastestPace: healthManager.fastestMilePace, 
                        mostMilesInDay: healthManager.mostMilesInOneDay
                    )
                    
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
        // Fetch all data from HealthKit
        healthManager.fetchAllWorkoutData()
        
        // Use a slight delay to ensure all async HealthKit queries complete
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            // Sync user data with HealthKit data
            userManager.updateUserWithHealthKitData(
                retroactiveStreak: healthManager.retroactiveStreak,
                currentMiles: healthManager.todaysDistance,
                totalMiles: healthManager.totalLifetimeMiles,
                fastestPace: healthManager.fastestMilePace,
                mostMilesInDay: healthManager.mostMilesInOneDay
            )
            
            // Legacy streak update for compatibility
            if healthManager.hasCompletedMileToday() &&
               !userManager.currentUser.isStreakActiveToday {
                userManager.completeRun(miles: healthManager.todaysDistance)
            }
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
    let healthManager: HealthKitManager
    @State private var showFastestPaceDetail = false
    @State private var showMostMilesDetail = false
    
    var formattedFastestPace: String {
        if user.fastestMilePace > 0 {
            let totalSeconds = Int(user.fastestMilePace * 60)
            let minutes = totalSeconds / 60
            let seconds = totalSeconds % 60
            return String(format: "%d:%02d /mi", minutes, seconds)
        }
        return "Not yet recorded"
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your Stats")
                .font(.headline)
            
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 15) {
                StatCard(title: "Total Miles", value: user.totalMiles.milesFormatted, icon: "map.fill")
                
                Button {
                    showFastestPaceDetail = true
                } label: {
                    StatCard(title: "Fastest Mile", value: formattedFastestPace, icon: "hare.fill")
                }
                .buttonStyle(PlainButtonStyle())
                
                Button {
                    showMostMilesDetail = true
                } label: {
                    StatCard(title: "Most in One Day", value: user.mostMilesInOneDay.milesFormatted, icon: "calendar.badge.clock")
                }
                .buttonStyle(PlainButtonStyle())
                
                StatCard(title: "Daily Goal", value: user.goalMiles.milesFormatted, icon: "target")
            }
        }
        .padding()
        .cardStyle()
        .sheet(isPresented: $showFastestPaceDetail) {
            FastestPaceDetailView(pace: user.fastestMilePace)
        }
        .sheet(isPresented: $showMostMilesDetail) {
            MostMilesDetailView(miles: user.mostMilesInOneDay, healthManager: healthManager)
        }
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
    @State private var selectedWorkout: HKWorkout?
    @State private var showDetail = false
    
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
                    Button {
                        selectedWorkout = workout
                        showDetail = true
                    } label: {
                        WorkoutRow(workout: workout)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
        .padding()
        .cardStyle()
        .sheet(isPresented: $showDetail) {
            if let workout = selectedWorkout {
                WorkoutDetailView(workout: workout)
            }
        }
    }
}

// Workout Row Component
struct WorkoutRow: View {
    let workout: HKWorkout
    
    var workoutTypeText: String {
        switch workout.workoutActivityType {
        case .running:
            return "Run"
        case .walking:
            return "Walk"
        default:
            return "Workout"
        }
    }
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(workoutTypeText)
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

// Workout Detail View
struct WorkoutDetailView: View {
    let workout: HKWorkout
    @Environment(\.dismiss) private var dismiss
    @State private var calories: Double?
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 30) {
                    // Top banner
                    VStack(spacing: 10) {
                        Text(workout.workoutActivityType == .running ? "Run" : "Walk")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        
                        Text(workout.formattedDate)
                            .font(.title)
                            .fontWeight(.bold)
                        
                        Text(workout.formattedDistance)
                            .font(.system(size: 48, weight: .bold, design: .rounded))
                            .foregroundColor(.blue)
                            .padding(.top, 5)
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(15)
                    
                    // Stats grid
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 20) {
                        StatBox(title: "Duration", value: workout.formattedDuration, icon: "clock.fill", color: .orange)
                        StatBox(title: "Pace", value: workout.pace, icon: "hare.fill", color: .green)
                        if let calories = calories {
                            StatBox(title: "Calories Burned", value: "\(Int(calories)) calories", icon: "flame.fill", color: .red)
                        }
                        StatBox(title: "Type", value: workout.workoutActivityType == .running ? "Running" : "Walking", icon: "figure.run", color: .purple)
                    }
                    .padding()
                    
                    // Additional details
                    VStack(alignment: .leading, spacing: 15) {
                        Text("Workout Details")
                            .font(.headline)
                        
                        DetailRow(title: "Start Time", value: workout.startDate.formattedTime)
                        DetailRow(title: "End Time", value: workout.endDate.formattedTime)
                        DetailRow(title: "Total Time", value: workout.formattedDuration)
                        DetailRow(title: "Distance", value: workout.formattedDistance)
                        DetailRow(title: "Average Pace", value: workout.pace)
                        if let calories = calories {
                            DetailRow(title: "Calories Burned", value: "\(Int(calories)) calories")
                        }
                    }
                    .padding()
                    .background(Color(.systemBackground))
                    .cornerRadius(12)
                    .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
                }
                .padding()
            }
            .navigationTitle("Workout Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .task {
                await fetchCalories()
            }
        }
    }
    
    private func fetchCalories() async {
        let healthStore = HKHealthStore()
        let energyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!
        
        let predicate = HKQuery.predicateForSamples(
            withStart: workout.startDate,
            end: workout.endDate,
            options: .strictStartDate
        )
        
        let query = HKStatisticsQuery(
            quantityType: energyType,
            quantitySamplePredicate: predicate,
            options: .cumulativeSum
        ) { _, result, error in
            guard let result = result,
                  let sum = result.sumQuantity() else {
                return
            }
            
            let calories = sum.doubleValue(for: HKUnit.kilocalorie())
            DispatchQueue.main.async {
                self.calories = calories
            }
        }
        
        healthStore.execute(query)
    }
}

struct StatBox: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
            
            Text(value)
                .font(.headline)
                .fontWeight(.bold)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
}

struct DetailRow: View {
    let title: String
    let value: String
    
    var body: some View {
        HStack {
            Text(title)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
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