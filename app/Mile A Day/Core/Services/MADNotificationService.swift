import Foundation
import UserNotifications
import UIKit

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
            print("[Notifications] Authorization request failed: \(error)")
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
        // Check if we already sent a notification today
        if let lastDate = lastCompletionNotificationDate,
           Calendar.current.isDate(lastDate, inSameDayAs: Date()) {
            print("[Notifications] Already sent completion notification today, skipping")
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
        
        print("[Notifications] Sent mile completion notification")
    }

    /// Sends a local push announcing a friend's mile completion.
    /// - Parameter friendName: The friend's display name.
    func sendFriendCompletedNotification(friendName: String) {
        let content = UNMutableNotificationContent()
        content.title = "\(friendName) just ran a mile!"
        content.body = "Send a high-five and keep each other motivated."
        content.sound = .default
        schedule(content: content, trigger: .none, identifier: Identifier.friendCompleted(friendName))
    }

    /// Updates the daily reminder with intelligent scheduling.
    /// Only schedules reminder notifications if the user hasn't completed their goal.
    /// - Parameters:
    ///   - isCompleted: Whether the user has completed their daily goal
    ///   - currentMiles: Current miles completed today
    ///   - goalMiles: User's daily goal in miles
    ///   - hour: Hour to schedule the reminder (default 18 = 6 PM)
    func updateDailyReminder(isCompleted: Bool, currentMiles: Double = 0, goalMiles: Double = 1.0, at hour: Int = 18) {
        // Remove any pending daily reminder first
        center.removePendingNotificationRequests(withIdentifiers: [Identifier.dailyReminder])
        
        print("[Notifications] Updating daily reminder - Completed: \(isCompleted), Miles: \(currentMiles)/\(goalMiles)")
        
        var dateComponents = DateComponents()
        dateComponents.hour = hour
        dateComponents.calendar = Calendar.current

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)

        let content = UNMutableNotificationContent()
        content.sound = .default
        
        if isCompleted {
            // Congratulatory message - only schedule for tomorrow and beyond
            content.title = "Way to go!"
            content.body = "You crushed your mile today. See you tomorrow at the start line!"
            print("[Notifications] Scheduled congratulatory daily reminder")
        } else {
            // Motivational reminder - only fires if not completed
            content.title = "Mile still waiting…"
            content.body = "Don't forget to log your daily mile! Lace up and get moving."
            print("[Notifications] Scheduled motivational daily reminder")
        }

        schedule(content: content, trigger: .calendar(trigger), identifier: Identifier.dailyReminder)
    }
    
    /// Legacy method - use updateDailyReminder(isCompleted:currentMiles:goalMiles:at:) instead
    @available(*, deprecated, message: "Use updateDailyReminder(isCompleted:currentMiles:goalMiles:at:) instead")
    func updateDailyReminder(completed: Bool, at hour: Int = 18) {
        updateDailyReminder(isCompleted: completed, at: hour)
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
        
        print("[Notifications] Should send completion? \(shouldSend) (current: \(currentMiles), goal: \(goalMiles), previous: \(previousMiles), sent today: \(alreadySentToday))")
        
        return shouldSend
    }
    
    /// Resets the daily notification tracking (call at midnight or app launch)
    func resetDailyNotificationTracking() {
        if let lastDate = lastCompletionNotificationDate,
           !Calendar.current.isDate(lastDate, inSameDayAs: Date()) {
            lastCompletionNotificationDate = nil
            userDefaults.removeObject(forKey: lastNotificationKey)
            print("[Notifications] Reset daily notification tracking for new day")
        }
    }

    // MARK: - Remote Notifications
    /// Registers with APNs for remote pushes (friend completion etc.). Should be called from the AppDelegate.
    func registerForRemoteNotifications() {
        UIApplication.shared.registerForRemoteNotifications()
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
            if let error {
                print("[Notifications] Failed to schedule: \(error)")
            }
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
    }
}

// MARK: - UNUserNotificationCenterDelegate
extension MADNotificationService: UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        // For daily reminders, only show if user hasn't completed their goal
        if notification.request.identifier == Identifier.dailyReminder {
            // Check current completion status
            let widgetData = WidgetDataStore.load()
            let isCompleted = widgetData.miles >= widgetData.goal
            
            if isCompleted {
                print("[Notifications] Suppressing daily reminder - goal already completed")
                return [] // Don't show notification
            }
        }
        
        // Show banner even when app is foreground to reinforce motivation
        return [.banner, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        // Handle deep links or custom actions in future
    }
} 