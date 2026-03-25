//
//  BadgeUnlockCelebrationView.swift
//  Mile A Day
//

import SwiftUI

struct BadgeUnlockCelebrationView: View {
    let badge: Badge
    @ObservedObject var manager = CelebrationManager.shared
    
    // Animation states
    @State private var overlayOpacity: Double = 0
    @State private var showMedal = false
    @State private var medalScale: CGFloat = 0
    @State private var showIcon = false
    @State private var iconScale: CGFloat = 0
    @State private var iconRotation: Double = -30
    @State private var showRarityBanner = false
    @State private var showConfetti = false
    @State private var showContent = false
    @State private var showButtons = false
    
    // Haptic generators
    private let impactGenerator = UIImpactFeedbackGenerator(style: .heavy)
    private let notificationGenerator = UINotificationFeedbackGenerator()
    
    // MARK: - Rarity Properties
    
    var rarityColor: Color {
        badge.rarity.color
    }
    
    var rarityGradient: [Color] {
        switch badge.rarity {
        case .common:
            return [Color(red: 0.5, green: 0.7, blue: 1.0), Color(red: 0.35, green: 0.55, blue: 0.85)]
        case .rare:
            return [Color(red: 0.75, green: 0.55, blue: 0.95), Color(red: 0.55, green: 0.35, blue: 0.8)]
        case .legendary:
            return [Color(red: 1.0, green: 0.88, blue: 0.45), Color(red: 0.9, green: 0.6, blue: 0.18)]
        }
    }
    
    var medalGradient: [Color] {
        switch badge.rarity {
        case .legendary:
            return [
                Color(red: 1.0, green: 0.88, blue: 0.45),
                Color(red: 0.9, green: 0.6, blue: 0.18)
            ]
        case .rare:
            return [
                Color(red: 0.75, green: 0.55, blue: 0.95),
                Color(red: 0.55, green: 0.35, blue: 0.8)
            ]
        case .common:
            return [
                Color(red: 0.5, green: 0.7, blue: 1.0),
                Color(red: 0.35, green: 0.55, blue: 0.85)
            ]
        }
    }
    
    var rarityText: String {
        badge.rarity.rawValue.uppercased()
    }
    
    var confettiCount: Int {
        switch badge.rarity {
        case .common: return 20
        case .rare: return 30
        case .legendary: return 40
        }
    }

    var ringCount: Int {
        switch badge.rarity {
        case .common: return 1
        case .rare: return 2
        case .legendary: return 3
        }
    }
    
    // MARK: - Body
    
