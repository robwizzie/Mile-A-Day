import SwiftUI

/// One bar of the pace wave — a mile of the workout, normalized by pace.
struct WorkoutSplitBar: Identifiable {
    let mile: Int
    /// Seconds per mile — the normalizing measure (a partial last split's raw
    /// duration would read as "fast" otherwise).
    let paceSeconds: Double
    /// The split's real distance; the last one is usually partial and draws
    /// slightly dimmed so a 0.1-mile tail doesn't claim a full mile's bar.
    let partialDistance: Double?
    var id: Int { mile }

    /// From the wire (`FeedEntry.splits` / `PostItem.splits`).
    static func bars(from splits: [FeedSplit]?) -> [WorkoutSplitBar] {
        guard let splits else { return [] }
        return splits.compactMap { split in
            let pace: Double
            if let p = split.split_pace, p > 0 {
                pace = p
            } else if let d = split.split_distance, d > 0 {
                pace = split.split_duration / d
            } else if split.split_duration > 0 {
                pace = split.split_duration
            } else {
                return nil
            }
            return WorkoutSplitBar(
                mile: split.split_number,
                paceSeconds: pace,
                partialDistance: split.split_distance
            )
        }
    }

    /// From the on-device calculator (`SplitCalculator`) — the owner's own
    /// surfaces, where HealthKit is available and the wire may not be.
    static func bars(from splits: [WorkoutSplit]) -> [WorkoutSplitBar] {
        splits.compactMap { split in
            guard split.pace > 0 else { return nil }
            return WorkoutSplitBar(
                mile: split.splitNumber,
                paceSeconds: split.pace,
                partialDistance: split.distance
            )
        }
    }
}

/// The workout's splits as a compact glowing waveform — fast miles tall, slow
/// miles short, drawn left-to-right. Decoration, not a chart: it sits between
/// the headline and the stat tiles on the indoor cards and gives a routeless
/// run a shape of its own. Renders nothing below two bars (one split is a
/// number, not a wave).
struct PaceWaveStrip: View {
    let bars: [WorkoutSplitBar]
    let accent: Color
    var height: CGFloat = 36
    var still: Bool = false

    /// Flipped once, OUTSIDE `withAnimation` — each bar's own
    /// `.animation(_:value:)` carries the stagger (the ios.md rule: an
    /// enclosing transaction would weld the bars back together).
    @State private var revealed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var effectiveStill: Bool { still || reduceMotion }

    var body: some View {
        if bars.count >= 2 {
            let showsNumbers = bars.count <= 8
            let fastest = bars.map(\.paceSeconds).min() ?? 0
            let slowest = bars.map(\.paceSeconds).max() ?? 0
            let barArea = height - (showsNumbers ? 12 : 0)
            HStack(alignment: .bottom, spacing: 5) {
                ForEach(Array(bars.enumerated()), id: \.element.id) { index, bar in
                    VStack(spacing: 2) {
                        RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                            .fill(LinearGradient(
                                colors: [accent, accent.opacity(0.55)],
                                startPoint: .top, endPoint: .bottom
                            ))
                            .frame(height: max(5, barArea * fraction(bar, fastest: fastest, slowest: slowest)))
                            .shadow(color: accent.opacity(0.45), radius: 3)
                            .opacity(isPartial(bar) ? 0.55 : 1)
                            .scaleEffect(y: (effectiveStill || revealed) ? 1 : 0.02, anchor: .bottom)
                            .animation(effectiveStill ? nil : .easeOut(duration: 0.35).delay(Double(index) * 0.06),
                                       value: revealed)
                        if showsNumbers {
                            Text("\(bar.mile)")
                                .font(.system(size: 8, weight: .bold, design: .rounded))
                                .foregroundColor(.white.opacity(0.4))
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: height)
            .task {
                guard !effectiveStill, !revealed else { return }
                try? await Task.sleep(for: .milliseconds(350))
                revealed = true
            }
        }
    }

    /// Same normalization rule as the workout detail's splits section: fastest
    /// mile = full height, slowest = 35%.
    private func fraction(_ bar: WorkoutSplitBar, fastest: Double, slowest: Double) -> CGFloat {
        guard slowest > fastest else { return 1 }
        let normalized = (bar.paceSeconds - fastest) / (slowest - fastest)
        return CGFloat(1 - normalized * 0.65)
    }

    private func isPartial(_ bar: WorkoutSplitBar) -> Bool {
        guard let d = bar.partialDistance else { return false }
        return d < 0.95
    }
}
