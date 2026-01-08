import SwiftUI
import HealthKit

struct ContentView: View {
    @EnvironmentObject var healthManager: HealthKitManager
    @EnvironmentObject var userManager: UserManager
    @State private var showWorkoutView = false
    @State private var selectedActivityType: HKWorkoutActivityType = .running
    @State private var showCelebration = false
    @State private var hasShownCelebration = false

    // MAD Theme Colors
    private let madRed = Color(red: 217/255, green: 64/255, blue: 63/255)
    private let madOrange = Color.orange

    private var goalDistance: Double {
        userManager.currentUser.goalMiles > 0 ? userManager.currentUser.goalMiles : 1.0
    }

    private var currentDistance: Double {
        healthManager.todaysDistance
    }

    private var progress: Double {
        min(currentDistance / goalDistance, 1.0)
    }

    private var isCompleted: Bool {
        currentDistance >= goalDistance
    }

    var body: some View {
        ZStack {
            // Main content
            VStack(spacing: 0) {
                // App title with logo
                HStack(spacing: 4) {
                    Image(systemName: "figure.run")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(madRed)
                    Text("Mile A Day")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(.primary)
                }
                .padding(.top, 8)
                .padding(.bottom, 4)

                Spacer()

                // RUN and WALK buttons
                VStack(spacing: 12) {
                    // RUN button
                    Button(action: {
                        selectedActivityType = .running
                        showWorkoutView = true
                    }) {
                        HStack(spacing: 12) {
                            Image(systemName: "figure.run")
                                .font(.system(size: 32, weight: .medium))
                                .foregroundColor(.white)
                            Text("RUN")
                                .font(.system(size: 24, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 64)
                        .background(
                            RoundedRectangle(cornerRadius: 32)
                                .fill(madRed)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 32)
                                .stroke(madRed.opacity(0.3), lineWidth: 3)
                        )
                    }
                    .buttonStyle(.plain)

                    // WALK button
                    Button(action: {
                        selectedActivityType = .walking
                        showWorkoutView = true
                    }) {
                        HStack(spacing: 12) {
                            Image(systemName: "figure.walk")
                                .font(.system(size: 32, weight: .medium))
                                .foregroundColor(.white)
                            Text("WALK")
                                .font(.system(size: 24, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 64)
                        .background(
                            RoundedRectangle(cornerRadius: 32)
                                .fill(Color.black.opacity(0.6))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 32)
                                .stroke(Color.white.opacity(0.3), lineWidth: 2)
                        )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)

                Spacer()

                // Today's progress
                VStack(spacing: 2) {
                    Text(String(format: "Today: %.1f / %.1f mi", currentDistance, goalDistance))
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(.secondary)

                    // Mini progress bar
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            // Background
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.secondary.opacity(0.2))
                                .frame(height: 4)

                            // Progress
                            RoundedRectangle(cornerRadius: 2)
                                .fill(
                                    LinearGradient(
                                        colors: isCompleted
                                            ? [Color.green, Color.green.opacity(0.8)]
                                            : [madRed, madOrange],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: geometry.size.width * progress, height: 4)
                                .animation(.spring(response: 0.6, dampingFraction: 0.8), value: progress)
                        }
                    }
                    .frame(height: 4)
                    .padding(.horizontal, 24)
                }
                .padding(.bottom, 12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Celebration animation overlay
            if showCelebration {
                CelebrationView(madRed: madRed, madOrange: madOrange)
                    .transition(.scale.combined(with: .opacity))
                    .zIndex(100)
            }
        }
        .fullScreenCover(isPresented: $showWorkoutView) {
            WorkoutView(
                healthManager: healthManager,
                userManager: userManager,
                goalDistance: goalDistance,
                startingDistance: currentDistance,
                activityType: selectedActivityType
            )
        }
        .onAppear {
            // Refresh data when view appears
            healthManager.fetchTodaysDistance()
        }
        .onChange(of: showWorkoutView) { oldValue, newValue in
            // When workout view is dismissed, refresh data
            if oldValue && !newValue {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    healthManager.fetchTodaysDistance()
                }
            }
        }
        .onChange(of: isCompleted) { oldValue, newValue in
            // Show celebration when goal is first completed
            if newValue && !oldValue && !hasShownCelebration {
                hasShownCelebration = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                        showCelebration = true
                    }
                }

                // Hide celebration after 2.5 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.7) {
                    withAnimation(.easeOut(duration: 0.3)) {
                        showCelebration = false
                    }
                }
            }
        }
    }
}

// MARK: - Celebration View
struct CelebrationView: View {
    let madRed: Color
    let madOrange: Color
    @State private var scale: CGFloat = 0.3
    @State private var rotation: Double = 0
    @State private var particles: [Particle] = []
    @State private var glowScale: CGFloat = 1.0
    
    var body: some View {
        ZStack {
            // Background blur
            Color.black.opacity(0.5)
                .ignoresSafeArea()
            
            // Confetti particles
            ForEach(particles) { particle in
                Circle()
                    .fill(particle.color)
                    .frame(width: particle.size, height: particle.size)
                    .position(particle.position)
                    .opacity(particle.opacity)
            }
            
            // Celebration content
            VStack(spacing: 8) {
                // Animated checkmark
                ZStack {
                    // Outer glow (pulsing)
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Color.green.opacity(0.3), Color.green.opacity(0.0)],
                                center: .center,
                                startRadius: 15,
                                endRadius: 45
                            )
                        )
                        .frame(width: 90, height: 90)
                        .scaleEffect(glowScale)
                    
                    // Checkmark circle
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.green, Color.green.opacity(0.85)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 60, height: 60)
                        .shadow(color: .green.opacity(0.4), radius: 8)
                    
                    Image(systemName: "checkmark")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundColor(.white)
                }
                .scaleEffect(scale)
                .rotationEffect(.degrees(rotation))
            }
        }
        .onAppear {
            generateParticles()
            animateParticles()
            
            // Animate in with bounce
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
                scale = 1.0
            }
            
            // Rotation animation
            withAnimation(.linear(duration: 0.4)) {
                rotation = 360
            }
            
            // Glow pulse animation
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                glowScale = 1.2
            }
        }
    }
    
    private func generateParticles() {
        let colors: [Color] = [.green, madOrange, .yellow, madRed, .blue]
        let centerX = 100.0
        let centerY = 100.0
        
        particles = (0..<12).map { index -> Particle in
            let angle = Double(index) * (2 * .pi / 12)
            let radius = 35.0
            return Particle(
                position: CGPoint(
                    x: centerX + cos(angle) * radius,
                    y: centerY + sin(angle) * radius
                ),
                color: colors.randomElement() ?? .green,
                size: CGFloat.random(in: 3...6),
                opacity: 1.0
            )
        }
    }
    
    private func animateParticles() {
        let centerX = 100.0
        let centerY = 100.0
        
        for index in particles.indices {
            let angle = Double(index) * (2 * .pi / Double(particles.count))
            let finalRadius = 100.0
            
            withAnimation(.easeOut(duration: 1.2).delay(Double(index) * 0.04)) {
                particles[index].position = CGPoint(
                    x: centerX + cos(angle) * finalRadius,
                    y: centerY + sin(angle) * finalRadius
                )
                particles[index].opacity = 0.0
            }
        }
    }
}

struct Particle: Identifiable {
    let id = UUID()
    var position: CGPoint
    let color: Color
    let size: CGFloat
    var opacity: Double
}

#Preview {
    ContentView()
        .environmentObject(HealthKitManager.shared)
        .environmentObject(UserManager.shared)
}
