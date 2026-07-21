import SwiftUI

/// Full-screen "Token Earned!" moment. Fires when a meter completes (or when
/// enrollment backfill hands a long streaker their starting set): dimmed
/// backdrop, contained glass panel, the medallion(s) spring in oversized with
/// a soft glow, then title + names + a single CTA. Deliberately self-contained
/// — no coupling to the goal-celebration state machine.
struct TokenUnlockOverlay: View {
    let kinds: [StreakTokenKind]
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    @State private var haloScale: CGFloat = 0.92

    private var title: String {
        kinds.count == 1 ? "Token Earned!" : "\(kinds.count) Tokens Earned!"
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.72).ignoresSafeArea()
                .onTapGesture { dismiss() }

            VStack(spacing: 18) {
                ZStack {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 1.0, green: 0.84, blue: 0.35).opacity(0.22),
                                    MADTheme.Colors.madRed.opacity(0.14),
                                    Color.clear
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: kinds.count == 1 ? 190 : 320, height: 92)
                        .blur(radius: 18)
                        .scaleEffect(haloScale)
                        .opacity(appeared ? 1 : 0)

                    HStack(spacing: kinds.count > 1 ? 18 : 0) {
                        ForEach(Array(kinds.enumerated()), id: \.element.title) { index, kind in
                            TokenMedallion(
                                kind: kind,
                                held: true,
                                size: kinds.count == 1 ? 128 : 82
                            )
                            .scaleEffect(appeared ? 1 : 0.2)
                            .opacity(appeared ? 1 : 0)
                            .animation(
                                .spring(response: 0.5, dampingFraction: 0.62)
                                    .delay(0.08 + Double(index) * 0.12),
                                value: appeared
                            )
                        }
                    }
                }

                VStack(spacing: 8) {
                    Text(title)
                        .font(.system(size: 31, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)

                    Text(kinds.map { $0.title }.joined(separator: " + "))
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .foregroundColor(Color(red: 1.0, green: 0.84, blue: 0.35))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)

                    Text(subtitle)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.72))
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 12)
                .animation(.easeOut(duration: 0.4).delay(0.3), value: appeared)

                Button {
                    dismiss()
                } label: {
                    Text("Let's Go")
                        .font(.system(size: 17, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                        .frame(minWidth: 170)
                        .padding(.vertical, 14)
                        .background(Capsule().fill(MADTheme.Colors.redGradient))
                        .shadow(color: MADTheme.Colors.madRed.opacity(0.34), radius: 12)
                }
                .buttonStyle(ScaleButtonStyle())
                .opacity(appeared ? 1 : 0)
                .animation(.easeOut(duration: 0.4).delay(0.45), value: appeared)
            }
            .padding(.horizontal, 26)
            .padding(.vertical, 28)
            .frame(maxWidth: 360)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.10),
                                        MADTheme.Colors.madRed.opacity(0.08),
                                        Color.clear
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.35), radius: 26, x: 0, y: 18)
            )
            .scaleEffect(appeared ? 1 : 0.94)
            .opacity(appeared ? 1 : 0)
            .padding(.horizontal, 22)
            .animation(.spring(response: 0.46, dampingFraction: 0.78), value: appeared)
        }
        .onAppear {
            appeared = true
            MADHaptics.success()
            if !reduceMotion {
                withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                    haloScale = 1.04
                }
            }
        }
    }

    private var subtitle: String {
        if kinds.count > 1 {
            return "Your streak history earned these. They are ready on your dashboard whenever you need them."
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
