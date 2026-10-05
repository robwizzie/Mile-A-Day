//
//  StreakMilestoneCelebrationView.swift
//  Mile A Day
//
//  The headline moment for a streak milestone day (7, 30, 100, 500…). Plays
//  right after the flame — the flame counts the streak up to the number, and
//  this is the number getting its own moment. Built on the yearly
//  celebration's effects so the two read as one family, scaled down for the
//  minis and all the way up for the majors.
//

import SwiftUI

struct StreakMilestoneCelebrationView: View {
    let info: StreakMilestoneInfo
    @ObservedObject var manager = CelebrationManager.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Phases
    @State private var raysOn = false
    @State private var counterOn = false
    @State private var numeralOn = false
    @State private var confettiOn = false
    @State private var fireworksOn = false
    @State private var detailsOn = false
    @State private var buttonsOn = false
    @State private var skipVisible = false
    @State private var shimmer = false

    @State private var counterDay = 1
    @State private var counterFlip: Double = 0
    @State private var counterOpacity: Double = 0
    @State private var numeralScale: CGFloat = 0.3
    @State private var numeralOpacity: Double = 0

    @State private var hasStarted = false
    @State private var storyShare: MADStoryContent?

    private let tapHaptic = UIImpactFeedbackGenerator(style: .light)
    private let mediumHaptic = UIImpactFeedbackGenerator(style: .medium)
    private let heavyHaptic = UIImpactFeedbackGenerator(style: .heavy)
    private let successHaptic = UINotificationFeedbackGenerator()

    // MARK: - Derived

    /// Gold for the biggest days, then the yearly family's metals by size, and
    /// a flame palette for the early minis — so 30 days and 500 days are
    /// visibly different occasions.
    private var palette: YearPalette {
        switch info.days {
        case 1000...: return .forYear(10)          // holographic
        case 500..<1000: return .forYear(1)        // gold
        case 250..<500: return .forYear(2)         // rose gold
        case 150..<250: return .forYear(4)         // sapphire
        case 100..<150: return .forYear(3)         // platinum
        default: return Self.ember
        }
    }

    private static let ember = YearPalette(
        primary: Color(red: 1.00, green: 0.55, blue: 0.20),
        secondary: Color(red: 0.86, green: 0.20, blue: 0.24),
        accent: Color(red: 1.00, green: 0.86, blue: 0.62),
        textGradient: [
            Color(red: 1.00, green: 0.95, blue: 0.80),
            Color(red: 1.00, green: 0.62, blue: 0.25),
            Color(red: 0.86, green: 0.22, blue: 0.20)
        ],
        confettiColors: [
            Color(red: 1.00, green: 0.55, blue: 0.20),
            Color(red: 1.00, green: 0.82, blue: 0.40),
            Color(red: 0.86, green: 0.20, blue: 0.24),
            .white
        ],
        backgroundGradient: [
            Color(red: 0.12, green: 0.05, blue: 0.04),
            Color(red: 0.20, green: 0.07, blue: 0.05),
            Color(red: 0.05, green: 0.02, blue: 0.02)
        ],
        label: "Ember"
    )

    private var headlineNumber: String { info.days.formatted() }

    private var subtitle: String {
        if let milestone = info.milestone, milestone.isMajor {
            return milestone.majorSubtitle
        }
        switch info.days {
        case 7: return "One full week. The habit's taking hold."
        case 14: return "Two weeks without missing a day."
        case 21: return "Three weeks. This is who you are now."
        case 30: return "A whole month of showing up."
        case 50: return "Fifty days. Half way to triple digits."
        case 75: return "Seventy-five days strong."
        case 150: return "150 days. Nothing can stop you."
        case 200: return "Two hundred days of miles."
        default: return "\(info.days.formatted()) days of showing up. Every single one."
        }
    }

    /// What the screen is labelled as. A replay says WHEN it happened.
    private var eyebrow: String {
        if info.isReplay {
            return "REPLAY · \(Self.dateText(info.achievedOn).uppercased())"
        }
        return info.isMajor ? "STREAK MILESTONE" : "MILESTONE"
    }

    private var streakStart: Date {
        Calendar.current.date(byAdding: .day, value: -(info.days - 1), to: info.achievedOn) ?? info.achievedOn
    }

    /// The streak medal for this length, when the shelf has it. Read live so
    /// a medal that arrived a beat after the walk still shows up here.
    private var medal: Badge? {
        UserManager.shared.currentUser.badges.first { $0.id == "streak_\(info.days)" && !$0.isLocked }
    }

