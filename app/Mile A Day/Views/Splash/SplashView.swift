import SwiftUI

/// Launch experience for Mile A Day.
///
/// Design intent: keep the signature "sprint in" entrance, but cleaner. A
/// runner sprints in from the left trailed by a soft motion blur (ghosted
/// echoes that converge on center, rather than a fan of speed lines), hands
/// off to the MAD mark at center with a single glow bloom and one impact
/// ring (rather than a burst of dust particles), then the wordmark resolves
/// beneath it. Layout is a single centered stack so it holds at every size.
struct SplashView: View {
    @Environment(\.colorScheme) private var colorScheme

    // Runner sprint (progress 0 = offscreen left, 1 = centered on the mark)
    @State private var runProgress: CGFloat = 0
    @State private var runnerOpacity: Double = 0
    @State private var trailOpacity: Double = 0
    @State private var runnerScale: CGFloat = 1.0

    // Atmosphere
    @State private var auraOpacity: Double = 0
    @State private var auraIntroScale: CGFloat = 0.85
    @State private var auraBreathe: CGFloat = 1.0

    // Logo
    @State private var logoScale: CGFloat = 0.5
    @State private var logoOpacity: Double = 0

    // Impact ring when the runner lands as the mark
    @State private var pulseScale: CGFloat = 0.6
    @State private var pulseOpacity: Double = 0

    // Text
    @State private var titleOpacity: Double = 0
    @State private var titleOffset: CGFloat = 14
    @State private var taglineOpacity: Double = 0

    // MARK: - Layout constants (fixed → consistent on every device)
    private let stageSize: CGFloat = 176
    private let logoSize: CGFloat = 104
    private let runnerSize: CGFloat = 48

    // Motion-blur echoes: tight spacing + low opacity reads as one clean streak
    private let echoSpacing: [CGFloat] = [16, 30, 42]
    private let echoOpacity: [Double] = [0.45, 0.28, 0.15]

    // MARK: - Palette
    private var isDark: Bool { colorScheme == .dark }
    private var accentRed: Color { MADTheme.Colors.madRed }
    private var accentBright: Color { Color(red: 1.0, green: 0.44, blue: 0.54) }

    private var titleColor: Color {
        isDark ? .white : Color(red: 0.11, green: 0.11, blue: 0.13)
    }
    private var subtitleColor: Color {
        isDark ? .white.opacity(0.62) : Color(red: 0.42, green: 0.40, blue: 0.44)
    }

