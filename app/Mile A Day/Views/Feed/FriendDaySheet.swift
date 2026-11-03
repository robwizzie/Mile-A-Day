import SwiftUI

/// One friend's day, opened from their Today-board tile.
///
/// Tapping a person should open THAT person. Done tiles used to jump
/// straight to the profile (or fire a photo ask on the first tap), which
/// skipped the one thing worth doing about a friend's finished day: saying
/// something. This is their day in one glance (a ring, how far, done or not)
/// and the action that fits it, in order:
///
/// - **Done, nothing shared**: Ask for a photo (the "show us your walk" ask),
///   then Hype.
/// - **Done**: Hype.
/// - **Not yet**: Nudge, or "Nudged" once it's gone (read from
///   `NudgeStatusStore`, so it agrees with every other surface).
/// - Always: Profile.
struct FriendDaySheet: View {
    let friend: FriendActivityItem
    let askedPhoto: Bool
    let onAskPhoto: () -> Void
    let onNudge: () -> Void
    let onOpenProfile: () -> Void

    @ObservedObject private var nudgeStore = NudgeStatusStore.shared
    @State private var hyped = false
    @State private var hypeBusy = false
    @State private var asked = false
    @State private var errorText: String?

    private var done: Bool { friend.completed_today }
    private var nudged: Bool { nudgeStore.hasNudgedToday(friend.user_id) }
    private var progress: Double { done ? 1 : min(1, max(0, friend.today_miles)) }

    var body: some View {
        VStack(spacing: 16) {
            AvatarWithRing(
                name: friend.displayName,
                imageURL: friend.profile_image_url,
                progress: progress,
                size: 96,
                ringWidth: 5,
                accent: .orange
            )
            .padding(.top, 28)

            VStack(spacing: 4) {
                Text(friend.displayName)
                    .madFont(size: 21, weight: .heavy, design: .rounded)
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text(statusLine)
                    .madFont(size: 14, weight: .semibold, design: .rounded, monospacedDigit: true)
                    .foregroundColor(done ? MADTheme.Colors.success : .white.opacity(0.55))
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            if let errorText {
                Text(errorText)
                    .madFont(size: 13, weight: .semibold, design: .rounded)
                    .foregroundColor(MADTheme.Colors.madRed)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            VStack(spacing: 10) {
                primaryAction
                HStack(spacing: 10) {
                    if done && friend.canAskForPhoto {
                        // The ask leads; Hype rides second.
                        secondaryButton(hyped ? "Hyped" : "Hype", systemImage: hyped ? "checkmark" : "hands.clap.fill",
                                        disabled: hyped || hypeBusy) { Task { await hype() } }
                    }
                    secondaryButton("Profile", systemImage: nil, disabled: false) {
                        MADHaptics.tap()
                        onOpenProfile()
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.09, green: 0.05, blue: 0.07).ignoresSafeArea())
        .madTypeCap(.madCardCap)
    }

    private var statusLine: String {
        if done { return "Done today · \(friend.today_miles.distanceFormatted)" }
        if friend.today_miles > 0.005 { return "\(friend.today_miles.distanceFormatted) so far today" }
        return "Not out yet today"
    }

    @ViewBuilder
    private var primaryAction: some View {
        if done {
            if friend.canAskForPhoto {
                let isAsked = askedPhoto || asked
                primaryButton(isAsked ? "Asked for a photo" : "📸  Ask for a photo",
                              filled: !isAsked, disabled: isAsked) {
                    MADHaptics.success()
                    asked = true
                    onAskPhoto()
                }
            } else {
                primaryButton(hyped ? "Hyped. Nice one" : "👏  Hype \(friend.displayName)",
                              filled: !hyped, disabled: hyped || hypeBusy) {
                    Task { await hype() }
                }
            }
        } else {
            primaryButton(nudged ? "Nudged. They'll get a buzz" : "👋  Nudge \(friend.displayName)",
                          filled: !nudged, disabled: nudged) {
                MADHaptics.success()
                onNudge()
            }
        }
    }

    private func primaryButton(_ title: String, filled: Bool, disabled: Bool,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .madFont(size: 16, weight: .heavy, design: .rounded, maxScale: 1.3)
                .foregroundColor(.white.opacity(filled ? 1 : 0.75))
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(Capsule().fill(filled ? MADTheme.Colors.madRed : Color.white.opacity(0.1)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .animation(.easeInOut(duration: 0.2), value: filled)
    }

    private func secondaryButton(_ title: String, systemImage: String?, disabled: Bool,
                                 action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .accessibilityHidden(true)
                }
                Text(title)
                    .lineLimit(1)
            }
            .madFont(size: 15, weight: .bold, design: .rounded, maxScale: 1.3)
            .foregroundColor(.white.opacity(0.85))
            .frame(maxWidth: .infinity, minHeight: 46)
            .background(Capsule().fill(Color.white.opacity(0.08)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    private func hype() async {
        guard !hyped, !hypeBusy else { return }
        hyped = true
        hypeBusy = true
        errorText = nil
        MADHaptics.success()
        defer { hypeBusy = false }
        do {
            _ = try await HypeService.sendHype(targetUserId: friend.user_id)
        } catch APIError.conflict {
            // Already hyped today: keep it locked.
            hyped = true
        } catch {
            hyped = false
            MADHaptics.error()
            errorText = (error as? LocalizedError)?.errorDescription ?? "Couldn't send that hype."
        }
    }
}
