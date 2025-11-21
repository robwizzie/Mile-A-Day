import SwiftUI

struct SplashView: View {
    @State private var logoScale: CGFloat = 0.5
    @State private var logoOpacity: Double = 0
    @State private var textOpacity: Double = 0
    @State private var backgroundOpacity: Double = 0
    @State private var showingSpeedLines = false
    @State private var speedLineOffset: CGFloat = -200
    
    var body: some View {
        ZStack {
            // Background gradient
            MADTheme.Colors.appBackgroundGradient
                .ignoresSafeArea()
                .opacity(backgroundOpacity)
            
            // Speed lines animation (like the logo)
            ForEach(0..<5, id: \.self) { index in
                Rectangle()
                    .fill(MADTheme.Colors.madRed.opacity(0.3))
                    .frame(width: 4, height: 60)
                    .offset(x: speedLineOffset + CGFloat(index * 40), y: CGFloat(index * 20 - 40))
                    .rotationEffect(.degrees(-15))
                    .opacity(showingSpeedLines ? 1 : 0)
            }
            
            VStack(spacing: MADTheme.Spacing.xl) {
                // MAD Logo - Replace "mad-logo" with your image name
                Image("mad-logo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 120, height: 120)
                    .scaleEffect(logoScale)
                    .opacity(logoOpacity)
                    .shadow(
                        color: MADTheme.Colors.madRed.opacity(0.3),
                        radius: 20,
                        x: 0,
                        y: 8
                    )
                
                // App subtitle
                VStack(spacing: MADTheme.Spacing.md) {
                    Text("MILE A DAY")
                        .font(MADTheme.Typography.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .tracking(1.5)
                        .opacity(textOpacity)
                    
                    Text("Stay Active. Stay Motivated.")
                        .font(MADTheme.Typography.headline)
                        .foregroundColor(.white.opacity(0.9))
                        .opacity(textOpacity)
                }
            }
        }
        .onAppear {
            startAnimations()
        }
    }
    
    private func startAnimations() {
        // Background fade in
        withAnimation(MADTheme.Animation.slow) {
            backgroundOpacity = 1.0
        }
        
        // Logo scale and fade in
        withAnimation(MADTheme.Animation.splash.delay(0.3)) {
            logoScale = 1.0
            logoOpacity = 1.0
        }
        
        // Speed lines animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            withAnimation(MADTheme.Animation.standard) {
                showingSpeedLines = true
                speedLineOffset = UIScreen.main.bounds.width + 100
            }
        }
        
        // Text fade in
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation(MADTheme.Animation.standard) {
                textOpacity = 1.0
            }
        }
    }
}

/// MAD Logo View - Recreates the essence of the logo in SwiftUI
struct MADLogoView: View {
    @State private var runnerOffset: CGFloat = 0
    @State private var showRunner = false
    
    var body: some View {
        ZStack {
            // Background shape (rounded rectangle with gradient)
            RoundedRectangle(cornerRadius: 24)
                .fill(
                    LinearGradient(
                        colors: [
                            MADTheme.Colors.madRed,
                            MADTheme.Colors.madRed.opacity(0.8),
                            Color.black.opacity(0.9)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 120, height: 120)
                .shadow(
                    color: MADTheme.Colors.madRed.opacity(0.3),
                    radius: 20,
                    x: 0,
                    y: 8
                )
            
            // Speed lines
            VStack(spacing: 2) {
                ForEach(0..<6, id: \.self) { index in
                    HStack(spacing: 1) {
                        Rectangle()
                            .fill(MADTheme.Colors.madRed)
                            .frame(width: CGFloat(30 - index * 3), height: 2)
                        Spacer()
                    }
                    .offset(x: -20)
                }
            }
            .frame(width: 80, height: 40)
            .offset(x: -10, y: -5)
            
            // MAD Text
            Text("MAD")
                .font(.system(size: 28, weight: .black, design: .rounded))
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.3), radius: 2, x: 1, y: 1)
            
            // Running figure silhouette
            RunnerSilhouetteView()
                .frame(width: 40, height: 40)
                .offset(x: 25, y: 10)
                .opacity(showRunner ? 1 : 0)
                .offset(x: runnerOffset)
        }
        .onAppear {
            // Animate runner appearing
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                withAnimation(MADTheme.Animation.bounce) {
                    showRunner = true
                }
            }
            
            // Subtle runner movement
            withAnimation(
                Animation.easeInOut(duration: 2)
                    .repeatForever(autoreverses: true)
                    .delay(1.0)
            ) {
                runnerOffset = 3
            }
        }
    }
}

/// Simple runner silhouette
struct RunnerSilhouetteView: View {
    var body: some View {
        ZStack {
            // Body
            Ellipse()
                .fill(MADTheme.Colors.madBlack)
                .frame(width: 12, height: 20)
                .offset(y: -5)
            
            // Head
            Circle()
                .fill(MADTheme.Colors.madBlack)
                .frame(width: 8, height: 8)
                .offset(y: -18)
            
            // Arms
            RoundedRectangle(cornerRadius: 1)
                .fill(MADTheme.Colors.madBlack)
                .frame(width: 8, height: 2)
                .rotationEffect(.degrees(-20))
                .offset(x: -4, y: -8)
            
            RoundedRectangle(cornerRadius: 1)
                .fill(MADTheme.Colors.madBlack)
                .frame(width: 8, height: 2)
                .rotationEffect(.degrees(30))
                .offset(x: 4, y: -6)
            
            // Legs
            RoundedRectangle(cornerRadius: 1)
                .fill(MADTheme.Colors.madBlack)
                .frame(width: 2, height: 12)
                .rotationEffect(.degrees(-10))
                .offset(x: -2, y: 8)
            
            RoundedRectangle(cornerRadius: 1)
                .fill(MADTheme.Colors.madBlack)
                .frame(width: 2, height: 12)
                .rotationEffect(.degrees(20))
                .offset(x: 3, y: 8)
        }
    }
}

#Preview {
    SplashView()
}