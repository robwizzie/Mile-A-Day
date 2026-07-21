import SwiftUI

/// One-time "you're already mid-story" reveal: the first time the app has a
/// real streak computed from HealthKit history, count it up from zero with
/// the flame igniting. For a brand-new runner it never fires (streak < 3);
/// for someone who's been running daily, it's the app's best first
/// impression: "You've run a mile every day for 37 days."
struct StreakRevealOverlay: View {
    let streak: Int
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var displayed = 0
    @State private var appeared = false
    @State private var countDone = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.88).ignoresSafeArea()

            VStack(spacing: MADTheme.Spacing.lg) {
                Text("WE CHECKED YOUR HISTORY")
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .tracking(1.6)
                    .foregroundColor(.white.opacity(0.55))
                    .opacity(appeared ? 1 : 0)
                    .animation(.easeOut(duration: 0.4), value: appeared)

                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color.orange.opacity(countDone ? 0.5 : 0.25),
                                    .clear
                                ],
                                center: .center,
                                startRadius: 10,
                                endRadius: 150
                            )
                        )
                        .frame(width: 300, height: 300)
                        .animation(.easeInOut(duration: 0.6), value: countDone)

                    VStack(spacing: 2) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 44, weight: .bold))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: countDone
                                        ? [.yellow, .orange, MADTheme.Colors.madRed]
                                        : [.gray.opacity(0.7), .gray.opacity(0.5)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .scaleEffect(countDone ? 1.12 : 1.0)
                            .animation(.spring(response: 0.4, dampingFraction: 0.5), value: countDone)
                            .shadow(color: countDone ? Color.orange.opacity(0.7) : .clear, radius: 16)

                        Text("\(displayed)")
                            .font(.system(size: 88, weight: .black, design: .rounded))
                            .monospacedDigit()
                            .foregroundColor(.white)
                            .contentTransition(.numericText(value: Double(displayed)))

                        Text("DAY STREAK")
                            .font(.system(size: 13, weight: .heavy, design: .rounded))
                            .tracking(2.0)
                            .foregroundColor(.white.opacity(0.7))
                    }
                }

                Text("You've completed a mile every single day for \(streak) days — your streak starts counted, not at zero.")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, MADTheme.Spacing.xl)
                    .opacity(countDone ? 1 : 0)
                    .offset(y: countDone ? 0 : 10)
                    .animation(.easeOut(duration: 0.4).delay(0.2), value: countDone)

                Button {
                    withAnimation(.easeOut(duration: 0.25)) { onDismiss() }
                } label: {
                    Text("Keep It Alive")
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.horizontal, 44)
                        .padding(.vertical, 14)
                        .background(Capsule().fill(MADTheme.Colors.redGradient))
                        .shadow(color: MADTheme.Colors.madRed.opacity(0.5), radius: 10)
                }
                .buttonStyle(ScaleButtonStyle())
                .opacity(countDone ? 1 : 0)
                .animation(.easeOut(duration: 0.4).delay(0.4), value: countDone)
            }
            .padding(MADTheme.Spacing.lg)
        }
        .onAppear { start() }
    }

    /// Ease-out count-up over ~2s (longer streaks take a touch longer, capped)
    /// with the flame igniting at the end. Reduce Motion jumps straight there.
    private func start() {
        appeared = true
        guard !reduceMotion else {
            displayed = streak
            countDone = true
            MADHaptics.success()
            return
        }
        let steps = min(max(streak, 12), 60)
        let total = streak >= 100 ? 2.6 : 2.0
        for i in 1...steps {
            let t = Double(i) / Double(steps)
            let eased = 1 - pow(1 - t, 3)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35 + total * t) {
                withAnimation(.linear(duration: 0.05)) {
                    displayed = Int(Double(streak) * eased)
                }
                if i == steps {
                    displayed = streak
                    countDone = true
                    MADHaptics.success()
                } else if i % max(steps / 8, 1) == 0 {
                    MADHaptics.tap()
                }
            }
        }
    }
}
