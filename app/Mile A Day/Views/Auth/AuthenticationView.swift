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
            // Soft gradient background - more subtle
            LinearGradient(
                colors: [
                    Color(red: 0.25, green: 0.25, blue: 0.3),
                    Color(red: 0.2, green: 0.2, blue: 0.25),
                    Color(red: 0.15, green: 0.15, blue: 0.2)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            // Running-themed decorative elements
            GeometryReader { geometry in
                // Footprint pattern
                ForEach(0..<4, id: \.self) { index in
                    Group {
                        // Left footprint
                        Path { path in
                            path.move(to: CGPoint(x: 0, y: 0))
                            path.addQuadCurve(to: CGPoint(x: 8, y: 15), control: CGPoint(x: 4, y: 5))
                            path.addQuadCurve(to: CGPoint(x: 16, y: 0), control: CGPoint(x: 12, y: 5))
                        }
                        .fill(Color(red: 0.85, green: 0.25, blue: 0.35).opacity(0.12))
                        .frame(width: 16, height: 15)
                        .offset(
                            x: CGFloat(index * 100) + geometry.size.width * 0.2,
                            y: CGFloat(index * 120) + geometry.size.height * 0.1
                        )
                        
                        // Right footprint
                        Path { path in
                            path.move(to: CGPoint(x: 0, y: 0))
                            path.addQuadCurve(to: CGPoint(x: 8, y: 15), control: CGPoint(x: 4, y: 5))
                            path.addQuadCurve(to: CGPoint(x: 16, y: 0), control: CGPoint(x: 12, y: 5))
                        }
                        .fill(Color(red: 0.85, green: 0.25, blue: 0.35).opacity(0.1))
                        .frame(width: 16, height: 15)
                        .offset(
                            x: CGFloat(index * 100 + 25) + geometry.size.width * 0.2,
                            y: CGFloat(index * 120 + 15) + geometry.size.height * 0.1
                        )
                    }
                }
            }
            
            VStack(spacing: MADTheme.Spacing.xxxl) {
                Spacer()
                
                // Logo and title section with liquid glass
                VStack(spacing: MADTheme.Spacing.xl) {
                    // MAD Logo with subtle glow
                    ZStack {
                        Circle()
                            .fill(Color(red: 0.85, green: 0.25, blue: 0.35).opacity(0.15))
                            .frame(width: 160, height: 160)
                            .blur(radius: 30)
                        
                        Image("mad-logo")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 120, height: 120)
                            .scaleEffect(logoScale)
                            .shadow(
                                color: Color(red: 0.85, green: 0.25, blue: 0.35).opacity(0.3),
                                radius: 25,
                                x: 0,
                                y: 10
                            )
                    }
                    
                    VStack(spacing: MADTheme.Spacing.sm) {
                        Text("Welcome to")
                            .font(.system(size: 20, weight: .semibold, design: .default))
                            .foregroundColor(.white.opacity(0.9))
                        
                        Text("MILE A DAY")
                            .font(.system(size: 32, weight: .black, design: .default))
                            .foregroundColor(.white)
                            .tracking(2)
                            .shadow(color: Color.black.opacity(0.3), radius: 4, x: 0, y: 2)
                        
                        Text("Your daily fitness adventure!")
                            .font(.system(size: 17, weight: .regular, design: .default))
                            .foregroundColor(.white.opacity(0.85))
                            .multilineTextAlignment(.center)
                            .shadow(color: Color.black.opacity(0.2), radius: 2, x: 0, y: 1)
                    }
                }
                .opacity(contentOpacity)
                
                Spacer()
                
                // Sleek authentication buttons with glass
                VStack(spacing: MADTheme.Spacing.lg) {
                    // Sign in with Apple - glass effect
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
                                    .font(.system(size: 22, weight: .medium, design: .default))
                                    .foregroundColor(.white)
                            }
                            
                            Text(appleSignInManager.isLoading ? "Signing in..." : "Continue with Apple")
                                .font(.system(size: 17, weight: .semibold, design: .default))
                                .foregroundColor(.white)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, MADTheme.Spacing.md + 4)
                        .background(
                            ZStack {
                                // Black background
                                RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                                    .fill(Color.black)
                                
                                // Glass overlay
                                RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                                    .fill(.ultraThinMaterial.opacity(0.1))
                            }
                        )
                        .shadow(
                            color: Color.black.opacity(0.4),
                            radius: 15,
                            x: 0,
                            y: 8
                        )
                    }
                    .disabled(appleSignInManager.isLoading)
                    .scaleEffect(contentOpacity)
                    
                    // Subtle encouragement text
                    Text("Sign in to start your journey")
                        .font(.system(size: 14, weight: .medium, design: .default))
                        .foregroundColor(.white.opacity(0.7))
                        .padding(.top, MADTheme.Spacing.xs)
                }
                .padding(.horizontal, MADTheme.Spacing.lg)
                .offset(y: buttonsOffset)
                
                Spacer()
                
                // Terms and privacy - clean style
                VStack(spacing: MADTheme.Spacing.xs) {
                    Text("By continuing, you agree to our")
                        .font(.system(size: 12, weight: .regular, design: .default))
                        .foregroundColor(.white.opacity(0.6))
                    
                    HStack(spacing: MADTheme.Spacing.xs) {
                        Button("Terms of Service") {
                            // TODO: Show terms
                        }
                        .font(.system(size: 12, weight: .regular, design: .default))
                        .foregroundColor(.white)
                        .underline()
                        
                        Text("and")
                            .font(.system(size: 12, weight: .regular, design: .default))
                            .foregroundColor(.white.opacity(0.6))
                        
                        Button("Privacy Policy") {
                            // TODO: Show privacy policy
                        }
                        .font(.system(size: 12, weight: .regular, design: .default))
                        .foregroundColor(.white)
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
}

#Preview {
    AuthenticationView()
        .environmentObject(AppStateManager())
}