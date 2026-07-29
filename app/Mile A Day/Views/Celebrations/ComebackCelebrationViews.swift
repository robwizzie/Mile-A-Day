//
//  ComebackCelebrationViews.swift
//  Mile A Day
//
//  Comeback-arc moments: day 3 / day 7 of a streak rebuilt after a break
//  (ComebackCelebrationView) and the day the current streak passes the
//  all-time record (RecordStreakCelebrationView). Same animation bones as
//  MilestoneCelebrationView, themed ember and gold respectively.
//

import SwiftUI

// MARK: - Comeback (day 3 / day 7)

struct ComebackCelebrationView: View {
    let day: Int
    let priorLength: Int
    let recordLength: Int
    let eraNumber: Int

    @ObservedObject var manager = CelebrationManager.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var scale: CGFloat = 0.5
    @State private var opacity: Double = 0
    @State private var showBurst = false
    @State private var showStars = false
    @State private var showContent = false
    @State private var hasStartedAnimation = false

    private var title: String {
        switch day {
        case 3: return "3 Days In"
        case 7: return "One Week Back"
        default: return "Day \(day)"
        }
    }

    private var message: String {
        switch day {
        case 3:
            return "The comeback is real. \(priorLength) days came before — this run is just getting started."
        case 7:
            if recordLength > 7 {
                return "Chapter \(eraNumber) is rolling. \(recordLength - 7) days to your record."
            }
            return "Chapter \(eraNumber) is rolling. Every day from here is new ground."
        default:
            return "Chapter \(eraNumber) keeps building."
        }
    }

    var body: some View {
        ComebackCelebrationScaffold(
            gradientColors: [
                Color(red: 0.16, green: 0.05, blue: 0.04),
                Color(red: 0.55, green: 0.14, blue: 0.08),
                MADTheme.Colors.madRed
            ],
            glowColor: .orange,
            icon: "flame.fill",
            iconGradient: [Color(red: 1.0, green: 0.62, blue: 0.15), MADTheme.Colors.madRed],
            eyebrow: "COMEBACK · ERA \(eraNumber)",
            title: title,
            message: message,
            buttonTint: MADTheme.Colors.madRed,
            scale: $scale, opacity: $opacity,
            showBurst: $showBurst, showStars: $showStars, showContent: $showContent
        ) {
            manager.dismissCurrentCelebration()
        }
        .onAppear { startAnimationIfActive() }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active && !hasStartedAnimation {
                startAnimationIfActive()
            }
        }
    }

    private func startAnimationIfActive() {
        guard !hasStartedAnimation, scenePhase == .active else { return }
        hasStartedAnimation = true
        ComebackCelebrationScaffold.animateIn(
            scale: $scale, opacity: $opacity,
            showBurst: $showBurst, showStars: $showStars, showContent: $showContent
        )
    }
}

// MARK: - New record streak

struct RecordStreakCelebrationView: View {
    let days: Int
    let previousBest: Int

    @ObservedObject var manager = CelebrationManager.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var scale: CGFloat = 0.5
    @State private var opacity: Double = 0
    @State private var showBurst = false
    @State private var showStars = false
    @State private var showContent = false
    @State private var hasStartedAnimation = false

    var body: some View {
        ComebackCelebrationScaffold(
            gradientColors: [
                Color(red: 0.14, green: 0.09, blue: 0.02),
                Color(red: 0.55, green: 0.36, blue: 0.05),
                Color(red: 0.85, green: 0.60, blue: 0.10)
            ],
            glowColor: .yellow,
            icon: "crown.fill",
            iconGradient: [Color(red: 1.0, green: 0.85, blue: 0.35), Color(red: 0.85, green: 0.55, blue: 0.08)],
            eyebrow: "ALL-TIME RECORD",
            title: "New Longest Streak!",
            message: "Day \(days) — you've never been here before. Your old record was \(previousBest).",
            buttonTint: Color(red: 0.72, green: 0.48, blue: 0.05),
            scale: $scale, opacity: $opacity,
            showBurst: $showBurst, showStars: $showStars, showContent: $showContent
        ) {
            manager.dismissCurrentCelebration()
        }
        .onAppear { startAnimationIfActive() }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active && !hasStartedAnimation {
                startAnimationIfActive()
            }
        }
    }

    private func startAnimationIfActive() {
        guard !hasStartedAnimation, scenePhase == .active else { return }
        hasStartedAnimation = true
        ComebackCelebrationScaffold.animateIn(
            scale: $scale, opacity: $opacity,
            showBurst: $showBurst, showStars: $showStars, showContent: $showContent
        )
    }
}

