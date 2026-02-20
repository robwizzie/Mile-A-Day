import Foundation
import SwiftUI

class UserManager: ObservableObject {
    static let shared = UserManager()
    
    @Published var currentUser: User
    @Published var friends: [User] = []
    @Published var authToken: String?
    @Published var refreshToken: String?
    
    private let userDefaults = UserDefaults.standard
    private let currentUserKey = "currentUser"
    private let friendsKey = "friends"
    private let authTokenKey = "authToken"
    private let refreshTokenKey = "refreshToken"
    
    init() {
        // Load or create a new user
        if let userData = userDefaults.data(forKey: currentUserKey),
           let decodedUser = try? JSONDecoder().decode(User.self, from: userData) {
            self.currentUser = decodedUser
        } else {
            // Default user
            self.currentUser = User(name: "You")
        }
        
        // Load auth token
        self.authToken = userDefaults.string(forKey: authTokenKey)
        
        // Load refresh token
        self.refreshToken = userDefaults.string(forKey: refreshTokenKey)
        
        // Initialize widget data store with current values
        #if !os(watchOS)
        let currentMiles = WidgetDataStore.load().miles
        WidgetDataStore.save(todayMiles: currentMiles, goal: currentUser.goalMiles)
        WidgetDataStore.save(streak: currentUser.streak)
        #endif
        
        // Load friends
        if let friendsData = userDefaults.data(forKey: friendsKey),
           let decodedFriends = try? JSONDecoder().decode([User].self, from: friendsData) {
            self.friends = decodedFriends
        } else {
            // Sample friends for development
            self.friends = [
                User(name: "Alex", streak: 12, totalMiles: 45.2, fastestMilePace: 8.5, mostMilesInOneDay: 3.5),
                User(name: "Taylor", streak: 30, totalMiles: 120.7, fastestMilePace: 7.2, mostMilesInOneDay: 6.2),
                User(name: "Jordan", streak: 5, totalMiles: 18.1, fastestMilePace: 9.3, mostMilesInOneDay: 2.8)
            ]
        }
        
        // Load privacy settings
        if let privacyData = userDefaults.data(forKey: "privacySettings"),
           let decodedPrivacy = try? JSONDecoder().decode(PrivacySettings.self, from: privacyData) {
            self.currentUser.privacySettings = decodedPrivacy
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
        
        // Save auth token
        if let token = authToken {
            userDefaults.set(token, forKey: authTokenKey)
        }
        
        // Save refresh token
        if let token = refreshToken {
            userDefaults.set(token, forKey: refreshTokenKey)
        }
        
        // Save privacy settings
        if let privacyEncoded = try? JSONEncoder().encode(currentUser.privacySettings) {
            userDefaults.set(privacyEncoded, forKey: "privacySettings")
        }
        
        // Push streak to widget store
        #if !os(watchOS)
        WidgetDataStore.save(streak: currentUser.streak)
        #endif
    }
    
    // Handle Apple Sign In completion
    #if !os(watchOS)
    func handleAppleSignIn(profile: AppleSignInManager.AppleUserProfile, backendResponse: AppleSignInManager.BackendAuthResponse) {
        // Update current user with Apple data
        currentUser.appleId = profile.id
        currentUser.email = profile.email
        currentUser.authProvider = .apple
        currentUser.backendUserId = backendResponse.user.user_id
        currentUser.authToken = backendResponse.accessToken
        
        // Update name if we have it from Apple
        if let fullName = profile.fullName?.formatted(), !fullName.isEmpty {
            currentUser.name = fullName
        } else if ((backendResponse.user.username?.isEmpty) == nil) {
            currentUser.name = backendResponse.user.username ?? "User"
        }
        
        // Save Apple profile image if available
        if let profileImage = profile.profileImage {
            saveAppleProfileImage(profileImage)
        }
        
        // Store auth token
        authToken = backendResponse.accessToken
        
        // Store refresh token
        refreshToken = backendResponse.refreshToken
        
        // Store backend user ID in UserDefaults for FriendService
        UserDefaults.standard.set(backendResponse.user.user_id, forKey: "backendUserId")
        
        // Save all data
        saveUserData()
    }
    #endif
    
    // Save Apple profile image
    #if !os(watchOS)
    private func saveAppleProfileImage(_ image: UIImage) {
        if let data = image.jpegData(compressionQuality: 0.8) {
            UserDefaults.standard.set(data, forKey: "appleProfileImage")
        }
    }
    
    // Get Apple profile image
    func getAppleProfileImage() -> UIImage? {
        if let data = UserDefaults.standard.data(forKey: "appleProfileImage"),
           let image = UIImage(data: data) {
            return image
        }
        return nil
    }
    #endif
    
    // Sign out
    func signOut() {
        currentUser.appleId = nil
        currentUser.email = nil
        currentUser.authProvider = .guest
        currentUser.backendUserId = nil
        currentUser.authToken = nil
        authToken = nil
        refreshToken = nil
        
        // Clear stored tokens
        userDefaults.removeObject(forKey: authTokenKey)
        userDefaults.removeObject(forKey: refreshTokenKey)
        
        saveUserData()
    }
    
    // Token management methods
    func setTokens(accessToken: String, refreshToken: String) {
        self.authToken = accessToken
        self.refreshToken = refreshToken
        userDefaults.set(accessToken, forKey: authTokenKey)
        userDefaults.set(refreshToken, forKey: refreshTokenKey)
    }
    
    func getAccessToken() -> String? {
        return authToken ?? userDefaults.string(forKey: authTokenKey)
    }
    
    func getRefreshToken() -> String? {
        return refreshToken ?? userDefaults.string(forKey: refreshTokenKey)
    }
    
    // Update user stats from HealthKit data
    func updateUserWithHealthKitData(
        retroactiveStreak: Int,
        currentMiles: Double,
        totalMiles: Double,
        fastestPace: TimeInterval,
        mostMilesInDay: Double
    ) {
        currentUser.updateFromHealthKit(
            streak: retroactiveStreak,
            miles: currentMiles,
            totalMiles: totalMiles,
            fastestPace: fastestPace,
            mostMilesInDay: mostMilesInDay,
            date: Date()
        )
        
        // Check for retroactive badges after updating stats
        checkForRetroactiveBadges()
        
        // CRITICAL FIX: Save data to persist streak update
        // Without this, streak updates are only in memory and revert when app reopens
        saveUserData()
    }
    
    // Update fastest mile pace from backend (authoritative source)
    func updateFastestPaceFromBackend(_ paceMinutesPerMile: TimeInterval) {
        guard paceMinutesPerMile > 0 else { return }
        currentUser.fastestMilePace = paceMinutesPerMile
        saveUserData()
    }

    // Legacy method for backward compatibility
    func completeRun(miles: Double) {
        currentUser.updateStreak(miles: miles)
        saveUserData()
    }
    
    // Set user's daily goal
    func setDailyGoal(miles: Double) {
        currentUser.goalMiles = miles
        
        // Update widget data with new goal
        #if !os(watchOS)
        let currentData = WidgetDataStore.load()
        WidgetDataStore.save(todayMiles: currentData.miles, goal: miles)
        saveUserData()
        let currentMiles = WidgetDataStore.load().miles
        WidgetDataStore.save(todayMiles: currentMiles, goal: miles)
        #else
        saveUserData()
        #endif
    }
    
    // Get users sorted by streak (for leaderboard)
    func getLeaderboardByStreak() -> [User] {
        let allUsers = [currentUser] + friends
        return allUsers.sorted(by: { userA, userB in
            return userA.streak > userB.streak
        })
    }
    
    // Get users sorted by total miles (for leaderboard)
    func getLeaderboardByTotalMiles() -> [User] {
        let allUsers = [currentUser] + friends
        return allUsers.sorted(by: { userA, userB in
            return userA.totalMiles > userB.totalMiles
        })
    }
    
    // Get users sorted by fastest mile pace (for leaderboard)
    func getLeaderboardByPersonalRecord() -> [User] {
        let allUsers = [currentUser] + friends
        return allUsers.sorted(by: { userA, userB in
            // For pace, lower is better, and a zero pace should be ranked last
            if userA.fastestMilePace == 0 { return false }
            if userB.fastestMilePace == 0 { return true }
            return userA.fastestMilePace < userB.fastestMilePace
        })
    }
    
    // Get users sorted by most miles in one day (for leaderboard)
    func getLeaderboardByMostMilesInDay() -> [User] {
        let allUsers = [currentUser] + friends
        return allUsers.sorted(by: { userA, userB in
            return userA.mostMilesInOneDay > userB.mostMilesInOneDay
        })
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
    
    // Check for retroactive badges based on current stats
    func checkForRetroactiveBadges() {
        // Force a badge check with current stats
        let newBadges = currentUser.checkForMilestoneBadges()
        saveUserData()

        // Trigger celebrations for badges earned today (not retroactive ones)
        let today = Calendar.current.startOfDay(for: Date())
        for badge in newBadges {
            let badgeDate = Calendar.current.startOfDay(for: badge.dateAwarded)
            // Only celebrate badges earned today to avoid showing celebrations for old retroactive badges
            if badgeDate == today {
                CelebrationManager.shared.addCelebration(.badgeUnlocked(badge: badge))
            }
        }
    }
} 
