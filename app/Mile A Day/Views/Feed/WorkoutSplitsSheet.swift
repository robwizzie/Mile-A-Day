import SwiftUI

/// SPLITS, the second chip on a card's media — dark glass beside the filled
/// FLYOVER pill, so the two read as "the primary thing" and "the detail".
/// Drawn only when the post's workout actually carries splits.
struct SplitsChipButton: View {
    /// The workout's colour — the glyph's tint.
    var accent: Color = MADTheme.Colors.madRed
    let action: () -> Void

    var body: some View {
        Button {
            MADHaptics.tap()
            action()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 10, weight: .black))
                    .foregroundColor(accent)
                Text("SPLITS")
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .tracking(1.0)
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Capsule().fill(Color.black.opacity(0.55)))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
            .shadow(color: .black.opacity(0.35), radius: 6, y: 3)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Show mile splits")
    }
}

/// A workout's per-mile splits, opened from a post or a raw workout card —
/// indoor or outdoor alike, since splits are pace and time, not location
/// (the server sends them regardless of route sharing).
///
/// Reads top to bottom the way the run happened: the headline numbers, the
/// pace wave (the indoor card's own strip, given room), a fastest-mile chip,
/// then one bar per mile in the same recipe the workout detail screen draws.
/// Bars are normalised by PACE, not time, so a partial last mile sits where
/// its speed puts it rather than reading as the fastest split of the day;
/// only full miles can be "fastest", because a 0.06-mile tail's pace is
/// noise.
struct WorkoutSplitsSheet: View {
    let bars: [WorkoutSplitBar]
    let stats: PostStats?
    let workoutType: String?
    /// nil = unknown; the chip simply doesn't draw (routeless is never
    /// "indoor" on its own).
    let isIndoor: Bool?
    /// Whose workout — "Rob" on a friend's card, "You" on your own.
    let ownerName: String

    @Environment(\.dismiss) private var dismiss

    private var accent: Color { ActivityCardView.color(workoutType) }
    private var verb: String { ActivityCardView.verb(workoutType, paceSecondsPerMile: stats?.pace) }
    private var icon: String { ActivityCardView.icon(workoutType, paceSecondsPerMile: stats?.pace) }
    private var noun: String { PostCardView.activityNoun(workoutType, pace: stats?.pace) }

    /// Same threshold the flyover's split toasts use for "a whole mile".
    private static let fullMile = 0.95

    private func isFull(_ bar: WorkoutSplitBar) -> Bool {
        (bar.partialDistance ?? 1) >= Self.fullMile
    }

    private var fastest: WorkoutSplitBar? {
        let full = bars.filter(isFull)
        guard full.count >= 2 else { return nil }
        return full.min { $0.paceSeconds < $1.paceSeconds }
    }

    private var slowest: WorkoutSplitBar? {
        let full = bars.filter(isFull)
        guard full.count >= 2 else { return nil }
        return full.max { $0.paceSeconds < $1.paceSeconds }
    }

    private var fastestPace: Double { bars.map(\.paceSeconds).min() ?? 0 }
    private var slowestPace: Double { bars.map(\.paceSeconds).max() ?? 0 }

    /// The fastest split fills the bar; the slowest reads at 35% so every
    /// mile stays visible — the workout detail screen's rule.
    private func fraction(_ bar: WorkoutSplitBar) -> CGFloat {
        guard slowestPace > fastestPace else { return 1 }
        let normalized = (bar.paceSeconds - fastestPace) / (slowestPace - fastestPace)
        return CGFloat(1 - normalized * 0.65)
    }

    /// The split's own time. The wire carries pace and distance; for a full
    /// mile the two are the same number, for a partial it's pace × distance.
    private func splitSeconds(_ bar: WorkoutSplitBar) -> Double {
        bar.paceSeconds * (bar.partialDistance ?? 1)
    }

    private func label(_ bar: WorkoutSplitBar) -> String {
        if let d = bar.partialDistance, d < Self.fullMile {
            return "Last \(d.milesText) mi"
        }
        return "Mile \(bar.mile)"
    }

