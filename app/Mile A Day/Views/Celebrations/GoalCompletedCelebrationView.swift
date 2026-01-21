//
//  GoalCompletedCelebrationView.swift
//  Mile A Day
//

import SwiftUI

// MARK: - Goal Completed Celebration View
// Note: GoalCompletionStats and StreakMilestone are defined in CelebrationManager.swift

struct GoalCompletedCelebrationView: View {
    @ObservedObject var manager = CelebrationManager.shared
    var stats: GoalCompletionStats = .placeholder
    
    // Animation states
    @State private var overlayOpacity: Double = 0
    @State private var showBackground = false
    @State private var showFireworks = false
    @State private var showMainIcon = false
    @State private var mainIconScale: CGFloat = 0
    @State private var mainIconRotation: Double = -180
    @State private var showTitle = false
    @State private var showStats = false
    @State private var showStreakBanner = false
    @State private var showMotivation = false
    @State private var showButtons = false
    @State private var confettiTrigger = false
    @State private var pulseAnimation = false
    @State private var shimmerPhase: CGFloat = -1
    
    // Haptic generators
    private let impactHeavy = UIImpactFeedbackGenerator(style: .heavy)
    private let impactMedium = UIImpactFeedbackGenerator(style: .medium)
    private let notification = UINotificationFeedbackGenerator()
    
