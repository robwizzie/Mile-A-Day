//
//  ParticleEffects.swift
//  Mile A Day
//

import SwiftUI

// MARK: - Sparkle Effect
struct SparkleView: View {
    let color: Color
    @State private var isAnimating = false
    @State private var opacity: Double = 0

    var body: some View {
        ZStack {
            ForEach(0..<8) { index in
                Rectangle()
                    .fill(color)
                    .frame(width: 2, height: isAnimating ? 20 : 0)
                    .offset(y: isAnimating ? -10 : 0)
                    .rotationEffect(.degrees(Double(index) * 45))
            }
        }
        .opacity(opacity)
        .onAppear {
            withAnimation(.easeOut(duration: 0.6)) {
                isAnimating = true
                opacity = 1
            }
            withAnimation(.easeIn(duration: 0.3).delay(0.3)) {
                opacity = 0
            }
        }
    }
}

// MARK: - Burst Particles
struct BurstParticle: Identifiable {
    let id = UUID()
    let color: Color
    let angle: Double
    let speed: Double
    let size: CGFloat
}

struct BurstEffect: View {
    let colors: [Color]
    let particleCount: Int
    @State private var particles: [BurstParticle] = []
    @State private var isAnimating = false

    init(colors: [Color] = [.red, .orange, .yellow, .pink, .purple], particleCount: Int = 30) {
        self.colors = colors
        self.particleCount = particleCount
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ForEach(particles) { particle in
                    Circle()
                        .fill(particle.color)
                        .frame(width: particle.size, height: particle.size)
                        .offset(
                            x: isAnimating ? cos(particle.angle) * particle.speed * 100 : 0,
                            y: isAnimating ? sin(particle.angle) * particle.speed * 100 : 0
                        )
                        .opacity(isAnimating ? 0 : 1)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
        .onAppear {
            generateParticles()
            withAnimation(.easeOut(duration: 1.2)) {
                isAnimating = true
            }
        }
    }

    private func generateParticles() {
        particles = (0..<particleCount).map { index in
            BurstParticle(
                color: colors.randomElement() ?? .red,
                angle: Double(index) * (2 * .pi / Double(particleCount)) + Double.random(in: -0.2...0.2),
                speed: Double.random(in: 0.6...1.2),
                size: CGFloat.random(in: 4...12)
            )
        }
    }
}

// MARK: - Floating Stars
struct FloatingStar: Identifiable {
    let id = UUID()
    let x: CGFloat
    let delay: Double
    let duration: Double
    let size: CGFloat
}

struct FloatingStarsEffect: View {
    let color: Color
    let starCount: Int
    @State private var stars: [FloatingStar] = []

    init(color: Color = .yellow, starCount: Int = 20) {
        self.color = color
        self.starCount = starCount
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ForEach(stars) { star in
                    StarShape()
                        .fill(color)
                        .frame(width: star.size, height: star.size)
                        .position(x: star.x, y: geometry.size.height)
                        .modifier(FloatingModifier(delay: star.delay, duration: star.duration, height: geometry.size.height))
                }
            }
        }
        .onAppear {
            generateStars()
        }
    }

    private func generateStars() {
        stars = (0..<starCount).map { index in
            FloatingStar(
                x: CGFloat.random(in: 0...UIScreen.main.bounds.width),
                delay: Double(index) * 0.1,
                duration: Double.random(in: 2...4),
                size: CGFloat.random(in: 10...20)
            )
        }
    }
}

struct FloatingModifier: ViewModifier {
    let delay: Double
    let duration: Double
    let height: CGFloat
    @State private var isAnimating = false

    func body(content: Content) -> some View {
        content
            .offset(y: isAnimating ? -height - 50 : 0)
            .opacity(isAnimating ? 0 : 1)
            .onAppear {
                withAnimation(.easeOut(duration: duration).delay(delay)) {
                    isAnimating = true
                }
            }
    }
}

struct StarShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outerRadius = min(rect.width, rect.height) / 2
        let innerRadius = outerRadius * 0.4
        let pointCount = 5

        for i in 0..<pointCount * 2 {
            let angle = CGFloat(i) * .pi / CGFloat(pointCount) - .pi / 2
            let radius = i.isMultiple(of: 2) ? outerRadius : innerRadius
            let point = CGPoint(
                x: center.x + cos(angle) * radius,
                y: center.y + sin(angle) * radius
            )
            if i == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        path.closeSubpath()
        return path
    }
}

// MARK: - Shimmer Effect
struct ShimmerEffect: ViewModifier {
    @State private var phase: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .overlay(
                LinearGradient(
                    gradient: Gradient(colors: [
                        .clear,
                        .white.opacity(0.3),
                        .clear
                    ]),
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .offset(x: phase)
                .mask(content)
            )
            .onAppear {
                withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
                    phase = 400
                }
            }
    }
}

extension View {
    func shimmer() -> some View {
        modifier(ShimmerEffect())
    }
}

// MARK: - Pulse Glow Effect
struct PulseGlowModifier: ViewModifier {
    @State private var isAnimating = false
    let color: Color
    let maxScale: CGFloat

    func body(content: Content) -> some View {
        content
            .shadow(color: color.opacity(isAnimating ? 0.6 : 0), radius: isAnimating ? 20 : 5)
            .scaleEffect(isAnimating ? maxScale : 1)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                    isAnimating = true
                }
            }
    }
}

extension View {
    func pulseGlow(color: Color = .yellow, maxScale: CGFloat = 1.05) -> some View {
        modifier(PulseGlowModifier(color: color, maxScale: maxScale))
    }
}
