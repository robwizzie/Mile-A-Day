import SwiftUI

// MARK: - Post-Goal Workout Encouragement (Extra Mile)

struct PostGoalEncouragementView: View {
    @ObservedObject var manager = CelebrationManager.shared
    var stats: GoalCompletionStats

    // Phased animation states
    @State private var overlayOpacity: Double = 0
    @State private var showIcon: Bool = false
    @State private var showTitle: Bool = false
    @State private var showLatestWorkout: Bool = false
    @State private var showTotals: Bool = false
    @State private var showBreakdown: Bool = false
    @State private var showButton: Bool = false
    @State private var confettiTrigger: Bool = false
    @State private var iconScale: CGFloat = 0.3
    @State private var glowOpacity: Double = 0

    private let impactMedium = UIImpactFeedbackGenerator(style: .medium)
    private let impactHeavy = UIImpactFeedbackGenerator(style: .heavy)
    private let notification = UINotificationFeedbackGenerator()

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Background
                extraMileBackground

                // Confetti
                if confettiTrigger {
                    ExtraMileConfetti()
                        .allowsHitTesting(false)
                }

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        // HERO SECTION: icon + title + today's total centered
                        VStack(spacing: 0) {
                            Spacer(minLength: geo.safeAreaInsets.top + 60)

                            // Star icon
                            if showIcon {
                                ZStack {
                                    // Glow behind star
                                    Image(systemName: "star.circle.fill")
                                        .font(.system(size: 90))
                                        .foregroundStyle(.orange.opacity(0.4))
                                        .blur(radius: 12)

                                    Image(systemName: "star.circle.fill")
                                        .font(.system(size: 90))
                                        .foregroundStyle(
                                            LinearGradient(
                                                colors: [.yellow, .orange],
                                                startPoint: .top,
                                                endPoint: .bottom
                                            )
                                        )
                                        .shadow(color: .yellow.opacity(0.5), radius: 25)
                                        .scaleEffect(iconScale)
                                }
                                .transition(.scale(scale: 0.3).combined(with: .opacity))
                            }

                            // Today's total distance (hero stat)
                            if showTotals {
                                HStack(alignment: .firstTextBaseline, spacing: 4) {
                                    Text(String(format: "%.2f", stats.todaysDistance))
                                        .font(.system(size: 56, weight: .black, design: .rounded))
                                        .foregroundColor(.white)
                                    Text("mi today")
                                        .font(.system(size: 20, weight: .bold, design: .rounded))
                                        .foregroundColor(.white.opacity(0.8))
                                }
                                .shadow(color: .orange.opacity(0.3), radius: 6)
                                .padding(.top, 16)
                                .transition(.scale(scale: 0.5).combined(with: .opacity))
                            }

                            // Title
                            if showTitle {
                                VStack(spacing: 6) {
                                    Text("Extra Mile!")
                                        .font(.system(size: 34, weight: .black, design: .rounded))
                                        .foregroundColor(.white)
                                        .shadow(color: .orange.opacity(0.3), radius: 8)

                                    Text("You're going above and beyond!")
                                        .font(.system(size: 17, weight: .medium, design: .rounded))
                                        .foregroundColor(.white.opacity(0.8))
                                        .multilineTextAlignment(.center)

                                    if stats.percentOver > 0 {
                                        Text("+\(Int(stats.percentOver))% over goal")
                                            .font(.system(size: 15, weight: .bold, design: .rounded))
                                            .foregroundColor(.green)
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 6)
                                            .background(
                                                Capsule()
                                                    .fill(Color.green.opacity(0.2))
                                            )
                                            .padding(.top, 4)
                                    }
                                }
                                .transition(.asymmetric(
                                    insertion: .offset(y: 20).combined(with: .opacity),
                                    removal: .opacity
                                ))
                                .padding(.top, 12)
                            }

