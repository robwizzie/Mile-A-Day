import SwiftUI

/// Full-screen "Token Earned!" moment. Fires when a meter completes (or when
/// enrollment backfill hands a long streaker their starting set): dimmed
/// backdrop, slow-spinning gold rays, the medallion(s) spring in oversized
/// with a glow, then title + names + a single CTA. Deliberately self-contained
/// — no coupling to the goal-celebration state machine.
struct TokenUnlockOverlay: View {
    let kinds: [StreakTokenKind]
    let onDismiss: () -> Void

    @State private var appeared = false
    @State private var raysAngle: Angle = .degrees(0)

    private var title: String {
        kinds.count == 1 ? "Token Earned!" : "\(kinds.count) Tokens Earned!"
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.82).ignoresSafeArea()
                .onTapGesture { dismiss() }

            // Gold rays radiating behind the medallions — the "reward" light.
            RaysShape(count: 12)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 1.0, green: 0.84, blue: 0.35).opacity(0.35), .clear],
                        startPoint: .center,
                        endPoint: .top
                    )
                )
                .frame(width: 420, height: 420)
                .rotationEffect(raysAngle)
                .opacity(appeared ? 1 : 0)
                .allowsHitTesting(false)

            VStack(spacing: MADTheme.Spacing.lg) {
                HStack(spacing: kinds.count > 1 ? 18 : 0) {
                    ForEach(Array(kinds.enumerated()), id: \.element.title) { index, kind in
                        TokenMedallion(
                            kind: kind,
                            held: true,
                            size: kinds.count == 1 ? 132 : 84
                        )
                        .scaleEffect(appeared ? 1 : 0.2)
                        .opacity(appeared ? 1 : 0)
                        .animation(
                            .spring(response: 0.5, dampingFraction: 0.62)
                                .delay(0.12 + Double(index) * 0.14),
                            value: appeared
                        )
                    }
                }

                VStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 30, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)

                    Text(kinds.map { $0.title }.joined(separator: " · "))
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(Color(red: 1.0, green: 0.84, blue: 0.35))

                    Text(subtitle)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, MADTheme.Spacing.xl)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 12)
                .animation(.easeOut(duration: 0.4).delay(0.35), value: appeared)

                Button {
                    dismiss()
                } label: {
                    Text("Let's Go")
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.horizontal, 44)
                        .padding(.vertical, 14)
                        .background(Capsule().fill(MADTheme.Colors.redGradient))
                        .shadow(color: MADTheme.Colors.madRed.opacity(0.5), radius: 10)
                }
                .buttonStyle(ScaleButtonStyle())
                .opacity(appeared ? 1 : 0)
                .animation(.easeOut(duration: 0.4).delay(0.5), value: appeared)
            }
            .padding(MADTheme.Spacing.lg)
        }
        .onAppear {
            appeared = true
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            withAnimation(.linear(duration: 24).repeatForever(autoreverses: false)) {
                raysAngle = .degrees(360)
            }
        }
    }

    private var subtitle: String {
        if kinds.count > 1 {
            return "Your streak history earned these. They're on your dashboard — tap them anytime to see what they do."
        }
        switch kinds[0] {
        case .doubleDown:
            return "Miss a day? Run 2× your goal the next day and it still counts."
        case .save:
            return "If you ever miss a day, this covers it automatically."
        case .assist:
            return "A friend's streak breaks? You can now save it from their row on the Friends tab."
        }
    }

    private func dismiss() {
        withAnimation(.easeOut(duration: 0.25)) { onDismiss() }
    }
}

/// Simple radial burst of tapered rays.
private struct RaysShape: Shape {
    let count: Int

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        let halfWidth = CGFloat.pi / CGFloat(count) * 0.35
        for i in 0..<count {
            let angle = CGFloat(i) / CGFloat(count) * 2 * .pi
            path.move(to: center)
            path.addLine(to: CGPoint(
                x: center.x + radius * cos(angle - halfWidth),
                y: center.y + radius * sin(angle - halfWidth)
            ))
            path.addLine(to: CGPoint(
                x: center.x + radius * cos(angle + halfWidth),
                y: center.y + radius * sin(angle + halfWidth)
            ))
            path.closeSubpath()
        }
        return path
    }
}

/// Maps the state's raw earned kinds to medallion kinds.
extension StreakTokenKind {
    static func from(raw: String) -> StreakTokenKind? {
        switch raw {
        case "double_down": return .doubleDown
        case "streak_save": return .save
        case "streak_assist": return .assist
        default: return nil
        }
    }
}
