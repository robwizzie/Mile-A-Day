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
    @State private var showFlame = false
    @State private var showStreakCount = false
    @State private var streakCountValue: Int = 0
    @State private var showWeekCalendar = false
    @State private var weekDayRevealIndex: Int = -1
    @State private var showTitle = false
    @State private var showStats = false
    @State private var showMotivation = false
    @State private var showButtons = false
    @State private var confettiTrigger = false

    private var isMajorMilestone: Bool {
        stats.streakMilestone?.isMajor == true
    }

    // Haptic generators
    private let impactMedium = UIImpactFeedbackGenerator(style: .medium)
    private let notification = UINotificationFeedbackGenerator()

    var body: some View {
        ZStack {
            // Warm gradient background
            celebrationBackground

            // Single confetti burst
            if confettiTrigger {
                CelebrationConfetti()
                    .allowsHitTesting(false)
            }

            // Content
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    Spacer(minLength: 40)

                    // HERO: Flame + streak counter
                    streakHeroSection

                    Spacer(minLength: 16)

                    // Title
                    if showTitle {
                        titleSection
                            .transition(.asymmetric(
                                insertion: .scale(scale: 0.8).combined(with: .opacity).combined(with: .offset(y: 20)),
                                removal: .opacity
                            ))
                    }

                    Spacer(minLength: 20)

                    // Week calendar
                    if showWeekCalendar {
                        weekCalendarSection
                            .transition(.asymmetric(
                                insertion: .scale(scale: 0.95).combined(with: .opacity),
                                removal: .opacity
                            ))
                    }

                    Spacer(minLength: 20)

                    // Today's stats (compact)
                    if showStats {
                        todayStatsSection
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .offset(y: 20)),
                                removal: .opacity
                            ))
                    }

                    // Streak milestone banner
                    if showMotivation, let milestone = stats.streakMilestone {
                        streakMilestoneBanner(milestone)
                            .transition(.asymmetric(
                                insertion: .scale(scale: 0.8).combined(with: .opacity),
                                removal: .opacity
                            ))
                            .padding(.top, 16)
                    }

                    // Motivation
                    if showMotivation {
                        motivationSection
                            .padding(.top, 16)
                            .transition(.opacity.combined(with: .offset(y: 20)))
                    }

                    Spacer(minLength: 24)

                    // Buttons
                    if showButtons {
                        buttonSection
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }

                    Spacer(minLength: 50)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 34) // Safe area for bottom
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
                    Color(red: 0.92, green: 0.50, blue: 0.08),
                    Color(red: 0.80, green: 0.22, blue: 0.12),
                    Color(red: 0.12, green: 0.06, blue: 0.03)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            // Warm radial glow behind flame area
            RadialGradient(
                colors: [
                    Color(red: 1.0, green: 0.65, blue: 0.15).opacity(0.35),
                    Color.clear
                ],
                center: UnitPoint(x: 0.5, y: 0.18),
                startRadius: 10,
                endRadius: 200
            )
        }
        .ignoresSafeArea()
    }

    // MARK: - Streak Hero (Flame + Counter)

    private var streakHeroSection: some View {
        VStack(spacing: 4) {
            // Animated flame with glow and embers
            FlameAnimationView(isIgnited: $showFlame)
                .frame(height: 140)

            // Streak counter
            if showStreakCount {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(streakCountValue)")
                        .font(.system(size: 56, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                        .contentTransition(.numericText())
                        .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)

                    Text("day streak!")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(.white.opacity(0.9))
                        .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 1)
                }
                .transition(.scale(scale: 0.5).combined(with: .opacity))
            }
        }
    }

    // MARK: - Title

    private var titleSection: some View {
        VStack(spacing: 6) {
            if stats.isNewPersonalBest {
                Text("NEW PERSONAL BEST!")
                    .font(.system(size: 14, weight: .black, design: .rounded))
                    .tracking(2)
                    .foregroundColor(.yellow)
                    .shadow(color: .orange.opacity(0.5), radius: 4, x: 0, y: 1)
            }

            Text(completionSubtitle)
                .font(.system(size: 18, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.95))
                .shadow(color: .black.opacity(0.3), radius: 3, x: 0, y: 1)
                .multilineTextAlignment(.center)
        }
    }

    private var completionSubtitle: String {
        if stats.percentOver > 50 {
            return "You absolutely crushed it today!"
        } else if stats.percentOver > 20 {
            return "You went above and beyond!"
        } else if stats.percentOver > 0 {
            return "Goal smashed! Keep it up!"
        } else {
            return "You hit your daily goal!"
        }
    }

    // MARK: - Week Calendar (Duolingo-style)

    private var weekCalendarSection: some View {
        let calendar = Calendar.current
        let today = Date()
        let weekday = calendar.component(.weekday, from: today)
        let daysFromSunday = weekday - 1

        let dayLabels = ["S", "M", "T", "W", "T", "F", "S"]

        return VStack(spacing: 12) {
            Text("THIS WEEK")
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .tracking(2)
                .foregroundColor(.white.opacity(0.5))

            HStack(spacing: 12) {
                ForEach(0..<7, id: \.self) { index in
                    let isPast = index < daysFromSunday
                    let isToday = index == daysFromSunday
                    let isFuture = index > daysFromSunday
                    let isRevealed = index <= weekDayRevealIndex

                    VStack(spacing: 6) {
                        Text(dayLabels[index])
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundColor(isToday ? .orange : .white.opacity(0.5))

                        ZStack {
                            if isFuture {
                                // Future: dim empty circle
                                Circle()
                                    .stroke(Color.white.opacity(0.15), lineWidth: 1.5)
                                    .frame(width: 36, height: 36)
                            } else if isToday {
                                // Today: green filled with running figure (just completed!)
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 36, height: 36)
                                    .shadow(color: .green.opacity(0.5), radius: isRevealed ? 8 : 0)

                                Image(systemName: "figure.run")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(.white)
                            } else if isPast {
                                // Past: check if goal was met (simplified — assume met for streak days)
                                let daysMet = stats.currentStreak >= daysFromSunday
                                    ? true
                                    : index >= (daysFromSunday - stats.currentStreak)

                                if daysMet {
                                    Circle()
                                        .fill(Color.green)
                                        .frame(width: 36, height: 36)

                                    Image(systemName: "figure.run")
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundColor(.white)
                                } else {
                                    Circle()
                                        .fill(Color.white.opacity(0.08))
                                        .frame(width: 36, height: 36)

                                    Image(systemName: "xmark")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundColor(.white.opacity(0.3))
                                }
                            }
                        }
                        .scaleEffect(isRevealed ? 1.0 : 0.5)
                        .opacity(isRevealed || isFuture ? 1.0 : 0.3)
                        .animation(.spring(response: 0.4, dampingFraction: 0.6), value: isRevealed)
                    }
                }
            }
        }
        .padding(.vertical, 20)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.white.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(.white.opacity(0.15), lineWidth: 1)
                )
        )
    }

    // MARK: - Today's Stats (Compact)

    private var todayStatsSection: some View {
        HStack(spacing: 12) {
            // Distance
            statPill(
                icon: "figure.run",
                iconColor: .green,
                value: String(format: "%.2f", stats.todaysDistance),
                unit: "mi",
                extra: stats.percentOver > 0 ? "+\(Int(stats.percentOver))%" : nil
            )

            // Duration
            if stats.todaysTotalDuration > 0 {
                statPill(
                    icon: "timer",
                    iconColor: .mint,
                    value: stats.formattedDuration,
                    unit: "min",
                    extra: nil
                )
            }

            // Pace
            if let pace = stats.todaysAveragePace {
                statPill(
                    icon: "speedometer",
                    iconColor: stats.isPacePB ? .green : .cyan,
                    value: formatPace(pace),
                    unit: "/mi",
                    extra: stats.isPacePB ? "PB!" : nil
                )
            }
        }
    }

    private func statPill(icon: String, iconColor: Color, value: String, unit: String, extra: String?) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(iconColor)

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text(unit)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.6))
            }

            if let extra = extra {
                Text(extra)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(.green)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.white.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(.white.opacity(0.15), lineWidth: 1)
                )
        )
    }

    // MARK: - Streak Milestone Banner

    @ViewBuilder
    private func streakMilestoneBanner(_ milestone: StreakMilestone) -> some View {
        if milestone.isMajor {
            majorMilestoneBanner(milestone)
        } else {
            miniMilestoneBanner(milestone)
        }
    }

    /// Mini milestone: clean, encouraging, compact
    private func miniMilestoneBanner(_ milestone: StreakMilestone) -> some View {
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
                        colors: [.orange.opacity(0.25), .red.opacity(0.2)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(.white.opacity(0.15), lineWidth: 1)
                )
        )
    }

    /// Major milestone: big, bold, extra sparkle
    private func majorMilestoneBanner(_ milestone: StreakMilestone) -> some View {
        VStack(spacing: 12) {
            // Big emoji with glow
            ZStack {
                Text(milestone.emoji)
                    .font(.system(size: 48))
                    .blur(radius: 15)
                    .opacity(0.5)
                Text(milestone.emoji)
                    .font(.system(size: 56))
            }

            Text(milestone.title.uppercased())
                .font(.system(size: 22, weight: .black, design: .rounded))
                .tracking(2)
                .foregroundColor(.yellow)

            Text(milestone.majorSubtitle)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.85))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .padding(.horizontal, 20)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.yellow.opacity(0.15),
                                Color.orange.opacity(0.2),
                                Color.red.opacity(0.15)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [.yellow.opacity(0.5), .orange.opacity(0.4), .red.opacity(0.3)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 2
                    )
            }
        )
        .shadow(color: .orange.opacity(0.3), radius: 20, x: 0, y: 8)
    }

    // MARK: - Motivation Section

    private var motivationSection: some View {
        VStack(spacing: 10) {
            // Show next milestone with progress bar
            if let next = nextStreakMilestone {
                let daysLeft = next.days - stats.currentStreak

                HStack(spacing: 6) {
                    Text(next.emoji)
                        .font(.system(size: 14))
                    Text("\(daysLeft) day\(daysLeft == 1 ? "" : "s") until \(next.title.lowercased())")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(.orange)
                }

                // Progress bar to next milestone
                GeometryReader { geo in
                    let previousMilestone = previousStreakMilestone?.days ?? 0
                    let range = next.days - previousMilestone
                    let progress = min(Double(stats.currentStreak - previousMilestone) / Double(max(range, 1)), 1.0)

                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.white.opacity(0.15))
                            .frame(height: 8)

                        RoundedRectangle(cornerRadius: 4)
                            .fill(
                                LinearGradient(
                                    colors: next.isMajor ? [.yellow, .orange] : [.orange, .red.opacity(0.8)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geo.size.width * progress, height: 8)
                    }
                }
                .frame(height: 8)

                // If the next milestone is mini, also tease the next major
                if !next.isMajor, let nextMajor = nextMajorMilestone, nextMajor.days != next.days {
                    let majorDaysLeft = nextMajor.days - stats.currentStreak
                    Text("\(nextMajor.emoji) \(majorDaysLeft) days to \(nextMajor.title.lowercased())")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(.yellow.opacity(0.7))
                        .padding(.top, 2)
                }
            }

            Text("Come back tomorrow to keep your streak alive!")
                .font(.system(size: 14, weight: .regular, design: .rounded))
                .foregroundColor(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .padding(.top, 4)
        }
        .padding(.horizontal, 8)
    }

    private var nextStreakMilestone: StreakMilestone? {
        StreakMilestone.allCases.first { $0.days > stats.currentStreak }
    }

    private var previousStreakMilestone: StreakMilestone? {
        StreakMilestone.allCases.last { $0.days <= stats.currentStreak }
    }

    private var nextMajorMilestone: StreakMilestone? {
        StreakMilestone.allCases.first { $0.days > stats.currentStreak && $0.isMajor }
    }

    // MARK: - Buttons

    private var buttonSection: some View {
        VStack(spacing: 12) {
            // Share button
            Button {
                impactMedium.impactOccurred()
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
                                colors: [.orange, Color(red: 0.85, green: 0.3, blue: 0.1)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .shadow(color: .orange.opacity(0.4), radius: 15, x: 0, y: 8)
                )
            }

            // Continue
            Button {
                impactMedium.impactOccurred()
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

    // MARK: - Helpers

    private func formatPace(_ pace: TimeInterval) -> String {
        let minutes = Int(pace)
        let seconds = Int((pace - Double(minutes)) * 60)
        return String(format: "%d:%02d", minutes, seconds)
    }

    // MARK: - Animation Sequence

    private func startCelebrationSequence() {
        impactMedium.prepare()
        notification.prepare()

        // Phase 1: Fade in background (0.0s)
        withAnimation(.easeOut(duration: 0.3)) {
            overlayOpacity = 1
        }

        // Phase 2: Ignite the flame (0.25s)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            showFlame = true
            notification.notificationOccurred(.success)
        }

        // Phase 3: Streak counter + confetti burst (0.7s - after flame has ignited)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                showStreakCount = true
            }
            animateStreakCounter()
            confettiTrigger = true
        }

        // Phase 4: Title + week calendar (1.1s)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                showTitle = true
                showWeekCalendar = true
            }
            // Quick staggered day reveals
            let calendar = Calendar.current
            let weekday = calendar.component(.weekday, from: Date())
            let daysFromSunday = weekday - 1
            for i in 0...daysFromSunday {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.06) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                        weekDayRevealIndex = i
                    }
                }
            }
        }

        // Phase 5: Stats + motivation (1.5s)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                showStats = true
                showMotivation = true
            }
        }

        // Phase 6: Buttons (1.8s)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                showButtons = true
            }
        }
    }

    private func animateStreakCounter() {
        let target = stats.currentStreak
        let startFrom = max(target - 3, 0)
        streakCountValue = startFrom

        for i in 0...(target - startFrom) {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.05) {
                withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                    streakCountValue = startFrom + i
                }
                if startFrom + i == target {
                    impactMedium.impactOccurred()
                }
            }
        }
    }
}

