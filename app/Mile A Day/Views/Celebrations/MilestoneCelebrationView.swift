//
//  MilestoneCelebrationView.swift
//  Mile A Day
//

import SwiftUI

struct MilestoneCelebrationView: View {
    let title: String
    let description: String
    let icon: String

    @ObservedObject var manager = CelebrationManager.shared
    @State private var scale: CGFloat = 0.5
    @State private var opacity: Double = 0
    @State private var iconRotation: Double = 0
    @State private var showBurst = false
    @State private var showStars = false
    @State private var showContent = false

    var body: some View {
        ZStack {
            // Gradient background
            LinearGradient(
                colors: [
                    Color(MADTheme.Colors.primary),
                    .purple.opacity(0.8),
                    .indigo.opacity(0.9)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            // Particle effects
            if showBurst {
                BurstEffect(
                    colors: [
                        Color(MADTheme.Colors.primary),
                        .purple,
                        .pink,
                        .orange,
                        .yellow
                    ],
                    particleCount: 35
                )
                .frame(height: 220)
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
                                    .purple.opacity(0.3),
                                    .clear
                                ],
                                center: .center,
                                startRadius: 50,
                                endRadius: 100
                            )
                        )
                        .frame(width: 200, height: 200)
                        .pulseGlow(color: .purple, maxScale: 1.1)

                    // Icon background
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    .purple,
                                    .purple.opacity(0.7)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 120, height: 120)
                        .shadow(color: .purple.opacity(0.5), radius: 20)

                    // Custom icon
                    Image(systemName: icon)
                        .font(.system(size: 60))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.white, .white.opacity(0.8)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .rotationEffect(.degrees(iconRotation))
                        .shimmer()

                    // Sparkles
                    MilestoneSparkleOverlay()
                }
                .scaleEffect(scale)
                .rotation3DEffect(
                    .degrees(showContent ? 0 : 180),
                    axis: (x: 0, y: 1, z: 0)
                )

                if showContent {
                    VStack(spacing: MADTheme.Spacing.md) {
                        // Title
                        Text(title)
                            .font(.system(size: 38, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                            .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
                            .padding(.horizontal)

                        // Description
                        Text(description)
                            .font(.system(size: 18, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.9))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, MADTheme.Spacing.xl)
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
                        .foregroundColor(.purple)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(
                            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                                .fill(.white)
                                .shadow(color: .purple.opacity(0.3), radius: 20, x: 0, y: 8)
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

// MARK: - Milestone Sparkle Overlay
struct MilestoneSparkleOverlay: View {
    @State private var showSparkles = false

    var body: some View {
        ZStack {
            ForEach(0..<4, id: \.self) { index in
                SparkleView(color: .white)
                    .frame(width: 25, height: 25)
                    .offset(
                        x: cos(Double(index) * .pi / 2) * 75,
                        y: sin(Double(index) * .pi / 2) * 75
                    )
                    .opacity(showSparkles ? 1 : 0)
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                showSparkles = true
            }
        }
    }
}

#Preview {
    MilestoneCelebrationView(
        title: "Milestone Reached!",
        description: "You've hit an amazing milestone. Keep going!",
        icon: "star.circle.fill"
    )
}
