import Foundation
import UserNotifications
import UIKit

extension Notification.Name {
    static let didReceivePushNotification = Notification.Name("didReceivePushNotification")
    static let didTapPushNotification = Notification.Name("didTapPushNotification")
}

/// A singleton that centralises all notification related logic for MAD.
///
/// - Handles permission requests
/// - Schedules and updates local notifications
/// - Registers and manages remote push notifications
/// - Prevents duplicate notifications
///
/// Always access through `MADNotificationService.shared`.
final class MADNotificationService: NSObject, ObservableObject {
    // MARK: - Singleton
    static let shared = MADNotificationService()

    private let center = UNUserNotificationCenter.current()

    // Expose authorisation status to SwiftUI views
    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    
    // Stores notification type from a tap when the app was not yet fully loaded
    @Published var pendingNotificationType: String?

    // Track when we last sent a completion notification to prevent duplicates
    private var lastCompletionNotificationDate: Date?
    private let userDefaults = UserDefaults.standard
    private let lastNotificationKey = "lastCompletionNotificationDate"

    // MARK: - Init
    private override init() {
        super.init()
        center.delegate = self
        
        // Load last notification date
        if let lastDate = userDefaults.object(forKey: lastNotificationKey) as? Date {
            lastCompletionNotificationDate = lastDate
        }
        
        Task {
            await refreshAuthorizationStatus()
        }
    }

    // MARK: - Public API

    /// Requests notification permission from the user.
    @MainActor
    func requestAuthorization() async {
        do {
            let options: UNAuthorizationOptions = [.alert, .sound, .badge]
            let granted = try await center.requestAuthorization(options: options)
            authorizationStatus = granted ? .authorized : .denied
        } catch {
            authorizationStatus = .denied
        }
    }

    /// Refreshes the cached notification authorization status.
    @MainActor
    func refreshAuthorizationStatus() async {
        let settings = await center.notificationSettings()
        authorizationStatus = settings.authorizationStatus
    }

    // MARK: - Scheduling Helpers

    /// Immediately sends a local notification celebrating mile completion.
    /// Prevents duplicate notifications for the same day.
    func sendMileCompletedNotification() {
        // Respect user preferences
        let prefs = NotificationPreferences.load()
        guard prefs.mileCompletedEnabled else { return }
        
        // Check if we already sent a notification today
        if let lastDate = lastCompletionNotificationDate,
           Calendar.current.isDate(lastDate, inSameDayAs: Date()) {
            return
        }
        
        let content = UNMutableNotificationContent()
        content.title = "Way to go!"
        content.body = "Great job completing your mile today. Keep the streak alive!"
        content.sound = .default
        
        schedule(content: content, trigger: .none, identifier: Identifier.mileCompleted)
        
        // Track that we sent a notification today
        lastCompletionNotificationDate = Date()
        userDefaults.set(lastCompletionNotificationDate, forKey: lastNotificationKey)
    }

    /// Sends a local push announcing a friend's mile completion.
    /// - Parameter friendName: The friend's display name.
    func sendFriendCompletedNotification(friendName: String) {
        // Respect user preferences
        let prefs = NotificationPreferences.load()
        guard prefs.friendCompletedEnabled else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "\(friendName) just ran a mile!"
        content.body = "Send a high-five and keep each other motivated."
        content.sound = .default
        schedule(content: content, trigger: .none, identifier: Identifier.friendCompleted(friendName))
    }

    /// Updates the daily reminder with intelligent scheduling.
    /// Schedules a one-shot notification for the next occurrence of the reminder hour.
    /// Content changes based on whether the user has completed their goal:
    /// - Completed: "Way to go!" congratulatory message
    /// - Not completed: "Mile still waiting…" motivational nudge
    /// Must be called on every foreground resume and health data update so the
    /// notification always reflects the latest completion state.
    func updateDailyReminder(isCompleted: Bool, currentMiles: Double = 0, goalMiles: Double = 1.0, at hour: Int? = nil) {
        // Remove any pending daily reminder first
        center.removePendingNotificationRequests(withIdentifiers: [Identifier.dailyReminder])

        // Respect user preferences
        let prefs = NotificationPreferences.load()
        guard prefs.dailyReminderEnabled else { return }

        let reminderHour = hour ?? prefs.dailyReminderHour

        // Schedule a one-shot notification for the next occurrence of reminderHour.
        // One-shot ensures stale content can never fire on a future day — the app must
        // re-evaluate and reschedule each time it runs.
        let now = Date()
        var targetComponents = Calendar.current.dateComponents([.year, .month, .day], from: now)
        targetComponents.hour = reminderHour
        targetComponents.minute = 0
        targetComponents.second = 0

        if let targetDate = Calendar.current.date(from: targetComponents), targetDate <= now {
            // Already past the reminder hour today — schedule for tomorrow
            if let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: now) {
                targetComponents = Calendar.current.dateComponents([.year, .month, .day], from: tomorrow)
                targetComponents.hour = reminderHour
                targetComponents.minute = 0
                targetComponents.second = 0
            }
        }

