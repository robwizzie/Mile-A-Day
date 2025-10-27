import SwiftUI

struct OnboardingView: View {
    @Environment(\.appStateManager) var appStateManager
    @State private var currentPage = 0
    @State private var contentOpacity: Double = 0
    
    private let onboardingPages: [OnboardingPage] = [
        OnboardingPage(
            icon: "figure.run",
            title: "Walk or Run One Mile",
            subtitle: "Every day, do at least one mile. That's it.",
            accentColor: Color(red: 0.85, green: 0.25, blue: 0.35),
            gradientColors: [
                Color(red: 0.95, green: 0.4, blue: 0.5),
                Color(red: 0.85, green: 0.25, blue: 0.35),
                Color(red: 0.7, green: 0.15, blue: 0.25)
            ]
        ),
        OnboardingPage(
            icon: "flame.fill",
            title: "Build Your Streak",
            subtitle: "Keep moving every single day to keep your streak alive.",
            accentColor: Color(red: 1.0, green: 0.5, blue: 0.0),
            gradientColors: [
                Color(red: 1.0, green: 0.6, blue: 0.3),
                Color(red: 1.0, green: 0.5, blue: 0.0),
                Color(red: 0.9, green: 0.4, blue: 0.0)
            ]
        ),
        OnboardingPage(
            icon: "person.2.fill",
            title: "Stay Motivated",
            subtitle: "Connect with friends and see who's leading the pack.",
            accentColor: Color(red: 0.2, green: 0.7, blue: 0.9),
            gradientColors: [
                Color(red: 0.3, green: 0.8, blue: 1.0),
                Color(red: 0.2, green: 0.7, blue: 0.9),
                Color(red: 0.1, green: 0.6, blue: 0.8)
            ]
        )
    ]
    
    var body: some View {
        ZStack {
            // Sleek gradient background
            LinearGradient(
                colors: [
                    onboardingPages[currentPage].gradientColors[0].opacity(0.3),
                    onboardingPages[currentPage].gradientColors[1].opacity(0.2),
                    onboardingPages[currentPage].gradientColors[2].opacity(0.15)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 0.5), value: currentPage)
            
            // Minimal motion lines - much more subtle
            ForEach(0..<2, id: \.self) { index in
                HStack(spacing: 2) {
                    ForEach(0..<2, id: \.self) { lineIndex in
                        Rectangle()
                            .fill(onboardingPages[currentPage].accentColor.opacity(0.08 - Double(lineIndex) * 0.04))
                            .frame(width: 2, height: 15 - CGFloat(lineIndex * 5))
                    }
                }
                .offset(
                    x: CGFloat(index % 2 == 0 ? -80 : 80),
                    y: CGFloat(index * 300 - 200)
                )
                .rotationEffect(.degrees(index % 2 == 0 ? -12 : 12))
            }
            
            VStack(spacing: 0) {
                // Skip button with glass effect
                HStack {
                    Spacer()
                    Button("Skip") {
                        appStateManager.completeOnboarding()
                    }
                    .font(.system(size: 16, weight: .medium, design: .default))
                    .foregroundColor(.white.opacity(0.8))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(.ultraThinMaterial)
                    )
                    .padding(.trailing, MADTheme.Spacing.lg)
                    .padding(.top, MADTheme.Spacing.lg)
                }
                .opacity(contentOpacity)
                
                // Main content area
                TabView(selection: $currentPage) {
                    ForEach(0..<onboardingPages.count, id: \.self) { index in
                        OnboardingPageView(page: onboardingPages[index])
                            .tag(index)
                    }
                }
                .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
                .opacity(contentOpacity)
                
                // Bottom section with controls
                VStack(spacing: MADTheme.Spacing.xl) {
                    // Sleek page indicator with glass
                    HStack(spacing: MADTheme.Spacing.sm) {
                        ForEach(0..<onboardingPages.count, id: \.self) { index in
                            Capsule()
                                .fill(index == currentPage ? onboardingPages[index].accentColor : Color.white.opacity(0.3))
                                .frame(width: index == currentPage ? 32 : 16, height: 8)
                                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: currentPage)
                        }
                    }
                    .padding(.top, MADTheme.Spacing.lg)
                    
                    // Sleek button with glass effect
                    Button(action: {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            if currentPage < onboardingPages.count - 1 {
                                currentPage += 1
                            } else {
                                appStateManager.completeOnboarding()
                            }
                        }
                    }) {
                        HStack {
                            Text(currentPage < onboardingPages.count - 1 ? "Continue" : "Get Started")
                                .font(.system(size: 17, weight: .semibold, design: .default))
                                .foregroundColor(.white)
                            
                            if currentPage < onboardingPages.count - 1 {
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(.white)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, MADTheme.Spacing.md)
                        .background(
                            ZStack {
                                // Gradient background
                                LinearGradient(
                                    colors: onboardingPages[currentPage].gradientColors,
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                                
                                // Glass overlay
                                RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                                    .fill(.ultraThinMaterial.opacity(0.2))
                            }
                        )
                        .cornerRadius(MADTheme.CornerRadius.large)
                        .shadow(color: onboardingPages[currentPage].accentColor.opacity(0.4), radius: 20, x: 0, y: 10)
                    }
                    .padding(.horizontal, MADTheme.Spacing.xl)
                    .padding(.bottom, MADTheme.Spacing.xxl)
                    .animation(.easeInOut(duration: 0.3), value: currentPage)
                }
                .opacity(contentOpacity)
            }
        }
        .onAppear {
            withAnimation(.easeIn(duration: 0.5).delay(0.2)) {
                contentOpacity = 1.0
            }
        }
    }
}

