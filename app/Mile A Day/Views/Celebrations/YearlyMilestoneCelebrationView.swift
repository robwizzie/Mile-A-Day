//
//  YearlyMilestoneCelebrationView.swift
//  Mile A Day
//
//  Headline celebration for completing a full year (or every subsequent year).
//  Multi-phase choreography designed to feel exceptional and shareable.
//

import SwiftUI

// MARK: - Info struct

/// Snapshot of the user's state at the moment they crossed a year boundary.
struct YearlyMilestoneInfo: Equatable {
    let years: Int
    let totalMiles: Double
    let totalStreakDays: Int
    /// Approximate date the current streak began (today minus streak days).
    let streakStartDate: Date?
}

// MARK: - View

struct YearlyMilestoneCelebrationView: View {
    let info: YearlyMilestoneInfo
    @ObservedObject var manager = CelebrationManager.shared

    // Phase flags
    @State private var phase1_rays = false
    @State private var phase2_calendar = false
    @State private var phase2_yearNumber = false
    @State private var phase3_confetti = false
    @State private var phase3_fireworks = false
    @State private var phase4_stats = false
    @State private var phase4_buttons = false

    // Continuous effects
    @State private var sustainedShimmer = false
    @State private var yearNumberScale: CGFloat = 0.2
    @State private var yearNumberRotation: Double = 90
    @State private var yearNumberOpacity: Double = 0

    // Calendar flip
    @State private var calendarDay: Int = 1
    @State private var calendarFlipProgress: Double = 0
    @State private var calendarOpacity: Double = 0

    // Backstop
    @State private var hasStarted = false
    @State private var skipVisible = false

    // Haptics
    private let tapHaptic = UIImpactFeedbackGenerator(style: .light)
    private let mediumHaptic = UIImpactFeedbackGenerator(style: .medium)
    private let heavyHaptic = UIImpactFeedbackGenerator(style: .heavy)
    private let successHaptic = UINotificationFeedbackGenerator()

    private var palette: YearPalette { YearPalette.forYear(info.years) }

    private var totalDaysInWindow: Int {
        // Show "of 365" for year 1, "of 730" for year 2, etc.
        info.years * 365
    }

    private var subtitle: String {
        switch info.years {
        case 1:  return "365 days. One full year. Legendary."
        case 2:  return "Two full years. You're built different."
        case 3:  return "Three years strong. Pure dedication."
        case 4:  return "Four years and counting. Unstoppable."
        case 5:  return "Half a decade of showing up."
        case 10: return "A full decade of miles. You are a legend."
        case 25: return "Twenty-five years. A lifetime of dedication."
        default: return "\(info.years) full years of showing up."
        }
    }

    private var headline: String {
        info.years == 1 ? "ONE YEAR" : "\(info.years) YEARS"
    }

    private var shareText: String {
        let miles = Int(info.totalMiles.rounded())
        return "I just hit \(info.years == 1 ? "1 YEAR" : "\(info.years) YEARS") of running a mile every day on Mile A Day. \(miles) miles and counting. 🏃"
    }

    // MARK: - Body

    var body: some View {
        GeometryReader { geo in
            ZStack {
                LinearGradient(
                    colors: palette.backgroundGradient,
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                if phase1_rays {
                    GoldenRaysEffect(color: palette.primary)
                        .ignoresSafeArea()
                        .transition(.opacity)
                }

                if phase3_confetti {
                    YearlyConfettiView(colors: palette.confettiColors, particleCount: 110)
                        .ignoresSafeArea()
                        .transition(.opacity)
                }

                if phase3_fireworks {
                    FireworksShow(palette: palette)
                        .ignoresSafeArea()
                        .transition(.opacity)
                }

                if phase4_stats {
                    FloatingStarsEffect(color: palette.primary, starCount: 24)
                        .opacity(0.55)
                        .ignoresSafeArea()
                }

                content(in: geo)

                if skipVisible {
                    skipButton
                }
            }
        }
        .onAppear {
            guard !hasStarted else { return }
            hasStarted = true
            tapHaptic.prepare(); mediumHaptic.prepare(); heavyHaptic.prepare(); successHaptic.prepare()
            runChoreography()
        }
    }

    // MARK: - Content

    @ViewBuilder
    private func content(in geo: GeometryProxy) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 60)

