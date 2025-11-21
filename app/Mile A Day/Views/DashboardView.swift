import SwiftUI
import HealthKit
import WidgetKit
import UIKit
import CoreLocation

// MARK: - Custom Navigation Bar Appearance for iOS 18 Liquid Glass

extension View {
    func liquidGlassNavigationBar() -> some View {
        self.onAppear {
            let appearance = UINavigationBarAppearance()

            if #available(iOS 18.0, *) {
                // iOS 18+ liquid glass effect
                appearance.configureWithTransparentBackground()
                appearance.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterial)
            } else {
                // Fallback for iOS 17
                appearance.configureWithTransparentBackground()
                appearance.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterial)
            }

            // Fully transparent to show gradient everywhere
            appearance.backgroundColor = .clear
            appearance.shadowColor = .clear

            // Apply to all appearance states
            UINavigationBar.appearance().standardAppearance = appearance
            UINavigationBar.appearance().scrollEdgeAppearance = appearance
            UINavigationBar.appearance().compactAppearance = appearance
            UINavigationBar.appearance().compactScrollEdgeAppearance = appearance

            // Ensure navbar extends behind status bar and dynamic island
            UINavigationBar.appearance().isTranslucent = true
        }
    }
}

struct DashboardView: View {
    @ObservedObject var healthManager: HealthKitManager
    @ObservedObject var userManager: UserManager
    @EnvironmentObject var notificationService: MADNotificationService
    @StateObject private var workoutService = WorkoutService()
    
    @State private var showConfetti = false
    @State private var showGoalSheet = false
    @State private var newGoalMiles: Double = 1.0
    @State private var isRefreshing = false
    @State private var showInstructions = false
    @State private var showCelebration = false
    @State private var showWorkoutUploadAlert = false
    @AppStorage("lastGoalCompletionDate") private var lastGoalCompletionDate: Date = Date.distantPast
    
    // Simplified state calculation
    private var currentState: (distance: Double, goal: Double, progress: Double, isCompleted: Bool) {
        let distance = healthManager.todaysDistance
        let goal = userManager.currentUser.goalMiles
        let progress = ProgressCalculator.calculateProgress(current: distance, goal: goal)
        let isCompleted = ProgressCalculator.isGoalCompleted(current: distance, goal: goal)
        
        return (distance, goal, progress, isCompleted)
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Instructions banner
                    InstructionsBanner(
                        showInstructions: $showInstructions
                    )

                    // SECTION: Streak Counter (full width at top)
                    StreakCard(
                        streak: userManager.currentUser.streak,
                        isActiveToday: userManager.currentUser.isStreakActiveToday,
                        isAtRisk: userManager.currentUser.isStreakAtRisk,
                        user: userManager.currentUser,
                        progress: currentState.progress,
                        isGoalCompleted: currentState.isCompleted,
                        isRefreshing: isRefreshing,
                        currentDistance: currentState.distance,
                        fastestPace: healthManager.fastestMilePace,
                        mostMiles: healthManager.mostMilesInOneDay,
                        totalMiles: healthManager.totalLifetimeMiles
                    )

                    // SECTION: Today's Progress (full width with Start Mile button)
                    TodayProgressCard(
                        currentDistance: currentState.distance,
                        goalDistance: currentState.goal,
                        progress: currentState.progress,
                        didComplete: currentState.isCompleted,
                        onRefresh: refreshData,
                        isRefreshing: isRefreshing,
                        user: userManager.currentUser,
                        fastestPace: healthManager.fastestMilePace,
                        mostMiles: healthManager.mostMilesInOneDay,
                        totalMiles: healthManager.totalLifetimeMiles,
                        healthManager: healthManager,
                        userManager: userManager
                    )

                    // SECTION: Steps and Badges (side by side)
                    HStack(spacing: 12) {
                        CalendarPreviewCard(
                            healthManager: healthManager,
                            userManager: userManager
                        )
                        .frame(maxWidth: .infinity)

                        BadgesPreviewCard(
                            userManager: userManager
                        )
                        .frame(maxWidth: .infinity)
                    }

                    // SECTION: Week at a Glance
                    WeekAtAGlanceCard(
                        healthManager: healthManager,
                        userManager: userManager
                    )

                    // SECTION: Statistics & History
                    VStack(spacing: 12) {
                        StatsGridView(user: userManager.currentUser, healthManager: healthManager)

                        RecentWorkoutsView(workouts: healthManager.recentWorkouts)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .refreshable {
                await refreshDataAsync()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .liquidGlassNavigationBar()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 12) {
                        Image("mad-logo")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(height: 40)

                        if userManager.hasNewBadges {
                            NavigationLink(destination: BadgesView(userManager: userManager)) {
                                Image(systemName: "trophy.fill")
                                    .foregroundColor(.yellow)
                                    .font(.title3)
                            }
                        }
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 16) {
                        Button {
                            showInstructions = true
                        } label: {
                            Image(systemName: "info.circle")
                                .foregroundColor(.white)
                                .font(.title3)
                        }

                        Button {
                            showGoalSheet = true
                        } label: {
                            Image(systemName: "gear")
                                .foregroundColor(.white)
                                .font(.title3)
                        }
                    }
                }
            }
            .onAppear {
                refreshData()
                // Sync widget data immediately
                syncWidgetData()

                // PHASE 1: Listen for workout index completion
                NotificationCenter.default.addObserver(
                    forName: NSNotification.Name("WorkoutIndexReady"),
                    object: nil,
                    queue: .main
                ) { [weak userManager, weak healthManager] _ in
                    guard let userManager = userManager, let healthManager = healthManager else { return }

                    print("[Dashboard] 🔔 Workout index ready, updating user data and syncing widgets")

                    // Update user manager with correct streak from index
                    userManager.updateUserWithHealthKitData(
                        retroactiveStreak: healthManager.retroactiveStreak,
                        currentMiles: healthManager.todaysDistance,
                        totalMiles: healthManager.totalLifetimeMiles,
                        fastestPace: healthManager.fastestMilePace,
                        mostMilesInDay: healthManager.mostMilesInOneDay
                    )

                    // Sync widgets with correct data
                    WidgetDataStore.save(todayMiles: healthManager.todaysDistance, goal: 1.0)
                    WidgetDataStore.save(streak: userManager.currentUser.streak)
                    WidgetCenter.shared.reloadAllTimelines()

                    print("[Dashboard] ✅ User data and widgets updated with streak: \(userManager.currentUser.streak)")
                }

                // Fetch fastest mile data immediately in background
                Task {
                    healthManager.fetchFastestMilePace()
                }

                // Check if this is the first time opening the app after completing today's goal
                let today = Calendar.current.startOfDay(for: Date())
                let lastCompletion = Calendar.current.startOfDay(for: lastGoalCompletionDate)

                if currentState.isCompleted && today != lastCompletion {
                    // This is the first time opening after completing today's goal
                    // Show celebration with minimal delay for smooth UX
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds
                        showCelebration = true
                        lastGoalCompletionDate = Date()
                    }
                }
            }
            .sheet(isPresented: $showGoalSheet) {
                GoalSettingSheet(
                    currentGoal: userManager.currentUser.goalMiles,
                    onSave: { newGoal in
                        userManager.setDailyGoal(miles: newGoal)
                        syncWidgetData()
                    }
                )
                .presentationDetents([.height(300)])
                    }
            .sheet(isPresented: $showInstructions) {
                InstructionsView()
            }
            .alert("Workout Upload", isPresented: $showWorkoutUploadAlert) {
                Button("OK") { }
            } message: {
                if let status = workoutService.lastUploadStatus {
                    Text(status)
                } else if let error = workoutService.errorMessage {
                    Text("Error: \(error)")
                } else {
                    Text("Upload completed")
                }
            }
            .onChange(of: currentState.isCompleted) { oldValue, newValue in
                if newValue && !oldValue {
                    triggerConfetti()
            }
        }
                    .confetti(isShowing: $showConfetti)
            .confetti(isShowing: $showCelebration)
            .overlay(
                // Celebration overlay
                Group {
                    if showCelebration {
                        ZStack {
                            // Background blur
                            Color.primary.opacity(0.4)
                                .ignoresSafeArea()
                            
                            // Celebration content
                            VStack(spacing: 24) {
                                // Animated trophy icon
                                ZStack {
                                    Circle()
                                        .fill(
                                            LinearGradient(
                                                gradient: Gradient(colors: [.yellow.opacity(0.3), .orange.opacity(0.2)]),
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                        .frame(width: 100, height: 100)
                                    
                                    Image(systemName: "trophy.fill")
                                        .font(.system(size: 50))
                                        .foregroundColor(.orange)
                                        .scaleEffect(showCelebration ? 1.1 : 0.9)
                                        .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: showCelebration)
                                }
                                
                                VStack(spacing: 8) {
                                    Text("Goal Completed!")
                                        .font(.title)
                                        .fontWeight(.bold)
                                        .foregroundColor(.primary)
                                    
                                    Text("You've crushed your daily mile goal. Keep up the amazing work!")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                        .multilineTextAlignment(.center)
                                        .padding(.horizontal, 20)
                                }
                                
                                Button {
                                    withAnimation(.easeInOut(duration: 0.5)) {
                                        showCelebration = false
                                    }
                                } label: {
                                    Text("Continue")
                                        .font(.headline)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.white)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 16)
                                        .background(
                                            RoundedRectangle(cornerRadius: 12)
                                                .fill(Color("appPrimary"))
                                        )
                                }
                                .padding(.horizontal, 20)
                            }
                            .padding(32)
                            .background(
                                RoundedRectangle(cornerRadius: 20)
                                    .fill(Color(.systemBackground))
                                    .shadow(color: Color.primary.opacity(0.2), radius: 20, x: 0, y: 10)
                            )
                            .scaleEffect(showCelebration ? 1.0 : 0.8)
                            .opacity(showCelebration ? 1.0 : 0.0)
                            .animation(.spring(response: 0.6, dampingFraction: 0.8), value: showCelebration)
                        }
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.5)) {
                                showCelebration = false
                            }
                        }
                    }
            }
        )
        }
    }
    
    private func syncWidgetData() {
        let state = currentState
        WidgetDataStore.save(todayMiles: state.distance, goal: state.goal)
        WidgetDataStore.save(streak: userManager.currentUser.streak)
        
        // Force widget updates
        WidgetCenter.shared.reloadAllTimelines()
    }
    
    private func refreshData() {
        isRefreshing = true

        // Fetch data in order to ensure consistency
        healthManager.fetchAllWorkoutData()

        // Use Task for better performance than DispatchQueue
        Task { @MainActor in
            // Reduced delay for faster UI responsiveness (from 2.5s to 1s)
            try? await Task.sleep(nanoseconds: 1_000_000_000)

            // Update user manager with fresh HealthKit data
            userManager.updateUserWithHealthKitData(
                retroactiveStreak: healthManager.retroactiveStreak,
                currentMiles: healthManager.todaysDistance,
                totalMiles: healthManager.totalLifetimeMiles,
                fastestPace: healthManager.fastestMilePace,
                mostMilesInDay: healthManager.mostMilesInOneDay
            )

            syncWidgetData()

            // Shorter additional delay (from 3s total to 1.5s total)
            try? await Task.sleep(nanoseconds: 500_000_000)
            syncWidgetData()
            isRefreshing = false
        }
    }
    
    private func refreshDataAsync() async {
        isRefreshing = true
        healthManager.fetchAllWorkoutData()

        // Reduced delay for faster UI responsiveness (from 2.5s to 1s)
        try? await Task.sleep(nanoseconds: 1_000_000_000)

        // Update user manager with fresh HealthKit data
        userManager.updateUserWithHealthKitData(
            retroactiveStreak: healthManager.retroactiveStreak,
            currentMiles: healthManager.todaysDistance,
            totalMiles: healthManager.totalLifetimeMiles,
            fastestPace: healthManager.fastestMilePace,
            mostMilesInDay: healthManager.mostMilesInOneDay
        )

        syncWidgetData()

        // Shorter additional delay (from 3s total to 1.5s total)
        try? await Task.sleep(nanoseconds: 500_000_000)
        syncWidgetData()
        isRefreshing = false
    }
    
    private func triggerConfetti() {
        showConfetti = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
            showConfetti = false
        }
    }
    
    // MARK: - Workout Upload Test Functions
    private func uploadWorkouts() async {
        do {
            // Get recent workouts from HealthKit
            let workouts = healthManager.recentWorkouts
            
            if workouts.isEmpty {
                await MainActor.run {
                    workoutService.errorMessage = "No workouts found to upload"
                }
                return
            }
            
            // Upload workouts
            try await workoutService.uploadWorkouts(workouts)
            
            // Show success alert
            await MainActor.run {
                showWorkoutUploadAlert = true
            }
            
        } catch {
            await MainActor.run {
                workoutService.errorMessage = error.localizedDescription
            }
        }
    }
    
    private func uploadAllWorkouts() async {
        do {
            // Upload all workouts from HealthKit
            try await workoutService.uploadAllWorkouts()
            
            // Show success alert
            await MainActor.run {
                showWorkoutUploadAlert = true
            }
            
        } catch {
            await MainActor.run {
                workoutService.errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - Instructions Banner

struct InstructionsBanner: View {
    @Binding var showInstructions: Bool
    @AppStorage("hasSeenInstructions") private var hasSeenInstructions = false
    
    var body: some View {
        if !hasSeenInstructions {
            VStack(spacing: 12) {
                HStack {
                    Image(systemName: "info.circle.fill")
                        .foregroundColor(.blue)
                        .font(.title2)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Welcome to Mile A Day!")
                            .font(.headline)
                            .fontWeight(.semibold)
                        
                        Text("Complete your workout in Apple Fitness, then return here to see your progress. Tap the ℹ️ icon anytime for help.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Button("Got it!") {
                        withAnimation {
                            hasSeenInstructions = true
            }
                    }
                    .font(.caption)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .clipShape(Capsule())
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.blue.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.blue.opacity(0.3), lineWidth: 1)
            )
        }
    }
}

// MARK: - Instructions View

struct InstructionsView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Header
                    VStack(alignment: .leading, spacing: 8) {
                        Text("How to Use Mile A Day")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        
                        Text("Simple steps to track your daily mile progress")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    // Step-by-step instructions
                    VStack(alignment: .leading, spacing: 20) {
                        InstructionStep(
                            number: "1",
                            title: "Start Your Workout",
                            description: "Open Apple Fitness or any workout app and start your run or walk. Make sure HealthKit integration is enabled.",
                            icon: "figure.run",
                            color: .blue
                        )
                        
                        InstructionStep(
                            number: "2",
                            title: "Complete Your Mile",
                            description: "Finish your workout to reach your daily mile goal. The app works with any distance - walking, running, or hiking.",
                            icon: "checkmark.circle.fill",
                            color: .green
                        )
                        
                        InstructionStep(
                            number: "3",
                            title: "Return to Mile A Day",
                            description: "Come back to this app to see your updated progress, maintain your streak, and earn badges.",
                            icon: "arrow.clockwise",
                            color: .orange
                        )
                        
                        InstructionStep(
                            number: "4",
                            title: "Check Your Widgets",
                            description: "Add our widgets to your home screen for quick progress updates throughout the day.",
                            icon: "rectangle.3.group",
                            color: .purple
                        )
                    }
                    
                    // Additional tips
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Tips for Success")
                            .font(.headline)
                            .fontWeight(.semibold)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            TipItem(text: "Enable HealthKit permissions for accurate tracking")
                            TipItem(text: "Pull down to refresh your progress manually")
                            TipItem(text: "Adjust your daily goal in settings (gear icon)")
                            TipItem(text: "Maintain your streak by hitting your goal daily")
                            TipItem(text: "Tap the ℹ️ icon anytime to see these instructions")
        }
    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(.systemGray6))
                    )
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

struct InstructionStep: View {
    let number: String
    let title: String
    let description: String
    let icon: String
    let color: Color
    
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            // Step number
                ZStack {
                    Circle()
                    .fill(color)
                    .frame(width: 32, height: 32)
                    
                Text(number)
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: icon)
                        .foregroundColor(color)
                    .font(.title2)
                
                    Text(title)
                            .font(.headline)
                            .fontWeight(.semibold)
                }
                
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Spacer()
        }
    }
}

