//
//  CelebrationManager.swift
//  Mile A Day
//

import Foundation
import SwiftUI

// MARK: - Goal Completion Stats

/// Stats displayed in the goal completion celebration
struct GoalCompletionStats: Equatable {
    let todaysDistance: Double
    let goalDistance: Double
    let currentStreak: Int
    let totalLifetimeMiles: Double
    let bestDayMiles: Double
    let todaysAveragePace: TimeInterval? // Average pace in minutes per mile from today's workouts
    let todaysFastestPace: TimeInterval? // Fastest pace from today's workouts
    let personalBestPace: TimeInterval? // All-time fastest pace
    let todaysTotalDuration: TimeInterval // Total workout duration in seconds
    let todaysCalories: Double // Total calories burned today
    let todaysWorkoutCount: Int // Number of workouts completed today
    
    var percentOver: Double {
        guard goalDistance > 0 else { return 0 }
        return ((todaysDistance - goalDistance) / goalDistance) * 100
    }
    
    var isNewPersonalBest: Bool {
        todaysDistance > bestDayMiles && bestDayMiles > 0
    }
    
    /// Check if today's fastest pace is a new personal best
    var isPacePB: Bool {
        guard let todaysFastest = todaysFastestPace, let bestPace = personalBestPace, bestPace > 0 else { return false }
        return todaysFastest < bestPace
    }
    
    var streakMilestone: StreakMilestone? {
        StreakMilestone.allCases.first { $0.days == currentStreak }
    }
    
