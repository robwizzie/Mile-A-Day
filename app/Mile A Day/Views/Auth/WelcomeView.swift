import SwiftUI

struct WelcomeView: View {
    @Environment(\.appStateManager) var appStateManager
    @EnvironmentObject var userManager: UserManager
    @State private var iconScale: CGFloat = 0.5
    @State private var titleOpacity: Double = 0
    @State private var featuresOpacity: Double = 0
    @State private var buttonOpacity: Double = 0
    @State private var floatOffset: CGFloat = 0

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.12, green: 0.06, blue: 0.08),
                    Color(red: 0.06, green: 0.03, blue: 0.04)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Animated logo with glow
                ZStack {
                    Circle()
                        .fill(MADTheme.Colors.madRed.opacity(0.15))
                        .frame(width: 180, height: 180)
                        .blur(radius: 35)

                    Image("mad-logo")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 100, height: 100)
                }
                .scaleEffect(iconScale)
                .offset(y: floatOffset)
                .padding(.bottom, MADTheme.Spacing.xl)

                // Personalized greeting
                VStack(spacing: MADTheme.Spacing.sm) {
                    Text("You're all set,")
                        .font(.system(size: 18, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.7))

                    Text(userManager.currentUser.username ?? "Runner")
                        .font(.system(size: 34, weight: .black, design: .rounded))
                        .foregroundColor(.white)

                    Text("Here's what awaits you")
                        .font(.system(size: 16, weight: .regular, design: .rounded))
                        .foregroundColor(.white.opacity(0.6))
                        .padding(.top, 2)
                }
                .opacity(titleOpacity)
                .padding(.bottom, MADTheme.Spacing.xxl)

                // Feature highlights
                VStack(alignment: .leading, spacing: MADTheme.Spacing.lg) {
                    featureRow(
                        icon: "figure.run",
                        color: MADTheme.Colors.madRed,
                        title: "Daily Mile",
                        subtitle: "Walk or run one mile every day"
                    )
                    featureRow(
                        icon: "flame.fill",
                        color: Color(red: 1.0, green: 0.5, blue: 0.0),
                        title: "Build Streaks",
                        subtitle: "Keep your streak alive day after day"
                    )
                    featureRow(
                        icon: "person.2.fill",
                        color: Color(red: 0.2, green: 0.7, blue: 0.9),
                        title: "Compete with Friends",
                        subtitle: "See who's leading the pack"
                    )
                }
                .padding(.horizontal, MADTheme.Spacing.xl)
                .opacity(featuresOpacity)

                Spacer()
                Spacer()

                // Continue button
                Button(action: {
                    withAnimation(MADTheme.Animation.standard) {
                        appStateManager.completeWelcome()
                    }
                }) {
                    Text("Let's Go")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(MADTheme.Colors.madRed)
                        )
                        .shadow(color: MADTheme.Colors.madRed.opacity(0.3), radius: 12, x: 0, y: 6)
                }
                .padding(.horizontal, MADTheme.Spacing.xl)
                .padding(.bottom, MADTheme.Spacing.xxl)
                .opacity(buttonOpacity)
            }
        }
        .onAppear { startAnimations() }
    }

    private func featureRow(icon: String, color: Color, title: String, subtitle: String) -> some View {
        HStack(spacing: MADTheme.Spacing.md) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.12))
                    .frame(width: 48, height: 48)
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(color)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                Text(subtitle)
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .foregroundColor(.white.opacity(0.6))
            }
        }
    }

    private func startAnimations() {
        withAnimation(.spring(response: 0.7, dampingFraction: 0.75).delay(0.1)) {
            iconScale = 1.0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation(.easeInOut(duration: 3.0).repeatForever(autoreverses: true)) {
                floatOffset = -6
            }
        }
        withAnimation(.easeOut(duration: 0.5).delay(0.3)) {
            titleOpacity = 1.0
        }
        withAnimation(.easeOut(duration: 0.5).delay(0.5)) {
            featuresOpacity = 1.0
        }
        withAnimation(.easeOut(duration: 0.5).delay(0.7)) {
            buttonOpacity = 1.0
        }
    }
}

#Preview {
    WelcomeView()
        .environmentObject(UserManager())
        .preferredColorScheme(.dark)
}
