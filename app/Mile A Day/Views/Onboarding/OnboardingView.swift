import SwiftUI

/// First-launch onboarding, shown once before sign-up: the five-step intro
/// (`OnboardingIntroView`), then authentication. "Already have an account?"
/// goes to the same Sign in with Apple screen (it resolves both).
///
/// The same tour is auto-shown once on the dashboard for users who upgrade and
/// never saw onboarding, and is replayable any time from
/// Profile → Settings → App Tour (or Help & Support).
struct OnboardingView: View {
    @Environment(\.appStateManager) var appStateManager

    var body: some View {
        OnboardingIntroView(finishButtonTitle: "Get started", showsSignInLink: true) {
            // The user has seen the full tour during onboarding — suppress the
            // dashboard's first-run auto-play and the welcome banner so it
            // isn't shown to them a second time.
            UserDefaults.standard.set(true, forKey: "hasSeenWelcomeTour")
            UserDefaults.standard.set(true, forKey: "hasSeenInstructions")
            appStateManager.completeOnboarding()
        }
    }
}

#Preview("Dark") {
    OnboardingView()
        .environmentObject(AppStateManager())
        .preferredColorScheme(.dark)
}
