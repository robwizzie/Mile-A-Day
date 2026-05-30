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
    
    init() {
        // Load or create a new user
        if let userData = userDefaults.data(forKey: currentUserKey),
           let decodedUser = try? JSONDecoder().decode(User.self, from: userData) {
            self.currentUser = decodedUser
        } else {
            // Default user
            self.currentUser = User(name: "You")
        }
        
        // Load tokens from Keychain (falls back to UserDefaults legacy mirror
        // on first read after upgrade, then promotes the value into Keychain).
        self.authToken = TokenStore.accessToken
        self.refreshToken = TokenStore.refreshToken
        
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

        #if !os(watchOS)
        // Refresh server-side rewards after every successful workout upload.
        NotificationCenter.default.addObserver(
            forName: Notification.Name("MAD_WorkoutsUploaded"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            guard let userId = self.currentUser.backendUserId else { return }
            Task {
                await self.refreshBadgesFromServer()
                await ChallengeService.refresh(userId: userId)
            }
        }
        #endif
    }
    
    // Save user data
    func saveUserData() {
        if let encoded = try? JSONEncoder().encode(currentUser) {
            userDefaults.set(encoded, forKey: currentUserKey)
        }
        
        if let encoded = try? JSONEncoder().encode(friends) {
            userDefaults.set(encoded, forKey: friendsKey)
        }
        
        // Tokens are persisted via TokenStore (Keychain + UserDefaults mirror)
        // at the point they're set, so saveUserData() no longer writes them.
        
        // Save privacy settings
        if let privacyEncoded = try? JSONEncoder().encode(currentUser.privacySettings) {
            userDefaults.set(privacyEncoded, forKey: "privacySettings")
        }
        
        // Push streak to widget store
        #if !os(watchOS)
        WidgetDataStore.save(streak: currentUser.streak)
        // Mirror the latest profile/goal to the watch so its home screen never
        // disagrees with the iPhone (streak, goal, first name).
        MADWatchBridge.shared.pushSnapshotIfReady()
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
        
        // Pick up username from backend if it exists
        if let backendUsername = backendResponse.user.username, !backendUsername.isEmpty {
            currentUser.username = backendUsername
        }

        // Sync profile fields from backend
        currentUser.firstName = backendResponse.user.first_name
        currentUser.lastName = backendResponse.user.last_name
        currentUser.bio = backendResponse.user.bio
        currentUser.profileImageUrl = backendResponse.user.profile_image_url
        currentUser.role = backendResponse.user.role

        // Update name if we have it from Apple
        if let fullName = profile.fullName?.formatted(), !fullName.isEmpty {
            currentUser.name = fullName
        } else if let backendUsername = backendResponse.user.username, !backendUsername.isEmpty {
            currentUser.name = backendUsername
        }
        
        // Save Apple profile image if available
        if let profileImage = profile.profileImage {
            saveAppleProfileImage(profileImage)
        }
        
        // Persist tokens via the canonical Keychain-backed store (also mirrors
        // to UserDefaults for legacy readers).
        authToken = backendResponse.accessToken
        refreshToken = backendResponse.refreshToken
        TokenStore.setTokens(
            accessToken: backendResponse.accessToken,
            refreshToken: backendResponse.refreshToken
        )

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
        // Fire-and-forget server-side revocation so the refresh token can't
        // be reused even if it's leaked. We must capture the value BEFORE we
        // clear local state.
        let tokenToRevoke = TokenStore.refreshToken
        if let rt = tokenToRevoke, !rt.isEmpty {
            Task.detached {
                await Self.revokeRefreshTokenOnBackend(rt)
            }
        }

        currentUser.appleId = nil
        currentUser.email = nil
        currentUser.authProvider = .guest
        currentUser.backendUserId = nil
        currentUser.authToken = nil
        authToken = nil
        refreshToken = nil

        // Clear stored tokens (Keychain + legacy UserDefaults mirror).
        TokenStore.clear()

        saveUserData()
    }

    /// Best-effort POST to /auth/logout. Failure is fine — local state is
    /// already wiped — but a successful call lets the backend mark the
    /// refresh token revoked so it can't be replayed.
    private static func revokeRefreshTokenOnBackend(_ refreshToken: String) async {
        guard let url = URL(string: "https://mad.mindgoblin.tech/auth/logout") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["refreshToken": refreshToken])
        _ = try? await URLSession.shared.data(for: request)
    }
    
    /// Permanently deletes the user's account on the backend, then clears all local state.
    ///
    /// Calls `DELETE /users/{userId}`, which cascades to workouts, splits, competitions,
    /// friendships, and refresh tokens. On success, performs the same local cleanup as
    /// `signOut()` so the app returns to the unauthenticated state.
    ///
    /// Throws if the network call fails. Callers should surface the error and leave the
    /// user signed in so they can retry.
    #if !os(watchOS)
    @MainActor
    func deleteAccount() async throws {
        guard let userId = currentUser.backendUserId, !userId.isEmpty else {
            throw NSError(
                domain: "UserManager",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "No active user to delete."]
            )
        }

        let _: [String: String] = try await APIClient.fancyFetch(
            endpoint: "/users/\(userId)",
            method: .DELETE,
            body: nil,
            responseType: [String: String].self
        )

        signOut()
    }
    #endif

    // Token management methods
    func setTokens(accessToken: String, refreshToken: String) {
        self.authToken = accessToken
        self.refreshToken = refreshToken
        TokenStore.setTokens(accessToken: accessToken, refreshToken: refreshToken)
    }

    func getAccessToken() -> String? {
        return TokenStore.accessToken
    }

    func getRefreshToken() -> String? {
        return TokenStore.refreshToken
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
    
    // Set fastest mile pace from backend. The backend's workout_splits table is the
    // authoritative source of truth for PRs — this overwrites whatever was there
    // (including a stale HealthKit-derived value), so the value can go up or down.
    func updateFastestPaceFromBackend(_ paceMinutesPerMile: TimeInterval) {
        guard paceMinutesPerMile > 0 else { return }
        guard currentUser.fastestMilePace != paceMinutesPerMile else { return }
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
    
    // Mark new badges as viewed — clear locally + sync to server.
    func markBadgesAsViewed() {
        for i in 0..<currentUser.badges.count {
            currentUser.badges[i].isNew = false
        }
        saveUserData()

        #if !os(watchOS)
        if let userId = currentUser.backendUserId {
            Task.detached {
                do {
                    _ = try await BadgeAPIService.markViewed(userId: userId)
                } catch {
                    print("[UserManager] markViewed failed: \(error)")
                }
            }
        }
        #endif
    }

    // Check if there are any new badges
    var hasNewBadges: Bool {
        return currentUser.badges.contains { $0.isNew }
    }

    /// Pinned badges for the local user's profile showcase, sorted by pin slot ascending.
    var pinnedBadges: [Badge] {
        currentUser.badges
            .filter { $0.pinSlot != nil }
            .sorted { ($0.pinSlot ?? 0) < ($1.pinSlot ?? 0) }
    }

    /// Replace the user's pinned badges. `badgeIds` order becomes pin slot 0..2 (max 3).
    /// Optimistically updates local state, then pushes to the server.
    /// Returns `nil` on success, an error message on failure (so the UI can show it).
    @MainActor
    @discardableResult
    func setPinnedBadges(_ badgeIds: [String]) async -> String? {
        #if !os(watchOS)
        guard let userId = currentUser.backendUserId else {
            return "Not signed in — try restarting the app."
        }
        let clamped = Array(badgeIds.prefix(3))

        let originalBadges = currentUser.badges
        applyPinSlots(clamped)
        saveUserData()

        do {
            let dtos = try await BadgeAPIService.setPinnedBadges(userId: userId, badgeIds: clamped)
            let fresh = dtos.map { $0.toBadge() }
            currentUser.badges = fresh
            saveUserData()
            return nil
        } catch {
            print("[UserManager] setPinnedBadges failed: \(error)")
            currentUser.badges = originalBadges
            saveUserData()
            return "Couldn't save pins: \(error.localizedDescription)"
        }
        #else
        return nil
        #endif
    }

    private func applyPinSlots(_ badgeIds: [String]) {
        let slotByBadgeId = Dictionary(uniqueKeysWithValues: badgeIds.enumerated().map { ($1, $0) })
        for i in 0..<currentUser.badges.count {
            currentUser.badges[i].pinSlot = slotByBadgeId[currentUser.badges[i].id]
        }
    }

    /// Fetch the user's earned badges from the backend. Server is authoritative.
    /// Safe to call on every workout-upload completion and on Badges view appear.
    func refreshBadgesFromServer() async {
        #if !os(watchOS)
        guard let userId = currentUser.backendUserId else { return }
        do {
            let dtos = try await BadgeAPIService.fetchUserBadges(userId: userId)
            let fetched = dtos.map { $0.toBadge() }
            let existingIds = Set(currentUser.badges.map { $0.id })

            await MainActor.run {
                currentUser.badges = fetched
                saveUserData()

                // Decide whether a yearly headline celebration is owed BEFORE we
                // queue any badge celebrations. If yes, suppress the matching
                // 365/730/etc. badge popups so they don't pile on top.
                let yearlyOwed = checkAndQueueYearlyCelebration()
                let suppressedBadgeIDs: Set<String> = yearlyOwed ? suppressedBadgeIDsForYearly() : []

                // Celebrate freshly-earned badges (not previously present).
                let today = Calendar.current.startOfDay(for: Date())
                for badge in fetched {
                    let earnedToday = Calendar.current.startOfDay(for: badge.dateAwarded) == today
                    if earnedToday && !existingIds.contains(badge.id) && !suppressedBadgeIDs.contains(badge.id) {
                        CelebrationManager.shared.addCelebration(.badgeUnlocked(badge: badge))
                    }
                }
            }
        } catch {
            print("[UserManager] refreshBadgesFromServer failed: \(error)")
        }
        #endif
    }

    // MARK: - Yearly milestone

    #if !os(watchOS)
    /// Persists the highest year-boundary streak we've already celebrated (e.g. 365, 730, 1095…).
    /// `-1` is the uninitialized sentinel so existing users with mid-year streaks aren't
    /// retroactively flooded with year-1/2/3 animations on first launch with this feature.
    @AppStorage("lastCelebratedYearMilestoneStreak") private var lastCelebratedYearMilestoneStreak: Int = -1

    /// Returns true if a yearly celebration was queued.
    @discardableResult
    private func checkAndQueueYearlyCelebration() -> Bool {
        let streak = currentUser.streak
        let currentYearBoundary = (streak / 365) * 365

        // First-run init: skip retroactively firing for users whose streak already
        // crossed year boundaries before this feature shipped.
        if lastCelebratedYearMilestoneStreak == -1 {
            lastCelebratedYearMilestoneStreak = currentYearBoundary
            return false
        }

        guard currentYearBoundary >= 365,
              currentYearBoundary > lastCelebratedYearMilestoneStreak
        else { return false }

        let years = currentYearBoundary / 365
        let startDate = Calendar.current.date(byAdding: .day, value: -streak, to: Date())
        let info = YearlyMilestoneInfo(
            years: years,
            totalMiles: currentUser.totalMiles,
            totalStreakDays: streak,
            streakStartDate: startDate
        )

        CelebrationManager.shared.addCelebration(.yearMilestone(info: info))
        lastCelebratedYearMilestoneStreak = currentYearBoundary
        return true
    }

    /// Streak-badge IDs that should be silenced when a yearly celebration is firing
    /// for the same milestone day.
    private func suppressedBadgeIDsForYearly() -> Set<String> {
        ["streak_365", "streak_730"]
    }
    #endif

    /// Legacy shim — kept so existing callers compile. Delegates to the server-side fetch.
    /// The local `checkForMilestoneBadges()` evaluator is no longer used.
    func checkForRetroactiveBadges() {
        Task { await refreshBadgesFromServer() }
    }
} 
