import SwiftUI

struct OnboardingView: View {
    @Environment(\.appStateManager) var appStateManager
    @State private var currentPage = 0
    @State private var contentOpacity: Double = 0
    
    private let onboardingPages: [OnboardingPage] = [
        OnboardingPage(
            icon: "figure.run",
            title: "Track Your Daily Mile",
            subtitle: "Stay motivated by walking or running at least one mile every day",
            accentColor: MADTheme.Colors.madRed
        ),
        OnboardingPage(
            icon: "trophy.fill",
            title: "Earn Badges & Rewards",
            subtitle: "Unlock achievements as you build your daily fitness habit",
            accentColor: MADTheme.Colors.madRed
        ),
        OnboardingPage(
            icon: "person.2.fill",
            title: "Connect with Friends",
            subtitle: "Share your progress and compete with friends on the leaderboard",
            accentColor: MADTheme.Colors.madRed
        ),
        OnboardingPage(
            icon: "chart.line.uptrend.xyaxis",
            title: "Monitor Your Progress",
            subtitle: "View detailed stats and track your fitness journey over time",
            accentColor: MADTheme.Colors.madRed
        )
    ]
    
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
            
            VStack(spacing: 0) {
                // Skip button
                HStack {
                    Spacer()
                    
                    Button("Skip") {
                        appStateManager.completeOnboarding()
                    }
                    .madTertiaryButton()
                    .padding(.trailing, MADTheme.Spacing.lg)
                    .padding(.top, MADTheme.Spacing.md)
                }
                .opacity(contentOpacity)
                
                // Main content
                TabView(selection: $currentPage) {
                    ForEach(0..<onboardingPages.count, id: \.self) { index in
                        OnboardingPageView(page: onboardingPages[index])
                            .tag(index)
                    }
                }
                .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
                .opacity(contentOpacity)
                
                // Bottom section
                VStack(spacing: MADTheme.Spacing.xl) {
                    // Page indicator
                    PageIndicator(
                        currentPage: currentPage,
                        totalPages: onboardingPages.count
                    )
                    
                    // Navigation buttons
                    HStack(spacing: MADTheme.Spacing.lg) {
                        // Previous button
                        Button(action: {
                            withAnimation(MADTheme.Animation.standard) {
                                if currentPage > 0 {
                                    currentPage -= 1
                                }
                            }
                        }) {
                            Text("Previous")
                        }
                        .madSecondaryButton()
                        .opacity(currentPage > 0 ? 1 : 0.3)
                        .disabled(currentPage == 0)
                        
                        Spacer()
                        
                        // Next/Get Started button
                        Button(action: {
                            withAnimation(MADTheme.Animation.standard) {
                                if currentPage < onboardingPages.count - 1 {
                                    currentPage += 1
                                } else {
                                    appStateManager.completeOnboarding()
                                }
                            }
                        }) {
                            Text(currentPage == onboardingPages.count - 1 ? "Get Started" : "Next")
                        }
                        .madPrimaryButton()
                    }
                    .padding(.horizontal, MADTheme.Spacing.lg)
                }
                .opacity(contentOpacity)
                .padding(.bottom, MADTheme.Spacing.xl)
            }
        }
        .onAppear {
            withAnimation(MADTheme.Animation.standard.delay(0.3)) {
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
}

/// Onboarding page view
struct OnboardingPageView: View {
    let page: OnboardingPage
    @State private var iconScale: CGFloat = 0.5
    @State private var iconOpacity: Double = 0
    @State private var textOpacity: Double = 0
    @State private var decorationOffset: CGFloat = 100
    
    var body: some View {
        VStack(spacing: MADTheme.Spacing.xxxl) {
            Spacer()
            
            // Decorative elements
            ZStack {
                // Background circles
                Circle()
                    .fill(page.accentColor.opacity(0.1))
                    .frame(width: 200, height: 200)
                    .offset(x: decorationOffset * 0.3, y: -decorationOffset * 0.2)
                
                Circle()
                    .fill(page.accentColor.opacity(0.05))
                    .frame(width: 120, height: 120)
                    .offset(x: -decorationOffset * 0.4, y: decorationOffset * 0.3)
                
                // Main icon
                ZStack {
                    Circle()
                        .fill(page.accentColor.opacity(0.15))
                        .frame(width: 140, height: 140)
                    
                    Image(systemName: page.icon)
                        .font(.system(size: 50, weight: .medium))
                        .foregroundColor(page.accentColor)
                }
                .scaleEffect(iconScale)
                .opacity(iconOpacity)
            }
            .frame(height: 250)
            
            // Text content
            VStack(spacing: MADTheme.Spacing.lg) {
                Text(page.title)
                    .font(MADTheme.Typography.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(MADTheme.Colors.primaryText)
                    .multilineTextAlignment(.center)
                    .opacity(textOpacity)
                
                Text(page.subtitle)
                    .font(MADTheme.Typography.body)
                    .foregroundColor(MADTheme.Colors.secondaryText)
                    .multilineTextAlignment(.center)
                    .lineLimit(nil)
                    .padding(.horizontal, MADTheme.Spacing.xl)
                    .opacity(textOpacity)
            }
            
            Spacer()
        }
        .onAppear {
            startAnimations()
        }
    }
    
    private func startAnimations() {
        // Decoration animation
        withAnimation(MADTheme.Animation.slow) {
            decorationOffset = 0
        }
        
        // Icon animation
        withAnimation(MADTheme.Animation.bounce.delay(0.2)) {
            iconScale = 1.0
            iconOpacity = 1.0
        }
        
        // Text animation
        withAnimation(MADTheme.Animation.standard.delay(0.5)) {
            textOpacity = 1.0
        }
    }
}

/// Page indicator component
struct PageIndicator: View {
    let currentPage: Int
    let totalPages: Int
    
    var body: some View {
        HStack(spacing: MADTheme.Spacing.sm) {
            ForEach(0..<totalPages, id: \.self) { index in
                RoundedRectangle(cornerRadius: MADTheme.CornerRadius.small)
                    .fill(index == currentPage ? MADTheme.Colors.madRed : MADTheme.Colors.madRed.opacity(0.3))
                    .frame(
                        width: index == currentPage ? 24 : 8,
                        height: 8
                    )
                    .animation(MADTheme.Animation.standard, value: currentPage)
            }
        }
    }
}

/// Onboarding container with enhanced animations
struct AnimatedOnboardingView: View {
    @State private var showContent = false
    
    var body: some View {
        ZStack {
            if showContent {
                OnboardingView()
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
            }
        }
        .onAppear {
            withAnimation(MADTheme.Animation.standard) {
                showContent = true
            }
        }
    }
}

#Preview {
    OnboardingView()
        .environmentObject(AppStateManager())
}