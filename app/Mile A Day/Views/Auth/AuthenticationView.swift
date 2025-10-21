import SwiftUI
import AuthenticationServices

struct AuthenticationView: View {
    @Environment(\.appStateManager) var appStateManager
    @EnvironmentObject var userManager: UserManager
    @StateObject private var appleSignInManager = AppleSignInManager()
    @State private var logoScale: CGFloat = 0.8
    @State private var contentOpacity: Double = 0
    @State private var buttonsOffset: CGFloat = 50
    @State private var showError = false
    
    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [
                    MADTheme.Colors.madWhite,
                    MADTheme.Colors.secondaryBackground
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            VStack(spacing: MADTheme.Spacing.xxxl) {
                Spacer()
                
                // Logo and title section
                VStack(spacing: MADTheme.Spacing.xl) {
                    // MAD Logo - Replace "mad-logo" with your image name
                    Image("mad-logo")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 120, height: 120)
                        .scaleEffect(logoScale)
                        .shadow(
                            color: MADTheme.Colors.madRed.opacity(0.3),
                            radius: 20,
                            x: 0,
                            y: 8
                        )
                    
                    VStack(spacing: MADTheme.Spacing.sm) {
                        Text("Welcome to")
                            .font(MADTheme.Typography.title3)
                            .foregroundColor(MADTheme.Colors.secondaryText)
                        
                        Text("MILE A DAY")
                            .font(MADTheme.Typography.title1)
                            .fontWeight(.black)
                            .foregroundColor(MADTheme.Colors.madRed)
                            .tracking(1)
                        
                        Text("Your daily fitness companion")
                            .font(MADTheme.Typography.body)
                            .foregroundColor(MADTheme.Colors.secondaryText)
                            .multilineTextAlignment(.center)
                    }
                }
                .opacity(contentOpacity)
                
                Spacer()
                
                // Authentication buttons
                VStack(spacing: MADTheme.Spacing.lg) {
                    // Sign in with Apple
                    Button(action: {
                        handleAppleSignIn()
                    }) {
                        HStack(spacing: MADTheme.Spacing.md) {
                            if appleSignInManager.isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "applelogo")
                                    .font(.system(size: 20, weight: .medium))
                                    .foregroundColor(.white)
                            }
                            
                            Text(appleSignInManager.isLoading ? "Signing in..." : "Continue with Apple")
                                .font(MADTheme.Typography.headline)
                                .foregroundColor(.white)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, MADTheme.Spacing.md + 2)
                        .background(
                            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                                .fill(Color.black)
                        )
                        .shadow(
                            color: MADTheme.Shadow.medium.color,
                            radius: MADTheme.Shadow.medium.radius,
                            x: MADTheme.Shadow.medium.x,
                            y: MADTheme.Shadow.medium.y
                        )
                    }
                    .disabled(appleSignInManager.isLoading)
                    .scaleEffect(contentOpacity)
                    
                    // Commented out Google Sign In
                    /*
                    // Sign in with Google
                    Button(action: {
                        // TODO: Implement Google Sign In
                        handleGoogleSignIn()
                    }) {
                        HStack(spacing: MADTheme.Spacing.md) {
                            // Google logo placeholder
                            GoogleLogoView()
                                .frame(width: 20, height: 20)
                            
                            Text("Continue with Google")
                                .font(MADTheme.Typography.headline)
                                .foregroundColor(MADTheme.Colors.primaryText)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, MADTheme.Spacing.md + 2)
                        .background(
                            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                                .fill(MADTheme.Colors.cardBackground)
                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                        )
                        .shadow(
                            color: MADTheme.Shadow.small.color,
                            radius: MADTheme.Shadow.small.radius,
                            x: MADTheme.Shadow.small.x,
                            y: MADTheme.Shadow.small.y
                        )
                    }
                    .scaleEffect(contentOpacity)
                    */
                    
                    // Commented out Guest Sign In
                    /*
                    // Alternative sign-in options
                    VStack(spacing: MADTheme.Spacing.md) {
                        HStack {
                            Rectangle()
                                .fill(Color.gray.opacity(0.3))
                                .frame(height: 1)
                            
                            Text("OR")
                                .font(MADTheme.Typography.caption)
                                .foregroundColor(MADTheme.Colors.secondaryText)
                                .padding(.horizontal, MADTheme.Spacing.md)
                            
                            Rectangle()
                                .fill(Color.gray.opacity(0.3))
                                .frame(height: 1)
                        }
                        
                        Button("Continue as Guest") {
                            handleGuestSignIn()
                        }
                        .madTertiaryButton()
                    }
                    .opacity(contentOpacity)
                    */
                }
                .padding(.horizontal, MADTheme.Spacing.lg)
                .offset(y: buttonsOffset)
                
                Spacer()
                
                // Terms and privacy
                VStack(spacing: MADTheme.Spacing.xs) {
                    Text("By continuing, you agree to our")
                        .font(MADTheme.Typography.caption)
                        .foregroundColor(MADTheme.Colors.secondaryText)
                    
                    HStack(spacing: MADTheme.Spacing.xs) {
                        Button("Terms of Service") {
                            // TODO: Show terms
                        }
                        .font(MADTheme.Typography.caption)
                        .foregroundColor(MADTheme.Colors.madRed)
                        
                        Text("and")
                            .font(MADTheme.Typography.caption)
                            .foregroundColor(MADTheme.Colors.secondaryText)
                        
                        Button("Privacy Policy") {
                            // TODO: Show privacy policy
                        }
                        .font(MADTheme.Typography.caption)
                        .foregroundColor(MADTheme.Colors.madRed)
                    }
                }
                .opacity(contentOpacity)
                .padding(.bottom, MADTheme.Spacing.lg)
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
        withAnimation(MADTheme.Animation.bounce.delay(0.2)) {
            logoScale = 1.0
        }
        
        withAnimation(MADTheme.Animation.standard.delay(0.4)) {
            contentOpacity = 1.0
        }
        
        withAnimation(MADTheme.Animation.standard.delay(0.6)) {
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
    
    // Commented out Google Sign In
    /*
    private func handleGoogleSignIn() {
        // Simulate Google Sign In for UI purposes
        withAnimation(MADTheme.Animation.standard) {
            // TODO: Replace with actual Google Sign In implementation
            appStateManager.completeAuthentication()
        }
    }
    */
    
    // Commented out Guest Sign In
    /*
    private func handleGuestSignIn() {
        // Allow guest access
        withAnimation(MADTheme.Animation.standard) {
            appStateManager.completeAuthentication()
        }
    }
    */
}

/// Google Logo Recreation
struct GoogleLogoView: View {
    var body: some View {
        ZStack {
            // Simplified Google logo colors
            HStack(spacing: 0) {
                // G shape using colored rectangles to simulate the logo
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        Rectangle()
                            .fill(Color.blue)
                            .frame(width: 7, height: 7)
                        Rectangle()
                            .fill(Color.red)
                            .frame(width: 7, height: 7)
                    }
                    HStack(spacing: 0) {
                        Rectangle()
                            .fill(Color.green)
                            .frame(width: 7, height: 7)
                        Rectangle()
                            .fill(Color.yellow)
                            .frame(width: 7, height: 7)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 2))
            }
        }
    }
}

#Preview {
    AuthenticationView()
        .environmentObject(AppStateManager())
}