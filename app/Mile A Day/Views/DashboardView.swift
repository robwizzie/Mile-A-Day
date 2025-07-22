import SwiftUI
import HealthKit
import WidgetKit

struct DashboardView: View {
    @ObservedObject var healthManager: HealthKitManager
    @ObservedObject var userManager: UserManager

    @EnvironmentObject var notificationService: MADNotificationService
    
    @State private var showConfetti = false
    @State private var showGoalSheet = false
    @State private var newGoalMiles: Double = 1.0
    @State private var isRefreshing = false
    
    @State private var showInstructions = false
    
    // Enhanced state calculation with day awareness
    private var currentState: (baseMiles: Double, totalDistance: Double, goal: Double, progress: Double, isCompleted: Bool, isToday: Bool) {
        let storeState = WidgetDataStore.getCurrentState()
        return (storeState.baseMiles, storeState.totalDistance, storeState.goal, storeState.progress, storeState.isCompleted, storeState.isToday)
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Instructions Card (prominent at top)
                    InstructionsCard(showFullInstructions: $showInstructions)
                    
                    // Simplified Streak card
                    StreakCard(
                        streak: userManager.currentUser.streak, 
                        isActiveToday: userManager.currentUser.isStreakActiveToday,
                        isAtRisk: userManager.currentUser.isStreakAtRisk,
                        user: userManager.currentUser,
                        progress: currentState.progress,
                        isGoalCompleted: currentState.isCompleted
                    )
                    
                    // Simplified Today's progress
                    TodayProgressCard(
                        currentDistance: currentState.totalDistance,
                        goalDistance: currentState.goal,
                        progress: currentState.progress,
                        didComplete: currentState.isCompleted,
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
                
                // Check if widgets need refresh and force sync if needed
                if WidgetDataStore.needsRefresh() {
                    WidgetDataStore.forceWidgetSync()
                }
            }
            .sheet(isPresented: $showGoalSheet) {
                GoalSettingSheet(
                    currentGoal: userManager.currentUser.goalMiles,
                    newGoal: $newGoalMiles,
                    onSave: { miles in
                        userManager.setDailyGoal(miles: miles)
                        updateWidgetData()
                        refreshData()
                    }
                )
            }
            .onChange(of: currentState.totalDistance) { oldValue, newValue in
                let goalMiles = currentState.goal
                
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
                
                // Ensure widget data is always synchronized
                updateWidgetData()
            }
            .onChange(of: currentState.isCompleted) { _, completed in
                if completed && !showConfetti {
                    triggerGoalCompletedCelebration()
                }
            }
            .sheet(isPresented: $showInstructions) {
                FullInstructionsView()
            }
        }
        .confetti(isShowing: $showConfetti)
        .overlay(
            // Development version indicator (top-right corner)
            VStack {
                HStack {
                    Spacer()
                    Text(getVersionString())
                        .font(.caption2)
                        .foregroundColor(.secondary.opacity(0.6))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(8)
                        .padding(.trailing, 16)
                        .padding(.top, 8)
                }
                Spacer()
            }
        )
    }
    
    private func getVersionString() -> String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "v\(version).\(build)"
    }
    
    private func updateWidgetData() {
        let state = currentState
        WidgetDataStore.save(
            todayMiles: state.baseMiles,
            goal: state.goal,
            forceRefresh: state.isCompleted // Force refresh when goal completed
        )
        WidgetDataStore.save(streak: userManager.currentUser.streak)
    }
    
    private func triggerGoalCompletedCelebration() {
        withAnimation {
            showConfetti = true
        }
        
        notificationService.sendMileCompletedNotification()
        userManager.updateStreakForCompletion()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            showConfetti = false
        }
    }
    
    private func refreshData() {
        isRefreshing = true
        
        // Request authorization if needed
        if !healthManager.isAuthorized {
            healthManager.requestAuthorization { success in
                if success {
                    fetchHealthData()
                }
                updateWidgetData()
                WidgetDataStore.forceWidgetSync()
                isRefreshing = false
            }
        } else {
            fetchHealthData()
            updateWidgetData()
            WidgetDataStore.forceWidgetSync()
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
        
        updateWidgetData()
        WidgetDataStore.forceWidgetSync()
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
            
            // Final widget update
            updateWidgetData()
        }
    }
}