// MARK: - Celebration Confetti

struct CelebrationConfetti: View {
    @State private var particles: [ConfettiPiece2] = []

    // App-themed confetti colors: warm oranges, yellows, whites, with pops of color
    private let confettiColors: [Color] = [
        .yellow,
        Color(red: 1.0, green: 0.85, blue: 0.2),  // Gold
        .orange,
        Color(red: 1.0, green: 0.45, blue: 0.15),  // Deep orange
        .white,
        .white.opacity(0.9),
        Color(red: 1.0, green: 0.6, blue: 0.7),    // Soft pink
        .cyan.opacity(0.8),
    ]

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(particles) { particle in
                    ConfettiPieceView(particle: particle, screenSize: geo.size)
                }
            }
            .onAppear {
                let centerX = geo.size.width / 2

                // Wave 1: Burst from top-center (0.0s) - 25 pieces
                let wave1 = (0..<25).map { _ in
                    ConfettiPiece2(
                        color: confettiColors.randomElement()!,
                        startX: centerX + CGFloat.random(in: -40...40),
                        startY: -20,
                        shape: ConfettiShape.allCases.randomElement()!,
                        size: CGFloat.random(in: 6...12),
                        delay: Double.random(in: 0...0.3),
                        duration: Double.random(in: 2.5...4.0),
                        swayAmount: CGFloat.random(in: 30...80),
                        driftX: CGFloat.random(in: -60...60)
                    )
                }

                // Wave 2: From sides (0.3s) - 15 pieces
                let wave2 = (0..<15).map { _ -> ConfettiPiece2 in
                    let fromLeft = Bool.random()
                    return ConfettiPiece2(
                        color: confettiColors.randomElement()!,
                        startX: fromLeft ? -10 : geo.size.width + 10,
                        startY: CGFloat.random(in: 50...200),
                        shape: ConfettiShape.allCases.randomElement()!,
                        size: CGFloat.random(in: 5...10),
                        delay: Double.random(in: 0.3...0.7),
                        duration: Double.random(in: 2.0...3.5),
                        swayAmount: CGFloat.random(in: 20...50),
                        driftX: fromLeft ? CGFloat.random(in: 30...120) : CGFloat.random(in: -120 ... -30)
                    )
                }

                // Wave 3: Gentle trailing confetti (1.0s) - 10 pieces
                let wave3 = (0..<10).map { _ in
                    ConfettiPiece2(
                        color: confettiColors.randomElement()!,
                        startX: CGFloat.random(in: 0...geo.size.width),
                        startY: -30,
                        shape: ConfettiShape.allCases.randomElement()!,
                        size: CGFloat.random(in: 4...8),
                        delay: Double.random(in: 1.0...1.8),
                        duration: Double.random(in: 3.0...5.0),
                        swayAmount: CGFloat.random(in: 20...40),
                        driftX: CGFloat.random(in: -30...30)
                    )
                }

                particles = wave1 + wave2 + wave3
            }
        }
    }
}

