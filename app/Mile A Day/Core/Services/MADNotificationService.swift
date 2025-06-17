import Foundation
import UserNotifications
import UIKit

/// A singleton that centralises all notification related logic for MAD.
///
/// - Handles permission requests
/// - Schedules and updates local notifications
/// - Registers and manages remote push notifications
///
/// Always access through `MADNotificationService.shared`.
final class MADNotificationService: NSObject, ObservableObject {
    // MARK: - Singleton
    static let shared = MADNotificationService()

    private let center = UNUserNotificationCenter.current()

    // Expose authorisation status to SwiftUI views
    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    // MARK: - Init
    private override init() {
        super.init()
        center.delegate = self
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
    func sendMileCompletedNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Mile Complete!"
        content.body = "Great job completing your mile today. Keep the streak alive!"
        content.sound = .default
        schedule(content: content, trigger: .none, identifier: Identifier.mileCompleted)
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

    /// Updates the daily 6 PM reminder.
    ///
    /// If `completed` is `true`, we schedule a congratulatory message at 6 PM.
    /// Otherwise a motivational reminder is scheduled.
    func updateDailyReminder(completed: Bool, at hour: Int = 18) {
        // Remove any pending daily reminder first
        center.removePendingNotificationRequests(withIdentifiers: [Identifier.dailyReminder])

        var dateComponents = DateComponents()
        dateComponents.hour = hour
        dateComponents.calendar = Calendar.current

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)

        let content = UNMutableNotificationContent()
        content.sound = .default
        if completed {
            content.title = "Way to go!"
            content.body = "You crushed your mile today. See you tomorrow at the start line!"
        } else {
            content.title = "Mile still waiting…"
            content.body = "Don't forget to log your daily mile! Lace up and get moving.";
        }

        schedule(content: content, trigger: .calendar(trigger), identifier: Identifier.dailyReminder)
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
        // Show banner even when app is foreground to reinforce motivation
        return [.banner, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        // Handle deep links or custom actions in future
    }
} 