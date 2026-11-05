import SwiftUI

/// Live guided tour over the real app: each step switches the tab underneath
/// and explains it on one card pinned above the tab bar.
///
/// Built to stay smooth: no material blur (a blur re-samples the live tabs
/// behind it every frame), no full-screen dark scrim hiding the very screen
/// being explained (just a fade behind the card), and the card never leaves.
/// A step change switches the tab FIRST and cross-fades only the card's text
/// on the next run loop, so the tab's rebuild doesn't land mid-animation.
struct AppGuidedTourView: View {
    /// Stamped when the tour ends (Done or Skip) — the dashboard's
    /// getting-started checklist reads it.
    static let seenKey = "hasSeenAppGuidedTour"

    let onComplete: () -> Void

    @State private var step = 0
    @State private var shown = false

    private let steps = GuidedTourStep.all
    private var isLast: Bool { step >= steps.count - 1 }
    private var current: GuidedTourStep { steps[step] }

    private static let surface = Color(red: 0.09, green: 0.06, blue: 0.075)

    var body: some View {
        ZStack(alignment: .bottom) {
            // Taps on the app are absorbed, but the app stays visible: only
            // the area behind the card is shaded.
            Color.black.opacity(0.001)
                .ignoresSafeArea()
                .onTapGesture { }
            LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .top, endPoint: .bottom)
                .frame(height: 420)
                .frame(maxWidth: .infinity)
                .allowsHitTesting(false)
                .ignoresSafeArea()

            card
                .padding(.horizontal, 16)
                .padding(.bottom, 96) // clear the tab bar
                .offset(y: shown ? 0 : 40)
                .opacity(shown ? 1 : 0)
        }
        .onAppear {
            switchToTab(steps[0].tabIndex)
            DispatchQueue.main.async {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) { shown = true }
            }
        }
    }

    // MARK: - Card

    private var card: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(current.tabName, systemImage: current.icon)
                    .madFont(size: 13, weight: .bold, design: .rounded, maxScale: 1.3)
                    .foregroundColor(current.accent)
                Spacer()
                Button("Skip", action: finish)
                    .madFont(size: 14, weight: .semibold, design: .rounded, maxScale: 1.3)
                    .foregroundColor(.white.opacity(0.55))
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(current.title)
                    .madFont(size: 22, weight: .heavy, design: .rounded, maxScale: 1.3)
                    .foregroundColor(.white)
                Text(current.body)
                    .madFont(size: 15, weight: .medium, design: .rounded, maxScale: 1.3)
                    .foregroundColor(.white.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(current.tips, id: \.self) { tip in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Circle()
                                .fill(current.accent)
                                .frame(width: 5, height: 5)
                                .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
                            Text(tip)
                                .madFont(size: 14, weight: .medium, design: .rounded, maxScale: 1.3)
                                .foregroundColor(.white.opacity(0.85))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.top, 4)
            }
            .id(step)
            .transition(.opacity)

            controls
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Self.surface))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(.white.opacity(0.06), lineWidth: 1))
    }

    private var controls: some View {
        HStack(spacing: 12) {
            if step > 0 {
                Button("Back") { go(to: step - 1) }
                    .madFont(size: 15, weight: .semibold, design: .rounded, maxScale: 1.3)
                    .foregroundColor(.white.opacity(0.7))
            }

            HStack(spacing: 6) {
                ForEach(steps.indices, id: \.self) { i in
                    Capsule()
                        .fill(i == step ? current.accent : Color.white.opacity(0.2))
                        .frame(width: i == step ? 18 : 6, height: 6)
                }
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Step \(step + 1) of \(steps.count)")

            Button {
                if isLast { finish() } else { go(to: step + 1) }
            } label: {
                Text(isLast ? "Done" : "Next")
                    .madFont(size: 15, weight: .bold, design: .rounded, maxScale: 1.3)
                    .foregroundColor(.white)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 11)
                    .background(Capsule().fill(MADTheme.Colors.madRed))
            }
        }
    }

    // MARK: - Navigation

    /// Tab first, then (next run loop, after the tab has rebuilt) a short
    /// cross-fade of the card's text. The card itself never moves.
    private func go(to newStep: Int) {
        MADHaptics.tap()
        switchToTab(steps[newStep].tabIndex)
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.22)) { step = newStep }
        }
    }

    private func finish() {
        switchToTab(0)
        UserDefaults.standard.set(true, forKey: Self.seenKey)
        withAnimation(.easeOut(duration: 0.2)) { shown = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { onComplete() }
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
            title: "Your day at a glance",
            body: "Your streak, today's mile and Flamey, all in one place.",
            tips: [
                "Tap Start to track a walk or run",
                "Walks from Apple Health count on their own",
                "Scroll down for challenges and medals"
            ],
            accent: MADTheme.Colors.madRed
        ),
        GuidedTourStep(
            tabName: "Compete",
            icon: "trophy.fill",
            tabIndex: 1,
            title: "Race your friends",
            body: "Head-to-head or group competitions over days or weeks.",
            tips: [
                "Tap + to start a competition",
                "Invite friends to race with you"
            ],
            accent: .orange
        ),
        GuidedTourStep(
            tabName: "Feed",
            icon: "square.stack.fill",
            tabIndex: 2,
            title: "See everyone's walks",
            body: "Photos, stories and who's out walking right now.",
            tips: [
                "Post a photo once your mile is done",
                "Tap the clap to hype a friend's walk"
            ],
            accent: MADTheme.Colors.walkBlue
        ),
        GuidedTourStep(
            tabName: "Friends",
            icon: "person.2.fill",
            tabIndex: 3,
            title: "Keep each other going",
            body: "See who's done today and nudge anyone running out of time.",
            tips: [
                "Tap Add friends to find people",
                "Walk together live with a friend"
            ],
            accent: .cyan
        ),
        GuidedTourStep(
            tabName: "Profile",
            icon: "person.fill",
            tabIndex: 4,
            title: "Your streak, your story",
            body: "Your stats, medals and posts, all in one place.",
            tips: [
                "The gear opens Settings",
                "Share your profile with friends"
            ],
            accent: .purple
        )
    ]
}

#Preview {
    AppGuidedTourView { }
}
