import Foundation
import SwiftUI

struct User: Identifiable, Codable {
    var id = UUID()
    var name: String
    var streak: Int = 0
    var totalMiles: Double = 0.0
    var personalRecord: Double = 0.0
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
        guard let lastCompletion = lastCompletionDate,
              !Calendar.current.isDateInToday(lastCompletion) else { return false }
        
        // If it's past 6pm and you haven't completed your run yet, streak is at risk
        let now = Date()
        let hour = Calendar.current.component(.hour, from: now)
        return hour >= 18
    }
    
    // Update streak when a new run is completed
    mutating func updateStreak(miles: Double, date: Date = Date()) {
        // Check if this is a personal record
        if miles > personalRecord {
            personalRecord = miles
        }
        
        // Add to total miles
        totalMiles += miles
        
        // If already completed today, just update stats
        if Calendar.current.isDateInToday(lastCompletionDate ?? Date.distantPast) {
            lastCompletionDate = date
            return
        }
        
        // Check if this is the next day from the last completion
        if let lastDate = lastCompletionDate {
            let isYesterday = Calendar.current.isDate(lastDate, inSameDayAs: 
                                                     Calendar.current.date(byAdding: .day, value: -1, to: date) ?? date)
            if isYesterday {
                // Continue the streak
                streak += 1
            } else {
                // Streak broken, reset to 1
                streak = 1
            }
        } else {
            // First completion
            streak = 1
        }
        
        lastCompletionDate = date
        
        // Check for milestone badges
        checkForMilestoneBadges()
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