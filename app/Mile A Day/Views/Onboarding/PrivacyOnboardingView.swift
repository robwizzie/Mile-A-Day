import SwiftUI

/// The one-time "here's exactly who sees what" sheet — shown once per install
/// on the first app open after signing in (existing users see it once after
/// updating). Nothing here is buried in a settings screen the user might
/// never open: every audience choice is made explicitly, up front, with the
/// safe answer preselected.
///
/// Preselections come from the user's CURRENT effective settings, so someone
/// who deliberately chose "Everyone" long ago sees "Everyone" preselected —
/// this sheet informs and confirms, it never silently flips a choice someone
/// already made. For everyone who never chose, the effective value IS the
/// safe default (friends-only), which is what Continue writes.
struct PrivacyOnboardingView: View {
    /// Marked at CONTINUE, not display — reopening after a crash re-asks.
    static let seenKey = "privacyOnboardingSeenV1"
    /// True once the walkthrough has been SAVED (the flag is stamped on Save,
    /// never on display). Other one-shot surfaces stand down on this: the
    /// sheet is hosted at MainTabView root, and a second sheet presented from
    /// a tab while it is up silently dismisses it — What's New did exactly
    /// that on first launch after an update, and the privacy questions were
    /// gone before anyone answered them.
    static var hasBeenSeen: Bool {
        UserDefaults.standard.bool(forKey: seenKey)
    }
    /// Posted when the sheet goes away (saved or not), so the surfaces that
    /// stood down for it can take their turn. Both are fine: a swipe-dismiss
    /// leaves `hasBeenSeen` false and the walkthrough returns next launch.
    static let doneNotification = Notification.Name("MAD_PrivacyOnboardingDone")

    let onDone: () -> Void

    @State private var prefs = NotificationPreferences.load()
    @State private var isSaving = false
    @StateObject private var friendService = FriendService()
    @State private var stealthOn = StealthModeStore.shared.isOn
    /// Only a TOUCHED toggle is sent: a fresh install's empty local log must
    /// not close a window opened from an old phone.
    @State private var stealthTouched = false

