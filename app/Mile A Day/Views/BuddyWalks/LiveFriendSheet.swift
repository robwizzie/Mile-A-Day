import SwiftUI

/// One friend who is out RIGHT NOW: what you see when you tap them.
///
/// Tapping a person should open that person. The first version opened the
/// whole "out right now" list, so tapping Patty showed you a list with Patty
/// somewhere in it. This is her: a big live ring filling toward her goal, the
/// distance and how long she's been out, and the three things you can do,
/// in order of how often people do them:
///
/// 1. **Hype**: lands on her tracker while she's walking (the shared
///    `<userId>:<localDate>` mile key, so it dedupes with a hype from the feed).
/// 2. **Join / Ask to walk**: the same actions as `BuddyJoinFriendCard`.
/// 3. **Profile**.
///
/// It stays live while open (re-reads friends-out every 15s; the walker's
/// phone reports about every 45s), and says so plainly when she finishes,
/// rather than freezing on a number that's no longer true.
struct LiveFriendSheet: View {
    let friendId: String
    /// A walk was joined or asked into: the host opens the lobby.
    let onJoined: () -> Void
    let onOpenProfile: (FriendOutNow) -> Void
    /// Shown as "See everyone out (N)" when more than one friend is out.
    var onSeeEveryone: (() -> Void)? = nil

    @ObservedObject private var buddy = BuddySessionService.shared
    @Environment(\.dismiss) private var dismiss
    @State private var hyped = false
    @State private var hypeBusy = false
    @State private var joinBusy = false
    @State private var asked = false
    @State private var errorText: String?
    /// The last time we saw them out, kept so a finished walk still shows
    /// whose sheet this is.
    @State private var lastSeen: FriendOutNow?

    private var friend: FriendOutNow? {
        buddy.friendsOutNow.first { $0.userId == friendId }
    }

    private var shown: FriendOutNow? { friend ?? lastSeen }
    private var stillOut: Bool { friend != nil }