struct TipItem: View {
    let text: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "lightbulb.fill")
                .foregroundColor(.yellow)
                        .font(.caption)
                .padding(.top, 2)
            
            Text(text)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
                }
    }
}

// MARK: - Updated Card Components

struct StreakCard: View {
    let streak: Int
    let isActiveToday: Bool
    let isAtRisk: Bool
    let user: User
    let progress: Double
    let isGoalCompleted: Bool
    let isRefreshing: Bool
    let currentDistance: Double
    let fastestPace: TimeInterval
    let mostMiles: Double
    let totalMiles: Double
    @State private var animateStreak = false
    @State private var animateFire = false
    @State private var showingShareSheet = false
    @State private var isPressed = false

    // Streak milestone milestones
    private let milestones = [3, 5, 7, 10, 14, 21, 30, 50, 60, 75, 90, 100, 150, 200, 250, 365, 500, 1000]

    private var nextMilestone: (value: Int, progress: Double, daysToGo: Int)? {
        for milestone in milestones {
            if streak < milestone {
                let progressToMilestone = Double(streak) / Double(milestone)
                let daysToGo = milestone - streak
                return (milestone, progressToMilestone, daysToGo)
            }
        }
        return nil
    }

    var body: some View {
        VStack(spacing: 16) {
            // Top section: Streak info and fire icon
            HStack(spacing: 20) {
                // Left side: Streak info
                VStack(alignment: .leading, spacing: 8) {
                    Text("CURRENT STREAK")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.white.opacity(0.7))
                        .tracking(1.2)

                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(streak)")
                            .font(.system(size: 44, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .contentTransition(.numericText())

                        Text(streak == 1 ? "day" : "days")
                            .font(.title3)
                            .fontWeight(.medium)
                            .foregroundColor(.white.opacity(0.8))
                    }

                    // Status message
                    HStack(spacing: 4) {
                        if isGoalCompleted {
                            Image(systemName: "flame.fill")
                                .font(.caption)
                                .foregroundColor(.orange)
                            Text("You're on fire!")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.9))
                                .fontWeight(.medium)
                        } else if isAtRisk {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.yellow)
                            Text("Complete today's goal!")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.9))
                                .fontWeight(.medium)
                        } else {
                            Text("\(String(format: "%.2f", user.goalMiles - currentDistance)) mi to go")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.9))
                                .fontWeight(.medium)
                        }
                    }
                }

                Spacer()

                // Right side: Animated Flame icon
                ZStack {
                    // Outer glow
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color.orange.opacity(0.5),
                                    Color.orange.opacity(0.2),
                                    Color.clear
                                ],
                                center: .center,
                                startRadius: 20,
                                endRadius: 45
                            )
                        )
                        .frame(width: 90, height: 90)
                        .scaleEffect(animateFire ? 1.15 : 0.95)
                        .opacity(animateFire ? 0.9 : 0.5)
                        .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: animateFire)

                    // Inner circle background
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.orange.opacity(0.5),
                                    Color.red.opacity(0.4)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 70, height: 70)

                    // Flame icon with animation
                    Image(systemName: "flame.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.orange, .yellow, .red],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .scaleEffect(animateFire ? 1.15 : 1.0)
                        .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: animateFire)
                        .shadow(color: .orange.opacity(0.7), radius: animateFire ? 15 : 8)
                }
            }

            // Milestone progress
            if let milestone = nextMilestone {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Next Milestone: \(milestone.value) Days")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.white.opacity(0.9))

                        Spacer()

                        Text("\(milestone.daysToGo) days to go")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.orange)
                    }

                    // Progress bar
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.white.opacity(0.15))
                                .frame(height: 8)

                            RoundedRectangle(cornerRadius: 8)
                                .fill(
                                    LinearGradient(
                                        colors: [.yellow, .orange, .red],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: milestone.progress * geometry.size.width, height: 8)
                                .animation(.easeOut(duration: 0.8), value: milestone.progress)
                        }
                    }
                    .frame(height: 8)
                }
            }
        }
        .padding(24)
        .background(
            ZStack {
                // Dark gradient background (glass effect)
                RoundedRectangle(cornerRadius: 20)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.3, green: 0.15, blue: 0.15).opacity(0.6),
                                        Color(red: 0.2, green: 0.1, blue: 0.1).opacity(0.8)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )

                // Glass border
                RoundedRectangle(cornerRadius: 20)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.25),
                                Color.clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
        )
        .shadow(color: .black.opacity(0.3), radius: 12, x: 0, y: 6)
        .scaleEffect(isPressed ? 0.98 : 1.0)
        .animation(.easeInOut(duration: 0.1), value: isPressed)
        .onAppear {
            // Start fire animation
            animateFire = true
        }
        .onChange(of: isGoalCompleted) { oldValue, newValue in
            if newValue && !oldValue {
                // Extra fire animation when goal completed
                withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                    animateFire = true
                }
            }
        }
        .onTapGesture {
            let impact = UIImpactFeedbackGenerator(style: .medium)
            impact.impactOccurred()
            showingShareSheet = true
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    withAnimation(.easeInOut(duration: 0.1)) {
                        isPressed = true
                    }
                }
                .onEnded { _ in
                    withAnimation(.easeInOut(duration: 0.1)) {
                        isPressed = false
                    }
                }
        )
        .sheet(isPresented: $showingShareSheet) {
            EnhancedShareView(
                user: user,
                currentDistance: currentDistance,
                progress: progress,
                isGoalCompleted: isGoalCompleted,
                fastestPace: fastestPace,
                mostMiles: mostMiles,
                totalMiles: totalMiles
            )
        }
    }
}

