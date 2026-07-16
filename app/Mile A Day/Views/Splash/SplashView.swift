import SwiftUI

/// Launch experience for Mile A Day.
///
/// Design intent: a calm, premium reveal built around the app's core mental
/// model — closing your daily mile. An atmospheric glow settles in, a goal
/// "ring" sweeps closed around the MAD mark (mirroring completing your mile),
/// the logo lands with a soft pulse, and the wordmark resolves beneath it.
/// No loose particles or external runner: the logo already carries the runner
/// + speed lines, so the ring is the only added motion, which keeps it clean
/// and legible at every screen size.
struct SplashView: View {
    @Environment(\.colorScheme) private var colorScheme

    // Atmosphere
    @State private var auraOpacity: Double = 0
    @State private var auraScale: CGFloat = 0.85

    // Goal ring (the "close your mile" sweep)
    @State private var ringProgress: CGFloat = 0
    @State private var ringOpacity: Double = 0
    @State private var trackOpacity: Double = 0

    // Logo
    @State private var logoScale: CGFloat = 0.7
    @State private var logoOpacity: Double = 0

    // Completion pulse when the ring closes
    @State private var pulseScale: CGFloat = 0.9
    @State private var pulseOpacity: Double = 0

    // Text
    @State private var titleOpacity: Double = 0
    @State private var titleOffset: CGFloat = 14
    @State private var taglineOpacity: Double = 0

    // MARK: - Layout constants (fixed → consistent on every device)
    private let ringSize: CGFloat = 176
    private let ringLineWidth: CGFloat = 6
    private let logoSize: CGFloat = 104

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

    private var trackColor: Color {
        isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.06)
    }

    private var backgroundView: some View {
        ZStack {
            // Base atmosphere
            (isDark ? Color(red: 0.05, green: 0.03, blue: 0.04)
                    : Color(red: 0.97, green: 0.96, blue: 0.96))
                .ignoresSafeArea()

            // Soft vertical depth
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
        ZStack {
            backgroundView

            VStack(spacing: 40) {
                logoStack

                textBlock
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { startAnimations() }
    }

    // MARK: - Logo + ring + glow

    private var logoStack: some View {
        ZStack {
            // Breathing atmospheric glow, centered on the mark
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            accentRed.opacity(isDark ? 0.40 : 0.20),
                            accentRed.opacity(0)
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: 190
                    )
                )
                .frame(width: 360, height: 360)
                .scaleEffect(auraScale)
                .opacity(auraOpacity)
                .blur(radius: 14)

            // Goal track (the unfilled ring)
            Circle()
                .stroke(trackColor, lineWidth: ringLineWidth)
                .frame(width: ringSize, height: ringSize)
                .opacity(trackOpacity)

            // Progress ring sweeping closed — "complete your mile"
            Circle()
                .trim(from: 0, to: ringProgress)
                .stroke(
                    AngularGradient(
                        // First/last stops match so the closed ring is seamless
                        gradient: Gradient(colors: [accentRed, accentBright, accentRed]),
                        center: .center,
                        startAngle: .degrees(-90),
                        endAngle: .degrees(270)
                    ),
                    style: StrokeStyle(lineWidth: ringLineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .frame(width: ringSize, height: ringSize)
                .opacity(ringOpacity)
                .shadow(color: accentRed.opacity(isDark ? 0.55 : 0.30), radius: 9)

            // Completion pulse — a quick ring flare when the sweep finishes
            Circle()
                .stroke(accentBright, lineWidth: 2)
                .frame(width: ringSize, height: ringSize)
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
        .frame(width: ringSize, height: ringSize)
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
        // Atmosphere fades in and starts a slow breath
        withAnimation(.easeOut(duration: 0.7)) {
            auraOpacity = 1.0
            auraScale = 1.0
            trackOpacity = 1.0
        }
        withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true)) {
            auraScale = 1.08
        }

        // Ring sweeps closed (0.2s → ~1.2s)
        withAnimation(.easeOut(duration: 0.25).delay(0.2)) {
            ringOpacity = 1.0
        }
        withAnimation(.easeInOut(duration: 1.0).delay(0.2)) {
            ringProgress = 1.0
        }

        // Logo lands as the ring fills
        withAnimation(.spring(response: 0.6, dampingFraction: 0.68).delay(0.45)) {
            logoScale = 1.0
            logoOpacity = 1.0
        }

        // Completion flare the instant the ring closes (~1.2s)
        withAnimation(.easeOut(duration: 0.45).delay(1.15)) {
            pulseScale = 1.16
            pulseOpacity = 0.9
        }
        withAnimation(.easeIn(duration: 0.5).delay(1.35)) {
            pulseOpacity = 0
        }

        // Wordmark resolves beneath the mark
        withAnimation(.easeOut(duration: 0.55).delay(1.35)) {
            titleOpacity = 1.0
            titleOffset = 0
        }
        withAnimation(.easeOut(duration: 0.55).delay(1.6)) {
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
