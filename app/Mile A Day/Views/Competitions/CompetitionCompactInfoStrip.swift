import SwiftUI

/// The masthead under the competition's title: what kind of competition this
/// is, what counts, and how long is left.
///
/// Was a horizontally SCROLLING rail of five or six outlined colour capsules —
/// status, type, each activity, interval, countdown — each with its own tint
/// and its own border. Six bordered colours in a row is the single most dated
/// thing on the screen, and putting facts that never change behind a sideways
/// scroll means some of them are simply never read.
///
/// Now one typographic line: a status dot, the facts separated by middots, and
/// the ONE number that moves (time remaining) given emphasis on the right.
struct CompetitionCompactInfoStrip: View {
    let competition: Competition

    private var accent: Color { CompeteDesign.accent(competition.type) }

    /// The unchanging facts, in reading order. Joined rather than stacked: a
    /// competition's format is one sentence, not six badges.
    private var facts: [String] {
        var parts = [competition.type.displayName]
        parts.append(competition.workouts.map { $0.displayName }.joined(separator: " + "))
        if let interval = competition.options.interval {
            parts.append(interval.displayName)
        }
        return parts
    }

    var body: some View {
        HStack(alignment: .center, spacing: 9) {
            Circle()
                .fill(competition.status.color)
                .frame(width: 7, height: 7)
                .accessibilityHidden(true)

            Text(competition.status.displayName.uppercased())
                .font(.system(size: 10, weight: .heavy, design: .rounded))
                .tracking(1.1)
                .foregroundColor(competition.status.color)
                .lineLimit(1)
                .fixedSize()

            Rectangle()
                .fill(CompeteDesign.rowRule)
                .frame(width: 1, height: 11)
                .accessibilityHidden(true)

            // The format. Allowed to shrink and truncate — it is reference,
            // and the countdown beside it is not.
            Text(facts.joined(separator: " · "))
                .font(CompeteDesign.detail)
                .foregroundColor(CompeteDesign.inkMuted)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let remaining = remainingTimeString {
                Text(remaining)
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundColor(accent)
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: CompeteDesign.innerRadius, style: .continuous)
                .fill(CompeteDesign.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: CompeteDesign.innerRadius, style: .continuous)
                .strokeBorder(CompeteDesign.hairline, lineWidth: 1)
        )
    }

    // MARK: - Helpers

    private var remainingTimeString: String? {
        guard competition.status == .active,
              let end = competition.endDateFormatted,
              end > Date() else { return nil }
        let total = end.timeIntervalSinceNow
        let days = Int(total) / 86_400
        let hours = (Int(total) % 86_400) / 3_600
        let mins = (Int(total) % 3_600) / 60
        if days > 0 { return "\(days)d \(hours)h left" }
        if hours > 0 { return "\(hours)h \(mins)m left" }
        return "\(max(1, mins))m left"
    }
}
