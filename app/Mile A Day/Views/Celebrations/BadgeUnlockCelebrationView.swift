//
//  BadgeUnlockCelebrationView.swift
//  Mile A Day
//
//  Created by Claude on 1/9/26.
//

import SwiftUI

struct BadgeUnlockCelebrationView: View {
    let badge: Badge
    @ObservedObject var manager = CelebrationManager.shared

    @State private var scale: CGFloat = 0.3
    @State private var opacity: Double = 0
    @State private var badgeOpacity: Double = 0
    @State private var badgeScale: CGFloat = 0
    @State private var showBurst = false
    @State private var showStars = false
    @State private var showContent = false
    @State private var showRarityLabel = false
    @State private var rotation: Double = 0

    var rarityColor: Color {
        switch badge.rarity {
        case .common:
            return .blue
        case .rare:
            return .purple
        case .legendary:
            return .orange
        }
    }

    var rarityColors: [Color] {
        switch badge.rarity {
        case .common:
            return [.blue, .cyan]
        case .rare:
            return [.purple, .pink]
        case .legendary:
            return [.orange, .yellow, .red]
        }
    }

    var rarityText: String {
        switch badge.rarity {
        case .common:
            return "COMMON"
        case .rare:
            return "RARE"
        case .legendary:
            return "LEGENDARY"
        }
    }

    var particleCount: Int {
        switch badge.rarity {
        case .common:
            return 25
        case .rare:
            return 40
        case .legendary:
            return 60
        }
    }

    var body: some View {
        ZStack {
            // Background based on rarity
            rarityBackgroundView

            // Particle effects
            if showBurst {
                BurstEffect(
                    colors: rarityColors,
                    particleCount: particleCount
                )
                .frame(height: 250)
            }

            if showStars {
                FloatingStarsEffect(
                    color: rarityColor,
                    starCount: badge.rarity == .legendary ? 35 : 20
                )
                .allowsHitTesting(false)
            }

            VStack(spacing: MADTheme.Spacing.xl) {
                Spacer()

                // Rarity label
                if showRarityLabel {
                    Text(rarityText)
                        .font(.system(size: 14, weight: .black, design: .rounded))
                        .tracking(2)
                        .foregroundColor(.white.opacity(0.9))
                        .padding(.horizontal, MADTheme.Spacing.md)
                        .padding(.vertical, MADTheme.Spacing.xs)
                        .background(
                            Capsule()
                                .fill(rarityColor.opacity(0.3))
                                .overlay(
                                    Capsule()
                                        .stroke(rarityColor, lineWidth: 2)
                                )
                        )
                        .transition(.scale.combined(with: .opacity))
                }

                // Badge display
                ZStack {
                    // Outer glow rings
                    if badge.rarity == .legendary {
                        ForEach(0..<3) { index in
                            Circle()
                                .stroke(
                                    rarityColor.opacity(0.3),
                                    lineWidth: 3
                                )
                                .frame(width: 180 + CGFloat(index * 30), height: 180 + CGFloat(index * 30))
                                .pulseGlow(color: rarityColor, maxScale: 1.05)
                        }
                    }

                    // Glow effect
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    rarityColor.opacity(0.4),
                                    .clear
                                ],
                                center: .center,
                                startRadius: 60,
                                endRadius: 120
                            )
                        )
                        .frame(width: 240, height: 240)
                        .pulseGlow(color: rarityColor, maxScale: 1.08)

                    // Badge circle background
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    rarityColor,
                                    rarityColor.opacity(0.7)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 140, height: 140)
                        .shadow(color: rarityColor.opacity(0.5), radius: 25)
                        .scaleEffect(scale)

                    // Badge icon
                    Image(systemName: badgeIcon(for: badge))
                        .font(.system(size: 70))
                        .foregroundColor(.white)
                        .scaleEffect(badgeScale)
                        .opacity(badgeOpacity)
                        .rotationEffect(.degrees(rotation))
                        .if(badge.rarity == .legendary) { view in
                            view.shimmer()
                        }

