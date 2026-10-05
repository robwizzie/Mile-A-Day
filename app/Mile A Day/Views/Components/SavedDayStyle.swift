import SwiftUI

// The covered-day model itself is `CoveredDate` in StreakFeatureService — the
// gated `streak_features.frozen_dates` already carried it, and the server
// already sends that payload for FRIEND stats fetches too, so nothing here
// needs a second field on the wire.

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

    /// The token's own name, no verb — for copy that already has one.
    static func tokenName(for kind: String) -> String {
        switch kind {
        case "double_down_recover": return "Double Down"
        case "streak_assist": return "Streak Assist"
        default: return "Streak Save"
        }
    }

    /// Who is holding this day up, in four words or fewer: "Saved by meghan",
    /// "Streak Save", "Double Down". The line every compact surface leads
    /// with — a friends row, a stat tile, a ring chip — because "covered" on
    /// its own prompts the question it is meant to answer.
    static func credit(for day: CoveredDate) -> String {
        if day.kind == "streak_assist", let name = day.source_username, !name.isEmpty {
            return "Saved by \(name)"
        }
        return tokenName(for: day.kind)
    }

    /// Headline for a day a token is carrying RIGHT NOW.
    ///
    /// Today is the case the app used to get most wrong: an Assist banked in
    /// the morning left the streak safe while every today-scoped surface —
    /// the goal ring, "1.00 mi to go", the friends row — still painted an
    /// untouched day, so the rescue looked like it had done nothing.
    static func todayHeadline(for day: CoveredDate) -> String {
        day.kind == "streak_assist" ? "Today's covered" : "Today's saved"
    }

    /// The sentence that makes the feature legible, and the one thing a
    /// covered day must never be allowed to imply: this is not a day off.
    /// Running the mile still counts, and the token comes back when you do —
    /// which is literally true now (the server refunds coverage the moment a
    /// covered day is earned for real).
    static func todayDetail(for day: CoveredDate, isSelf: Bool) -> String {
        if isSelf {
            switch day.kind {
            case "streak_assist":
                let who = day.source_username.flatMap { $0.isEmpty ? nil : "\($0)'s" } ?? "A friend's"
                return "\(who) mile is holding your streak. Run yours today and you'll both get it back."
            case "double_down_recover":
                return "Your Double Down is holding today. Run your mile and the token returns to you."
            default:
                return "Your Streak Save is holding today. Run your mile and the token returns to you."
            }
        }
        switch day.kind {
        case "streak_assist":
            if let name = day.source_username, !name.isEmpty {
                return "\(name) donated a mile, so their streak is safe today. If they run it themselves, the token goes back."
            }
            return "A friend donated a mile, so their streak is safe today."
        case "double_down_recover":
            return "A Double Down is holding today for them."
        default:
            return "A Streak Save is holding today for them."
        }
    }

    /// The saved-day marker for TODAY: a filled capsule, because it replaces
    /// a filled capsule ("0% TO GOAL") rather than annotating one.
    static func todayChip(for day: CoveredDate) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon(for: day.kind))
                .font(.system(size: 8, weight: .black))
            Text(day.kind == "streak_assist" ? "ASSIST HELD" : "SAVED TODAY")
                .font(.system(size: 9, weight: .black, design: .rounded))
                .tracking(0.6)
        }
        .foregroundColor(.black.opacity(0.88))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(tint))
        .overlay(Capsule().strokeBorder(Color.black.opacity(0.5), lineWidth: 1.5))
        .fixedSize()
    }

    /// Full sentence for a detail panel. `isSelf` changes the voice — on a
    /// friend's profile "You used a Streak Save" would be plainly wrong.
    static func explanation(for day: CoveredDate, isSelf: Bool) -> String {
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
struct CoveredDateIndex {
    private let byDate: [String: CoveredDate]

    init(_ days: [CoveredDate]?) {
        byDate = Dictionary(
            (days ?? []).map { ($0.local_date, $0) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    var isEmpty: Bool { byDate.isEmpty }

    subscript(dateKey: String) -> CoveredDate? { byDate[dateKey] }

    /// Convenience for views that hold `Date` rather than the API string.
    /// Formats in UTC to match the server's calendar-date semantics — the same
    /// trap that made Hall of Streaks render every date a day early.
    func day(for date: Date) -> CoveredDate? {
        byDate[Self.key(for: date)]
    }

    func contains(_ date: Date) -> Bool { day(for: date) != nil }

    /// Today, if a token is carrying it. Keyed on the DEVICE's local day —
    /// the owner's own payload carries `today_covered` resolved server-side
    /// and should be preferred where it exists; this is for the surfaces that
    /// only have the day list.
    var today: CoveredDate? { day(for: Date()) }

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

/// "Today's covered" — ONE construction, used wherever a day being held by a
/// token has to be explained rather than just marked.
///
/// The marker (a blue bar, a shield, a chip) answers "what is this?"; it does
/// not answer the two questions that actually confused people: *who paid for
/// this* and *what happens if I go run anyway*. Both belong in the same
/// place, on the screen where the user is looking at a streak that went up
/// beside a mile that didn't happen — so this carries the credit line and the
/// refund promise together, and every surface says it identically.
struct SavedTodayBanner: View {
    let day: CoveredDate
    /// Whose day it is. A friend's profile must not say "run yours today".
    var isSelf: Bool
    /// Opens the tokens explainer. Omitted on a friend's profile, where the
    /// viewer has nothing to act on.
    var onLearnMore: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(SavedDayStyle.tint.opacity(0.16))
                    .frame(width: 38, height: 38)
                Image(systemName: SavedDayStyle.icon(for: day.kind))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(SavedDayStyle.tint)
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(SavedDayStyle.todayHeadline(for: day))
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                    SavedDayStyle.chip(for: day.kind)
                }
                Text(SavedDayStyle.credit(for: day))
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(SavedDayStyle.tint)
                Text(SavedDayStyle.todayDetail(for: day, isSelf: isSelf))
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.62))
                    .fixedSize(horizontal: false, vertical: true)
                if onLearnMore != nil {
                    Text("How tokens work")
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .foregroundColor(SavedDayStyle.tint)
                        .padding(.top, 2)
                }
            }

            Spacer(minLength: 0)

            if onLearnMore != nil {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white.opacity(0.3))
                    .padding(.top, 3)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(SavedDayStyle.tint.opacity(0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(SavedDayStyle.tint.opacity(0.32), lineWidth: 1)
                )
        )
        .contentShape(Rectangle())
        // Only claim the taps when there is somewhere to send them — on a
        // friend's profile the viewer has nothing to act on here.
        .onTapGesture { if let onLearnMore { onLearnMore() } }
        .allowsHitTesting(onLearnMore != nil)
        .accessibilityElement(children: .combine)
    }
}
