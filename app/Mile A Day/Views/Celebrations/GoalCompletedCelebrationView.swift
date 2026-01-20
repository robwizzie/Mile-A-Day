//
//  GoalCompletedCelebrationView.swift
//  Mile A Day
//
//  Created by Claude on 1/9/26.
//

import SwiftUI

struct GoalCompletedCelebrationView: View {
    @ObservedObject var manager = CelebrationManager.shared
    @State private var scale: CGFloat = 0.5
    @State private var opacity: Double = 0
    @State private var iconRotation: Double = 0
    @State private var showBurst = false
    @State private var showStars = false
    @State private var showContent = false

    var body: some View {
        ZStack {
            // Animated gradient background
            AnimatedGradientBackground()

            // Particle effects
            if showBurst {
                BurstEffect(
                    colors: [
                        Color(MADTheme.Colors.primary),
                        .orange,
                        .yellow,
                        .pink,
                        .purple
                    ],
                    particleCount: 40
                )
                .frame(height: 200)
            }

            if showStars {
                FloatingStarsEffect(
                    color: .yellow.opacity(0.8),
                    starCount: 25
                )
                .allowsHitTesting(false)
            }

            VStack(spacing: MADTheme.Spacing.xl) {
                Spacer()

                // Main icon with effects
                ZStack {
                    // Glow circles
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color(MADTheme.Colors.primary).opacity(0.3),
                                    .clear
                                ],
                                center: .center,
                                startRadius: 50,
                                endRadius: 100
                            )
                        )
                        .frame(width: 200, height: 200)
                        .pulseGlow(color: Color(MADTheme.Colors.primary), maxScale: 1.1)

                    // Icon background
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(MADTheme.Colors.primary),
                                    Color(MADTheme.Colors.primary).opacity(0.7)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 120, height: 120)
                        .shadow(color: Color(MADTheme.Colors.primary).opacity(0.5), radius: 20)

                    // Trophy icon
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.yellow, .orange],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .rotationEffect(.degrees(iconRotation))
                        .shimmer()

                    // Sparkles around icon
                    SparkleOverlay()
                }
                .scaleEffect(scale)
                .rotation3DEffect(
                    .degrees(showContent ? 0 : 180),
                    axis: (x: 0, y: 1, z: 0)
                )

                if showContent {
                    VStack(spacing: MADTheme.Spacing.md) {
                        // Title
                        Text("Goal Crushed!")
                            .font(.system(size: 42, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)

                        // Subtitle
                        Text("You've completed your daily mile!")
                            .font(.system(size: 18, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.9))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)

                        // Motivational message
                        Text("Keep the momentum going! 🔥")
                            .font(.system(size: 16, weight: .regular, design: .rounded))
                            .foregroundColor(.white.opacity(0.8))
                            .padding(.top, 4)
                    }
                    .transition(.scale.combined(with: .opacity))
                }

                Spacer()

                // Continue button
                if showContent {
                    Button(action: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            manager.dismissCurrentCelebration()
                        }
                    }) {
                        HStack(spacing: MADTheme.Spacing.sm) {
                            Text("Continue")
                                .font(.system(size: 20, weight: .semibold, design: .rounded))

                            Image(systemName: "arrow.right.circle.fill")
                                .font(.system(size: 20))
                        }
                        .foregroundColor(Color(MADTheme.Colors.primary))
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(
                            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                                .fill(.white)
                                .shadow(color: .black.opacity(0.2), radius: 15, x: 0, y: 5)
                        )
                        .padding(.horizontal, MADTheme.Spacing.xl)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                Spacer()
                    .frame(height: 60)
            }
        }
        .ignoresSafeArea()
        .opacity(opacity)
        .onAppear {
            animateIn()
        }
    }

    private func animateIn() {
        // Initial fade in
        withAnimation(.easeOut(duration: 0.3)) {
            opacity = 1
        }

        // Icon burst in
        withAnimation(.spring(response: 0.6, dampingFraction: 0.6).delay(0.1)) {
            scale = 1.0
        }

        // Icon rotation
        withAnimation(.spring(response: 0.8, dampingFraction: 0.7).delay(0.1)) {
            iconRotation = 360
        }

        // Burst effect
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            showBurst = true
        }

        // Stars effect
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            showStars = true
        }

        // Content appears
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                showContent = true
            }
        }
    }
}

// MARK: - Sparkle Overlay
struct SparkleOverlay: View {
    @State private var showSparkles = false

    var body: some View {
        ZStack {
            SparkleView(color: .yellow)
                .frame(width: 30, height: 30)
                .offset(x: -60, y: -60)
                .opacity(showSparkles ? 1 : 0)

            SparkleView(color: .orange)
                .frame(width: 25, height: 25)
                .offset(x: 60, y: -50)
                .opacity(showSparkles ? 1 : 0)

            SparkleView(color: .yellow)
                .frame(width: 20, height: 20)
                .offset(x: -50, y: 60)
                .opacity(showSparkles ? 1 : 0)

            SparkleView(color: .pink)
                .frame(width: 28, height: 28)
                .offset(x: 55, y: 55)
                .opacity(showSparkles ? 1 : 0)
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                showSparkles = true
            }
        }
    }
}

// MARK: - Animated Gradient Background
struct AnimatedGradientBackground: View {
    @State private var gradientStart = UnitPoint.topLeading
    @State private var gradientEnd = UnitPoint.bottomTrailing

    var body: some View {
        LinearGradient(
            colors: [
                Color(MADTheme.Colors.primary),
                Color(MADTheme.Colors.primary).opacity(0.8),
                .purple.opacity(0.6)
            ],
            startPoint: gradientStart,
            endPoint: gradientEnd
        )
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: true)) {
                gradientStart = .bottomLeading
                gradientEnd = .topTrailing
            }
        }
    }
}

#Preview {
    GoalCompletedCelebrationView()
}
