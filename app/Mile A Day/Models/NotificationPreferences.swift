import Foundation

/// Who may see my workout CONTENT — routes and photos. Mirrors the backend's
/// `workout_visibility` on /notifications/preferences; the raw values must stay
/// exactly these three strings (the DB has a CHECK constraint on them).
///
/// This is the coarse gate: it decides WHO gets in at all. The sharing toggles
/// below it (`shareRouteMaps`, `shareWorkoutsToFeed`) decide WHAT those people
/// then see. Both apply.
enum WorkoutVisibility: String, Codable, CaseIterable, Identifiable {
    case `public`
    case friends
    case `private`

    var id: String { rawValue }

    var title: String {
        switch self {
        case .public: return "Everyone"
        case .friends: return "Friends only"
        case .private: return "Only me"
        }
    }

    var subtitle: String {
        switch self {
        case .public:
            return "Any Mile A Day user can open your profile and see your runs, routes and photos."
        case .friends:
            return "Only friends you've accepted. People you block never see them."
        case .private:
            return "Nobody but you. Your posts leave your friends' feeds too."
        }
    }

    var icon: String {
        switch self {
        case .public: return "globe.americas.fill"
        case .friends: return "person.2.fill"
        case .private: return "lock.fill"
        }
    }
}

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

    /// Remind me about friend requests I've left unanswered for over a day.
    /// Unlike the other flags here, this one is synced to the backend — the
    /// reminder is sent server-side, so a purely local switch could not turn it
    /// off (App Review 4.5.4 requires a working opt-out).
    var friendRequestReminderEnabled: Bool = true

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

    /// Surface the shareable "Your Week" recap (feed teaser card on
    /// Sunday/Monday). Same optional-backing pattern as shareRouteMaps so
    /// prefs saved by older app versions (no key) still decode.
    private var weeklyRecapEnabledRaw: Bool?
    var weeklyRecapEnabled: Bool {
        get { weeklyRecapEnabledRaw ?? true }
        set { weeklyRecapEnabledRaw = newValue }
    }

    /// Who can see my routes and photos. Same optional-backing pattern, and an
    /// unrecognised stored value falls back to `.friends` rather than to
    /// something more exposed.
    private var workoutVisibilityRaw: String?
    var workoutVisibility: WorkoutVisibility {
        get { workoutVisibilityRaw.flatMap(WorkoutVisibility.init(rawValue:)) ?? .friends }
        set { workoutVisibilityRaw = newValue.rawValue }
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