    private var backgroundView: some View {
        ZStack {
            (isDark ? Color(red: 0.05, green: 0.03, blue: 0.04)
                    : Color(red: 0.97, green: 0.96, blue: 0.96))
                .ignoresSafeArea()

            LinearGradient(
                colors: isDark
                    ? [Color(red: 0.13, green: 0.06, blue: 0.08),
                       Color(red: 0.05, green: 0.03, blue: 0.04),
                       Color(red: 0.03, green: 0.02, blue: 0.03)]
                    : [Color(red: 0.99, green: 0.98, blue: 0.98),
                       Color(red: 0.95, green: 0.94, blue: 0.95),
                       Color(red: 0.92, green: 0.91, blue: 0.93)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        }
    }

    var body: some View {
        GeometryReader { geo in
            // Start fully offscreen-left regardless of device width
            let startX = -(geo.size.width / 2 + 80)
            let runnerX = startX * (1 - runProgress)

            ZStack {
                backgroundView

                VStack(spacing: 40) {
                    stage(runnerX: runnerX)
                    textBlock
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 32)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea()
        .onAppear { startAnimations() }
    }

    // MARK: - Runner + logo stage

    private func stage(runnerX: CGFloat) -> some View {
        ZStack {
            // Breathing glow that blooms as the mark lands
            Circle()
                .fill(
                    RadialGradient(
                        colors: [accentRed.opacity(isDark ? 0.40 : 0.20), accentRed.opacity(0)],
                        center: .center, startRadius: 0, endRadius: 190
                    )
                )
                .frame(width: 360, height: 360)
                .scaleEffect(auraIntroScale)
                .scaleEffect(auraBreathe)
                .opacity(auraOpacity)
                .blur(radius: 14)

            // Motion-blur echoes (converge on center as the runner slows)
            ForEach(0..<echoSpacing.count, id: \.self) { i in
                Image(systemName: "figure.run")
                    .font(.system(size: runnerSize, weight: .medium))
                    .foregroundColor(accentRed)
                    .scaleEffect(runnerScale)
                    .opacity(trailOpacity * echoOpacity[i])
                    .blur(radius: 1.5)
                    .offset(x: runnerX - echoSpacing[i] * (1 - runProgress))
            }

            // Lead runner
            Image(systemName: "figure.run")
                .font(.system(size: runnerSize, weight: .semibold))
                .foregroundColor(accentRed)
                .scaleEffect(runnerScale)
                .opacity(runnerOpacity)
                .offset(x: runnerX)

            // Impact ring
            Circle()
                .stroke(accentBright, lineWidth: 2)
                .frame(width: stageSize * 0.86, height: stageSize * 0.86)
                .scaleEffect(pulseScale)
                .opacity(pulseOpacity)

            // MAD mark
            Image("mad-logo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: logoSize, height: logoSize)
                .scaleEffect(logoScale)
                .opacity(logoOpacity)
                .shadow(color: accentRed.opacity(isDark ? 0.35 : 0.18), radius: 22, x: 0, y: 10)
        }
        .frame(width: stageSize, height: stageSize)
    }

    // MARK: - Text

    private var textBlock: some View {
        VStack(spacing: MADTheme.Spacing.sm) {
            Text("MILE A DAY")
                .font(.system(size: 38, weight: .black, design: .rounded))
                .tracking(4)
                .foregroundColor(titleColor)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .opacity(titleOpacity)
                .offset(y: titleOffset)

            Text("Stay Active. Stay Motivated.")
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundColor(subtitleColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .opacity(taglineOpacity)
                .offset(y: titleOffset)
        }
        .multilineTextAlignment(.center)
    }

    // MARK: - Animation timeline (settles well before the 2.5s dismiss)

    private func startAnimations() {
        // Phase 1 — runner sprints in from the left and decelerates to center
        withAnimation(.easeIn(duration: 0.12)) {
            runnerOpacity = 1.0
            trailOpacity = 1.0
        }
        withAnimation(.easeOut(duration: 0.72).delay(0.04)) {
            runProgress = 1.0
        }

        // Phase 2 — hand off to the mark (~0.6s, as the sprint settles)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            // Runner + trail dissolve and shrink into the mark
            withAnimation(.easeIn(duration: 0.18)) {
                runnerOpacity = 0
                trailOpacity = 0
                runnerScale = 0.5
            }

            // Glow blooms, then breathes
            withAnimation(.easeOut(duration: 0.55)) {
                auraOpacity = 1.0
                auraIntroScale = 1.0
            }
            withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true).delay(0.55)) {
                auraBreathe = 1.08
            }

            // Logo punches in
            withAnimation(.spring(response: 0.5, dampingFraction: 0.62)) {
                logoScale = 1.0
                logoOpacity = 1.0
            }

            // Single impact ring
            withAnimation(.easeOut(duration: 0.5)) {
                pulseScale = 1.22
                pulseOpacity = 0.85
            }
            withAnimation(.easeIn(duration: 0.45).delay(0.25)) {
                pulseOpacity = 0
            }
        }

        // Phase 3 — wordmark resolves beneath the mark
        withAnimation(.easeOut(duration: 0.5).delay(1.05)) {
            titleOpacity = 1.0
            titleOffset = 0
        }
        withAnimation(.easeOut(duration: 0.4).delay(1.35)) {
            taglineOpacity = 1.0
        }
    }
}

#Preview("Dark") {
    SplashView()
        .preferredColorScheme(.dark)
}

#Preview("Light") {
    SplashView()
        .preferredColorScheme(.light)
}
