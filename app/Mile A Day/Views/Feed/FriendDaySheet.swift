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
    /// The content's measured height: the sheet is exactly that tall. A
    /// `.medium` detent left half the sheet empty under two buttons.
    @State private var contentHeight: CGFloat = 300

    private var done: Bool { friend.completed_today }
    private var nudged: Bool { nudgeStore.hasNudgedToday(friend.user_id) }
    private var progress: Double { done ? 1 : min(1, max(0, friend.today_miles)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Who and how their day went, in one row.
            HStack(spacing: 14) {
                AvatarWithRing(
                    name: friend.displayName,
                    imageURL: friend.profile_image_url,
                    progress: progress,
                    size: 64,
                    ringWidth: 4,
                    accent: .orange
                )
                VStack(alignment: .leading, spacing: 3) {
                    Text(friend.displayName)
                        .madFont(size: 20, weight: .heavy, design: .rounded)
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Text(statusLine)
                        .madFont(size: 14, weight: .semibold, design: .rounded, monospacedDigit: true)
                        .foregroundColor(done ? MADTheme.Colors.success : .white.opacity(0.55))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Spacer(minLength: 0)
            }

            if let errorText {
                Text(errorText)
                    .madFont(size: 13, weight: .semibold, design: .rounded)
                    .foregroundColor(MADTheme.Colors.madRed)
            }

            VStack(spacing: 8) {
                HStack(spacing: 10) {
                    primaryAction
                    if done && friend.canAskForPhoto {
                        // The ask leads; Hype rides second.
                        iconButton(hyped ? "checkmark" : "hands.clap.fill",
                                   label: hyped ? "Hyped" : "Hype \(friend.displayName)",
                                   disabled: hyped || hypeBusy) { Task { await hype() } }
                    }
                    iconButton("person.crop.circle", label: "\(friend.displayName)'s profile", disabled: false) {
                        MADHaptics.tap()
                        onOpenProfile()
                    }
                }
                Text(actionNote)
                    .madFont(size: 12, weight: .medium, design: .rounded)
                    .foregroundColor(.white.opacity(0.45))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 26)
        .padding(.bottom, 12)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(red: 0.09, green: 0.05, blue: 0.07).ignoresSafeArea())
        .presentationDetents([.height(contentHeight)])
        .madTypeCap(.madCardCap)
    }

    /// What the main button actually does, in one line.
    private var actionNote: String {
        if done {
            if friend.canAskForPhoto, !(askedPhoto || asked) {
                return "They'll get a nudge to post a photo of today's walk."
            }
            return hyped
                ? "Sent. It shows on their mile and they get a 🔥 notification."
                : "Lands on today's mile: they get a 🔥 notification and it counts on their card."
        }
        return nudged
            ? "They'll get one reminder today. One nudge per friend a day."
            : "Sends one reminder to get their mile in. One nudge per friend a day."
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
                .minimumScaleFactor(0.75)
                .madFont(size: 16, weight: .heavy, design: .rounded, maxScale: 1.3)
                .foregroundColor(.white.opacity(filled ? 1 : 0.75))
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(Capsule().fill(filled ? MADTheme.Colors.madRed : Color.white.opacity(0.1)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .animation(.easeInOut(duration: 0.2), value: filled)
    }

    /// A round 50pt button beside the main one (Hype, Profile).
    private func iconButton(_ systemImage: String, label: String, disabled: Bool,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .madFont(size: 18, weight: .bold, maxScale: 1.3)
                .foregroundColor(.white.opacity(0.85))
                .frame(width: 50, height: 50)
                .background(Circle().fill(Color.white.opacity(0.08)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .accessibilityLabel(label)
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