    var body: some View {
        VStack(spacing: 0) {
            if let f = shown {
                content(f)
            } else {
                ProgressView().tint(.white).frame(maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.09, green: 0.05, blue: 0.07).ignoresSafeArea())
        .madTypeCap(.madCardCap)
        .onAppear { lastSeen = friend }
        .onChange(of: friend) { _, new in if let new { lastSeen = new } }
        .task {
            while !Task.isCancelled {
                await buddy.refreshFriendsOutNow()
                try? await Task.sleep(nanoseconds: 15 * 1_000_000_000)
            }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private func content(_ f: FriendOutNow) -> some View {
        let accent = f.accentColor
        let progress = min(1, max(0, (f.distanceMiles ?? 0) / f.goal))

        VStack(spacing: 18) {
            AvatarWithRing(
                name: f.displayName,
                imageURL: f.profileImageUrl,
                progress: progress,
                size: 112,
                ringWidth: 6,
                accent: accent
            )
            .padding(.top, 34)
            .animation(.easeOut(duration: 0.6), value: progress)

            VStack(spacing: 4) {
                Text(f.displayName)
                    .madFont(size: 22, weight: .heavy, design: .rounded)
                    .foregroundColor(.white)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if stillOut {
                        Circle().fill(accent).frame(width: 7, height: 7)
                            .accessibilityHidden(true)
                    }
                    Text(statusLine(f))
                        .madFont(size: 14, weight: .semibold, design: .rounded)
                        .foregroundColor(stillOut ? accent : .white.opacity(0.55))
                        .lineLimit(1)
                }
            }

            if let miles = f.distanceMiles {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(miles.distanceText)
                        .madFont(size: 44, weight: .black, design: .rounded, maxScale: 1.3, monospacedDigit: true)
                        .foregroundColor(.white)
                        .contentTransition(.numericText(value: miles))
                        .animation(.easeOut(duration: 0.4), value: miles)
                    Text("of \(f.goal.distanceFormatted)")
                        .madFont(size: 16, weight: .bold, design: .rounded)
                        .foregroundColor(.white.opacity(0.5))
                }
                .accessibilityElement(children: .combine)
            }

            Spacer(minLength: 8)

            if let errorText {
                Text(errorText)
                    .madFont(size: 13, weight: .semibold, design: .rounded)
                    .foregroundColor(MADTheme.Colors.madRed)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            actions(f, accent: accent)
                .padding(.horizontal, 20)

            if let onSeeEveryone, buddy.friendsOutNow.count > 1 {
                Button {
                    MADHaptics.tap()
                    onSeeEveryone()
                } label: {
                    Text("See everyone out (\(buddy.friendsOutNow.count))")
                        .madFont(size: 14, weight: .bold, design: .rounded)
                        .foregroundColor(.white.opacity(0.6))
                        .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.bottom, 20)
    }

    private func statusLine(_ f: FriendOutNow) -> String {
        guard stillOut else { return "Finished their walk" }
        let verb = f.isRunning ? "Running" : "Walking"
        if let elapsed = FriendOutTime.elapsed(since: f.startedAt) {
            return "\(verb) now · \(elapsed)"
        }
        return "\(verb) now"
    }

    @ViewBuilder
    private func actions(_ f: FriendOutNow, accent: Color) -> some View {
        VStack(spacing: 10) {
            Button {
                Task { await hype(f) }
            } label: {
                HStack(spacing: 8) {
                    if hypeBusy {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: hyped ? "checkmark" : "hands.clap.fill")
                            .accessibilityHidden(true)
                    }
                    Text(hyped ? "Hyped. They'll see it mid-walk" : "Hype \(f.displayName)")
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .madFont(size: 16, weight: .heavy, design: .rounded, maxScale: 1.3)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(Capsule().fill(hyped ? Color.white.opacity(0.1) : MADTheme.Colors.madRed))
            }
            .buttonStyle(.plain)
            .disabled(hyped || hypeBusy || !stillOut)

            HStack(spacing: 10) {
                if stillOut, InProgressWorkoutStore.load()?.isActive != true {
                    Button {
                        Task { await join(f) }
                    } label: {
                        HStack(spacing: 6) {
                            if joinBusy { ProgressView().tint(.white) }
                            Text(joinTitle(f))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .madFont(size: 15, weight: .bold, design: .rounded, maxScale: 1.3)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .background(Capsule().fill(accent.opacity(0.22)))
                    }
                    .buttonStyle(.plain)
                    .disabled(joinBusy || joinDisabled(f))
                }
                Button {
                    MADHaptics.tap()
                    onOpenProfile(f)
                } label: {
                    Text("Profile")
                        .madFont(size: 15, weight: .bold, design: .rounded, maxScale: 1.3)
                        .foregroundColor(.white.opacity(0.85))
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .background(Capsule().fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Actions (mirroring BuddyJoinFriendCard)

    private func joinTitle(_ f: FriendOutNow) -> String {
        if asked || f.hasAskedToJoinRoom { return "Asked" }
        if f.roomRefusedMe { return "Walk is full" }
        guard f.hasJoinableRoom else { return "Ask to walk" }
        return f.canJoinRoomDirectly ? "Join" : "Ask to join"
    }

    private func joinDisabled(_ f: FriendOutNow) -> Bool {
        asked || f.hasAskedToJoinRoom || f.roomRefusedMe
    }

    private func hype(_ f: FriendOutNow) async {
        guard !hyped, !hypeBusy else { return }
        hyped = true
        hypeBusy = true
        errorText = nil
        MADHaptics.success()
        defer { hypeBusy = false }
        do {
            if let localDate = f.localDate {
                _ = try await HypeService.sendHype(
                    targetUserId: f.userId,
                    context: HypeContext(
                        contextType: "mile",
                        contextId: "\(f.userId):\(localDate)",
                        contextLabel: f.isRunning ? "run" : "walk"
                    )
                )
            } else {
                _ = try await HypeService.sendHype(targetUserId: f.userId)
            }
        } catch APIError.conflict {
            // Already hyped today: keep it locked.
            hyped = true
        } catch {
            hyped = false
            MADHaptics.error()
            errorText = (error as? LocalizedError)?.errorDescription ?? "Couldn't send that hype."
        }
    }

    private func join(_ f: FriendOutNow) async {
        guard !joinBusy else { return }
        joinBusy = true
        errorText = nil
        defer { joinBusy = false }
        do {
            if let sessionId = f.buddySessionId, !f.canJoinRoomDirectly {
                do {
                    try await buddy.requestToJoin(sessionId: sessionId)
                    MADHaptics.success()
                    asked = true
                } catch BuddyServiceError.api("join_directly") {
                    try await buddy.join(sessionId: sessionId)
                    MADHaptics.success()
                    await buddy.refreshFriendsOutNow()
                    dismiss()
                    onJoined()
                }
            } else if let sessionId = f.buddySessionId {
                try await buddy.join(sessionId: sessionId)
                MADHaptics.success()
                await buddy.refreshFriendsOutNow()
                dismiss()
                onJoined()
            } else {
                try await buddy.askFriendToWalk(f)
                MADHaptics.success()
                asked = true
                dismiss()
                onJoined()
            }
        } catch {
            MADHaptics.error()
            errorText = (error as? LocalizedError)?.errorDescription ?? "Couldn't do that."
            await buddy.refreshFriendsOutNow()
        }
    }
}
