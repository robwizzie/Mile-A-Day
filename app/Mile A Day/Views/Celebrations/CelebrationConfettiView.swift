import SwiftUI

// MARK: - Celebration Confetti

struct CelebrationConfetti: View {
    @State private var particles: [ConfettiPiece2] = []

    private let confettiColors: [Color] = [
        MADTheme.Colors.madRed,
        Color(red: 0.9, green: 0.3, blue: 0.4),
        .white,
        .white.opacity(0.85),
        Color(red: 1.0, green: 0.55, blue: 0.65),
        Color(red: 0.7, green: 0.2, blue: 0.3),
        MADTheme.Colors.madRed.opacity(0.7),
        Color(red: 0.95, green: 0.85, blue: 0.85),
    ]

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(particles) { particle in
                    ConfettiPieceView(particle: particle, screenSize: geo.size)
                }
            }
            .onAppear {
                let centerX = geo.size.width / 2

                let wave1 = (0..<25).map { _ in
                    ConfettiPiece2(
                        color: confettiColors.randomElement()!,
                        startX: centerX + CGFloat.random(in: -40...40),
                        startY: -20,
                        shape: CelebrationConfettiShape.allCases.randomElement()!,
                        size: CGFloat.random(in: 6...12),
                        delay: Double.random(in: 0...0.3),
                        duration: Double.random(in: 2.5...4.0),
                        swayAmount: CGFloat.random(in: 30...80),
                        driftX: CGFloat.random(in: -60...60)
                    )
                }

                let wave2 = (0..<15).map { _ -> ConfettiPiece2 in
                    let fromLeft = Bool.random()
                    return ConfettiPiece2(
                        color: confettiColors.randomElement()!,
                        startX: fromLeft ? -10 : geo.size.width + 10,
                        startY: CGFloat.random(in: 50...200),
                        shape: CelebrationConfettiShape.allCases.randomElement()!,
                        size: CGFloat.random(in: 5...10),
                        delay: Double.random(in: 0.3...0.7),
                        duration: Double.random(in: 2.0...3.5),
                        swayAmount: CGFloat.random(in: 20...50),
                        driftX: fromLeft ? CGFloat.random(in: 30...120) : CGFloat.random(in: -120 ... -30)
                    )
                }

                let wave3 = (0..<10).map { _ in
                    ConfettiPiece2(
                        color: confettiColors.randomElement()!,
                        startX: CGFloat.random(in: 0...geo.size.width),
                        startY: -30,
                        shape: CelebrationConfettiShape.allCases.randomElement()!,
                        size: CGFloat.random(in: 4...8),
                        delay: Double.random(in: 1.0...1.8),
                        duration: Double.random(in: 3.0...5.0),
                        swayAmount: CGFloat.random(in: 20...40),
                        driftX: CGFloat.random(in: -30...30)
                    )
                }

                particles = wave1 + wave2 + wave3
            }
        }
    }
}

// CelebrationConfettiShape is defined in CelebrationConfettiTypes.swift

struct ConfettiPiece2: Identifiable {
    let id = UUID()
    let color: Color
    let startX: CGFloat
    let startY: CGFloat
    let shape: CelebrationConfettiShape
    let size: CGFloat
    let delay: Double
    let duration: Double
    let swayAmount: CGFloat
    let driftX: CGFloat
}

struct ConfettiPieceView: View {
    let particle: ConfettiPiece2
    let screenSize: CGSize

    @State private var yOffset: CGFloat = 0
    @State private var xOffset: CGFloat = 0
    @State private var rotation: Double = 0
    @State private var rotation3D: Double = 0
    @State private var sway: CGFloat = 0
    @State private var opacity: Double = 1.0

    var body: some View {
        Group {
            switch particle.shape {
            case .rectangle:
                Rectangle()
                    .fill(particle.color)
                    .frame(width: particle.size, height: particle.size * 1.6)
            case .circle:
                Circle()
                    .fill(particle.color)
                    .frame(width: particle.size, height: particle.size)
            case .roundedSquare:
                RoundedRectangle(cornerRadius: 2)
                    .fill(particle.color)
                    .frame(width: particle.size, height: particle.size)
            case .triangle:
                CelebrationTriangle()
                    .fill(particle.color)
                    .frame(width: particle.size, height: particle.size)
            }
        }
        .rotation3DEffect(.degrees(rotation3D), axis: (x: 1, y: 0, z: 0))
        .rotationEffect(.degrees(rotation))
        .opacity(opacity)
        .offset(x: particle.startX + xOffset + sway, y: particle.startY + yOffset)
        .onAppear {
            withAnimation(.easeIn(duration: particle.duration).delay(particle.delay)) {
                yOffset = screenSize.height + 80
            }
            withAnimation(.easeOut(duration: particle.duration * 0.8).delay(particle.delay)) {
                xOffset = particle.driftX
            }
            withAnimation(.linear(duration: particle.duration).delay(particle.delay)) {
                rotation = Double.random(in: 360...1080)
            }
            withAnimation(.linear(duration: particle.duration * 0.4).delay(particle.delay).repeatForever(autoreverses: false)) {
                rotation3D = 360
            }
            withAnimation(.easeInOut(duration: 0.6).delay(particle.delay).repeatForever(autoreverses: true)) {
                sway = CGFloat.random(in: -particle.swayAmount...particle.swayAmount)
            }
            withAnimation(.easeIn(duration: particle.duration * 0.3).delay(particle.delay + particle.duration * 0.7)) {
                opacity = 0
            }
        }
    }
}
