//
//  YearlyParticleEffects.swift
//  Mile A Day
//
//  Visual effects reserved for the once-a-year milestone celebration.
//  Designed to feel premium and distinct from the per-badge celebrations.
//

import SwiftUI

// MARK: - Palette

/// Per-year color palette. Each year evolves the look so subsequent years feel
/// fresh, but every year retains the same lavish choreography (no year is "lesser").
struct YearPalette {
    let primary: Color
    let secondary: Color
    let accent: Color
    let textGradient: [Color]
    let confettiColors: [Color]
    let backgroundGradient: [Color]
    let label: String

    static func forYear(_ year: Int) -> YearPalette {
        switch max(1, year) {
        case 1:
            return YearPalette(
                primary:   Color(red: 1.00, green: 0.84, blue: 0.30),
                secondary: Color(red: 0.95, green: 0.62, blue: 0.18),
                accent:    Color(red: 1.00, green: 0.95, blue: 0.65),
                textGradient: [
                    Color(red: 1.00, green: 0.97, blue: 0.78),
                    Color(red: 1.00, green: 0.84, blue: 0.30),
                    Color(red: 0.85, green: 0.55, blue: 0.10)
                ],
                confettiColors: [
                    Color(red: 1.00, green: 0.84, blue: 0.30),
                    Color(red: 1.00, green: 0.93, blue: 0.55),
                    Color(red: 0.92, green: 0.62, blue: 0.10),
                    .white
                ],
                backgroundGradient: [
                    Color(red: 0.10, green: 0.07, blue: 0.04),
                    Color(red: 0.18, green: 0.12, blue: 0.04),
                    Color(red: 0.05, green: 0.03, blue: 0.02)
                ],
                label: "Gold"
            )
        case 2:
            return YearPalette(
                primary:   Color(red: 0.97, green: 0.66, blue: 0.62),
                secondary: Color(red: 0.85, green: 0.42, blue: 0.45),
                accent:    Color(red: 1.00, green: 0.85, blue: 0.80),
                textGradient: [
                    Color(red: 1.00, green: 0.92, blue: 0.88),
                    Color(red: 0.97, green: 0.66, blue: 0.62),
                    Color(red: 0.78, green: 0.36, blue: 0.40)
                ],
                confettiColors: [
                    Color(red: 0.97, green: 0.66, blue: 0.62),
                    Color(red: 1.00, green: 0.85, blue: 0.80),
                    Color(red: 0.80, green: 0.40, blue: 0.45),
                    Color(red: 1.00, green: 0.93, blue: 0.88)
                ],
                backgroundGradient: [
                    Color(red: 0.10, green: 0.05, blue: 0.05),
                    Color(red: 0.16, green: 0.07, blue: 0.08),
                    Color(red: 0.05, green: 0.02, blue: 0.03)
                ],
                label: "Rose Gold"
            )
        case 3:
            return YearPalette(
                primary:   Color(red: 0.85, green: 0.88, blue: 0.93),
                secondary: Color(red: 0.62, green: 0.66, blue: 0.74),
                accent:    .white,
                textGradient: [
                    .white,
                    Color(red: 0.88, green: 0.92, blue: 0.96),
                    Color(red: 0.55, green: 0.62, blue: 0.72)
                ],
                confettiColors: [
                    Color(red: 0.92, green: 0.94, blue: 0.97),
                    Color(red: 0.70, green: 0.74, blue: 0.82),
                    .white,
                    Color(red: 0.45, green: 0.52, blue: 0.62)
                ],
                backgroundGradient: [
                    Color(red: 0.06, green: 0.07, blue: 0.10),
                    Color(red: 0.10, green: 0.12, blue: 0.16),
                    Color(red: 0.03, green: 0.04, blue: 0.06)
                ],
                label: "Platinum"
            )
        case 4:
            return YearPalette(
                primary:   Color(red: 0.40, green: 0.65, blue: 0.98),
                secondary: Color(red: 0.18, green: 0.40, blue: 0.85),
                accent:    Color(red: 0.85, green: 0.93, blue: 1.00),
                textGradient: [
                    Color(red: 0.92, green: 0.96, blue: 1.00),
                    Color(red: 0.40, green: 0.65, blue: 0.98),
                    Color(red: 0.10, green: 0.30, blue: 0.78)
                ],
                confettiColors: [
                    Color(red: 0.40, green: 0.65, blue: 0.98),
                    Color(red: 0.85, green: 0.93, blue: 1.00),
                    Color(red: 0.18, green: 0.40, blue: 0.85),
                    .white
                ],
                backgroundGradient: [
                    Color(red: 0.04, green: 0.06, blue: 0.12),
                    Color(red: 0.06, green: 0.10, blue: 0.20),
                    Color(red: 0.02, green: 0.03, blue: 0.07)
                ],
                label: "Sapphire"
            )
        case 5...9:
            return YearPalette(
                primary:   Color(red: 0.75, green: 0.95, blue: 1.00),
                secondary: Color(red: 0.45, green: 0.85, blue: 0.95),
                accent:    .white,
                textGradient: [
                    .white,
                    Color(red: 0.85, green: 0.97, blue: 1.00),
                    Color(red: 0.40, green: 0.80, blue: 0.95)
                ],
                confettiColors: [
                    .white,
                    Color(red: 0.75, green: 0.95, blue: 1.00),
                    Color(red: 0.45, green: 0.85, blue: 0.95),
                    Color(red: 0.92, green: 0.98, blue: 1.00)
                ],
                backgroundGradient: [
                    Color(red: 0.04, green: 0.08, blue: 0.10),
                    Color(red: 0.06, green: 0.12, blue: 0.16),
                    Color(red: 0.02, green: 0.04, blue: 0.06)
                ],
                label: "Diamond"
            )
        default:
            return YearPalette(
                primary:   Color(red: 0.95, green: 0.55, blue: 0.95),
                secondary: Color(red: 0.40, green: 0.85, blue: 0.95),
                accent:    Color(red: 1.00, green: 0.92, blue: 0.55),
                textGradient: [
                    Color(red: 1.00, green: 0.55, blue: 0.85),
                    Color(red: 0.55, green: 0.50, blue: 1.00),
                    Color(red: 0.40, green: 0.95, blue: 0.85),
                    Color(red: 1.00, green: 0.92, blue: 0.55)
                ],
                confettiColors: [
                    Color(red: 1.00, green: 0.55, blue: 0.85),
                    Color(red: 0.55, green: 0.50, blue: 1.00),
                    Color(red: 0.40, green: 0.95, blue: 0.85),
                    Color(red: 1.00, green: 0.92, blue: 0.55),
                    .white
                ],
                backgroundGradient: [
                    Color(red: 0.05, green: 0.04, blue: 0.10),
                    Color(red: 0.10, green: 0.06, blue: 0.14),
                    Color(red: 0.02, green: 0.02, blue: 0.05)
                ],
                label: "Holographic"
            )
        }
    }
}

