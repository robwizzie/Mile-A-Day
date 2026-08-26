import SwiftUI

/// The moment you beat the ghost.
///
/// This used to be a generic `.milestone` popup — the same purple screen with
/// the same star sparkles that a baseline mile got. Two things were wrong with
/// that. It had nothing to do with a race, and it was SEE-THROUGH: the shared
/// milestone gradient is built from `.opacity(0.8)`/`.opacity(0.9)` color
/// stops, so the dashboard showed through the bottom two-thirds of what is
/// supposed to be a full-screen moment. (That bug is fixed at its source too,
/// since every milestone celebration had it.)
///
/// What this shows instead is the race itself: the ghost you were chasing
/// drifts away and dissolves, the margin lands as the hero number, and the two
/// times sit side by side so the win is legible in one glance. Every number is
/// the FROZEN verdict from the 1.00-mile crossing — the same figures the live
/// chip showed, so the popup can't contradict what the user watched.
struct GhostBeatenCelebrationView: View {
    let win: GhostRaceWin

    @ObservedObject var manager = CelebrationManager.shared
    @Environment(\.scenePhase) private var scenePhase

    @State private var hasStartedAnimation = false
    @State private var backdrop: Double = 0
    @State private var ghostDrift: CGFloat = 0
    @State private var ghostGone = false
    @State private var runnerIn = false
    @State private var showMargin = false
    @State private var showTimes = false
    @State private var showButton = false
    @State private var showBurst = false

    private var accent: Color { MADTheme.workoutColor(win.activityKey) }
    private var isRun: Bool { win.activityKey == "running" }
    private var marginText: String { "\(max(1, Int(win.marginSeconds.rounded())))s" }

    // MARK: - Body

