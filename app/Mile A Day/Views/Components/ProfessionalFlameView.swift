import SwiftUI

struct ProfessionalFlameView: View {
    let health: FlameHealth
    var size: CGFloat = 150
    var ringProgress: Double = 0.72

    var body: some View {
        ZStack {
            if health != .blazing {
                countdownRing
            }

            FlameBuddyView(health: health, size: size * 0.98, showsFace: false)
                .offset(y: -size * 0.035)
                .scaleEffect(flameScale, anchor: .bottom)
                .saturation(flameSaturation)
                .brightness(flameBrightness)
                .opacity(flameOpacity)
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var countdownRing: some View {
        let ringSpan = min(max(ringProgress, 0.025), 0.985)
        let lineWidth = max(3, size * 0.034)
        let diameter = size * 0.78

        return ZStack {
            Circle()
                .stroke(Color.white.opacity(health == .dead ? 0.025 : 0.045), lineWidth: lineWidth)
                .frame(width: diameter, height: diameter)

            Circle()
                .trim(from: 0, to: ringSpan)
                .stroke(
                    accentColor.opacity(arcOpacity),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .frame(width: diameter, height: diameter)
                .rotationEffect(.degrees(-90))
                .scaleEffect(health == .dead ? 0.84 : 1)
                .shadow(color: accentColor.opacity(0.10), radius: 4, x: 0, y: 0)
        }
    }

    private var timeVigor: Double {
        guard health != .blazing else { return 1 }
        return min(max(ringProgress, 0), 1)
    }

    private var flameScale: CGFloat {
        guard health != .blazing else { return 1 }
        return 0.84 + CGFloat(timeVigor) * 0.16
    }

    private var flameOpacity: Double {
        guard health != .blazing else { return 1 }
        return 0.58 + timeVigor * 0.42
    }

    private var flameSaturation: Double {
        guard health != .blazing else { return 1 }
        return 0.42 + timeVigor * 0.58
    }

    private var flameBrightness: Double {
        guard health != .blazing else { return 0 }
        return -0.12 + timeVigor * 0.12
    }

    private var accentColor: Color {
        switch health {
        case .blazing, .healthy: return .orange
        case .dimming: return Color(red: 0.75, green: 0.18, blue: 0.10)
        case .low: return Color(red: 0.36, green: 0.28, blue: 0.82)
        case .critical: return MADTheme.Colors.madRed
        case .dead: return .gray
        }
    }

    private var arcOpacity: Double {
        switch health {
        case .blazing: return 0
        case .healthy: return 0.48
        case .dimming: return 0.40
        case .low: return 0.32
        case .critical: return 0.52
        case .dead: return 0.14
        }
    }

    private var accessibilityText: String {
        switch health {
        case .blazing: return "Professional flame blazing. Today's mile is complete."
        case .healthy: return "Professional flame healthy."
        case .dimming: return "Professional flame dimming."
        case .low: return "Professional flame low."
        case .critical: return "Professional flame at risk."
        case .dead: return "Professional flame out."
        }
    }
}
