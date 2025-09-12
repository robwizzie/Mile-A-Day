import Foundation
import SwiftUI

struct User: Identifiable, Codable {
    var id = UUID()
    var name: String
    var username: String?
    var bio: String?
    var streak: Int = 0
    var totalMiles: Double = 0.0
    var fastestMilePace: TimeInterval = 0.0  // Minutes per mile (fastest pace)
    var mostMilesInOneDay: Double = 0.0      // Most miles run in a single day
    var lastCompletionDate: Date?
    var goalMiles: Double = 1.0
    var badges: [Badge] = []
    
    // Apple Sign In fields
    var appleId: String?
    var email: String?
    var authProvider: AuthProvider = .guest
    var backendUserId: String?
    var authToken: String?
    
    // Privacy settings
    var privacySettings: PrivacySettings = .default
    
    enum AuthProvider: String, Codable {
        case apple
        case google
        case guest
    }
    
    // Check if user has a username set
    var hasUsername: Bool {
        return username != nil && !username!.isEmpty
    }
    
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
    mutating func checkForMilestoneBadges() {
        // Streak milestones
        if streak >= 7 && !hasBadge(id: "streak_7") {
            let earnedDate = calculateRetroactiveDate(for: 7, type: .streak)
            badges.append(Badge(id: "streak_7", name: "Week Warrior", description: "7 day streak!", dateAwarded: earnedDate))
        }
        if streak >= 14 && !hasBadge(id: "streak_14") {
            let earnedDate = calculateRetroactiveDate(for: 14, type: .streak)
            badges.append(Badge(id: "streak_14", name: "Fortnight Fighter", description: "14 day streak!", dateAwarded: earnedDate))
        }
        if streak >= 30 && !hasBadge(id: "streak_30") {
            let earnedDate = calculateRetroactiveDate(for: 30, type: .streak)
            badges.append(Badge(id: "streak_30", name: "Monthly Master", description: "30 day streak!", dateAwarded: earnedDate))
        }
        if streak >= 50 && !hasBadge(id: "streak_50") {
            let earnedDate = calculateRetroactiveDate(for: 50, type: .streak)
            badges.append(Badge(id: "streak_50", name: "Half Century", description: "50 day streak!", dateAwarded: earnedDate))
        }
        if streak >= 100 && !hasBadge(id: "streak_100") {
            let earnedDate = calculateRetroactiveDate(for: 100, type: .streak)
            badges.append(Badge(id: "streak_100", name: "Century Club", description: "100 day streak!", dateAwarded: earnedDate))
        }
        if streak >= 365 && !hasBadge(id: "streak_365") {
            let earnedDate = calculateRetroactiveDate(for: 365, type: .streak)
            badges.append(Badge(id: "streak_365", name: "Year Warrior", description: "365 day streak!", dateAwarded: earnedDate))
        }
        
        // Total miles milestones
        if totalMiles >= 50 && !hasBadge(id: "miles_50") {
            badges.append(Badge(id: "miles_50", name: "50 Mile Club", description: "Ran 50 total miles!", dateAwarded: lastCompletionDate ?? Date()))
        }
        if totalMiles >= 100 && !hasBadge(id: "miles_100") {
            badges.append(Badge(id: "miles_100", name: "100 Mile Club", description: "Ran 100 total miles!", dateAwarded: lastCompletionDate ?? Date()))
        }
        if totalMiles >= 250 && !hasBadge(id: "miles_250") {
            badges.append(Badge(id: "miles_250", name: "250 Mile Club", description: "Ran 250 total miles!", dateAwarded: lastCompletionDate ?? Date()))
        }
        if totalMiles >= 500 && !hasBadge(id: "miles_500") {
            badges.append(Badge(id: "miles_500", name: "500 Mile Club", description: "Ran 500 total miles!", dateAwarded: lastCompletionDate ?? Date()))
        }
        if totalMiles >= 1000 && !hasBadge(id: "miles_1000") {
            badges.append(Badge(id: "miles_1000", name: "1000 Mile Club", description: "Ran 1000 total miles!", dateAwarded: lastCompletionDate ?? Date()))
        }
        
        // Speed milestones (fastest mile pace)
        if fastestMilePace > 0 && fastestMilePace <= 6.0 && !hasBadge(id: "pace_6min") {
            badges.append(Badge(id: "pace_6min", name: "Speed Demon", description: "Sub-6 minute mile!", dateAwarded: lastCompletionDate ?? Date()))
        }
        if fastestMilePace > 0 && fastestMilePace <= 7.0 && !hasBadge(id: "pace_7min") {
            badges.append(Badge(id: "pace_7min", name: "Quick Runner", description: "Sub-7 minute mile!", dateAwarded: lastCompletionDate ?? Date()))
        }
        if fastestMilePace > 0 && fastestMilePace <= 8.0 && !hasBadge(id: "pace_8min") {
            badges.append(Badge(id: "pace_8min", name: "Fast Runner", description: "Sub-8 minute mile!", dateAwarded: lastCompletionDate ?? Date()))
        }
        
        // Distance milestones (most miles in one day)
        if mostMilesInOneDay >= 5.0 && !hasBadge(id: "daily_5") {
            badges.append(Badge(id: "daily_5", name: "5 Mile Day", description: "Ran 5+ miles in one day!", dateAwarded: lastCompletionDate ?? Date()))
        }
        if mostMilesInOneDay >= 10.0 && !hasBadge(id: "daily_10") {
            badges.append(Badge(id: "daily_10", name: "10 Mile Day", description: "Ran 10+ miles in one day!", dateAwarded: lastCompletionDate ?? Date()))
        }
        if mostMilesInOneDay >= 13.1 && !hasBadge(id: "daily_half") {
            badges.append(Badge(id: "daily_half", name: "Half Marathon", description: "Ran 13.1+ miles in one day!", dateAwarded: lastCompletionDate ?? Date()))
        }
        if mostMilesInOneDay >= 26.2 && !hasBadge(id: "daily_marathon") {
            badges.append(Badge(id: "daily_marathon", name: "Marathon Runner", description: "Ran 26.2+ miles in one day!", dateAwarded: lastCompletionDate ?? Date()))
        }
        
        // Consistency milestones (consecutive days)
        if streak >= 3 && !hasBadge(id: "consistency_3") {
            let earnedDate = calculateRetroactiveDate(for: 3, type: .streak)
            badges.append(Badge(id: "consistency_3", name: "Getting Started", description: "3 day streak!", dateAwarded: earnedDate))
        }
        if streak >= 5 && !hasBadge(id: "consistency_5") {
            let earnedDate = calculateRetroactiveDate(for: 5, type: .streak)
            badges.append(Badge(id: "consistency_5", name: "Building Habits", description: "5 day streak!", dateAwarded: earnedDate))
        }
    }
    
