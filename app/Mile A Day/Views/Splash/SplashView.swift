import SwiftUI

struct SplashView: View {
    @Environment(\.colorScheme) private var colorScheme

    // Runner animation
    @State private var runnerX: CGFloat = -100
    @State private var runnerOpacity: Double = 0
    @State private var runnerScale: CGFloat = 1.0

    // Logo
    @State private var logoScale: CGFloat = 0.3
    @State private var logoOpacity: Double = 0

    // Speed lines
    @State private var speedLinesOffset: CGFloat = 0
    @State private var speedLinesOpacity: Double = 0

    // Dust particles
    @State private var dustOpacity: Double = 0
    @State private var dustSpread: CGFloat = 0

    // Text
    @State private var textOpacity: Double = 0
    @State private var textOffset: CGFloat = 15
    @State private var taglineOpacity: Double = 0

    private var backgroundGradient: LinearGradient {
        colorScheme == .dark
            ? LinearGradient(
                colors: [
                    Color(red: 0.12, green: 0.06, blue: 0.08),
                    Color(red: 0.06, green: 0.03, blue: 0.04)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            : LinearGradient(
                colors: [
                    Color(red: 0.98, green: 0.97, blue: 0.97),
                    Color(red: 0.94, green: 0.93, blue: 0.94)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
    }

    private var titleColor: Color {
        colorScheme == .dark ? .white : Color(red: 0.12, green: 0.12, blue: 0.14)
    }

    private var subtitleColor: Color {
        colorScheme == .dark ? .white.opacity(0.7) : Color(red: 0.4, green: 0.38, blue: 0.42)
    }

    private var trailColor: Color {
        MADTheme.Colors.madRed.opacity(colorScheme == .dark ? 0.6 : 0.4)
    }

    var body: some View {
        GeometryReader { geometry in
            let centerX = geometry.size.width / 2
            let centerY = geometry.size.height * 0.38

            ZStack {
                // Background
                backgroundGradient
                    .ignoresSafeArea()

                // Speed lines behind logo (appear after runner arrives)
                ZStack {
                    ForEach(0..<6, id: \.self) { index in
                        let yOffset = CGFloat(index - 3) * 14
                        let width: CGFloat = CGFloat(80 - index * 8)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        MADTheme.Colors.madRed.opacity(0.5),
                                        MADTheme.Colors.madRed.opacity(0)
                                    ],
                                    startPoint: .trailing,
                                    endPoint: .leading
                                )
                            )
                            .frame(width: width, height: 3)
                            .offset(x: -speedLinesOffset - 70, y: yOffset)
                            .opacity(speedLinesOpacity)
                    }
                }
                .position(x: centerX, y: centerY)

                // Runner figure
                Image(systemName: "figure.run")
                    .font(.system(size: 50, weight: .medium))
                    .foregroundColor(MADTheme.Colors.madRed)
                    .scaleEffect(runnerScale)
                    .opacity(runnerOpacity)
                    .position(x: runnerX, y: centerY)

                // Dust/energy burst particles (appear when runner becomes logo)
                ZStack {
                    ForEach(0..<8, id: \.self) { index in
                        let angle = Double(index) * (360.0 / 8.0)
                        let radians = angle * .pi / 180
                        Circle()
                            .fill(MADTheme.Colors.madRed.opacity(0.4))
                            .frame(width: 6, height: 6)
                            .offset(
                                x: cos(radians) * dustSpread,
                                y: sin(radians) * dustSpread
                            )
                            .opacity(dustOpacity)
                    }
                }
                .position(x: centerX, y: centerY)

                // MAD Logo
                Image("mad-logo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 130, height: 130)
                    .scaleEffect(logoScale)
                    .opacity(logoOpacity)
                    .shadow(
                        color: MADTheme.Colors.madRed.opacity(colorScheme == .dark ? 0.4 : 0.2),
                        radius: 25,
                        x: 0,
                        y: 8
                    )
                    .position(x: centerX, y: centerY)

                // Title and tagline
                VStack(spacing: MADTheme.Spacing.sm) {
                    Text("MILE A DAY")
                        .font(.system(size: 36, weight: .black, design: .rounded))
                        .foregroundColor(titleColor)
                        .tracking(3)
                        .opacity(textOpacity)
                        .offset(y: textOffset)

                    Text("Stay Active. Stay Motivated.")
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundColor(subtitleColor)
                        .opacity(taglineOpacity)
                        .offset(y: textOffset)
                }
                .position(x: centerX, y: centerY + 115)
            }
        }
        .onAppear {
            startAnimations()
        }
    }

    private func startAnimations() {
        // Phase 1: Runner sprints in from left to center (0.0 - 0.7s)
        withAnimation(.easeIn(duration: 0.15)) {
            runnerOpacity = 1.0
        }
        withAnimation(.easeOut(duration: 0.65).delay(0.05)) {
            runnerX = UIScreen.main.bounds.width / 2
        }

        // Phase 2: Runner shrinks and fades, logo punches in (0.6 - 1.0s)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            withAnimation(.easeIn(duration: 0.15)) {
                runnerOpacity = 0
                runnerScale = 0.5
            }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
                logoScale = 1.0
                logoOpacity = 1.0
            }

            // Dust burst
            withAnimation(.easeOut(duration: 0.4)) {
                dustOpacity = 0.8
                dustSpread = 90
            }
            withAnimation(.easeIn(duration: 0.3).delay(0.3)) {
                dustOpacity = 0
            }

            // Speed lines shoot out
            withAnimation(.easeOut(duration: 0.5)) {
                speedLinesOpacity = 1.0
                speedLinesOffset = 20
            }
            withAnimation(.easeIn(duration: 0.4).delay(0.4)) {
                speedLinesOpacity = 0
            }
        }

        // Phase 3: Title slides up and fades in (1.0 - 1.4s)
        withAnimation(.easeOut(duration: 0.5).delay(1.0)) {
            textOpacity = 1.0
            textOffset = 0
        }

        // Tagline follows
        withAnimation(.easeOut(duration: 0.4).delay(1.3)) {
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
