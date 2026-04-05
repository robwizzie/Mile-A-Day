import Foundation

struct NotificationPreferences: Codable {
    var dailyReminderEnabled: Bool = true
    var dailyReminderHour: Int = 18 // 24-hour format

    var mileCompletedEnabled: Bool = true
    var friendCompletedEnabled: Bool = true

    /// Notify when someone sends me a friend request.
    var friendRequestReceivedEnabled: Bool = true

    /// Notify when a friend request results in a new friendship.
    var friendRequestAcceptedEnabled: Bool = true

    // Competition notifications
    var competitionInviteEnabled: Bool = true
    var competitionAcceptedEnabled: Bool = true
    var competitionStartEnabled: Bool = true
    var competitionFinishEnabled: Bool = true
    var competitionNudgeEnabled: Bool = true
    var competitionFlexEnabled: Bool = true
    var competitionMilestonesEnabled: Bool = true

    // Friend nudge notifications
    var friendNudgeEnabled: Bool = true

    // Do Not Disturb schedule
    var dndEnabled: Bool = false
    var dndStartHour: Int = 22  // 10 PM
    var dndEndHour: Int = 8     // 8 AM

    static let `default` = NotificationPreferences()
}

extension NotificationPreferences {
    private static let storageKey = "MAD_NOTIFICATION_PREFERENCES"

    /// Loads stored preferences or returns default values.
    static func load() -> NotificationPreferences {
        guard
            let data = UserDefaults.standard.data(forKey: storageKey),
            let prefs = try? JSONDecoder().decode(NotificationPreferences.self, from: data)
        else {
            return .default
        }
        return prefs
    }

    /// Persists the current preferences to `UserDefaults`.
    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
}
