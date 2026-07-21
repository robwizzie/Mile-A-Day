import SwiftUI

/// The story moment when a token FIRES: a Streak Save quietly covered a
/// missed day, a Double Down comeback landed, or a friend's Streak Assist
/// rescued the user. The numbers were already corrected server-side — this
/// overlay makes sure the user gets the story, not just adjusted math.
struct TokenStoryOverlay: View {
    let event: TokenStoryEvent
    let streak: Int
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    private var kind: StreakTokenKind {
        switch event.kind {
        case "double_down_recover": return .doubleDown
        case "streak_assist": return .assist
        default: return .save
        }
    }

    private var title: String {
        switch event.kind {
        case "double_down_recover": return "You Ran It Back!"
        case "streak_assist": return "A Friend Saved Your Streak"
        default: return "Streak Saved"
        }
    }

    private var message: String {
        let day = friendlyDay
        let days = streak > 0 ? "\(streak) days, intact." : "Your streak is intact."
        switch event.kind {
        case "double_down_recover":
            return "You doubled your goal, so \(day) counts. \(days)"
        case "streak_assist":
            return "\(day) was covered by a friend's Streak Assist. \(days)"
        default:
            return "\(day) was covered automatically. \(days)"
        }
    }

    private var footnote: String {
        switch event.kind {
        case "double_down_recover":
            return "That's the comeback. 14 more active days earns the next Double Down."
        case "streak_assist":
            return "Someone spent 20 hard-earned over-goal miles on you. Send them some love."
        default:
            return "Your Streak Save was spent — 7 run days earns the next one."
        }
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.82).ignoresSafeArea()
                .onTapGesture { dismiss() }

            VStack(spacing: MADTheme.Spacing.lg) {
                ZStack {
                    // Soft halo instead of the unlock overlay's rays — this is
                    // a warm "you're okay" moment, not a trophy moment.
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [kind.tint.opacity(0.45), .clear],
                                center: .center,
                                startRadius: 10,
                                endRadius: 130
                            )
                        )
                        .frame(width: 260, height: 260)

                    TokenMedallion(kind: kind, held: true, size: 116)
                        .scaleEffect(appeared ? 1 : 0.3)
                        .opacity(appeared ? 1 : 0)
                        .animation(
                            reduceMotion
                                ? .default
                                : .spring(response: 0.5, dampingFraction: 0.65).delay(0.1),
                            value: appeared
                        )
                }

                VStack(spacing: 8) {
                    Text(title)
                        .font(.system(size: 28, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)

                    Text(message)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(footnote)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                }
                .padding(.horizontal, MADTheme.Spacing.xl)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 12)
                .animation(.easeOut(duration: 0.4).delay(0.3), value: appeared)

                Button {
                    dismiss()
                } label: {
                    Text("Keep Running")
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.horizontal, 44)
                        .padding(.vertical, 14)
                        .background(Capsule().fill(MADTheme.Colors.redGradient))
                        .shadow(color: MADTheme.Colors.madRed.opacity(0.5), radius: 10)
                }
                .buttonStyle(ScaleButtonStyle())
                .opacity(appeared ? 1 : 0)
                .animation(.easeOut(duration: 0.4).delay(0.45), value: appeared)
            }
            .padding(MADTheme.Spacing.lg)
        }
        .onAppear {
            appeared = true
            MADHaptics.success()
        }
    }

    /// "Yesterday", a weekday name for the last week, or "Jul 19".
    private var friendlyDay: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: event.localDate) else { return "A missed day" }
        let calendar = Calendar.current
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        if let daysAgo = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: Date())).day,
           daysAgo < 7 {
            let weekday = DateFormatter()
            weekday.dateFormat = "EEEE"
            return weekday.string(from: date)
        }
        let short = DateFormatter()
        short.dateFormat = "MMM d"
        return short.string(from: date)
    }

    private func dismiss() {
        withAnimation(.easeOut(duration: 0.25)) { onDismiss() }
    }
}
