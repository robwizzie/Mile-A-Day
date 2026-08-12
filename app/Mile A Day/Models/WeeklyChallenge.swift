import Foundation

/// This week's challenge, the user's progress, and their friends' standings.
///
/// `week_start` / `week_end` are backend `date` columns, so plain "YYYY-MM-DD"
/// strings. `completed_at` is a `timestamptz`, which serializes WITH fractional
/// seconds — `APIClient`'s `.iso8601` decoder cannot parse those and one bad
/// date fails the entire payload, so it stays a `String` and is parsed on
/// demand.
struct WeeklyChallengeResponse: Codable {
    let week_start: String
    let week_end: String
    let days_left: Int
    let challenge: Challenge
    /// Scaled to this user and frozen when the week was first served.
    let target: Double
    /// What the target was scaled from — their own recent average. Nil when
    /// they had too little history and got the catalog's base target.
    let baseline: Double?
    let progress: Progress
    let streak: Streak
    let friends: [LeaderboardEntry]
    let my_rank: Int?
    let next_challenge: NextChallenge?

    struct Challenge: Codable {
        let challenge_key: String
        let title: String
        /// Already rendered with this user's target substituted in.
        let description: String
        let icon: String
        let gradient_start: String
        let gradient_end: String
        let metric: String
        let unit: String
    }

    struct Progress: Codable {
        let value: Double
        /// 0...1, already clamped server-side.
        let percent: Double
        let completed: Bool
        let completed_at: String?
    }

    struct Streak: Codable {
        let current_weeks: Int
        let best_weeks: Int
    }

    struct LeaderboardEntry: Codable, Identifiable {
        let user_id: String
        let username: String?
        let first_name: String?
        let profile_image_url: String?
        let value: Double
        /// Their own target, which differs from yours — the board ranks on
        /// `percent` for exactly this reason, so never render one person's
        /// value against another's target.
        let target: Double
        let percent: Double
        let completed: Bool
        let rank: Int
        let is_me: Bool

        var id: String { user_id }

        var displayName: String {
            if is_me { return "You" }
            if let username, !username.isEmpty { return username }
            if let first_name, !first_name.isEmpty { return first_name }
            return "Someone"
        }
    }

    struct NextChallenge: Codable {
        let title: String
        let icon: String
        /// The target is deliberately absent — next week's isn't frozen yet and
        /// would move if we scaled it now.
        let description: String
    }
}

struct WeeklyChallengeHistoryResponse: Codable {
    let history: [Item]

    struct Item: Codable, Identifiable {
        let week_start: String
        let challenge_key: String
        let title: String
        let icon: String
        let gradient_start: String
        let gradient_end: String
        let unit: String
        /// The target this user was actually set that week, not what the
        /// formula would produce today.
        let target: Double
        let final_value: Double?
        let completed: Bool

        var id: String { week_start }
    }
}

/// Number formatting shared by every weekly-challenge surface, so the hero, the
/// leaderboard and the history can't disagree about the same value.
enum WeeklyChallengeFormat {
    /// Steps and minutes read as whole numbers with separators; distances get
    /// one decimal. Driven by the unit because the metric's own step size isn't
    /// sent to the client.
    static func value(_ value: Double, unit: String) -> String {
        switch unit {
        case "steps", "minutes":
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 0
            return formatter.string(from: NSNumber(value: value)) ?? "\(Int(value))"
        case "days", "runs":
            return String(Int(value.rounded()))
        default:
            return String(format: "%.1f", value)
        }
    }

    static func valueWithUnit(_ value: Double, unit: String) -> String {
        "\(self.value(value, unit: unit)) \(unit)"
    }

    /// "3 days left" / "Last day" / "Week over".
    static func daysLeft(_ days: Int) -> String {
        switch days {
        case ..<0: return "Week over"
        case 0: return "Week over"
        case 1: return "Last day"
        default: return "\(days) days left"
        }
    }

    /// "Aug 4" from a "YYYY-MM-DD" date column.
    static func shortDate(_ ymd: String) -> String {
        let parser = DateFormatter()
        parser.dateFormat = "yyyy-MM-dd"
        parser.calendar = Calendar(identifier: .gregorian)
        parser.locale = Locale(identifier: "en_US_POSIX")
        guard let date = parser.date(from: ymd) else { return ymd }

        let out = DateFormatter()
        out.dateFormat = "MMM d"
        out.locale = Locale.current
        return out.string(from: date)
    }
}