/// Individual onboarding page data
struct OnboardingPage {
    let icon: String
    let title: String
    let subtitle: String
    let accentColor: Color
    let gradientColors: [Color]
}

/// Onboarding page view with sleek design
struct OnboardingPageView: View {
    let page: OnboardingPage
    @State private var iconScale: CGFloat = 0.8
    @State private var iconRotation: Double = -5
    @State private var contentOffset: CGFloat = 30
    @State private var contentOpacity: Double = 0
    @State private var floatOffset: CGFloat = 0
    
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            
            // Sleek icon presentation with glass
            ZStack {
                // Background blur with glass effect
                Circle()
                    .fill(
                        LinearGradient(
                            colors: page.gradientColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 200, height: 200)
                    .blur(radius: 30)
                    .opacity(0.6)
                
                // Icon container with liquid glass
                ZStack {
                    // White background with glass
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 140, height: 140)
                        .shadow(color: Color.black.opacity(0.2), radius: 20, x: 0, y: 10)
                    
                    Image(systemName: page.icon)
                        .font(.system(size: 60, weight: .light, design: .default))
                        .foregroundColor(page.accentColor)
                }
                .scaleEffect(iconScale)
                .rotationEffect(.degrees(iconRotation))
                .offset(y: floatOffset)
            }
            .padding(.bottom, MADTheme.Spacing.xxxl)
            
            // Sleek text content
            VStack(spacing: MADTheme.Spacing.md) {
                Text(page.title)
                    .font(.system(size: 34, weight: .bold, design: .default))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .tracking(-0.5)
                    .shadow(color: Color.black.opacity(0.2), radius: 4, x: 0, y: 2)
                
                Text(page.subtitle)
                    .font(.system(size: 18, weight: .regular, design: .default))
                    .foregroundColor(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .lineLimit(nil)
                    .padding(.horizontal, MADTheme.Spacing.xl)
                    .lineSpacing(4)
                    .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
            }
            .offset(y: contentOffset)
            .opacity(contentOpacity)
            
            Spacer()
            Spacer()
        }
        .onAppear {
            startAnimations()
        }
    }
    
    private func startAnimations() {
        // Icon animation - smooth entry
        withAnimation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.1)) {
            iconScale = 1.0
            iconRotation = 0
        }
        
        // Subtle floating animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation(.easeInOut(duration: 3.0).repeatForever(autoreverses: true)) {
                floatOffset = -6
            }
        }
        
        // Content animation - smooth fade and slide
        withAnimation(.easeOut(duration: 0.6).delay(0.3)) {
            contentOffset = 0
            contentOpacity = 1.0
        }
    }
}

#Preview {
    OnboardingView()
        .environmentObject(AppStateManager())
}