struct TodayProgressCard: View {
    let currentDistance: Double
    let goalDistance: Double
    let progress: Double
    let didComplete: Bool
    let onRefresh: () -> Void
    let isRefreshing: Bool
    let user: User
    let fastestPace: TimeInterval
    let mostMiles: Double
    let totalMiles: Double
    @ObservedObject var healthManager: HealthKitManager
    @ObservedObject var userManager: UserManager
    @State private var animateProgress = false
    @State private var showWorkoutView = false
    @State private var isPressed = false

    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Image(systemName: "figure.run")
                    .foregroundColor(.white)
                    .font(.title3)
                Text("Today's Progress")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                Spacer()
                if didComplete {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.title3)
                }
            }

            // Large progress display
            VStack(spacing: 8) {
                Text(String(format: "%.2f", currentDistance))
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .contentTransition(.numericText())

                Text("of \(String(format: "%.1f", goalDistance)) mi")
                    .font(.title3)
                    .foregroundColor(.white.opacity(0.8))
            }

            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.2))
                        .frame(height: 12)

                    RoundedRectangle(cornerRadius: 8)
                        .fill(
                            LinearGradient(
                                colors: didComplete ? [.green, .green] : [.orange, .red],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: progress * geometry.size.width, height: 12)
                        .animation(.easeOut(duration: 0.8), value: progress)
                }
            }
            .frame(height: 12)

            // Start Mile button
            Button(action: {
                showWorkoutView = true
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "play.fill")
                        .font(.title3)
                    Text("Start Mile")
                        .font(.headline)
                        .fontWeight(.semibold)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 217/255, green: 64/255, blue: 63/255),
                                    Color(red: 180/255, green: 50/255, blue: 50/255)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
                .shadow(color: Color(red: 217/255, green: 64/255, blue: 63/255).opacity(0.4), radius: 8, x: 0, y: 4)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(20)
        .background(
            ZStack {
                // Glass effect background
                RoundedRectangle(cornerRadius: 20)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.85, green: 0.25, blue: 0.35).opacity(0.25),
                                        Color(red: 0.7, green: 0.2, blue: 0.3).opacity(0.35)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )

                // Glass border
                RoundedRectangle(cornerRadius: 20)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.3),
                                Color.clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
        )
        .shadow(color: .black.opacity(0.3), radius: 12, x: 0, y: 6)
        .fullScreenCover(isPresented: $showWorkoutView) {
            WorkoutTrackingView(healthManager: healthManager, userManager: userManager, goalDistance: goalDistance)
        }
    }
}

// MARK: - Supporting Components

// Unified Stats Grid Component
struct UnifiedStatsGrid: View {
    let user: User
    @ObservedObject var healthManager: HealthKitManager
    let statsType: StatsViewType
    @State private var statsData: (totalMiles: Double, mostMiles: Double, fastestPace: TimeInterval, streakDays: Int) = (0.0, 0.0, 0.0, 0)
    @State private var isCalculating = false
    @State private var showFastestPaceDetail = false
    @State private var showMostMilesDetail = false
    @State private var showGoalSheet = false
    @State private var isRefreshingFastestPace = false
    
    enum StatsViewType: String, CaseIterable {
        case allTime = "All Time"
        case currentStreak = "Current Streak"
    }
    
    var formattedFastestPace: String {
        if isCalculating || isRefreshingFastestPace {
            return "Calculating..."
        }
        
        if statsType == .allTime {
            if healthManager.fastestMilePace > 0 {
                let totalMinutes = healthManager.fastestMilePace
                let minutes = Int(totalMinutes)
                let seconds = Int((totalMinutes - Double(minutes)) * 60)
                return String(format: "%d:%02d /mi", minutes, seconds)
            }
        } else {
            if statsData.fastestPace > 0 {
                let totalMinutes = statsData.fastestPace
                let minutes = Int(totalMinutes)
                let seconds = Int((totalMinutes - Double(minutes)) * 60)
                return String(format: "%d:%02d /mi", minutes, seconds)
            }
        }
        return "Not yet recorded"
    }
    
    var headerIcon: String {
        statsType == .allTime ? "trophy.fill" : "flame.fill"
    }
    
    var headerTitle: String {
        statsType == .allTime ? "All Time Stats" : "Current Streak Stats"
    }
    
    var badgeValue: String {
        if statsType == .allTime {
            return "All Time"
        } else {
            return "\(statsData.streakDays) days"
        }
    }
    
    var badgeColor: Color {
        statsType == .allTime ? .blue : .orange
    }
    
    var totalMiles: Double {
        statsType == .allTime ? user.totalMiles : statsData.totalMiles
    }
    
    var mostMiles: Double {
        statsType == .allTime ? user.mostMilesInOneDay : statsData.mostMiles
    }
    
    var streakDays: Int {
        statsType == .allTime ? user.streak : statsData.streakDays
    }
    
    var avgMilesPerDay: Double {
        if streakDays > 0 {
            return totalMiles / Double(streakDays)
        }
        return 0.0
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            // Header with icon and badge
            HStack {
                Image(systemName: headerIcon)
                    .foregroundColor(badgeColor)
                    .font(.title2)
                
                Text(headerTitle)
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                // Badge
                Text(badgeValue)
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(badgeColor)
                    )
            }
            
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 15) {
                // Total Miles Card
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "map.fill")
                            .foregroundColor(.blue)
                        Text(statsType == .allTime ? "Total Miles" : "Streak Miles")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Text(String(format: "%.1f mi", totalMiles))
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                    
                    // Progress indicator - only show for current streak, not all time
                    if streakDays > 0 && statsType == .currentStreak {
                        Text(String(format: "%.1f avg/day", avgMilesPerDay))
                            .font(.caption2)
                            .foregroundColor(.blue)
                    } else if statsType == .allTime {
                        // Add blank space to maintain consistent card height
                        Text(" ")
                            .font(.caption2)
                            .foregroundColor(.clear)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, minHeight: 80, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.blue.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                        )
                )
                
                // Fastest Mile Card
                Button {
                    showFastestPaceDetail = true
                } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "hare.fill")
                                .foregroundColor(.green)
                            Text("Fastest Mile")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Text(formattedFastestPace)
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                            .multilineTextAlignment(.leading)
                        
                        if isCalculating || isRefreshingFastestPace {
                            HStack {
                                ProgressView()
                                    .scaleEffect(0.6)
                                Text("Calculating...")
                                    .font(.caption2)
                                    .foregroundColor(.green)
                            }
                        } else if (statsType == .allTime ? healthManager.fastestMilePace : statsData.fastestPace) > 0 {
                            Text(statsType == .allTime ? "All time" : "Current streak")
                                .font(.caption2)
                                .foregroundColor(.green)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, minHeight: 80, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.green.opacity(0.1))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.green.opacity(0.3), lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(PlainButtonStyle())
                .onLongPressGesture {
                    if statsType == .allTime {
                        // Manual refresh of fastest mile data
                        isRefreshingFastestPace = true
                        healthManager.fetchFastestMilePace()

                        // Set a timeout to stop refreshing indicator
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 seconds (reduced from 2s)
                            isRefreshingFastestPace = false
                        }
                    }
                }
                
                // Most Miles Card
                Button {
                    showMostMilesDetail = true
                } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "calendar.badge.clock")
                                .foregroundColor(.purple)
                            Text("Most in One Day")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Text(String(format: "%.1f mi", mostMiles))
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                        
                        Text(statsType == .allTime ? "All time" : "Current streak")
                            .font(.caption2)
                            .foregroundColor(.purple)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, minHeight: 80, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.purple.opacity(0.1))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.purple.opacity(0.3), lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(PlainButtonStyle())
                
                // Daily Goal / Streak Days Card
                if statsType == .allTime {
                    Button {
                        showGoalSheet = true
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "target")
                                    .foregroundColor(.gray)
                                Text("Daily Goal")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Text(user.goalMiles.milesFormatted)
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.primary)
                            
                            Text("Tap to edit")
                                .font(.caption2)
                                .foregroundColor(.gray)
                        }
                        .padding()
                        .frame(maxWidth: .infinity, minHeight: 80, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.gray.opacity(0.1))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                                )
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "flame.fill")
                                .foregroundColor(.orange)
                            Text("Streak Days")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Text("\(streakDays)")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                        
                        if streakDays > 0 {
                            Text("Current streak")
                                .font(.caption2)
                                .foregroundColor(.orange)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, minHeight: 80, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.orange.opacity(0.1))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                            )
                    )
                }
            }
        }
        .onAppear {
            if statsType == .currentStreak {
                calculateCurrentStreakStats()
            }
        }
        .onChange(of: healthManager.retroactiveStreak) { _, _ in
            if statsType == .currentStreak {
                calculateCurrentStreakStats()
            }
        }
        .onChange(of: statsType) { _, newType in
            if newType == .currentStreak {
                calculateCurrentStreakStats()
            }
        }
        .sheet(isPresented: $showFastestPaceDetail) {
            if statsType == .allTime {
                FastestPaceDetailView(healthManager: healthManager)
            } else {
                CurrentStreakFastestPaceDetailView(healthManager: healthManager, currentStreakStats: statsData)
            }
        }
        .sheet(isPresented: $showMostMilesDetail) {
            if statsType == .allTime {
                MostMilesDetailView(miles: mostMiles, healthManager: healthManager)
            } else {
                CurrentStreakMostMilesDetailView(mostMiles: mostMiles, healthManager: healthManager, currentStreakStats: statsData)
            }
        }
        .sheet(isPresented: $showGoalSheet) {
            GoalSettingSheet(
                currentGoal: user.goalMiles,
                onSave: { newGoal in
                    // Note: This will need to be handled by the parent view
                    // since we don't have access to userManager here
                }
            )
            .presentationDetents([.height(300)])
        }
    }
    
    private func calculateCurrentStreakStats() {
        isCalculating = true
        
        DispatchQueue.global(qos: .userInitiated).async {
            let stats = healthManager.calculateCurrentStreakStats()
            
            DispatchQueue.main.async {
                self.statsData = stats
                self.isCalculating = false
            }
        }
    }
}

