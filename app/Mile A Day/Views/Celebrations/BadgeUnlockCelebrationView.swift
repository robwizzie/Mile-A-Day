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
    @State private var showRaysBackground = false
    @State private var showBadgeContainer = false
    @State private var badgeContainerScale: CGFloat = 0
    @State private var showBadgeIcon = false
    @State private var badgeIconScale: CGFloat = 0
    @State private var badgeIconRotation: Double = -30
    @State private var showRarityBanner = false
    @State private var showConfetti = false
    @State private var showRingPulse = false
    @State private var showContent = false
    @State private var showButtons = false
    @State private var showGlowRings = false
    @State private var shimmerPhase: CGFloat = 0
    @State private var continuousRotation: Double = 0
    
    // Haptic generators
    private let impactGenerator = UIImpactFeedbackGenerator(style: .heavy)
    private let notificationGenerator = UINotificationFeedbackGenerator()
    
    // MARK: - Rarity Properties
    
    var rarityColor: Color {
        switch badge.rarity {
        case .common: return Color(red: 0.2, green: 0.6, blue: 1.0)
        case .rare: return Color(red: 0.7, green: 0.3, blue: 0.9)
        case .legendary: return Color(red: 1.0, green: 0.7, blue: 0.2)
        }
    }
    
    var rarityGradient: [Color] {
        switch badge.rarity {
        case .common:
            return [Color(red: 0.3, green: 0.7, blue: 1.0), Color(red: 0.1, green: 0.4, blue: 0.8)]
        case .rare:
            return [Color(red: 0.8, green: 0.4, blue: 1.0), Color(red: 0.5, green: 0.2, blue: 0.8)]
        case .legendary:
            return [Color(red: 1.0, green: 0.85, blue: 0.4), Color(red: 1.0, green: 0.5, blue: 0.2)]
        }
    }
    
    var rarityText: String {
        switch badge.rarity {
        case .common: return "COMMON"
        case .rare: return "RARE"
        case .legendary: return "LEGENDARY"
        }
    }
    
    var confettiCount: Int {
        switch badge.rarity {
        case .common: return 40
        case .rare: return 70
        case .legendary: return 120
        }
    }
    
    var ringCount: Int {
        switch badge.rarity {
        case .common: return 2
        case .rare: return 3
        case .legendary: return 5
        }
    }
    
    // MARK: - Body
    
    var body: some View {
        ZStack {
            // Dynamic gradient background
            badgeBackgroundView
            
            // Animated ray burst background
            if showRaysBackground {
                RayBurstView(color: rarityColor)
                    .opacity(badge.rarity == .legendary ? 0.4 : 0.25)
            }
            
            // Confetti explosion
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
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity).combined(with: .scale(scale: 0.8)),
                        removal: .opacity
                    ))
                }
                
                Spacer()
                
                // Badge display with effects
                ZStack {
                    // Animated glow rings
                    if showGlowRings {
                        ForEach(0..<ringCount, id: \.self) { index in
                            GlowRingView(
                                color: rarityColor,
                                delay: Double(index) * 0.15,
                                size: 160 + CGFloat(index * 40)
                            )
                        }
                    }
                    
                    // Ring pulse effect
                    if showRingPulse {
                        RingPulseView(color: rarityColor)
                    }
                    
                    // Badge container (background circle)
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: rarityGradient,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 160, height: 160)
                        .shadow(color: rarityColor.opacity(0.6), radius: 30, x: 0, y: 10)
                        .overlay(
                            Circle()
                                .stroke(
                                    LinearGradient(
                                        colors: [.white.opacity(0.6), .clear],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 3
                                )
                        )
                        .scaleEffect(badgeContainerScale)
                        .opacity(showBadgeContainer ? 1 : 0)
                    
                    // Badge icon
                    Image(systemName: badgeIcon)
                        .font(.system(size: 80, weight: .medium))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.3), radius: 5, x: 0, y: 3)
                        .scaleEffect(badgeIconScale)
                        .rotationEffect(.degrees(badgeIconRotation))
                        .opacity(showBadgeIcon ? 1 : 0)
                        .overlay(
                            // Shimmer effect for legendary
                            badge.rarity == .legendary ? legendaryShimmerOverlay : nil
                        )
                    
                    // Sparkle particles around badge
                    if showContent {
                        BadgeSparkleRing(
                            color: badge.rarity == .legendary ? .yellow : .white,
                            count: badge.rarity == .legendary ? 8 : 5
                        )
                    }
                }
                .rotation3DEffect(
                    .degrees(showContent ? 0 : -180),
                    axis: (x: 0, y: 1, z: 0),
                    perspective: 0.5
                )
                
                Spacer()
                    .frame(height: 40)
                
                // Badge info content
                if showContent {
                    VStack(spacing: 16) {
                        // Achievement unlocked text
                        Text("🏆 BADGE UNLOCKED! 🏆")
                            .font(.system(size: 16, weight: .black, design: .rounded))
                            .tracking(2)
                            .foregroundColor(.white.opacity(0.9))
                        
                        // Badge name with gradient
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
                        
                        // Achievement description (how they unlocked it)
                        VStack(spacing: 8) {
                            Text("You achieved this by:")
                                .font(.system(size: 14, weight: .medium, design: .rounded))
                                .foregroundColor(.white.opacity(0.7))
                            
                            Text(badge.description)
                                .font(.system(size: 18, weight: .semibold, design: .rounded))
                                .foregroundColor(.white)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                        }
                        .padding(.top, 4)
                        
                        // Date earned
                        if !badge.isLocked {
                            Text("Earned \(badge.dateAwarded.formattedDate)")
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundColor(.white.opacity(0.5))
                                .padding(.top, 4)
                        }
                    }
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.9).combined(with: .opacity).combined(with: .offset(y: 30)),
                        removal: .opacity
                    ))
                }
                
                Spacer()
                
                // Action buttons
                if showButtons {
                    VStack(spacing: 12) {
                        // View All Badges button
                        Button {
                            triggerHaptic()
                            manager.dismissWithAction(.viewBadges)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "trophy.fill")
                                    .font(.system(size: 18, weight: .semibold))
                                Text("View All Badges")
                                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                            }
                            .foregroundColor(rarityColor)
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(.white)
                                    .shadow(color: rarityColor.opacity(0.3), radius: 15, x: 0, y: 8)
                            )
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
                                    .font(.system(size: 17, weight: .medium, design: .rounded))
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            .foregroundColor(.white.opacity(0.9))
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(.white.opacity(0.15))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14)
                                            .stroke(.white.opacity(0.3), lineWidth: 1)
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
                
                Spacer()
                    .frame(height: 50)
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
        ZStack {
            // Base gradient
            LinearGradient(
                colors: [
                    rarityColor.opacity(0.9),
                    rarityColor.opacity(0.7),
                    Color.black.opacity(0.95)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            
            // Animated mesh for legendary
            if badge.rarity == .legendary {
                AnimatedMeshBackground(colors: rarityGradient)
            }
            
            // Vignette overlay
            RadialGradient(
                colors: [.clear, .black.opacity(0.5)],
                center: .center,
                startRadius: 150,
                endRadius: 400
            )
        }
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
    
    // MARK: - Shimmer Overlay
    
    @ViewBuilder
    private var legendaryShimmerOverlay: some View {
        Image(systemName: badgeIcon)
            .font(.system(size: 80, weight: .medium))
            .foregroundStyle(
                LinearGradient(
                    colors: [.clear, .white.opacity(0.4), .clear],
                    startPoint: UnitPoint(x: shimmerPhase - 0.5, y: 0),
                    endPoint: UnitPoint(x: shimmerPhase + 0.5, y: 1)
                )
            )
            .onAppear {
                withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
                    shimmerPhase = 1.5
                }
            }
    }
    
    // MARK: - Animation Sequence
    
    private func startCelebrationSequence() {
        // Prepare haptics
        impactGenerator.prepare()
        notificationGenerator.prepare()
        
        // Phase 1: Fade in overlay and background
        withAnimation(.easeOut(duration: 0.3)) {
            overlayOpacity = 1
        }
        
        // Phase 2: Ray burst background
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(.easeOut(duration: 0.4)) {
                showRaysBackground = true
            }
        }
        
        // Phase 3: Rarity banner drops in
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                showRarityBanner = true
            }
            impactGenerator.impactOccurred(intensity: 0.5)
        }
        
        // Phase 4: Badge container scales in
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.65)) {
                showBadgeContainer = true
                badgeContainerScale = 1.0
            }
            impactGenerator.impactOccurred(intensity: 0.7)
        }
        
        // Phase 5: Badge icon bursts in with rotation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
                showBadgeIcon = true
                badgeIconScale = 1.0
                badgeIconRotation = 0
            }
            impactGenerator.impactOccurred(intensity: 1.0)
        }
        
        // Phase 6: Ring pulse and glow rings
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            showRingPulse = true
            withAnimation(.easeOut(duration: 0.3)) {
                showGlowRings = true
            }
        }
        
        // Phase 7: Confetti explosion
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            showConfetti = true
            notificationGenerator.notificationOccurred(.success)
        }
        
        // Phase 8: Content reveals with 3D flip
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.75)) {
                showContent = true
            }
        }
        
        // Phase 9: Buttons appear
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
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
        HStack(spacing: 8) {
            Image(systemName: rarityIcon)
                .font(.system(size: 14, weight: .bold))
            
            Text(rarityText)
                .font(.system(size: 14, weight: .black, design: .rounded))
                .tracking(3)
            
            Image(systemName: rarityIcon)
                .font(.system(size: 14, weight: .bold))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
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

// MARK: - Ray Burst View

struct RayBurstView: View {
    let color: Color
    @State private var rotation: Double = 0
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(0..<16, id: \.self) { index in
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [color, color.opacity(0)],
                                startPoint: .center,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width, height: 3)
                        .rotationEffect(.degrees(Double(index) * 22.5 + rotation))
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
        .onAppear {
            withAnimation(.linear(duration: 20).repeatForever(autoreverses: false)) {
                rotation = 360
            }
        }
    }
}

