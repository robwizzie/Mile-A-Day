//
//  ChallengeCompletedCelebrationView.swift
//  Mile A Day
//
//  Rewarding full-screen moment when the user completes today's daily challenge.
//  Visuals adopt the challenge's own gradient so the celebration feels tied to
//  the specific challenge that was just conquered.
//

import SwiftUI

struct ChallengeCompletedCelebrationView: View {
    let info: ChallengeCelebrationInfo

    @ObservedObject var manager = CelebrationManager.shared
    @Environment(\.scenePhase) private var scenePhase

    @State private var opacity: Double = 0
    @State private var badgeScale: CGFloat = 0.4
    @State private var ringTrim: CGFloat = 0
    @State private var checkScale: CGFloat = 0
    @State private var showBurst = false
    @State private var showStars = false
    @State private var showContent = false
    @State private var hasStartedAnimation = false

    private var accent: Color { info.gradient.first ?? MADTheme.Colors.madRed }
    private var accentEnd: Color { info.gradient.last ?? accent }

    var body: some View {
        ZStack {
            // Dark base so the challenge gradient pops.
            LinearGradient(
                colors: [Color.black, accent.opacity(0.28), Color.black],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            if showBurst {
                BurstEffect(
                    colors: [accent, accentEnd, .white, .yellow],
                    particleCount: 34
                )
                .frame(height: 240)
                .allowsHitTesting(false)
            }
            if showStars {
                FloatingStarsEffect(color: accent.opacity(0.85), starCount: 22)
                    .allowsHitTesting(false)
            }

            VStack(spacing: MADTheme.Spacing.lg) {
                Spacer()

                Text("CHALLENGE COMPLETE")
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .tracking(3)
                    .foregroundColor(.white.opacity(0.7))
                    .opacity(showContent ? 1 : 0)

                challengeMedallion

                if showContent {
                    VStack(spacing: MADTheme.Spacing.sm) {
                        Text(info.title)
                            .font(.system(size: 34, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                            .minimumScaleFactor(0.6)
                            .lineLimit(2)
                            .shadow(color: .black.opacity(0.3), radius: 8, y: 4)

                        Text(info.description)
                            .font(.system(size: 16, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.85))
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, MADTheme.Spacing.xl)
                    }
                    .transition(.scale.combined(with: .opacity))

                    if info.challengeStreak > 1 {
                        streakPill
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }

                Spacer()

                if showContent {
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            manager.dismissCurrentCelebration()
                        }
                    } label: {
                        HStack(spacing: MADTheme.Spacing.sm) {
                            Text("Nice!")
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                            Image(systemName: "arrow.right.circle.fill")
                                .font(.system(size: 20))
                        }
                        .foregroundColor(accent)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(
                            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                                .fill(.white)
                                .shadow(color: accent.opacity(0.4), radius: 18, y: 8)
                        )
                        .padding(.horizontal, MADTheme.Spacing.xl)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                Spacer().frame(height: 56)
            }
        }
        .opacity(opacity)
        .onAppear { startAnimationIfActive() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { startAnimationIfActive() }
        }
    }

    private var challengeMedallion: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [accent.opacity(0.35), .clear],
                                     center: .center, startRadius: 40, endRadius: 110))
                .frame(width: 230, height: 230)

            // Progress ring sweeping to full as the medallion lands.
            Circle()
                .trim(from: 0, to: ringTrim)
                .stroke(
                    AngularGradient(colors: [accent, accentEnd, accent],
                                    center: .center),
                    style: StrokeStyle(lineWidth: 8, lineCap: .round)
                )
                .frame(width: 156, height: 156)
                .rotationEffect(.degrees(-90))

            Circle()
                .fill(LinearGradient(colors: [accent, accentEnd],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 124, height: 124)
                .shadow(color: accent.opacity(0.55), radius: 22)

            Image(systemName: info.icon)
                .font(.system(size: 54, weight: .semibold))
                .foregroundStyle(LinearGradient(colors: [.white, .white.opacity(0.85)],
                                                startPoint: .top, endPoint: .bottom))

            // Completion check badge.
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 40))
                .foregroundColor(.green)
                .background(Circle().fill(.white).frame(width: 34, height: 34))
                .offset(x: 46, y: 46)
                .scaleEffect(checkScale)
        }
        .scaleEffect(badgeScale)
    }

    private var streakPill: some View {
        HStack(spacing: 6) {
            Image(systemName: "flame.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.orange)
            Text("\(info.challengeStreak)-day challenge streak")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(Capsule().fill(Color.white.opacity(0.12)))
        .overlay(Capsule().strokeBorder(Color.orange.opacity(0.5), lineWidth: 1))
    }

    private func startAnimationIfActive() {
        guard !hasStartedAnimation, scenePhase == .active else { return }
        hasStartedAnimation = true
        animateIn()
    }

    private func animateIn() {
        withAnimation(.easeOut(duration: 0.3)) { opacity = 1 }
        withAnimation(.spring(response: 0.6, dampingFraction: 0.6).delay(0.1)) { badgeScale = 1 }
        withAnimation(.easeInOut(duration: 0.8).delay(0.2)) { ringTrim = 1 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.5)) { checkScale = 1 }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { showBurst = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { showStars = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { showContent = true }
        }
    }
}

#Preview {
    ChallengeCompletedCelebrationView(info: ChallengeCelebrationInfo(
        key: "five_k_day",
        title: "5K Day",
        description: "Go the distance — cover 3.1 miles (a full 5K) today",
        icon: "figure.run",
        gradient: [Color(hex: "#FF9500"), Color(hex: "#FF3B30")],
        challengeStreak: 4
    ))
}
