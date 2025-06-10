import Foundation
import SwiftUI

struct User: Identifiable, Codable {
    var id = UUID()
    var name: String
    var streak: Int = 0
    var totalMiles: Double = 0.0
    var fastestMilePace: TimeInterval = 0.0  // Minutes per mile (fastest pace)
    var mostMilesInOneDay: Double = 0.0      // Most miles run in a single day
    var lastCompletionDate: Date?
    var goalMiles: Double = 1.0
    var badges: [Badge] = []
    
    // Check if the streak is active today
    var isStreakActiveToday: Bool {
        guard let lastCompletion = lastCompletionDate else { return false }
        return Calendar.current.isDateInToday(lastCompletion)
    }
    
    // Check if the streak is at risk (not completed today and it's past a certain time)
    var isStreakAtRisk: Bool {
        // If already completed today, streak is not at risk
        if isStreakActiveToday { return false }
        
        // Get current time
        let now = Date()
        let hour = Calendar.current.component(.hour, from: now)
        
        // Streak is at risk if it's past 6pm
        return hour >= 18
    }
    
    // Get time remaining until streak reset (returns nil if streak is already completed today)
    var timeUntilStreakReset: TimeInterval? {
        // If already completed today, return nil
        if isStreakActiveToday { return nil }
        
        let calendar = Calendar.current
        let now = Date()
        
        // Get end of today
        guard let endOfDay = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: now) else {
            return nil
        }
        
        return endOfDay.timeIntervalSince(now)
    }
    
    // Format time remaining until streak reset
    var formattedTimeUntilReset: String {
        guard let timeRemaining = timeUntilStreakReset else {
            return "Completed for today!"
        }
        
        let hours = Int(timeRemaining) / 3600
        let minutes = Int(timeRemaining) % 3600 / 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)m remaining"
        } else {
            return "\(minutes)m remaining"
        }
    }
    
    // Update user data from HealthKit
    mutating func updateFromHealthKit(
        streak: Int,
        miles: Double,
        totalMiles: Double,
        fastestPace: TimeInterval,
        mostMilesInDay: Double,
        date: Date = Date()
    ) {
        // Update streak (use retroactive streak from HealthKit)
        self.streak = streak
        
        // Update total miles from HealthKit
        self.totalMiles = totalMiles
        
        // Update fastest mile pace
        if fastestPace > 0 && (self.fastestMilePace == 0 || fastestPace < self.fastestMilePace) {
            self.fastestMilePace = fastestPace
        }
        
        // Update most miles in one day
        if mostMilesInDay > self.mostMilesInOneDay {
            self.mostMilesInOneDay = mostMilesInDay
        }
        
        // Only update completion date if we've completed a mile today
        if miles >= 0.95 && Calendar.current.isDateInToday(date) {
            lastCompletionDate = date
        } else if Calendar.current.isDateInToday(date) {
            // If it's today but we haven't completed a mile, clear the completion date
            // This ensures isStreakActiveToday returns false
            lastCompletionDate = nil
        }
        
        // Check for milestone badges
        checkForMilestoneBadges()
    }
    
    // Legacy method for backward compatibility - now just updates daily stats
    mutating func updateStreak(miles: Double, date: Date = Date()) {
        // Add to total miles
        totalMiles += miles
        
        // If already completed today, just update stats
        if Calendar.current.isDateInToday(lastCompletionDate ?? Date.distantPast) {
            lastCompletionDate = date
            return
        }
        
        // Check if the distance is enough to maintain streak (with 0.05 mile offset)
        if miles >= 0.95 {
            // Update completion date
            lastCompletionDate = date
        }
    }
    
    // Award badges based on milestones
    private mutating func checkForMilestoneBadges() {
        // Streak milestones
        if streak == 7 && !hasBadge(id: "streak_7") {
            badges.append(Badge(id: "streak_7", name: "Week Warrior", description: "7 day streak!"))
        }
        if streak == 30 && !hasBadge(id: "streak_30") {
            badges.append(Badge(id: "streak_30", name: "Monthly Master", description: "30 day streak!"))
        }
        if streak == 100 && !hasBadge(id: "streak_100") {
            badges.append(Badge(id: "streak_100", name: "Century Club", description: "100 day streak!"))
        }
        
        // Total miles milestones
        if totalMiles >= 100 && !hasBadge(id: "miles_100") {
            badges.append(Badge(id: "miles_100", name: "100 Mile Club", description: "Ran 100 total miles!"))
        }
    }
    
    // Helper to check if user already has a badge
    private func hasBadge(id: String) -> Bool {
        return badges.contains { $0.id == id }
    }
}

// Badge for achievements
struct Badge: Identifiable, Codable {
    var id: String
    var name: String
    var description: String
    var dateAwarded: Date = Date()
    var isNew: Bool = true
    
    // Badge rarity (can be used for visual styling)
    var rarity: BadgeRarity {
        if id.starts(with: "streak_100") || id.starts(with: "miles_1000") {
            return .legendary
        } else if id.starts(with: "streak_30") || id.starts(with: "miles_100") {
            return .rare
        } else {
            return .common
        }
    }
}

enum BadgeRarity: String, Codable {
    case common
    case rare
    case legendary
    
    var color: Color {
        switch self {
        case .common:
            return .blue
        case .rare:
            return .purple
        case .legendary:
            return .orange
        }
    }
} 