            ZStack {
                if phase2_calendar && !phase2_yearNumber {
                    CalendarFlipCard(
                        palette: palette,
                        dayNumber: calendarDay,
                        totalDays: totalDaysInWindow,
                        flipProgress: calendarFlipProgress
                    )
                    .frame(width: 240, height: 220)
                    .opacity(calendarOpacity)
                    .transition(.scale(scale: 0.7).combined(with: .opacity))
                }

                if phase2_yearNumber {
                    yearNumeralBlock
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(height: 320)

            Spacer(minLength: 12)

            if phase4_stats {
                statsCard
                    .padding(.horizontal, MADTheme.Spacing.lg)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            Spacer(minLength: 16)

            if phase4_buttons {
                buttonRow
                    .padding(.horizontal, MADTheme.Spacing.lg)
                    .padding(.bottom, MADTheme.Spacing.xl)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    // MARK: - Year numeral

    @ViewBuilder
    private var yearNumeralBlock: some View {
        VStack(spacing: 6) {
            Text(eyebrowLabel)
                .font(.system(size: 16, weight: .heavy, design: .rounded))
                .tracking(8)
                .foregroundColor(palette.accent.opacity(0.85))

            Text(headline)
                .font(.system(size: info.years > 9 ? 96 : 120, weight: .black, design: .rounded))
                .foregroundStyle(
                    LinearGradient(colors: palette.textGradient, startPoint: .top, endPoint: .bottom)
                )
                .scaleEffect(yearNumberScale)
                .rotation3DEffect(
                    .degrees(yearNumberRotation),
                    axis: (x: 1, y: 0, z: 0),
                    perspective: 0.7
                )
                .opacity(yearNumberOpacity)
                .shadow(color: palette.primary.opacity(0.55), radius: 30, x: 0, y: 0)
                .modifier(YearNumberShimmer(active: sustainedShimmer, color: palette.accent))

            Text(subtitle)
                .font(.system(size: 19, weight: .bold, design: .rounded))
                .foregroundColor(palette.accent)
                .multilineTextAlignment(.center)
                .padding(.horizontal, MADTheme.Spacing.lg)
                .padding(.top, 6)
                .opacity(yearNumberOpacity)
        }
    }

    private var eyebrowLabel: String {
        info.years == 1 ? "STREAK COMPLETE" : "ANOTHER YEAR DOWN"
    }

    // MARK: - Stats card

    @ViewBuilder
    private var statsCard: some View {
        HStack(spacing: 0) {
            statColumn(
                value: "\(Int(info.totalMiles.rounded()))",
                label: info.totalMiles == 1 ? "Mile" : "Miles"
            )
            statDivider
            statColumn(
                value: "\(info.totalStreakDays)",
                label: "Day Streak"
            )
            statDivider
            statColumn(
                value: streakStartLabel,
                label: "Began"
            )
        }
        .padding(.vertical, MADTheme.Spacing.md)
        .padding(.horizontal, MADTheme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large, style: .continuous)
                        .strokeBorder(palette.primary.opacity(0.4), lineWidth: 1)
                )
        )
    }

    private func statColumn(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(
                    LinearGradient(colors: palette.textGradient, startPoint: .top, endPoint: .bottom)
                )
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label.uppercased())
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .tracking(1.2)
                .foregroundColor(palette.accent.opacity(0.75))
        }
        .frame(maxWidth: .infinity)
    }

    private var statDivider: some View {
        Rectangle()
            .fill(palette.primary.opacity(0.25))
            .frame(width: 1, height: 32)
    }

