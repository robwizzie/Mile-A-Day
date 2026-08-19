import Foundation
import SwiftUI

/// How a profile's Posts grid is ordered.
///
/// Both values are a walk of the same `created_at` index in opposite
/// directions, which is what lets either one paginate correctly. A sort that
/// isn't a date walk (most-hyped, longest) can't be keyset-paginated on the
/// cursor the grid already sends, so it isn't offered rather than offered and
/// quietly wrong on page two.
enum PostGridSort: String, CaseIterable, Identifiable, Codable {
    case newest
    case oldest

    var id: String { rawValue }

    var title: String {
        switch self {
        case .newest: return "Newest first"
        case .oldest: return "Oldest first"
        }
    }

    var icon: String {
        switch self {
        case .newest: return "arrow.down"
        case .oldest: return "arrow.up"
        }
    }
}

/// What the grid is narrowed to.
///
/// There used to be a photos/route-cards split here as well. It was a filter
/// nobody asked a grid of their own runs: both are just your posts, the tile
/// already looks like what it is, and splitting them mostly answered "which
/// days did I skip the photo prompt" — which is a question about the prompt,
/// not about the walk. The server still honours `photos` and `auto` for the
/// builds that shipped with them; this is only what we offer now.
///
/// A preference persisted as one of the retired values decodes to nil and
/// falls back to `.all`, so a grid that was left filtered comes back whole.
enum PostGridFilter: String, CaseIterable, Identifiable, Codable {
    case all
    case collabs

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "Everything"
        case .collabs: return "With friends"
        }
    }

    var icon: String {
        switch self {
        case .all: return "square.grid.3x3"
        case .collabs: return "person.2"
        }
    }
}

/// How many thumbnails fit across the grid.
///
/// Not a cosmetic toggle: at three across a walk photo is a 120pt tile you
/// scan, at two it's something you actually look at, and a run log is read
/// both ways at different times. Persisted because it's a way of using the
/// screen, not a per-visit decision.
enum PostGridLayout: String, CaseIterable, Identifiable, Codable {
    case compact
    case large

    var id: String { rawValue }

    var columns: Int {
        switch self {
        case .compact: return 3
        case .large: return 2
        }
    }

    var title: String {
        switch self {
        case .compact: return "Compact"
        case .large: return "Large"
        }
    }

    var icon: String {
        switch self {
        case .compact: return "square.grid.3x3.fill"
        case .large: return "square.grid.2x2.fill"
        }
    }
}

/// The user's own grid setup, remembered across launches.
///
/// Only ever applied to the OWNER's grid. A visitor's copy of someone else's
/// profile uses the defaults: how you like to read your own history is not a
/// statement about how their history should be laid out, and a sticky filter
/// silently applied to every profile you open looks like their grid is empty.
enum PostGridPreferences {
    static let sortKey = "postGridSortV1"
    static let filterKey = "postGridFilterV1"
    static let layoutKey = "postGridLayoutV1"

    /// Mirrors the server's POST_PIN_LIMIT. The server is authoritative and
    /// answers 409 past it; this is only so the UI can say "3" out loud and
    /// grey the action before the round trip.
    static let pinLimit = 3

    static var sort: PostGridSort {
        get { PostGridSort(rawValue: UserDefaults.standard.string(forKey: sortKey) ?? "") ?? .newest }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: sortKey) }
    }

    static var filter: PostGridFilter {
        get { PostGridFilter(rawValue: UserDefaults.standard.string(forKey: filterKey) ?? "") ?? .all }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: filterKey) }
    }

    static var layout: PostGridLayout {
        get { PostGridLayout(rawValue: UserDefaults.standard.string(forKey: layoutKey) ?? "") ?? .compact }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: layoutKey) }
    }
}

/// What the composer does with a run's route map, remembered between posts.
///
/// The per-post toggle in the share step is unchanged and always wins — this
/// only decides where that toggle STARTS. `.ask` is the shipped behaviour
/// (on, and you turn it off if you don't want it); `.never` is for the people
/// whose walks all start at their front door, who were otherwise re-making the
/// same decision every single day and only had to forget once.
enum RouteSharingDefault: String, CaseIterable, Identifiable, Codable {
    case always
    case ask
    case never

    var id: String { rawValue }

    var title: String {
        switch self {
        case .always: return "Always include"
        case .ask: return "Ask each time"
        case .never: return "Never include"
        }
    }

    var subtitle: String {
        switch self {
        case .always: return "New posts start with the map on"
        case .ask: return "The map starts on and you can turn it off"
        case .never: return "New posts start with the map off"
        }
    }

    /// What the composer's `includeRoute` toggle opens at.
    var initialIncludeRoute: Bool { self != .never }

    static let key = "routeSharingDefaultV1"

    static var current: RouteSharingDefault {
        get { RouteSharingDefault(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .ask }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: key) }
    }
}

// MARK: - Story Highlights

/// One circle on the profile rail: a named, permanent collection of the
/// owner's own posts.
///
/// The point is the expiry. A story is the only thing here that disappears,
/// which is exactly why nobody bothers making a good one — putting it in a
/// highlight is what makes it keepable. Nothing is copied: the server holds an
/// ordered list of post ids and re-resolves them on every read, so a post that
/// is later deleted or made private simply leaves the highlight.
struct PostHighlight: Codable, Identifiable, Equatable {
    let highlight_id: String
    let user_id: String
    var title: String
    var cover_post_id: String?
    /// A cover picked from the camera roll rather than from the posts inside.
    /// Optional because an older server doesn't send it at all — nil there
    /// means "this server has no custom covers", not "no custom cover set",
    /// and either way `cover_media_url` is what gets drawn.
    var cover_image_url: String?
    /// The resolved cover photo — the uploaded cover if there is one, else the
    /// chosen member post, else the first member, so a highlight always has a
    /// face even after its cover is deleted.
    var cover_media_url: String?
    var item_count: Int
    var sort_index: Int?

    var id: String { highlight_id }

    var coverURL: URL? {
        guard let cover_media_url, !cover_media_url.isEmpty else { return nil }
        return ProfileImageService.fullImageURL(for: cover_media_url)
    }

    /// Is the circle a photo the owner chose, rather than one of the posts?
    var hasCustomCover: Bool { cover_image_url?.isEmpty == false }
}

/// A highlight, opened — its members in the owner's chosen order.
struct PostHighlightDetail: Codable {
    let highlight_id: String
    let user_id: String
    let title: String
    let items: [PostItem]
}
