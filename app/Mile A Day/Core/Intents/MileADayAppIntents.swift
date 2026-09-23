import AppIntents
import SwiftUI

// Siri / Shortcuts / Spotlight / Action Button entry points.
//
// `StartMileIntent` itself lives in Shared/WidgetDataStore.swift because the
// Control Center control in the widget extension runs it too; everything in
// this file is app-only.

// MARK: - How far today?

/// Today's progress as the widgets last saw it — the App Group snapshot the
/// app writes on every HealthKit refresh. Read-only and never a HealthKit
/// query: this answers without opening the app, and a stale day is SAID, not
/// reported as zero.
struct TodayMileSummary {
    let isFresh: Bool
    let miles: Double
    let goal: Double
    let streak: Int

    static func current() -> TodayMileSummary {
        let progress = WidgetDataStore.load()
        return TodayMileSummary(
            isFresh: WidgetDataStore.hasProgressForToday(),
            miles: max(progress.miles, 0),
            goal: progress.goal > 0 ? progress.goal : 1,
            streak: max(WidgetDataStore.loadStreak(), 0)
        )
    }

    /// Scoring rule, not the tracker's celebration rule: the server counts a
    /// day at 95% of the goal (`ProgressCalculator.isGoalCompleted`).
    var isDone: Bool { ProgressCalculator.isGoalCompleted(current: miles, goal: goal) }

    var fraction: Double { min(max(miles / goal, 0), 1) }

    private var unit: DisplayDistanceUnit { DistanceUnits.current }

    /// "1 mile" / "2 miles" / "1.61 kilometers" — the goal, in words.
    var goalText: String {
        let value = goal.inDisplayUnit
        let isWhole = abs(value - value.rounded()) < 0.005
        let number = isWhole ? String(Int(value.rounded())) : String(format: "%.2f", value)
        return "\(number) \(isWhole && Int(value.rounded()) == 1 ? unit.singular : unit.plural)"
    }

    /// Ceiled in the display unit — never promise the goal is closer than it is.
    var remainingText: String {
        "\(max(goal - miles, 0).distanceToGoText) \(unit.plural)"
    }

    var streakSentence: String {
        switch streak {
        case 0: return "No streak running yet — today can start one."
        case 1: return "Your streak is 1 day."
        default: return "Your streak is \(streak) days."
        }
    }

    /// The spoken / displayed answer.
    var sentence: String {
        guard isFresh else {
            return "Mile A Day hasn't updated today's progress yet. Open Mile A Day to refresh."
        }
        if isDone {
            return "You've done it today: \(miles.distanceText) of \(goalText). \(streakSentence)"
        }
        return "You're at \(miles.distanceText) of \(goalText) today — \(remainingText) to go. \(streakSentence)"
    }
}

struct HowFarTodayIntent: AppIntent {
    static var title: LocalizedStringResource { "How Far Today" }

    static var description: IntentDescription {
        IntentDescription(
            "Tells you today's distance against your daily goal, how much is left, and your current streak, without opening the app."
        )
    }

    static var openAppWhenRun: Bool { false }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let summary = TodayMileSummary.current()
        return .result(
            dialog: IntentDialog(stringLiteral: summary.sentence),
            view: TodayMileSnippetView(summary: summary)
        )
    }
}

/// The visual half of the answer: the goal ring plus the three numbers.
struct TodayMileSnippetView: View {
    let summary: TodayMileSummary

    private let red = Color(red: 0.85, green: 0.25, blue: 0.35)
    private let green = Color(red: 0.30, green: 0.85, blue: 0.45)
    private let orange = Color(red: 1.0, green: 0.55, blue: 0.2)

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .stroke(Color.primary.opacity(0.12), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: summary.isFresh ? summary.fraction : 0)
                    .stroke(summary.isDone ? green : red,
                            style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: summary.isDone ? "checkmark" : "figure.walk")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(summary.isDone ? green : .primary)
                    .accessibilityHidden(true)
            }
            .frame(width: 58, height: 58)

            VStack(alignment: .leading, spacing: 4) {
                if summary.isFresh {
                    Text("\(summary.miles.distanceText) / \(summary.goalText)")
                        .font(.system(.title3, design: .rounded).weight(.bold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(summary.isDone ? "Goal done today" : "\(summary.remainingText) to go")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(summary.isDone ? green : .secondary)
                        .lineLimit(1)
                } else {
                    Text("Open Mile A Day to refresh")
                        .font(.system(.headline, design: .rounded))
                        .lineLimit(2)
                }
                if summary.isFresh, summary.streak > 0 {
                    Label("\(summary.streak)-day streak", systemImage: "flame.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(orange)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding()
    }
}

// MARK: - App Shortcuts

struct MileADayShortcuts: AppShortcutsProvider {
    @AppShortcutsBuilder
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartMileIntent(),
            phrases: [
                "Start my mile in \(.applicationName)",
                "Start my mile with \(.applicationName)",
                "Track my mile with \(.applicationName)",
                "Log my mile with \(.applicationName)",
                "Start a \(\.$activity) in \(.applicationName)"
            ],
            shortTitle: "Start My Mile",
            systemImageName: "figure.walk"
        )
        AppShortcut(
            intent: HowFarTodayIntent(),
            phrases: [
                "How far have I walked today in \(.applicationName)",
                "How far today in \(.applicationName)",
                "How close am I to my mile in \(.applicationName)",
                "Check my mile in \(.applicationName)"
            ],
            shortTitle: "How Far Today",
            systemImageName: "flag.checkered"
        )
    }

    static var shortcutTileColor: ShortcutTileColor { .red }
}