        let trigger = UNCalendarNotificationTrigger(dateMatching: targetComponents, repeats: false)

        let content = UNMutableNotificationContent()
        content.sound = .default

        if isCompleted {
            content.title = "Way to go!"
            content.body = "You crushed your mile today. See you tomorrow at the start line!"
        } else {
            content.title = "Mile still waiting…"
            content.body = "Don't forget to log your daily mile! Lace up and get moving."
        }

        schedule(content: content, trigger: .calendar(trigger), identifier: Identifier.dailyReminder)
    }
    
    // MARK: - Smart Notification Logic
    
    /// Checks if we should send a completion notification based on current progress
    /// - Parameters:
    ///   - currentMiles: Current miles completed
    ///   - goalMiles: Daily goal in miles
    ///   - previousMiles: Previous miles count (to detect when goal was just reached)
    /// - Returns: True if notification should be sent
    func shouldSendCompletionNotification(currentMiles: Double, goalMiles: Double, previousMiles: Double) -> Bool {
        // Only send if:
        // 1. Current miles meets or exceeds goal
        // 2. Previous miles was below goal (just completed)
        // 3. Haven't sent notification today already
        
        let justCompleted = currentMiles >= goalMiles && previousMiles < goalMiles
        let alreadySentToday = lastCompletionNotificationDate != nil && 
                             Calendar.current.isDate(lastCompletionNotificationDate!, inSameDayAs: Date())
        
        let shouldSend = justCompleted && !alreadySentToday
        
        return shouldSend
    }
    
    /// Sends a notification when a new friend request is received.
    /// Intended to be called on the device that detects a new incoming request.
    /// - Parameter fromName: Display name of the user who sent the request.
    func sendFriendRequestReceivedNotification(fromName: String) {
        let prefs = NotificationPreferences.load()
        guard prefs.friendRequestReceivedEnabled else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "New friend request"
        content.body = "\(fromName) just sent you a friend request."
        content.sound = .default
        
        schedule(content: content, trigger: .none, identifier: Identifier.friendRequestReceived(fromName))
    }
    
    /// Sends a notification when a friendship is created (a request is accepted).
    /// This can be triggered on whichever device first sees the new friendship.
    /// - Parameter friendName: Display name of the new friend.
    func sendFriendRequestAcceptedNotification(friendName: String) {
        let prefs = NotificationPreferences.load()
        guard prefs.friendRequestAcceptedEnabled else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "You're now friends!"
        content.body = "You and \(friendName) are now friends."
        content.sound = .default
        
        schedule(content: content, trigger: .none, identifier: Identifier.friendRequestAccepted(friendName))
    }
    
    /// Resets the daily notification tracking (call at midnight or app launch)
    func resetDailyNotificationTracking() {
        if let lastDate = lastCompletionNotificationDate,
           !Calendar.current.isDate(lastDate, inSameDayAs: Date()) {
            lastCompletionNotificationDate = nil
            userDefaults.removeObject(forKey: lastNotificationKey)
        }
    }

    // MARK: - Remote Notifications

    /// The current APNs device token (hex string), kept in memory for unregister on sign-out.
    private(set) var currentDeviceToken: String?

    /// Registers with APNs for remote pushes. Call after auth + notification permission granted.
    func registerForRemoteNotifications() {
        UIApplication.shared.registerForRemoteNotifications()
    }

    /// Sends the device token to the backend. Called from AppDelegate when APNs returns a token.
    @MainActor
    func sendDeviceTokenToBackend(_ token: String) async {
        currentDeviceToken = token
        UserDefaults.standard.set(token, forKey: "apnsDeviceToken")

        guard UserDefaults.standard.string(forKey: "authToken") != nil else {
            print("[Notifications] No auth token, skipping device token registration")
            return
        }

        do {
            struct RegisterRequest: Codable { let device_token: String }
            let body = try JSONEncoder().encode(RegisterRequest(device_token: token))
            let _: [String: String] = try await APIClient.fancyFetch(
                endpoint: "/devices/register",
                method: .POST,
                body: body,
                responseType: [String: String].self
            )
            print("[Notifications] Device token registered with backend")
        } catch {
            print("[Notifications] Failed to register device token: \(error.localizedDescription)")
        }
    }

    /// Unregisters the device token from the backend. Call on sign-out.
    @MainActor
    func unregisterDeviceToken() async {
        let token = currentDeviceToken ?? UserDefaults.standard.string(forKey: "apnsDeviceToken")
        guard let token else { return }

        do {
            struct UnregisterRequest: Codable { let device_token: String }
            let body = try JSONEncoder().encode(UnregisterRequest(device_token: token))
            let _: [String: String] = try await APIClient.fancyFetch(
                endpoint: "/devices/unregister",
                method: .DELETE,
                body: body,
                responseType: [String: String].self
            )
            print("[Notifications] Device token unregistered from backend")
        } catch {
            print("[Notifications] Failed to unregister device token: \(error.localizedDescription)")
        }

        currentDeviceToken = nil
        UserDefaults.standard.removeObject(forKey: "apnsDeviceToken")
    }

    /// Checks if a remote notification type is enabled in user preferences.
    private func isRemoteNotificationEnabled(type: String) -> Bool {
        let prefs = NotificationPreferences.load()
        switch type {
        case "friend_request": return prefs.friendRequestReceivedEnabled
        case "friend_request_accepted": return prefs.friendRequestAcceptedEnabled
        case "friend_nudge": return prefs.friendNudgeEnabled
        case "friend_activity": return prefs.friendCompletedEnabled
        case "competition_invite": return prefs.competitionInviteEnabled
        case "competition_accepted": return prefs.competitionAcceptedEnabled
        case "competition_started", "competition_updates": return prefs.competitionStartEnabled
        case "competition_finished": return prefs.competitionFinishEnabled
        case "competition_nudge": return prefs.competitionNudgeEnabled
        case "competition_flex": return prefs.competitionFlexEnabled
        case "competition_milestone": return prefs.competitionMilestonesEnabled
        default: return true
        }
    }

    // MARK: - Private helpers

    private func schedule(content: UNMutableNotificationContent, trigger: TriggerType, identifier: String) {
        let notificationTrigger: UNNotificationTrigger?
        switch trigger {
        case .none:
            notificationTrigger = nil
        case .calendar(let cal):
            notificationTrigger = cal
        case .timeInterval(let interval, let repeats):
            notificationTrigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: repeats)
        }

        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: notificationTrigger)

        center.add(request) { error in
            // Notification scheduling completed
        }
    }
}