    var body: some View {
        ZStack {
            background

            if showBurst {
                BurstEffect(
                    colors: [accent, .white, .cyan, .purple],
                    particleCount: 30
                )
                .frame(height: 220)
                .allowsHitTesting(false)
            }

            VStack(spacing: MADTheme.Spacing.lg) {
                Spacer(minLength: MADTheme.Spacing.md)

                chase

                if showMargin { marginBlock.transition(.scale.combined(with: .opacity)) }
                if showTimes { timesBlock.transition(.move(edge: .bottom).combined(with: .opacity)) }

                Spacer(minLength: MADTheme.Spacing.md)

                if showButton {
                    continueButton
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                // Clear the floating tab bar + home indicator (this overlay
                // ignores the safe area).
                Spacer().frame(height: 110)
            }
        }
        .ignoresSafeArea()
        .opacity(backdrop)
        .onAppear { startAnimationIfActive() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active && !hasStartedAnimation { startAnimationIfActive() }
        }
    }

    // MARK: - Background

    /// OPAQUE by construction: a solid base color under the gradient, so no
    /// amount of alpha in the stops above it can let the dashboard through.
    private var background: some View {
        ZStack {
            Color(red: 0.05, green: 0.04, blue: 0.11)

            LinearGradient(
                colors: [
                    Color(red: 0.16, green: 0.11, blue: 0.34),
                    Color(red: 0.09, green: 0.07, blue: 0.22),
                    Color(red: 0.04, green: 0.03, blue: 0.09)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            // A cold glow behind the chase, so the ghost reads as lit from
            // within rather than pasted onto a flat field.
            RadialGradient(
                colors: [accent.opacity(0.35), .clear],
                center: .init(x: 0.5, y: 0.32),
                startRadius: 10,
                endRadius: 320
            )
        }
        .ignoresSafeArea()
    }

    // MARK: - The chase

    /// The runner catches the ghost, which drifts off and dissolves. Reads
    /// left-to-right the way the race did.
    private var chase: some View {
        ZStack {
            GhostSprite(
                size: 108,
                color: .white.opacity(0.92),
                glancesBack: true,
                isVanishing: ghostGone
            )
            .offset(x: 62 + ghostDrift, y: -6)

            Image(systemName: isRun ? "figure.run" : "figure.walk")
                .font(.system(size: 66, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.white, accent],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .offset(x: runnerIn ? -46 : -160, y: 10)
                .shadow(color: accent.opacity(0.7), radius: 18)
        }
        .frame(height: 170)
        .padding(.horizontal, MADTheme.Spacing.lg)
    }

    // MARK: - Margin

    private var marginBlock: some View {
        VStack(spacing: 2) {
            Text("GHOST BEATEN")
                .font(.system(size: 13, weight: .black, design: .rounded))
                .tracking(2.4)
                .foregroundColor(.white.opacity(0.6))

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("+")
                    .font(.system(size: 44, weight: .black, design: .rounded))
                Text(marginText)
                    .font(.system(size: 76, weight: .black, design: .rounded))
                    .monospacedDigit()
            }
            .foregroundStyle(
                LinearGradient(
                    colors: [.white, accent],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .shadow(color: accent.opacity(0.55), radius: 22)

            Text("ahead of \(win.ghostName) over \(racedDistanceLabel)")
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.75))
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, MADTheme.Spacing.lg)
    }

    /// "the mile" / "the 5K" / "3 miles". A race longer than a mile used to
    /// render here as a mile — so a 24:48 5K was announced as a 24:48 mile,
    /// with the ghost's total in the column beside it.
    /// Spelled out rather than reusing `BestEffortStore.distanceLabel`, which
    /// is built for a CHIP: it already carries its own unit ("3 mi"), so
    /// wrapping it here produced "over 3 mi miles".
    private var racedDistanceLabel: String {
        let miles = win.distanceMiles
        if abs(miles - 1.0) < 0.005 { return "the mile" }
        if abs(miles - 3.1) < 0.005 { return "the 5K" }
        if abs(miles - 6.2) < 0.005 { return "the 10K" }
        if abs(miles - 13.1) < 0.005 { return "the half" }
        if abs(miles - miles.rounded()) < 0.005 {
            return "\(Int(miles.rounded())) miles"
        }
        return String(format: "%.1f miles", miles)
    }

    // MARK: - Times

    private var timesBlock: some View {
        VStack(spacing: MADTheme.Spacing.md) {
            HStack(spacing: 0) {
                timeColumn(
                    label: isRun ? "YOUR RUN" : "YOUR WALK",
                    seconds: win.mileSeconds,
                    highlighted: true
                )

                Rectangle()
                    .fill(Color.white.opacity(0.15))
                    .frame(width: 1, height: 44)

                timeColumn(label: "THE GHOST", seconds: win.ghostSeconds, highlighted: false)
            }
            .padding(.vertical, MADTheme.Spacing.md)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large, style: .continuous)
                    .fill(Color.white.opacity(0.09))
                    .overlay(
                        RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
                    )
            )

            if let record = win.newRecordSeconds {
                HStack(spacing: 7) {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 12, weight: .bold))
                    Text("\(BestEffortStore.formatSeconds(record)) is your new mile to beat")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                }
                .foregroundColor(.black.opacity(0.85))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Capsule().fill(Color.yellow))
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, MADTheme.Spacing.lg)
    }

    private func timeColumn(label: String, seconds: Double, highlighted: Bool) -> some View {
        VStack(spacing: 3) {
            Text(label)
                .font(.system(size: 10, weight: .black, design: .rounded))
                .tracking(1.2)
                .foregroundColor(.white.opacity(0.5))
            Text(BestEffortStore.formatSeconds(seconds))
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundColor(highlighted ? .white : .white.opacity(0.55))
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Continue

    private var continueButton: some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                manager.dismissCurrentCelebration()
            }
        } label: {
            HStack(spacing: MADTheme.Spacing.sm) {
                Text("Nice work")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                Image(systemName: "arrow.right.circle.fill")
                    .font(.system(size: 20))
            }
            .foregroundColor(Color(red: 0.09, green: 0.07, blue: 0.22))
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(
                RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                    .fill(.white)
                    .shadow(color: accent.opacity(0.4), radius: 20, x: 0, y: 8)
            )
            .padding(.horizontal, MADTheme.Spacing.xl)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Choreography

    private func startAnimationIfActive() {
        guard !hasStartedAnimation, scenePhase == .active else { return }
        hasStartedAnimation = true
        animateIn()
    }

    /// Beat, then overtake, then verdict — in that order, because that's the
    /// order it happened.
    private func animateIn() {
        withAnimation(.easeOut(duration: 0.3)) { backdrop = 1 }

        withAnimation(.spring(response: 0.75, dampingFraction: 0.8).delay(0.15)) {
            runnerIn = true
        }

        // The ghost gets left behind, then dissolves.
        withAnimation(.easeInOut(duration: 1.0).delay(0.45)) {
            ghostDrift = 70
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.95) {
            ghostGone = true
            showBurst = true
            MADHaptics.action()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.15) {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) { showMargin = true }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.45) {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { showTimes = true }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.7) {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { showButton = true }
        }
    }
}

#Preview {
    GhostBeatenCelebrationView(
        win: GhostRaceWin(
            marginSeconds: 14,
            mileSeconds: 528,
            ghostSeconds: 542,
            ghostName: "your best",
            activityKey: "running",
            newRecordSeconds: 528,
            friendUserId: nil,
            workoutId: "preview"
        )
    )
}