// MARK: - Supporting Components

// Simplified Streak Card Component
struct StreakCard: View {
    let streak: Int
    let isActiveToday: Bool
    let isAtRisk: Bool
    let user: User
    let progress: Double
    let isGoalCompleted: Bool
    
    @State private var animateProgress = false
    
    var streakColor: Color {
        if isGoalCompleted {
            return .green
        } else if isAtRisk {
            return .red
        } else {
            return .orange
        }
    }
    
    var backgroundColor: Color {
        if isGoalCompleted {
            return .green.opacity(0.1)
        } else if isAtRisk {
            return .red.opacity(0.1)
        } else {
            return .orange.opacity(0.1)
        }
    }
    
    var statusText: String {
        if isGoalCompleted {
            return "Goal Complete!"
        } else if progress > 0 {
            return "In Progress (\(Int(progress * 100))%)"
        } else if isAtRisk {
            return "At Risk"
        } else {
            return "Ready to Start"
        }
    }
    
    var statusColor: Color {
        if isGoalCompleted {
            return .green
        } else if progress > 0 {
            return .blue
        } else if isAtRisk {
            return .red
        } else {
            return .gray
        }
    }
    
    var body: some View {
        VStack(spacing: 20) {
            // Header with flame icon
            HStack {
                ZStack {
                    Circle()
                        .fill(backgroundColor)
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: "flame.fill")
                        .font(.title2)
                        .foregroundColor(streakColor)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Current Streak")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    Text(statusText)
                        .font(.caption)
                        .foregroundColor(statusColor)
                }
                
                Spacer()
            }
            
            // Large streak number with live progress circle
            ZStack {
                // Background circle
                Circle()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [streakColor.opacity(0.3), streakColor.opacity(0.1)]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 120, height: 120)
                
                // Progress ring (shows goal completion progress)
                Circle()
                    .stroke(Color.gray.opacity(0.2), lineWidth: 4)
                    .frame(width: 130, height: 130)
                
                Circle()
                    .trim(from: 0, to: animateProgress ? progress : 0)
                    .stroke(
                        streakColor,
                        style: StrokeStyle(lineWidth: 4, lineCap: .round)
                    )
                    .frame(width: 130, height: 130)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.8), value: animateProgress)
                
                // Main streak number
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(streakColor)
                            .opacity(0.8)
                    }
                    .offset(y: -45)
                }
                
                // Streak number in center
                VStack(spacing: 4) {
                    Text("\(streak)")
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                        .foregroundColor(streakColor)
                    
                    Text(streak == 1 ? "day" : "days")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(streakColor.opacity(0.8))
                }
            }
            
            // Status section
            VStack(spacing: 12) {
                if isGoalCompleted {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Goal completed today!")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.green)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(20)
                } else {
                    // Time remaining until streak ends
                    VStack(spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: isAtRisk ? "exclamationmark.triangle.fill" : "clock")
                                .foregroundColor(isAtRisk ? .red : .orange)
                            Text(isAtRisk ? "Streak at risk!" : "Time remaining:")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(isAtRisk ? .red : .primary)
                        }
                        
                        Text(user.formattedTimeUntilReset)
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundColor(isAtRisk ? .red : .orange)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(backgroundColor)
                            .cornerRadius(12)
                    }
                    
                    if isAtRisk {
                        Text("Complete your mile to keep your \(streak)-day streak!")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 8)
                    }
                }
                }
            }
        .padding(20)
            .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: streakColor.opacity(0.2), radius: 8, x: 0, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(streakColor.opacity(0.3), lineWidth: 1)
        )
        .onAppear {
            animateProgress = true
        }
        .onChange(of: progress) { _, _ in
            animateProgress = true
        }
    }
}

