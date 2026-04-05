//
//  FlameAnimationView.swift
//  Mile A Day
//

import SwiftUI

// MARK: - Flame Ignition Animation View
// Duolingo-inspired flame that ignites with a satisfying multi-phase animation

struct FlameAnimationView: View {
    @Binding var isIgnited: Bool
    var size: CGFloat = 80

    // Animation phases
    @State private var showEmber: Bool = false
    @State private var emberScale: CGFloat = 0.3
    @State private var flameOpacity: Double = 0
    @State private var flameScale: CGFloat = 0.1
    @State private var flameScaleX: CGFloat = 0.3
    @State private var glowRadius: CGFloat = 0
    @State private var glowOpacity: Double = 0
    @State private var flickerPhase: Bool = false
    @State private var emberParticles: [EmberParticle] = []
    @State private var showParticles: Bool = false

    private var flameSize: CGFloat { size }
    private let glowColor = MADTheme.Colors.madRed

    var body: some View {
        ZStack {
            // Layer 1: Outer warm glow
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            glowColor.opacity(glowOpacity * 0.4),
                            glowColor.opacity(glowOpacity * 0.15),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 10,
                        endRadius: 80
                    )
                )
                .frame(width: flameSize * 2, height: flameSize * 2)
                .scaleEffect(glowRadius > 0 ? 1.0 : 0.5)
                .blur(radius: 8)

            // Layer 2: Inner glow ring
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(glowOpacity * 0.5),
                            MADTheme.Colors.madRed.opacity(glowOpacity * 0.35),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 5,
                        endRadius: flameSize * 0.625
                    )
                )
                .frame(width: flameSize * 1.25, height: flameSize * 1.25)
                .blur(radius: 4)

            // Layer 3: Ember particles floating up
            if showParticles {
                ForEach(emberParticles) { particle in
                    EmberParticleView(particle: particle)
                }
            }

            // Layer 4: The flame itself — grows upward from base like a fire being lit
            ZStack {
                // Flame shadow/glow underneath
                Image(systemName: "flame.fill")
                    .font(.system(size: flameSize, weight: .medium))
                    .foregroundStyle(MADTheme.Colors.madRed.opacity(0.6))
                    .blur(radius: 12)
                    .scaleEffect(x: flameScaleX * 1.05, y: flameScale * 1.05, anchor: .bottom)

                // Main flame with gradient
                Image(systemName: "flame.fill")
                    .font(.system(size: flameSize, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(
                            stops: [
                                .init(color: Color(red: 1.0, green: 0.95, blue: 0.85), location: 0.0),  // White-hot core
                                .init(color: Color(red: 1.0, green: 0.65, blue: 0.55), location: 0.25), // Light red
                                .init(color: MADTheme.Colors.madRed, location: 0.55),                     // Brand red
                                .init(color: Color(red: 0.7, green: 0.15, blue: 0.25), location: 0.85),  // Deep red
                                .init(color: Color(red: 0.4, green: 0.08, blue: 0.15), location: 1.0)    // Dark red
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .shadow(color: MADTheme.Colors.madRed.opacity(0.7), radius: 16, x: 0, y: 4)
                    .shadow(color: Color.white.opacity(0.2), radius: 8, x: 0, y: -2)
                    .scaleEffect(x: flameScaleX, y: flameScale, anchor: .bottom)
                    .scaleEffect(x: flickerPhase ? 1.02 : 0.98, y: flickerPhase ? 1.04 : 0.97, anchor: .bottom)
            }
            .opacity(flameOpacity)

            // Layer 5: Initial spark/ember before ignition
            if showEmber && flameOpacity < 0.5 {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [.white, Color(red: 1.0, green: 0.65, blue: 0.55), MADTheme.Colors.madRed, .clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: 12
                        )
                    )
                    .frame(width: 24, height: 24)
                    .scaleEffect(emberScale)
                    .offset(y: 20)
            }
        }
        .onChange(of: isIgnited) { _, newValue in
            if newValue {
                startIgnitionSequence()
            }
        }
    }

    // MARK: - Ignition Sequence

    private func startIgnitionSequence() {
        // Phase 1: Spark appears at the base (0.0s)
        withAnimation(.easeOut(duration: 0.12)) {
            showEmber = true
            emberScale = 1.2
        }

        // Phase 2: Tiny flame catches from the spark — small and narrow at the base (0.12s)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            flameOpacity = 1.0
            withAnimation(.easeOut(duration: 0.3)) {
                flameScale = 0.35
                flameScaleX = 0.35
                glowOpacity = 0.25
                glowRadius = 0.3
            }
        }

        // Phase 3: Fire catches — grows taller and wider in one smooth motion (0.4s)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.55)) {
                flameScale = 1.15
                flameScaleX = 1.08
                glowRadius = 1.0
                glowOpacity = 1.0
            }
        }

        // Phase 4: Settle to final size (0.9s)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.65)) {
                flameScale = 1.0
                flameScaleX = 1.0
            }

            showParticles = true
            spawnEmberBurst()

            withAnimation(.easeInOut(duration: 0.4)) {
                glowOpacity = 0.6
            }
        }

        // Phase 5: Continuous flicker (1.1s)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
            startFlickerLoop()
        }
    }

    private func startFlickerLoop() {
        withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
            flickerPhase = true
        }

        // Subtle glow pulse
        withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
            glowOpacity = 0.8
        }
    }

    private func spawnEmberBurst() {
        emberParticles = (0..<14).map { _ in
            EmberParticle(
                startX: CGFloat.random(in: -20...20),
                startY: CGFloat.random(in: -15...5),
                endX: CGFloat.random(in: -50...50),
                endY: CGFloat.random(in: -90 ... -25),
                size: CGFloat.random(in: 2...6),
                duration: Double.random(in: 0.8...2.0),
                delay: Double.random(in: 0...0.5)
            )
        }
    }
}

// MARK: - Ember Particle

struct EmberParticle: Identifiable {
    let id = UUID()
    let startX: CGFloat
    let startY: CGFloat
    let endX: CGFloat
    let endY: CGFloat
    let size: CGFloat
    let duration: Double
    let delay: Double
}

struct EmberParticleView: View {
    let particle: EmberParticle

    @State private var progress: CGFloat = 0
    @State private var opacity: Double = 1.0

    var body: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [.white, MADTheme.Colors.madRed.opacity(0.8), MADTheme.Colors.madRed.opacity(0.3)],
                    center: .center,
                    startRadius: 0,
                    endRadius: particle.size
                )
            )
            .frame(width: particle.size, height: particle.size)
            .offset(
                x: particle.startX + (particle.endX - particle.startX) * progress,
                y: particle.startY + (particle.endY - particle.startY) * progress
            )
            .opacity(opacity)
            .onAppear {
                withAnimation(.easeOut(duration: particle.duration).delay(particle.delay)) {
                    progress = 1.0
                }
                withAnimation(.easeIn(duration: particle.duration * 0.7).delay(particle.delay + particle.duration * 0.3)) {
                    opacity = 0
                }
            }
    }
}

#Preview {
    ZStack {
        LinearGradient(
            colors: [
                Color(red: 0.15, green: 0.08, blue: 0.1),
                Color(red: 0.12, green: 0.06, blue: 0.08),
                Color(red: 0.05, green: 0.02, blue: 0.04)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()

        FlameAnimationView(isIgnited: .constant(true))
    }
}
