import SwiftUI

struct ConfettiView: View {
    @Binding var isShowing: Bool
    let duration: Double
    
    @State private var particles: [Particle] = []
    
    init(isShowing: Binding<Bool>, duration: Double = 3.0) {
        self._isShowing = isShowing
        self.duration = duration
    }
    
    var body: some View {
        // The window's size, not the screen's: on a resizable window (iPhone
        // Duo's inner display, Split View) the two differ.
        GeometryReader { geometry in
        ZStack {
            ForEach(particles) { particle in
                Circle()
                    .fill(particle.color)
                    .frame(width: particle.size, height: particle.size)
                    .position(particle.position)
                    .opacity(particle.opacity)
            }
        }
        .onChange(of: isShowing) { oldValue, newValue in
            if newValue {
                generateParticles(in: geometry.size)
                
                // Hide confetti after duration
                DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                    withAnimation {
                        isShowing = false
                    }
                }
            } else {
                particles = []
            }
        }
        }
    }
    
    private func generateParticles(in size: CGSize) {
        particles = []
        
        let colors: [Color] = [.red, .blue, .green, .yellow, .purple, .orange]
        
        for _ in 0..<100 {
            let randomX = CGFloat.random(in: 0...max(size.width, 1))
            let randomY = CGFloat.random(in: -50...0)
            let dotSize = CGFloat.random(in: 5...12)
            
            var particle = Particle(
                position: CGPoint(x: randomX, y: randomY),
                finalPosition: CGPoint(x: randomX + CGFloat.random(in: -100...100),
                                      y: size.height + dotSize),
                color: colors.randomElement() ?? .red,
                size: dotSize
            )
            
            withAnimation(.easeOut(duration: Double.random(in: 1...duration))) {
                particle.position = particle.finalPosition
                particle.opacity = 0
            }
            
            particles.append(particle)
        }
    }
    
    struct Particle: Identifiable {
        let id = UUID()
        var position: CGPoint
        let finalPosition: CGPoint
        let color: Color
        let size: CGFloat
        var opacity: Double = 1.0
    }
}

// Create a modifier to easily add confetti to any view
extension View {
    func confetti(isShowing: Binding<Bool>, duration: Double = 3.0) -> some View {
        ZStack {
            self
            ConfettiView(isShowing: isShowing, duration: duration)
                .allowsHitTesting(false)
        }
    }
}

#Preview {
    struct PreviewWrapper: View {
        @State private var showConfetti = false
        
        var body: some View {
            VStack {
                Button("Show Confetti") {
                    showConfetti = true
                }
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(8)
            }
            .confetti(isShowing: $showConfetti)
        }
    }
    
    return PreviewWrapper()
} 