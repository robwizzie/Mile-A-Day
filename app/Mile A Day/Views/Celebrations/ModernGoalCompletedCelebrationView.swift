import SwiftUI
import UIKit

struct ModernGoalCompletedCelebrationView: View {
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
                Color(red: 0.045, green: 0.045, blue: 0.052)
                    .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 14) {
                        Spacer(minLength: geo.safeAreaInsets.top + 34)

                        hero

                        if showDetails {
                            details
                                .transition(.opacity.combined(with: .offset(y: 18)))
                        }

                        if showButtons {
                            buttons
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }

                        Spacer(minLength: geo.safeAreaInsets.bottom + 44)
                    }
                    .padding(.horizontal, 22)
                }
            }
            .opacity(overlayOpacity)
            .ignoresSafeArea()
            .onAppear {
                if recapGains.isEmpty {
                    recapGains = tokensState.meterGains
                }
                startSequence()
            }
        }
    }

    private var hero: some View {
        VStack(spacing: 10) {
            ReignitingFlameView(showsFace: false, size: 168, progress: ignitionProgress, intensity: 0.85)
                .frame(height: 184)

            if showStreak {
                VStack(spacing: 10) {
                    Text("REIGNITED")
                        .font(.system(size: 13, weight: .black, design: .rounded))
                        .tracking(2.6)
                        .foregroundColor(.orange)

                    Text("\(streakCountValue)")
                        .font(.system(size: 82, weight: .black, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(.white)
                        .contentTransition(.numericText())
                        .lineLimit(1)
                        .minimumScaleFactor(0.55)

                    Text("Day Streak")
                        .font(.system(size: 17, weight: .heavy, design: .rounded))
                        .tracking(4)
                        .foregroundColor(.white.opacity(0.76))

                    Text(completionSubtitle)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.56))
                        .multilineTextAlignment(.center)
                }
                .transition(.scale(scale: 0.74).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(red: 0.075, green: 0.075, blue: 0.085))
                .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
        )
    }

    private var details: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                stat(icon: "figure.run", value: String(format: "%.2f", stats.todaysDistance), label: "mi today", tint: MADTheme.Colors.madRed)
                stat(icon: "target", value: String(format: "%.1f", stats.goalDistance), label: "goal", tint: .white.opacity(0.70))
                if stats.todaysTotalDuration > 0 {
                    stat(icon: "timer", value: stats.formattedDuration, label: "time", tint: .cyan)
                }
            }

            milestoneRow

            if tokensState.payload != nil {
                tokenRow
            }

            if let pending = pendingService.mileCompletedPending {
                notifyCard(pending)
            }
        }
    }

    private func stat(icon: String, value: String, label: String, tint: Color) -> some View {
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
                .foregroundColor(.white.opacity(0.46))
        }
        .frame(maxWidth: .infinity)
        .frame(height: 96)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.055))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.white.opacity(0.085), lineWidth: 1))
        )
    }

    private var milestoneRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Next milestone")
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundColor(.white.opacity(0.58))
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
                    Capsule().fill(Color.white.opacity(0.11))
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
            .frame(height: 6)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.055))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.white.opacity(0.085), lineWidth: 1))
        )
    }

    private var tokenRow: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Streak Tokens")
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .foregroundColor(.white.opacity(0.68))
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
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.055))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.white.opacity(0.085), lineWidth: 1))
        )
    }

    private func tokenCell(kind: StreakTokenKind, held: Bool, progress: Double, caption: String) -> some View {
        VStack(spacing: 5) {
            TokenMedallion(kind: kind, held: held, progress: progress, size: 36)
            Text(recapGains[kind.raw] ?? caption)
                .font(.system(size: 10, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundColor(recapGains[kind.raw] == nil ? (held ? .green : .white.opacity(0.52)) : .yellow)
                .lineLimit(1)
                .minimumScaleFactor(0.70)
        }
        .frame(maxWidth: .infinity)
    }

    private func notifyCard(_ pending: PendingFriendNotification) -> some View {
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
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.055))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.white.opacity(0.085), lineWidth: 1))
        )
    }

    private var buttons: some View {
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
                .frame(height: 52)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(MADTheme.Colors.madRed))
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
                .frame(height: 48)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white.opacity(0.065))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var completionSubtitle: String {
        if stats.percentOver > 50 { return "Goal cleared. Flame restored." }
        if stats.percentOver > 20 { return "Strong finish. Streak protected." }
        return "Today is complete. Keep the line alive."
    }

    private func startSequence() {
        withAnimation(.easeOut(duration: 0.22)) {
            overlayOpacity = 1
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            MADHaptics.emphasis()
            withAnimation(.timingCurve(0.18, 0.86, 0.24, 1.0, duration: 1.02)) {
                ignitionProgress = 1
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.82) {
            MADHaptics.success()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.96) {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.76)) {
                showStreak = true
            }
            animateStreakCounter()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.38) {
            withAnimation(.spring(response: 0.40, dampingFraction: 0.82)) {
                showDetails = true
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.66) {
            withAnimation(.spring(response: 0.40, dampingFraction: 0.82)) {
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
                print("[ModernGoalCelebration] notify friends failed: \(error)")
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
                print("[ModernGoalCelebration] notify decline failed: \(error)")
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
