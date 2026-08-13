import Foundation

/// A one-tap competition configuration.
///
/// The full create form asks nine questions before you can start anything —
/// name, friends, type, activities, goal, interval, end mode, first-to,
/// duration — which is a lot of decisions about a game you haven't played yet.
/// A preset answers all of them except "who", so the quick-start path is
/// preset → friend picker → Create.
///
/// Every field maps 1:1 onto a `@State` in `CreateCompetitionView`; applying a
/// preset is a straight assignment, never a parallel code path. The full form
/// stays reachable behind "Customize" so nothing here is a dead end.
struct CompetitionPreset: Identifiable, Hashable {
    let id: String
    /// Shown on the preset card. Deliberately a *name*, not a description of
    /// the mode — "Week of Miles" reads as a thing you can start, where
    /// "Apex, 7 days" reads as a form you have to fill in.
    let title: String
    /// One line under the title: what actually happens.
    let blurb: String
    let systemImage: String

    let type: CompetitionType
    let goal: Double
    let unit: CompetitionUnit
    let interval: CompetitionInterval
    let activities: Set<CompetitionActivity>
    /// Point target for clash / targets, and — see below — the LIVES count for
    /// streaks.
    let firstTo: Int
    /// Only meaningful for the types where `needsDuration` is true (apex, and
    /// targets when not ending on a point target). Nil elsewhere.
    let durationHours: Int?
    /// Targets only: end on a point target rather than a fixed duration.
    let targetsUseFirstTo: Bool

    static let all: [CompetitionPreset] = [
        CompetitionPreset(
            id: "week_of_miles",
            title: "Week of Miles",
            blurb: "Seven days. Most miles wins.",
            systemImage: "arrow.up.circle.fill",
            type: .apex,
            goal: 0,
            unit: .miles,
            interval: .day,
            activities: [.run, .walk],
            firstTo: 0,
            durationHours: 168,
            targetsUseFirstTo: false
        ),
        CompetitionPreset(
            id: "daily_duel",
            title: "Daily Duel",
            blurb: "Go furthest each day. First to 5 wins.",
            systemImage: "bolt.fill",
            type: .clash,
            goal: 0,
            unit: .miles,
            interval: .day,
            activities: [.run, .walk],
            firstTo: 5,
            durationHours: nil,
            targetsUseFirstTo: false
        ),
        CompetitionPreset(
            id: "streak_standoff",
            title: "Streak Standoff",
            blurb: "A mile a day, three lives each.",
            systemImage: "flame.fill",
            type: .streaks,
            goal: 1.0,
            unit: .miles,
            interval: .day,
            activities: [.run, .walk],
            // Streak LIVES, not a point target — createCompetition sends
            // `lives: isStreaks ? firstTo : nil`, so leaving this at 0 would
            // create a competition nobody survives their first missed day in.
            firstTo: 3,
            durationHours: nil,
            targetsUseFirstTo: false
        ),
        CompetitionPreset(
            id: "race_to_20",
            title: "Race to 20",
            blurb: "First to 20 miles takes it.",
            systemImage: "flag.fill",
            type: .race,
            goal: 20.0,
            unit: .miles,
            interval: .day,
            activities: [.run, .walk],
            firstTo: 0,
            durationHours: nil,
            targetsUseFirstTo: false
        )
    ]

    /// Gradient hexes come from the mode, so a preset always reads as the mode
    /// it starts — no second palette to keep in sync.
    var gradient: [String] { type.gradient }
}
