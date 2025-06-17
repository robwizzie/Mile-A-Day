import Foundation

struct NotificationPreferences: Codable {
    var dailyReminderEnabled: Bool = true
    var dailyReminderHour: Int = 18 // 24-hour format

    var mileCompletedEnabled: Bool = true
    var friendCompletedEnabled: Bool = true

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