    /// Formatted total duration string (e.g., "32:15")
    var formattedDuration: String {
        let minutes = Int(todaysTotalDuration) / 60
        let seconds = Int(todaysTotalDuration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    /// Formatted calories string
    var formattedCalories: String {
        if todaysCalories >= 1000 {
            return String(format: "%.1fk", todaysCalories / 1000)
        }
        return String(format: "%.0f", todaysCalories)
    }
    
    static var placeholder: GoalCompletionStats {
        GoalCompletionStats(
            todaysDistance: 1.5,
            goalDistance: 1.0,
            currentStreak: 7,
            totalLifetimeMiles: 150,
            bestDayMiles: 5.0,
            todaysAveragePace: 8.5,
            todaysFastestPace: 7.8,
            personalBestPace: 7.5,
            todaysTotalDuration: 765, // 12:45
            todaysCalories: 185,
            todaysWorkoutCount: 1
        )
    }
}

/// Milestone tier: mini milestones are frequent encouragement, major milestones get extra celebration
enum MilestoneTier {
    case mini
    case major
}

/// Streak milestones for celebration highlights
/// Mini milestones every ~50 days keep users motivated; major milestones get special treatment
enum StreakMilestone: CaseIterable {
    // Mini milestones (frequent encouragement)
    case week           // 7
    case twoWeeks       // 14
    case threeWeeks     // 21
    case month          // 30
    case fiftyDays      // 50
    case seventyFive    // 75
    // Major milestones (extra special)
    case hundredDays    // 100
    // Mini
    case oneFifty       // 150
    case twoHundred     // 200
    // Major
    case twoFifty       // 250
    case threeHundred   // 300
    // Major
    case year           // 365
    // Mini
    case fourHundred    // 400
    case fourFifty      // 450
    // Major
    case fiveHundred    // 500
    // Mini
    case sixHundred     // 600
    // Major
    case twoYears       // 730
    // Major
    case thousandDays   // 1000

    var days: Int {
        switch self {
        case .week: return 7
        case .twoWeeks: return 14
        case .threeWeeks: return 21
        case .month: return 30
        case .fiftyDays: return 50
        case .seventyFive: return 75
        case .hundredDays: return 100
        case .oneFifty: return 150
        case .twoHundred: return 200
        case .twoFifty: return 250
        case .threeHundred: return 300
        case .year: return 365
        case .fourHundred: return 400
        case .fourFifty: return 450
        case .fiveHundred: return 500
        case .sixHundred: return 600
        case .twoYears: return 730
        case .thousandDays: return 1000
        }
    }

    var tier: MilestoneTier {
        switch self {
        case .hundredDays, .twoFifty, .threeHundred, .year, .fiveHundred, .twoYears, .thousandDays:
            return .major
        default:
            return .mini
        }
    }

    var isMajor: Bool { tier == .major }

    var title: String {
        switch self {
        case .week: return "1 Week Streak!"
        case .twoWeeks: return "2 Week Streak!"
        case .threeWeeks: return "3 Week Streak!"
        case .month: return "1 Month Streak!"
        case .fiftyDays: return "50 Day Streak!"
        case .seventyFive: return "75 Day Streak!"
        case .hundredDays: return "100 Day Streak!"
        case .oneFifty: return "150 Day Streak!"
        case .twoHundred: return "200 Day Streak!"
        case .twoFifty: return "250 Day Streak!"
        case .threeHundred: return "300 Day Streak!"
        case .year: return "1 Year Streak!"
        case .fourHundred: return "400 Day Streak!"
        case .fourFifty: return "450 Day Streak!"
        case .fiveHundred: return "500 Day Streak!"
        case .sixHundred: return "600 Day Streak!"
        case .twoYears: return "2 Year Streak!"
        case .thousandDays: return "1,000 Day Streak!"
        }
    }

    var emoji: String {
        switch self {
        case .week: return "🔥"
        case .twoWeeks: return "💪"
        case .threeWeeks: return "⚡️"
        case .month: return "🏆"
        case .fiftyDays: return "🎯"
        case .seventyFive: return "✨"
        case .hundredDays: return "💎"
        case .oneFifty: return "🚀"
        case .twoHundred: return "⭐️"
        case .twoFifty: return "👑"
        case .threeHundred: return "🏅"
        case .year: return "🌟"
        case .fourHundred: return "🔥"
        case .fourFifty: return "💪"
        case .fiveHundred: return "🏆"
        case .sixHundred: return "⚡️"
        case .twoYears: return "💎"
        case .thousandDays: return "👑"
        }
    }

    /// Subtitle shown on major milestones
    var majorSubtitle: String {
        switch self {
        case .hundredDays: return "Triple digits! You're in the elite!"
        case .twoFifty: return "A quarter thousand days of dedication!"
        case .threeHundred: return "300 days of pure commitment!"
        case .year: return "365 days. One full year. Legendary!"
        case .fiveHundred: return "Half a thousand! Absolutely incredible!"
        case .twoYears: return "Two full years! You're unstoppable!"
        case .thousandDays: return "ONE THOUSAND DAYS. You are a legend!"
        default: return "Incredible dedication!"
        }
    }
}

// MARK: - Celebration Types

/// Types of celebrations that can be shown
enum CelebrationType: Identifiable, Equatable {
    case goalCompleted(stats: GoalCompletionStats)
    case postGoalWorkout(stats: GoalCompletionStats)
    case badgeUnlocked(badge: Badge)
    case milestone(title: String, description: String, icon: String)

    var id: String {
        switch self {
        case .goalCompleted:
            return "goal-completed-\(Date().timeIntervalSince1970)"
        case .postGoalWorkout:
            return "post-goal-\(Date().timeIntervalSince1970)"
        case .badgeUnlocked(let badge):
            return "badge-\(badge.id)"
        case .milestone(let title, _, _):
            return "milestone-\(title)"
        }
    }

    static func == (lhs: CelebrationType, rhs: CelebrationType) -> Bool {
        switch (lhs, rhs) {
        case (.goalCompleted, .goalCompleted):
            return true // Only one goal completion per day
        case (.postGoalWorkout, .postGoalWorkout):
            return true
        case (.badgeUnlocked(let b1), .badgeUnlocked(let b2)):
            return b1.id == b2.id
        case (.milestone(let t1, _, _), .milestone(let t2, _, _)):
            return t1 == t2
        default:
            return false
        }
    }
}

/// Actions that can be triggered when dismissing a celebration
enum CelebrationDismissAction: Equatable {
    case none
    case viewBadges
}

/// Manages queuing and displaying celebration screens
class CelebrationManager: ObservableObject {
    static let shared = CelebrationManager()

    @Published private(set) var celebrationQueue: [CelebrationType] = []
    @Published var currentCelebration: CelebrationType?
    @Published var isShowingCelebration = false
    @Published var pendingAction: CelebrationDismissAction = .none
    
    /// Tracks whether goal completion has been shown today (to prevent duplicates)
    @AppStorage("lastGoalCelebrationDate") private var lastGoalCelebrationDateString: String = ""

    private init() {}
    
    /// Check if goal celebration has already been shown today
    var hasShownGoalCelebrationToday: Bool {
        let today = formatDate(Date())
        return lastGoalCelebrationDateString == today
    }
    
    /// Mark goal celebration as shown for today
    func markGoalCelebrationShown() {
        lastGoalCelebrationDateString = formatDate(Date())
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.calendar = Calendar.current
        formatter.timeZone = TimeZone.current
        return formatter.string(from: date)
    }

    /// Add a celebration to the queue
    func addCelebration(_ celebration: CelebrationType) {
        // Special handling for goal completion - only allow once per day
        if case .goalCompleted = celebration {
            guard !hasShownGoalCelebrationToday else {
                print("[CelebrationManager] ⏭️  Goal celebration already shown today (\(lastGoalCelebrationDateString)), skipping")
                return
            }
            print("[CelebrationManager] ✅ Goal celebration will be shown (last shown: \(lastGoalCelebrationDateString.isEmpty ? "never" : lastGoalCelebrationDateString), today: \(formatDate(Date())))")
            markGoalCelebrationShown()
        }

        // Avoid duplicates in queue
        guard !celebrationQueue.contains(where: { $0 == celebration }) else {
            print("[CelebrationManager] ⏭️  Celebration already in queue, skipping")
            return
        }
        guard currentCelebration != celebration else {
            print("[CelebrationManager] ⏭️  Celebration already showing, skipping")
            return
        }

        print("[CelebrationManager] 🎉 Adding celebration to queue: \(celebration.id)")
        celebrationQueue.append(celebration)

        // If nothing is currently showing, show the next one
        if !isShowingCelebration {
            showNextCelebration()
        }
    }

    /// Dismiss the current celebration and show the next one if available
    func dismissCurrentCelebration() {
        isShowingCelebration = false
        currentCelebration = nil

        // Small delay before showing next celebration for better UX
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.showNextCelebration()
        }
    }
    
    /// Dismiss the current celebration with a specific action
    func dismissWithAction(_ action: CelebrationDismissAction) {
        // Clear remaining queue when user wants to navigate away
        if action != .none {
            celebrationQueue.removeAll()
        }
        
        isShowingCelebration = false
        currentCelebration = nil
        
        // Set the pending action after a brief delay for animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.pendingAction = action
        }
    }
    
    /// Clear the pending action (should be called after handling it)
    func clearPendingAction() {
        pendingAction = .none
    }

    /// Show the next celebration in the queue
    private func showNextCelebration() {
        guard !celebrationQueue.isEmpty else { return }

        currentCelebration = celebrationQueue.removeFirst()
        isShowingCelebration = true
    }

    /// Clear all celebrations (useful for testing or reset)
    func clearAll() {
        celebrationQueue.removeAll()
        currentCelebration = nil
        isShowingCelebration = false
        pendingAction = .none
    }
    
    /// Reset daily tracking (for testing)
    func resetDailyTracking() {
        lastGoalCelebrationDateString = ""
    }
}
