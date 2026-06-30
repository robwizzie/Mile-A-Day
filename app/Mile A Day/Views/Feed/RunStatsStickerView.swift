import SwiftUI

/// The run-stats "sticker" overlaid on a post photo (distance / pace / time /
/// streak), styled to match the celebration + share-card visual language. Used
/// two ways:
///   1. Draggable in the composer, then composited onto the photo via ImageRenderer.
///   2. (Future) re-rendered server-side from `stats_snapshot`.
/// `displayDate` lets the caller stamp the run's day; pace/duration are optional
/// and simply omitted when unavailable.
struct RunStatsStickerView: View {
    var distance: Double
    var paceSecondsPerMile: Double?
    var durationSeconds: Double?
    var streak: Int?
    var dateText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(MADTheme.Colors.redGradient)
                Text("MILE A DAY")
                    .font(.system(size: 11, weight: .black, design: .rounded))
                    .tracking(1.5)
                    .foregroundColor(.white.opacity(0.85))
                if let dateText {
                    Text("· \(dateText)")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.5))
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(String(format: "%.2f", distance))
                    .font(.system(size: 40, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .monospacedDigit()
                Text("mi")
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .foregroundColor(.white.opacity(0.7))
            }

            HStack(spacing: 14) {
                if let paceSecondsPerMile, paceSecondsPerMile > 0 {
                    stat(icon: "speedometer", value: Self.paceText(paceSecondsPerMile), label: "pace")
                }
                if let durationSeconds, durationSeconds > 0 {
                    stat(icon: "clock.fill", value: Self.durationText(durationSeconds), label: "time")
                }
                if let streak, streak > 0 {
                    stat(icon: "flame.fill", value: "\(streak)", label: streak == 1 ? "day" : "days")
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.35), radius: 12, x: 0, y: 6)
        .fixedSize()
    }

    private func stat(icon: String, value: String, label: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.orange)
            VStack(alignment: .leading, spacing: 0) {
                Text(value)
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                    .monospacedDigit()
                Text(label.uppercased())
                    .font(.system(size: 8, weight: .heavy, design: .rounded))
                    .tracking(0.8)
                    .foregroundColor(.white.opacity(0.5))
            }
        }
    }

    static func paceText(_ secPerMile: Double) -> String {
        let m = Int(secPerMile) / 60
        let s = Int(secPerMile) % 60
        return String(format: "%d:%02d", m, s)
    }

    static func durationText(_ seconds: Double) -> String {
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }
}
