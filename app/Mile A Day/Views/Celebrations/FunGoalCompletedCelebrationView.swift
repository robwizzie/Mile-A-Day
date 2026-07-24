import SwiftUI
import UIKit

struct FunGoalCompletedCelebrationView: View {
    @ObservedObject private var manager = CelebrationManager.shared
    @ObservedObject private var pendingService = PendingNotificationsService.shared
    @ObservedObject private var tokensState = StreakTokensState.shared

    let stats: GoalCompletionStats

    @State private var overlayOpacity: Double = 0
    @State private var ignitionProgress: CGFloat = 0
    @State private var showStreak = false
    @State private var showDetails = false
    @State private var showButtons = false
    @State private var streakCountValue = 0
    @State private var shareItem: ShareableImage?
    @State private var notifyInFlight = false
    @State private var recapGains: [String: String] = [:]

    var body: some View {
        GeometryReader { geo in
            ZStack {
                background

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 14) {
                        Spacer(minLength: geo.safeAreaInsets.top + 34)

                        VStack(spacing: 8) {
                            reigniteStage
                                .frame(height: min(286, geo.size.height * 0.34))

                            if showStreak {
                                streakSection
                                    .transition(.scale(scale: 0.7).combined(with: .opacity))
                            }
                        }
                        .frame(minHeight: geo.size.height * 0.42)

                        if showDetails {
                            detailsStack
                                .transition(.opacity.combined(with: .offset(y: 22)))
                        }

                        if showButtons {
                            buttonSection
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }

                        Spacer(minLength: geo.safeAreaInsets.bottom + 44)
                    }
                    .padding(.horizontal, 22)
                }
            }
            .ignoresSafeArea()
            .opacity(overlayOpacity)
            .onAppear {
                if recapGains.isEmpty {
                    recapGains = tokensState.meterGains
                }
                startSequence()
            }
        }
    }

    private var background: some View {
        ZStack {
            Color(red: 0.055, green: 0.020, blue: 0.030)

            Circle()
                .fill(Color.orange.opacity(0.08 + Double(ignitionProgress) * 0.13))
                .blur(radius: 86)
                .frame(width: 290, height: 290)
                .offset(y: -105)
                .scaleEffect(0.76 + ignitionProgress * 0.24)
                .animation(.easeInOut(duration: 0.9), value: ignitionProgress)
        }
    }

    private var reigniteStage: some View {
        ReignitingFlameView(showsFace: true, size: 210, progress: ignitionProgress, intensity: 1.35, startsSad: true)
            .frame(width: 330, height: 276)
    }

    private var streakSection: some View {
        VStack(spacing: 10) {
            Text("REIGNITED")
                .font(.system(size: 14, weight: .black, design: .rounded))
                .tracking(3)
                .foregroundColor(.orange)

            Text("\(streakCountValue)")
                .font(.system(size: 78, weight: .black, design: .rounded))
                .monospacedDigit()
                .foregroundColor(.white)
                .contentTransition(.numericText())
                .shadow(color: MADTheme.Colors.madRed.opacity(0.45), radius: 10, x: 0, y: 6)
                .lineLimit(1)
                .minimumScaleFactor(0.55)

            Text("Day Streak")
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .tracking(5)
                .foregroundColor(.green)
                .lineLimit(1)
                .minimumScaleFactor(0.70)

            Text(completionSubtitle)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.72))
                .multilineTextAlignment(.center)
        }
    }

    private var detailsStack: some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                celebrationStat(icon: "figure.run", value: String(format: "%.2f", stats.todaysDistance), label: "mi today", tint: MADTheme.Colors.madRed)
                celebrationStat(icon: "flame.fill", value: "\(stats.currentStreak)", label: "day streak", tint: .orange)
                if stats.todaysTotalDuration > 0 {
                    celebrationStat(icon: "timer", value: stats.formattedDuration, label: "time", tint: .cyan)
                }
            }

            milestoneProgress

            if tokensState.payload != nil {
                tokenRecapSection
            }

            if let pending = pendingService.mileCompletedPending {
                notifyFriendsCard(pending)
            }
        }
    }

    private func celebrationStat(icon: String, value: String, label: String, tint: Color) -> some View {
        VStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(tint)
            Text(value)
                .font(.system(size: 20, weight: .black, design: .rounded))
                .monospacedDigit()
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            Text(label)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundColor(.white.opacity(0.48))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 98)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.065))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
        )
    }

    private var milestoneProgress: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Next milestone")
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundColor(.white.opacity(0.60))
                Spacer()
                if let next = StreakMilestone.next(after: stats.currentStreak) {
                    Text("\(next.daysToGo) days to Day \(next.value)")
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .foregroundColor(.white.opacity(0.72))
                        .monospacedDigit()
                }
            }

            GeometryReader { geo in
                let next = StreakMilestone.next(after: stats.currentStreak)
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.14))
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 1.0, green: 0.68, blue: 0.14),
                                    Color(red: 1.0, green: 0.34, blue: 0.16),
                                    MADTheme.Colors.madRed
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(5, geo.size.width * CGFloat(next?.progress ?? 1)))
                }
            }
            .frame(height: 8)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.060))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
        )
    }

    private var tokenRecapSection: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Streak Tokens")
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .foregroundColor(.white.opacity(0.72))
                Spacer()
                if let payload = tokensState.payload {
                    let ready = [payload.double_down.held, payload.streak_save.held, payload.streak_assist.held].filter { $0 }.count
                    Text("\(ready) ready")
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .foregroundColor(ready > 0 ? .green : .white.opacity(0.48))
                }
            }

            if let payload = tokensState.payload {
                HStack(spacing: 0) {
                    tokenCell(kind: .doubleDown, held: payload.double_down.held, progress: payload.double_down.fraction, caption: payload.double_down.held ? "Ready" : "\(Int(payload.double_down.progress))/\(Int(payload.double_down.target))")
                    tokenCell(kind: .save, held: payload.streak_save.held, progress: payload.streak_save.fraction, caption: payload.streak_save.held ? "Ready" : "\(Int(payload.streak_save.progress))/\(Int(payload.streak_save.target))")
                    tokenCell(kind: .assist, held: payload.streak_assist.held, progress: payload.streak_assist.fraction, caption: payload.streak_assist.held ? "Ready" : String(format: "%.1f/%.0f mi", payload.streak_assist.progress, payload.streak_assist.target))
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.060))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
        )
    }

    private func tokenCell(kind: StreakTokenKind, held: Bool, progress: Double, caption: String) -> some View {
        VStack(spacing: 5) {
            TokenMedallion(kind: kind, held: held, progress: progress, size: 38)
            Text(recapGains[kind.raw] ?? caption)
                .font(.system(size: 10, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundColor(recapGains[kind.raw] == nil ? (held ? .green : .white.opacity(0.52)) : .yellow)
                .lineLimit(1)
                .minimumScaleFactor(0.70)
        }
        .frame(maxWidth: .infinity)
    }

    private func notifyFriendsCard(_ pending: PendingFriendNotification) -> some View {
        VStack(spacing: 12) {
            Text("Let your friends know?")
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .foregroundColor(.white)

            Button {
                handleNotify(pending)
            } label: {
                HStack(spacing: 8) {
                    if notifyInFlight {
                        ProgressView().scaleEffect(0.8).tint(.white)
                    } else {
                        Image(systemName: "bell.fill")
                        Text("Notify Friends")
                    }
                }
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(MADTheme.Colors.madRed))
            }
            .buttonStyle(.plain)
            .disabled(notifyInFlight)

            Button {
                handleNotifyDecline(pending)
            } label: {
                Text("Not this time")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.52))
            }
            .buttonStyle(.plain)
            .disabled(notifyInFlight)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.060))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
        )
    }

    private var buttonSection: some View {
        VStack(spacing: 12) {
            Button {
                MADHaptics.action()
                if let image = generateShareCardImage() {
                    shareItem = ShareableImage(image: image)
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "square.and.arrow.up")
                    Text("Share Achievement")
                }
                .font(.system(size: 17, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(MADTheme.Colors.madRed)
                )
            }
            .buttonStyle(.plain)
            .sheet(item: $shareItem) { item in
                ShareSheet(items: [item.image])
            }

            Button {
                MADHaptics.tap()
                manager.dismissCurrentCelebration()
            } label: {
                HStack(spacing: 8) {
                    Text("Continue")
                    Image(systemName: "arrow.right")
                }
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.88))
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.white.opacity(0.075))
                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var completionSubtitle: String {
        if stats.percentOver > 50 { return "Your flame is absolutely roaring." }
        if stats.percentOver > 20 { return "Big mile. Big flame." }
        return "You brought your flame back to life."
    }

    private func startSequence() {
        withAnimation(.easeOut(duration: 0.22)) {
            overlayOpacity = 1
        }

        // Reignite in readable beats instead of one front-loaded rush: the coal
        // glows and LINGERS, then visibly CATCHES into open flame, then the flame
        // swells to full and settles. An ease-in-out curve keeps the ember on
        // screen long enough to read (the old curve shot past it in a blink) and
        // eases into the settle — the ReignitingFlameView crossfade + catch-flash
        // are timed to this shape (catch peaks around progress 0.34).
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) {
            MADHaptics.tap() // the coal begins to catch
            withAnimation(.timingCurve(0.66, 0.0, 0.34, 1.0, duration: 1.5)) {
                ignitionProgress = 1
            }
        }

        // Emphasis right as it ignites into open flame…
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.92) {
            MADHaptics.emphasis()
        }

        // …and a success tick as the full flame settles.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.74) {
            MADHaptics.success()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.86) {
            withAnimation(.spring(response: 0.40, dampingFraction: 0.72)) {
                showStreak = true
            }
            animateStreakCounter()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.24) {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
                showDetails = true
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.52) {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
                showButtons = true
            }
        }
    }

    private func animateStreakCounter() {
        let target = stats.currentStreak
        let start = max(0, target - min(target, 7))
        streakCountValue = start
        let steps = min(max(target - start, 1), 18)

        for i in 0...steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.045) {
                let progress = Double(i) / Double(max(steps, 1))
                streakCountValue = start + Int(Double(target - start) * progress)
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + Double(steps) * 0.045 + 0.02) {
            streakCountValue = target
        }
    }

    private func handleNotify(_ pending: PendingFriendNotification) {
        guard !notifyInFlight else { return }
        notifyInFlight = true
        MADHaptics.action()
        Task {
            do {
                try await pendingService.send(pending)
                MADHaptics.success()
            } catch {
                print("[FunGoalCelebration] notify friends failed: \(error)")
                MADHaptics.error()
            }
            await MainActor.run { notifyInFlight = false }
        }
    }

    private func handleNotifyDecline(_ pending: PendingFriendNotification) {
        guard !notifyInFlight else { return }
        notifyInFlight = true
        Task {
            do {
                try await pendingService.dismiss(pending)
            } catch {
                print("[FunGoalCelebration] notify decline failed: \(error)")
            }
            await MainActor.run { notifyInFlight = false }
        }
    }

    private func generateShareCardImage() -> UIImage? {
        let card = CelebrationShareCardView(stats: stats)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3.0
        renderer.isOpaque = false
        return renderer.uiImage
    }
}