    private var streakStartLabel: String {
        guard let start = info.streakStartDate else { return "—" }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: start)
    }

    // MARK: - Buttons

    @ViewBuilder
    private var buttonRow: some View {
        VStack(spacing: 12) {
            ShareLink(item: shareText) {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.arrow.up.fill")
                    Text("Share This Win")
                }
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundColor(palette.backgroundGradient.first ?? .black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [palette.primary, palette.secondary],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .shadow(color: palette.primary.opacity(0.6), radius: 16, x: 0, y: 6)
                )
            }

            Button {
                manager.dismissCurrentCelebration()
            } label: {
                Text("Keep Going")
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

    // MARK: - Skip

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
                        .background(
                            Capsule().fill(.ultraThinMaterial)
                        )
                }
                .padding(.trailing, 16)
                .padding(.top, 8)
            }
            Spacer()
        }
        .transition(.opacity)
    }

    // MARK: - Choreography

    private func runChoreography() {
        // Phase 1: rays + first soft haptic
        withAnimation(.easeOut(duration: 0.8)) {
            phase1_rays = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { tapHaptic.impactOccurred(intensity: 0.6) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.85) { tapHaptic.impactOccurred(intensity: 0.8) }

        // Phase 2a: calendar appears at ~1.4s
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.78)) {
                phase2_calendar = true
                calendarOpacity = 1
            }
            startCalendarFlipping()
            // Allow user to skip after the calendar appears.
            withAnimation(.easeIn(duration: 0.4).delay(0.3)) { skipVisible = true }
        }

        // Phase 2b: year numeral at ~3.6s (after calendar lands)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.6) {
            withAnimation(.easeOut(duration: 0.3)) {
                calendarOpacity = 0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                phase2_yearNumber = true
                yearNumberOpacity = 0.0
                yearNumberScale = 0.4
                yearNumberRotation = 90
                mediumHaptic.impactOccurred()

                withAnimation(.easeOut(duration: 0.5)) {
                    yearNumberOpacity = 1
                }
                withAnimation(.spring(response: 0.7, dampingFraction: 0.55)) {
                    yearNumberScale = 1.0
                    yearNumberRotation = 0
                }
            }
        }

        // Phase 3: climax — confetti + fireworks + chord at ~4.5s
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.5) {
            withAnimation(.easeOut(duration: 0.4)) {
                phase3_confetti = true
                phase3_fireworks = true
            }
            heavyHaptic.impactOccurred()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { heavyHaptic.impactOccurred() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.36) { heavyHaptic.impactOccurred() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { successHaptic.notificationOccurred(.success) }
            // Sustained shimmer over numeral
            sustainedShimmer = true
        }

        // Phase 4: stats + buttons at ~6.0s
        DispatchQueue.main.asyncAfter(deadline: .now() + 6.0) {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.82)) {
                phase4_stats = true
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 6.5) {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.82)) {
                phase4_buttons = true
            }
        }
    }

    /// Animates the calendar through every day of the year via shrinking time slices.
    /// Uses a manually scheduled sequence so users can see the count visibly racing,
    /// rather than a single linear interpolation that would look static at high counts.
    private func startCalendarFlipping() {
        let target = totalDaysInWindow
        // ~2.0 seconds total, ~80 visible "ticks" with eased acceleration then deceleration
        let tickCount = 80
        let totalDuration: Double = 2.0
        for i in 0...tickCount {
            // Ease in-out so it speeds up then slows on landing
            let t = Double(i) / Double(tickCount)
            let eased = easeInOut(t)
            let day = max(1, Int(round(eased * Double(target))))
            // Distribute timing in eased bands so visible count looks like a real accelerator
            let scheduledAt = totalDuration * easeInOutTiming(t)
            DispatchQueue.main.asyncAfter(deadline: .now() + scheduledAt) {
                calendarDay = day
                if i.isMultiple(of: 8) { tapHaptic.impactOccurred(intensity: 0.4) }
                withAnimation(.linear(duration: 0.04)) {
                    calendarFlipProgress = (i.isMultiple(of: 2) ? 1 : -1)
                }
            }
        }
        // Land on final number with a satisfying thump
        DispatchQueue.main.asyncAfter(deadline: .now() + totalDuration + 0.05) {
            calendarDay = target
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                calendarFlipProgress = 0
            }
            mediumHaptic.impactOccurred()
        }
    }

    private func easeInOut(_ t: Double) -> Double {
        // Smoothstep
        let clamped = max(0, min(1, t))
        return clamped * clamped * (3 - 2 * clamped)
    }

    private func easeInOutTiming(_ t: Double) -> Double {
        // A slightly stronger ease so the early ticks fly by and the last few linger
        let clamped = max(0, min(1, t))
        return clamped < 0.5
            ? 2 * clamped * clamped
            : 1 - pow(-2 * clamped + 2, 2) / 2
    }
}

#Preview("Year 1") {
    YearlyMilestoneCelebrationView(
        info: YearlyMilestoneInfo(
            years: 1,
            totalMiles: 412.7,
            totalStreakDays: 365,
            streakStartDate: Calendar.current.date(byAdding: .day, value: -365, to: Date())
        )
    )
}

#Preview("Year 3") {
    YearlyMilestoneCelebrationView(
        info: YearlyMilestoneInfo(
            years: 3,
            totalMiles: 1284.5,
            totalStreakDays: 1095,
            streakStartDate: Calendar.current.date(byAdding: .day, value: -1095, to: Date())
        )
    )
}

#Preview("Year 10") {
    YearlyMilestoneCelebrationView(
        info: YearlyMilestoneInfo(
            years: 10,
            totalMiles: 4280,
            totalStreakDays: 3650,
            streakStartDate: Calendar.current.date(byAdding: .day, value: -3650, to: Date())
        )
    )
}