// MARK: - Golden Rays

/// Slow rotating radial light beams emanating from screen center.
/// Used in Phase 1 to build anticipation.
struct GoldenRaysEffect: View {
    let color: Color
    var rayCount: Int = 16

    @State private var rotation: Double = 0
    @State private var opacity: Double = 0

    var body: some View {
        GeometryReader { geo in
            let maxDim = max(geo.size.width, geo.size.height) * 1.5
            ZStack {
                // Soft center glow
                RadialGradient(
                    colors: [color.opacity(0.55), color.opacity(0.15), .clear],
                    center: .center,
                    startRadius: 0,
                    endRadius: maxDim * 0.45
                )
                .blendMode(.screen)

                // Rays
                ForEach(0..<rayCount, id: \.self) { i in
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [color.opacity(0.0), color.opacity(0.55), color.opacity(0.0)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 80, height: maxDim)
                        .rotationEffect(.degrees(Double(i) * (360.0 / Double(rayCount))))
                        .blendMode(.screen)
                }
                .rotationEffect(.degrees(rotation))
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .opacity(opacity)
        }
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.easeOut(duration: 1.2)) { opacity = 1.0 }
            withAnimation(.linear(duration: 28).repeatForever(autoreverses: false)) {
                rotation = 360
            }
        }
    }
}

