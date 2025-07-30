import SwiftUI

struct OnboardingView: View {
    @Environment(\.appStateManager) var appStateManager
    @State private var currentPage = 0
    @State private var contentOpacity: Double = 0
    @State private var backgroundAnimation: Double = 0
    
    private let onboardingPages: [OnboardingPage] = [
        OnboardingPage(
            icon: "figure.run",
            title: "Start Your Mile Journey",
            subtitle: "Turn your daily mile into an adventure! Track, celebrate, and make every step count.",
            accentColor: MADTheme.Colors.madRed,
            backgroundColor: MADTheme.Colors.vibrantRedGradient,
            decorativeElements: ["circle.fill", "star.fill", "heart.fill"]
        ),
        OnboardingPage(
            icon: "trophy.fill",
            title: "Unlock Amazing Badges",
            subtitle: "Collect beautiful achievements and show off your dedication with our reward system.",
            accentColor: MADTheme.Colors.accentYellow,
            backgroundColor: MADTheme.Colors.vibrantRedGradient,
            decorativeElements: ["diamond.fill", "crown.fill", "gem"]
        ),
        OnboardingPage(
            icon: "person.2.fill",
            title: "Connect & Compete",
            subtitle: "Join a community of champions! Challenge friends and climb the leaderboard together.",
            accentColor: MADTheme.Colors.accentPink,
            backgroundColor: MADTheme.Colors.vibrantRedGradient,
            decorativeElements: ["hands.clap.fill", "sparkles", "party.popper.fill"]
        ),
        OnboardingPage(
            icon: "chart.line.uptrend.xyaxis",
            title: "Track Your Success",
            subtitle: "Beautiful insights and progress tracking keep you motivated on your fitness journey.",
            accentColor: MADTheme.Colors.accentOrange,
            backgroundColor: MADTheme.Colors.vibrantRedGradient,
            decorativeElements: ["chart.bar.fill", "target", "bolt.fill"]
        )
    ]
    
    var body: some View {
        ZStack {
            // Dynamic animated background
            AnimatedBackground(page: currentPage)
                .ignoresSafeArea()
            
            // Floating decorative elements
            FloatingElements()
                .opacity(contentOpacity * 0.6)
            
            VStack(spacing: 0) {
                // Enhanced skip button
                HStack {
                    Spacer()
                    
                    Button("Skip") {
                        appStateManager.completeOnboarding()
                    }
                    .font(MADTheme.Typography.headline)
                    .foregroundColor(.white)
                    .padding(.horizontal, MADTheme.Spacing.lg)
                    .padding(.vertical, MADTheme.Spacing.sm)
                    .background(
                        Capsule()
                            .fill(.white.opacity(0.2))
                            .background(
                                Capsule()
                                    .stroke(.white.opacity(0.3), lineWidth: 1)
                            )
                    )
                    .padding(.trailing, MADTheme.Spacing.lg)
                    .padding(.top, MADTheme.Spacing.md)
                }
                .opacity(contentOpacity)
                
                // Main content with enhanced design
                TabView(selection: $currentPage) {
                    ForEach(0..<onboardingPages.count, id: \.self) { index in
                        EnhancedOnboardingPageView(
                            page: onboardingPages[index],
                            isActive: currentPage == index
                        )
                        .tag(index)
                    }
                }
                .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
                .opacity(contentOpacity)
                
                // Enhanced bottom section with vibrant design
                VStack(spacing: MADTheme.Spacing.xl) {
                    // Modern page indicator
                    ModernPageIndicator(
                        currentPage: currentPage,
                        totalPages: onboardingPages.count
                    )
                    
                    // Vibrant navigation buttons
                    HStack(spacing: MADTheme.Spacing.lg) {
                        // Previous button with glass effect
                        Button(action: {
                            withAnimation(MADTheme.Animation.bounce) {
                                if currentPage > 0 {
                                    currentPage -= 1
                                }
                            }
                        }) {
                            HStack(spacing: MADTheme.Spacing.sm) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 16, weight: .semibold))
                                Text("Back")
                                    .font(MADTheme.Typography.headline)
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, MADTheme.Spacing.lg)
                            .padding(.vertical, MADTheme.Spacing.md)
                            .background(
                                Capsule()
                                    .fill(.white.opacity(0.15))
                                    .background(
                                        Capsule()
                                            .stroke(.white.opacity(0.3), lineWidth: 1)
                                    )
                            )
                        }
                        .opacity(currentPage > 0 ? 1 : 0.3)
                        .disabled(currentPage == 0)
                        .scaleEffect(currentPage > 0 ? 1 : 0.9)
                        .animation(MADTheme.Animation.bounce, value: currentPage)
                        
                        Spacer()
                        
                        // Next/Get Started button with vibrant gradient
                        Button(action: {
                            withAnimation(MADTheme.Animation.bounce) {
                                if currentPage < onboardingPages.count - 1 {
                                    currentPage += 1
                                } else {
                                    appStateManager.completeOnboarding()
                                }
                            }
                        }) {
                            HStack(spacing: MADTheme.Spacing.sm) {
                                Text(currentPage == onboardingPages.count - 1 ? "Get Started" : "Next")
                                    .font(MADTheme.Typography.headline)
                                    .fontWeight(.bold)
                                
                                if currentPage == onboardingPages.count - 1 {
                                    Image(systemName: "sparkles")
                                        .font(.system(size: 16, weight: .semibold))
                                } else {
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 16, weight: .semibold))
                                }
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, MADTheme.Spacing.xl)
                            .padding(.vertical, MADTheme.Spacing.md)
                            .background(
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                .white.opacity(0.9),
                                                .white.opacity(0.7)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
                            )
                        }
                        .foregroundColor(MADTheme.Colors.madRed)
                        .scaleEffect(1.05)
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
                backgroundAnimation = 1.0
            }
        }
        .onChange(of: currentPage) { _ in
            // Add subtle haptic feedback
            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
            impactFeedback.impactOccurred()
        }
    }
}

