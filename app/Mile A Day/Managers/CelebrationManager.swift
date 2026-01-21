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
    let todaysPace: TimeInterval? // Average pace in minutes per mile
    let personalBestPace: TimeInterval?
    
    var percentOver: Double {
        guard goalDistance > 0 else { return 0 }
        return ((todaysDistance - goalDistance) / goalDistance) * 100
    }
    
    var isNewPersonalBest: Bool {
        todaysDistance > bestDayMiles && bestDayMiles > 0
    }
    
    var isPacePB: Bool {
        guard let todaysPace = todaysPace, let bestPace = personalBestPace, bestPace > 0 else { return false }
        return todaysPace < bestPace
    }
    
    var streakMilestone: StreakMilestone? {
        StreakMilestone.allCases.first { $0.days == currentStreak }
    }
    
    static var placeholder: GoalCompletionStats {
        GoalCompletionStats(
            todaysDistance: 1.5,
            goalDistance: 1.0,
            currentStreak: 7,
            totalLifetimeMiles: 150,
            bestDayMiles: 5.0,
            todaysPace: 8.5,
            personalBestPace: 7.5
        )
    }
}

/// Streak milestones for celebration highlights
enum StreakMilestone: CaseIterable {
    case week, twoWeeks, threeWeeks, month, fiftyDays, hundredDays, year
    
    var days: Int {
        switch self {
        case .week: return 7
        case .twoWeeks: return 14
        case .threeWeeks: return 21
        case .month: return 30
        case .fiftyDays: return 50
        case .hundredDays: return 100
        case .year: return 365
        }
    }
    
    var title: String {
        switch self {
        case .week: return "1 Week Streak!"
        case .twoWeeks: return "2 Week Streak!"
        case .threeWeeks: return "3 Week Streak!"
        case .month: return "1 Month Streak!"
        case .fiftyDays: return "50 Day Streak!"
        case .hundredDays: return "100 Day Streak!"
        case .year: return "1 Year Streak!"
        }
    }
    
    var emoji: String {
        switch self {
        case .week: return "🔥"
        case .twoWeeks: return "💪"
        case .threeWeeks: return "⚡️"
        case .month: return "🏆"
        case .fiftyDays: return "👑"
        case .hundredDays: return "💎"
        case .year: return "🌟"
        }
    }
}

// MARK: - Celebration Types

/// Types of celebrations that can be shown
enum CelebrationType: Identifiable, Equatable {
    case goalCompleted(stats: GoalCompletionStats)
    case badgeUnlocked(badge: Badge)
    case milestone(title: String, description: String, icon: String)

    var id: String {
        switch self {
        case .goalCompleted:
            return "goal-completed-\(Date().timeIntervalSince1970)"
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
        return formatter.string(from: date)
    }

    /// Add a celebration to the queue
    func addCelebration(_ celebration: CelebrationType) {
        // Special handling for goal completion - only allow once per day
        if case .goalCompleted = celebration {
            guard !hasShownGoalCelebrationToday else {
                print("[CelebrationManager] Goal celebration already shown today, skipping")
                return
            }
            markGoalCelebrationShown()
        }
        
        // Avoid duplicates in queue
        guard !celebrationQueue.contains(where: { $0 == celebration }) else { return }
        guard currentCelebration != celebration else { return }

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