// MARK: - Identifiers & Helpers
extension MADNotificationService {
    enum TriggerType {
        case none
        case calendar(UNCalendarNotificationTrigger)
        case timeInterval(TimeInterval, repeats: Bool)
    }

    struct Identifier {
        static let mileCompleted = "mileCompleted"
        static let dailyReminder = "dailyReminder"
        static func friendCompleted(_ friend: String) -> String { "friendCompleted_\(friend)" }
        static func friendRequestReceived(_ from: String) -> String { "friendRequestReceived_\(from)" }
        static func friendRequestAccepted(_ friend: String) -> String { "friendRequestAccepted_\(friend)" }
    }
}

// MARK: - UNUserNotificationCenterDelegate
extension MADNotificationService: UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        // For daily reminders, do a last-second check: if the content says
        // "Mile still waiting" but the user has actually completed their goal,
        // suppress it. This catches the edge case where HealthKit data arrived
        // after the notification was scheduled but before it fired.
        if notification.request.identifier == Identifier.dailyReminder {
            let widgetData = WidgetDataStore.load()
            let isCompleted = widgetData.miles >= widgetData.goal
            let isReminderContent = notification.request.content.title.contains("waiting")
            if isCompleted && isReminderContent {
                center.removePendingNotificationRequests(withIdentifiers: [Identifier.dailyReminder])
                return []
            }
        }

        // For remote notifications, check user preferences
        let userInfo = notification.request.content.userInfo
        if let type = userInfo["type"] as? String {
            if !isRemoteNotificationEnabled(type: type) {
                return []
            }

            // Check DND schedule
            let prefs = NotificationPreferences.load()
            if prefs.dndEnabled {
                let hour = Calendar.current.component(.hour, from: Date())
                let inDND: Bool
                if prefs.dndStartHour > prefs.dndEndHour {
                    // Spans midnight (e.g., 22 to 8)
                    inDND = hour >= prefs.dndStartHour || hour < prefs.dndEndHour
                } else {
                    inDND = hour >= prefs.dndStartHour && hour < prefs.dndEndHour
                }
                if inDND {
                    return [] // Suppress banner during DND
                }
            }

            // Notify the app so badge counts can refresh while in foreground
            let data = userInfo["data"] as? [String: String] ?? [:]
            NotificationCenter.default.post(
                name: .didReceivePushNotification,
                object: nil,
                userInfo: ["type": type, "data": data]
            )
        }

        return [.banner, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let userInfo = response.notification.request.content.userInfo
        guard let type = userInfo["type"] as? String else { return }
        let data = userInfo["data"] as? [String: String] ?? [:]

        // Store for cold-launch case (MainTabView may not be mounted yet)
        pendingNotificationType = type

        // Post a tap-specific notification so the app can navigate to the right screen
        NotificationCenter.default.post(
            name: .didTapPushNotification,
            object: nil,
            userInfo: ["type": type, "data": data]
        )
    }
} 