    private static func dateText(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy"
        return f.string(from: date)
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            LinearGradient(colors: palette.backgroundGradient, startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            if raysOn {
                GoldenRaysEffect(color: palette.primary)
                    .ignoresSafeArea()
                    .transition(.opacity)
            }
            if confettiOn {
                YearlyConfettiView(colors: palette.confettiColors, particleCount: info.isMajor ? 110 : 60)
                    .ignoresSafeArea()
                    .transition(.opacity)
            }
            if fireworksOn {
                FireworksShow(palette: palette)
                    .ignoresSafeArea()
                    .transition(.opacity)
            }
            if detailsOn {
                FloatingStarsEffect(color: palette.primary, starCount: info.isMajor ? 24 : 12)
                    .opacity(0.5)
                    .ignoresSafeArea()
            }

            content

            if skipVisible {
                skipButton
            }
        }
        .onAppear {
            guard !hasStarted else { return }
            hasStarted = true
            tapHaptic.prepare(); mediumHaptic.prepare(); heavyHaptic.prepare(); successHaptic.prepare()
            if reduceMotion {
                showFinalFrame()
            } else {
                runChoreography()
            }
        }
        .sheet(item: $storyShare) { content in
            ShareStudioView(content: content, initialTemplate: .streakMilestone)
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 56)

            ZStack {
                if counterOn && !numeralOn {
                    CalendarFlipCard(
                        palette: palette,
                        dayNumber: counterDay,
                        totalDays: info.days,
                        flipProgress: counterFlip
                    )
                    .frame(width: 240, height: 220)
                    .opacity(counterOpacity)
                    .transition(.scale(scale: 0.7).combined(with: .opacity))
                }
                if numeralOn {
                    numeralBlock
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(height: 340)

            Spacer(minLength: 12)

            if detailsOn {
                VStack(spacing: 12) {
                    if let medal {
                        medalChip(medal)
                    }
                    statsCard
                }
                .padding(.horizontal, MADTheme.Spacing.lg)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            Spacer(minLength: 16)

            if buttonsOn {
                buttons
                    .padding(.horizontal, MADTheme.Spacing.lg)
                    .padding(.bottom, MADTheme.Spacing.xl)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    private var numeralBlock: some View {
        VStack(spacing: 10) {
            Text(eyebrow)
                .font(.system(size: 13, weight: .black, design: .rounded))
                .tracking(3)
                .foregroundColor(palette.accent.opacity(0.95))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, 16)
                .padding(.vertical, 7)
                .background(
                    Capsule()
                        .fill(.ultraThinMaterial)
                        .overlay(Capsule().strokeBorder(palette.primary.opacity(0.45), lineWidth: 1))
                )

            Text(headlineNumber)
                .font(.system(size: info.days >= 1000 ? 104 : 128, weight: .black, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .foregroundStyle(LinearGradient(colors: palette.textGradient, startPoint: .top, endPoint: .bottom))
                .scaleEffect(numeralScale)
                .opacity(numeralOpacity)
                .shadow(color: .black.opacity(0.55), radius: 8, x: 0, y: 4)
                .shadow(color: palette.primary.opacity(0.55), radius: 30)
                .padding(.horizontal, MADTheme.Spacing.md)
                .modifier(YearNumberShimmer(active: shimmer, color: palette.accent))
                .accessibilityLabel("\(info.days) day streak")

            Text("DAY STREAK")
                .font(.system(size: 18, weight: .black, design: .rounded))
                .tracking(5)
                .foregroundColor(.white)
                .opacity(numeralOpacity)

            Text(subtitle)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(palette.primary.opacity(0.35), lineWidth: 1)
                        )
                )
                .padding(.horizontal, MADTheme.Spacing.lg)
                .padding(.top, 6)
                .opacity(numeralOpacity)
        }
    }

    private func medalChip(_ medal: Badge) -> some View {
        HStack(spacing: 10) {
            Image(systemName: iconName(for: medal))
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(palette.backgroundGradient.first ?? .black)
                .frame(width: 30, height: 30)
                .background(Circle().fill(LinearGradient(colors: [palette.primary, palette.secondary],
                                                         startPoint: .topLeading, endPoint: .bottomTrailing)))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text("MEDAL EARNED")
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .tracking(1.2)
                    .foregroundColor(palette.accent.opacity(0.9))
                Text(medal.name)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.black.opacity(0.3))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(palette.primary.opacity(0.5), lineWidth: 1)
                )
        )
    }

    private var statsCard: some View {
        HStack(spacing: 0) {
            statColumn(value: info.days.formatted(), label: "Days")
            divider
            statColumn(value: Self.shortDate(streakStart), label: "Began")
            divider
            if let miles = info.totalMiles, miles > 0 {
                statColumn(value: miles.distanceText, label: "Lifetime")
            } else {
                statColumn(value: Self.shortDate(info.achievedOn), label: "Reached")
            }
        }
        .padding(.vertical, MADTheme.Spacing.md)
        .padding(.horizontal, MADTheme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large, style: .continuous)
                        .fill(Color.black.opacity(0.25))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large, style: .continuous)
                        .strokeBorder(palette.primary.opacity(0.55), lineWidth: 1.2)
                )
        )
    }

    private static func shortDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "M/d/yy"
        return f.string(from: date)
    }

    private func statColumn(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(LinearGradient(colors: palette.textGradient, startPoint: .top, endPoint: .bottom))
                .lineLimit(1)
                .minimumScaleFactor(0.45)
            Text(label.uppercased())
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .tracking(1.0)
                .foregroundColor(.white.opacity(0.95))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 4)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.25))
            .frame(width: 1, height: 32)
    }

    private var buttons: some View {
        VStack(spacing: 12) {
            Button {
                mediumHaptic.impactOccurred()
                TelemetryService.record(ShareTelemetry.opened)
                var content = MADStoryContent(
                    streak: info.days,
                    totalMiles: info.totalMiles,
                    date: info.achievedOn
                )
                content.goalMet = true
                storyShare = content
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.arrow.up.fill")
                    Text("Share your streak")
                }
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundColor(palette.backgroundGradient.first ?? .black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large, style: .continuous)
                        .fill(LinearGradient(colors: [palette.primary, palette.secondary],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .shadow(color: palette.primary.opacity(0.6), radius: 16, x: 0, y: 6)
                )
            }

            Button {
                manager.dismissCurrentCelebration()
            } label: {
                Text(info.isReplay ? "Done" : "Keep Going")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundColor(palette.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large, style: .continuous)
                            .strokeBorder(palette.primary.opacity(0.5), lineWidth: 1)
                    )
            }
        }
    }

    private var skipButton: some View {
        VStack {
            HStack {
                Spacer()
                Button {
                    manager.dismissCurrentCelebration()
                } label: {
                    Text("Skip")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(palette.accent.opacity(0.6))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(.ultraThinMaterial))
                }
                .padding(.trailing, 16)
                .padding(.top, 8)
            }
            Spacer()
        }
        .transition(.opacity)
    }

    // MARK: - Choreography

    /// Reduce Motion: no count, no flight — the finished frame, at once.
    private func showFinalFrame() {
        raysOn = true
        numeralOn = true
        numeralScale = 1
        numeralOpacity = 1
        detailsOn = true
        buttonsOn = true
        skipVisible = false
        successHaptic.notificationOccurred(.success)
    }

    private func runChoreography() {
        withAnimation(.easeOut(duration: 0.8)) { raysOn = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { tapHaptic.impactOccurred(intensity: 0.6) }

        // The count up to the number — the streak, day by day, at speed.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.78)) {
                counterOn = true
                counterOpacity = 1
            }
            startCounting(duration: info.isMajor ? 2.0 : 1.3)
            withAnimation(.easeIn(duration: 0.4).delay(0.3)) { skipVisible = true }
        }

        let numeralAt = info.isMajor ? 3.3 : 2.5
        DispatchQueue.main.asyncAfter(deadline: .now() + numeralAt) {
            withAnimation(.easeOut(duration: 0.3)) { counterOpacity = 0 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                numeralOn = true
                mediumHaptic.impactOccurred()
                withAnimation(.easeOut(duration: 0.5)) { numeralOpacity = 1 }
                withAnimation(.spring(response: 0.7, dampingFraction: 0.55)) { numeralScale = 1 }
            }
        }

        // Climax.
        DispatchQueue.main.asyncAfter(deadline: .now() + numeralAt + 0.8) {
            withAnimation(.easeOut(duration: 0.4)) {
                confettiOn = true
                fireworksOn = info.isMajor
            }
            heavyHaptic.impactOccurred()
            if info.isMajor {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { heavyHaptic.impactOccurred() }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.36) { heavyHaptic.impactOccurred() }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { successHaptic.notificationOccurred(.success) }
            shimmer = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + numeralAt + 2.0) {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.82)) { detailsOn = true }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + numeralAt + 2.5) {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.82)) {
                buttonsOn = true
                skipVisible = false
            }
        }
    }

    private func startCounting(duration: Double) {
        let target = info.days
        let ticks = min(70, max(12, target))
        for i in 0...ticks {
            let t = Double(i) / Double(ticks)
            let eased = t * t * (3 - 2 * t)
            let day = max(1, Int((eased * Double(target)).rounded()))
            let at = duration * (t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2)
            DispatchQueue.main.asyncAfter(deadline: .now() + at) {
                counterDay = day
                if i.isMultiple(of: 8) { tapHaptic.impactOccurred(intensity: 0.4) }
                withAnimation(.linear(duration: 0.04)) {
                    counterFlip = i.isMultiple(of: 2) ? 1 : -1
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.05) {
            counterDay = target
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) { counterFlip = 0 }
            mediumHaptic.impactOccurred()
        }
    }
}

#Preview("500 days") {
    StreakMilestoneCelebrationView(
        info: StreakMilestoneInfo(days: 500, achievedOn: Date(), totalMiles: 612.4, isReplay: false)
    )
}

#Preview("30 days, replay") {
    StreakMilestoneCelebrationView(
        info: StreakMilestoneInfo(days: 30, achievedOn: Date().addingTimeInterval(-86400 * 40), totalMiles: nil, isReplay: true)
    )
}
