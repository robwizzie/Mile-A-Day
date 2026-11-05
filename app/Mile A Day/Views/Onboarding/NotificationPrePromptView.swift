import SwiftUI

/// Flamey asks before iOS does: one setup step, shown only while notification
/// permission is undecided. "Turn on reminders" opens the system prompt;
/// "Not now" defers it (`NotificationPrePrompt.notNow`). Either way setup
/// continues — notifications are never required.
struct NotificationPrePromptView: View {
    @Environment(\.appStateManager) var appStateManager
    @State private var isRequesting = false

    var body: some View {
        OnboardingStepScaffold(
            colors: [Color(red: 1.0, green: 0.58, blue: 0.24), Color(red: 0.85, green: 0.25, blue: 0.27)],
            chip: "Last step",
            headline: "Let Flamey nudge you",
            message: "A reminder before your streak runs out, and a heads-up when friends hype or nudge you. Change it any time in Settings.",
            art: { height in NotificationHeroArt(height: height) },
            actions: {
                VStack(spacing: 6) {
                    OnboardingPrimaryButton(title: "Turn on reminders", isLoading: isRequesting, action: turnOn)
                    OnboardingSecondaryButton(title: "Not now") {
                        NotificationPrePrompt.notNow()
                        appStateManager.completeNotifications()
                    }
                }
            }
        )
    }

    private func turnOn() {
        isRequesting = true
        NotificationPrePrompt.release()
        Task { @MainActor in
            await MADNotificationService.shared.requestAuthorization()
            MADNotificationService.shared.registerForRemoteNotifications()
            await MADNotificationService.shared.syncDailyReminderPrefsToBackend()
            isRequesting = false
            appStateManager.completeNotifications()
        }
    }
}

/// Flamey with the kind of notification he sends.
private struct NotificationHeroArt: View {
    let height: CGFloat

    var body: some View {
        // Banners are ~58pt. A short hero (SE) shows one banner; Flamey
        // takes whatever height is left.
        let showsSecond = height >= 260
        let banners: CGFloat = showsSecond ? 58 + 12 + 55 : 58
        let flame = max(48, min(height - banners - 12, 160))
        VStack(spacing: 12) {
            banner(title: "Flamey", text: "2h left to keep your 12 day streak 🔥")
                .introPop(0.15)
                .introBob(3, period: 3.2)
            if showsSecond {
                banner(title: "Maya hyped your mile", text: "🔥🔥🔥")
                    .introPop(0.3)
                    .introBob(3, period: 3.6, phase: 0.4)
                    .scaleEffect(0.94)
                    .opacity(0.9)
            }
            FlameBuddyView(health: .healthy, size: flame, showsMoodBubble: false)
                .frame(width: flame, height: flame)
                .introPop(0)
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// An iOS-style notification banner.
    private func banner(title: String, text: String) -> some View {
        HStack(spacing: 10) {
            Image("mad-logo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 34, height: 34)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .madFont(size: 14, weight: .semibold, maxScale: 1.1)
                Text(text)
                    .madFont(size: 14, maxScale: 1.1)
                    .opacity(0.8)
            }
            .foregroundColor(.black)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
            Text("now")
                .madFont(size: 12, maxScale: 1.1)
                .foregroundColor(.black.opacity(0.45))
        }
        .padding(12)
        .frame(maxWidth: 340)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(.white.opacity(0.92)))
        .shadow(color: .black.opacity(0.18), radius: 12, y: 6)
        .accessibilityHidden(true)
    }
}

#Preview {
    NotificationPrePromptView()
}
