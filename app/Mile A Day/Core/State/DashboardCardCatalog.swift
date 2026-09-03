import Foundation
import Observation

/// Everything on the dashboard BELOW the day's cards (hero, start, steps and
/// medals stay put) is one of these: switchable on or off, and draggable
/// into any order. Each style has its own list and its own defaults, so a
/// user who never opens "Customize" sees exactly what shipped for that
/// style.
enum DashboardCard: String, CaseIterable, Identifiable {
    case dailyChallenge
    case streakTokens
    case friendActivity
    case treats
    case weekChart
    case recentWorkouts
    case competitions
    case weeklyChallenge
    case streakHistory
    case routeMap

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dailyChallenge: return "Daily challenge"
        case .streakTokens: return "Streak Tokens"
        case .friendActivity: return "Friends' activity"
        case .treats: return CalorieTreat.featureName
        case .weekChart: return "This week's miles"
        case .recentWorkouts: return "Recent workouts"
        case .competitions: return "Your competitions"
        case .weeklyChallenge: return "Weekly challenge"
        case .streakHistory: return "Hall of Streaks"
        case .routeMap: return "Your routes"
        }
    }

    var subtitle: String {
        switch self {
        case .dailyChallenge:
            return "Today's challenge and how you're doing on it."
        case .streakTokens:
            return "Double Down, Streak Save and Assist — how close each one is."
        case .friendActivity:
            return "Who's been out today, and a hype button for each."
        case .treats:
            return "What your miles' calories are worth in wine, burgers or lattes — and Flamey enjoying them for you. Always in Insights too."
        case .weekChart:
            return "The week's miles as bars, straight from Insights."
        case .recentWorkouts:
            return "Your last three walks and runs, one tap from the full list."
        case .competitions:
            return "Every competition you're in, with what it needs from you today."
        case .weeklyChallenge:
            return "This week's challenge and how far along you are."
        case .streakHistory:
            return "Your best streaks ever, from the profile's Hall of Streaks."
        case .routeMap:
            return "Every walk and run you've mapped, on one map."
        }
    }

    var icon: String {
        switch self {
        case .dailyChallenge: return "target"
        case .streakTokens: return "shield.lefthalf.filled"
        case .friendActivity: return "person.2.fill"
        case .treats: return "fork.knife"
        case .weekChart: return "chart.bar.fill"
        case .recentWorkouts: return "figure.walk"
        case .competitions: return "trophy.fill"
        case .weeklyChallenge: return "calendar.badge.checkmark"
        case .streakHistory: return "crown.fill"
        case .routeMap: return "map.fill"
        }
    }

    /// What each style ships with, in order — exactly the cards it showed
    /// before any of this was movable.
    static func defaults(for style: DashboardStyle) -> [DashboardCard] {
        switch style {
        case .fun: return [.streakTokens, .dailyChallenge, .friendActivity]
        case .modern: return [.dailyChallenge]
        }
    }
}

/// Per-style ordered lists, each ONE comma-joined `@AppStorage` string whose
/// ORDER is the dashboard's order — switching a card on appends it,
/// dragging rewrites it, and every view reading the key re-renders on the
/// spot. An EMPTY string means "never customised" and reads as the style's
/// defaults; a user who removed everything is stored as `-`, so their empty
/// dashboard stays empty. Unknown ids — a retired card — drop on read.
enum DashboardCards {
    static let funKey = "dashboardCardsFunV1"
    static let modernKey = "dashboardCardsModernV1"
    static let emptyMarker = "-"

    static func key(for style: DashboardStyle) -> String {
        style == .fun ? funKey : modernKey
    }

    /// The cards on the dashboard, in the user's order.
    static func ordered(in raw: String, for style: DashboardStyle) -> [DashboardCard] {
        if raw.isEmpty { return DashboardCard.defaults(for: style) }
        if raw == emptyMarker { return [] }
        var seen = Set<DashboardCard>()
        return raw.split(separator: ",")
            .compactMap { DashboardCard(rawValue: String($0)) }
            .filter { seen.insert($0).inserted }
    }

    static func raw(_ cards: [DashboardCard]) -> String {
        cards.isEmpty ? emptyMarker : cards.map(\.rawValue).joined(separator: ",")
    }

    static func isOn(_ card: DashboardCard, in raw: String, for style: DashboardStyle) -> Bool {
        ordered(in: raw, for: style).contains(card)
    }

    /// The cards NOT on the dashboard, in catalogue order.
    static func off(in raw: String, for style: DashboardStyle) -> [DashboardCard] {
        let on = Set(ordered(in: raw, for: style))
        return DashboardCard.allCases.filter { !on.contains($0) }
    }

    /// On ⇒ appended to the end (a new card lands last, where the user can
    /// see it appear and drag it up); off ⇒ removed, the rest keep their order.
    static func toggling(_ card: DashboardCard, on: Bool, in raw: String, for style: DashboardStyle) -> String {
        var cards = ordered(in: raw, for: style)
        cards.removeAll { $0 == card }
        if on { cards.append(card) }
        return self.raw(cards)
    }

    static func moving(fromOffsets source: IndexSet, toOffset destination: Int,
                       in raw: String, for style: DashboardStyle) -> String {
        var cards = ordered(in: raw, for: style)
        cards.move(fromOffsets: source, toOffset: destination)
        return self.raw(cards)
    }
}

/// Whether the Customize sheet is up — shared so the dashboard can keep the
/// row that presents it in view when a style switch reflows the page under
/// the sheet.
@MainActor
@Observable
final class DashboardCustomizeState {
    static let shared = DashboardCustomizeState()
    var isPresented = false
}
