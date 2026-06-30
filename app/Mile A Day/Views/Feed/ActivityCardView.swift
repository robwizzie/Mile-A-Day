import SwiftUI

/// A raw walk/run in the unified feed (no photo) — the auto activity card.
/// Shares the visual language of PostCardView: author header, the run line,
/// a compact stat strip, and a hype affordance.
struct ActivityCardView: View {
    let entry: FeedEntry
    var isHyping: Bool = false
    let onHype: () -> Void

    private var distance: Double { entry.distance ?? 0 }
    private var completedMile: Bool { distance >= 1.0 }

    var body: some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.sm) {
            header
            runLine
            statStrip
            footer
        }
        .padding(MADTheme.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
    }

    private var header: some View {
        HStack(spacing: 10) {
            AvatarView(name: entry.displayName, imageURL: entry.profile_image_url, size: 40)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(entry.displayName)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    if completedMile {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.green)
                    }
                }
                Text(entry.relativeTime)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.5))
            }
            Spacer()
            Image(systemName: Self.icon(entry.workout_type))
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(Self.color(entry.workout_type))
        }
    }

    private var runLine: some View {
        HStack(spacing: 6) {
            Text("\(Self.verb(entry.workout_type)) \(String(format: "%.2f", distance)) mi")
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 2)
    }

    @ViewBuilder
    private var statStrip: some View {
        let items = statItems
        if !items.isEmpty {
            HStack(spacing: 8) {
                ForEach(items, id: \.0) { item in
                    HStack(spacing: 4) {
                        Image(systemName: item.1).font(.system(size: 10, weight: .bold))
                            .foregroundColor(.orange)
                        Text(item.2)
                            .font(.system(size: 11, weight: .heavy, design: .rounded))
                            .monospacedDigit()
                            .foregroundColor(.white.opacity(0.85))
                    }
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Capsule().fill(Color.white.opacity(0.06)))
                }
            }
            .padding(.horizontal, 2)
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if let count = entry.hype_count, count > 0 {
                HypeTally(count: count)
            }
            Spacer()
            if !entry.is_self {
                HypeButton(isHyped: entry.is_hyped, isBusy: isHyping, action: onHype)
            }
        }
        .padding(.horizontal, 2)
        .padding(.bottom, 2)
    }

    // (label-key, icon, value) for time / pace / calories / steps when present.
    private var statItems: [(String, String, String)] {
        var out: [(String, String, String)] = []
        if let d = entry.total_duration, d > 0 {
            out.append(("time", "clock.fill", RunStatsStickerView.durationText(d)))
            if distance > 0 {
                out.append(("pace", "speedometer", "\(RunStatsStickerView.paceText(d / distance)) /mi"))
            }
        }
        if let c = entry.calories, c > 0 {
            out.append(("cal", "bolt.fill", "\(Int(c.rounded())) cal"))
        }
        if let s = entry.steps, s > 0 {
            out.append(("steps", "shoeprints.fill", "\(s)"))
        }
        return out
    }

    // MARK: workout type styling
    static func verb(_ type: String?) -> String {
        switch (type ?? "").lowercased() {
        case "running": return "Ran"
        case "walking": return "Walked"
        case "hiking": return "Hiked"
        case "cycling": return "Cycled"
        default: return "Moved"
        }
    }
    static func icon(_ type: String?) -> String {
        switch (type ?? "").lowercased() {
        case "running": return "figure.run"
        case "walking": return "figure.walk"
        case "hiking": return "figure.hiking"
        case "cycling": return "figure.outdoor.cycle"
        default: return "figure.run"
        }
    }
    static func color(_ type: String?) -> Color {
        switch (type ?? "").lowercased() {
        case "running": return MADTheme.Colors.madRed
        case "walking": return .orange
        case "hiking": return .green
        case "cycling": return .blue
        default: return MADTheme.Colors.madRed
        }
    }
}