// Simplified Today's Progress Card
struct TodayProgressCard: View {
    let currentDistance: Double
    let goalDistance: Double
    let progress: Double
    let didComplete: Bool
    let onRefresh: () -> Void
    
    var body: some View {
        VStack(spacing: 15) {
            HStack {
                Image(systemName: "figure.run")
                    .foregroundColor(.primary)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Today's Progress")
                        .font(.headline)
                }
                
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
                let remaining = ProgressCalculator.remainingDistance(current: currentDistance, goal: goalDistance)
                Text("\((remaining * 1609.34).formatted(.number.precision(.fractionLength(0)))) meters to go")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .cardStyle()
    }
}

// Progress Bar Component with guaranteed 100% cap
struct ProgressBar: View {
    var progress: Double // Already capped at 1.0 by ProgressCalculator
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: geometry.size.width, height: geometry.size.height)
                
                RoundedRectangle(cornerRadius: 10)
                    .fill(progress >= 1.0 ? Color.green : Color("appPrimary"))
                    .frame(width: progress * geometry.size.width, height: geometry.size.height) // progress already capped
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

// Goal Setting Sheet with Version Info
struct GoalSettingSheet: View {
    let currentGoal: Double
    @Binding var newGoal: Double
    let onSave: (Double) -> Void
    @Environment(\.dismiss) private var dismiss
    
    // Version information from bundle
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    }
    
    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
    }
    
    private var versionString: String {
        "v\(appVersion) (\(buildNumber))"
    }
    
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
                
                Section("App Info") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(versionString)
                            .foregroundColor(.secondary)
                            .font(.system(.body, design: .monospaced))
                    }
                    
                    HStack {
                        Text("Build Date")
                        Spacer()
                        Text(getBuildDate())
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Settings")
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
    
    private func getBuildDate() -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        
        if let infoPath = Bundle.main.path(forResource: "Info", ofType: "plist"),
           let infoAttrs = try? FileManager.default.attributesOfItem(atPath: infoPath),
           let infoDate = infoAttrs[.modificationDate] as? Date {
            return formatter.string(from: infoDate)
        }
        
        return formatter.string(from: Date())
    }
}



// MARK: - Instructions Components

struct InstructionsCard: View {
    @Binding var showFullInstructions: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "info.circle.fill")
                    .foregroundColor(.blue)
                    .font(.title2)
                
                Text("How to Use Mile A Day")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button("Full Guide") {
                    showFullInstructions = true
                }
                .font(.caption)
                .foregroundColor(.blue)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                InstructionStep(
                    number: "1",
                    text: "Set your daily mile goal using the gear icon",
                    icon: "target"
                )
                
                InstructionStep(
                    number: "2", 
                    text: "Start a walk or run workout in Apple Fitness",
                    icon: "figure.walk"
                )
                
                InstructionStep(
                    number: "3",
                    text: "Complete your target distance and end workout",
                    icon: "checkmark.circle"
                )
                
                InstructionStep(
                    number: "4",
                    text: "Return to Mile A Day - your streak will update automatically!",
                    icon: "arrow.clockwise"
                )
            }
            
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.caption)
                
                Text("Your widgets will refresh and show your updated progress")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 4)
        }
        .padding()
        .cardStyle()
    }
}

struct InstructionStep: View {
    let number: String
    let text: String
    let icon: String
    
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.1))
                    .frame(width: 24, height: 24)
                
                Text(number)
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.blue)
            }
            
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundColor(.blue)
                    .font(.caption)
                
                Text(text)
                    .font(.caption)
                    .foregroundColor(.primary)
            }
            
            Spacer()
        }
    }
}

// MARK: - Full Instructions View

