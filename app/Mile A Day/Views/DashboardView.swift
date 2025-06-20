import SwiftUI
import HealthKit

struct DashboardView: View {
    @ObservedObject var healthManager: HealthKitManager
    @ObservedObject var userManager: UserManager
    @ObservedObject var liveWorkoutManager = LiveWorkoutManager.shared
    @EnvironmentObject var notificationService: MADNotificationService
    
    @State private var showConfetti = false
    @State private var showGoalSheet = false
    @State private var newGoalMiles: Double = 1.0
    @State private var isRefreshing = false
    
    // Computed property for total distance including live workout
    private var totalCurrentDistance: Double {
        var total = healthManager.todaysDistance
        if liveWorkoutManager.isWorkoutActive {
            total += liveWorkoutManager.currentWorkoutDistance
        }
        return total
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Live workout indicator (when active)
                    if liveWorkoutManager.isWorkoutActive {
                        LiveWorkoutCard(
                            workoutType: liveWorkoutManager.currentWorkoutType,
                            currentDistance: liveWorkoutManager.currentWorkoutDistance,
                            startTime: liveWorkoutManager.workoutStartTime
                        )
                    }
                    
                    // Streak card
                    StreakCard(streak: userManager.currentUser.streak, 
                              isActiveToday: userManager.currentUser.isStreakActiveToday,
                              isAtRisk: userManager.currentUser.isStreakAtRisk,
                              user: userManager.currentUser)
                    
                    // Today's progress (includes live workout distance)
                    TodayProgressCard(
                        currentDistance: totalCurrentDistance,
                        goalDistance: userManager.currentUser.goalMiles,
                        didComplete: totalCurrentDistance >= userManager.currentUser.goalMiles,
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
            .onChange(of: totalCurrentDistance) { oldValue, newValue in
                let goalMiles = userManager.currentUser.goalMiles
                
                // Show confetti if the user just completed their goal
                if oldValue < goalMiles && newValue >= goalMiles {
                    showConfetti = true
                    
                    // Update user stats with comprehensive HealthKit data
                    userManager.updateUserWithHealthKitData(
                        retroactiveStreak: healthManager.retroactiveStreak,
                        currentMiles: newValue,
                        totalMiles: healthManager.totalLifetimeMiles,
                        fastestPace: healthManager.fastestMilePace, 
                        mostMilesInDay: healthManager.mostMilesInOneDay
                    )
                    
                    // Send a notification only if conditions are met
                    if notificationService.shouldSendCompletionNotification(
                        currentMiles: newValue,
                        goalMiles: goalMiles,
                        previousMiles: oldValue
                    ) {
                        notificationService.sendMileCompletedNotification()
                    }
                }
                
                // Update daily reminder based on current completion status
                notificationService.updateDailyReminder(
                    isCompleted: newValue >= goalMiles,
                    currentMiles: newValue,
                    goalMiles: goalMiles
                )
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
    let user: User
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Image(systemName: "flame.fill")
                    .font(.title2)
                    .foregroundStyle(.orange.gradient)
                Text("Current Streak")
                    .font(.title3.bold())
                Spacer()
                
                // Streak Badge
                Text("\(streak)")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .frame(minWidth: 44)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(isAtRisk ? Color.red.gradient : Color.orange.gradient)
                    )
            }
            
            // Status Section
            VStack(spacing: 12) {
                // Status Icon and Message
                HStack(spacing: 12) {
                    Circle()
                        .fill(isActiveToday ? Color.green : isAtRisk ? Color.red : Color.orange)
                        .frame(width: 8, height: 8)
                    
                    if isActiveToday {
                        Text("Mile Completed Today!")
                            .font(.subheadline.bold())
                            .foregroundColor(.green)
                    } else {
                        Text(isAtRisk ? "Streak at Risk!" : "Keep Your Streak Alive!")
                            .font(.subheadline.bold())
                            .foregroundColor(isAtRisk ? .red : .orange)
                    }
                    
                    Spacer()
                }
                
                // Time Remaining (if not completed)
                if !isActiveToday {
                    HStack {
                        Image(systemName: "clock")
                            .foregroundColor(.secondary)
                        Text(user.formattedTimeUntilReset)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemGray6))
            )
            
            // Motivational Message
            if !isActiveToday {
                Text(isAtRisk ? "Complete your mile soon to keep your \(streak)-day streak!" : "You're on a roll! Keep up the great work!")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
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

// MARK: - Live Workout Card Component

struct LiveWorkoutCard: View {
    let workoutType: HKWorkoutActivityType?
    let currentDistance: Double
    let startTime: Date?
    
    @State private var elapsedTime: TimeInterval = 0
    @State private var timer: Timer?
    
    var body: some View {
        VStack(spacing: 16) {
            // Header with live indicator
            HStack {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 8, height: 8)
                        .scaleEffect(1.0)
                        .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: true)
                    
                    Text("LIVE WORKOUT")
                        .font(.caption.bold())
                        .foregroundColor(.red)
                }
                
                Spacer()
                
                Text(workoutType?.name ?? "Workout")
                    .font(.subheadline.bold())
                    .foregroundColor(.primary)
            }
            
            // Live metrics
            HStack(spacing: 32) {
                // Distance
                VStack(spacing: 4) {
                    Text(String(format: "%.2f", currentDistance))
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                    Text("miles")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                // Duration
                VStack(spacing: 4) {
                    Text(formatDuration(elapsedTime))
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .foregroundColor(.primary)
                    Text("duration")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                // Pace (if distance > 0)
                if currentDistance > 0.01 {
                    VStack(spacing: 4) {
                        Text(formatPace(minutes: elapsedTime / 60 / currentDistance))
                            .font(.system(size: 16, weight: .medium, design: .rounded))
                            .foregroundColor(.primary)
                        Text("pace")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.red.opacity(0.1))
                .stroke(.red.opacity(0.3), lineWidth: 1)
        )
        .onAppear {
            startTimer()
        }
        .onDisappear {
            stopTimer()
        }
    }
    
    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            if let start = startTime {
                elapsedTime = Date().timeIntervalSince(start)
            }
        }
    }
    
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = Int(duration) % 3600 / 60
        let seconds = Int(duration) % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
    
    private func formatPace(minutes: Double) -> String {
        guard minutes > 0 && !minutes.isInfinite else { return "0:00" }
        
        let totalSeconds = Int(minutes * 60)
        let mins = totalSeconds / 60
        let secs = totalSeconds % 60
        
        return String(format: "%d:%02d", mins, secs)
    }
} 