//
//  YearlyMilestoneCelebrationView.swift
//  Mile A Day
//
//  Headline celebration for completing a full year (or every subsequent year).
//  Multi-phase choreography designed to feel exceptional and shareable.
//

import SwiftUI

// `YearlyMilestoneInfo` lives in `Models/YearlyMilestoneInfo.swift` so it
// can be a member of both the iOS and Watch targets.

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

    // Share — use Identifiable wrapper with `.sheet(item:)` so the first tap
    // always presents (the two-state-update + `isPresented` pattern can drop
    // the first tap because the sheet content captures stale state).
    @State private var shareItem: ShareableImage? = nil

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
        case 1:  return "365 days. A full year. Legendary."
        case 2:  return "2 full years. You're built different."
        case 3:  return "3 years strong. Pure dedication."
        case 4:  return "4 years and counting. Unstoppable."
        case 5:  return "Half a decade of showing up."
        case 10: return "A full decade of miles. You are a legend."
        case 25: return "25 years. A lifetime of dedication."
        default: return "\(info.years) full years of showing up."
        }
    }

    private var headline: String {
        info.years == 1 ? "1 YEAR" : "\(info.years) YEARS"
    }

    private var shareText: String {
        let miles = Int(info.totalMiles.rounded())
        let yearLabel = info.years == 1 ? "1 YEAR" : "\(info.years) YEARS"
        let yearLine: String
        switch info.years {
        case 1:  yearLine = "🏆 1 YEAR of running a mile every single day."
        case 2:  yearLine = "🏆 2 YEARS strong. Every. Single. Day."
        case 3:  yearLine = "🏆 3 YEARS. 1,095 days of showing up."
        case 5:  yearLine = "🏆 5 YEARS. Half a decade of mile-a-day."
        case 10: yearLine = "🏆 10 YEARS. A full decade of miles."
        default: yearLine = "🏆 \(yearLabel) of running a mile every single day."
        }
        return """
        \(yearLine)
        🏃 \(info.totalStreakDays.formatted()) day streak
        📏 \(miles.formatted()) miles and counting

        Mile A Day · mileaday.run
        """
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
        VStack(spacing: 12) {
            Text(eyebrowLabel)
                .font(.system(size: 13, weight: .black, design: .rounded))
                .tracking(4)
                .foregroundColor(palette.accent.opacity(0.95))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, 16)
                .padding(.vertical, 7)
                .background(
                    Capsule()
                        .fill(.ultraThinMaterial)
                        .overlay(
                            Capsule()
                                .strokeBorder(palette.primary.opacity(0.45), lineWidth: 1)
                        )
                )

            Text(headline)
                .font(.system(size: info.years > 9 ? 88 : 120, weight: .black, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.35)
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
                .shadow(color: .black.opacity(0.55), radius: 8, x: 0, y: 4)
                .shadow(color: palette.primary.opacity(0.55), radius: 30, x: 0, y: 0)
                .padding(.horizontal, MADTheme.Spacing.md)
                .modifier(YearNumberShimmer(active: sustainedShimmer, color: palette.accent))

            Text(subtitle)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.85)
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
                .padding(.top, 4)
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
                        .fill(Color.black.opacity(0.25))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large, style: .continuous)
                        .strokeBorder(palette.primary.opacity(0.55), lineWidth: 1.2)
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
                .minimumScaleFactor(0.45)
                .shadow(color: .black.opacity(0.4), radius: 3, x: 0, y: 2)
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

    private var statDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.25))
            .frame(width: 1, height: 32)
    }

    private var streakStartLabel: String {
        guard let start = info.streakStartDate else { return "—" }
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d/yy"
        return formatter.string(from: start)
    }

    // MARK: - Buttons

    @ViewBuilder
    private var buttonRow: some View {
        VStack(spacing: 12) {
            Button {
                mediumHaptic.impactOccurred()
                if let image = generateShareCardImage() {
                    shareItem = ShareableImage(image: image)
                }
            } label: {
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
            .sheet(item: $shareItem) { item in
                YearlyMilestoneSharePreviewSheet(
                    image: item.image,
                    shareText: shareText,
                    palette: palette
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

    /// Render the milestone as a 600x900 image suitable for posting to social media.
    private func generateShareCardImage() -> UIImage? {
        let card = YearlyMilestoneShareCardView(info: info, palette: palette)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3.0
        renderer.isOpaque = false
        return renderer.uiImage
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

// MARK: - Yearly Milestone Share Card
// Rendered to UIImage via ImageRenderer for sharing/saving to social media.

struct YearlyMilestoneShareCardView: View {
    let info: YearlyMilestoneInfo
    let palette: YearPalette

    private let cardWidth: CGFloat = 600
    private let cardHeight: CGFloat = 900

    private var headline: String {
        info.years == 1 ? "1 YEAR" : "\(info.years) YEARS"
    }

    private var subtitle: String {
        switch info.years {
        case 1:  return "365 days. A full year. Legendary."
        case 2:  return "2 full years. Built different."
        case 3:  return "3 years strong. Pure dedication."
        case 4:  return "4 years and counting."
        case 5:  return "Half a decade of showing up."
        case 10: return "A decade of miles. A legend."
        case 25: return "25 years. A lifetime."
        default: return "\(info.years) full years of showing up."
        }
    }

    private var startedString: String {
        guard let start = info.streakStartDate else { return "—" }
        let f = DateFormatter()
        f.dateFormat = "M/d/yy"
        return f.string(from: start)
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: palette.backgroundGradient,
                startPoint: .top,
                endPoint: .bottom
            )

            RadialGradient(
                colors: [palette.primary.opacity(0.45), palette.primary.opacity(0.10), .clear],
                center: UnitPoint(x: 0.5, y: 0.32),
                startRadius: 30,
                endRadius: 420
            )

            VStack(spacing: 0) {
                Spacer(minLength: 70)

                Text("STREAK MILESTONE")
                    .font(.system(size: 14, weight: .black, design: .rounded))
                    .tracking(5)
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 9)
                    .background(
                        Capsule()
                            .fill(Color.black.opacity(0.35))
                            .overlay(
                                Capsule()
                                    .strokeBorder(palette.primary.opacity(0.6), lineWidth: 1.2)
                            )
                    )

                Spacer(minLength: 22)

                Text(headline)
                    .font(.system(size: info.years > 9 ? 110 : 132, weight: .black, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.35)
                    .foregroundStyle(
                        LinearGradient(colors: palette.textGradient, startPoint: .top, endPoint: .bottom)
                    )
                    .shadow(color: .black.opacity(0.55), radius: 10, x: 0, y: 6)
                    .shadow(color: palette.primary.opacity(0.5), radius: 24, x: 0, y: 6)
                    .padding(.horizontal, 36)

                Spacer(minLength: 18)

                Text(subtitle)
                    .font(.system(size: 21, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .minimumScaleFactor(0.85)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.black.opacity(0.32))
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .strokeBorder(palette.primary.opacity(0.5), lineWidth: 1.2)
                            )
                    )
                    .padding(.horizontal, 40)

                Spacer(minLength: 36)

                statsRow

                Spacer(minLength: 32)

                brandingFooter
                    .padding(.horizontal, 36)
                    .padding(.bottom, 32)
            }
        }
        .frame(width: cardWidth, height: cardHeight)
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [palette.primary.opacity(0.8), palette.secondary.opacity(0.4)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 3
                )
        )
    }

    private var statsRow: some View {
        HStack(spacing: 0) {
            shareStatColumn(
                value: info.totalStreakDays.formatted(),
                label: "Day Streak"
            )
            shareDivider
            shareStatColumn(
                value: Int(info.totalMiles.rounded()).formatted(),
                label: info.totalMiles == 1 ? "Mile" : "Miles"
            )
            shareDivider
            shareStatColumn(
                value: startedString,
                label: "Began"
            )
        }
        .padding(.vertical, 22)
        .padding(.horizontal, 24)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.black.opacity(0.35))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(palette.primary.opacity(0.55), lineWidth: 1.5)
                )
        )
        .padding(.horizontal, 36)
    }

    private func shareStatColumn(value: String, label: String) -> some View {
        VStack(spacing: 6) {
            Text(value)
                .font(.system(size: 26, weight: .black, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .foregroundStyle(
                    LinearGradient(colors: palette.textGradient, startPoint: .top, endPoint: .bottom)
                )
                .shadow(color: .black.opacity(0.4), radius: 4, x: 0, y: 2)
            Text(label.uppercased())
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .tracking(1.2)
                .foregroundColor(.white.opacity(0.95))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 6)
    }

    private var shareDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.25))
            .frame(width: 1, height: 40)
    }

    private var brandingFooter: some View {
        HStack(spacing: 12) {
            MADLogoMark(size: 38, opacity: 1, shadow: false)
            Spacer()
            Text("mileaday.run")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.7))
        }
    }
}

