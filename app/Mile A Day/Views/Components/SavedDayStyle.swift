import SwiftUI

/// A day a streak token carried, as the API reports it.
///
/// Decoded from the additive `covered_days` on `/stats` and `/streak-eras`.
/// Absent for the overwhelming majority of users and on older servers, so
/// every field is read through optionals and an empty list is the norm.
struct CoveredDay: Codable, Equatable, Hashable {
    let local_date: String  // YYYY-MM-DD
    let kind: String
    let source_username: String?
}

/// ONE visual language for "this day was saved, not missed".
///
/// The problem this exists to end: every per-day surface paints from raw
/// mileage, so a token-covered day looked exactly like a plain miss — an
/// orange 0.57 mi bar — while the streak quietly counted it. The user then
/// sees a Save Streak offer referencing a run they can see was broken, and
/// concludes the app is wrong. A saved day has to LOOK saved everywhere it
/// appears, in the same way, or the confusion just moves to a different screen.
///
/// Blue is deliberate: green/orange/red are already taken by done / short /
/// today, so a fourth state needs its own hue rather than a shade of an
/// existing one.
enum SavedDayStyle {
    static let tint = Color(red: 0.36, green: 0.66, blue: 0.98)

    /// SF Symbol for the token that carried the day.
    static func icon(for kind: String) -> String {
        switch kind {
        case "streak_save": return "shield.fill"
        case "double_down_recover": return "flame.fill"
        case "streak_assist": return "hands.clap.fill"
        default: return "shield.fill"
        }
    }

    /// Short label for a chip: "Saved", "Double Down", "Assist".
    static func shortLabel(for kind: String) -> String {
        switch kind {
        case "double_down_recover": return "Double Down"
        case "streak_assist": return "Assist"
        default: return "Saved"
        }
    }

    /// Full sentence for a detail panel. `isSelf` changes the voice — on a
    /// friend's profile "You used a Streak Save" would be plainly wrong.
    static func explanation(for day: CoveredDay, isSelf: Bool) -> String {
        let subject = isSelf ? "You" : "They"
        switch day.kind {
        case "double_down_recover":
            return "\(subject) covered this day with a Double Down — an extra mile on another day paid for it."
        case "streak_assist":
            if let name = day.source_username, !name.isEmpty {
                return "\(name) saved this day with a Streak Assist."
            }
            return "A friend saved this day with a Streak Assist."
        default:
            return "\(subject) used a Streak Save on this day."
        }
    }

    /// "2026-07-31" → "Jul 31, 2026".
    ///
    /// UTC on BOTH formatters, deliberately. `local_date` is a calendar date
    /// the server already resolved in the user's timezone; printing it with a
    /// device-timezone formatter rewinds UTC midnight into the previous
    /// evening and shows every date a day early west of Greenwich. That exact
    /// bug shipped in Hall of Streaks.
    static func formatDate(_ ymd: String) -> String {
        guard let date = parseFormat.date(from: ymd) else { return ymd }
        return displayFormat.string(from: date)
    }

    private static let parseFormat: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = TimeZone(identifier: "UTC")
        return fmt
    }()

    private static let displayFormat: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d, yyyy"
        fmt.timeZone = TimeZone(identifier: "UTC")
        return fmt
    }()

    /// Compact chip for day rows and era rows.
    static func chip(for kind: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon(for: kind))
                .font(.system(size: 8, weight: .bold))
            Text(shortLabel(for: kind).uppercased())
                .font(.system(size: 9, weight: .black, design: .rounded))
                .tracking(0.6)
        }
        .foregroundColor(tint)
        .fixedSize()
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Capsule().fill(tint.opacity(0.16)))
    }
}

/// Lookup keyed by YYYY-MM-DD, so a view can ask "was this day saved?" without
/// re-scanning an array per row.
struct CoveredDayIndex {
    private let byDate: [String: CoveredDay]

    init(_ days: [CoveredDay]?) {
        byDate = Dictionary(
            (days ?? []).map { ($0.local_date, $0) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    var isEmpty: Bool { byDate.isEmpty }

    subscript(dateKey: String) -> CoveredDay? { byDate[dateKey] }

    /// Convenience for views that hold `Date` rather than the API string.
    /// Formats in UTC to match the server's calendar-date semantics — the same
    /// trap that made Hall of Streaks render every date a day early.
    func day(for date: Date) -> CoveredDay? {
        byDate[Self.key(for: date)]
    }

    func contains(_ date: Date) -> Bool { day(for: date) != nil }

    /// Any saved day inside an inclusive YYYY-MM-DD range.
    func countInRange(start: String, end: String) -> Int {
        byDate.keys.filter { $0 >= start && $0 <= end }.count
    }

    /// A `Date` from a per-day chart is a LOCAL start-of-day, so it must be
    /// keyed with the local calendar — unlike the API strings, which are
    /// already calendar dates.
    static func key(for date: Date) -> String {
        Self.localKeyFormat.string(from: date)
    }

    private static let localKeyFormat: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.locale = Locale(identifier: "en_US_POSIX")
        return fmt
    }()
}