// MARK: - Enhanced Components

/// Animated background that changes with pages
struct AnimatedBackground: View {
    let page: Int
    @State private var animationOffset: CGFloat = 0
    
    var body: some View {
        ZStack {
            // Base gradient background
            MADTheme.Colors.vibrantRedGradient
            
            // Animated decorative shapes
            ForEach(0..<8, id: \.self) { index in
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                .white.opacity(0.1),
                                .white.opacity(0.05)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: CGFloat.random(in: 60...120))
                    .offset(
                        x: CGFloat.random(in: -200...200) + animationOffset,
                        y: CGFloat.random(in: -300...300) + sin(animationOffset * 0.01 + Double(index)) * 50
                    )
                    .blur(radius: 1)
            }
        }
        .onAppear {
            withAnimation(
                .linear(duration: 20)
                .repeatForever(autoreverses: false)
            ) {
                animationOffset = 400
            }
        }
    }
}

/// Floating decorative elements
struct FloatingElements: View {
    @State private var isAnimating = false
    
    var body: some View {
        ZStack {
            ForEach(0..<6, id: \.self) { index in
                Image(systemName: ["star.fill", "heart.fill", "sparkles", "bolt.fill", "flame.fill", "leaf.fill"][index])
                    .font(.system(size: CGFloat.random(in: 12...20)))
                    .foregroundColor(.white.opacity(0.3))
                    .offset(
                        x: CGFloat.random(in: -150...150),
                        y: CGFloat.random(in: -200...200) + (isAnimating ? -20 : 20)
                    )
                    .animation(
                        .easeInOut(duration: Double.random(in: 2...4))
                        .repeatForever(autoreverses: true)
                        .delay(Double(index) * 0.3),
                        value: isAnimating
                    )
            }
        }
        .onAppear {
            isAnimating = true
        }
    }
}

/// Enhanced onboarding page view
struct EnhancedOnboardingPageView: View {
    let page: OnboardingPage
    let isActive: Bool
    @State private var iconScale: CGFloat = 0.5
    @State private var iconRotation: Double = 0
    @State private var textOpacity: Double = 0
    @State private var decorationOffset: CGFloat = 100
    @State private var shimmerPosition: CGFloat = -200
    
