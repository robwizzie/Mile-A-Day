import SwiftUI

/// Branded 4:5 stats card used as the auto feed image for a run that has no
/// photo and no GPS route (e.g. a treadmill mile). Rendered to a flat image via
/// `ImageRenderer` and uploaded as the post media.
struct RunStatsCardView: View {
    let stats: RunStatsInput
    /// "running" / "walking" — drives the icon + accent.
    let workoutType: String

    private var isWalk: Bool { workoutType == "walking" }
    private var icon: String { isWalk ? "figure.walk" : "figure.run" }
    private var accent: Color { isWalk ? .blue : MADTheme.Colors.madRed }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.09, green: 0.09, blue: 0.12), .black],
                startPoint: .top, endPoint: .bottom
            )
            // Accent glow
            RadialGradient(colors: [accent.opacity(0.35), .clear],
                           center: .init(x: 0.5, y: 0.22), startRadius: 10, endRadius: 360)

            VStack(spacing: 18) {
                Spacer()

                Image(systemName: icon)
                    .font(.system(size: 52, weight: .semibold))
                    .foregroundStyle(LinearGradient(colors: [.white, accent],
                                                    startPoint: .top, endPoint: .bottom))
                    .shadow(color: accent.opacity(0.5), radius: 16)

                Text(String(format: "%.2f", stats.distance))
                    .font(.system(size: 96, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .monospacedDigit()
                    .shadow(color: .black.opacity(0.4), radius: 8, y: 4)
                Text("MILES")
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .tracking(6)
                    .foregroundColor(.white.opacity(0.65))

                HStack(spacing: 10) {
                    if let p = stats.paceSecondsPerMile, p > 0 {
                        chip("speedometer", "\(RunStatsStickerView.paceText(p)) /mi")
                    }
                    if let d = stats.durationSeconds, d > 0 {
                        chip("clock.fill", RunStatsStickerView.durationText(d))
                    }
                    if let s = stats.streak, s > 0 {
                        chip("flame.fill", "\(s) day streak", tint: .orange)
                    }
                }
                .padding(.top, 4)

                Spacer()

                HStack(spacing: 6) {
                    Image(systemName: "figure.run.circle.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(accent)
                    Text("Mile A Day")
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .foregroundColor(.white.opacity(0.85))
                    if let date = stats.dateText, !date.isEmpty {
                        Text("· \(date)")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundColor(.white.opacity(0.4))
                    }
                }
                .padding(.bottom, 34)
            }
            .padding(.horizontal, 28)
        }
    }

    private func chip(_ icon: String, _ text: String, tint: Color = .white) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 12, weight: .bold))
            Text(text).font(.system(size: 14, weight: .heavy, design: .rounded)).monospacedDigit()
        }
        .foregroundColor(tint)
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Capsule().fill(Color.white.opacity(0.1)))
    }
}