// MARK: - Glow Ring View

struct GlowRingView: View {
    let color: Color
    let delay: Double
    let size: CGFloat
    
    @State private var scale: CGFloat = 0.8
    @State private var opacity: Double = 0
    
    var body: some View {
        Circle()
            .stroke(
                color.opacity(0.4),
                lineWidth: 2
            )
            .frame(width: size, height: size)
            .scaleEffect(scale)
            .opacity(opacity)
            .onAppear {
                withAnimation(.easeOut(duration: 1.5).delay(delay).repeatForever(autoreverses: false)) {
                    scale = 1.3
                    opacity = 0
                }
                // Initial state
                withAnimation(.easeIn(duration: 0.3).delay(delay)) {
                    opacity = 0.6
                }
            }
    }
}

// MARK: - Ring Pulse View

struct RingPulseView: View {
    let color: Color
    @State private var scale: CGFloat = 1
    @State private var opacity: Double = 1
    
    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .stroke(color, lineWidth: 4)
                    .frame(width: 160, height: 160)
                    .scaleEffect(scale)
                    .opacity(opacity)
                    .animation(
                        .easeOut(duration: 1.2)
                            .delay(Double(index) * 0.3),
                        value: scale
                    )
            }
        }
        .onAppear {
            scale = 2.5
            opacity = 0
        }
    }
}

