import SwiftUI

/// BeReal-style prompt shown as the finale after finishing today's mile: snap a
/// photo of your run, or skip. Either way the run becomes one feed item — taking
/// a photo publishes it with the photo; skipping publishes the route map (or a
/// stats card) via `RunPostService`. Friends get one merged notification ~10 min
/// later (handled server-side), so there's a window to add a photo.
struct PostRunPhotoPromptView: View {
    let workoutId: String
    let workoutType: String

    @ObservedObject private var manager = CelebrationManager.shared
    @State private var showComposer = false
    @State private var appeared = false
    @State private var didAct = false

    private var isWalk: Bool { workoutType == "walking" }
    private var accent: Color { isWalk ? .blue : MADTheme.Colors.madRed }

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.08, green: 0.06, blue: 0.10), .black],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(spacing: MADTheme.Spacing.lg) {
                Spacer()

                ZStack {
                    Circle().fill(accent.opacity(0.18)).frame(width: 150, height: 150)
                    Circle().strokeBorder(accent.opacity(0.4), lineWidth: 1).frame(width: 150, height: 150)
                    Image(systemName: "camera.fill")
                        .font(.system(size: 54, weight: .semibold))
                        .foregroundStyle(LinearGradient(colors: [.white, accent],
                                                        startPoint: .top, endPoint: .bottom))
                        .shadow(color: accent.opacity(0.5), radius: 16)
                }
                .scaleEffect(appeared ? 1 : 0.6)
                .opacity(appeared ? 1 : 0)

                VStack(spacing: 8) {
                    Text(isWalk ? "Capture your walk" : "Capture your run")
                        .font(.system(size: 26, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                    Text("Add a photo to today's mile — it shares to your feed either way. Snap one before your friends get the heads-up.")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, MADTheme.Spacing.xl)
                }
                .opacity(appeared ? 1 : 0)

                Spacer()

                VStack(spacing: MADTheme.Spacing.sm) {
                    Button { showComposer = true } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "camera.fill")
                            Text("Take a photo")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .madPrimaryButton(fullWidth: true)

                    Button { skip() } label: {
                        Text("Skip")
                            .font(MADTheme.Typography.headline)
                            .foregroundColor(.white.opacity(0.7))
                    }
                    .padding(.top, 2)
                }
                .padding(.horizontal, MADTheme.Spacing.lg)
                .padding(.bottom, MADTheme.Spacing.xl)
            }
        }
        .onAppear { withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) { appeared = true } }
        .fullScreenCover(isPresented: $showComposer) {
            PostComposerView(stats: RunPostService.todayStats(workoutId: workoutId)) { success in
                showComposer = false
                didAct = true
                // Cancelled the camera? Still publish the auto route/stats post so
                // the run gets one nice feed item.
                if !success {
                    Task { await RunPostService.autoPostMile(workoutId: workoutId, workoutType: workoutType) }
                }
                finish()
            }
        }
    }

    private func skip() {
        guard !didAct else { return }
        didAct = true
        Task { await RunPostService.autoPostMile(workoutId: workoutId, workoutType: workoutType) }
        finish()
    }

    private func finish() {
        manager.dismissCurrentCelebration()
    }
}