// MARK: - Share Preview Sheet
// Mirrors the dashboard streak-share preview UX: shows the rendered image first,
// then lets the user Copy (to clipboard) or Share via the system sheet.

struct YearlyMilestoneSharePreviewSheet: View {
    let image: UIImage
    let shareText: String
    let palette: YearPalette

    @Environment(\.dismiss) private var dismiss
    @State private var shareSheetItem: ShareableImage? = nil
    @State private var showingCopiedFeedback = false

    var body: some View {
        NavigationStack {
            ZStack {
                MADTheme.Colors.appBackgroundGradient.ignoresSafeArea()

                VStack(spacing: 18) {
                    // Image preview
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .shadow(color: .black.opacity(0.35), radius: 18, x: 0, y: 10)
                        .padding(.horizontal, 20)
                        .padding(.top, 8)

                    // Action buttons
                    HStack(spacing: 12) {
                        Button {
                            UIPasteboard.general.image = image
                            MADHaptics.action()
                            showingCopiedFeedback = true
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: showingCopiedFeedback ? "checkmark.circle.fill" : "doc.on.doc")
                                Text(showingCopiedFeedback ? "Copied!" : "Copy")
                            }
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(showingCopiedFeedback ? Color.green.opacity(0.85) : Color.white.opacity(0.12))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                                    )
                            )
                            .animation(.easeInOut(duration: 0.2), value: showingCopiedFeedback)
                        }

                        Button {
                            MADHaptics.action()
                            shareSheetItem = ShareableImage(image: image)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "square.and.arrow.up")
                                Text("Share")
                            }
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: [palette.primary, palette.secondary],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .shadow(color: palette.primary.opacity(0.5), radius: 12, x: 0, y: 4)
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
                }
            }
            .navigationTitle("Share This Win")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundColor(MADTheme.Colors.madRed)
                        .fontWeight(.semibold)
                }
            }
            .onChange(of: showingCopiedFeedback) { _, isShowing in
                guard isShowing else { return }
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    showingCopiedFeedback = false
                }
            }
            .sheet(item: $shareSheetItem) { item in
                ShareSheet(items: [item.image, shareText])
            }
        }
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
