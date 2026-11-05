import SwiftUI
import AuthenticationServices

struct AuthenticationView: View {
    @Environment(\.appStateManager) var appStateManager
    @EnvironmentObject var userManager: UserManager
    @StateObject private var appleSignInManager = AppleSignInManager()
    @State private var showError = false
    @State private var legalSheetURL: URL?

    var body: some View {
        OnboardingStepScaffold(
            colors: [Color(red: 0.93, green: 0.33, blue: 0.30), Color(red: 0.62, green: 0.12, blue: 0.22)],
            headline: "Save your streak",
            message: "Sign in so your streak, photos and friends follow you to any iPhone.",
            art: { height in AuthHeroArt(height: height) },
            actions: { actions }
        )
        .alert("Sign In Error", isPresented: $showError) {
            Button("OK") { }
        } message: {
            Text(appleSignInManager.errorMessage ?? "An unknown error occurred")
        }
        .sheet(item: $legalSheetURL) { url in
            SafariWebView(url: url)
                .ignoresSafeArea()
        }
        .onChange(of: appleSignInManager.errorMessage) { oldValue, newValue in
            showError = newValue != nil
        }
    }

    private var actions: some View {
        VStack(spacing: 14) {
            // Sign in with Apple, styled per the HIG: white on a dark
            // background, Apple logo + "Continue with Apple", full width.
            Button(action: handleAppleSignIn) {
                HStack(spacing: 8) {
                    if appleSignInManager.isLoading {
                        ProgressView().tint(.black)
                    } else {
                        Image(systemName: "applelogo")
                            .font(.system(size: 19, weight: .medium))
                    }
                    Text(appleSignInManager.isLoading ? "Signing in..." : "Continue with Apple")
                        .madFont(size: 18, weight: .semibold, maxScale: 1.3)
                }
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 17)
                .background(Capsule().fill(.white))
            }
            .disabled(appleSignInManager.isLoading)

            VStack(spacing: 2) {
                Text("By continuing, you agree to our")
                    .foregroundColor(.white.opacity(0.45))
                HStack(spacing: 4) {
                    Button("Terms") { legalSheetURL = URL(string: "https://mileaday.run/terms") }
                        .foregroundColor(.white.opacity(0.8))
                    Text("and").foregroundColor(.white.opacity(0.45))
                    Button("Privacy Policy") { legalSheetURL = URL(string: "https://mileaday.run/privacy") }
                        .foregroundColor(.white.opacity(0.8))
                }
                .fixedSize()
            }
            .madFont(size: 12, weight: .medium, design: .rounded, maxScale: 1.3)
        }
    }

    private func handleAppleSignIn() {
        Task {
            do {
                let (profile, backendResponse) = try await appleSignInManager.signIn()

                // Update user manager with Apple authentication data
                try userManager.handleAppleSignIn(profile: profile, backendResponse: backendResponse)

                await MainActor.run {
                    withAnimation(MADTheme.Animation.standard) {
                        appStateManager.completeAuthentication(userManager: userManager)
                    }
                }
            } catch {
                await MainActor.run {
                    appleSignInManager.errorMessage = error.localizedDescription
                    appleSignInManager.isLoading = false
                }
            }
        }
    }
}

/// Flamey blazing, ready for day one.
private struct AuthHeroArt: View {
    let height: CGFloat
    @Environment(\.introArtWidth) private var artWidth

    var body: some View {
        let flame = min(height * 0.7, 220)
        ZStack {
            FlameBuddyView(health: .blazing, size: flame, showsMoodBubble: false)
                .frame(width: flame, height: flame)
                .introPop(0.05)
                .introBob(5, period: 3.6)
            IntroChip(text: "🔥 Day 1 starts today")
                .introBob(5, period: 3.0, phase: 0.3)
                .introPop(0.25)
                .offset(x: introClampX(flame * 0.55, "🔥 Day 1 starts today", width: artWidth), y: -flame * 0.38)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview("Dark") {
    AuthenticationView()
        .environmentObject(AppStateManager())
        .preferredColorScheme(.dark)
}

#Preview("Light") {
    AuthenticationView()
        .environmentObject(AppStateManager())
        .preferredColorScheme(.light)
}
