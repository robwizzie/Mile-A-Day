import SwiftUI

/// Explains a daily mile that was completed across several walks or runs.
///
/// The card above this shows one combined distance, which on its own reads as a
/// single continuous effort. Three lunchtime laps and one steady mile are
/// different achievements, and the feed should say which it's looking at — so
/// when the server reports more than one segment, this breaks the total back
/// down into the legs that made it.
///
/// Segments come from the server (`segments` on a feed entry), which decides
/// which workouts folded into the mile. Sub-floor accidents are never among
/// them, so a 3-second phantom can't show up as a leg of someone's mile.
struct MileSegmentStrip: View {
    let segments: [RunSegment]
    /// Tints the bars to match the card's workout type.
    var accent: Color = MADTheme.Colors.primary

    /// Longest leg, for proportional bar widths. Guarded so a set of zero-length
    /// segments can't divide by zero.
    private var longest: Double {
        max(segments.map(\.distance).max() ?? 0, 0.01)
    }

    private var headline: String {
        // "3 walks" when they're all walks, "3 runs" when all runs, and the
        // neutral "3 activities" for a mixed day rather than mislabelling it.
        let count = segments.count
        let allWalks = segments.allSatisfy { $0.isWalk }
        let allRuns = segments.allSatisfy { !$0.isWalk }
        let noun = allWalks ? "walk" : (allRuns ? "run" : "activity")
        let plural = noun == "activity" ? "activities" : "\(noun)s"
        return "Mile completed in \(count) \(count == 1 ? noun : plural)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.xs) {
            HStack(spacing: 5) {
                Image(systemName: "square.stack.3d.up.fill")
                    .font(.system(size: 10, weight: .bold))
                Text(headline)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
            }
            .foregroundColor(.secondary)

            ForEach(segments) { segment in
                SegmentBarRow(
                    segment: segment,
                    fraction: CGFloat(segment.distance / longest),
                    color: accent
                )
            }
        }
        .padding(.horizontal, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(headline). "
                + segments
                .map { String(format: "%.2f miles", $0.distance) }
                .joined(separator: ", ")
        )
    }
}

/// One leg. Deliberately the same shape as `SplitBarRow` on the workout detail
/// screen so a breakdown reads the same wherever it appears.
private struct SegmentBarRow: View {
    let segment: RunSegment
    let fraction: CGFloat
    let color: Color

    private var durationLabel: String? {
        guard let duration = segment.duration, duration > 0 else { return nil }
        let total = Int(duration.rounded())
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    var body: some View {
        HStack(spacing: MADTheme.Spacing.sm) {
            Image(systemName: segment.isWalk ? "figure.walk" : "figure.run")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
                .frame(width: 14)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.07))
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [color.opacity(0.85), color],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        // Floor the width so a very short leg is still visible
                        // as a bar rather than collapsing to nothing.
                        .frame(width: max(6, geo.size.width * min(max(fraction, 0), 1)))
                }
            }
            .frame(height: 8)

            Text(String(format: "%.2f mi", segment.distance))
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(.primary)
                .frame(width: 58, alignment: .trailing)

            if let durationLabel {
                Text(durationLabel)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
                    .frame(width: 44, alignment: .trailing)
            }
        }
    }
}
