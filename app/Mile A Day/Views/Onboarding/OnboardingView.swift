import SwiftUI

struct OnboardingView: View {
    @Environment(\.appStateManager) var appStateManager
    @Environment(\.colorScheme) private var colorScheme
    @State private var currentPage = 0
    @State private var contentOpacity: Double = 0

    private let onboardingPages: [OnboardingPage] = [
        OnboardingPage(
            icon: "figure.run",
            title: "Walk or Run One Mile",
            subtitle: "Every day, do at least one mile.\nThat's it.",
            accentColor: Color(red: 0.85, green: 0.25, blue: 0.35)
        ),
        OnboardingPage(
            icon: "flame.fill",
            title: "Build Your Streak",
            subtitle: "Keep moving every single day\nto keep your streak alive.",
            accentColor: Color(red: 1.0, green: 0.5, blue: 0.0)
        ),
        OnboardingPage(
            icon: "person.2.fill",
            title: "Stay Motivated",
            subtitle: "Connect with friends and see\nwho's leading the pack.",
            accentColor: Color(red: 0.2, green: 0.7, blue: 0.9)
        )
    ]

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

    private var primaryTextColor: Color {
        colorScheme == .dark ? .white : Color(red: 0.12, green: 0.12, blue: 0.14)
    }

    private var secondaryTextColor: Color {
        colorScheme == .dark ? .white.opacity(0.7) : Color(red: 0.45, green: 0.43, blue: 0.47)
    }

    var body: some View {
        ZStack {
            backgroundColor
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Skip button
                HStack {
                    Spacer()
                    Button("Skip") {
                        appStateManager.completeOnboarding()
                    }
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(secondaryTextColor)
                    .padding(.trailing, MADTheme.Spacing.lg)
                    .padding(.top, MADTheme.Spacing.lg)
                }
                .opacity(contentOpacity)

                // Main content
                TabView(selection: $currentPage) {
                    ForEach(0..<onboardingPages.count, id: \.self) { index in
                        OnboardingPageView(
                            page: onboardingPages[index],
                            primaryTextColor: primaryTextColor,
                            secondaryTextColor: secondaryTextColor
                        )
                        .tag(index)
                    }
                }
                .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
                .opacity(contentOpacity)

                // Bottom controls
                VStack(spacing: MADTheme.Spacing.lg) {
                    // Page indicator
                    HStack(spacing: 8) {
                        ForEach(0..<onboardingPages.count, id: \.self) { index in
                            Capsule()
                                .fill(index == currentPage
                                    ? onboardingPages[currentPage].accentColor
                                    : (colorScheme == .dark ? Color.white.opacity(0.25) : Color.black.opacity(0.15)))
                                .frame(width: index == currentPage ? 28 : 8, height: 8)
                                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: currentPage)
                        }
                    }

                    // Continue / Get Started button
                    Button(action: {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            if currentPage < onboardingPages.count - 1 {
                                currentPage += 1
                            } else {
                                appStateManager.completeOnboarding()
                            }
                        }
                    }) {
                        HStack(spacing: 8) {
                            Text(currentPage < onboardingPages.count - 1 ? "Continue" : "Get Started")
                                .font(.system(size: 17, weight: .semibold, design: .rounded))

                            if currentPage < onboardingPages.count - 1 {
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 14, weight: .semibold))
                            }
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(MADTheme.Colors.madRed)
                        )
                        .shadow(color: MADTheme.Colors.madRed.opacity(0.3), radius: 12, x: 0, y: 6)
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

// MARK: - Data Model

struct OnboardingPage {
    let icon: String
    let title: String
    let subtitle: String
    let accentColor: Color
}

// MARK: - Page View

struct OnboardingPageView: View {
    let page: OnboardingPage
    let primaryTextColor: Color
    let secondaryTextColor: Color
    @State private var iconScale: CGFloat = 0.8
    @State private var contentOffset: CGFloat = 20
    @State private var contentOpacity: Double = 0
    @State private var floatOffset: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Icon
            ZStack {
                // Soft glow
                Circle()
                    .fill(page.accentColor.opacity(0.15))
                    .frame(width: 180, height: 180)
                    .blur(radius: 25)

                // Icon circle
                Circle()
                    .fill(page.accentColor.opacity(0.12))
                    .frame(width: 130, height: 130)
                    .overlay(
                        Circle()
                            .stroke(page.accentColor.opacity(0.2), lineWidth: 1)
                    )

                Image(systemName: page.icon)
                    .font(.system(size: 52, weight: .medium))
                    .foregroundColor(page.accentColor)
            }
            .scaleEffect(iconScale)
            .offset(y: floatOffset)
            .padding(.bottom, MADTheme.Spacing.xxxl)

            // Text
            VStack(spacing: MADTheme.Spacing.md) {
                Text(page.title)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(primaryTextColor)
                    .multilineTextAlignment(.center)

                Text(page.subtitle)
                    .font(.system(size: 17, weight: .regular, design: .rounded))
                    .foregroundColor(secondaryTextColor)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }
            .padding(.horizontal, MADTheme.Spacing.xl)
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
        withAnimation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.1)) {
            iconScale = 1.0
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation(.easeInOut(duration: 3.0).repeatForever(autoreverses: true)) {
                floatOffset = -6
            }
        }

        withAnimation(.easeOut(duration: 0.5).delay(0.25)) {
            contentOffset = 0
            contentOpacity = 1.0
        }
    }
}

#Preview("Dark") {
    OnboardingView()
        .environmentObject(AppStateManager())
        .preferredColorScheme(.dark)
}

#Preview("Light") {
    OnboardingView()
        .environmentObject(AppStateManager())
        .preferredColorScheme(.light)
}
