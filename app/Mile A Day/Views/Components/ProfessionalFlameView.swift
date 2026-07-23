import SwiftUI

/// The Modern dashboard streak hero: a vivid flame that burns down with the
/// day like a candle and dies to a cold coal when the streak is gone.
///
/// Time left is communicated by SIZE, never by fading — a live flame stays
/// fully saturated and opaque; it only gets smaller. The countdown ring frames
/// the flame only while there is still a mile to run.
struct ProfessionalFlameView: View {
    let phase: StreakFlamePhase
    let health: FlameHealth
    var size: CGFloat = 150
    /// Fraction of the day remaining (1 just after midnight, 0 at midnight).
    var ringProgress: Double = 0.72
    var dayEnd: Date? = nil
    /// Today's partial mile progress (0-1) — warms the coal before ignition.
    var coalWarmth: Double = 0

    var body: some View {
        ZStack {
            if phase == .burning {
                countdownRing
            }

            FlameBuddyView(
                health: health,
                size: size * 0.98,
                showsFace: false,
                phase: phase,
                dayEnd: dayEnd,
                coalWarmth: coalWarmth,
                grounded: false
            )
            .offset(y: -size * 0.035)
        }
        .frame(width: size, height: size)
        .animation(.easeInOut(duration: 0.45), value: phase == .burning)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var countdownRing: some View {
        let ringSpan = min(max(ringProgress, 0.02), 0.985)
        let lineWidth = max(3, size * 0.034)
        let diameter = size * 0.78

        return ZStack {
            Circle()
                .stroke(Color.white.opacity(0.045), lineWidth: lineWidth)
                .frame(width: diameter, height: diameter)

            Circle()
                .trim(from: 0, to: ringSpan)
                .stroke(
                    ringColor.opacity(0.50),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .frame(width: diameter, height: diameter)
                .rotationEffect(.degrees(-90))
                .shadow(color: ringColor.opacity(0.12), radius: 4, x: 0, y: 0)
        }
    }

    /// Warm orange with a full day ahead, deepening to alarm red as it drains.
    private var ringColor: Color {
        FlamePalette.lerp((1.0, 0.62, 0.12), (0.86, 0.14, 0.16), 1 - min(max(ringProgress, 0), 1))
    }

    private var accessibilityText: String {
        switch phase {
        case .blazing:
            return "Streak flame blazing. Today's mile is complete."
        case .coal:
            return "Streak coal. Run a mile to ignite your flame."
        case .burning:
            let percent = Int((min(max(ringProgress, 0), 1) * 100).rounded())
            return "Streak flame burning. \(percent) percent of the day left to run your mile."
        }
    }
}