    var body: some View {
        ZStack {
            // Animated gradient background
            celebrationBackground
            
            // Fireworks particle effect
            if showFireworks {
                FireworksView()
                    .allowsHitTesting(false)
            }
            
            // Main confetti
            if confettiTrigger {
                CelebrationConfetti()
                    .allowsHitTesting(false)
            }
            
            // Content
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    Spacer(minLength: 60)
                    
                    // Main trophy/checkmark icon
                    mainIconView
                    
                    Spacer(minLength: 30)
                    
                    // Title section
                    if showTitle {
                        titleSection
                            .transition(.asymmetric(
                                insertion: .scale(scale: 0.8).combined(with: .opacity).combined(with: .offset(y: 20)),
                                removal: .opacity
                            ))
                    }
                    
                    Spacer(minLength: 24)
                    
                    // Stats cards
                    if showStats {
                        statsSection
                            .transition(.asymmetric(
                                insertion: .scale(scale: 0.9).combined(with: .opacity).combined(with: .offset(y: 30)),
                                removal: .opacity
                            ))
                    }
                    
                    // Streak milestone banner (if applicable)
                    if showStreakBanner, let milestone = stats.streakMilestone {
                        streakMilestoneBanner(milestone)
                            .transition(.asymmetric(
                                insertion: .scale(scale: 0.8).combined(with: .opacity),
                                removal: .opacity
                            ))
                            .padding(.top, 16)
                    }
                    
                    // Motivational message
                    if showMotivation {
                        motivationSection
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .offset(y: 20)),
                                removal: .opacity
                            ))
                            .padding(.top, 20)
                    }
                    
                    Spacer(minLength: 24)
                    
                    // Action buttons
                    if showButtons {
                        buttonSection
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    
                    Spacer(minLength: 50)
                }
                .padding(.horizontal, 24)
            }
        }
        .ignoresSafeArea()
        .opacity(overlayOpacity)
        .onAppear {
            startCelebrationSequence()
        }
    }
    
    // MARK: - Background
    
    private var celebrationBackground: some View {
        ZStack {
            // Base gradient
            LinearGradient(
                colors: [
                    Color(red: 0.85, green: 0.25, blue: 0.35),
                    Color(red: 0.7, green: 0.2, blue: 0.3),
                    Color(red: 0.15, green: 0.08, blue: 0.1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            
            // Animated radial pulse
            if showBackground {
                RadialGradient(
                    colors: [
                        Color.yellow.opacity(pulseAnimation ? 0.15 : 0.05),
                        Color.clear
                    ],
                    center: .center,
                    startRadius: 50,
                    endRadius: pulseAnimation ? 400 : 200
                )
                .animation(.easeInOut(duration: 2).repeatForever(autoreverses: true), value: pulseAnimation)
            }
            
            // Subtle overlay pattern
            GeometryReader { geo in
                ForEach(0..<20, id: \.self) { i in
                    Circle()
                        .fill(Color.white.opacity(0.03))
                        .frame(width: CGFloat.random(in: 50...150))
                        .position(
                            x: CGFloat.random(in: 0...geo.size.width),
                            y: CGFloat.random(in: 0...geo.size.height)
                        )
                        .blur(radius: 20)
                }
            }
        }
        .ignoresSafeArea()
    }
    
    // MARK: - Main Icon
    
    private var mainIconView: some View {
        ZStack {
            // Outer glow rings
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .stroke(
                        Color.yellow.opacity(0.3 - Double(index) * 0.1),
                        lineWidth: 3
                    )
                    .frame(width: 180 + CGFloat(index * 30), height: 180 + CGFloat(index * 30))
                    .scaleEffect(pulseAnimation ? 1.1 : 1.0)
                    .animation(
                        .easeInOut(duration: 1.5)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.2),
                        value: pulseAnimation
                    )
            }
            
            // Inner glow
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.yellow.opacity(0.4), Color.clear],
                        center: .center,
                        startRadius: 50,
                        endRadius: 100
                    )
                )
                .frame(width: 200, height: 200)
            
            // Main circle background
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 1.0, green: 0.85, blue: 0.3),
                            Color(red: 1.0, green: 0.6, blue: 0.2)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 140, height: 140)
                .shadow(color: Color.orange.opacity(0.5), radius: 30, x: 0, y: 10)
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
            
            // Trophy icon
            Image(systemName: stats.isNewPersonalBest ? "star.fill" : "trophy.fill")
                .font(.system(size: 70, weight: .medium))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.white, .white.opacity(0.9)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .shadow(color: .black.opacity(0.2), radius: 5, x: 0, y: 3)
                .overlay(shimmerOverlay)
        }
        .scaleEffect(mainIconScale)
        .rotationEffect(.degrees(mainIconRotation))
        .opacity(showMainIcon ? 1 : 0)
    }
    
    @ViewBuilder
    private var shimmerOverlay: some View {
        Image(systemName: stats.isNewPersonalBest ? "star.fill" : "trophy.fill")
            .font(.system(size: 70, weight: .medium))
            .foregroundStyle(
                LinearGradient(
                    colors: [.clear, .white.opacity(0.5), .clear],
                    startPoint: UnitPoint(x: shimmerPhase - 0.3, y: 0),
                    endPoint: UnitPoint(x: shimmerPhase + 0.3, y: 1)
                )
            )
            .onAppear {
                withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
                    shimmerPhase = 1.5
                }
            }
    }
    
    // MARK: - Title Section
    
    private var titleSection: some View {
        VStack(spacing: 8) {
            if stats.isNewPersonalBest {
                Text("🎉 NEW PERSONAL BEST! 🎉")
                    .font(.system(size: 14, weight: .black, design: .rounded))
                    .tracking(2)
                    .foregroundColor(.yellow)
            }
            
            Text("Goal Crushed!")
                .font(.system(size: 42, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
            
            Text(completionSubtitle)
                .font(.system(size: 18, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.9))
                .multilineTextAlignment(.center)
        }
    }
    
    private var completionSubtitle: String {
        if stats.percentOver > 50 {
            return "You absolutely smashed it today! 💥"
        } else if stats.percentOver > 20 {
            return "You went above and beyond! 🚀"
        } else if stats.percentOver > 0 {
            return "You crushed your daily goal! 🎯"
        } else {
            return "You hit your daily goal! ✅"
        }
    }
    
    // MARK: - Stats Section
    
    private var statsSection: some View {
        VStack(spacing: 12) {
            // Distance card (main stat)
            distanceCard
            
            // Secondary stats row
            HStack(spacing: 12) {
                // Streak card
                streakCard
                
                // Pace card (if available)
                if stats.todaysPace != nil {
                    paceCard
                } else {
                    lifetimeMilesCard
                }
            }
        }
    }
    
    private var distanceCard: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "figure.run")
                    .font(.system(size: 16, weight: .semibold))
                Text("Today's Distance")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                Spacer()
                if stats.percentOver > 0 {
                    Text("+\(Int(stats.percentOver))%")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(.green)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.green.opacity(0.2))
                        .cornerRadius(8)
                }
            }
            .foregroundColor(.white.opacity(0.8))
            
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(String(format: "%.2f", stats.todaysDistance))
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                
                Text("mi")
                    .font(.system(size: 20, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.7))
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Goal")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.6))
                    Text("\(String(format: "%.1f", stats.goalDistance)) mi")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.8))
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.white.opacity(0.15))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(.white.opacity(0.25), lineWidth: 1)
                )
        )
    }
    
    private var streakCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "flame.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.orange)
                Text("Streak")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.7))
            }
            
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(stats.currentStreak)")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                
                Text("days")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.6))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.white.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(.white.opacity(0.2), lineWidth: 1)
                )
        )
    }
    
    private var paceCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "speedometer")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(stats.isPacePB ? .green : .cyan)
                Text(stats.isPacePB ? "Pace PB!" : "Avg Pace")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.7))
            }
            
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(formatPace(stats.todaysPace ?? 0))
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                
                Text("/mi")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.6))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.white.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(stats.isPacePB ? Color.green.opacity(0.4) : .white.opacity(0.2), lineWidth: 1)
                )
        )
    }
    
    private var lifetimeMilesCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "road.lanes")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.purple)
                Text("Total Miles")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.7))
            }
            
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(String(format: "%.0f", stats.totalLifetimeMiles))
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                
                Text("mi")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.6))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.white.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(.white.opacity(0.2), lineWidth: 1)
                )
        )
    }
    
    // MARK: - Streak Milestone Banner
    
    private func streakMilestoneBanner(_ milestone: StreakMilestone) -> some View {
        HStack(spacing: 12) {
            Text(milestone.emoji)
                .font(.system(size: 32))
            
            VStack(alignment: .leading, spacing: 2) {
                Text(milestone.title)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                
                Text("Keep the momentum going!")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.7))
            }
            
            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(
                    LinearGradient(
                        colors: [.orange.opacity(0.3), .red.opacity(0.3)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(
                            LinearGradient(
                                colors: [.orange.opacity(0.5), .red.opacity(0.5)],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            lineWidth: 1
                        )
                )
        )
    }
    
    // MARK: - Motivation Section
    
    private var motivationSection: some View {
        VStack(spacing: 8) {
            Text(motivationalMessage)
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.85))
                .multilineTextAlignment(.center)
            
            Text(nextGoalMessage)
                .font(.system(size: 14, weight: .regular, design: .rounded))
                .foregroundColor(.white.opacity(0.6))
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 16)
    }
    
    private var motivationalMessage: String {
        if stats.isNewPersonalBest {
            return "You just set a new personal record! 🏅"
        } else if stats.currentStreak >= 30 {
            return "A whole month of consistency! You're unstoppable! 💪"
        } else if stats.currentStreak >= 7 {
            return "A full week of crushing it! Amazing discipline! 🔥"
        } else if stats.percentOver > 30 {
            return "Way to go the extra mile (literally)! 🌟"
        } else {
            return "Every mile counts. You're building something great! ✨"
        }
    }
    
    private var nextGoalMessage: String {
        if let milestone = nextStreakMilestone {
            return "Only \(milestone.days - stats.currentStreak) days until your next streak milestone!"
        } else {
            return "Come back tomorrow to keep your streak alive!"
        }
    }
    
    private var nextStreakMilestone: StreakMilestone? {
        StreakMilestone.allCases.first { $0.days > stats.currentStreak }
    }
    
    // MARK: - Buttons Section
    
    private var buttonSection: some View {
        VStack(spacing: 12) {
            // Share achievement button
            Button {
                triggerHaptic()
                // Share action would go here
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 18, weight: .semibold))
                    Text("Share Achievement")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(
                            LinearGradient(
                                colors: [Color(red: 0.85, green: 0.25, blue: 0.35), Color(red: 0.7, green: 0.2, blue: 0.3)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .shadow(color: Color(red: 0.85, green: 0.25, blue: 0.35).opacity(0.4), radius: 15, x: 0, y: 8)
                )
            }
            
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
                                .stroke(.white.opacity(0.25), lineWidth: 1)
                        )
                )
            }
        }
    }
    
    // MARK: - Helper Functions
    
    private func formatPace(_ pace: TimeInterval) -> String {
        let minutes = Int(pace)
        let seconds = Int((pace - Double(minutes)) * 60)
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    private func triggerHaptic() {
        impactMedium.impactOccurred()
    }
    
    // MARK: - Animation Sequence
    
    private func startCelebrationSequence() {
        impactHeavy.prepare()
        notification.prepare()
        
        // Phase 1: Fade in
        withAnimation(.easeOut(duration: 0.3)) {
            overlayOpacity = 1
            showBackground = true
        }
        
        // Phase 2: Main icon appears
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.6)) {
                showMainIcon = true
                mainIconScale = 1.0
                mainIconRotation = 0
            }
            impactHeavy.impactOccurred(intensity: 1.0)
            
            // Start pulse animation
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                pulseAnimation = true
            }
        }
        
        // Phase 3: Fireworks and confetti
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            showFireworks = true
            confettiTrigger = true
            notification.notificationOccurred(.success)
        }
        
        // Phase 4: Title
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                showTitle = true
            }
        }
        
        // Phase 5: Stats
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                showStats = true
            }
            impactMedium.impactOccurred()
        }
        
        // Phase 6: Streak banner (if applicable)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) {
            if stats.streakMilestone != nil {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                    showStreakBanner = true
                }
                impactMedium.impactOccurred()
            }
        }
        
        // Phase 7: Motivation
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.easeOut(duration: 0.4)) {
                showMotivation = true
            }
        }
        
        // Phase 8: Buttons
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                showButtons = true
            }
        }
    }
}

