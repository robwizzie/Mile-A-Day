import SwiftUI
import AuthenticationServices

struct AuthenticationView: View {
    @Environment(\.appStateManager) var appStateManager
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var userManager: UserManager
    @StateObject private var appleSignInManager = AppleSignInManager()
    @State private var logoScale: CGFloat = 0.8
    @State private var contentOpacity: Double = 0
    @State private var buttonsOffset: CGFloat = 40
    @State private var showError = false

    private var backgroundColor: LinearGradient {
        colorScheme == .dark
            ? LinearGradient(
                colors: [
                    Color(red: 0.12, green: 0.06, blue: 0.08),
                    Color(red: 0.06, green: 0.03, blue: 0.04)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            : LinearGradient(
                colors: [
                    Color(red: 0.98, green: 0.97, blue: 0.97),
                    Color(red: 0.94, green: 0.93, blue: 0.94)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
    }

    private var titleColor: Color {
        colorScheme == .dark ? .white : Color(red: 0.12, green: 0.12, blue: 0.14)
    }

    private var subtitleColor: Color {
        colorScheme == .dark ? .white.opacity(0.7) : Color(red: 0.45, green: 0.43, blue: 0.47)
    }

    private var tertiaryTextColor: Color {
        colorScheme == .dark ? .white.opacity(0.5) : Color(red: 0.6, green: 0.58, blue: 0.62)
    }

    private var appleButtonBackground: Color {
        colorScheme == .dark ? .white : .black
    }

    private var appleButtonForeground: Color {
        colorScheme == .dark ? .black : .white
    }

    var body: some View {
        ZStack {
            backgroundColor
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Logo and title
                VStack(spacing: MADTheme.Spacing.xl) {
                    // Logo with glow
                    ZStack {
                        Circle()
                            .fill(MADTheme.Colors.madRed.opacity(colorScheme == .dark ? 0.15 : 0.08))
                            .frame(width: 180, height: 180)
                            .blur(radius: 35)

                        Image("mad-logo")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 120, height: 120)
                            .scaleEffect(logoScale)
                            .shadow(
                                color: MADTheme.Colors.madRed.opacity(colorScheme == .dark ? 0.3 : 0.15),
                                radius: 25,
                                x: 0,
                                y: 10
                            )
                    }

                    VStack(spacing: MADTheme.Spacing.sm) {
                        Text("Welcome to")
                            .font(.system(size: 18, weight: .medium, design: .rounded))
                            .foregroundColor(subtitleColor)

                        Text("MILE A DAY")
                            .font(.system(size: 34, weight: .black, design: .rounded))
                            .foregroundColor(titleColor)
                            .tracking(2)

                        Text("Your daily fitness journey starts here")
                            .font(.system(size: 16, weight: .regular, design: .rounded))
                            .foregroundColor(subtitleColor)
                            .padding(.top, 2)
                    }
                }
                .opacity(contentOpacity)

                Spacer()
                Spacer()

                // Sign in button
                VStack(spacing: MADTheme.Spacing.md) {
                    Button(action: {
                        handleAppleSignIn()
                    }) {
                        HStack(spacing: 10) {
                            if appleSignInManager.isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: appleButtonForeground))
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "applelogo")
                                    .font(.system(size: 20, weight: .medium))
                            }

                            Text(appleSignInManager.isLoading ? "Signing in..." : "Continue with Apple")
                                .font(.system(size: 17, weight: .semibold, design: .rounded))
                        }
                        .foregroundColor(appleButtonForeground)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(appleButtonBackground)
                        )
                        .shadow(
                            color: Color.black.opacity(colorScheme == .dark ? 0.4 : 0.15),
                            radius: 12,
                            x: 0,
                            y: 6
                        )
                    }
                    .disabled(appleSignInManager.isLoading)

                    Text("Sign in to track your runs and compete with friends")
                        .font(.system(size: 14, weight: .regular, design: .rounded))
                        .foregroundColor(tertiaryTextColor)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, MADTheme.Spacing.lg)
                .offset(y: buttonsOffset)
                .opacity(contentOpacity)

                Spacer()

                // Terms and privacy
                VStack(spacing: MADTheme.Spacing.xs) {
                    Text("By continuing, you agree to our")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(tertiaryTextColor)

                    HStack(spacing: MADTheme.Spacing.xs) {
                        Button("Terms of Service") {
                            // TODO: Show terms
                        }
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(subtitleColor)
                        .underline()

                        Text("and")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(tertiaryTextColor)

                        Button("Privacy Policy") {
                            // TODO: Show privacy policy
                        }
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(subtitleColor)
                        .underline()
                    }
                }
                .opacity(contentOpacity)
                .padding(.bottom, MADTheme.Spacing.xl)
            }
        }
        .onAppear {
            startAnimations()
        }
        .alert("Sign In Error", isPresented: $showError) {
            Button("OK") { }
        } message: {
            Text(appleSignInManager.errorMessage ?? "An unknown error occurred")
        }
        .onChange(of: appleSignInManager.errorMessage) { oldValue, newValue in
            showError = newValue != nil
        }
    }

    private func startAnimations() {
        withAnimation(.spring(response: 0.7, dampingFraction: 0.75).delay(0.2)) {
            logoScale = 1.0
        }

        withAnimation(.easeOut(duration: 0.5).delay(0.3)) {
            contentOpacity = 1.0
        }

        withAnimation(.easeOut(duration: 0.5).delay(0.5)) {
            buttonsOffset = 0
        }
    }

    private func handleAppleSignIn() {
        Task {
            do {
                let (profile, backendResponse) = try await appleSignInManager.signIn()

                // Update user manager with Apple authentication data
                userManager.handleAppleSignIn(profile: profile, backendResponse: backendResponse)

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