                    // Sparkles
                    if badge.rarity != .common {
                        BadgeSparkleOverlay(rarity: badge.rarity)
                    }
                }
                .rotation3DEffect(
                    .degrees(showContent ? 0 : 180),
                    axis: (x: 0, y: 1, z: 0)
                )

                if showContent {
                    VStack(spacing: MADTheme.Spacing.md) {
                        // Badge unlocked text
                        Text("Badge Unlocked!")
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)

                        // Badge name
                        Text(badge.name)
                            .font(.system(size: 24, weight: .semibold, design: .rounded))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: rarityColors,
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)

                        // Badge description
                        Text(badge.description)
                            .font(.system(size: 16, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.85))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, MADTheme.Spacing.xl)
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
                            Text("Awesome!")
                                .font(.system(size: 20, weight: .semibold, design: .rounded))

                            Image(systemName: "star.fill")
                                .font(.system(size: 18))
                        }
                        .foregroundColor(rarityColor)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(
                            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                                .fill(.white)
                                .shadow(color: rarityColor.opacity(0.3), radius: 20, x: 0, y: 8)
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

    private var rarityBackgroundView: some View {
        Group {
            if badge.rarity == .legendary {
                // Animated multi-color gradient for legendary
                AnimatedLegendaryBackground()
            } else {
                // Standard gradient for common/rare
                LinearGradient(
                    colors: [
                        rarityColor,
                        rarityColor.opacity(0.7),
                        .black.opacity(0.8)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
            }
        }
    }

    private func animateIn() {
        // Fade in background
        withAnimation(.easeOut(duration: 0.3)) {
            opacity = 1
        }

        // Show rarity label
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                showRarityLabel = true
            }
        }

        // Badge background scale in
        withAnimation(.spring(response: 0.7, dampingFraction: 0.6).delay(0.3)) {
            scale = 1.0
        }

        // Badge icon appears with rotation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                badgeScale = 1.0
                badgeOpacity = 1.0
            }
            withAnimation(.easeOut(duration: 0.8)) {
                rotation = 360
            }
        }

        // Burst effect
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            showBurst = true
        }

        // Stars effect
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            showStars = true
        }

        // Content appears
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                showContent = true
            }
        }
    }

    private func badgeIcon(for badge: Badge) -> String {
        // Return appropriate icon based on badge type
        if badge.name.contains("Streak") || badge.name.contains("Day") {
            return "flame.fill"
        } else if badge.name.contains("Miles") && !badge.name.contains("Sub") {
            return "figure.run"
        } else if badge.name.contains("Sub") {
            return "bolt.fill"
        } else if badge.name.contains("Marathon") || badge.name.contains("Half") {
            return "figure.run.circle.fill"
        } else {
            return "star.fill"
        }
    }
}

// MARK: - Badge Sparkle Overlay
struct BadgeSparkleOverlay: View {
    let rarity: BadgeRarity
    @State private var showSparkles = false

    var sparkleColor: Color {
        rarity == .legendary ? .yellow : .white
    }

    var sparkleCount: Int {
        rarity == .legendary ? 6 : 4
    }

    var body: some View {
        ZStack {
            ForEach(0..<sparkleCount, id: \.self) { index in
                SparkleView(color: sparkleColor)
                    .frame(width: 25, height: 25)
                    .offset(
                        x: cos(Double(index) * 2 * .pi / Double(sparkleCount)) * 80,
                        y: sin(Double(index) * 2 * .pi / Double(sparkleCount)) * 80
                    )
                    .opacity(showSparkles ? 1 : 0)
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                showSparkles = true
            }
        }
    }
}

// MARK: - Animated Legendary Background
struct AnimatedLegendaryBackground: View {
    @State private var gradientOffset: CGFloat = 0

    var body: some View {
        ZStack {
            // Base gradient
            LinearGradient(
                colors: [
                    .orange,
                    .red,
                    .purple
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Animated overlay
            LinearGradient(
                colors: [
                    .yellow.opacity(0.3),
                    .orange.opacity(0.5),
                    .red.opacity(0.3)
                ],
                startPoint: .init(x: 0, y: gradientOffset),
                endPoint: .init(x: 1, y: 1 - gradientOffset)
            )
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.linear(duration: 3).repeatForever(autoreverses: true)) {
                gradientOffset = 1
            }
        }
    }
}

// MARK: - Conditional View Modifier
extension View {
    @ViewBuilder func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

#Preview {
    BadgeUnlockCelebrationView(
        badge: Badge(
            id: "test",
            name: "100 Day Streak",
            description: "Completed your daily mile for 100 days in a row",
            dateAwarded: Date()
        )
    )
}