    var body: some View {
        ZStack {
            // Dynamic gradient background
            badgeBackgroundView

            // Confetti
            if showConfetti {
                ConfettiCannon(
                    colors: confettiColors,
                    particleCount: confettiCount
                )
                .allowsHitTesting(false)
            }

            // Main content
            VStack(spacing: 0) {
                Spacer()

                // Rarity banner at top
                if showRarityBanner {
                    RarityBannerView(
                        rarity: badge.rarity,
                        rarityText: rarityText,
                        rarityColor: rarityColor,
                        rarityGradient: rarityGradient
                    )
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
                }

                Spacer()

                // Badge display
                ZStack {
                    // Subtle ambient glow
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [rarityColor.opacity(0.35), rarityColor.opacity(0)],
                                center: .center,
                                startRadius: 50,
                                endRadius: 130
                            )
                        )
                        .frame(width: 280, height: 280)

                    // Medal
                    ZStack {
                        // Main medal
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: medalGradient,
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 160, height: 160)
                            .overlay(
                                Circle()
                                    .stroke(
                                        LinearGradient(
                                            colors: [Color.white.opacity(0.6), rarityColor.opacity(0.3)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 3
                                    )
                            )
                            .shadow(color: rarityColor.opacity(0.5), radius: 20, x: 0, y: 10)

                        // Inner ring
                        Circle()
                            .stroke(Color.white.opacity(0.3), lineWidth: 1.5)
                            .frame(width: 130, height: 130)

                        // Badge icon
                        Image(systemName: badgeIcon)
                            .font(.system(size: 64, weight: .semibold))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.white, .white.opacity(0.85)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 3)
                            .scaleEffect(iconScale)
                            .rotationEffect(.degrees(iconRotation))
                            .opacity(showIcon ? 1 : 0)
                    }
                    .scaleEffect(medalScale)
                    .opacity(showMedal ? 1 : 0)
                }
                
                Spacer()
                    .frame(height: 50)
                
                // Badge info content
                if showContent {
                    VStack(spacing: 16) {
                        // Achievement unlocked banner
                        HStack(spacing: 8) {
                            Image(systemName: "trophy.fill")
                                .font(.system(size: 14))
                            Text("BADGE UNLOCKED")
                                .font(.system(size: 13, weight: .black, design: .rounded))
                                .tracking(2.5)
                            Image(systemName: "trophy.fill")
                                .font(.system(size: 14))
                        }
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.yellow, .orange],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(Color.yellow.opacity(0.1))
                                .overlay(
                                    Capsule()
                                        .stroke(Color.yellow.opacity(0.2), lineWidth: 1)
                                )
                        )

                        // Badge name
                        Text(badge.name)
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.white, .white.opacity(0.85)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .multilineTextAlignment(.center)
                            .shadow(color: .black.opacity(0.4), radius: 8, x: 0, y: 4)

                        // Achievement description in a card
                        VStack(spacing: 8) {
                            Text(badge.description)
                                .font(.system(size: 17, weight: .semibold, design: .rounded))
                                .foregroundColor(.white.opacity(0.9))
                                .multilineTextAlignment(.center)
                        }
                        .padding(.horizontal, 32)

                        // Date earned
                        HStack(spacing: 6) {
                            Image(systemName: "calendar")
                                .font(.system(size: 11))
                            Text("Earned \(badge.dateAwarded.formattedDate)")
                        }
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.4))
                        .padding(.top, 2)
                    }
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.9).combined(with: .opacity).combined(with: .offset(y: 30)),
                        removal: .opacity
                    ))
                }
                
                Spacer()
                    .frame(minHeight: 20)

                // Action buttons
                if showButtons {
                    VStack(spacing: 14) {
                        // View All Badges button
                        Button {
                            triggerHaptic()
                            manager.dismissWithAction(.viewBadges)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "trophy.fill")
                                    .font(.system(size: 18, weight: .semibold))
                                Text("View All Medals")
                                    .font(.system(size: 17, weight: .bold, design: .rounded))
                            }
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(
                                        LinearGradient(
                                            colors: rarityGradient,
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16)
                                            .stroke(Color.white.opacity(0.3), lineWidth: 1)
                                    )
                            )
                            .shadow(color: rarityColor.opacity(0.4), radius: 15, x: 0, y: 8)
                        }
                        .padding(.horizontal, 32)
                        
                        // Continue button
                        Button {
                            triggerHaptic()
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                manager.dismissCurrentCelebration()
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Text("Continue")
                                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 14, weight: .bold))
                            }
                            .foregroundColor(.white.opacity(0.9))
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(.white.opacity(0.12))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14)
                                            .stroke(.white.opacity(0.2), lineWidth: 1)
                                    )
                            )
                        }
                        .padding(.horizontal, 32)
                    }
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .opacity
                    ))
                }

                // Safe area spacing for bottom (tab bar + home indicator)
                Spacer()
                    .frame(height: 100)
            }
        }
        .ignoresSafeArea()
        .opacity(overlayOpacity)
        .onAppear {
            startCelebrationSequence()
        }
    }
    
    // MARK: - Background View
    
    private var badgeBackgroundView: some View {
        LinearGradient(
            colors: [
                rarityColor.opacity(0.8),
                rarityColor.opacity(0.5),
                Color.black.opacity(0.95)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
    
    // MARK: - Badge Icon
    
    private var badgeIcon: String {
        if badge.id.starts(with: "streak_") || badge.id.starts(with: "consistency_") {
            return "flame.fill"
        } else if badge.id.starts(with: "miles_") {
            return "figure.run"
        } else if badge.id.starts(with: "pace_") {
            return "bolt.fill"
        } else if badge.id.starts(with: "daily_") {
            return "figure.run.circle.fill"
        } else if badge.id.starts(with: "hidden_") || badge.id.starts(with: "secret_") || badge.id.starts(with: "special_") {
            return "sparkles"
        } else {
            return "star.fill"
        }
    }
    
    // MARK: - Confetti Colors
    
    private var confettiColors: [Color] {
        switch badge.rarity {
        case .common:
            return [.blue, .cyan, .white, .mint]
        case .rare:
            return [.purple, .pink, .blue, .indigo, .white]
        case .legendary:
            return [.yellow, .orange, .red, .pink, .white, .gold]
        }
    }
    
    // MARK: - Animation Sequence

    private func startCelebrationSequence() {
        notificationGenerator.prepare()

        // Phase 1: Fade in + rarity banner
        withAnimation(.easeOut(duration: 0.25)) {
            overlayOpacity = 1
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                showRarityBanner = true
            }
        }

        // Phase 2: Medal + icon appear together
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.55)) {
                showMedal = true
                medalScale = 1.0
            }
            notificationGenerator.notificationOccurred(.success)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.5)) {
                showIcon = true
                iconScale = 1.0
                iconRotation = 0
            }
            impactGenerator.impactOccurred(intensity: 0.8)
        }

        // Phase 3: Confetti
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            showConfetti = true
        }

        // Phase 4: Content
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                showContent = true
            }
        }

        // Phase 5: Buttons
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                showButtons = true
            }
        }
    }
    
    private func triggerHaptic() {
        let impact = UIImpactFeedbackGenerator(style: .medium)
        impact.impactOccurred()
    }
}

// MARK: - Gold Color Extension