    var body: some View {
        ZStack {
            MADTheme.Colors.appBackgroundGradient.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: MADTheme.Spacing.lg) {
                    header

                    infoCard(
                        icon: "person.crop.circle",
                        title: "Always visible",
                        text: "Your name, username, profile photo and streak — that's how friends find you in search. Nothing else is shown without your say-so below."
                    )

                    sectionCard("Your workouts", icon: "figure.run") {
                        Text("Who can see your walks and runs — distances, times, and history on your profile.")
                            .modifier(PrivacyCaption())
                        ForEach(WorkoutVisibility.allCases) { option in
                            visibilityRow(option)
                        }
                    }

                    sectionCard("Route maps", icon: "map") {
                        Toggle(isOn: $prefs.shareRouteMaps) {
                            Text("Show my GPS routes to friends")
                                .font(MADTheme.Typography.body)
                                .foregroundColor(.white)
                        }
                        .tint(MADTheme.Colors.madRed)
                        Text("Off = friends see your cards without the path. A repeated route can reveal where you live — your call.")
                            .modifier(PrivacyCaption())
                    }

                    sectionCard("Stealth Mode", icon: "eye.slash") {
                        Toggle(isOn: $stealthOn) {
                            Text("Hide where I walk, for good")
                                .font(MADTheme.Typography.body)
                                .foregroundColor(.white)
                        }
                        .tint(MADTheme.Colors.madRed)
                        .onChange(of: stealthOn) { _, _ in stealthTouched = true }
                        Text("While it's on, friends never see where your walks were — the map stays on your phone, and those walks stay hidden even after you turn it off. Distance and pace still show. Handy for a trip.")
                            .modifier(PrivacyCaption())
                    }

                    sectionCard("Route flyovers", icon: "play.circle") {
                        Text("The cinematic 3D replay of a route. Friends only, or keep it to yourself.")
                            .modifier(PrivacyCaption())
                        HStack(spacing: 8) {
                            ForEach(FlyoverVisibility.allCases) { option in
                                flyoverChip(option)
                            }
                        }
                    }

                    infoCard(
                        icon: "person.2",
                        title: "Your friends list",
                        text: "Visible to your friends only — never to strangers who search you up."
                    )

                    continueButton
                }
                .padding(MADTheme.Spacing.lg)
                .padding(.bottom, MADTheme.Spacing.xl)
            }
        }
        .interactiveDismissDisabled()
        .preferredColorScheme(.dark)
        .task {
            // Best-effort: the server's window log wins over an empty install.
            await StealthModeStore.shared.hydrateFromServerIfNeeded()
            if !stealthTouched { stealthOn = StealthModeStore.shared.isOn }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                Circle()
                    .fill(MADTheme.Colors.madRed.opacity(0.18))
                    .frame(width: 56, height: 56)
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(MADTheme.Colors.madRed)
            }
            Text("Your privacy")
                .font(.system(size: 30, weight: .black, design: .rounded))
                .foregroundColor(.white)
            Text("Two minutes, once: exactly who sees what. You can change any of this later in Settings.")
                .font(MADTheme.Typography.subheadline)
                .foregroundColor(.white.opacity(0.6))
        }
        .padding(.top, MADTheme.Spacing.lg)
    }

    private func visibilityRow(_ option: WorkoutVisibility) -> some View {
        let selected = prefs.workoutVisibility == option
        return Button {
            guard !selected else { return }
            MADHaptics.tap()
            withAnimation(.easeInOut(duration: 0.15)) { prefs.workoutVisibility = option }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 18))
                    .foregroundColor(selected ? MADTheme.Colors.madRed : .white.opacity(0.3))
                VStack(alignment: .leading, spacing: 1) {
                    Text(option.title)
                        .font(MADTheme.Typography.body)
                        .foregroundColor(.white)
                    Text(option.subtitle)
                        .modifier(PrivacyCaption())
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func flyoverChip(_ option: FlyoverVisibility) -> some View {
        let selected = prefs.flyoverVisibility == option
        return Button {
            guard !selected else { return }
            MADHaptics.tap()
            withAnimation(.easeInOut(duration: 0.15)) { prefs.flyoverVisibility = option }
        } label: {
            Text(option.title)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(selected ? .white : .white.opacity(0.55))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Capsule().fill(selected
                    ? MADTheme.Colors.madRed.opacity(0.85)
                    : Color.white.opacity(0.07)))
        }
        .buttonStyle(.plain)
    }

    private var continueButton: some View {
        Button {
            save()
        } label: {
            HStack {
                if isSaving {
                    ProgressView().tint(.white)
                } else {
                    Text("Save my choices")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(Capsule().fill(MADTheme.Colors.redGradient))
            .foregroundColor(.white)
        }
        .buttonStyle(.plain)
        .disabled(isSaving)
        .padding(.top, MADTheme.Spacing.sm)
    }

    private func save() {
        guard !isSaving else { return }
        isSaving = true
        prefs.save()
        // The server enforces these (feed/list/flyover SQL), so the write has
        // to reach it — but its column defaults already match the safe
        // preselections, so a failed PATCH still leaves a new user friends-only
        // server-side; the settings screen re-syncs on its next save.
        var settings: [String: Any] = [
            "workout_visibility": prefs.workoutVisibility.rawValue,
            "share_route_maps": prefs.shareRouteMaps,
            "flyover_visibility": prefs.flyoverVisibility.rawValue,
        ]
        if stealthTouched {
            settings["stealth_mode"] = stealthOn
            // Local first: an offline enable still keeps the next upload's
            // route on the phone.
            StealthModeStore.shared.setOn(stealthOn)
        }
        Task {
            let response = try? await friendService.updateNotificationSettings(settings)
            await MainActor.run {
                if let response { StealthModeStore.shared.apply(response) }
                UserDefaults.standard.set(true, forKey: Self.seenKey)
                isSaving = false
                onDone()
            }
        }
    }

    private func sectionCard<Content: View>(
        _ title: String, icon: String, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.sm) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(MADTheme.Colors.madRed)
                Text(title)
                    .font(MADTheme.Typography.bodyBold)
                    .foregroundColor(.white)
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(MADTheme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
    }

    private func infoCard(icon: String, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: MADTheme.Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white.opacity(0.5))
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(MADTheme.Typography.bodyBold)
                    .foregroundColor(.white)
                Text(text)
                    .modifier(PrivacyCaption())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(MADTheme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large, style: .continuous)
                .fill(Color.white.opacity(0.03))
        )
    }
}

private struct PrivacyCaption: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.system(size: 12, design: .rounded))
            .foregroundColor(.white.opacity(0.45))
            .fixedSize(horizontal: false, vertical: true)
    }
}