// Stats Grid Component with Toggle
struct StatsGridView: View {
    let user: User
    @ObservedObject var healthManager: HealthKitManager
    @State private var selectedStatsView: UnifiedStatsGrid.StatsViewType = .allTime
    
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            // Header with toggle
            HStack {
                Text("Your Stats")
                    .font(.headline)
                
                Spacer()
                
                // Toggle between All Time and Current Streak
                Picker("Stats View", selection: $selectedStatsView) {
                    ForEach(UnifiedStatsGrid.StatsViewType.allCases, id: \.self) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .frame(width: 180)
            }
            
            // Show unified stats view based on selection
            UnifiedStatsGrid(
                user: user,
                healthManager: healthManager,
                statsType: selectedStatsView
            )
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
    @State private var selectedWorkout: IdentifiableWorkout?
    
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
                        selectedWorkout = IdentifiableWorkout(workout: workout)
                    } label: {
                        DashboardWorkoutRow(workout: workout)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
        .padding()
        .cardStyle()
        .sheet(item: $selectedWorkout) { identifiableWorkout in
            WorkoutDetailView(workout: identifiableWorkout.workout)
        }
    }
}

// Workout Row Component for DashboardView (without MADTheme dependency)
struct DashboardWorkoutRow: View {
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
    @State private var splitTimes: [TimeInterval]?
    @State private var isLoadingSplits = false
    @EnvironmentObject var healthManager: HealthKitManager
    
    // Timezone-corrected times from index
    private var correctedEndTime: Date {
        healthManager.getCorrectedLocalTime(for: workout)
    }
    
    private var correctedStartTime: Date {
        let endTime = correctedEndTime
        return endTime.addingTimeInterval(-workout.duration)
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 30) {
                    // Top banner
                    VStack(spacing: 10) {
                        Text(workout.workoutActivityType == .running ? "Run" : "Walk")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        
                        Text(correctedEndTime.formattedDate)
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
                        DashboardStatBox(title: "Duration", value: workout.formattedDuration, icon: "clock.fill", color: .orange)
                        DashboardStatBox(title: "Pace", value: workout.pace, icon: "hare.fill", color: .green)
                        if let calories = calories {
                            DashboardStatBox(title: "Calories Burned", value: "\(Int(calories)) calories", icon: "flame.fill", color: .red)
                        }
                        DashboardStatBox(title: "Type", value: workout.workoutActivityType == .running ? "Running" : "Walking", icon: "figure.run", color: .purple)
                    }
                    .padding()
                    
                    // Additional details
                    VStack(alignment: .leading, spacing: 15) {
                        Text("Workout Details")
                            .font(.headline)
                        
                        // Use timezone-corrected times from index
                        DetailRow(title: "Start Time", value: correctedStartTime.formattedTime)
                        DetailRow(title: "End Time", value: correctedEndTime.formattedTime)
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
                    
                    // Split Times Section
                    if let splitTimes = splitTimes, !splitTimes.isEmpty {
                        VStack(alignment: .leading, spacing: 15) {
                            Text("Mile Splits")
                                .font(.headline)
                            
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                                ForEach(Array(splitTimes.enumerated()), id: \.offset) { index, splitTime in
                                    VStack(spacing: 5) {
                                        Text("Mile \(index + 1)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        
                                        Text(formatSplitTime(splitTime))
                                            .font(.headline)
                                            .foregroundColor(.primary)
                                    }
                                    .padding()
                                    .background(Color(.systemGray6))
                                    .cornerRadius(8)
                                }
                            }
                        }
                        .padding()
                        .background(Color(.systemBackground))
                        .cornerRadius(12)
                        .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
                    } else if isLoadingSplits {
                        VStack(alignment: .leading, spacing: 15) {
                            Text("Mile Splits")
                                .font(.headline)
                            
                            HStack {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Loading split times...")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding()
                        .background(Color(.systemBackground))
                        .cornerRadius(12)
                        .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
                    }
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
                await fetchSplitTimes()
            }
        }
    }
    
    private func fetchSplitTimes() async {
        isLoadingSplits = true
        
        // Create a HealthKitManager instance to access the split times functionality
        let healthManager = HealthKitManager()
        
        await withCheckedContinuation { continuation in
            healthManager.getWorkoutSplitTimes(for: workout) { splits in
                DispatchQueue.main.async {
                    self.splitTimes = splits
                    self.isLoadingSplits = false
                }
                continuation.resume()
            }
        }
    }
    
    private func formatSplitTime(_ splitTime: TimeInterval) -> String {
        let totalMinutes = splitTime
        let minutes = Int(totalMinutes)
        let seconds = Int((totalMinutes - Double(minutes)) * 60)
        
        return String(format: "%d:%02d", minutes, seconds)
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

// StatBox component for DashboardView (without MADTheme dependency)
struct DashboardStatBox: View {
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
    let onSave: (Double) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var newGoalMiles: Double = 1.0
    
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
                    Stepper(value: $newGoalMiles, in: 0.1...26.2, step: 0.1) {
                        HStack {
                            Text("Miles:")
                            Text(newGoalMiles.milesFormatted)
                                .fontWeight(.bold)
                        }
                    }
                }
                
                Section("Common Goals") {
                    Button("1 mile") { newGoalMiles = 1.0 }
                    Button("5K (3.1 miles)") { newGoalMiles = 3.1 }
                    Button("10K (6.2 miles)") { newGoalMiles = 6.2 }
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
                        onSave(newGoalMiles)
                        dismiss()
                    }
                }
            }
            .onAppear {
                newGoalMiles = currentGoal
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

// MARK: - Current Streak Detail Views

// Current Streak Fastest Pace Detail View
struct CurrentStreakFastestPaceDetailView: View {
    @ObservedObject var healthManager: HealthKitManager
    let currentStreakStats: (totalMiles: Double, mostMiles: Double, fastestPace: TimeInterval, streakDays: Int)
    @Environment(\.dismiss) private var dismiss
    @State private var streakWorkouts: [HKWorkout] = []
    @State private var isLoading = true
    @State private var selectedWorkout: IdentifiableWorkout?
    
    var formattedPace: String {
        guard currentStreakStats.fastestPace > 0 else { return "Not yet recorded" }
        
        let totalMinutes = currentStreakStats.fastestPace
        let minutes = Int(totalMinutes)
        let seconds = Int((totalMinutes - Double(minutes)) * 60)
        
        return String(format: "%d:%02d /mi", minutes, seconds)
    }
    
    var speedMph: String {
        guard currentStreakStats.fastestPace > 0 else { return "0.0 mph" }
        return String(format: "%.1f mph", 60 / currentStreakStats.fastestPace)
    }
    
    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: MADTheme.Spacing.xl) {
                    // Top banner
                    VStack(spacing: MADTheme.Spacing.md) {
                        Text("Current Streak")
                            .font(MADTheme.Typography.headline)
                            .foregroundColor(MADTheme.Colors.secondaryText)
                        
                        Text("Fastest Mile Pace")
                            .font(MADTheme.Typography.title1)
                            .fontWeight(.bold)
                            .foregroundColor(MADTheme.Colors.primaryText)
                        
                        Text(formattedPace)
                                .font(.system(size: 48, weight: .bold, design: .rounded))
                            .foregroundColor(MADTheme.Colors.success)
                            .padding(.top, MADTheme.Spacing.sm)
                    }
                    .padding(MADTheme.Spacing.xl)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                            .fill(MADTheme.Colors.success.opacity(0.1))
                    )
                    .madCard(hasShadow: false)
                    
                    // Stats grid
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: MADTheme.Spacing.lg) {
                        StatBox(
                            title: "Pace",
                            value: formattedPace,
                            icon: "hare.fill",
                            color: MADTheme.Colors.success
                        )
                        StatBox(
                            title: "Speed",
                            value: speedMph,
                            icon: "speedometer",
                            color: Color.blue
                        )
                        StatBox(
                            title: "Streak Days",
                            value: "\(currentStreakStats.streakDays)",
                            icon: "flame.fill",
                            color: .orange
                        )
                        StatBox(
                            title: "Total Miles",
                            value: String(format: "%.1f mi", currentStreakStats.totalMiles),
                            icon: "map.fill",
                            color: .blue
                        )
                    }
                    .padding(.horizontal, MADTheme.Spacing.lg)
                    
