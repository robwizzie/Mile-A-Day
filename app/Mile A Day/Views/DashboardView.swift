import SwiftUI
import HealthKit
import WidgetKit
import UIKit

struct DashboardView: View {
    @ObservedObject var healthManager: HealthKitManager
    @ObservedObject var userManager: UserManager
    @EnvironmentObject var notificationService: MADNotificationService
    
    @State private var showConfetti = false
    @State private var showGoalSheet = false
    @State private var newGoalMiles: Double = 1.0
    @State private var isRefreshing = false
    @State private var showInstructions = false
    @State private var showCelebration = false
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
                VStack(spacing: 20) {
                    // Instructions banner
                    InstructionsBanner(
                        showInstructions: $showInstructions
                    )
                    
                    // Today's progress with static data
                    TodayProgressCard(
                        currentDistance: currentState.distance,
                        goalDistance: currentState.goal,
                        progress: currentState.progress,
                        didComplete: currentState.isCompleted,
                        onRefresh: refreshData,
                        isRefreshing: isRefreshing,
                        user: userManager.currentUser
                    )
                    
                    // Streak card with simplified progress
                    StreakCard(
                        streak: userManager.currentUser.streak, 
                        isActiveToday: userManager.currentUser.isStreakActiveToday,
                        isAtRisk: userManager.currentUser.isStreakAtRisk,
                        user: userManager.currentUser,
                        progress: currentState.progress,
                        isGoalCompleted: currentState.isCompleted,
                        isRefreshing: isRefreshing
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
                    HStack(spacing: 16) {
                        Button {
                            showInstructions = true
                        } label: {
                            Image(systemName: "info.circle")
                                .foregroundColor(.blue)
                        }
                        
                    Button {
                        showGoalSheet = true
                    } label: {
                        Image(systemName: "gear")
                        }
                        
                        // Test celebration animation button (only in debug)
                        #if DEBUG
                        Button {
                            showCelebration = true
                        } label: {
                            Image(systemName: "star.fill")
                                .foregroundColor(.yellow)
                        }
                        #endif
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
                // Always sync widget data when the dashboard appears - multiple times for reliability
                syncWidgetData()
                
                // Ensure fastest mile data is fresh and reliable
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    healthManager.fetchFastestMilePace()
                }
                
                // Additional widget sync after a delay to ensure consistency
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    syncWidgetData()
                }
                
                // Check if this is the first time opening the app after completing today's goal (UTC-based)
                var utcCal = Calendar.current
                utcCal.timeZone = TimeZone(secondsFromGMT: 0)!
                let today = utcCal.startOfDay(for: Date())
                let lastCompletion = utcCal.startOfDay(for: lastGoalCompletionDate)
                
                if currentState.isCompleted && today != lastCompletion {
                    // This is the first time opening after completing today's goal
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
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
        
        print("[Dashboard] Synced widget data - Miles: \(state.distance), Goal: \(state.goal), Progress: \(state.progress * 100)%, Streak: \(userManager.currentUser.streak)")
    }
    
    private func refreshData() {
        isRefreshing = true
        
        // Fetch data in order to ensure consistency
        healthManager.fetchAllWorkoutData()
        
        // Allow time for HealthKit data to process, then sync widgets multiple times for reliability
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            syncWidgetData()
        }
        
        // Additional sync after a longer delay to ensure data consistency
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            syncWidgetData()
            isRefreshing = false
        }
    }
    
    private func refreshDataAsync() async {
        await withCheckedContinuation { continuation in
            isRefreshing = true
            healthManager.fetchAllWorkoutData()
            
            // Allow time for HealthKit data to process
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                syncWidgetData()
            }
            
            // Additional sync for reliability
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                syncWidgetData()
                isRefreshing = false
                continuation.resume()
            }
        }
    }
    
    private func triggerConfetti() {
        showConfetti = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            showConfetti = false
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
    @State private var animateStreak = false
    @State private var showingShareSheet = false
    @State private var streakImage: UIImage?
    @State private var progressImage: UIImage?
    @State private var isPressed = false
    
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
    
    var backgroundColor: Color {
        if isGoalCompleted {
            return .green.opacity(0.1)
        } else if isAtRisk {
            return .red.opacity(0.1)
        } else {
            return .orange.opacity(0.1)
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
        VStack(spacing: 12) {
            // Title
            Text("Current Streak")
                .font(.headline)
                .fontWeight(.semibold)
            
            // Streak circle with fire icon (matching widget design)
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
                    .frame(width: 120, height: 120)
                    .scaleEffect(isPressed ? 0.95 : 1.0)
                
                // Progress ring - now changes color with streak status
                Circle()
                    .stroke(Color.gray.opacity(0.2), lineWidth: 5)
                    .frame(width: 130, height: 130)
                
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(streakColor, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .frame(width: 130, height: 130)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.8), value: progress)
                
                // Loading indicator overlay when refreshing
                if isRefreshing {
                    Circle()
                        .stroke(Color.blue.opacity(0.3), lineWidth: 2)
                        .frame(width: 140, height: 140)
                        .rotationEffect(.degrees(-90))
                        .overlay(
                            Circle()
                                .trim(from: 0, to: 0.25)
                                .stroke(Color.blue, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                                .frame(width: 140, height: 140)
                                .rotationEffect(.degrees(animateStreak ? 360 : 0))
                                .animation(.linear(duration: 1.0).repeatForever(autoreverses: false), value: animateStreak)
                        )
                }
                
                // Center content
                VStack(spacing: 4) {
                    Text("\(streak)")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundColor(streakColor)
                        .scaleEffect(animateStreak && !isRefreshing ? 1.1 : 1.0)
                        .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: animateStreak)
                        .opacity(isRefreshing ? 0.6 : 1.0)
                    
                    Text(streak == 1 ? "day" : "days")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(streakColor.opacity(0.8))
                        .opacity(isRefreshing ? 0.6 : 1.0)
                }
            }
            
            // Status message with time until streak reset
            VStack(spacing: 4) {
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
                    
                    // Show time until streak ends - use same color as streak
                    Text(user.formattedTimeUntilReset)
                        .font(.caption2)
                        .foregroundColor(streakColor.opacity(0.8))
                        .fontWeight(.medium)
                } else {
                    Text("Keep it going!")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    // Show time until streak is at risk if not completed - use same color as streak
                    if !isActiveToday, user.timeUntilStreakReset != nil {
                        Text(user.formattedTimeUntilReset)
                            .font(.caption2)
                            .foregroundColor(streakColor.opacity(0.8))
                    }
                }
            }
            

        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color(.systemGray4), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
        )
        .scaleEffect(isPressed ? 0.98 : 1.0)
        .animation(.easeInOut(duration: 0.1), value: isPressed)
        .onLongPressGesture(minimumDuration: 0.5, maximumDistance: 50) {
            generateShareImage(theme: colorScheme)
        } onPressingChanged: { pressing in
            withAnimation(.easeInOut(duration: 0.1)) {
                isPressed = pressing
            }
            
            if pressing {
                // Light haptic feedback when press starts
                let impact = UIImpactFeedbackGenerator(style: .light)
                impact.impactOccurred()
            } else {
                // Medium haptic feedback when released/completed
                let impact = UIImpactFeedbackGenerator(style: .medium)
                impact.impactOccurred()
            }
        }
        .sheet(isPresented: $showingShareSheet) {
            SharePreviewView(streakImage: streakImage, progressImage: progressImage, title: "Share", initialTab: 0, user: user, progress: progress, isGoalCompleted: isGoalCompleted)
        }
        .onAppear {
            // Start pulsing animation for streaks at risk (but not while refreshing)
            if isAtRisk && !isRefreshing {
                animateStreak = true
            }
        }
        .onChange(of: isRefreshing) { oldValue, newValue in
            if newValue {
                // Start loading animation
                animateStreak = true
            } else {
                // Stop loading animation and start appropriate streak animation
                if isAtRisk {
                    // Keep animating for at-risk streaks
                    animateStreak = true
                } else {
                    // Stop animation for normal streaks
                    animateStreak = false
                }
            }
        }
    }
    
    @Environment(\.colorScheme) private var colorScheme
    
    private func generateShareImage(theme: ColorScheme = .light) {
        // Generate streak image that matches dashboard exactly
        let streakRenderer = ImageRenderer(content: StreakCardShareView(
            streak: streak,
            isActiveToday: isActiveToday,
            isAtRisk: isAtRisk,
            user: user,
            progress: progress,
            isGoalCompleted: isGoalCompleted
        ).environment(\.colorScheme, theme))
        streakRenderer.scale = 3.0 // High resolution for Instagram
        
        // Generate progress image that matches dashboard exactly
        let progressRenderer = ImageRenderer(content: TodayProgressCardShareView(
            currentDistance: progress * user.goalMiles,
            goalDistance: user.goalMiles,
            progress: progress,
            didComplete: isGoalCompleted,
            totalMiles: user.totalMiles
        ).environment(\.colorScheme, theme))
        progressRenderer.scale = 3.0 // High resolution for Instagram
        
        if let streakImg = streakRenderer.uiImage, let progressImg = progressRenderer.uiImage {
            streakImage = streakImg
            progressImage = progressImg
            showingShareSheet = true
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
    @State private var animateProgress = false
    @State private var animateNumbers = false
    @State private var animateBar = false
    @State private var showingShareSheet = false
    @State private var streakImage: UIImage?
    @State private var progressImage: UIImage?
    @State private var isPressed = false
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
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
                if isRefreshing {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                            .font(.title3)
                            .foregroundColor(.blue)
                            .rotationEffect(.degrees(360))
                            .animation(.linear(duration: 1.0).repeatForever(autoreverses: false), value: isRefreshing)
                        
                        Text("Updating...")
                            .font(.caption2)
                            .foregroundColor(.blue)
                    }
                } else {
                    Button(action: onRefresh) {
                        Image(systemName: "arrow.clockwise")
                            .font(.title3)
                            .foregroundColor(.blue)
                    }
                }
            }
            
            // Progress Bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 16)
                    
                    RoundedRectangle(cornerRadius: 8)
                        .fill(didComplete ? Color.green : Color("appPrimary"))
                        .frame(width: animateProgress ? progress * geometry.size.width : 0, height: 16)
                        .scaleEffect(y: animateBar ? 1.3 : 1.0)
                        .shadow(color: animateBar ? (didComplete ? .green : .blue) : .clear, radius: animateBar ? 8 : 0)
                        .animation(.easeInOut(duration: 1.2).delay(0.5), value: animateProgress)
                        .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: animateBar)
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .frame(height: 16)
            
            // Distance Display
            HStack {
                Text(String(format: "%.2f", currentDistance))
                    .font(.title2)
                    .fontWeight(.bold)
                    .scaleEffect(animateNumbers ? 1.1 : 1.0)
                    .animation(.easeInOut(duration: 0.6).delay(0.8), value: animateNumbers)
                
                Text("of")
                    .font(.subheadline)
                    .opacity(animateNumbers ? 1.0 : 0.0)
                    .animation(.easeInOut(duration: 0.4).delay(1.0), value: animateNumbers)
                
                Text(String(format: "%.1f mi", goalDistance))
                    .font(.title2)
                    .fontWeight(.bold)
                    .scaleEffect(animateNumbers ? 1.1 : 1.0)
                    .animation(.easeInOut(duration: 0.6).delay(1.2), value: animateNumbers)
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
            

        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color(.systemGray4), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
        )
        .scaleEffect(isPressed ? 0.98 : 1.0)
        .animation(.easeInOut(duration: 0.1), value: isPressed)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.5).delay(0.2)) {
                animateProgress = true
            }
            withAnimation(.easeInOut(duration: 0.5).delay(0.4)) {
                animateNumbers = true
            }
            
            // Start bar pulsing animation if goal is completed
            if didComplete {
                withAnimation(.easeInOut(duration: 0.5).delay(1.5)) {
                    animateBar = true
                }
            }
        }
        .onLongPressGesture(minimumDuration: 0.5, maximumDistance: 50) {
            generateShareImage(theme: colorScheme)
        } onPressingChanged: { pressing in
            withAnimation(.easeInOut(duration: 0.1)) {
                isPressed = pressing
            }
            
            if pressing {
                // Light haptic feedback when press starts
                let impact = UIImpactFeedbackGenerator(style: .light)
                impact.impactOccurred()
            } else {
                // Medium haptic feedback when released/completed
                let impact = UIImpactFeedbackGenerator(style: .medium)
                impact.impactOccurred()
            }
        }
        .sheet(isPresented: $showingShareSheet) {
            SharePreviewView(streakImage: streakImage, progressImage: progressImage, title: "Share", initialTab: 1, user: user, progress: progress, isGoalCompleted: didComplete)
        }
    }
    
    private func generateShareImage(theme: ColorScheme = .light) {
        // Generate progress image that matches dashboard exactly
        let progressRenderer = ImageRenderer(content: TodayProgressCardShareView(
            currentDistance: currentDistance,
            goalDistance: goalDistance,
            progress: progress,
            didComplete: didComplete,
            totalMiles: user.totalMiles
        ).environment(\.colorScheme, theme))
        progressRenderer.scale = 3.0 // High resolution for Instagram
        
        // Generate streak image that matches dashboard exactly
        let streakRenderer = ImageRenderer(content: StreakCardShareView(
            streak: user.streak,
            isActiveToday: user.isStreakActiveToday,
            isAtRisk: user.isStreakAtRisk,
            user: user,
            progress: progress,
            isGoalCompleted: didComplete
        ).environment(\.colorScheme, theme))
        streakRenderer.scale = 3.0 // High resolution for Instagram
        
        if let progressImg = progressRenderer.uiImage, let streakImg = streakRenderer.uiImage {
            progressImage = progressImg
            streakImage = streakImg
            showingShareSheet = true
        }
    }
}