// MARK: - Fireworks

/// A single firework: radial particle burst with trail fade.
struct FireworkBurstView: View {
    let position: CGPoint
    let colors: [Color]
    let particleCount: Int
    let delay: Double

    @State private var animate = false
    @State private var visible = false

    var body: some View {
        ZStack {
            ForEach(0..<particleCount, id: \.self) { i in
                let angle = Double(i) * (2 * .pi / Double(particleCount))
                let distance: CGFloat = animate ? CGFloat.random(in: 90...160) : 0
                Circle()
                    .fill(colors.randomElement() ?? .white)
                    .frame(width: 6, height: 6)
                    .shadow(color: colors.randomElement()?.opacity(0.8) ?? .white, radius: 4)
                    .offset(x: cos(angle) * distance, y: sin(angle) * distance)
                    .opacity(animate ? 0 : 1)
            }
        }
        .position(position)
        .opacity(visible ? 1 : 0)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                visible = true
                withAnimation(.easeOut(duration: 1.1)) { animate = true }
            }
        }
    }
}

/// Multiple fireworks bursting at staggered positions during the climax.
struct FireworksShow: View {
    let palette: YearPalette

    var body: some View {
        GeometryReader { geo in
            ZStack {
                FireworkBurstView(
                    position: CGPoint(x: geo.size.width * 0.20, y: geo.size.height * 0.28),
                    colors: palette.confettiColors,
                    particleCount: 20,
                    delay: 0.0
                )
                FireworkBurstView(
                    position: CGPoint(x: geo.size.width * 0.80, y: geo.size.height * 0.32),
                    colors: palette.confettiColors,
                    particleCount: 22,
                    delay: 0.18
                )
                FireworkBurstView(
                    position: CGPoint(x: geo.size.width * 0.30, y: geo.size.height * 0.72),
                    colors: palette.confettiColors,
                    particleCount: 20,
                    delay: 0.34
                )
                FireworkBurstView(
                    position: CGPoint(x: geo.size.width * 0.78, y: geo.size.height * 0.68),
                    colors: palette.confettiColors,
                    particleCount: 22,
                    delay: 0.50
                )
                FireworkBurstView(
                    position: CGPoint(x: geo.size.width * 0.50, y: geo.size.height * 0.18),
                    colors: palette.confettiColors,
                    particleCount: 24,
                    delay: 0.70
                )
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Yearly Confetti

/// Premium confetti shower — denser, longer-falling, mixed shapes.
struct YearlyConfettiPiece: Identifiable {
    let id = UUID()
    let x: CGFloat
    let startY: CGFloat
    let endY: CGFloat
    let color: Color
    let size: CGFloat
    let rotation: Double
    let rotationSpeed: Double
    let swayAmplitude: CGFloat
    let swaySpeed: Double
    let delay: Double
    let duration: Double
    let shape: ConfettiShape
}

enum ConfettiShape: CaseIterable {
    case rectangle, circle, triangle, roundedSquare
}

struct YearlyConfettiView: View {
    let colors: [Color]
    let particleCount: Int

    @State private var pieces: [YearlyConfettiPiece] = []

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(pieces) { piece in
                    YearlyConfettiPieceView(piece: piece, screenHeight: geo.size.height)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .onAppear { generate(in: geo.size) }
        }
        .allowsHitTesting(false)
    }

    private func generate(in size: CGSize) {
        pieces = (0..<particleCount).map { _ in
            YearlyConfettiPiece(
                x: CGFloat.random(in: 0...size.width),
                startY: CGFloat.random(in: -size.height * 0.4 ... -20),
                endY: size.height + 80,
                color: colors.randomElement() ?? .white,
                size: CGFloat.random(in: 6...14),
                rotation: Double.random(in: 0...360),
                rotationSpeed: Double.random(in: 180...720) * (Bool.random() ? 1 : -1),
                swayAmplitude: CGFloat.random(in: 12...40),
                swaySpeed: Double.random(in: 1.0...2.4),
                delay: Double.random(in: 0...0.6),
                duration: Double.random(in: 2.6...4.2),
                shape: ConfettiShape.allCases.randomElement() ?? .rectangle
            )
        }
    }
}

private struct YearlyConfettiPieceView: View {
    let piece: YearlyConfettiPiece
    let screenHeight: CGFloat
    @State private var falling = false
    @State private var sway: CGFloat = 0
    @State private var rotation: Double = 0

    var body: some View {
        confettiShape
            .frame(width: piece.size, height: piece.size * (piece.shape == .rectangle ? 1.6 : 1.0))
            .rotationEffect(.degrees(piece.rotation + rotation))
            .position(
                x: piece.x + sway,
                y: falling ? piece.endY : piece.startY
            )
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + piece.delay) {
                    withAnimation(.easeIn(duration: piece.duration)) {
                        falling = true
                    }
                    withAnimation(.linear(duration: piece.duration).repeatForever(autoreverses: false)) {
                        rotation = piece.rotationSpeed
                    }
                    withAnimation(.easeInOut(duration: piece.swaySpeed).repeatForever(autoreverses: true)) {
                        sway = piece.swayAmplitude
                    }
                }
            }
    }

    @ViewBuilder
    private var confettiShape: some View {
        switch piece.shape {
        case .rectangle:     Rectangle().fill(piece.color)
        case .circle:        Circle().fill(piece.color)
        case .triangle:      Triangle().fill(piece.color)
        case .roundedSquare: RoundedRectangle(cornerRadius: 2).fill(piece.color)
        }
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

// MARK: - Shimmer overlay

/// A continuously sweeping highlight that gives the year numeral a "trophy" feel.
struct YearNumberShimmer: ViewModifier {
    let active: Bool
    let color: Color
    @State private var phase: CGFloat = -1.0

    func body(content: Content) -> some View {
        content
            .overlay(
                LinearGradient(
                    colors: [
                        .clear,
                        color.opacity(0.85),
                        .clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .blendMode(.screen)
                .mask(content)
                .offset(x: phase * 300)
                .opacity(active ? 1 : 0)
            )
            .onChange(of: active) { _, newValue in
                if newValue {
                    withAnimation(.linear(duration: 2.4).repeatForever(autoreverses: false)) {
                        phase = 1.5
                    }
                }
            }
    }
}

// MARK: - Calendar Flip

/// A "365 days" calendar that rapidly flips through every day of the year,
/// landing on the milestone day. Visual metaphor for completing a full year.
struct CalendarFlipCard: View {
    let palette: YearPalette
    let dayNumber: Int
    let totalDays: Int
    /// 0...1 — drives the page flip.
    let flipProgress: Double

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(Color.black.opacity(0.32))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(palette.primary.opacity(0.55), lineWidth: 1.5)
                )
                .shadow(color: palette.primary.opacity(0.45), radius: 22, x: 0, y: 0)

            VStack(spacing: 4) {
                Text("DAY")
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .tracking(4)
                    .foregroundColor(.white.opacity(0.95))
                    .lineLimit(1)

                Text("\(dayNumber)")
                    .font(.system(size: 82, weight: .black, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                    .foregroundStyle(
                        LinearGradient(colors: palette.textGradient, startPoint: .top, endPoint: .bottom)
                    )
                    .shadow(color: .black.opacity(0.45), radius: 4, x: 0, y: 2)
                    .contentTransition(.numericText())
                    .animation(.easeOut(duration: 0.05), value: dayNumber)
                    .padding(.horizontal, 6)

                Text("of \(totalDays.formatted())")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.85))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, 6)
            }
            .padding(20)
        }
        .rotation3DEffect(
            .degrees(flipProgress * 14),
            axis: (x: 1, y: 0, z: 0),
            perspective: 0.6
        )
    }
}
