import Foundation
import SwiftUI

class UserManager: ObservableObject {
    @Published var currentUser: User
    @Published var friends: [User] = []
    
    private let userDefaults = UserDefaults.standard
    private let currentUserKey = "currentUser"
    private let friendsKey = "friends"
    
    init() {
        // Load or create a new user
        if let userData = userDefaults.data(forKey: currentUserKey),
           let decodedUser = try? JSONDecoder().decode(User.self, from: userData) {
            self.currentUser = decodedUser
        } else {
            // Default user
            self.currentUser = User(name: "You")
        }
        
        // Load friends
        if let friendsData = userDefaults.data(forKey: friendsKey),
           let decodedFriends = try? JSONDecoder().decode([User].self, from: friendsData) {
            self.friends = decodedFriends
        } else {
            // Sample friends for development
            self.friends = [
                User(name: "Alex", streak: 12, totalMiles: 45.2, personalRecord: 3.5),
                User(name: "Taylor", streak: 30, totalMiles: 120.7, personalRecord: 6.2),
                User(name: "Jordan", streak: 5, totalMiles: 18.1, personalRecord: 2.8)
            ]
        }
    }
    
    // Save user data
    func saveUserData() {
        if let encoded = try? JSONEncoder().encode(currentUser) {
            userDefaults.set(encoded, forKey: currentUserKey)
        }
        
        if let encoded = try? JSONEncoder().encode(friends) {
            userDefaults.set(encoded, forKey: friendsKey)
        }
    }
    
    // Update user streak with new run
    func completeRun(miles: Double) {
        currentUser.updateStreak(miles: miles)
        saveUserData()
    }
    
    // Set user's daily goal
    func setDailyGoal(miles: Double) {
        currentUser.goalMiles = miles
        saveUserData()
    }
    
    // Get users sorted by streak (for leaderboard)
    func getLeaderboardByStreak() -> [User] {
        let allUsers = [currentUser] + friends
        return allUsers.sorted { $0.streak > $1.streak }
    }
    
    // Get users sorted by total miles (for leaderboard)
    func getLeaderboardByTotalMiles() -> [User] {
        let allUsers = [currentUser] + friends
        return allUsers.sorted { $0.totalMiles > $1.totalMiles }
    }
    
    // Get users sorted by personal record (for leaderboard)
    func getLeaderboardByPersonalRecord() -> [User] {
        let allUsers = [currentUser] + friends
        return allUsers.sorted { $0.personalRecord > $1.personalRecord }
    }
    
    // Mark new badges as viewed
    func markBadgesAsViewed() {
        for i in 0..<currentUser.badges.count {
            currentUser.badges[i].isNew = false
        }
        saveUserData()
    }
    
    // Check if there are any new badges
    var hasNewBadges: Bool {
        return currentUser.badges.contains { $0.isNew }
    }
} 