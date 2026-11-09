import SwiftUI

/// How a day was done: "1 mile OR 10,000 steps" (`ProgressCalculator`), so a
/// day can be done by either, or both. Every per-day surface (week charts,
/// monthly recap) reads this one type so a steps day never looks like a miss
/// on one screen and done on another.
enum DayDoneKind: Equatable {
    case none, mile, steps, both

    init(mile: Bool, steps: Bool) {
        switch (mile, steps) {
        case (true, true): self = .both
        case (true, false): self = .mile
        case (false, true): self = .steps
        default: self = .none
        }
    }

    var isDone: Bool { self != .none }
    var hasMile: Bool { self == .mile || self == .both }
    var hasSteps: Bool { self == .steps || self == .both }

    /// The same icons Home's "Today · either one counts" row uses.
    static let mileIcon = "figure.run"
    static let stepsIcon = "shoeprints.fill"

    /// One line for a day's detail panel; nil when not done.
    var explanation: String? {
        switch self {
        case .none: return nil
        case .mile: return "Done with a mile"
        case .steps: return "Done with 10,000+ steps"
        case .both: return "Done with a mile and 10,000+ steps"
        }
    }
}

/// The small marks above a done day: a runner for the mile, footprints for
/// 10k steps, both side by side when both happened. Draws nothing for `.none`.
struct DayDoneMark: View {
    let kind: DayDoneKind
    var size: CGFloat = 9
    var tint: Color = MADTheme.Colors.success

    var body: some View {
        HStack(spacing: 2) {
            if kind.hasMile {
                Image(systemName: DayDoneKind.mileIcon)
            }
            if kind.hasSteps {
                Image(systemName: DayDoneKind.stepsIcon)
            }
        }
        .madFont(size: size, weight: .bold, maxScale: 1.5)
        .foregroundColor(tint)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(kind.explanation ?? "")
        .accessibilityHidden(!kind.isDone)
    }
}

/// "Mile · 10k steps", shown under a chart only when a step day is in view,
/// so the footprints explain themselves the first time someone sees them.
struct DayDoneLegend: View {
    var body: some View {
        HStack(spacing: 10) {
            Label("Mile", systemImage: DayDoneKind.mileIcon)
            Label("10k steps", systemImage: DayDoneKind.stepsIcon)
            Text("either one counts")
                .foregroundColor(.white.opacity(0.45))
        }
        .labelStyle(DayDoneLegendLabelStyle())
        .madFont(size: 11, weight: .semibold, design: .rounded, maxScale: 1.3)
        .foregroundColor(.white.opacity(0.6))
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }
}

private struct DayDoneLegendLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon.foregroundColor(MADTheme.Colors.success)
            configuration.title
        }
    }
}