    var body: some View {
        VStack(spacing: MADTheme.Spacing.xxxl) {
            Spacer()
            
            // Enhanced visual section
            ZStack {
                // Animated background elements
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    page.accentColor.opacity(0.2),
                                    page.accentColor.opacity(0.05)
                                ],
                                center: .center,
                                startRadius: 10,
                                endRadius: 100
                            )
                        )
                        .frame(width: CGFloat(120 + index * 40))
                        .offset(
                            x: decorationOffset * CGFloat(0.3 - Double(index) * 0.2),
                            y: -decorationOffset * CGFloat(0.2 + Double(index) * 0.1)
                        )
                        .rotationEffect(.degrees(iconRotation + Double(index * 120)))
                }
                
                // Main icon with enhanced styling
                ZStack {
                    // Glow effect
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    .white.opacity(0.8),
                                    .white.opacity(0.3),
                                    .clear
                                ],
                                center: .center,
                                startRadius: 20,
                                endRadius: 80
                            )
                        )
                        .frame(width: 160, height: 160)
                        .blur(radius: 2)
                    
                    // Icon background
                    Circle()
                        .fill(.white)
                        .frame(width: 140, height: 140)
                        .shadow(color: .black.opacity(0.1), radius: 20, x: 0, y: 10)
                    
                    // Main icon
                    Image(systemName: page.icon)
                        .font(.system(size: 50, weight: .medium))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [page.accentColor, page.accentColor.opacity(0.7)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    
                    // Shimmer effect
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    .clear,
                                    .white.opacity(0.4),
                                    .clear
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: 30, height: 140)
                        .offset(x: shimmerPosition)
                        .mask(Circle().frame(width: 140, height: 140))
                }
                .scaleEffect(iconScale)
                .rotationEffect(.degrees(iconRotation * 0.1))
            }
            .frame(height: 280)
            
            // Enhanced text content
            VStack(spacing: MADTheme.Spacing.lg) {
                Text(page.title)
                    .font(MADTheme.Typography.onboardingTitle)
                    .fontWeight(.heavy)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .opacity(textOpacity)
                    .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
                
                Text(page.subtitle)
                    .font(MADTheme.Typography.onboardingSubtitle)
                    .foregroundColor(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .lineLimit(nil)
                    .lineSpacing(4)
                    .padding(.horizontal, MADTheme.Spacing.xl)
                    .opacity(textOpacity)
                    .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
            }
            
            Spacer()
        }
        .onAppear {
            if isActive {
                startAnimations()
            }
        }
        .onChange(of: isActive) { active in
            if active {
                startAnimations()
            }
        }
    }
    
    private func startAnimations() {
        // Reset animations
        iconScale = 0.5
        iconRotation = 0
        textOpacity = 0
        decorationOffset = 100
        shimmerPosition = -200
        
        // Decoration animation
        withAnimation(MADTheme.Animation.bounce.delay(0.1)) {
            decorationOffset = 0
        }
        
        // Icon scale animation
        withAnimation(MADTheme.Animation.bounce.delay(0.3)) {
            iconScale = 1.0
        }
        
        // Icon rotation animation
        withAnimation(
            .linear(duration: 8)
            .repeatForever(autoreverses: false)
            .delay(0.5)
        ) {
            iconRotation = 360
        }
        
        // Text animation
        withAnimation(MADTheme.Animation.standard.delay(0.6)) {
            textOpacity = 1.0
        }
        
        // Shimmer effect
        withAnimation(
            .linear(duration: 2)
            .repeatForever(autoreverses: false)
            .delay(1.0)
        ) {
            shimmerPosition = 200
        }
    }
}

/// Modern page indicator
struct ModernPageIndicator: View {
    let currentPage: Int
    let totalPages: Int
    
    var body: some View {
        HStack(spacing: MADTheme.Spacing.sm) {
            ForEach(0..<totalPages, id: \.self) { index in
                RoundedRectangle(cornerRadius: MADTheme.CornerRadius.small)
                    .fill(
                        index == currentPage
                            ? .white
                            : .white.opacity(0.4)
                    )
                    .frame(
                        width: index == currentPage ? 32 : 8,
                        height: 8
                    )
                    .shadow(
                        color: index == currentPage ? .black.opacity(0.2) : .clear,
                        radius: 4,
                        x: 0,
                        y: 2
                    )
                    .animation(MADTheme.Animation.bounce, value: currentPage)
            }
        }
    }
}

// MARK: - Data Models

/// Enhanced onboarding page data
struct OnboardingPage {
    let icon: String
    let title: String
    let subtitle: String
    let accentColor: Color
    let backgroundColor: LinearGradient
    let decorativeElements: [String]
}

// MARK: - Preview

#Preview {
    OnboardingView()
        .environmentObject(AppStateManager())
}