extension Color {
    static let gold = Color(red: 1.0, green: 0.84, blue: 0.0)
}

// MARK: - Rarity Banner View

struct RarityBannerView: View {
    let rarity: BadgeRarity
    let rarityText: String
    let rarityColor: Color
    let rarityGradient: [Color]
    
    @State private var shimmer: CGFloat = -1
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: rarityIcon)
                .font(.system(size: 14, weight: .bold))
            
            Text(rarityText)
                .font(.system(size: 15, weight: .black, design: .rounded))
                .tracking(3)
            
            Image(systemName: rarityIcon)
                .font(.system(size: 14, weight: .bold))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 28)
        .padding(.vertical, 12)
        .background(
            Capsule()
                .fill(
                    LinearGradient(
                        colors: rarityGradient,
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .overlay(
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [.clear, .white.opacity(0.4), .clear],
                                startPoint: UnitPoint(x: shimmer, y: 0.5),
                                endPoint: UnitPoint(x: shimmer + 0.5, y: 0.5)
                            )
                        )
                )
                .overlay(
                    Capsule()
                        .stroke(.white.opacity(0.4), lineWidth: 1)
                )
        )
        .shadow(color: rarityColor.opacity(0.5), radius: 15, x: 0, y: 5)
        .onAppear {
            withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
                shimmer = 2
            }
        }
    }
    
    private var rarityIcon: String {
        switch rarity {
        case .common: return "circle.fill"
        case .rare: return "diamond.fill"
        case .legendary: return "star.fill"
        }
    }
}


// MARK: - Confetti Cannon

struct ConfettiCannon: View {
    let colors: [Color]
    let particleCount: Int
    
    @State private var particles: [ConfettiParticle] = []
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(particles) { particle in
                    ConfettiPiece(particle: particle, screenHeight: geo.size.height)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .onAppear {
                particles = (0..<particleCount).map { _ in
                    ConfettiParticle(
                        color: colors.randomElement() ?? .white,
                        x: CGFloat.random(in: 0...geo.size.width),
                        startY: -50,
                        size: CGFloat.random(in: 8...16),
                        rotation: Double.random(in: 0...360),
                        delay: Double.random(in: 0...0.8),
                        duration: Double.random(in: 2.5...4.0),
                        swayAmount: CGFloat.random(in: -60...60),
                        shape: ConfettiShape.allCases.randomElement() ?? .rectangle
                    )
                }
            }
        }
    }
}

struct ConfettiParticle: Identifiable {
    let id = UUID()
    let color: Color
    let x: CGFloat
    let startY: CGFloat
    let size: CGFloat
    let rotation: Double
    let delay: Double
    let duration: Double
    let swayAmount: CGFloat
    let shape: ConfettiShape
}

enum ConfettiShape: CaseIterable {
    case rectangle, circle, triangle
}

struct ConfettiPiece: View {
    let particle: ConfettiParticle
    let screenHeight: CGFloat
    
    @State private var offset: CGFloat = 0
    @State private var currentRotation: Double = 0
    @State private var swayOffset: CGFloat = 0
    @State private var opacity: Double = 1
    
    var body: some View {
        confettiShapeView
            .frame(width: particle.size, height: particle.size * 1.5)
            .rotationEffect(.degrees(currentRotation))
            .offset(x: particle.x + swayOffset, y: particle.startY + offset)
            .opacity(opacity)
            .onAppear {
                withAnimation(.easeIn(duration: particle.duration).delay(particle.delay)) {
                    offset = screenHeight + 100
                    opacity = 0
                }
                withAnimation(.linear(duration: particle.duration).delay(particle.delay).repeatForever(autoreverses: false)) {
                    currentRotation = particle.rotation + 720
                }
                withAnimation(.easeInOut(duration: 0.8).delay(particle.delay).repeatForever(autoreverses: true)) {
                    swayOffset = particle.swayAmount
                }
            }
    }
    
    @ViewBuilder
    private var confettiShapeView: some View {
        switch particle.shape {
        case .rectangle:
            Rectangle().fill(particle.color)
        case .circle:
            Circle().fill(particle.color)
        case .triangle:
            Triangle().fill(particle.color)
        }
    }
}

struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

// MARK: - Preview

#Preview("Common Badge") {
    BadgeUnlockCelebrationView(
        badge: Badge(
            id: "streak_7",
            name: "Week Warrior",
            description: "7 day streak!",
            dateAwarded: Date()
        )
    )
}

#Preview("Rare Badge") {
    BadgeUnlockCelebrationView(
        badge: Badge(
            id: "streak_100",
            name: "Century Club",
            description: "100 day streak!",
            dateAwarded: Date()
        )
    )
}

#Preview("Legendary Badge") {
    BadgeUnlockCelebrationView(
        badge: Badge(
            id: "streak_365",
            name: "Year Warrior",
            description: "365 day streak!",
            dateAwarded: Date()
        )
    )
}
