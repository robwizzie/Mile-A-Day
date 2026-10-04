import Foundation

/// Who sees ONE walk — the choice the post-run photo prompt puts in front of
/// the user, so nobody has to discover after the fact that a walk went to the
/// feed (with or without a photo), or wonder why it's in friends' feeds but
/// not on their own grid.
///
/// Three answers, because the server has exactly three distinct outcomes for
/// a walk without a photo:
///   - `feedAndProfile`: the route/stats card goes to the feed AND the grid.
///   - `feedOnly`: the card goes to the feed with `on_profile: false`, so it
///     stays off the grid (posts.on_profile).
///   - `offFeed`: no card at all, and the walk's raw workout card is kept out
///     of friends' feeds too (`PUT …/feed-hidden`). Without that second half
///     "skip and it stays off the feed" was untrue: friends still got the
///     workout card unless the account-wide "Share my walks & runs" switch
///     was off.
///
/// A photo post is still decided on the composer's share step (Story / Feed /
/// Both + "Show on my profile"); this choice seeds that screen.
enum WalkAudience: String, CaseIterable, Identifiable {
    case feedAndProfile
    case feedOnly
    case offFeed

    var id: String { rawValue }

    /// Short label for the chooser tiles.
    var title: String {
        switch self {
        case .feedAndProfile: return "Feed + profile"
        case .feedOnly: return "Feed only"
        case .offFeed: return "Off the feed"
        }
    }

    var icon: String {
        switch self {
        case .feedAndProfile: return "person.2.fill"
        case .feedOnly: return "rectangle.stack.fill"
        case .offFeed: return "eye.slash.fill"
        }
    }

    /// One plain sentence naming exactly what happens. `noun` is "walk"/"run".
    func explanation(noun: String) -> String {
        switch self {
        case .feedAndProfile:
            return "Friends see your \(noun) in their feed, and it's added to your profile grid."
        case .feedOnly:
            return "Friends see your \(noun) in their feed. It stays off your profile grid."
        case .offFeed:
            return "Your \(noun) stays out of friends' feeds and off your grid. It still counts toward your streak."
        }
    }

    /// Does a walk WITHOUT a photo get its route/stats card on the feed?
    var postsCard: Bool { self != .offFeed }

    /// The per-post grid choice sent with the card.
    var onProfile: Bool { self == .feedAndProfile }

    // MARK: - Default

    private static let storageKey = "walkAudienceDefaultV1"

    /// What the prompt opens on: the last choice the user asked to remember,
    /// else whatever the two existing settings already said, so nobody's
    /// standing choice silently changes when this screen arrives.
    static var storedDefault: WalkAudience {
        if let raw = UserDefaults.standard.string(forKey: storageKey),
           let remembered = WalkAudience(rawValue: raw) {
            return remembered
        }
        let prefs = NotificationPreferences.load()
        if !prefs.autoPostWithoutPhoto { return .offFeed }
        if !prefs.autoPostsOnProfile { return .feedOnly }
        return .feedAndProfile
    }

    /// Has the user picked a default themselves (prompt or Settings), rather
    /// than it being derived from the older switches?
    static var hasRememberedChoice: Bool {
        UserDefaults.standard.string(forKey: storageKey) != nil
    }

    /// Make `audience` the default for future walks. Also mirrors the
    /// photo-less half into `autoPostWithoutPhoto`, which `autoPostMile`'s
    /// other callers (the buddy recap) still read, and which Settings syncs to
    /// the server so the choice survives a reinstall.
    ///
    /// Deliberately does NOT touch `autoPostsOnProfile`: that switch is
    /// retroactive (it hides EVERY existing route card from the grid), and a
    /// choice about new walks must not rearrange a grid full of old ones.
    static func remember(_ audience: WalkAudience) {
        UserDefaults.standard.set(audience.rawValue, forKey: storageKey)
        var prefs = NotificationPreferences.load()
        let postsCard = audience.postsCard
        if prefs.autoPostWithoutPhoto != postsCard {
            prefs.autoPostWithoutPhoto = postsCard
            prefs.save()
        }
    }
}
