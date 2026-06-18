import SwiftUI

// MARK: - Instructions Banner

/// Dashboard welcome banner shown to new users until they take (or dismiss)
/// the tour. "Take the tour" launches the full-screen `WelcomeTourView`.
struct InstructionsBanner: View {
    /// Launches the welcome tour (replay).
    let onTakeTour: () -> Void
    @AppStorage("hasSeenInstructions") private var hasSeenInstructions = false

    var body: some View {
        if !hasSeenInstructions {
            VStack(spacing: 14) {
                HStack(spacing: 12) {
                    Image(systemName: "figure.run.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [MADTheme.Colors.madRed, .orange],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Welcome to Mile A Day!")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundColor(.white)

                        Text("Take a quick tour to see streaks, competitions, medals, and everything you can do.")
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.7))
                }

                HStack(spacing: 10) {
                    Button {
                        onTakeTour()
                    } label: {
                        Text("Take the tour")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(
                                Capsule()
                                    .fill(MADTheme.Colors.madRed.opacity(0.8))
                            )
                    }

                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            hasSeenInstructions = true
                        }
                    } label: {
                        Text("Got it!")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundColor(.white.opacity(0.85))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(
                                Capsule()
                                    .fill(Color.white.opacity(0.10))
                                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.15), lineWidth: 1))
                            )
                    }
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                    .fill(Color.white.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
        }
    }
}
