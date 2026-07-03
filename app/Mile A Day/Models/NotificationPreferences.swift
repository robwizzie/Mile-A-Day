import Foundation

struct NotificationPreferences: Codable {
    var dailyReminderEnabled: Bool = true
    var dailyReminderHour: Int = 18 // 24-hour format

    var mileCompletedEnabled: Bool = true
    var friendCompletedEnabled: Bool = true
    var friendPersonalBestEnabled: Bool = true

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

    // Hype reactions (positive friend/competitor reaction to a completed mile)
    var hypeEnabled: Bool = true

    // Step goal achieved (local notification when daily 10k is hit)
    var stepGoalEnabled: Bool = true

    // Friend nudge notifications
    var friendNudgeEnabled: Bool = true

    // Feed & Stories (v2)
    /// Include my raw walks/runs as activity cards in friends' feed.
    var shareWorkoutsToFeed: Bool = true
    /// Notify me when a friend shares a new photo post.
    var friendPostsEnabled: Bool = true
    /// Show my GPS route maps on my feed entries and posts. Off = friends see
    /// the cards without the route slide/map (I still see my own).
    /// Optional backing field so prefs saved by older app versions (no key)
    /// still decode instead of silently resetting everything to defaults.
    private var shareRouteMapsRaw: Bool?
    var shareRouteMaps: Bool {
        get { shareRouteMapsRaw ?? true }
        set { shareRouteMapsRaw = newValue }
    }

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
