import SwiftUI

/// Flyover cinema: the map stays full-bleed and the splits run down the side,
/// lighting up as the flight passes each mile.
struct DuoFlyoverSplitsPanel: View {
    let bars: [WorkoutSplitBar]
    let miles: Double

    private var fastest: Double { bars.map(\.paceSeconds).min() ?? 1 }
    private var slowest: Double { bars.map(\.paceSeconds).max() ?? 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Splits")
                .madFont(size: 14, weight: .heavy, design: .rounded, maxScale: 1.3)
                .foregroundColor(.white)
            // Hugs its rows; only a long run needs to scroll.
            ViewThatFits(in: .vertical) {
                rows
                ScrollView(showsIndicators: false) { rows }
            }
        }
        .padding(14)
        .frame(width: 196)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.black.opacity(0.55)))
        .accessibilityElement(children: .combine)
    }

    private var rows: some View {
        VStack(spacing: 8) {
            ForEach(bars) { bar in
                row(bar)
            }
        }
    }

    private func row(_ bar: WorkoutSplitBar) -> some View {
        let reached = miles >= Double(bar.mile)
        let span = max(slowest - fastest, 1)
        // Fastest mile draws longest, so a quick mile reads as a big bar.
        let fill = 0.35 + 0.65 * (slowest - bar.paceSeconds) / span
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Mile \(bar.mile)")
                    .madFont(size: 12, weight: .bold, design: .rounded, maxScale: 1.3)
                Spacer(minLength: 6)
                Text(Self.paceText(bar.paceSeconds))
                    .madFont(size: 12, weight: .semibold, design: .rounded, maxScale: 1.3, monospacedDigit: true)
                    .lineLimit(1)
            }
            .foregroundColor(.white.opacity(reached ? 1 : 0.7))
            GeometryReader { geo in
                Capsule()
                    .fill(reached ? MADTheme.Colors.madRed : Color.white.opacity(0.28))
                    .frame(width: geo.size.width * fill)
            }
            .frame(height: 5)
        }
        .animation(.easeOut(duration: 0.3), value: reached)
    }

    private static func paceText(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
