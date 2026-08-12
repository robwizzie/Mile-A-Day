import Foundation

/// Your competition win/loss record, as computed server-side.
///
/// Separate structs rather than fields on `Competition`: that type has an
/// explicit `CodingKeys` enum AND a hand-written `init(from:)`, so adding a
/// stored property silently breaks decoding of everything after it.
///
/// `end_date` / `last_competed_on` are backend `date` columns, which serialize
/// as plain "YYYY-MM-DD" — safe as `String`. Nothing here is a `timestamptz`;
/// those carry fractional seconds that `APIClient`'s `.iso8601` decoder cannot
/// parse, and one unparseable date fails the whole payload.
struct CompetitionRecord: Codable {
    let record: Tally
    let win_rate: Double
    let current_win_streak: Int
    let best_win_streak: Int
    let by_type: [ModeTally]
    let rivals: [Rival]
    let recent: [RecentResult]
    /// The user has more finished competitions than the endpoint walks.
    let truncated: Bool

    struct Tally: Codable {
        let wins: Int
        let losses: Int
        let total: Int
        let podiums: Int
        /// How many of `total` carry a placement at all. `placement` was added
        /// after launch, so older resolved competitions have none — they still
        /// count as wins/losses but can't contribute a podium.
        let podiums_known_of: Int
    }

    struct ModeTally: Codable, Identifiable {
        let type: CompetitionType
        let wins: Int
        let losses: Int
        let total: Int

        var id: String { type.rawValue }
    }

    struct Rival: Codable, Identifiable {
        let user_id: String
        let username: String?
        let first_name: String?
        let profile_image_url: String?
        /// Competitions we both finished where I placed first.
        let wins: Int
        /// ...where they did.
        let losses: Int
        /// Every finished competition we were both in. One a third party won
        /// counts here and in neither `wins` nor `losses`.
        let meetings: Int
        let last_competed_on: String?

        var id: String { user_id }

        var displayName: String {
            if let username, !username.isEmpty { return username }
            if let first_name, !first_name.isEmpty { return first_name }
            return "Someone"
        }

        /// "3–1" against this person.
        var recordText: String { "\(wins)–\(losses)" }
    }

    struct RecentResult: Codable, Identifiable {
        let competition_id: String
        let competition_name: String
        let type: CompetitionType
        let end_date: String?
        let placement: Int?
        let participant_count: Int
        let winner_user_id: String?
        let won: Bool

        var id: String { competition_id }
    }

    /// Whether the podium count covers the whole record. When false the UI
    /// should say what it's counting rather than imply a low number is the
    /// full story.
    var podiumsCoverEverything: Bool {
        record.podiums_known_of >= record.total
    }

    /// Modes the user has actually finished something in.
    var playedModes: [ModeTally] { by_type.filter { $0.total > 0 } }
}