                            Spacer(minLength: 20)
                        }
                        .frame(minHeight: geo.size.height * 0.55)

                        // BELOW-FOLD: workout details + button
                        VStack(spacing: 16) {
                            // Latest workout card
                            if showLatestWorkout, let latest = stats.latestWorkout {
                                latestWorkoutCard(latest)
                                    .transition(.asymmetric(
                                        insertion: .scale(scale: 0.9).combined(with: .opacity),
                                        removal: .opacity
                                    ))
                            }

                            // Full breakdown (if multiple types)
                            if showBreakdown, stats.workoutBreakdowns.count > 1 {
                                workoutBreakdownSection
                                    .transition(.asymmetric(
                                        insertion: .opacity.combined(with: .offset(y: 15)),
                                        removal: .opacity
                                    ))
                            }

                            // Button
                            if showButton {
                                Button {
                                    impactMedium.impactOccurred()
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                        manager.dismissCurrentCelebration()
                                    }
                                } label: {
                                    HStack(spacing: 8) {
                                        Text("Keep Going!")
                                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                                        Image(systemName: "arrow.right")
                                            .font(.system(size: 14, weight: .semibold))
                                    }
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
                                            .shadow(color: .green.opacity(0.3), radius: 12, x: 0, y: 6)
                                    )
                                }
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
                startExtraMileSequence()
            }
        }
    }

    // MARK: - Background

    private var extraMileBackground: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.08, green: 0.18, blue: 0.1),
                    Color(red: 0.05, green: 0.12, blue: 0.08),
                    Color(red: 0.03, green: 0.06, blue: 0.04)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            RadialGradient(
                colors: [
                    Color.orange.opacity(glowOpacity * 0.3),
                    Color.green.opacity(glowOpacity * 0.15),
                    Color.clear
                ],
                center: UnitPoint(x: 0.5, y: 0.25),
                startRadius: 10,
                endRadius: 200
            )
        }
        .ignoresSafeArea()
    }

    // MARK: - Latest Workout Card

    private func latestWorkoutCard(_ workout: WorkoutBreakdown) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: workout.icon)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.orange)
                Text("Latest \(workout.displayName)")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.8))
                Spacer()
            }

            HStack(spacing: 16) {
                workoutStatItem(value: workout.formattedDistance, label: "mi")
                workoutStatItem(value: workout.formattedDuration, label: "time")
                if let pace = workout.formattedPace {
                    workoutStatItem(value: pace, label: "pace")
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
        )
    }

    private func workoutStatItem(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            Text(label)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Full Breakdown

    private var workoutBreakdownSection: some View {
        VStack(spacing: 8) {
            Text("TODAY'S BREAKDOWN")
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .tracking(2)
                .foregroundColor(.white.opacity(0.4))

            ForEach(Array(stats.workoutBreakdowns.enumerated()), id: \.offset) { _, breakdown in
                HStack(spacing: 12) {
                    Image(systemName: breakdown.icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.orange)
                        .frame(width: 24)

                    Text(breakdown.displayName)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)

                    Spacer()

                    Text(breakdown.formattedDistance + " mi")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(.white)

                    Text(breakdown.formattedDuration)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.6))
                        .frame(width: 50, alignment: .trailing)
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 14)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
    }

    // MARK: - Animation Sequence

    private func startExtraMileSequence() {
        impactMedium.prepare()
        impactHeavy.prepare()
        notification.prepare()

        // Phase 1: Fade in
        withAnimation(.easeOut(duration: 0.3)) {
            overlayOpacity = 1
        }
        withAnimation(.easeOut(duration: 0.6)) {
            glowOpacity = 1.0
        }

        // Phase 2: Star icon bounces in (0.1s)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            impactHeavy.impactOccurred(intensity: 0.8)
            withAnimation(.spring(response: 0.5, dampingFraction: 0.5)) {
                showIcon = true
                iconScale = 1.0
            }
            confettiTrigger = true
        }

        // Phase 3: Total distance (0.5s)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                showTotals = true
            }
            notification.notificationOccurred(.success)
        }

        // Phase 4: Title + percent over (0.8s)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                showTitle = true
            }
        }

        // Phase 5: Latest workout card (1.2s)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                showLatestWorkout = true
            }
        }

        // Phase 6: Full breakdown (1.5s)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                showBreakdown = true
            }
        }

        // Phase 7: Button (1.8s)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                showButton = true
            }
        }
    }
}

// MARK: - Extra Mile Confetti (green/gold themed)

struct ExtraMileConfetti: View {
    @State private var particles: [ConfettiPiece2] = []

    private let confettiColors: [Color] = [
        .green,
        Color(red: 0.2, green: 0.8, blue: 0.4),
        .yellow,
        .orange,
        .white,
        .white.opacity(0.85),
        Color(red: 0.4, green: 0.9, blue: 0.5),
        Color(red: 1.0, green: 0.85, blue: 0.3),
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

                let wave1 = (0..<20).map { _ in
                    ConfettiPiece2(
                        color: confettiColors.randomElement()!,
                        startX: centerX + CGFloat.random(in: -40...40),
                        startY: -20,
                        shape: CelebrationConfettiShape.allCases.randomElement()!,
                        size: CGFloat.random(in: 5...10),
                        delay: Double.random(in: 0...0.3),
                        duration: Double.random(in: 2.5...4.0),
                        swayAmount: CGFloat.random(in: 25...60),
                        driftX: CGFloat.random(in: -50...50)
                    )
                }

                let wave2 = (0..<10).map { _ in
                    ConfettiPiece2(
                        color: confettiColors.randomElement()!,
                        startX: CGFloat.random(in: 0...geo.size.width),
                        startY: -30,
                        shape: CelebrationConfettiShape.allCases.randomElement()!,
                        size: CGFloat.random(in: 4...8),
                        delay: Double.random(in: 0.5...1.2),
                        duration: Double.random(in: 3.0...5.0),
                        swayAmount: CGFloat.random(in: 20...40),
                        driftX: CGFloat.random(in: -30...30)
                    )
                }

                particles = wave1 + wave2
            }
        }
    }
}
