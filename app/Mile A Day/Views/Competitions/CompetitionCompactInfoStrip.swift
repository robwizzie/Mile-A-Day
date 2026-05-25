import SwiftUI

/// Single-row horizontal info bar that replaces the tall premium-hero block.
/// Reads at a glance: status dot, type, allowed activities, interval, time
/// remaining. The comp name is already in the nav title, so we omit it.
struct CompetitionCompactInfoStrip: View {
    let competition: Competition

    private var typeColor: Color {
        Color(hex: competition.type.gradient.first ?? "#888888")
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                statusChip
                typeChip
                ForEach(competition.workouts, id: \.self) { activity in
                    activityChip(activity)
                }
                if let interval = competition.options.interval {
                    intervalChip(interval.displayName)
                }
                if let remaining = remainingTimeString {
                    timeRemainingChip(remaining)
                }
            }
            .padding(.horizontal, 2)
        }
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
    }

    // MARK: - Chips

    private var statusChip: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(competition.status.color)
                .frame(width: 6, height: 6)
            Text(competition.status.displayName.uppercased())
                .font(.system(size: 10, weight: .black, design: .rounded))
                .tracking(1.0)
                .foregroundColor(competition.status.color)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(competition.status.color.opacity(0.15))
                .overlay(Capsule().strokeBorder(competition.status.color.opacity(0.35), lineWidth: 1))
        )
    }

    private var typeChip: some View {
        HStack(spacing: 5) {
            Image(systemName: competition.type.icon)
                .font(.system(size: 10, weight: .heavy))
            Text(competition.type.displayName.uppercased())
                .font(.system(size: 10, weight: .black, design: .rounded))
                .tracking(1.0)
        }
        .foregroundColor(typeColor)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(typeColor.opacity(0.15))
                .overlay(Capsule().strokeBorder(typeColor.opacity(0.35), lineWidth: 1))
        )
    }

    private func activityChip(_ activity: CompetitionActivity) -> some View {
        HStack(spacing: 4) {
            Image(systemName: activity.icon)
                .font(.system(size: 9, weight: .bold))
            Text(activity.displayName)
                .font(.system(size: 10, weight: .bold, design: .rounded))
        }
        .foregroundColor(activity.color)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Capsule().fill(activity.backgroundColor))
    }

    private func intervalChip(_ name: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "arrow.trianglehead.2.clockwise")
                .font(.system(size: 9, weight: .bold))
            Text(name)
                .font(.system(size: 10, weight: .bold, design: .rounded))
        }
        .foregroundColor(.white.opacity(0.75))
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Capsule().fill(Color.white.opacity(0.08)))
    }

    private func timeRemainingChip(_ text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "clock.fill")
                .font(.system(size: 9, weight: .bold))
            Text(text)
                .font(.system(size: 10, weight: .bold, design: .rounded))
        }
        .foregroundColor(.orange)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(Color.orange.opacity(0.12))
                .overlay(Capsule().strokeBorder(Color.orange.opacity(0.3), lineWidth: 1))
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