enum ConfettiShape: CaseIterable {
    case rectangle
    case circle
    case roundedSquare
}

struct ConfettiPiece2: Identifiable {
    let id = UUID()
    let color: Color
    let startX: CGFloat
    let startY: CGFloat
    let shape: ConfettiShape
    let size: CGFloat
    let delay: Double
    let duration: Double
    let swayAmount: CGFloat
    let driftX: CGFloat
}

struct ConfettiPieceView: View {
    let particle: ConfettiPiece2
    let screenSize: CGSize

    @State private var yOffset: CGFloat = 0
    @State private var xOffset: CGFloat = 0
    @State private var rotation: Double = 0
    @State private var rotation3D: Double = 0
    @State private var sway: CGFloat = 0
    @State private var opacity: Double = 1.0

    var body: some View {
        Group {
            switch particle.shape {
            case .rectangle:
                Rectangle()
                    .fill(particle.color)
                    .frame(width: particle.size, height: particle.size * 1.6)
            case .circle:
                Circle()
                    .fill(particle.color)
                    .frame(width: particle.size, height: particle.size)
            case .roundedSquare:
                RoundedRectangle(cornerRadius: 2)
                    .fill(particle.color)
                    .frame(width: particle.size, height: particle.size)
            }
        }
        .rotation3DEffect(.degrees(rotation3D), axis: (x: 1, y: 0, z: 0))
        .rotationEffect(.degrees(rotation))
        .opacity(opacity)
        .offset(x: particle.startX + xOffset + sway, y: particle.startY + yOffset)
        .onAppear {
            // Fall down
            withAnimation(.easeIn(duration: particle.duration).delay(particle.delay)) {
                yOffset = screenSize.height + 80
            }
            // Drift sideways
            withAnimation(.easeOut(duration: particle.duration * 0.8).delay(particle.delay)) {
                xOffset = particle.driftX
            }
            // Spin
            withAnimation(.linear(duration: particle.duration).delay(particle.delay)) {
                rotation = Double.random(in: 360...1080)
            }
            // 3D flip for paper-like effect
            withAnimation(.linear(duration: particle.duration * 0.4).delay(particle.delay).repeatForever(autoreverses: false)) {
                rotation3D = 360
            }
            // Sway side to side
            withAnimation(.easeInOut(duration: 0.6).delay(particle.delay).repeatForever(autoreverses: true)) {
                sway = CGFloat.random(in: -particle.swayAmount...particle.swayAmount)
            }
            // Fade out near end
            withAnimation(.easeIn(duration: particle.duration * 0.3).delay(particle.delay + particle.duration * 0.7)) {
                opacity = 0
            }
        }
    }
}

