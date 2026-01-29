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
    @discardableResult
    mutating func checkForMilestoneBadges() -> [Badge] {
        var newBadges: [Badge] = []

        // MARK: - Streak Milestones
        let streakMilestones: [(Int, String, String, String)] = [
            (7, "streak_7", "Week Warrior", "7 day streak! A full week of dedication!"),
            (10, "streak_10", "Ten Days Strong", "10 day streak! Double digits!"),
            (14, "streak_14", "Fortnight Fighter", "14 day streak! Two weeks strong!"),
            (21, "streak_21", "Three Week Champion", "21 day streak! Habits are forming!"),
            (30, "streak_30", "Monthly Master", "30 day streak! A full month!"),
            (45, "streak_45", "45 Day Legend", "45 day streak! Halfway to 90!"),
            (50, "streak_50", "Half Century", "50 day streak! Incredible consistency!"),
            (60, "streak_60", "Two Month Milestone", "60 day streak! Two months strong!"),
            (75, "streak_75", "Consistency King", "75 day streak! You're unstoppable!"),
            (90, "streak_90", "Quarter Year Hero", "90 day streak! A quarter year!"),
            (100, "streak_100", "Century Club", "100 day streak! Triple digits!"),
            (120, "streak_120", "Four Month Fury", "120 day streak! Four months!"),
            (150, "streak_150", "Unstoppable Force", "150 day streak! Nothing can stop you!"),
            (180, "streak_180", "Half Year Hero", "180 day streak! Six months of glory!"),
            (200, "streak_200", "Double Century", "200 day streak! Legendary status!"),
            (250, "streak_250", "Legendary Streak", "250 day streak! You're a legend!"),
            (300, "streak_300", "300 Club", "300 day streak! Almost a year!"),
            (365, "streak_365", "Year Warrior", "365 day streak! A FULL YEAR!"),
            (500, "streak_500", "Elite Runner", "500 day streak! Beyond legendary!"),
            (730, "streak_730", "Two Year Titan", "730 day streak! TWO YEARS!"),
            (1000, "streak_1000", "Immortal", "1000 day streak! You're immortal!")
        ]
        
        for (days, id, name, description) in streakMilestones {
            if streak >= days && !hasBadge(id: id) {
                let earnedDate = calculateRetroactiveDate(for: days, type: .streak)
                let badge = Badge(id: id, name: name, description: description, dateAwarded: earnedDate)
                badges.append(badge)
                newBadges.append(badge)
            }
        }
        
        // MARK: - Consistency (Early Streak) Milestones
        if streak >= 3 && !hasBadge(id: "consistency_3") {
            let earnedDate = calculateRetroactiveDate(for: 3, type: .streak)
            let badge = Badge(
                id: "consistency_3",
                name: "Getting Started",
                description: "3 day streak! You're on your way!",
                dateAwarded: earnedDate
            )
            badges.append(badge)
            newBadges.append(badge)
        }
        if streak >= 5 && !hasBadge(id: "consistency_5") {
            let earnedDate = calculateRetroactiveDate(for: 5, type: .streak)
            let badge = Badge(
                id: "consistency_5",
                name: "Building Habits",
                description: "5 day streak! Consistency is key!",
                dateAwarded: earnedDate
            )
            badges.append(badge)
            newBadges.append(badge)
        }
        
        // MARK: - Total Miles Milestones
        let milesMilestones: [(Double, String, String, String)] = [
            (25, "miles_25", "25 Mile Mark", "Ran 25 total miles!"),
            (50, "miles_50", "50 Mile Club", "Ran 50 total miles!"),
            (100, "miles_100", "Century Runner", "Ran 100 total miles!"),
            (150, "miles_150", "150 Mile Mark", "Ran 150 total miles!"),
            (200, "miles_200", "200 Mile Mark", "Ran 200 total miles!"),
            (250, "miles_250", "250 Mile Club", "Ran 250 total miles!"),
            (500, "miles_500", "500 Mile Club", "Ran 500 total miles!"),
            (750, "miles_750", "750 Mile Club", "Ran 750 total miles!"),
            (1000, "miles_1000", "1000 Mile Club", "Ran 1000 total miles!"),
            (1500, "miles_1500", "1500 Mile Legend", "Ran 1500 total miles!"),
            (2000, "miles_2000", "2000 Mile Legend", "Ran 2000 total miles!"),
            (2500, "miles_2500", "Ultra Runner", "Ran 2500 total miles!")
        ]
        
        for (miles, id, name, description) in milesMilestones {
            if totalMiles >= miles && !hasBadge(id: id) {
                let badge = Badge(id: id, name: name, description: description, dateAwarded: lastCompletionDate ?? Date())
                badges.append(badge)
                newBadges.append(badge)
            }
        }

        // MARK: - Speed Milestones (Fastest Mile Pace)
        let paceMilestones: [(Double, String, String, String)] = [
            (12.0, "pace_12min", "Getting Faster", "Sub-12 minute mile!"),
            (11.0, "pace_11min", "Picking Up Speed", "Sub-11 minute mile!"),
            (10.0, "pace_10min", "Double Digits", "Sub-10 minute mile!"),
            (9.0, "pace_9min", "Solid Pace", "Sub-9 minute mile!"),
            (8.0, "pace_8min", "Fast Runner", "Sub-8 minute mile!"),
            (7.0, "pace_7min", "Quick Runner", "Sub-7 minute mile!"),
            (6.0, "pace_6min", "Speed Demon", "Sub-6 minute mile!"),
            (5.0, "pace_5min", "Elite Speed", "Sub-5 minute mile! Incredible!")
        ]
        
        for (pace, id, name, description) in paceMilestones {
            if fastestMilePace > 0 && fastestMilePace <= pace && !hasBadge(id: id) {
                let badge = Badge(id: id, name: name, description: description, dateAwarded: lastCompletionDate ?? Date())
                badges.append(badge)
                newBadges.append(badge)
            }
        }

        // MARK: - Daily Distance Milestones
        let dailyMilestones: [(Double, String, String, String)] = [
            (2.0, "daily_2", "2 Mile Day", "Ran 2+ miles in one day!"),
            (3.0, "daily_3", "5K Runner", "Ran 3+ miles (5K) in one day!"),
            (5.0, "daily_5", "5 Mile Day", "Ran 5+ miles in one day!"),
            (6.2, "daily_10k", "10K Runner", "Ran 6.2+ miles (10K) in one day!"),
            (8.0, "daily_8", "8 Mile Day", "Ran 8+ miles in one day!"),
            (10.0, "daily_10", "10 Mile Day", "Ran 10+ miles in one day!"),
            (13.1, "daily_half", "Half Marathon", "Ran 13.1+ miles in one day!"),
            (15.0, "daily_15", "15 Mile Day", "Ran 15+ miles in one day!"),
            (20.0, "daily_20", "20 Mile Day", "Ran 20+ miles in one day!"),
            (26.2, "daily_marathon", "Marathon Runner", "Ran 26.2+ miles in one day!"),
            (31.0, "daily_50k", "50K Ultra", "Ran 31+ miles (50K) in one day!"),
            (50.0, "daily_ultra", "Ultra Legend", "Ran 50+ miles in one day!")
        ]
        
        for (miles, id, name, description) in dailyMilestones {
            if mostMilesInOneDay >= miles && !hasBadge(id: id) {
                let badge = Badge(id: id, name: name, description: description, dateAwarded: lastCompletionDate ?? Date())
                badges.append(badge)
                newBadges.append(badge)
            }
        }
        
        // MARK: - Special Achievement Badges
        // These are for specific combinations or milestones
        
        // First Mile - awarded on first completion
        if totalMiles >= 1.0 && !hasBadge(id: "special_first_mile") {
            let badge = Badge(id: "special_first_mile", name: "First Mile", description: "Completed your first mile! The journey begins!")
            badges.append(badge)
            newBadges.append(badge)
        }
        
        // First Week Complete
        if streak >= 7 && totalMiles >= 7.0 && !hasBadge(id: "special_first_week") {
            let badge = Badge(id: "special_first_week", name: "Perfect Week", description: "Ran at least a mile every day for a week!")
            badges.append(badge)
            newBadges.append(badge)
        }
        
        // MARK: - Hidden/Secret Badges
        // These don't show in the locked badges list - they're surprises!
        
        // Perfect 10 - Exactly 10.00 miles in a day
        if mostMilesInOneDay >= 10.0 && mostMilesInOneDay < 10.1 && !hasBadge(id: "hidden_perfect_10") {
            let badge = Badge(id: "hidden_perfect_10", name: "Perfect 10", description: "Ran exactly 10.00 miles in one day!", isHidden: true)
            badges.append(badge)
            newBadges.append(badge)
        }
        
        // Lucky Number - 7 miles on day 7 of streak
        if streak == 7 && mostMilesInOneDay >= 7.0 && !hasBadge(id: "hidden_lucky_7") {
            let badge = Badge(id: "hidden_lucky_7", name: "Lucky Seven", description: "Ran 7+ miles on day 7 of your streak!", isHidden: true)
            badges.append(badge)
            newBadges.append(badge)
        }
        
        // Double Trouble - 22 miles total (2x11)
        if totalMiles >= 22.0 && totalMiles < 23.0 && !hasBadge(id: "hidden_double_trouble") {
            let badge = Badge(id: "hidden_double_trouble", name: "Double Trouble", description: "Hit exactly 22 total miles!", isHidden: true)
            badges.append(badge)
            newBadges.append(badge)
        }
        
        // Century Double - 100 days AND 100 miles
        if streak >= 100 && totalMiles >= 100 && !hasBadge(id: "hidden_century_double") {
            let badge = Badge(id: "hidden_century_double", name: "Century Double", description: "100 day streak AND 100+ total miles!", isHidden: true)
            badges.append(badge)
            newBadges.append(badge)
        }
        
        // Speed + Distance combo - Sub 8 pace AND 5+ miles in a day
        if fastestMilePace > 0 && fastestMilePace <= 8.0 && mostMilesInOneDay >= 5.0 && !hasBadge(id: "hidden_speed_endurance") {
            let badge = Badge(id: "hidden_speed_endurance", name: "Speed & Endurance", description: "Sub-8 min pace AND 5+ mile day!", isHidden: true)
            badges.append(badge)
            newBadges.append(badge)
        }
        
        // Marathon Pace - Sub 10 min pace on a marathon distance
        if fastestMilePace > 0 && fastestMilePace <= 10.0 && mostMilesInOneDay >= 26.2 && !hasBadge(id: "hidden_marathon_pace") {
            let badge = Badge(id: "hidden_marathon_pace", name: "Marathon Master", description: "Marathon distance with sub-10 min pace!", isHidden: true)
            badges.append(badge)
            newBadges.append(badge)
        }
        
        // Triple Threat - 30 day streak, 30+ miles total, 3+ mile best day
        if streak >= 30 && totalMiles >= 30 && mostMilesInOneDay >= 3.0 && !hasBadge(id: "hidden_triple_threat") {
            let badge = Badge(id: "hidden_triple_threat", name: "Triple Threat", description: "30 day streak, 30+ miles, 3+ mile day!", isHidden: true)
            badges.append(badge)
            newBadges.append(badge)
        }
        
        // 50/50 Club - 50 day streak AND 50 miles
        if streak >= 50 && totalMiles >= 50 && !hasBadge(id: "hidden_50_50") {
            let badge = Badge(id: "hidden_50_50", name: "50/50 Club", description: "50 day streak AND 50+ total miles!", isHidden: true)
            badges.append(badge)
            newBadges.append(badge)
        }
        
        // Year of Running - 365 miles total
        if totalMiles >= 365 && !hasBadge(id: "hidden_year_miles") {
            let badge = Badge(id: "hidden_year_miles", name: "Year in Miles", description: "Ran 365 total miles - a mile for every day of the year!", isHidden: true)
            badges.append(badge)
            newBadges.append(badge)
        }
        
        // Thousand Club - 1000 days OR 1000 miles (either one)
        if (streak >= 1000 || totalMiles >= 1000) && !hasBadge(id: "hidden_thousand_club") {
            let badge = Badge(id: "hidden_thousand_club", name: "Thousand Club", description: "Reached 1000 in days OR miles!", isHidden: true)
            badges.append(badge)
            newBadges.append(badge)
        }
        
        // Pace Perfectionist - Sub 7 pace on a 10+ mile day
        if fastestMilePace > 0 && fastestMilePace <= 7.0 && mostMilesInOneDay >= 10.0 && !hasBadge(id: "hidden_pace_perfect") {
            let badge = Badge(id: "hidden_pace_perfect", name: "Pace Perfectionist", description: "Sub-7 pace AND 10+ mile day!", isHidden: true)
            badges.append(badge)
            newBadges.append(badge)
        }

        return newBadges
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
        let milesMilestones = [25, 50, 100, 150, 200, 250, 500, 750, 1000, 1500, 2000, 2500]
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
        let paceMilestones = [12, 11, 10, 9, 8, 7, 6, 5]
        for milestone in paceMilestones {
            let badgeId = "pace_\(milestone)min"
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
        
        // Distance badges (daily)
        let distanceBadges: [(String, String, String)] = [
            ("daily_2", "2 Mile Day", "Ran 2+ miles in one day!"),
            ("daily_3", "5K Runner", "Ran 3+ miles (5K) in one day!"),
            ("daily_5", "5 Mile Day", "Ran 5+ miles in one day!"),
            ("daily_10k", "10K Runner", "Ran 6.2+ miles (10K) in one day!"),
            ("daily_8", "8 Mile Day", "Ran 8+ miles in one day!"),
            ("daily_10", "10 Mile Day", "Ran 10+ miles in one day!"),
            ("daily_half", "Half Marathon", "Ran 13.1+ miles in one day!"),
            ("daily_15", "15 Mile Day", "Ran 15+ miles in one day!"),
            ("daily_20", "20 Mile Day", "Ran 20+ miles in one day!"),
            ("daily_marathon", "Marathon Runner", "Ran 26.2+ miles in one day!"),
            ("daily_50k", "50K Ultra", "Ran 31+ miles (50K) in one day!"),
            ("daily_ultra", "Ultra Legend", "Ran 50+ miles in one day!")
        ]
        
        for (badgeId, name, description) in distanceBadges {
            if !hasBadge(id: badgeId) {
                lockedBadges.append(Badge(
                    id: badgeId,
                    name: name,
                    description: description,
                    dateAwarded: Date.distantFuture,
                    isNew: false,
                    isLocked: true
                ))
            }
        }
        
        // Special badges (visible)
        let specialBadges: [(String, String, String)] = [
            ("special_first_mile", "First Mile", "Completed your first mile!"),
            ("special_first_week", "Perfect Week", "Ran every day for a week!")
        ]
        
        for (badgeId, name, description) in specialBadges {
            if !hasBadge(id: badgeId) {
                lockedBadges.append(Badge(
                    id: badgeId,
                    name: name,
                    description: description,
                    dateAwarded: Date.distantFuture,
                    isNew: false,
                    isLocked: true
                ))
            }
        }
        
        // Note: Hidden badges are NOT shown in locked list - they're surprises!
        
        return lockedBadges
    }
    
    // Helper functions for badge information
    private func getBadgeName(for id: String) -> String {
        let badgeNames: [String: String] = [
            // Consistency
            "consistency_3": "Getting Started",
            "consistency_5": "Building Habits",
            // Streaks
            "streak_7": "Week Warrior",
            "streak_10": "Ten Days Strong",
            "streak_14": "Fortnight Fighter",
            "streak_21": "Three Week Champion",
            "streak_30": "Monthly Master",
            "streak_45": "45 Day Legend",
            "streak_50": "Half Century",
            "streak_60": "Two Month Milestone",
            "streak_75": "Consistency King",
            "streak_90": "Quarter Year Hero",
            "streak_100": "Century Club",
            "streak_120": "Four Month Fury",
            "streak_150": "Unstoppable Force",
            "streak_180": "Half Year Hero",
            "streak_200": "Double Century",
            "streak_250": "Legendary Streak",
            "streak_300": "300 Club",
            "streak_365": "Year Warrior",
            "streak_500": "Elite Runner",
            "streak_730": "Two Year Titan",
            "streak_1000": "Immortal",
            // Miles
            "miles_25": "25 Mile Mark",
            "miles_50": "50 Mile Club",
            "miles_100": "Century Runner",
            "miles_150": "150 Mile Mark",
            "miles_200": "200 Mile Mark",
            "miles_250": "250 Mile Club",
            "miles_500": "500 Mile Club",
            "miles_750": "750 Mile Club",
            "miles_1000": "1000 Mile Club",
            "miles_1500": "1500 Mile Legend",
            "miles_2000": "2000 Mile Legend",
            "miles_2500": "Ultra Runner",
            // Pace
            "pace_12min": "Getting Faster",
            "pace_11min": "Picking Up Speed",
            "pace_10min": "Double Digits",
            "pace_9min": "Solid Pace",
            "pace_8min": "Fast Runner",
            "pace_7min": "Quick Runner",
            "pace_6min": "Speed Demon",
            "pace_5min": "Elite Speed"
        ]
        return badgeNames[id] ?? "Unknown Badge"
    }
    
    private func getBadgeDescription(for id: String) -> String {
        let badgeDescriptions: [String: String] = [
            // Consistency
            "consistency_3": "3 day streak!",
            "consistency_5": "5 day streak!",
            // Streaks
            "streak_7": "7 day streak!",
            "streak_10": "10 day streak!",
            "streak_14": "14 day streak!",
            "streak_21": "21 day streak!",
            "streak_30": "30 day streak!",
            "streak_45": "45 day streak!",
            "streak_50": "50 day streak!",
            "streak_60": "60 day streak!",
            "streak_75": "75 day streak!",
            "streak_90": "90 day streak!",
            "streak_100": "100 day streak!",
            "streak_120": "120 day streak!",
            "streak_150": "150 day streak!",
            "streak_180": "180 day streak!",
            "streak_200": "200 day streak!",
            "streak_250": "250 day streak!",
            "streak_300": "300 day streak!",
            "streak_365": "365 day streak!",
            "streak_500": "500 day streak!",
            "streak_730": "730 day streak!",
            "streak_1000": "1000 day streak!",
            // Miles
            "miles_25": "Ran 25 total miles!",
            "miles_50": "Ran 50 total miles!",
            "miles_100": "Ran 100 total miles!",
            "miles_150": "Ran 150 total miles!",
            "miles_200": "Ran 200 total miles!",
            "miles_250": "Ran 250 total miles!",
            "miles_500": "Ran 500 total miles!",
            "miles_750": "Ran 750 total miles!",
            "miles_1000": "Ran 1000 total miles!",
            "miles_1500": "Ran 1500 total miles!",
            "miles_2000": "Ran 2000 total miles!",
            "miles_2500": "Ran 2500 total miles!",
            // Pace
            "pace_12min": "Sub-12 minute mile!",
            "pace_11min": "Sub-11 minute mile!",
            "pace_10min": "Sub-10 minute mile!",
            "pace_9min": "Sub-9 minute mile!",
            "pace_8min": "Sub-8 minute mile!",
            "pace_7min": "Sub-7 minute mile!",
            "pace_6min": "Sub-6 minute mile!",
            "pace_5min": "Sub-5 minute mile!"
        ]
        return badgeDescriptions[id] ?? "Unknown achievement!"
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
        } else if id.starts(with: "special_") {
            return .special
        } else if id.starts(with: "hidden_") || id.starts(with: "secret_") {
            return .hidden
        }
        return .other
    }
    
    private func getBadgeRequirement(_ id: String) -> Int {
        // Extract number from badge ID for sorting
        let components = id.components(separatedBy: CharacterSet.decimalDigits.inverted)
        return components.compactMap { Int($0) }.first ?? 0
    }
    
    private enum BadgeCategory: Int {
        case streak = 0, miles = 1, speed = 2, distance = 3, special = 4, hidden = 5, other = 6
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
    var isHidden: Bool = false // Secret badges that don't show requirements until earned
    
    // Badge rarity (can be used for visual styling)
    var rarity: BadgeRarity {
        // Legendary badges
        if id.starts(with: "streak_365") || id.starts(with: "streak_500") || id.starts(with: "streak_1000") ||
           id.starts(with: "miles_1000") || id.starts(with: "miles_2500") ||
           id.starts(with: "daily_marathon") || id.starts(with: "daily_ultra") ||
           id.starts(with: "pace_5min") || id.starts(with: "pace_6min") ||
           id.starts(with: "hidden_") || id.starts(with: "secret_") {
            return .legendary
        }
        // Rare badges
        else if id.starts(with: "streak_100") || id.starts(with: "streak_150") || id.starts(with: "streak_200") ||
                id.starts(with: "streak_50") || id.starts(with: "streak_75") ||
                id.starts(with: "miles_500") || id.starts(with: "miles_750") ||
                id.starts(with: "daily_half") || id.starts(with: "daily_15") || id.starts(with: "daily_20") ||
                id.starts(with: "pace_7min") || id.starts(with: "pace_8min") ||
                id.starts(with: "special_") {
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