    /// "Rob · Walk · 19:30 · 18:24 /mi" — whichever of those the run has.
    private var detailLine: String {
        var parts = [ownerName, noun]
        if let d = stats?.duration, d > 0 {
            parts.append(RunStatsStickerView.durationText(d))
        }
        if let p = stats?.pace, p > 0 {
            parts.append("\(RunStatsStickerView.paceText(p)) /mi")
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        ZStack {
            MADTheme.Colors.appBackgroundGradient.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
                    header
                    headline

                    if bars.count >= 2 {
                        PaceWaveStrip(bars: bars, accent: accent, height: 64)
                            .padding(.vertical, MADTheme.Spacing.xs)
                    }

                    if let fastest, let slowest, fastest.id != slowest.id {
                        summaryChips(fastest: fastest, slowest: slowest)
                    }

                    rows

                    Text("Pace per mile, from the workout's own splits.")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundColor(.white.opacity(0.4))
                        .padding(.top, MADTheme.Spacing.xs)
                }
                .padding(.horizontal, MADTheme.Spacing.md)
                .padding(.top, MADTheme.Spacing.lg)
                .padding(.bottom, MADTheme.Spacing.xl)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: Pieces

    private var header: some View {
        HStack(spacing: MADTheme.Spacing.sm) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 12, weight: .bold))
                Text(verb.uppercased())
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .tracking(1.4)
            }
            .foregroundColor(accent)
            .padding(.horizontal, 11).padding(.vertical, 6)
            .background(Capsule().fill(accent.opacity(0.15)))

            if let isIndoor {
                Text(isIndoor ? "INDOOR" : "OUTDOOR")
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .tracking(1.2)
                    .foregroundColor(.white.opacity(0.55))
                    .padding(.horizontal, 9).padding(.vertical, 6)
                    .background(Capsule().fill(Color.white.opacity(0.08)))
            }

            Spacer(minLength: 0)

            Text("SPLITS")
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .tracking(1.6)
                .foregroundColor(.white.opacity(0.45))
        }
    }

    private var headline: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text((stats?.distance ?? 0).milesText)
                    .font(.system(size: 44, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(.white)
                Text("mi")
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .foregroundColor(.white.opacity(0.6))
            }
            Text(detailLine)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.55))
                .lineLimit(1)
        }
    }

    private func summaryChips(fastest: WorkoutSplitBar, slowest: WorkoutSplitBar) -> some View {
        let spread = max(0, slowest.paceSeconds - fastest.paceSeconds)
        return HStack(spacing: MADTheme.Spacing.sm) {
            summaryChip(
                icon: "bolt.fill",
                title: "FASTEST",
                value: "Mile \(fastest.mile) · \(RunStatsStickerView.paceText(fastest.paceSeconds))",
                tint: MADTheme.Colors.success
            )
            summaryChip(
                icon: "arrow.left.and.right",
                title: "SPREAD",
                value: "\(Int(spread.rounded()))s between miles",
                tint: .white.opacity(0.7)
            )
        }
    }

    private func summaryChip(icon: String, title: String, value: String, tint: Color) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(tint)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 9, weight: .heavy, design: .rounded))
                    .tracking(1.2)
                    .foregroundColor(.white.opacity(0.45))
                Text(value)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(.white.opacity(0.9))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 11).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
    }

    private var rows: some View {
        VStack(spacing: MADTheme.Spacing.sm) {
            ForEach(bars) { bar in
                SplitBarRow(
                    mile: bar.mile,
                    timeLabel: RunStatsStickerView.durationText(splitSeconds(bar)),
                    fraction: fraction(bar),
                    isFastest: bar.id == fastest?.id,
                    color: accent,
                    label: label(bar),
                    detailLabel: "\(RunStatsStickerView.paceText(bar.paceSeconds)) /mi",
                    dimmed: !isFull(bar)
                )
            }
        }
        .padding(MADTheme.Spacing.md)
        .madLiquidGlass()
    }
}