// MARK: - Post-Goal Workout Encouragement

struct PostGoalEncouragementView: View {
    @ObservedObject var manager = CelebrationManager.shared
    var stats: GoalCompletionStats

    @State private var showContent = false

    var body: some View {
        ZStack {
            // Dark overlay
            LinearGradient(
                colors: [
                    Color(red: 0.1, green: 0.5, blue: 0.3),
                    Color(red: 0.05, green: 0.25, blue: 0.15),
                    Color(red: 0.05, green: 0.08, blue: 0.05)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            if showContent {
                VStack(spacing: 20) {
                    Spacer()

                    // Star icon
                    Image(systemName: "star.circle.fill")
                        .font(.system(size: 80))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.yellow, .orange],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .shadow(color: .yellow.opacity(0.4), radius: 20)

                    VStack(spacing: 8) {
                        Text("Extra Mile!")
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .foregroundColor(.white)

                        Text("You're going above and beyond today!")
                            .font(.system(size: 18, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.8))
                            .multilineTextAlignment(.center)
                    }

                    // Updated distance
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(String(format: "%.2f", stats.todaysDistance))
                            .font(.system(size: 48, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        Text("mi total today")
                            .font(.system(size: 16, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.7))
                    }
                    .padding(.top, 8)

                    // Percentage over goal
                    if stats.percentOver > 0 {
                        Text("+\(Int(stats.percentOver))% over goal")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundColor(.green)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(Color.green.opacity(0.2))
                            )
                    }

                    Spacer()

                    // Continue button
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            manager.dismissCurrentCelebration()
                        }
                    } label: {
                        Text("Keep Going!")
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(
                                        LinearGradient(
                                            colors: [.green, Color(red: 0.1, green: 0.6, blue: 0.3)],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                            )
                    }
                    .padding(.horizontal, 24)

                    Spacer(minLength: 80)
                }
                .transition(.scale(scale: 0.9).combined(with: .opacity))
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.1)) {
                showContent = true
            }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
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
            todaysAveragePace: 8.45,
            todaysFastestPace: 8.12,
            personalBestPace: 7.8,
            todaysTotalDuration: 890,
            todaysCalories: 215,
            todaysWorkoutCount: 1
        )
    )
}

#Preview("Long Streak") {
    GoalCompletedCelebrationView(
        stats: GoalCompletionStats(
            todaysDistance: 4.21,
            goalDistance: 1.0,
            currentStreak: 303,
            totalLifetimeMiles: 500.0,
            bestDayMiles: 5.0,
            todaysAveragePace: 8.5,
            todaysFastestPace: 7.8,
            personalBestPace: 7.5,
            todaysTotalDuration: 2376,
            todaysCalories: 580,
            todaysWorkoutCount: 2
        )
    )
}

#Preview("Post-Goal Encouragement") {
    PostGoalEncouragementView(
        stats: GoalCompletionStats(
            todaysDistance: 3.5,
            goalDistance: 1.0,
            currentStreak: 30,
            totalLifetimeMiles: 250.0,
            bestDayMiles: 5.0,
            todaysAveragePace: 7.2,
            todaysFastestPace: 6.8,
            personalBestPace: 7.5,
            todaysTotalDuration: 2376,
            todaysCalories: 580,
            todaysWorkoutCount: 2
        )
    )
}
