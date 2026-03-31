//
//  FlameAnimationView.swift
//  Mile A Day
//

import SwiftUI

// MARK: - Flame Ignition Animation View
// Duolingo-inspired flame that ignites with a satisfying multi-phase animation

struct FlameAnimationView: View {
    @Binding var isIgnited: Bool

    // Animation phases
    @State private var showEmber: Bool = false
    @State private var emberScale: CGFloat = 0.3
    @State private var flameOpacity: Double = 0
    @State private var flameScale: CGFloat = 0.2
    @State private var glowRadius: CGFloat = 0
    @State private var glowOpacity: Double = 0
    @State private var flameOffset: CGFloat = 8
    @State private var flickerPhase: Bool = false
    @State private var emberParticles: [EmberParticle] = []
    @State private var showParticles: Bool = false

    private let flameSize: CGFloat = 72
    private let glowColor = Color(red: 1.0, green: 0.5, blue: 0.1)

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
                .frame(width: 160, height: 160)
                .scaleEffect(glowRadius > 0 ? 1.0 : 0.5)
                .blur(radius: 8)

            // Layer 2: Inner glow ring
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.yellow.opacity(glowOpacity * 0.5),
                            Color.orange.opacity(glowOpacity * 0.25),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 5,
                        endRadius: 50
                    )
                )
                .frame(width: 100, height: 100)
                .blur(radius: 4)

            // Layer 3: Ember particles floating up
            if showParticles {
                ForEach(emberParticles) { particle in
                    EmberParticleView(particle: particle)
                }
            }

            // Layer 4: The flame itself
            ZStack {
                // Flame shadow/glow underneath
                Image(systemName: "flame.fill")
                    .font(.system(size: flameSize, weight: .medium))
                    .foregroundStyle(Color.orange.opacity(0.6))
                    .blur(radius: 12)
                    .scaleEffect(flameScale * 1.1)

                // Main flame with gradient
                Image(systemName: "flame.fill")
                    .font(.system(size: flameSize, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(
                            stops: [
                                .init(color: Color(red: 1.0, green: 1.0, blue: 0.7), location: 0.0),
                                .init(color: .yellow, location: 0.25),
                                .init(color: .orange, location: 0.55),
                                .init(color: Color(red: 1.0, green: 0.25, blue: 0.05), location: 0.85),
                                .init(color: Color(red: 0.8, green: 0.15, blue: 0.05), location: 1.0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .shadow(color: .orange.opacity(0.7), radius: 16, x: 0, y: 4)
                    .shadow(color: .yellow.opacity(0.3), radius: 8, x: 0, y: -2)
                    .scaleEffect(flameScale)
                    .scaleEffect(x: flickerPhase ? 1.02 : 0.98, y: flickerPhase ? 1.04 : 0.97)
            }
            .opacity(flameOpacity)
            .offset(y: flameOffset)

            // Layer 5: Initial spark/ember before ignition
            if showEmber && flameOpacity < 0.5 {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [.white, .yellow, .orange, .clear],
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
        // Phase 1: Spark appears (0.0s)
        withAnimation(.easeOut(duration: 0.15)) {
            showEmber = true
            emberScale = 1.0
        }

        // Phase 2: Flame ignites from spark (0.15s)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.55, blendDuration: 0)) {
                flameOpacity = 1.0
                flameScale = 1.15 // Overshoot slightly
                flameOffset = 0
            }

            // Glow expands
            withAnimation(.easeOut(duration: 0.6)) {
                glowRadius = 1.0
                glowOpacity = 1.0
            }
        }

        // Phase 3: Settle to natural size (0.5s)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                flameScale = 1.0
            }

            // Start ember particles
            showParticles = true
            spawnEmberBurst()

            // Glow settles to steady state
            withAnimation(.easeInOut(duration: 0.5)) {
                glowOpacity = 0.6
            }
        }

        // Phase 4: Start continuous flicker (0.8s)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
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
        emberParticles = (0..<8).map { _ in
            EmberParticle(
                startX: CGFloat.random(in: -15...15),
                startY: CGFloat.random(in: -10...5),
                endX: CGFloat.random(in: -35...35),
                endY: CGFloat.random(in: -70 ... -30),
                size: CGFloat.random(in: 2...5),
                duration: Double.random(in: 0.8...1.6),
                delay: Double.random(in: 0...0.4)
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
                    colors: [.white, .yellow, .orange.opacity(0.5)],
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
                Color(red: 0.95, green: 0.55, blue: 0.1),
                Color(red: 0.85, green: 0.25, blue: 0.15),
                Color(red: 0.15, green: 0.08, blue: 0.05)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()

        FlameAnimationView(isIgnited: .constant(true))
    }
}