// MARK: - Supporting Components

// Stats Grid Component
struct StatsGridView: View {
    let user: User
    let healthManager: HealthKitManager
    @State private var showFastestPaceDetail = false
    @State private var showMostMilesDetail = false
    @State private var isRefreshingFastestPace = false
    
    var formattedFastestPace: String {
        if isRefreshingFastestPace {
            return "Loading..."
        }
        
        if healthManager.fastestMilePace > 0 {
            let totalMinutes = healthManager.fastestMilePace
            let minutes = Int(totalMinutes)
            let seconds = Int((totalMinutes - Double(minutes)) * 60)
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
                .onLongPressGesture {
                    // Manual refresh of fastest mile data
                    isRefreshingFastestPace = true
                    healthManager.fetchFastestMilePace()
                    
                    // Set a timeout to stop refreshing indicator
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        isRefreshingFastestPace = false
                    }
                }
                
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
            FastestPaceDetailView(pace: healthManager.fastestMilePace)
        }
        .sheet(isPresented: $showMostMilesDetail) {
            MostMilesDetailView(miles: user.mostMilesInOneDay, healthManager: healthManager)
        }
        .onAppear {
            // Ensure fastest mile data is loaded when stats grid appears
            if healthManager.fastestMilePace <= 0 {
                isRefreshingFastestPace = true
                healthManager.fetchFastestMilePace()
                
                // Set a timeout to stop refreshing indicator
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    isRefreshingFastestPace = false
                }
            }
        }
        .onChange(of: healthManager.fastestMilePace) { oldValue, newValue in
            if newValue > 0 {
                isRefreshingFastestPace = false
            }
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
    
    var backgroundColor: Color {
        if isGoalCompleted {
            return .green.opacity(0.1)
        } else if isAtRisk {
            return .red.opacity(0.1)
        } else {
            return .orange.opacity(0.1)
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
        VStack(spacing: 12) {
            // Title
            Text("Current Streak")
                .font(.headline)
                .fontWeight(.semibold)
            
            // Streak circle with fire icon (matching widget design)
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
                    .frame(width: 120, height: 120)
                
                // Progress ring - now changes color with streak status
                Circle()
                    .stroke(Color.gray.opacity(0.2), lineWidth: 5)
                    .frame(width: 130, height: 130)
                
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(streakColor, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .frame(width: 130, height: 130)
                    .rotationEffect(.degrees(-90))
                
                // Center content
                VStack(spacing: 4) {
                    Text("\(streak)")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundColor(streakColor)
                    
                    Text(streak == 1 ? "day" : "days")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(streakColor.opacity(0.8))
                }
            }
            
            // Status message with time until streak reset
            VStack(spacing: 4) {
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
                    
                    // Show time until streak ends - use same color as streak
                    Text(user.formattedTimeUntilReset)
                        .font(.caption2)
                        .foregroundColor(streakColor.opacity(0.8))
                        .fontWeight(.medium)
                } else {
                    Text("Keep it going!")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    // Show time until streak is at risk if not completed - use same color as streak
                    if !isActiveToday, user.timeUntilStreakReset != nil {
                        Text(user.formattedTimeUntilReset)
                            .font(.caption2)
                            .foregroundColor(streakColor.opacity(0.8))
                    }
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color(.systemGray4), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
        )
        .frame(width: 300, height: 400) // Fixed size for consistent sharing
    }
}

struct TodayProgressCardShareView: View {
    let currentDistance: Double
    let goalDistance: Double
    let progress: Double
    let didComplete: Bool
    let totalMiles: Double
    
    var body: some View {
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
                        .frame(height: 16)
                    
                    RoundedRectangle(cornerRadius: 8)
                        .fill(didComplete ? Color.green : Color("appPrimary"))
                        .frame(width: progress * geometry.size.width, height: 16)
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .frame(height: 16)
            
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
            .padding(.top, 4)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color(.systemGray4), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
        )
        .frame(width: 300, height: 320) // Fixed size for consistent sharing
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
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
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