// MARK: - Fireworks View

struct FireworksView: View {
    @State private var fireworks: [Firework] = []
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(fireworks) { firework in
                    FireworkBurst(firework: firework)
                }
            }
            .onAppear {
                generateFireworks(in: geo.size)
            }
        }
    }
    
    private func generateFireworks(in size: CGSize) {
        // Generate multiple fireworks with delays
        for i in 0..<8 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.3) {
                let firework = Firework(
                    position: CGPoint(
                        x: CGFloat.random(in: size.width * 0.2...size.width * 0.8),
                        y: CGFloat.random(in: size.height * 0.15...size.height * 0.5)
                    ),
                    color: [Color.yellow, .orange, .red, .pink, .white].randomElement()!
                )
                fireworks.append(firework)
            }
        }
    }
}

struct Firework: Identifiable {
    let id = UUID()
    let position: CGPoint
    let color: Color
}

struct FireworkBurst: View {
    let firework: Firework
    @State private var isAnimating = false
    
    var body: some View {
        ZStack {
            ForEach(0..<12, id: \.self) { index in
                Circle()
                    .fill(firework.color)
                    .frame(width: 6, height: 6)
                    .offset(
                        x: isAnimating ? cos(Double(index) * .pi / 6) * 60 : 0,
                        y: isAnimating ? sin(Double(index) * .pi / 6) * 60 : 0
                    )
                    .opacity(isAnimating ? 0 : 1)
            }
        }
        .position(firework.position)
        .onAppear {
            withAnimation(.easeOut(duration: 0.8)) {
                isAnimating = true
            }
        }
    }
}

