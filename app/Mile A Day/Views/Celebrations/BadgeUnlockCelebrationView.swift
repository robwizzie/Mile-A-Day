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
    @State private var showRibbon = false
    @State private var showMedal = false
    @State private var medalScale: CGFloat = 0
    @State private var showIcon = false
    @State private var iconScale: CGFloat = 0
    @State private var iconRotation: Double = -30
    @State private var showRarityBanner = false
    @State private var showConfetti = false
    @State private var showRingPulse = false
    @State private var showContent = false
    @State private var showButtons = false
    @State private var showGlowRings = false
    @State private var shimmerPhase: CGFloat = -0.5
    @State private var glowPulse = false
    
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
        case .common: return 50
        case .rare: return 80
        case .legendary: return 130
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
                                size: 180 + CGFloat(index * 40)
                            )
                        }
                    }
                    
                    // Ring pulse effect
                    if showRingPulse {
                        RingPulseView(color: rarityColor)
                    }
                    
                    // Ambient glow
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    rarityColor.opacity(glowPulse ? 0.5 : 0.3),
                                    rarityColor.opacity(0)
                                ],
                                center: .center,
                                startRadius: 50,
                                endRadius: glowPulse ? 150 : 120
                            )
                        )
                        .frame(width: 300, height: 300)
                    
                    // Ribbon
                    if showRibbon {
                        VStack(spacing: 0) {
                            Rectangle()
                                .fill(
                                    LinearGradient(
                                        colors: [rarityColor, rarityColor.opacity(0.8)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .frame(width: 50, height: 70)
                            
                            HStack(spacing: 0) {
                                CelebrationRibbonTail(isLeft: true, color: rarityColor)
                                CelebrationRibbonTail(isLeft: false, color: rarityColor)
                            }
                            .frame(width: 50)
                        }
                        .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
                        .offset(y: -115)
                        .transition(.asymmetric(
                            insertion: .move(edge: .top).combined(with: .opacity),
                            removal: .opacity
                        ))
                    }
                    
                    // Medal container
                    ZStack {
                        // Outer decorative rings
                        ForEach(0..<3, id: \.self) { i in
                            Circle()
                                .stroke(rarityColor.opacity(0.2 - Double(i) * 0.05), lineWidth: 2)
                                .frame(width: 200 + CGFloat(i * 30), height: 200 + CGFloat(i * 30))
                        }
                        
                        // Main medal
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: medalGradient,
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 170, height: 170)
                            .overlay(
                                Circle()
                                    .stroke(
                                        LinearGradient(
                                            colors: [Color.white.opacity(0.7), rarityColor.opacity(0.4)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 4
                                    )
                            )
                            .shadow(color: rarityColor.opacity(0.6), radius: 30, x: 0, y: 15)
                        
                        // Inner decorative ring
                        Circle()
                            .stroke(Color.white.opacity(0.35), lineWidth: 2)
                            .frame(width: 140, height: 140)
                        
                        // Badge icon
                        Image(systemName: badgeIcon)
                            .font(.system(size: 80, weight: .semibold))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.white, .white.opacity(0.85)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .shadow(color: .black.opacity(0.35), radius: 5, x: 0, y: 4)
                            .scaleEffect(iconScale)
                            .rotationEffect(.degrees(iconRotation))
                            .opacity(showIcon ? 1 : 0)
                        
                        // Shimmer effect
                        if badge.rarity == .legendary {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [.clear, .white.opacity(0.4), .clear],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: 170, height: 170)
                                .offset(x: shimmerPhase * 200)
                                .clipShape(Circle())
                        }
                    }
                    .scaleEffect(medalScale)
                    .opacity(showMedal ? 1 : 0)
                    
                    // Sparkle particles around badge
                    if showContent {
                        BadgeSparkleRing(
                            color: badge.rarity == .legendary ? .yellow : .white,
                            count: badge.rarity == .legendary ? 10 : 6
                        )
                    }
                }
                
                Spacer()
                    .frame(height: 50)
                
                // Badge info content
                if showContent {
                    VStack(spacing: 20) {
                        // Achievement unlocked text
                        HStack(spacing: 8) {
                            Image(systemName: "trophy.fill")
                                .font(.system(size: 16))
                            Text("BADGE UNLOCKED!")
                                .font(.system(size: 16, weight: .black, design: .rounded))
                                .tracking(2)
                            Image(systemName: "trophy.fill")
                                .font(.system(size: 16))
                        }
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.yellow, .orange],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        
                        // Badge name with gradient
                        Text(badge.name)
                            .font(.system(size: 38, weight: .bold, design: .rounded))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.white, .white.opacity(0.85)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .multilineTextAlignment(.center)
                            .shadow(color: .black.opacity(0.4), radius: 8, x: 0, y: 4)
                        
                        // Achievement description
                        VStack(spacing: 10) {
                            Text("You achieved this by:")
                                .font(.system(size: 14, weight: .medium, design: .rounded))
                                .foregroundColor(.white.opacity(0.6))
                            
                            Text(badge.description)
                                .font(.system(size: 18, weight: .semibold, design: .rounded))
                                .foregroundColor(.white.opacity(0.9))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                        }
                        
                        // Date earned
                        HStack(spacing: 6) {
                            Image(systemName: "calendar")
                                .font(.system(size: 12))
                            Text("Earned \(badge.dateAwarded.formattedDate)")
                        }
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.45))
                        .padding(.top, 4)
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
                                Text("View All Badges")
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
        ZStack {
            // Base gradient
            LinearGradient(
                colors: [
                    rarityColor.opacity(0.85),
                    rarityColor.opacity(0.6),
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
                colors: [.clear, .black.opacity(0.6)],
                center: .center,
                startRadius: 100,
                endRadius: 450
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
        
        // Phase 4: Ribbon drops
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.75)) {
                showRibbon = true
            }
        }
        
        // Phase 5: Medal scales in
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.65)) {
                showMedal = true
                medalScale = 1.0
            }
            impactGenerator.impactOccurred(intensity: 0.8)
        }
        
        // Phase 6: Icon bursts in with rotation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
                showIcon = true
                iconScale = 1.0
                iconRotation = 0
            }
            impactGenerator.impactOccurred(intensity: 1.0)
        }
        
        // Phase 7: Ring pulse and glow rings
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.95) {
            showRingPulse = true
            withAnimation(.easeOut(duration: 0.3)) {
                showGlowRings = true
            }
        }
        
        // Phase 8: Confetti explosion
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.05) {
            showConfetti = true
            notificationGenerator.notificationOccurred(.success)
        }
        
        // Phase 9: Content reveals
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.75)) {
                showContent = true
            }
        }
        
        // Phase 10: Buttons appear
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                showButtons = true
            }
        }
        
        // Start continuous shimmer for legendary
        if badge.rarity == .legendary {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
                    shimmerPhase = 1.5
                }
            }
        }
        
        // Start glow pulse
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                glowPulse = true
            }
        }
    }
    
    private func triggerHaptic() {
        let impact = UIImpactFeedbackGenerator(style: .medium)
        impact.impactOccurred()
    }
}

// MARK: - Celebration Ribbon Tail

struct CelebrationRibbonTail: View {
    let isLeft: Bool
    let color: Color
    
    var body: some View {
        Path { path in
            let width: CGFloat = 25
            let height: CGFloat = 30
            
            path.move(to: CGPoint(x: 0, y: 0))
            path.addLine(to: CGPoint(x: width, y: 0))
            path.addLine(to: CGPoint(x: width, y: height))
            path.addLine(to: CGPoint(x: width * 0.5, y: height * 0.6))
            path.addLine(to: CGPoint(x: 0, y: height))
            path.closeSubpath()
        }
        .fill(
            LinearGradient(
                colors: [color, color.opacity(0.7)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .frame(width: 25, height: 30)
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
                    .frame(width: 170, height: 170)
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
                        x: cos(Double(index) * 2 * .pi / Double(count)) * 120,
                        y: sin(Double(index) * 2 * .pi / Double(count)) * 120
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
                .frame(width: 18, height: 3)
            
            // Vertical line
            Capsule()
                .fill(color)
                .frame(width: 3, height: 18)
            
            // Glow
            Circle()
                .fill(color.opacity(0.5))
                .frame(width: 10, height: 10)
                .blur(radius: 3)
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