// MARK: - Shared scaffold

/// The MilestoneCelebrationView layout, parameterized so the comeback and
/// record moments share one implementation instead of two near-copies.
private struct ComebackCelebrationScaffold: View {
    let gradientColors: [Color]
    let glowColor: Color
    let icon: String
    let iconGradient: [Color]
    let eyebrow: String
    let title: String
    let message: String
    let buttonTint: Color

    @Binding var scale: CGFloat
    @Binding var opacity: Double
    @Binding var showBurst: Bool
    @Binding var showStars: Bool
    @Binding var showContent: Bool
    let onContinue: () -> Void

    var body: some View {
        ZStack {
            LinearGradient(
                colors: gradientColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            if showBurst {
                BurstEffect(
                    colors: [glowColor, .orange, .yellow, .white],
                    particleCount: 35
                )
                .frame(height: 220)
            }

            if showStars {
                FloatingStarsEffect(
                    color: glowColor.opacity(0.8),
                    starCount: 25
                )
                .allowsHitTesting(false)
            }

            VStack(spacing: MADTheme.Spacing.xl) {
                Spacer()

                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [glowColor.opacity(0.3), .clear],
                                center: .center,
                                startRadius: 50,
                                endRadius: 100
                            )
                        )
                        .frame(width: 200, height: 200)
                        .pulseGlow(color: glowColor, maxScale: 1.1)

                    Circle()
                        .fill(
                            LinearGradient(
                                colors: iconGradient,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 120, height: 120)
                        .shadow(color: glowColor.opacity(0.5), radius: 20)

                    Image(systemName: icon)
                        .font(.system(size: 56))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.white, .white.opacity(0.8)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .shimmer()

                    MilestoneSparkleOverlay()
                }
                .scaleEffect(scale)
                .rotation3DEffect(
                    .degrees(showContent ? 0 : 180),
                    axis: (x: 0, y: 1, z: 0)
                )

                if showContent {
                    VStack(spacing: MADTheme.Spacing.md) {
                        Text(eyebrow)
                            .font(.system(size: 13, weight: .heavy, design: .rounded))
                            .tracking(2.4)
                            .foregroundColor(.white.opacity(0.72))

                        Text(title)
                            .font(.system(size: 38, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.6)
                            .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
                            .padding(.horizontal)

                        Text(message)
                            .font(.system(size: 18, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.9))
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, MADTheme.Spacing.xl)
                    }
                    .transition(.scale.combined(with: .opacity))
                }

                Spacer()

                if showContent {
                    Button(action: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            onContinue()
                        }
                    }) {
                        HStack(spacing: MADTheme.Spacing.sm) {
                            Text("Keep Going")
                                .font(.system(size: 20, weight: .semibold, design: .rounded))

                            Image(systemName: "arrow.right.circle.fill")
                                .font(.system(size: 20))
                        }
                        .foregroundColor(buttonTint)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(
                            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                                .fill(.white)
                                .shadow(color: glowColor.opacity(0.3), radius: 20, x: 0, y: 8)
                        )
                        .padding(.horizontal, MADTheme.Spacing.xl)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                // Clear the floating tab bar + home indicator (this overlay
                // ignores the safe area).
                Spacer()
                    .frame(height: 110)
            }
        }
        .ignoresSafeArea()
        .opacity(opacity)
    }

    /// Shared entrance choreography — mirrors MilestoneCelebrationView's.
    static func animateIn(
        scale: Binding<CGFloat>,
        opacity: Binding<Double>,
        showBurst: Binding<Bool>,
        showStars: Binding<Bool>,
        showContent: Binding<Bool>
    ) {
        withAnimation(.easeOut(duration: 0.3)) {
            opacity.wrappedValue = 1
        }
        withAnimation(.spring(response: 0.6, dampingFraction: 0.6).delay(0.1)) {
            scale.wrappedValue = 1.0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            showBurst.wrappedValue = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            showStars.wrappedValue = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                showContent.wrappedValue = true
            }
        }
    }
}

#Preview("Comeback day 3") {
    ComebackCelebrationView(day: 3, priorLength: 96, recordLength: 96, eraNumber: 2)
}

#Preview("New record") {
    RecordStreakCelebrationView(days: 97, previousBest: 96)
}