// MARK: - Celebration Confetti

struct CelebrationConfetti: View {
    @State private var particles: [ConfettiPiece2] = []
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(particles) { particle in
                    ConfettiPieceView(particle: particle, screenHeight: geo.size.height)
                }
            }
            .onAppear {
                particles = (0..<80).map { _ in
                    ConfettiPiece2(
                        color: [.yellow, .orange, .red, .pink, .white, .cyan].randomElement()!,
                        x: CGFloat.random(in: 0...geo.size.width),
                        size: CGFloat.random(in: 6...12),
                        delay: Double.random(in: 0...0.5),
                        duration: Double.random(in: 2.5...4.0)
                    )
                }
            }
        }
    }
}

struct ConfettiPiece2: Identifiable {
    let id = UUID()
    let color: Color
    let x: CGFloat
    let size: CGFloat
    let delay: Double
    let duration: Double
}

struct ConfettiPieceView: View {
    let particle: ConfettiPiece2
    let screenHeight: CGFloat
    
    @State private var offset: CGFloat = -50
    @State private var rotation: Double = 0
    @State private var sway: CGFloat = 0
    
    var body: some View {
        Rectangle()
            .fill(particle.color)
            .frame(width: particle.size, height: particle.size * 1.5)
            .rotationEffect(.degrees(rotation))
            .offset(x: particle.x + sway, y: offset)
            .onAppear {
                withAnimation(.easeIn(duration: particle.duration).delay(particle.delay)) {
                    offset = screenHeight + 50
                }
                withAnimation(.linear(duration: particle.duration).delay(particle.delay)) {
                    rotation = Double.random(in: 360...720)
                }
                withAnimation(.easeInOut(duration: 0.8).delay(particle.delay).repeatForever(autoreverses: true)) {
                    sway = CGFloat.random(in: -40...40)
                }
            }
    }
}

// MARK: - Preview

#Preview("Goal Completed") {
    GoalCompletedCelebrationView(
        stats: GoalCompletionStats(
            todaysDistance: 1.75,
            goalDistance: 1.0,
            currentStreak: 7,
            totalLifetimeMiles: 156.5,
            bestDayMiles: 3.2,
            todaysPace: 8.45,
            personalBestPace: 7.8
        )
    )
}

#Preview("Personal Best") {
    GoalCompletedCelebrationView(
        stats: GoalCompletionStats(
            todaysDistance: 5.5,
            goalDistance: 1.0,
            currentStreak: 30,
            totalLifetimeMiles: 250.0,
            bestDayMiles: 5.0,
            todaysPace: 7.2,
            personalBestPace: 7.5
        )
    )
}