    // Calculate retroactive date when badge should have been earned
    private func calculateRetroactiveDate(for milestone: Int, type: BadgeType) -> Date {
        let calendar = Calendar.current
        let today = Date()
        
        switch type {
        case .streak:
            // For streak badges, calculate when the streak reached the milestone
            if let lastCompletion = lastCompletionDate {
                // Calculate how many days ago the streak reached this milestone
                let daysSinceMilestone = streak - milestone
                if daysSinceMilestone >= 0 {
                    return calendar.date(byAdding: .day, value: -daysSinceMilestone, to: lastCompletion) ?? lastCompletion
                }
            }
            return lastCompletionDate ?? today
            
        case .miles, .pace, .distance:
            // For other badges, use the last completion date or today
            return lastCompletionDate ?? today
        }
    }
    
    // Badge type for retroactive date calculation
    private enum BadgeType {
        case streak, miles, pace, distance
    }
    
    // Helper to check if user already has a badge
    private func hasBadge(id: String) -> Bool {
        return badges.contains { $0.id == id }
    }
    
    // Get all possible badges (both earned and locked)
    func getAllBadges() -> [Badge] {
        var allBadges: [Badge] = []
        
        // Add earned badges
        allBadges.append(contentsOf: badges)
        
        // Add locked badges
        let lockedBadges = getLockedBadges()
        allBadges.append(contentsOf: lockedBadges)
        
        // Sort by category and then by requirement
        return allBadges.sorted { badge1, badge2 in
            let category1 = getBadgeCategory(badge1.id)
            let category2 = getBadgeCategory(badge2.id)
            
            if category1 == category2 {
                return getBadgeRequirement(badge1.id) < getBadgeRequirement(badge2.id)
            }
            return category1.rawValue < category2.rawValue
        }
    }
    
    // Get locked badges that user hasn't earned yet
    private func getLockedBadges() -> [Badge] {
        var lockedBadges: [Badge] = []
        
        // Streak badges
        let streakMilestones = [3, 5, 7, 14, 30, 50, 100, 365]
        for milestone in streakMilestones {
            let badgeId = milestone <= 5 ? "consistency_\(milestone)" : "streak_\(milestone)"
            if !hasBadge(id: badgeId) {
                lockedBadges.append(Badge(
                    id: badgeId,
                    name: getBadgeName(for: badgeId),
                    description: getBadgeDescription(for: badgeId),
                    dateAwarded: Date.distantFuture,
                    isNew: false,
                    isLocked: true
                ))
            }
        }
        
        // Miles badges
        let milesMilestones = [50, 100, 250, 500, 1000]
        for milestone in milesMilestones {
            let badgeId = "miles_\(milestone)"
            if !hasBadge(id: badgeId) {
                lockedBadges.append(Badge(
                    id: badgeId,
                    name: getBadgeName(for: badgeId),
                    description: getBadgeDescription(for: badgeId),
                    dateAwarded: Date.distantFuture,
                    isNew: false,
                    isLocked: true
                ))
            }
        }
        
        // Speed badges
        let paceMilestones = [8.0, 7.0, 6.0]
        for milestone in paceMilestones {
            let badgeId = "pace_\(Int(milestone))min"
            if !hasBadge(id: badgeId) {
                lockedBadges.append(Badge(
                    id: badgeId,
                    name: getBadgeName(for: badgeId),
                    description: getBadgeDescription(for: badgeId),
                    dateAwarded: Date.distantFuture,
                    isNew: false,
                    isLocked: true
                ))
            }
        }
        
        // Distance badges
        let distanceMilestones = [5.0, 10.0, 13.1, 26.2]
        for milestone in distanceMilestones {
            let badgeId = milestone == 13.1 ? "daily_half" : 
                         milestone == 26.2 ? "daily_marathon" : "daily_\(Int(milestone))"
            if !hasBadge(id: badgeId) {
                lockedBadges.append(Badge(
                    id: badgeId,
                    name: getBadgeName(for: badgeId),
                    description: getBadgeDescription(for: badgeId),
                    dateAwarded: Date.distantFuture,
                    isNew: false,
                    isLocked: true
                ))
            }
        }
        
        return lockedBadges
    }
    