                    // Performance categories
                    if currentStreakStats.fastestPace > 0 {
                        performanceSection
                    }
                    
                    // Workouts during streak
                    if isLoading {
                        ProgressView("Loading streak workouts...")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if !streakWorkouts.isEmpty {
                        VStack(alignment: .leading, spacing: MADTheme.Spacing.lg) {
                            Text("Fastest Mile During Current Streak")
                                .font(MADTheme.Typography.title3)
                                .fontWeight(.bold)
                                .foregroundColor(MADTheme.Colors.primaryText)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            
                                ForEach(streakWorkouts.prefix(10), id: \.uuid) { workout in
                                Button {
                                    selectedWorkout = IdentifiableWorkout(workout: workout)
                                } label: {
                                    WorkoutRow(workout: workout)
                                        .padding(MADTheme.Spacing.lg)
                                        .madCard()
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                        .padding(.horizontal, MADTheme.Spacing.lg)
                    }
                    
                    // Tips and achievements
                    VStack(alignment: .leading, spacing: MADTheme.Spacing.lg) {
                        Text("Achievements")
                            .font(MADTheme.Typography.title3)
                            .fontWeight(.bold)
                            .foregroundColor(MADTheme.Colors.primaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        HStack(spacing: MADTheme.Spacing.lg) {
                            Image(systemName: "stopwatch.fill")
                                .font(.largeTitle)
                                .foregroundColor(.orange)
                            
                            VStack(alignment: .leading, spacing: MADTheme.Spacing.sm) {
                                Text("Your fastest pace in current streak!")
                                    .font(MADTheme.Typography.headline)
                                    .foregroundColor(MADTheme.Colors.primaryText)
                                
                                Text("You've run a mile at \(formattedPace) during your current streak. Great job!")
                                    .font(MADTheme.Typography.body)
                                    .foregroundColor(MADTheme.Colors.secondaryText)
                            }
                        }
                        .padding(MADTheme.Spacing.lg)
                        .madCard()
                        
                        // Tips for improving pace
                        HStack(spacing: MADTheme.Spacing.lg) {
                            Image(systemName: "bolt.fill")
                                .font(.largeTitle)
                                .foregroundColor(.yellow)
                            
                            VStack(alignment: .leading, spacing: MADTheme.Spacing.sm) {
                                Text("Improve your pace!")
                                    .font(MADTheme.Typography.headline)
                                    .foregroundColor(MADTheme.Colors.primaryText)
                                
                                Text("Try interval training and tempo runs to increase your speed over time.")
                                    .font(MADTheme.Typography.body)
                                    .foregroundColor(MADTheme.Colors.secondaryText)
                            }
                        }
                        .padding(MADTheme.Spacing.lg)
                        .madCard()
                    }
                    .padding(.horizontal, MADTheme.Spacing.lg)
                }
                .padding(MADTheme.Spacing.lg)
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity)
            .clipped()
            .scrollDisabled(false)
            .background(MADTheme.Colors.secondaryBackground)
            .navigationTitle("Streak Pace Record")
            .navigationBarTitleDisplayMode(.inline)
            .scrollContentBackground(.hidden)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .madTertiaryButton()
                }
            }
            .sheet(item: $selectedWorkout) { identifiableWorkout in
                WorkoutDetailView(workout: identifiableWorkout.workout)
            }
            .task {
                await loadStreakWorkouts()
            }
        }
    }
    
    private var performanceSection: some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.lg) {
            Text("Performance Category")
                .font(MADTheme.Typography.title3)
                .fontWeight(.bold)
                .foregroundColor(MADTheme.Colors.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            VStack(spacing: MADTheme.Spacing.md) {
                PerformanceCategoryRow(
                    category: "Elite",
                    paceRange: "< 5:00",
                    isActive: currentStreakStats.fastestPace < 5.0,
                    color: .purple
                )
                
                PerformanceCategoryRow(
                    category: "Competitive",
                    paceRange: "5:00 - 6:30",
                    isActive: currentStreakStats.fastestPace >= 5.0 && currentStreakStats.fastestPace < 6.5,
                    color: MADTheme.Colors.madRed
                )
                
                PerformanceCategoryRow(
                    category: "Recreational",
                    paceRange: "6:30 - 8:00",
                    isActive: currentStreakStats.fastestPace >= 6.5 && currentStreakStats.fastestPace < 8.0,
                    color: Color.blue
                )
                
                PerformanceCategoryRow(
                    category: "Fitness",
                    paceRange: "8:00 - 10:00",
                    isActive: currentStreakStats.fastestPace >= 8.0 && currentStreakStats.fastestPace < 10.0,
                    color: MADTheme.Colors.success
                )
                
                PerformanceCategoryRow(
                    category: "Beginner",
                    paceRange: "10:00+",
                    isActive: currentStreakStats.fastestPace >= 10.0,
                    color: MADTheme.Colors.warning
                )
            }
        }
        .padding(.horizontal, MADTheme.Spacing.lg)
    }
    
    private func loadStreakWorkouts() async {
        isLoading = true
        
        // Use the pre-calculated workouts from HealthKitManager
        // This avoids recalculating split times for every workout
        let allStreakWorkouts = healthManager.getWorkoutsForCurrentStreak()
        let fastestMileWorkouts = healthManager.currentStreakFastestMileWorkouts
        
        // Get all workouts from the day(s) that contain the fastest mile
        var dayWorkouts: [HKWorkout] = []
        
        if !fastestMileWorkouts.isEmpty {
            // Get all unique days that contain fastest mile workouts
            let fastestDays = Set(fastestMileWorkouts.map { Calendar.current.startOfDay(for: $0.endDate) })
            
            // Get all workouts from those days
            dayWorkouts = allStreakWorkouts.filter { workout in
                let workoutDay = Calendar.current.startOfDay(for: workout.endDate)
                return fastestDays.contains(workoutDay)
            }
        }
        
        await MainActor.run {
            self.streakWorkouts = dayWorkouts
            self.isLoading = false
        }
    }
    
    private func formatPace(minutesPerMile: TimeInterval) -> String {
        let totalMinutes = minutesPerMile
        let minutes = Int(totalMinutes)
        let seconds = Int((totalMinutes - Double(minutes)) * 60)
        return String(format: "%d:%02d /mi", minutes, seconds)
    }
}