// MARK: - Badge Sparkle Ring

struct BadgeSparkleRing: View {
    let color: Color
    let count: Int
    
    @State private var isAnimating = false
    
    var body: some View {
        ZStack {
            ForEach(0..<count, id: \.self) { index in
                SparkleParticle(color: color)
                    .offset(
                        x: cos(Double(index) * 2 * .pi / Double(count)) * 100,
                        y: sin(Double(index) * 2 * .pi / Double(count)) * 100
                    )
                    .opacity(isAnimating ? 1 : 0)
                    .scaleEffect(isAnimating ? 1 : 0)
                    .animation(
                        .spring(response: 0.5, dampingFraction: 0.6)
                            .delay(Double(index) * 0.08),
                        value: isAnimating
                    )
            }
        }
        .onAppear {
            isAnimating = true
        }
    }
}

// MARK: - Sparkle Particle

struct SparkleParticle: View {
    let color: Color
    @State private var twinkle = false
    
    var body: some View {
        ZStack {
            // Horizontal line
            Capsule()
                .fill(color)
                .frame(width: 16, height: 3)
            
            // Vertical line
            Capsule()
                .fill(color)
                .frame(width: 3, height: 16)
            
            // Glow
            Circle()
                .fill(color.opacity(0.5))
                .frame(width: 8, height: 8)
                .blur(radius: 2)
        }
        .scaleEffect(twinkle ? 1.2 : 0.8)
        .opacity(twinkle ? 1 : 0.6)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                twinkle = true
            }
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

// MARK: - Animated Mesh Background (Legendary)

struct AnimatedMeshBackground: View {
    let colors: [Color]
    @State private var animate = false
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(0..<5, id: \.self) { index in
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [colors[index % colors.count].opacity(0.6), .clear],
                                center: .center,
                                startRadius: 0,
                                endRadius: 200
                            )
                        )
                        .frame(width: 300, height: 300)
                        .offset(
                            x: animate ? meshOffset(for: index, in: geo.size).x : -meshOffset(for: index, in: geo.size).x,
                            y: animate ? meshOffset(for: index, in: geo.size).y : -meshOffset(for: index, in: geo.size).y
                        )
                        .blur(radius: 50)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 5).repeatForever(autoreverses: true)) {
                animate = true
            }
        }
    }
    
    private func meshOffset(for index: Int, in size: CGSize) -> CGPoint {
        let angles: [Double] = [0, 72, 144, 216, 288]
        let angle = angles[index] * .pi / 180
        let radius = Double(min(size.width, size.height) * 0.3)
        return CGPoint(
            x: cos(angle) * radius,
            y: sin(angle) * radius
        )
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