    // Helper functions for badge information
    private func getBadgeName(for id: String) -> String {
        switch id {
        case "consistency_3": return "Getting Started"
        case "consistency_5": return "Building Habits"
        case "streak_7": return "Week Warrior"
        case "streak_14": return "Fortnight Fighter"
        case "streak_30": return "Monthly Master"
        case "streak_50": return "Half Century"
        case "streak_100": return "Century Club"
        case "streak_365": return "Year Warrior"
        case "miles_50": return "50 Mile Club"
        case "miles_100": return "100 Mile Club"
        case "miles_250": return "250 Mile Club"
        case "miles_500": return "500 Mile Club"
        case "miles_1000": return "1000 Mile Club"
        case "pace_8min": return "Fast Runner"
        case "pace_7min": return "Quick Runner"
        case "pace_6min": return "Speed Demon"
        case "daily_5": return "5 Mile Day"
        case "daily_10": return "10 Mile Day"
        case "daily_half": return "Half Marathon"
        case "daily_marathon": return "Marathon Runner"
        default: return "Unknown Badge"
        }
    }
    
    private func getBadgeDescription(for id: String) -> String {
        switch id {
        case "consistency_3": return "3 day streak!"
        case "consistency_5": return "5 day streak!"
        case "streak_7": return "7 day streak!"
        case "streak_14": return "14 day streak!"
        case "streak_30": return "30 day streak!"
        case "streak_50": return "50 day streak!"
        case "streak_100": return "100 day streak!"
        case "streak_365": return "365 day streak!"
        case "miles_50": return "Ran 50 total miles!"
        case "miles_100": return "Ran 100 total miles!"
        case "miles_250": return "Ran 250 total miles!"
        case "miles_500": return "Ran 500 total miles!"
        case "miles_1000": return "Ran 1000 total miles!"
        case "pace_8min": return "Sub-8 minute mile!"
        case "pace_7min": return "Sub-7 minute mile!"
        case "pace_6min": return "Sub-6 minute mile!"
        case "daily_5": return "Ran 5+ miles in one day!"
        case "daily_10": return "Ran 10+ miles in one day!"
        case "daily_half": return "Ran 13.1+ miles in one day!"
        case "daily_marathon": return "Ran 26.2+ miles in one day!"
        default: return "Unknown achievement!"
        }
    }
    
    private func getBadgeCategory(_ id: String) -> BadgeCategory {
        if id.starts(with: "streak_") || id.starts(with: "consistency_") {
            return .streak
        } else if id.starts(with: "miles_") {
            return .miles
        } else if id.starts(with: "pace_") {
            return .speed
        } else if id.starts(with: "daily_") {
            return .distance
        }
        return .other
    }
    
    private func getBadgeRequirement(_ id: String) -> Int {
        // Extract number from badge ID for sorting
        let components = id.components(separatedBy: CharacterSet.decimalDigits.inverted)
        return components.compactMap { Int($0) }.first ?? 0
    }
    
    private enum BadgeCategory: Int {
        case streak = 0, miles = 1, speed = 2, distance = 3, other = 4
    }
}

// Badge for achievements
struct Badge: Identifiable, Codable {
    var id: String
    var name: String
    var description: String
    var dateAwarded: Date = Date()
    var isNew: Bool = true
    var isLocked: Bool = false
    
    // Badge rarity (can be used for visual styling)
    var rarity: BadgeRarity {
        // Legendary badges
        if id.starts(with: "streak_365") || id.starts(with: "miles_1000") || 
           id.starts(with: "daily_marathon") || id.starts(with: "pace_6min") {
            return .legendary
        }
        // Rare badges
        else if id.starts(with: "streak_100") || id.starts(with: "streak_50") || 
                id.starts(with: "miles_500") || id.starts(with: "daily_half") ||
                id.starts(with: "pace_7min") {
            return .rare
        }
        // Common badges
        else {
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