// Current Streak Most Miles Detail View
struct CurrentStreakMostMilesDetailView: View {
    let mostMiles: Double
    @ObservedObject var healthManager: HealthKitManager
    let currentStreakStats: (totalMiles: Double, mostMiles: Double, fastestPace: TimeInterval, streakDays: Int)
    @Environment(\.dismiss) private var dismiss
    @State private var streakWorkouts: [HKWorkout] = []
    @State private var isLoading = true
    @State private var selectedWorkout: IdentifiableWorkout?
    
    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: MADTheme.Spacing.xl) {
                    // Top banner
                    VStack(spacing: MADTheme.Spacing.md) {
                        Text("Current Streak")
                            .font(MADTheme.Typography.headline)
                            .foregroundColor(MADTheme.Colors.secondaryText)
                        
                        Text("Most Miles in One Day")
                            .font(MADTheme.Typography.title1)
                            .fontWeight(.bold)
                            .foregroundColor(MADTheme.Colors.primaryText)
                        
                        Text(mostMiles.milesFormatted)
                            .font(.system(size: 48, weight: .bold, design: .rounded))
                            .foregroundColor(Color.purple)
                            .padding(.top, MADTheme.Spacing.sm)
                    }
                    .padding(MADTheme.Spacing.xl)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                            .fill(Color.purple.opacity(0.1))
                    )
                    .madCard(hasShadow: false)
                    
                    // Stats grid
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: MADTheme.Spacing.lg) {
                        StatBox(
                            title: "Distance",
                            value: mostMiles.milesFormatted,
                            icon: "map.fill",
                            color: Color.purple
                        )
                        StatBox(
                            title: "Steps",
                            value: String(format: "%.0f steps", mostMiles * 2000),
                            icon: "figure.walk",
                            color: MADTheme.Colors.success
                        )
                        StatBox(
                            title: "Calories Burned",
                            value: String(format: "%.0f calories", mostMiles * 100),
                            icon: "flame.fill",
                            color: MADTheme.Colors.warning
                        )
                        StatBox(
                            title: "Streak Days",
                            value: "\(currentStreakStats.streakDays)",
                            icon: "flame.fill",
                            color: .orange
                        )
                    }
                    .padding(.horizontal, MADTheme.Spacing.lg)
                    
                    // Workouts during streak
                    if isLoading {
                        ProgressView("Loading streak workouts...")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if !streakWorkouts.isEmpty {
                        VStack(alignment: .leading, spacing: MADTheme.Spacing.lg) {
                            Text("Most Miles During Current Streak")
                                .font(MADTheme.Typography.title3)
                                .fontWeight(.bold)
                                .foregroundColor(MADTheme.Colors.primaryText)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            
                                ForEach(streakWorkouts.prefix(10), id: \.uuid) { workout in
                                Button {
                                    selectedWorkout = IdentifiableWorkout(workout: workout)
                                } label: {
                                    WorkoutRow(workout: workout)
                                        .padding(MADTheme.Spacing.lg)
                                        .madCard()
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                        .padding(.horizontal, MADTheme.Spacing.lg)
                    }
                    
                    // Tips and achievements
                    VStack(alignment: .leading, spacing: MADTheme.Spacing.lg) {
                        Text("Achievements")
                            .font(MADTheme.Typography.title3)
                            .fontWeight(.bold)
                            .foregroundColor(MADTheme.Colors.primaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        HStack(spacing: MADTheme.Spacing.lg) {
                            Image(systemName: "trophy.fill")
                                .font(.largeTitle)
                                .foregroundColor(.yellow)
                            
                            VStack(alignment: .leading, spacing: MADTheme.Spacing.sm) {
                                Text("Streak Distance Record!")
                                    .font(MADTheme.Typography.headline)
                                    .foregroundColor(MADTheme.Colors.primaryText)
                                
                                Text("You've covered \(mostMiles.milesFormatted) in a single day during your current streak. Amazing achievement!")
                                    .font(MADTheme.Typography.body)
                                    .foregroundColor(MADTheme.Colors.secondaryText)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(MADTheme.Spacing.lg)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .madCard()
                        
                        // Tips for improving distance
                        HStack(spacing: MADTheme.Spacing.lg) {
                            Image(systemName: "figure.run")
                                .font(.largeTitle)
                                .foregroundColor(MADTheme.Colors.success)
                            
                            VStack(alignment: .leading, spacing: MADTheme.Spacing.sm) {
                                Text("Build Endurance!")
                                    .font(MADTheme.Typography.headline)
                                    .foregroundColor(MADTheme.Colors.primaryText)
                                
                                Text("Gradually increase your daily distance and incorporate long runs into your training.")
                                    .font(MADTheme.Typography.body)
                                    .foregroundColor(MADTheme.Colors.secondaryText)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(MADTheme.Spacing.lg)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .madCard()
                    }
                    .padding(.horizontal, MADTheme.Spacing.lg)
                    .frame(maxWidth: .infinity)
                }
                .padding(MADTheme.Spacing.lg)
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity)
            .clipped()
            .scrollDisabled(false)
            .background(MADTheme.Colors.secondaryBackground)
            .navigationTitle("Streak Distance Record")
            .navigationBarTitleDisplayMode(.inline)
            .scrollContentBackground(.hidden)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .madTertiaryButton()
                }
            }
            .sheet(item: $selectedWorkout) { identifiableWorkout in
                WorkoutDetailView(workout: identifiableWorkout.workout)
            }
            .task {
                await loadStreakWorkouts()
            }
        }
    }
    
    private func loadStreakWorkouts() async {
        isLoading = true
        
        // Get workouts for the specific day that had the most miles
        // We need to find which day had the most miles and get workouts from that day only
        let allStreakWorkouts = healthManager.getWorkoutsForCurrentStreak()
        let workoutsByDay = Dictionary(grouping: allStreakWorkouts) { workout in
            Calendar.current.startOfDay(for: workout.endDate)
        }
        
        // Find the day with the most miles
        var mostMilesDay: Date?
        var maxMiles = 0.0
        
        for (date, workouts) in workoutsByDay {
            let dayMiles = workouts.reduce(0.0) { total, workout in
                if let distance = workout.totalDistance {
                    return total + distance.doubleValue(for: HKUnit.mile())
                }
                return total
            }
            
            if dayMiles > maxMiles {
                maxMiles = dayMiles
                mostMilesDay = date
            }
        }
        
        // Get workouts from the specific day with most miles
        let dayWorkouts = mostMilesDay != nil ? (workoutsByDay[mostMilesDay!] ?? []) : []
        
        await MainActor.run {
            self.streakWorkouts = dayWorkouts
            self.isLoading = false
        }
    }
    
    private func formatPace(minutesPerMile: TimeInterval) -> String {
        let totalMinutes = minutesPerMile
        let minutes = Int(totalMinutes)
        let seconds = Int((totalMinutes - Double(minutes)) * 60)
        return String(format: "%d:%02d /mi", minutes, seconds)
    }
}

// MARK: - Share Views

struct StreakShareView: View {
    let streak: Int
    let isGoalCompleted: Bool
    let isAtRisk: Bool
    
    // Dynamic colors for share view
    var streakColor: Color {
        if isGoalCompleted {
            return .green
        } else if isAtRisk {
            return .red
        } else {
            return .orange
        }
    }
    
    var gradientColors: [Color] {
        if isGoalCompleted {
            return [.green.opacity(0.3), .green.opacity(0.1)]
        } else if isAtRisk {
            return [.red.opacity(0.3), .red.opacity(0.1)]
        } else {
            return [.orange.opacity(0.3), .orange.opacity(0.1)]
        }
    }
    
    var body: some View {
        VStack(spacing: 20) {
            // App branding
            HStack {
                Image(systemName: "figure.run")
                    .font(.title)
                    .foregroundColor(.orange)
                Text("Mile A Day")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
            }
            
            // Streak display
            VStack(spacing: 16) {
                Text("Current Streak")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                ZStack {
                    // Background circle
                    Circle()
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: gradientColors),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 140, height: 140)
                    
                    // Progress ring
                    Circle()
                        .stroke(Color.gray.opacity(0.2), lineWidth: 6)
                        .frame(width: 150, height: 150)
                    
                    Circle()
                        .trim(from: 0, to: isGoalCompleted ? 1.0 : (isAtRisk ? 0.2 : 0.8))
                        .stroke(streakColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .frame(width: 150, height: 150)
                        .rotationEffect(.degrees(-90))
                    
                    // Center content
                    VStack(spacing: 4) {
                        Text("\(streak)")
                            .font(.system(size: 48, weight: .bold, design: .rounded))
                            .foregroundColor(streakColor)
                        
                        Text(streak == 1 ? "day" : "days")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(streakColor.opacity(0.8))
                    }
                }
                
                // Status message
                if isGoalCompleted {
                    Text("Goal Completed Today! 🎉")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.green)
                } else if isAtRisk {
                    Text("Streak at risk! ⚠️")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.red)
                } else {
                    Text("Keep the streak alive!")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            
            // Footer
            Text("Track your daily mile progress with Mile A Day")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(40)
        .background(
            LinearGradient(
                gradient: Gradient(colors: [Color(.systemBackground), Color(.systemGray6)]),
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .frame(width: 400, height: 600)
    }
}

struct TodayProgressShareView: View {
    let currentDistance: Double
    let goalDistance: Double
    let progress: Double
    let didComplete: Bool
    let totalMiles: Double
    
    var body: some View {
        VStack(spacing: 20) {
            // App branding
            HStack {
                Image(systemName: "figure.run")
                    .font(.title)
                    .foregroundColor(.orange)
                Text("Mile A Day")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
            }
            
            // Progress display
            VStack(spacing: 16) {
                Text("Today's Progress")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                // Progress Bar
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.gray.opacity(0.2))
                            .frame(height: 24)
                        
                        RoundedRectangle(cornerRadius: 12)
                            .fill(didComplete ? Color.green : Color.orange)
                            .frame(width: progress * geometry.size.width, height: 24)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .frame(height: 24)
                
                // Distance Display
                HStack(spacing: 8) {
                    Text(String(format: "%.2f", currentDistance))
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                    
                    Text("of")
                        .font(.title3)
                        .foregroundColor(.secondary)
                    
                    Text(String(format: "%.1f mi", goalDistance))
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                }
                
                if didComplete {
                    Label("Goal Complete!", systemImage: "star.fill")
                        .foregroundColor(.green)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                } else {
                    let remaining = max(goalDistance - currentDistance, 0.0)
                    Text(String(format: "%.2f mi to go", remaining))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                // Total miles display
                HStack {
                    Image(systemName: "trophy.fill")
                        .foregroundColor(.orange)
                        .font(.subheadline)
                    Text(String(format: "Total Miles: %.1f", totalMiles))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                }
                .padding(.top, 8)
            }
            
            // Footer
            Text("Track your daily mile progress with Mile A Day")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(40)
        .background(
            LinearGradient(
                gradient: Gradient(colors: [Color(.systemBackground), Color(.systemGray6)]),
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .frame(width: 400, height: 600)
    }
}

// MARK: - Dashboard Card Share Views

struct StreakCardShareView: View {
    let streak: Int
    let isActiveToday: Bool
    let isAtRisk: Bool
    let user: User
    let progress: Double
    let isGoalCompleted: Bool
    @Environment(\.colorScheme) var colorScheme

    // Dynamic colors based on streak status
    var streakColor: Color {
        if isGoalCompleted {
            return .green
        } else if isAtRisk {
            return .red
        } else {
            return .orange
        }
    }

    var gradientColors: [Color] {
        if isGoalCompleted {
            return [.green.opacity(0.3), .green.opacity(0.1)]
        } else if isAtRisk {
            return [.red.opacity(0.3), .red.opacity(0.1)]
        } else {
            return [.orange.opacity(0.3), .orange.opacity(0.1)]
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // MAD Branding Header
            HStack(spacing: 8) {
                Image("mad-logo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: 1) {
                    Text("MILE A DAY")
                        .font(.system(size: 14, weight: .bold))
                        .tracking(0.5)

                    Text("Stay Active. Stay Motivated.")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.secondary)
                }

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)

            VStack(spacing: 10) {
                // Title
                Text("Current Streak")
                    .font(.headline)
                    .fontWeight(.semibold)

                // Streak circle
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: gradientColors),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 100, height: 100)

                    Circle()
                        .stroke(Color.gray.opacity(0.2), lineWidth: 4)
                        .frame(width: 108, height: 108)

                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(streakColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .frame(width: 108, height: 108)
                        .rotationEffect(.degrees(-90))

                    VStack(spacing: 2) {
                        Text("\(streak)")
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .foregroundColor(streakColor)

                        Text(streak == 1 ? "day" : "days")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(streakColor.opacity(0.8))
                    }
                }

                // Status message
                VStack(spacing: 2) {
                    if isGoalCompleted {
                        Label("Goal completed!", systemImage: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.caption)
                            .fontWeight(.medium)
                    } else if isAtRisk {
                        Label("Streak at risk!", systemImage: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                            .font(.caption)
                            .fontWeight(.medium)
                    } else {
                        Text("Keep it going!")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(16)
        }
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .fill(.ultraThinMaterial)

                LinearGradient(
                    colors: [
                        streakColor.opacity(0.05),
                        Color.clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .clipShape(RoundedRectangle(cornerRadius: 20))

                RoundedRectangle(cornerRadius: 20)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(colorScheme == .dark ? 0.2 : 0.3),
                                Color.clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
        )
        .shadow(color: .black.opacity(0.15), radius: 15, x: 0, y: 8)
        .frame(width: 300, height: 380)
    }
}

struct TodayProgressCardShareView: View {
    let currentDistance: Double
    let goalDistance: Double
    let progress: Double
    let didComplete: Bool
    let totalMiles: Double
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            // MAD Branding Header
            HStack(spacing: 8) {
                Image("mad-logo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: 1) {
                    Text("MILE A DAY")
                        .font(.system(size: 14, weight: .bold))
                        .tracking(0.5)

                    Text("Stay Active. Stay Motivated.")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.secondary)
                }

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)

            VStack(spacing: 12) {
                // Header
                HStack {
                    Image(systemName: "figure.run")
                        .foregroundColor(.primary)
                    Text("Today's Progress")
                        .font(.headline)
                        .fontWeight(.semibold)
                    Spacer()
                    if didComplete {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    }
                }

                // Progress Bar
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.gray.opacity(0.2))
                            .frame(height: 14)

                        RoundedRectangle(cornerRadius: 8)
                            .fill(didComplete ? Color.green : Color(red: 217/255, green: 64/255, blue: 63/255))
                            .frame(width: progress * geometry.size.width, height: 14)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .frame(height: 14)

                // Distance Display
                HStack {
                    Text(String(format: "%.2f", currentDistance))
                        .font(.title2)
                        .fontWeight(.bold)

                    Text("of")
                        .font(.subheadline)

                    Text(String(format: "%.1f mi", goalDistance))
                        .font(.title2)
                        .fontWeight(.bold)
                }

                // Status or remaining distance
                if didComplete {
                    Label("Goal Complete!", systemImage: "star.fill")
                        .foregroundColor(.green)
                        .font(.caption)
                } else {
                    let remaining = max(goalDistance - currentDistance, 0.0)
                    Text(String(format: "%.2f mi to go", remaining))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // Total miles display
                HStack {
                    Image(systemName: "trophy.fill")
                        .foregroundColor(.orange)
                        .font(.caption)
                    Text(String(format: "Total Miles: %.1f", totalMiles))
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                }
            }
            .padding(16)
        }
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .fill(.ultraThinMaterial)

                LinearGradient(
                    colors: [
                        (didComplete ? Color.green : Color(red: 217/255, green: 64/255, blue: 63/255)).opacity(0.05),
                        Color.clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .clipShape(RoundedRectangle(cornerRadius: 20))

                RoundedRectangle(cornerRadius: 20)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(colorScheme == .dark ? 0.2 : 0.3),
                                Color.clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
        )
        .shadow(color: .black.opacity(0.15), radius: 15, x: 0, y: 8)
        .frame(width: 300, height: 350)
    }
}

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Share Preview View

struct SharePreviewView: View {
    let streakImage: UIImage?
    let progressImage: UIImage?
    let title: String
    let initialTab: Int // 0 for streak, 1 for progress
    let user: User
    let progress: Double
    let isGoalCompleted: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var showingShareSheet = false
    @State private var selectedImage: UIImage?
    @State private var copyButtonText = "Copy"
    @State private var showingCopiedFeedback = false
    @State private var currentTab = 0
    @State private var selectedTheme: ColorScheme = .light
    @State private var regeneratedImages: (streak: UIImage?, progress: UIImage?) = (nil, nil)
    @Environment(\.colorScheme) private var systemColorScheme
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Carousel for multiple images
                if let streakImage = streakImage, let progressImage = progressImage {
                    // Both images available - show carousel
                    TabView(selection: $currentTab) {
                        // Streak image
                        VStack(spacing: 12) {
                            Text("Streak")
                                .font(.headline)
                                .fontWeight(.semibold)
                            
                            Image(uiImage: regeneratedImages.streak ?? streakImage)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .padding()
                        }
                        .tag(0)
                        
                        // Progress image
                        VStack(spacing: 12) {
                            Text("Progress")
                                .font(.headline)
                                .fontWeight(.semibold)
                            
                            Image(uiImage: regeneratedImages.progress ?? progressImage)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .padding()
                        }
                        .tag(1)
                    }
                    .tabViewStyle(PageTabViewStyle())
                    .indexViewStyle(PageIndexViewStyle(backgroundDisplayMode: .always))
                    .onAppear {
                        currentTab = initialTab
                        selectedTheme = systemColorScheme
                        selectedImage = initialTab == 0 ? (regeneratedImages.streak ?? streakImage) : (regeneratedImages.progress ?? progressImage)
                        regenerateImages()
                    }
                    .onChange(of: currentTab) { _, newValue in
                        selectedImage = newValue == 0 ? (regeneratedImages.streak ?? streakImage) : (regeneratedImages.progress ?? progressImage)
                    }
                    .onChange(of: showingCopiedFeedback) { _, newValue in
                        if newValue {
                            Task { @MainActor in
                                try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 seconds
                                copyButtonText = "Copy"
                                showingCopiedFeedback = false
                            }
                        }
                    }
                } else {
                    // Single image
                    Image(uiImage: selectedImage ?? (regeneratedImages.streak ?? streakImage) ?? (regeneratedImages.progress ?? progressImage) ?? UIImage())
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding()
                        .onAppear {
                            selectedTheme = systemColorScheme
                            selectedImage = regeneratedImages.streak ?? regeneratedImages.progress ?? streakImage ?? progressImage
                            regenerateImages()
                        }
                }
                
                // Action buttons
                HStack(spacing: 12) {
                    // Copy button
                    Button {
                        if let imageToCopy = selectedImage {
                            UIPasteboard.general.image = imageToCopy
                            // Haptic feedback for copy
                            let impact = UIImpactFeedbackGenerator(style: .medium)
                            impact.impactOccurred()
                            
                            // Show "Copied!" feedback
                            copyButtonText = "Copied!"
                            showingCopiedFeedback = true
                        }
                    } label: {
                        HStack {
                            Image(systemName: showingCopiedFeedback ? "checkmark" : "doc.on.doc")
                            Text(copyButtonText)
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(showingCopiedFeedback ? Color.green : Color.green)
                        .cornerRadius(12)
                        .animation(.easeInOut(duration: 0.2), value: showingCopiedFeedback)
                    }
                    .disabled(selectedImage == nil)
                    
                    // Share button
                    Button {
                        showingShareSheet = true
                    } label: {
                        HStack {
                            Image(systemName: "square.and.arrow.up")
                            Text("Share")
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(12)
                    }
                    .disabled(selectedImage == nil)
                }
                .padding(.horizontal)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        selectedTheme = selectedTheme == .light ? .dark : .light
                        regenerateImages()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: selectedTheme == .light ? "moon.fill" : "sun.max.fill")
                                .foregroundColor(selectedTheme == .light ? .blue : .orange)
                            Text(selectedTheme == .light ? "Dark" : "Light")
                                .font(.caption)
                                .foregroundColor(selectedTheme == .light ? .blue : .orange)
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showingShareSheet) {
            if let image = selectedImage {
                ShareSheet(items: [image])
            }
        }
    }
    
    private func regenerateImages() {
        // Generate new images with the selected theme
        let streakRenderer = ImageRenderer(content: StreakCardShareView(
            streak: user.streak,
            isActiveToday: user.isStreakActiveToday,
            isAtRisk: user.isStreakAtRisk,
            user: user,
            progress: progress,
            isGoalCompleted: isGoalCompleted
        ).environment(\.colorScheme, selectedTheme))
        streakRenderer.scale = 3.0
        
        let progressRenderer = ImageRenderer(content: TodayProgressCardShareView(
            currentDistance: progress * user.goalMiles,
            goalDistance: user.goalMiles,
            progress: progress,
            didComplete: isGoalCompleted,
            totalMiles: user.totalMiles
        ).environment(\.colorScheme, selectedTheme))
        progressRenderer.scale = 3.0
        
        if let streakImg = streakRenderer.uiImage, let progressImg = progressRenderer.uiImage {
            regeneratedImages = (streak: streakImg, progress: progressImg)
            selectedImage = currentTab == 0 ? streakImg : progressImg
        }
    }
}

// MARK: - Workout Tracking View

struct WorkoutTrackingView: View {
    @ObservedObject var healthManager: HealthKitManager
    @ObservedObject var userManager: UserManager
    let goalDistance: Double
    @Environment(\.dismiss) var dismiss

    @State private var countdownNumber = 3
    @State private var showCountdown = true
    @State private var isTracking = false
    @State private var elapsedTime: TimeInterval = 0
    @State private var currentDistance: Double = 0.0
    @State private var timer: Timer?
    @State private var workoutStartDate: Date?
    @State private var showCompletion = false
    @State private var showRecap = false
    @State private var workoutSession: HKWorkoutSession?
    @State private var workoutBuilder: HKLiveWorkoutBuilder?

    private var progress: Double {
        min(currentDistance / goalDistance, 1.0)
    }

    private var formattedTime: String {
        let minutes = Int(elapsedTime) / 60
        let seconds = Int(elapsedTime) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    var body: some View {
        ZStack {
            // Gradient background
            MADTheme.Colors.appBackgroundGradient
                .ignoresSafeArea()

            if showCountdown {
                // Countdown view
                VStack {
                    Text("\(countdownNumber)")
                        .font(.system(size: 120, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .scaleEffect(countdownNumber > 0 ? 1.0 : 0.5)
                        .opacity(countdownNumber > 0 ? 1.0 : 0.0)
                        .animation(.spring(response: 0.5, dampingFraction: 0.6), value: countdownNumber)
                }
                .onAppear {
                    startCountdown()
                }
            } else if showRecap {
                WorkoutRecapView(
                    distance: currentDistance,
                    duration: elapsedTime,
                    goalDistance: goalDistance,
                    onDismiss: {
                        dismiss()
                    }
                )
            } else {
                // Tracking view
                VStack(spacing: 40) {
                    Spacer()

                    // Distance display
                    VStack(spacing: 12) {
                        Text("DISTANCE")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.white.opacity(0.7))
                            .tracking(1.5)

                        Text(String(format: "%.2f", currentDistance))
                            .font(.system(size: 80, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .contentTransition(.numericText())

                        Text("miles")
                            .font(.title2)
                            .foregroundColor(.white.opacity(0.8))
                    }

                    // Progress ring
                    ZStack {
                        Circle()
                            .stroke(Color.white.opacity(0.2), lineWidth: 12)
                            .frame(width: 200, height: 200)

                        Circle()
                            .trim(from: 0, to: progress)
                            .stroke(
                                LinearGradient(
                                    colors: progress >= 1.0 ? [.green, .green] : [.orange, .red],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                style: StrokeStyle(lineWidth: 12, lineCap: .round)
                            )
                            .frame(width: 200, height: 200)
                            .rotationEffect(.degrees(-90))
                            .animation(.easeOut(duration: 0.5), value: progress)

                        VStack(spacing: 4) {
                            Text("\(Int(progress * 100))%")
                                .font(.system(size: 36, weight: .bold, design: .rounded))
                                .foregroundColor(.white)

                            Text("of goal")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }

                    // Time display
                    VStack(spacing: 8) {
                        Text("TIME")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.white.opacity(0.7))
                            .tracking(1.5)

                        Text(formattedTime)
                            .font(.system(size: 48, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                            .monospacedDigit()
                    }

                    Spacer()

                    // Stop button
                    Button(action: {
                        stopWorkout()
                    }) {
                        HStack(spacing: 12) {
                            Image(systemName: "stop.fill")
                                .font(.title2)
                            Text("Stop Workout")
                                .font(.title3)
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.red.opacity(0.3))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(Color.red, lineWidth: 2)
                                )
                        )
                    }
                    .padding(.horizontal, 32)
                    .padding(.bottom, 40)
                    .buttonStyle(PlainButtonStyle())
                }
                .opacity(showCompletion ? 0 : 1)
                .overlay(
                    // Completion celebration
                    Group {
                        if showCompletion {
                            VStack(spacing: 24) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 100))
                                    .foregroundStyle(
                                        LinearGradient(
                                            colors: [.green, .green.opacity(0.7)],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                                    .scaleEffect(showCompletion ? 1.0 : 0.5)
                                    .animation(.spring(response: 0.6, dampingFraction: 0.6), value: showCompletion)

                                Text("Goal Complete!")
                                    .font(.system(size: 48, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)

                                Text("You did it! Keep going or finish your workout.")
                                    .font(.title3)
                                    .foregroundColor(.white.opacity(0.9))
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 40)
                            }
                            .transition(.scale.combined(with: .opacity))
                        }
                    }
                )
            }
        }
        .onChange(of: currentDistance) { oldValue, newValue in
            if !showCompletion && newValue >= goalDistance {
                // Show completion celebration
                withAnimation {
                    showCompletion = true
                }

                // Haptic feedback
                let notification = UINotificationFeedbackGenerator()
                notification.notificationOccurred(.success)

                // Hide completion after 3 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    withAnimation {
                        showCompletion = false
                    }
                }
            }
        }
    }

    private func startCountdown() {
        // Haptic feedback for countdown
        let impact = UIImpactFeedbackGenerator(style: .heavy)

        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
            if countdownNumber > 1 {
                countdownNumber -= 1
                impact.impactOccurred()
            } else {
                timer.invalidate()
                // Start workout
                withAnimation {
                    showCountdown = false
                    isTracking = true
                }
                startWorkout()
            }
        }
    }

    private func startWorkout() {
        workoutStartDate = Date()

        // Request authorization first
        healthManager.requestAuthorization { authorized in
            guard authorized else {
                print("HealthKit authorization denied")
                return
            }

            // Start HealthKit workout session
            let configuration = HKWorkoutConfiguration()
            configuration.activityType = .walking
            configuration.locationType = .outdoor

            do {
                let healthStore = HKHealthStore()
                let session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
                let builder = session.associatedWorkoutBuilder()

                self.workoutSession = session
                self.workoutBuilder = builder

                builder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: configuration)

                let startDate = Date()
                session.startActivity(with: startDate)

                builder.beginCollection(withStart: startDate) { success, error in
                    if let error = error {
                        print("Failed to start workout collection: \(error)")
                        return
                    }

                    if success {
                        // Start timer for elapsed time
                        DispatchQueue.main.async {
                            self.timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                                if let startDate = self.workoutStartDate {
                                    self.elapsedTime = Date().timeIntervalSince(startDate)
                                }

                                // Update distance from builder
                                if let statistics = builder.statistics(for: HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning)!) {
                                    let distanceMeters = statistics.sumQuantity()?.doubleValue(for: HKUnit.meter()) ?? 0
                                    DispatchQueue.main.async {
                                        self.currentDistance = distanceMeters * 0.000621371 // Convert to miles
                                    }
                                }
                            }
                        }
                    }
                }
            } catch {
                print("Failed to start workout: \(error)")
            }
        }
    }

    private func stopWorkout() {
        // Stop timer
        timer?.invalidate()
        timer = nil

        // End HealthKit workout session
        if let session = workoutSession, let builder = workoutBuilder {
            let endDate = Date()
            session.end()

            builder.endCollection(withEnd: endDate) { success, error in
                if let error = error {
                    print("Failed to end workout collection: \(error)")
                    // Show recap anyway
                    DispatchQueue.main.async {
                        withAnimation {
                            self.showRecap = true
                        }
                    }
                    return
                }

                if success {
                    builder.finishWorkout { workout, error in
                        if let error = error {
                            print("Failed to finish workout: \(error)")
                        } else if let workout = workout {
                            // Workout saved to HealthKit
                            print("Workout saved: \(workout)")

                            // Refresh health data
                            DispatchQueue.main.async {
                                self.healthManager.fetchAllWorkoutData()
                            }
                        }

                        // Show recap
                        DispatchQueue.main.async {
                            withAnimation {
                                self.showRecap = true
                            }
                        }
                    }
                } else {
                    // Show recap anyway
                    DispatchQueue.main.async {
                        withAnimation {
                            self.showRecap = true
                        }
                    }
                }
            }
        } else {
            // No active session, just show recap
            withAnimation {
                showRecap = true
            }
        }
    }
}

// MARK: - Workout Recap View

struct WorkoutRecapView: View {
    let distance: Double
    let duration: TimeInterval
    let goalDistance: Double
    let onDismiss: () -> Void

    private var formattedTime: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private var pace: String {
        guard distance > 0 else { return "--:--" }
        let paceSeconds = duration / distance
        let minutes = Int(paceSeconds) / 60
        let seconds = Int(paceSeconds) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    var body: some View {
        ZStack {
            // Gradient background
            MADTheme.Colors.appBackgroundGradient
                .ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer()

                // Header
                VStack(spacing: 12) {
                    Image(systemName: distance >= goalDistance ? "checkmark.circle.fill" : "flag.checkered.circle.fill")
                        .font(.system(size: 80))
                        .foregroundStyle(
                            LinearGradient(
                                colors: distance >= goalDistance ? [.green, .green] : [.orange, .red],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                    Text(distance >= goalDistance ? "Workout Complete!" : "Great Work!")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundColor(.white)

                    if distance >= goalDistance {
                        Text("You reached your goal!")
                            .font(.title3)
                            .foregroundColor(.white.opacity(0.9))
                    }
                }

                // Stats
                VStack(spacing: 20) {
                    StatRow(icon: "figure.walk", label: "Distance", value: String(format: "%.2f mi", distance))
                    StatRow(icon: "clock.fill", label: "Time", value: formattedTime)
                    StatRow(icon: "speedometer", label: "Avg Pace", value: "\(pace) /mi")

                    if distance >= goalDistance {
                        StatRow(icon: "target", label: "Goal", value: "✓ Completed")
                    } else {
                        StatRow(icon: "target", label: "Goal Progress", value: String(format: "%.0f%%", (distance / goalDistance) * 100))
                    }
                }
                .padding(24)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color.white.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                        )
                )
                .padding(.horizontal, 32)

                Spacer()

                // Done button
                Button(action: onDismiss) {
                    Text("Done")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color(red: 217/255, green: 64/255, blue: 63/255),
                                            Color(red: 180/255, green: 50/255, blue: 50/255)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        )
                        .shadow(color: Color(red: 217/255, green: 64/255, blue: 63/255).opacity(0.4), radius: 12, x: 0, y: 6)
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 40)
                .buttonStyle(PlainButtonStyle())
            }
        }
    }
}

struct StatRow: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.white.opacity(0.7))
                .frame(width: 32)

            Text(label)
                .font(.headline)
                .foregroundColor(.white.opacity(0.9))

            Spacer()

            Text(value)
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(.white)
        }
    }
}