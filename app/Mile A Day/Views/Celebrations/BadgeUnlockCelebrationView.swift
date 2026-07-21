//
//  BadgeUnlockCelebrationView.swift
//  Mile A Day
//

import SwiftUI

struct BadgeUnlockCelebrationView: View {
    let badge: Badge
    @ObservedObject var manager = CelebrationManager.shared
    @Environment(\.scenePhase) private var scenePhase

    // Animation states
    @State private var overlayOpacity: Double = 0
    @State private var showMedal = false
    @State private var medalScale: CGFloat = 0
    @State private var showIcon = false
    @State private var iconScale: CGFloat = 0
    @State private var iconRotation: Double = -30
    @State private var showRarityBanner = false
    @State private var showConfetti = false
    @State private var showBurst = false
    @State private var showRays = false
    @State private var showContent = false
    @State private var showButtons = false
    @State private var hasStartedAnimation: Bool = false
    /// Rendered badge card presented in the system share sheet.
    @State private var shareItem: ShareableImage?
    
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
        case .common: return 36
        case .rare: return 55
        case .legendary: return 80
        }
    }

    // Rotating light rays behind the medal — reserved for rare/legendary so common
    // unlocks stay clean.
    var rayCount: Int {
        switch badge.rarity {
        case .common: return 0
        case .rare: return 10
        case .legendary: return 16
        }
    }
    
    // MARK: - Body
    
    var body: some View {
        GeometryReader { geo in
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

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        // HERO SECTION: rarity banner + medal + badge info centered
                        VStack(spacing: 0) {
                            Spacer(minLength: geo.safeAreaInsets.top + 60)

                            // Rarity banner at top
                            if showRarityBanner {
                                RarityBannerView(
                                    rarity: badge.rarity,
                                    rarityText: rarityText,
                                    rarityColor: rarityColor,
                                    rarityGradient: rarityGradient
                                )
                                .transition(.scale(scale: 0.8).combined(with: .opacity))
                                .padding(.bottom, 16)
                            }

                            // Badge display
                            ZStack {
                                // Rotating light rays (rare/legendary only)
                                if showRays && rayCount > 0 {
                                    LightRays(color: rarityColor, rayCount: rayCount)
                                        .frame(width: 340, height: 340)
                                        .transition(.opacity)
                                }

                                // Ambient glow
                                Circle()
                                    .fill(
                                        RadialGradient(
                                            colors: [rarityColor.opacity(0.4), rarityColor.opacity(0)],
                                            center: .center,
                                            startRadius: 40,
                                            endRadius: 130
                                        )
                                    )
                                    .frame(width: 240, height: 240)

                                // Radial burst at the reveal moment
                                if showBurst {
                                    BurstEffect(colors: confettiColors, particleCount: 26)
                                        .frame(width: 280, height: 280)
                                        .allowsHitTesting(false)
                                }

                                // Premium tiltable medal
                                TiltableMedal(badge: badge, size: 172)
                                    .scaleEffect(medalScale)
                                    .opacity(showMedal ? 1 : 0)
                            }

                            // Badge info content
                            if showContent {
                                VStack(spacing: 12) {
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

                                    // Achievement description
                                    Text(badge.description)
                                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                                        .foregroundColor(.white.opacity(0.9))
                                        .multilineTextAlignment(.center)
                                        .padding(.horizontal, 32)

                                    // Date earned
                                    HStack(spacing: 6) {
                                        Image(systemName: "calendar")
                                            .font(.system(size: 11))
                                        Text("Earned \(badge.dateAwarded.formattedDate)")
                                    }
                                    .font(.system(size: 12, weight: .medium, design: .rounded))
                                    .foregroundColor(.white.opacity(0.4))
                                }
                                .padding(.top, 16)
                                .transition(.asymmetric(
                                    insertion: .scale(scale: 0.9).combined(with: .opacity).combined(with: .offset(y: 20)),
                                    removal: .opacity
                                ))
                            }

                            Spacer(minLength: 20)
                        }
                        .frame(minHeight: geo.size.height * 0.65)

                        // BELOW-FOLD: buttons
                        VStack(spacing: 14) {
                            if showButtons {
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

                                Button {
                                    triggerHaptic()
                                    if let image = renderAchievementShareImage(BadgeShareCardView(badge: badge)) {
                                        shareItem = ShareableImage(image: image)
                                    }
                                } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: "square.and.arrow.up")
                                            .font(.system(size: 17, weight: .semibold))
                                        Text("Share")
                                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                                    }
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 52)
                                    .background(
                                        RoundedRectangle(cornerRadius: 14)
                                            .fill(.white.opacity(0.12))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 14)
                                                    .stroke(.white.opacity(0.2), lineWidth: 1)
                                            )
                                    )
                                }
                                .sheet(item: $shareItem) { item in
                                    ShareSheet(items: [item.image])
                                }

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
                            }

                            // Clear the floating tab bar + home indicator so the
                            // buttons are reachable when scrolled to the bottom
                            // (the celebration ignores the safe area).
                            Spacer(minLength: geo.safeAreaInsets.bottom + 60)
                        }
                        .padding(.horizontal, 32)
                        .padding(.top, 8)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .ignoresSafeArea()
            .opacity(overlayOpacity)
            .onAppear {
                startAnimationIfActive()
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active && !hasStartedAnimation {
                    startAnimationIfActive()
                }
            }
        }
    }

    private func startAnimationIfActive() {
        guard !hasStartedAnimation else { return }
        guard scenePhase == .active else { return }
        hasStartedAnimation = true
        startCelebrationSequence()
    }

    // MARK: - Background View
    
    private var badgeBackgroundView: some View {
        ZStack {
            // Solid dark base — fully opaque so dashboard doesn't bleed through
            Color(red: 0.05, green: 0.03, blue: 0.08)

            // Rarity-colored gradient overlay
            LinearGradient(
                colors: [
                    rarityColor.opacity(0.5),
                    rarityColor.opacity(0.2),
                    Color.clear
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            // Radial glow behind medal area
            RadialGradient(
                colors: [
                    rarityColor.opacity(0.3),
                    rarityColor.opacity(0.1),
                    Color.clear
                ],
                center: UnitPoint(x: 0.5, y: 0.35),
                startRadius: 10,
                endRadius: 250
            )
        }
        .ignoresSafeArea()
    }
    
    // MARK: - Badge Icon
    
    private var badgeIcon: String {
        // Shared resolver (PinnedBadgesShowcase.swift) covers every category,
        // incl. story / hype / competition badges.
        iconName(for: badge)
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

        // Phase 2: Light rays fade in behind, then the medal punches in with a burst.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.easeOut(duration: 0.6)) { showRays = true }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.52)) {
                showMedal = true
                medalScale = 1.0
            }
            showBurst = true
            notificationGenerator.notificationOccurred(.success)
            impactGenerator.impactOccurred(intensity: 1.0)
        }

        // Phase 3: Confetti rains down
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
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


// MARK: - Light Rays

/// Slowly rotating volumetric light rays behind the medal. Masked to fade out at
/// the center (behind the medal) and the edges so it reads as a soft halo of
/// god-rays rather than a hard pinwheel.
struct LightRays: View {
    let color: Color
    var rayCount: Int = 12

    @State private var angle: Double = 0

    private var rayColors: [Color] {
        (0..<max(1, rayCount)).flatMap { _ in [color.opacity(0), color.opacity(0.32)] }
    }

    var body: some View {
        AngularGradient(gradient: Gradient(colors: rayColors), center: .center)
            .blur(radius: 5)
            .mask(
                RadialGradient(
                    colors: [.clear, .white, .clear],
                    center: .center,
                    startRadius: 50,
                    endRadius: 170
                )
            )
            .blendMode(.screen)
            .rotationEffect(.degrees(angle))
            .onAppear {
                withAnimation(.linear(duration: 18).repeatForever(autoreverses: false)) {
                    angle = 360
                }
            }
            .allowsHitTesting(false)
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
                        shape: CelebrationConfettiShape.allCases.randomElement() ?? .rectangle
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
    let shape: CelebrationConfettiShape
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
            CelebrationTriangle().fill(particle.color)
        case .roundedSquare:
            RoundedRectangle(cornerRadius: 2).fill(particle.color)
        }
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
