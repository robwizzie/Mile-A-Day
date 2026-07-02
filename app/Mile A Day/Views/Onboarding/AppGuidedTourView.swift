import SwiftUI

/// Live guided tour that overlays the real app and navigates the user through
/// each tab. Presented as a fullScreenCover from DashboardView; on each step
/// it posts a `MAD_SwitchTab` notification to flip the underlying tab, then
/// shows a floating coach-mark card explaining what they're looking at.
struct AppGuidedTourView: View {
    let onComplete: () -> Void

    @State private var step = 0
    @State private var didAppear = false
    @State private var cardVisible = false

    private let steps = GuidedTourStep.all
    private var isLast: Bool { step >= steps.count - 1 }
    private var current: GuidedTourStep { steps[step] }

    var body: some View {
        ZStack {
            // Semi-transparent scrim so the real app shows through but dimmed.
            Color.black.opacity(0.75)
                .ignoresSafeArea()
                .onTapGesture { } // absorb taps

            VStack {
                // Top bar
                topBar
                    .padding(.horizontal, 20)
                    .padding(.top, 12)

                Spacer()

                // Floating coach-mark card
                if cardVisible {
                    coachCard
                        .padding(.horizontal, 20)
                        .transition(.asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity),
                            removal: .opacity
                        ))
                }

                // Bottom navigation
                bottomControls
                    .padding(.horizontal, 20)
                    .padding(.bottom, 100) // clear tab bar
            }
            .opacity(didAppear ? 1 : 0)
        }
        .onAppear {
            switchToTab(steps[0].tabIndex)
            withAnimation(.easeOut(duration: 0.3)) { didAppear = true }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.3)) {
                cardVisible = true
            }
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            // Step indicator
            HStack(spacing: 6) {
                Image(systemName: current.icon)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(current.accent)
                Text("\(step + 1) of \(steps.count)")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.6))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color.white.opacity(0.1)))

            Spacer()

            Button {
                switchToTab(0)
                onComplete()
            } label: {
                Text("End Tour")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.6))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(Color.white.opacity(0.1)))
            }
        }
    }

    // MARK: - Coach Card

    private var coachCard: some View {
        VStack(spacing: 14) {
            // Tab badge
            HStack(spacing: 8) {
                Image(systemName: current.icon)
                    .font(.system(size: 16, weight: .bold))
                Text(current.tabName.uppercased())
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .tracking(1.5)
            }
            .foregroundColor(current.accent)

            Text(current.title)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)

            Text(current.body)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.75))
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            // Tips
            VStack(alignment: .leading, spacing: 8) {
                ForEach(current.tips, id: \.self) { tip in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(current.accent)
                            .padding(.top, 2)
                        Text(tip)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.8))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(current.accent.opacity(0.1))
            )
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.4), radius: 20, y: 10)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(current.accent.opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Bottom Controls

    private var bottomControls: some View {
        HStack {
            // Back button
            if step > 0 {
                Button {
                    navigate(to: step - 1)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.left")
                            .font(.system(size: 14, weight: .bold))
                        Text("Back")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                    }
                    .foregroundColor(.white.opacity(0.7))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(Capsule().fill(Color.white.opacity(0.12)))
                }
            }

            Spacer()

            // Progress dots
            HStack(spacing: 6) {
                ForEach(steps.indices, id: \.self) { i in
                    Circle()
                        .fill(i == step ? current.accent : Color.white.opacity(0.25))
                        .frame(width: i == step ? 10 : 6, height: i == step ? 10 : 6)
                        .animation(.spring(response: 0.3), value: step)
                }
            }

            Spacer()

            // Next / Done button
            Button {
                if isLast {
                    switchToTab(0)
                    onComplete()
                } else {
                    navigate(to: step + 1)
                }
            } label: {
                HStack(spacing: 6) {
                    Text(isLast ? "Done" : "Next")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                    Image(systemName: isLast ? "checkmark" : "arrow.right")
                        .font(.system(size: 13, weight: .bold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 22)
                .padding(.vertical, 12)
                .background(
                    Capsule().fill(
                        LinearGradient(
                            colors: [current.accent, current.accent.opacity(0.75)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                )
                .shadow(color: current.accent.opacity(0.35), radius: 8, y: 3)
            }
        }
    }

    // MARK: - Navigation

    private func navigate(to newStep: Int) {
        // Hide card, switch tab, then show card for the new step.
        withAnimation(.easeOut(duration: 0.15)) {
            cardVisible = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            step = newStep
            switchToTab(steps[newStep].tabIndex)
            withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                cardVisible = true
            }
        }
    }

    private func switchToTab(_ tab: Int) {
        NotificationCenter.default.post(
            name: NSNotification.Name("MAD_SwitchTab"),
            object: nil,
            userInfo: ["tab": tab]
        )
    }
}

// MARK: - Tour Step Data

private struct GuidedTourStep {
    let tabName: String
    let icon: String
    let tabIndex: Int
    let title: String
    let body: String
    let tips: [String]
    let accent: Color

    static let all: [GuidedTourStep] = [
        GuidedTourStep(
            tabName: "Dashboard",
            icon: "house.fill",
            tabIndex: 0,
            title: "Your Home Base",
            body: "This is where you track today's progress, see your streak, and stay on top of competitions and challenges.",
            tips: [
                "Tap the pencil icon to log a manual workout",
                "Your streak and today's miles update live",
                "Scroll down for stats, medals, and workout history"
            ],
            accent: MADTheme.Colors.madRed
        ),
        GuidedTourStep(
            tabName: "Compete",
            icon: "trophy.fill",
            tabIndex: 1,
            title: "Challenge Your Friends",
            body: "Create head-to-head or group competitions. Race to hit miles, maintain streaks, or outlast each other over days or weeks.",
            tips: [
                "Tap + to create a new competition",
                "Invite friends or share a join code",
                "Watch the leaderboard update in real time"
            ],
            accent: .orange
        ),
        GuidedTourStep(
            tabName: "Feed",
            icon: "square.stack.fill",
            tabIndex: 2,
            title: "See What's Happening",
            body: "Photo posts, workout activity, and stories from you and your friends all flow through here.",
            tips: [
                "Complete your mile to unlock posting",
                "Hype friends' workouts with the fire button",
                "Tap a name or photo to visit their profile"
            ],
            accent: .blue
        ),
        GuidedTourStep(
            tabName: "Friends",
            icon: "person.2.fill",
            tabIndex: 3,
            title: "Build Your Crew",
            body: "Find friends, climb the leaderboard, and nudge anyone who's slacking. Streaks are better together.",
            tips: [
                "Search by username or share your QR code",
                "Star close friends for quick access",
                "Check the leaderboard for weekly rankings"
            ],
            accent: .cyan
        ),
        GuidedTourStep(
            tabName: "Profile",
            icon: "person.fill",
            tabIndex: 4,
            title: "Your Running Resume",
            body: "View your stats, earned medals, posts, and activity history. Pin your favorite badges and share your profile.",
            tips: [
                "Pin up to 3 favorite medals to show off",
                "Tap the gear icon for all settings",
                "Share your profile QR code with friends"
            ],
            accent: .purple
        )
    ]
}

#Preview {
    AppGuidedTourView { }
}
