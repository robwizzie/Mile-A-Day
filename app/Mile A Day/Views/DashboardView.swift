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
    
    // Real-time unified state calculation with live workout integration
    private var currentState: (baseMiles: Double, liveDistance: Double, totalDistance: Double, goal: Double, progress: Double, isCompleted: Bool, isLiveMode: Bool) {
        let baseMiles = healthManager.todaysDistance
        let liveDistance = liveWorkoutManager.isWorkoutActive ? liveWorkoutManager.currentWorkoutDistance : 0.0
        let totalDistance = baseMiles + liveDistance
        let goal = userManager.currentUser.goalMiles
        
        // Use real-time progress from LiveWorkoutManager when active
        let progress = liveWorkoutManager.isWorkoutActive ? 
            liveWorkoutManager.liveProgress : 
            ProgressCalculator.calculateProgress(current: totalDistance, goal: goal)
        
        let isCompleted = liveWorkoutManager.isWorkoutActive ? 
            liveWorkoutManager.isGoalReached : 
            ProgressCalculator.isGoalCompleted(current: totalDistance, goal: goal)
        
        return (baseMiles, liveDistance, totalDistance, goal, progress, isCompleted, liveWorkoutManager.isWorkoutActive)
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
                    
                    // Enhanced Streak card with live progress
                    StreakCard(
                        streak: userManager.currentUser.streak, 
                              isActiveToday: userManager.currentUser.isStreakActiveToday,
                              isAtRisk: userManager.currentUser.isStreakAtRisk,
                        user: userManager.currentUser,
                        liveProgress: currentState.progress,
                        isLiveMode: currentState.isLiveMode,
                        isGoalCompleted: currentState.isCompleted
                    )
                    
                    // Today's progress with real-time live data
                    TodayProgressCard(
                        currentDistance: currentState.totalDistance,
                        goalDistance: currentState.goal,
                        progress: currentState.progress,
                        didComplete: currentState.isCompleted,
                        isLiveMode: currentState.isLiveMode,
                        liveDistance: currentState.liveDistance,
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
                // Start real-time live workout monitoring
                liveWorkoutManager.startLiveWorkoutMonitoring()
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
            .onChange(of: liveWorkoutManager.isWorkoutActive) { oldValue, newValue in
                // Update widget data when workout state changes
                updateWidgetData()
                print("[Dashboard] 🔴 Live workout state changed: \(newValue)")
            }
            .onChange(of: liveWorkoutManager.liveProgress) { oldValue, newValue in
                // Update widget data when live progress changes
                updateWidgetData()
                if abs(newValue - oldValue) > 0.01 {
                    print("[Dashboard] 📊 Live progress updated: \(String(format: "%.1f", newValue * 100))%")
                }
            }
            .onChange(of: liveWorkoutManager.currentWorkoutDistance) { oldValue, newValue in
                // Update widget data when workout distance changes
                updateWidgetData()
                if abs(newValue - oldValue) > 0.005 {
                    print("[Dashboard] 🏃‍♂️ Live distance updated: \(String(format: "%.3f", newValue)) miles")
                }
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
            liveWorkoutDistance: state.liveDistance
        )
        WidgetDataStore.save(streak: userManager.currentUser.streak)
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
                isRefreshing = false
            }
        } else {
            fetchHealthData()
            updateWidgetData()
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

// Enhanced Streak Card Component with Live Progress Circle
struct StreakCard: View {
    let streak: Int
    let isActiveToday: Bool
    let isAtRisk: Bool
    let user: User
    let liveProgress: Double
    let isLiveMode: Bool
    let isGoalCompleted: Bool
    
    @State private var animateProgress = false
    @State private var livePulse = false
    
    var streakColor: Color {
        if isGoalCompleted {
            return .green
        } else if isAtRisk {
            return .red
        } else if isLiveMode {
            return .blue
        } else {
            return .orange
        }
    }
    
    var backgroundColor: Color {
        if isGoalCompleted {
            return .green.opacity(0.1)
        } else if isAtRisk {
            return .red.opacity(0.1)
        } else if isLiveMode {
            return .blue.opacity(0.1)
        } else {
            return .orange.opacity(0.1)
        }
    }
    
    var statusText: String {
        if isLiveMode {
            return "Live Workout"
        } else if isActiveToday {
            return "Active Today"
        } else if isAtRisk {
            return "At Risk"
        } else {
            return "Keep It Going"
        }
    }
    
    var statusColor: Color {
        if isLiveMode {
            return .blue
        } else if isActiveToday {
            return .green
        } else if isAtRisk {
            return .red
        } else {
            return .orange
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
                    
                    // Live pulse indicator when in live mode
                    if isLiveMode {
                        Circle()
                            .stroke(Color.blue, lineWidth: 2)
                            .frame(width: 44, height: 44)
                            .scaleEffect(livePulse ? 1.1 : 1.0)
                            .opacity(livePulse ? 0.0 : 1.0)
                            .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: false), value: livePulse)
                    }
                    
                    Image(systemName: isLiveMode ? "dot.radiowaves.left.and.right" : "flame.fill")
                    .font(.title2)
                        .foregroundColor(streakColor)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                Text("Current Streak")
                            .font(.headline)
                            .fontWeight(.semibold)
                        
                        if isLiveMode {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(Color.red)
                                    .frame(width: 6, height: 6)
                                    .scaleEffect(livePulse ? 1.3 : 1.0)
                                    .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: livePulse)
                                
                                Text("LIVE")
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .foregroundColor(.red)
                            }
                        }
                    }
                    
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
                
                // Live progress ring (shows goal completion progress)
                    Circle()
                    .stroke(Color.gray.opacity(0.2), lineWidth: 4)
                    .frame(width: 130, height: 130)
                
                Circle()
                    .trim(from: 0, to: animateProgress ? liveProgress : 0)
                    .stroke(
                        streakColor,
                        style: StrokeStyle(lineWidth: 4, lineCap: .round)
                    )
                    .frame(width: 130, height: 130)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.8), value: animateProgress)
                
                // Progress percentage text (when in live mode and progress > 0)
                if isLiveMode && liveProgress > 0.01 {
                    VStack(spacing: 2) {
                        Text("\(Int(liveProgress * 100))%")
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
            
            // Status and time remaining section
            VStack(spacing: 12) {
                    if isActiveToday {
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
            if isLiveMode {
                livePulse = true
            }
        }
        .onChange(of: liveProgress) { _, _ in
            animateProgress = true
        }
        .onChange(of: isLiveMode) { _, newValue in
            livePulse = newValue
        }
    }
}

// Today's Progress Card with real-time live updates
struct TodayProgressCard: View {
    let currentDistance: Double
    let goalDistance: Double
    let progress: Double // Pre-calculated progress capped at 1.0
    let didComplete: Bool
    let isLiveMode: Bool
    let liveDistance: Double
    let onRefresh: () -> Void
    
    @State private var livePulse = false
    
    var body: some View {
        VStack(spacing: 15) {
            HStack {
                Image(systemName: isLiveMode ? "dot.radiowaves.left.and.right" : "figure.run")
                    .foregroundColor(isLiveMode ? .blue : .primary)
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                Text("Today's Progress")
                    .font(.headline)
                        
                        if isLiveMode {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(Color.red)
                                    .frame(width: 6, height: 6)
                                    .scaleEffect(livePulse ? 1.3 : 1.0)
                                    .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: livePulse)
                                
                                Text("LIVE")
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .foregroundColor(.red)
                            }
                        }
                    }
                    
                    if isLiveMode && liveDistance > 0.01 {
                        Text("Live: +\(liveDistance.milesFormatted)")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
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
        .onAppear {
            if isLiveMode {
                livePulse = true
            }
        }
        .onChange(of: isLiveMode) { _, newValue in
            livePulse = newValue
        }
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

// MARK: - Enhanced Live Workout Card Component

struct LiveWorkoutCard: View {
    let workoutType: HKWorkoutActivityType?
    let currentDistance: Double
    let startTime: Date?
    
    @State private var elapsedTime: TimeInterval = 0
    @State private var timer: Timer?
    @State private var pulseAnimation = false
    
    var workoutIcon: String {
        switch workoutType {
        case .running:
            return "figure.run"
        case .walking:
            return "figure.walk"
        default:
            return "figure.mixed.cardio"
        }
    }
    
    var body: some View {
        VStack(spacing: 20) {
            // Enhanced header with workout icon
            HStack {
                ZStack {
                    Circle()
                        .fill(Color.red.opacity(0.1))
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: workoutIcon)
                        .font(.title2)
                        .foregroundColor(.red)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 8, height: 8)
                            .scaleEffect(pulseAnimation ? 1.3 : 1.0)
                            .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: pulseAnimation)
                    
                    Text("LIVE WORKOUT")
                        .font(.caption.bold())
                        .foregroundColor(.red)
                }
                
                Text(workoutType?.name ?? "Workout")
                        .font(.headline)
                        .fontWeight(.semibold)
                }
                
                Spacer()
            }
            
            // Enhanced live metrics with background circles
            HStack(spacing: 24) {
                // Distance metric
                VStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(colors: [Color.blue.opacity(0.3), Color.blue.opacity(0.1)]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 70, height: 70)
                        
                        VStack(spacing: 2) {
                    Text(String(format: "%.2f", currentDistance))
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .foregroundColor(.blue)
                            Text("mi")
                                .font(.caption2)
                                .foregroundColor(.blue.opacity(0.8))
                        }
                    }
                    
                    Text("Distance")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                }
                
                // Duration metric
                VStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(colors: [Color.purple.opacity(0.3), Color.purple.opacity(0.1)]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 70, height: 70)
                        
                        Text(formatDurationCompact(elapsedTime))
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundColor(.purple)
                    }
                    
                    Text("Duration")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                }
                
                // Pace metric (if distance > 0)
                if currentDistance > 0.01 {
                    VStack(spacing: 8) {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        gradient: Gradient(colors: [Color.orange.opacity(0.3), Color.orange.opacity(0.1)]),
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 70, height: 70)
                            
                        Text(formatPace(minutes: elapsedTime / 60 / currentDistance))
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundColor(.orange)
                        }
                        
                        Text("Pace")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            // Motivational message
            Text("Keep going! Every step counts towards your goal.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: Color.red.opacity(0.2), radius: 8, x: 0, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.red.opacity(0.3), lineWidth: 1)
        )
        .onAppear {
            startTimer()
            pulseAnimation = true
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
    
    private func formatDurationCompact(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = Int(duration) % 3600 / 60
        let seconds = Int(duration) % 60
        
        if hours > 0 {
            return String(format: "%d:%02d", hours, minutes)
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