struct FullInstructionsView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Header
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Welcome to Mile A Day")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        
                        Text("Build a consistent walking or running habit with simple goal tracking")
                            .font(.title3)
                            .foregroundColor(.secondary)
                    }
                    
                    // How it works section
                    SectionCard(
                        title: "How It Works",
                        icon: "lightbulb.fill",
                        color: .orange
                    ) {
                        VStack(alignment: .leading, spacing: 16) {
                            DetailedStep(
                                number: "1",
                                title: "Set Your Goal", 
                                description: "Choose your daily walking/running target using the gear icon. Start with 1 mile and adjust as needed.",
                                tip: "Start small and build consistency!"
                            )
                            
                            DetailedStep(
                                number: "2",
                                title: "Use Apple Fitness",
                                description: "Open Apple Fitness app and start a 'Walking' or 'Running' workout. Mile A Day reads your workout data automatically.",
                                tip: "Make sure HealthKit permissions are enabled"
                            )
                            
                            DetailedStep(
                                number: "3",
                                title: "Complete & Check Back",
                                description: "Finish your workout in Apple Fitness, then return to Mile A Day. Your progress updates automatically!",
                                tip: "Widgets will refresh within a few minutes"
                            )
                        }
                    }
                    
                    // Tips section
                    SectionCard(
                        title: "Pro Tips",
                        icon: "star.fill",
                        color: .yellow
                    ) {
                        VStack(alignment: .leading, spacing: 12) {
                            TipItem(
                                icon: "target",
                                text: "Start with achievable goals to build momentum"
                            )
                            
                            TipItem(
                                icon: "bell.fill",
                                text: "Enable notifications for daily reminders and completion celebrations"
                            )
                            
                            TipItem(
                                icon: "square.grid.2x2.fill",
                                text: "Add widgets to your home screen for quick progress checks"
                            )
                            
                            TipItem(
                                icon: "flame.fill",
                                text: "Focus on consistency over speed - every day counts!"
                            )
                        }
                    }
                    
                    // Troubleshooting section
                    SectionCard(
                        title: "Troubleshooting",
                        icon: "questionmark.circle.fill",
                        color: .blue
                    ) {
                        VStack(alignment: .leading, spacing: 12) {
                            TroubleshootingItem(
                                question: "Progress not updating?",
                                answer: "Pull down to refresh the main screen or restart the app. Check that HealthKit permissions are enabled."
                            )
                            
                            TroubleshootingItem(
                                question: "Widgets showing old data?",
                                answer: "Widgets update automatically but may take a few minutes. You can force refresh by opening the app."
                            )
                            
                            TroubleshootingItem(
                                question: "Missing workouts?",
                                answer: "Only Apple Fitness walking/running workouts count. Other workout apps may not sync properly."
                            )
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Instructions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct SectionCard<Content: View>: View {
    let title: String
    let icon: String
    let color: Color
    let content: Content
    
    init(title: String, icon: String, color: Color, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.color = color
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.title2)
                
                Text(title)
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Spacer()
            }
            
            content
        }
        .padding()
        .cardStyle()
    }
}

struct DetailedStep: View {
    let number: String
    let title: String
    let description: String
    let tip: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 32, height: 32)
                    
                    Text(number)
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    Text(description)
                        .font(.body)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            
            HStack(spacing: 8) {
                Image(systemName: "lightbulb.fill")
                    .foregroundColor(.yellow)
                    .font(.caption)
                
                Text(tip)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .italic()
            }
            .padding(.leading, 44)
        }
    }
}

struct TipItem: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.yellow)
                .font(.body)
                .frame(width: 20)
            
            Text(text)
                .font(.body)
        }
    }
}

struct TroubleshootingItem: View {
    let question: String
    let answer: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(question)
                .font(.body)
                .fontWeight(.semibold)
            
            Text(answer)
                .font(.body)
                .foregroundColor(.secondary)
        }
    }
} 