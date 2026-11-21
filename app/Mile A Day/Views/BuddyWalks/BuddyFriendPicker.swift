import Foundation

/// How the buddy setup's friend list ("Who's coming?") is ordered.
///
/// The list used to be every buddy-capable friend in streak order, with no
/// search and nothing on a row but a name: the friend you walk with every
/// Tuesday sat beside one who installed the app once and never came back, and
/// a long list meant scrolling for a face. The server now sends who you've
/// walked with and how recently each friend was active
/// (`walks_together`, `active_days_ago`), and the app already knows who is
/// out or looking right now; this turns those into an order and one line of
/// "why them" per row.
enum BuddyPickerSort: String, CaseIterable, Identifiable {
    /// Out or looking now → walk partners → recently active → the rest.
    case best
    case walkedWith
    case active
    case name

    var id: String { rawValue }

    var title: String {
        switch self {
        case .best: return String(localized: "Best match")
        case .walkedWith: return String(localized: "Walked with most")
        case .active: return String(localized: "Recently active")
        case .name: return String(localized: "A–Z")
        }
    }

    static let storageKey = "buddyPickerSortV1"
}

/// One friend's row in the picker, with everything the order and the
/// status line need, computed once per render of the list.
struct BuddyPickerEntry: Identifiable {
    let candidate: BuddyCandidate
    let isLooking: Bool
    let isOut: Bool
    /// Walking or running right now, from `friendsOutNow`.
    let outVerb: String?

    var id: String { candidate.userId }
    var walks: Int { candidate.walksTogether ?? 0 }
    var isLive: Bool { isLooking || isOut }

    /// Past this they read as "quiet", and Best match lists them last, under
    /// their own label.
    static let quietAfterDays = 14

    /// Unknown (never, private, or an older server) counts as quiet only when
    /// nothing else speaks for them: a streak is activity the server already
    /// told us about.
    var isQuiet: Bool {
        if isLive || walks > 0 { return false }
        if let days = candidate.activeDaysAgo { return days > Self.quietAfterDays }
        return (candidate.currentStreak ?? 0) == 0
    }

    /// The one line under the name: the most useful true thing about them.
    var statusLine: String? {
        if isLooking { return String(localized: "Looking for a buddy right now") }
        if let outVerb { return String(localized: "Out \(outVerb) now") }
        if walks > 0 {
            let together = walks == 1
                ? String(localized: "1 walk together")
                : String(localized: "\(walks) walks together")
            if let active = activeText { return "\(together) · \(active)" }
            return together
        }
        if let active = activeText { return active }
        if let streak = candidate.currentStreak, streak > 0 {
            return String(localized: "\(streak)-day streak")
        }
        return nil
    }

    private var activeText: String? {
        guard let days = candidate.activeDaysAgo else { return nil }
        switch days {
        case 0: return String(localized: "Active today")
        case 1: return String(localized: "Active yesterday")
        case 2...Self.quietAfterDays: return String(localized: "Active \(days) days ago")
        default: return String(localized: "Quiet lately")
        }
    }

    /// Smaller = more recently active; unknown sorts after every known day.
    private var recency: Int { candidate.activeDaysAgo ?? 1_000 }

    // MARK: - Ordering

    @MainActor
    static func entries(
        _ candidates: [BuddyCandidate],
        buddy: BuddySessionService,
        search: String,
        sort: BuddyPickerSort
    ) -> [BuddyPickerEntry] {
        let looking = Set(buddy.lookingFriends.map(\.userId))
        let out = Dictionary(
            buddy.friendsOutNow.map { ($0.userId, $0.isRunning ? "running" : "walking") },
            uniquingKeysWith: { first, _ in first })
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let all = candidates
            .filter { query.isEmpty || matches($0, query) }
            .map {
                BuddyPickerEntry(
                    candidate: $0,
                    isLooking: looking.contains($0.userId),
                    isOut: out[$0.userId] != nil,
                    outVerb: out[$0.userId])
            }
        return all.sorted { lhs, rhs in ordered(lhs, rhs, by: sort) }
    }

    /// Name, last name or @username, ignoring case and accents, anywhere in
    /// the word ("mad" finds Maddy, "@mw" finds @mwalker).
    private static func matches(_ c: BuddyCandidate, _ query: String) -> Bool {
        let needle = query.hasPrefix("@") ? String(query.dropFirst()) : query
        guard !needle.isEmpty else { return true }
        let fields = [c.firstName, c.lastName, c.username, c.displayName]
            .compactMap { $0 }
        let full = [c.firstName, c.lastName].compactMap { $0 }.joined(separator: " ")
        return (fields + [full]).contains {
            $0.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }

    private static func ordered(
        _ a: BuddyPickerEntry, _ b: BuddyPickerEntry, by sort: BuddyPickerSort
    ) -> Bool {
        switch sort {
        case .best:
            if a.isQuiet != b.isQuiet { return !a.isQuiet }
            if a.isLive != b.isLive { return a.isLive }
            if a.walks != b.walks { return a.walks > b.walks }
            if a.recency != b.recency { return a.recency < b.recency }
        case .walkedWith:
            if a.walks != b.walks { return a.walks > b.walks }
            let aLast = a.candidate.lastWalkTogetherRaw ?? ""
            let bLast = b.candidate.lastWalkTogetherRaw ?? ""
            if aLast != bLast { return aLast > bLast }  // YYYY-MM-DD sorts as text
        case .active:
            if a.isLive != b.isLive { return a.isLive }
            if a.recency != b.recency { return a.recency < b.recency }
            let aStreak = a.candidate.currentStreak ?? 0
            let bStreak = b.candidate.currentStreak ?? 0
            if aStreak != bStreak { return aStreak > bStreak }
        case .name:
            break
        }
        let byName = a.candidate.displayName.localizedCaseInsensitiveCompare(b.candidate.displayName)
        if byName != .orderedSame { return byName == .orderedAscending }
        return a.candidate.userId < b.candidate.userId
    }
}
