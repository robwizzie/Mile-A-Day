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

    // Phase 1: Flame Ignition
    @State private var overlayOpacity: Double = 0
    @State private var redGlowRadius: CGFloat = 0
    @State private var redGlowOpacity: Double = 0
    @State private var showFlame: Bool = false
    @State private var confettiTrigger: Bool = false

    // Phase 2: Weekday Calendar
    @State private var showWeekCard: Bool = false
    @State private var weekDayRevealIndex: Int = -1

    // Phase 3: Streak Count + Details
    @State private var showStreakCount: Bool = false
    @State private var streakCountValue: Int = 0
    @State private var showTitle: Bool = false

    // Phase 4: Below-fold content
    @State private var showStats: Bool = false
    @State private var showMotivation: Bool = false
    @State private var showButtons: Bool = false

    // Share - use Identifiable wrapper so .sheet(item:) works on first tap
    @State private var shareItem: ShareableImage? = nil

    private var isMajorMilestone: Bool {
        stats.streakMilestone?.isMajor == true
    }

    // Haptic generators
    private let impactMedium = UIImpactFeedbackGenerator(style: .medium)
    private let impactHeavy = UIImpactFeedbackGenerator(style: .heavy)
    private let impactLight = UIImpactFeedbackGenerator(style: .light)
    private let notification = UINotificationFeedbackGenerator()

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Background with expanding red glow
                celebrationBackground

                // Confetti burst
                if confettiTrigger {
                    CelebrationConfetti()
                        .allowsHitTesting(false)
                }

                // Scrollable content — hero fills first screen, details below
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        // HERO SECTION: centered flame + weekdays + streak
                        VStack(spacing: 0) {
                            Spacer(minLength: geo.safeAreaInsets.top + 60)

                            // Flame
                            FlameAnimationView(isIgnited: $showFlame, size: 120)
                                .frame(height: 220)
                                .opacity(showFlame ? 1.0 : 0.0)

                            // Weekday calendar
                            if showWeekCard {
                                weekCalendarSection
                                    .transition(.opacity)
                                    .padding(.top, 8)
                            }

                            // Streak count
                            streakCountSection
                                .padding(.top, 16)

                            // Title
                            if showTitle {
                                titleSection
                                    .transition(.asymmetric(
                                        insertion: .scale(scale: 0.8).combined(with: .opacity).combined(with: .offset(y: 20)),
                                        removal: .opacity
                                    ))
                                    .padding(.top, 12)
                            }

                            Spacer(minLength: 20)
                        }
                        .frame(minHeight: geo.size.height * 0.65)

                        // BELOW-FOLD: stats, motivation, buttons
                        VStack(spacing: 16) {
                            if showStats {
                                todayStatsSection
                                    .transition(.asymmetric(
                                        insertion: .opacity.combined(with: .offset(y: 20)),
                                        removal: .opacity
                                    ))
                            }

                            if showMotivation, let milestone = stats.streakMilestone {
                                streakMilestoneBanner(milestone)
                                    .transition(.asymmetric(
                                        insertion: .scale(scale: 0.8).combined(with: .opacity),
                                        removal: .opacity
                                    ))
                            }

                            if showMotivation {
                                motivationSection
                                    .transition(.opacity.combined(with: .offset(y: 20)))
                            }

                            if showButtons {
                                buttonSection
                                    .transition(.move(edge: .bottom).combined(with: .opacity))
                            }

                            Spacer(minLength: 120)
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 8)
                    }
                }
            }
            .ignoresSafeArea()
            .opacity(overlayOpacity)
            .onAppear {
                startCelebrationSequence()
            }
        }
    }

    // MARK: - Background

    private var celebrationBackground: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.15, green: 0.08, blue: 0.1),
                    Color(red: 0.12, green: 0.06, blue: 0.08),
                    Color(red: 0.05, green: 0.02, blue: 0.04)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            RadialGradient(
                colors: [
                    MADTheme.Colors.madRed.opacity(redGlowOpacity * 0.5),
                    MADTheme.Colors.madRed.opacity(redGlowOpacity * 0.15),
                    Color.clear
                ],
                center: UnitPoint(x: 0.5, y: 0.3),
                startRadius: 10,
                endRadius: 250
            )
            .scaleEffect(redGlowRadius > 0 ? 1.0 : 0.3)
        }
        .ignoresSafeArea()
    }

    // MARK: - Week Calendar (Clean centered circles)

    private var weekCalendarSection: some View {
        let calendar = Calendar.current
        let today = Date()
        let weekday = calendar.component(.weekday, from: today)
        let daysFromSunday = weekday - 1
        let dayLabels = ["S", "M", "T", "W", "T", "F", "S"]

        return HStack(spacing: 14) {
            ForEach(0..<7, id: \.self) { index in
                let isPast = index < daysFromSunday
                let isToday = index == daysFromSunday
                let isFuture = index > daysFromSunday
                let isRevealed = index <= weekDayRevealIndex

                VStack(spacing: 6) {
                    Text(dayLabels[index])
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(isToday ? MADTheme.Colors.madRed : .white.opacity(0.5))

                    ZStack {
                        if isFuture {
                            Circle()
                                .stroke(Color.white.opacity(0.15), lineWidth: 1.5)
                                .frame(width: 36, height: 36)
                        } else if isToday {
                            Circle()
                                .fill(MADTheme.Colors.madRed)
                                .frame(width: 36, height: 36)
                                .shadow(color: MADTheme.Colors.madRed.opacity(0.6), radius: isRevealed ? 8 : 0)

                            Image(systemName: "flame.fill")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.white)
                        } else if isPast {
                            let daysMet = stats.currentStreak >= daysFromSunday
                                ? true
                                : index >= (daysFromSunday - stats.currentStreak)

                            if daysMet {
                                Circle()
                                    .fill(MADTheme.Colors.madRed)
                                    .frame(width: 36, height: 36)

                                Image(systemName: "checkmark")
                                    .font(.system(size: 14, weight: .bold))
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
                    .scaleEffect(isRevealed ? 1.0 : 0.3)
                    .opacity(isRevealed || isFuture ? 1.0 : 0.0)
                    .animation(.spring(response: 0.35, dampingFraction: 0.5), value: isRevealed)
                }
            }
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Streak Counter

    private var streakCountSection: some View {
        Group {
            if showStreakCount {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(streakCountValue)")
                        .font(.system(size: 64, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                        .contentTransition(.numericText())
                        .shadow(color: MADTheme.Colors.madRed.opacity(0.5), radius: 8, x: 0, y: 4)

                    Text("day streak!")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
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
                    .foregroundColor(Color(red: 1.0, green: 0.65, blue: 0.55))
                    .shadow(color: MADTheme.Colors.madRed.opacity(0.5), radius: 4, x: 0, y: 1)
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

    // MARK: - Today's Stats (Compact)

    private var todayStatsSection: some View {
        HStack(spacing: 12) {
            statPill(
                icon: "figure.run",
                iconColor: MADTheme.Colors.madRed,
                value: String(format: "%.2f", stats.todaysDistance),
                unit: "mi",
                extra: stats.percentOver > 0 ? "+\(Int(stats.percentOver))%" : nil
            )

            if stats.todaysTotalDuration > 0 {
                statPill(
                    icon: "timer",
                    iconColor: .white.opacity(0.8),
                    value: stats.formattedDuration,
                    unit: "min",
                    extra: nil
                )
            }

            if let pace = stats.todaysAveragePace {
                statPill(
                    icon: "speedometer",
                    iconColor: stats.isPacePB ? MADTheme.Colors.madRed : .white.opacity(0.7),
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

            Text(extra ?? " ")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundColor(extra != nil ? MADTheme.Colors.madRed : .clear)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 90)
        .liquidGlassCard()
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
                        colors: [MADTheme.Colors.madRed.opacity(0.25), MADTheme.Colors.madRed.opacity(0.15)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(MADTheme.Colors.madRed.opacity(0.3), lineWidth: 1)
                )
        )
    }

    private func majorMilestoneBanner(_ milestone: StreakMilestone) -> some View {
        VStack(spacing: 12) {
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
                .foregroundColor(.white)

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
                                MADTheme.Colors.madRed.opacity(0.2),
                                Color(red: 0.9, green: 0.3, blue: 0.4).opacity(0.15),
                                MADTheme.Colors.madRed.opacity(0.1)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                MADTheme.Colors.madRed.opacity(0.5),
                                Color(red: 0.9, green: 0.3, blue: 0.4).opacity(0.4),
                                MADTheme.Colors.madRed.opacity(0.3)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 2
                    )
            }
        )
        .shadow(color: MADTheme.Colors.madRed.opacity(0.3), radius: 20, x: 0, y: 8)
    }

    // MARK: - Motivation Section

    private var motivationSection: some View {
        VStack(spacing: 10) {
            if let next = nextStreakMilestone {
                let daysLeft = next.days - stats.currentStreak

                HStack(spacing: 6) {
                    Text(next.emoji)
                        .font(.system(size: 14))
                    Text("\(daysLeft) day\(daysLeft == 1 ? "" : "s") until \(next.title.lowercased())")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(MADTheme.Colors.madRed)
                }

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
                                    colors: next.isMajor
                                        ? [Color(red: 0.9, green: 0.3, blue: 0.4), MADTheme.Colors.madRed]
                                        : [MADTheme.Colors.madRed.opacity(0.7), MADTheme.Colors.madRed],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geo.size.width * progress, height: 8)
                    }
                }
                .frame(height: 8)

                if !next.isMajor, let nextMajor = nextMajorMilestone, nextMajor.days != next.days {
                    let majorDaysLeft = nextMajor.days - stats.currentStreak
                    Text("\(nextMajor.emoji) \(majorDaysLeft) days to \(nextMajor.title.lowercased())")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(MADTheme.Colors.madRed.opacity(0.7))
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
            Button {
                impactMedium.impactOccurred()
                if let image = generateShareCardImage() {
                    shareItem = ShareableImage(image: image)
                }
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
                        .fill(MADTheme.Colors.redGradient)
                        .shadow(color: MADTheme.Colors.madRed.opacity(0.4), radius: 15, x: 0, y: 8)
                )
            }
            .sheet(item: $shareItem) { item in
                ShareSheet(items: [item.image])
            }

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
                .liquidGlassCard()
            }
        }
    }

    /// Generate a shareable image card from the celebration stats
    private func generateShareCardImage() -> UIImage? {
        let card = CelebrationShareCardView(stats: stats)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3.0
        renderer.isOpaque = false
        return renderer.uiImage
    }

    // MARK: - Helpers

    private func formatPace(_ pace: TimeInterval) -> String {
        let minutes = Int(pace)
        let seconds = Int((pace - Double(minutes)) * 60)
        return String(format: "%d:%02d", minutes, seconds)
    }

    // MARK: - Animation Sequence (3 Phases)

    private func startCelebrationSequence() {
        impactMedium.prepare()
        impactHeavy.prepare()
        impactLight.prepare()
        notification.prepare()

        // Phase 1: Flame Ignition (0.0s - 0.8s)
        withAnimation(.easeOut(duration: 0.3)) {
            overlayOpacity = 1
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            impactHeavy.impactOccurred(intensity: 1.0)
            showFlame = true
            withAnimation(.easeOut(duration: 0.6)) {
                redGlowRadius = 1.0
                redGlowOpacity = 1.0
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            confettiTrigger = true
            notification.notificationOccurred(.success)
        }

        // Phase 2: Weekday Calendar (0.8s - 1.6s)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                showWeekCard = true
            }
            let calendar = Calendar.current
            let weekday = calendar.component(.weekday, from: Date())
            let daysFromSunday = weekday - 1
            for i in 0...6 {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.08) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.5)) {
                        weekDayRevealIndex = i
                    }
                    // Haptic on each past/today day
                    if i <= daysFromSunday {
                        impactLight.impactOccurred(intensity: 0.5)
                    }
                }
            }
        }

        // Phase 3: Streak Count (1.4s - 2.2s)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                showStreakCount = true
            }
            animateStreakCounter()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                showTitle = true
            }
        }

        // Phase 4: Below-fold content (2.2s+)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.3) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                showStats = true
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                showMotivation = true
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.9) {
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

// MARK: - Shareable Image Wrapper (for .sheet(item:))

struct ShareableImage: Identifiable {
    let id = UUID()
    let image: UIImage
}

// MARK: - Celebration Share Card (rendered to image for sharing)

struct CelebrationShareCardView: View {
    let stats: GoalCompletionStats

    private let cardWidth: CGFloat = 600
    private let cardHeight: CGFloat = 900

    private var completionSubtitle: String {
        if stats.percentOver > 50 {
            return "Absolutely crushed it today!"
        } else if stats.percentOver > 20 {
            return "Went above and beyond!"
        } else if stats.percentOver > 0 {
            return "Goal smashed!"
        } else {
            return "Daily goal complete!"
        }
    }

    var body: some View {
        ZStack {
            // Full background gradient matching celebration screen
            LinearGradient(
                colors: [
                    Color(red: 0.15, green: 0.08, blue: 0.1),
                    Color(red: 0.12, green: 0.06, blue: 0.08),
                    Color(red: 0.05, green: 0.02, blue: 0.04)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            // Red glow behind flame
            RadialGradient(
                colors: [
                    MADTheme.Colors.madRed.opacity(0.45),
                    MADTheme.Colors.madRed.opacity(0.12),
                    Color.clear
                ],
                center: UnitPoint(x: 0.5, y: 0.18),
                startRadius: 10,
                endRadius: 250
            )

            VStack(spacing: 0) {
                Spacer()

                // Centered content block: flame + calendar + streak + stats
                VStack(spacing: 16) {
                    // Flame icon
                    ZStack {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 80, weight: .medium))
                            .foregroundStyle(MADTheme.Colors.madRed.opacity(0.5))
                            .blur(radius: 12)

                        Image(systemName: "flame.fill")
                            .font(.system(size: 80, weight: .medium))
                            .foregroundStyle(
                                LinearGradient(
                                    stops: [
                                        .init(color: Color(red: 1.0, green: 0.95, blue: 0.85), location: 0.0),
                                        .init(color: Color(red: 1.0, green: 0.65, blue: 0.55), location: 0.25),
                                        .init(color: MADTheme.Colors.madRed, location: 0.55),
                                        .init(color: Color(red: 0.7, green: 0.15, blue: 0.25), location: 1.0)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .shadow(color: MADTheme.Colors.madRed.opacity(0.6), radius: 14)
                    }

                    // Weekday calendar row
                    shareWeekCalendar

                    // Streak count
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(stats.currentStreak)")
                            .font(.system(size: 64, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                        Text("day streak!")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundColor(.white.opacity(0.9))
                    }
                    .shadow(color: MADTheme.Colors.madRed.opacity(0.4), radius: 6)

                    // Title / subtitle
                    VStack(spacing: 4) {
                        if stats.isNewPersonalBest {
                            Text("NEW PERSONAL BEST!")
                                .font(.system(size: 14, weight: .black, design: .rounded))
                                .tracking(2)
                                .foregroundColor(Color(red: 1.0, green: 0.65, blue: 0.55))
                        }

                        Text(completionSubtitle)
                            .font(.system(size: 18, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.9))
                    }

                    // Stats row
                    HStack(spacing: 0) {
                        shareStatColumn(
                            icon: "figure.run",
                            iconColor: MADTheme.Colors.madRed,
                            value: String(format: "%.2f", stats.todaysDistance),
                            unit: "mi",
                            extra: stats.percentOver > 0 ? "+\(Int(stats.percentOver))%" : nil
                        )

                        if stats.todaysTotalDuration > 0 {
                            shareDivider
                            shareStatColumn(
                                icon: "timer",
                                iconColor: .white.opacity(0.8),
                                value: stats.formattedDuration,
                                unit: "min",
                                extra: nil
                            )
                        }

                        if let pace = stats.todaysAveragePace {
                            shareDivider
                            let minutes = Int(pace)
                            let seconds = Int((pace - Double(minutes)) * 60)
                            shareStatColumn(
                                icon: "speedometer",
                                iconColor: stats.isPacePB ? MADTheme.Colors.madRed : .white.opacity(0.7),
                                value: String(format: "%d:%02d", minutes, seconds),
                                unit: "/mi",
                                extra: stats.isPacePB ? "PB!" : nil
                            )
                        }
                    }
                    .padding(.horizontal, 24)

                    // Milestone badge if applicable
                    if let milestone = stats.streakMilestone {
                        HStack(spacing: 8) {
                            Text(milestone.emoji)
                                .font(.system(size: 20))
                            Text(milestone.title)
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                        .background(
                            Capsule()
                                .fill(MADTheme.Colors.madRed.opacity(0.25))
                                .overlay(
                                    Capsule()
                                        .stroke(MADTheme.Colors.madRed.opacity(0.4), lineWidth: 1)
                                )
                        )
                    }
                }

                Spacer()

                // Branding footer pinned at bottom
                HStack(spacing: 10) {
                    Image("mad-logo")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 28, height: 28)
                    Text("Mile A Day")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.6))
                    Spacer()
                    Text("mileaday.run")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.4))
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 24)
            }
        }
        .frame(width: cardWidth, height: cardHeight)
        .clipShape(RoundedRectangle(cornerRadius: 28))
        .overlay(
            RoundedRectangle(cornerRadius: 28)
                .stroke(MADTheme.Colors.madRed.opacity(0.3), lineWidth: 2)
        )
    }

    // MARK: - Weekday Calendar for Share Card

    private var shareWeekCalendar: some View {
        let calendar = Calendar.current
        let today = Date()
        let weekday = calendar.component(.weekday, from: today)
        let daysFromSunday = weekday - 1
        let dayLabels = ["S", "M", "T", "W", "T", "F", "S"]

        return HStack(spacing: 14) {
            ForEach(0..<7, id: \.self) { index in
                let isPast = index < daysFromSunday
                let isToday = index == daysFromSunday
                let isFuture = index > daysFromSunday

                VStack(spacing: 6) {
                    Text(dayLabels[index])
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(isToday ? MADTheme.Colors.madRed : .white.opacity(0.5))

                    ZStack {
                        if isFuture {
                            Circle()
                                .stroke(Color.white.opacity(0.15), lineWidth: 1.5)
                                .frame(width: 40, height: 40)
                        } else if isToday {
                            Circle()
                                .fill(MADTheme.Colors.madRed)
                                .frame(width: 40, height: 40)
                                .shadow(color: MADTheme.Colors.madRed.opacity(0.6), radius: 6)

                            Image(systemName: "flame.fill")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(.white)
                        } else if isPast {
                            let daysMet = stats.currentStreak >= daysFromSunday
                                ? true
                                : index >= (daysFromSunday - stats.currentStreak)

                            if daysMet {
                                Circle()
                                    .fill(MADTheme.Colors.madRed)
                                    .frame(width: 40, height: 40)

                                Image(systemName: "checkmark")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundColor(.white)
                            } else {
                                Circle()
                                    .fill(Color.white.opacity(0.08))
                                    .frame(width: 40, height: 40)

                                Image(systemName: "xmark")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundColor(.white.opacity(0.3))
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Stat Column

    private func shareStatColumn(icon: String, iconColor: Color, value: String, unit: String, extra: String?) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(iconColor)

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text(unit)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.6))
            }

            Text(extra ?? " ")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(extra != nil ? MADTheme.Colors.madRed : .clear)
        }
        .frame(maxWidth: .infinity)
    }

    private var shareDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.15))
            .frame(width: 1, height: 50)
    }
}

