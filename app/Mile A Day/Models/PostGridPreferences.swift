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

/// Which FACE of a post a highlight kept.
///
/// A buddy walk is ONE shared card carrying several people's pictures plus the
/// route, so "keep this walk" is nearly always one of those faces and not the
/// whole carousel — and before this, a walk could be kept exactly once and
/// always played the author's photo, however many of the pictures on it were
/// yours.
///
/// The wire value is a bare string, deliberately open: `""` is the whole post
/// (what every earlier row and every older client means), `"map"` is the route
/// face, and anything else is a USER ID — the author's for the lead photo, a
/// credited participant's for theirs. An unknown value must therefore read as
/// "some person's slide" and fall back to the post's own photo, never as an
/// error.
enum HighlightSlideKey: Equatable, Hashable {
    case wholePost
    case map
    case person(String)

    static let mapWireValue = "map"

    init(wire: String?) {
        guard let wire, !wire.isEmpty else {
            self = .wholePost
            return
        }
        self = wire == HighlightSlideKey.mapWireValue ? .map : .person(wire)
    }

    var wireValue: String {
        switch self {
        case .wholePost: return ""
        case .map: return HighlightSlideKey.mapWireValue
        case .person(let userId): return userId
        }
    }
}

/// One member of a highlight: a post, and which face of it was kept.
///
/// The face is a KEY, not a resolved photo url, because the url for every face
/// is already on the post — the lead photo, a crew member's slide, the route —
/// and those are the fields the server's earn-to-view gate blanks. A
/// pre-resolved second copy would be a picture that gate doesn't know about.
struct PostHighlightItem: Codable, Identifiable {
    let post: PostItem
    let slideKey: HighlightSlideKey

    /// Post AND face: the same walk can legitimately be in a highlight twice
    /// under two faces, so the post id alone is not an identity here.
    var id: String { "\(post.post_id)#\(slideKey.wireValue)" }

    init(post: PostItem, slideKey: HighlightSlideKey) {
        self.post = post
        self.slideKey = slideKey
    }

    init(from decoder: Decoder) throws {
        post = try PostItem(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        slideKey = HighlightSlideKey(
            wire: try container.decodeIfPresent(String.self, forKey: .slide_key)
        )
    }

    func encode(to encoder: Encoder) throws {
        try post.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(slideKey.wireValue, forKey: .slide_key)
    }

    private enum CodingKeys: String, CodingKey { case slide_key }

    /// The picture this member shows: the crew member's own slide for a
    /// person face that isn't the author's, else the post's lead photo. The
    /// map face has no photo of its own and draws the route instead.
    var slideImageURL: URL? {
        if case .person(let userId) = slideKey, userId != post.user_id,
           let crew = post.acceptedCoauthors.first(where: { $0.user_id == userId }) {
            return crew.mediaURL
        }
        return post.storyPhotoURL ?? post.mediaURL
    }

    /// The words that belong under this face — the same rule the feed card
    /// follows, so a highlight can't caption a photo with somebody else's line.
    var slideCaption: (name: String, text: String)? {
        if case .person(let userId) = slideKey, userId != post.user_id {
            // Their picture carries THEIR words or NONE. Falling through to
            // the post's caption here would print the author's line under
            // somebody else's photo, which reads as that person having said
            // it — the same trap the feed card's `currentCaption` avoids.
            guard let crew = post.acceptedCoauthors.first(where: { $0.user_id == userId }),
                  let caption = crew.caption, !caption.isEmpty else { return nil }
            return (crew.displayName, caption)
        }
        guard let caption = post.caption, !caption.isEmpty else { return nil }
        return (post.displayName, caption)
    }
}

/// A highlight, opened — its members in the owner's chosen order.
struct PostHighlightDetail: Codable {
    let highlight_id: String
    let user_id: String
    let title: String
    let items: [PostHighlightItem]
}
