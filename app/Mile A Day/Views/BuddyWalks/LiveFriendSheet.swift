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
    /// App-wide "hyped today" (`HypeLedger`): one hype per friend's day,
    /// whichever screen sent it.
    @ObservedObject private var hypeLedger = HypeLedger.shared
    private var hyped: Bool { hypeLedger.hasHypedToday(friendId) }
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

    /// The content's measured height: the sheet is exactly that tall. A
    /// full-height sheet left two thirds of the screen empty above the
    /// buttons.
    @State private var contentHeight: CGFloat = 320

    var body: some View {
        Group {
            if let f = shown {
                content(f)
            } else {
                ProgressView().tint(.white).frame(maxWidth: .infinity, minHeight: 200)
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(red: 0.09, green: 0.05, blue: 0.07).ignoresSafeArea())
        .presentationDetents([.height(contentHeight)])
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

    /// One row for who and how far (ring, name, live status, the distance
    /// against their goal), then the actions. The same shape as
    /// `FriendDaySheet`, so a friend's sheet looks alike done, out or not yet.
    private func content(_ f: FriendOutNow) -> some View {
        let accent = f.accentColor
        let progress = min(1, max(0, (f.distanceMiles ?? 0) / f.goal))

        return VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                AvatarWithRing(
                    name: f.displayName,
                    imageURL: f.profileImageUrl,
                    progress: progress,
                    size: 64,
                    ringWidth: 4,
                    accent: accent
                )
                .animation(.easeOut(duration: 0.6), value: progress)

                VStack(alignment: .leading, spacing: 3) {
                    Text(f.displayName)
                        .madFont(size: 20, weight: .heavy, design: .rounded)
                        .foregroundColor(.white)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        if stillOut {
                            LiveDot(color: accent)
                        }
                        Text(statusLine(f))
                            .madFont(size: 14, weight: .semibold, design: .rounded, monospacedDigit: true)
                            .foregroundColor(stillOut ? accent : .white.opacity(0.55))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }

                Spacer(minLength: 8)

                if let miles = f.distanceMiles {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(miles.distanceText)
                            .madFont(size: 30, weight: .black, design: .rounded, maxScale: 1.3, monospacedDigit: true)
                            .foregroundColor(.white)
                            .contentTransition(.numericText(value: miles))
                            .animation(.easeOut(duration: 0.4), value: miles)
                        Text("of \(f.goal.distanceFormatted)")
                            .madFont(size: 12, weight: .bold, design: .rounded)
                            .foregroundColor(.white.opacity(0.5))
                    }
                    .lineLimit(1)
                    .fixedSize()
                    .accessibilityElement(children: .combine)
                }
            }

            if let errorText {
                Text(errorText)
                    .madFont(size: 13, weight: .semibold, design: .rounded)
                    .foregroundColor(MADTheme.Colors.madRed)
            }

            VStack(spacing: 8) {
                actions(f, accent: accent)
                Text(actionNote)
                    .madFont(size: 12, weight: .medium, design: .rounded)
                    .foregroundColor(.white.opacity(0.45))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let onSeeEveryone, buddy.friendsOutNow.count > 1 {
                Button {
                    MADHaptics.tap()
                    onSeeEveryone()
                } label: {
                    HStack(spacing: 4) {
                        Text("See everyone out (\(buddy.friendsOutNow.count))")
                        Image(systemName: "chevron.right")
                            .madFont(size: 11, weight: .bold, maxScale: 1.2)
                    }
                    .madFont(size: 14, weight: .bold, design: .rounded)
                    .foregroundColor(.white.opacity(0.6))
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 26)
        .padding(.bottom, 12)
    }

    /// What Hype does, in one line.
    private var actionNote: String {
        if !stillOut { return "Their walk just ended. Hype lands on today's mile." }
        return hyped
            ? "Hyped. It pops up on their screen mid-walk."
            : "Hype pops up on their screen mid-walk and counts on today's mile."
    }

    private func statusLine(_ f: FriendOutNow) -> String {
        guard stillOut else { return "Finished their walk" }
        let verb = f.isRunning ? "Running" : "Walking"
        if let elapsed = FriendOutTime.elapsed(since: f.startedAt) {
            return "\(verb) now · \(elapsed)"
        }
        return "\(verb) now"
    }

    /// Hype (the main thing) with Profile as a round button beside it, then
    /// Join / Ask to walk under them when it's on offer.
    @ViewBuilder
    private func actions(_ f: FriendOutNow, accent: Color) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Button {
                    Task { await hype(f) }
                } label: {
                    HStack(spacing: 8) {
                        if hypeBusy {
                            ProgressView().tint(.white)
                        } else {
                            Text(hyped ? "✓" : "👏")
                                .accessibilityHidden(true)
                        }
                        Text(hyped ? "Hyped" : "Hype \(f.displayName)")
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    .madFont(size: 16, weight: .heavy, design: .rounded, maxScale: 1.3)
                    .foregroundColor(.white.opacity(hyped ? 0.75 : 1))
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(Capsule().fill(hyped ? Color.white.opacity(0.1) : MADTheme.Colors.madRed))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(hyped || hypeBusy || !stillOut)
                .animation(.easeInOut(duration: 0.2), value: hyped)

                Button {
                    MADHaptics.tap()
                    onOpenProfile(f)
                } label: {
                    Image(systemName: "person.crop.circle")
                        .madFont(size: 18, weight: .bold, maxScale: 1.3)
                        .foregroundColor(.white.opacity(0.85))
                        .frame(width: 50, height: 50)
                        .background(Circle().fill(Color.white.opacity(0.08)))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(f.displayName)'s profile")
            }

            if stillOut, InProgressWorkoutStore.load()?.isActive != true {
                Button {
                    Task { await join(f) }
                } label: {
                    HStack(spacing: 6) {
                        if joinBusy {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: f.hasJoinableRoom ? "person.2.fill" : "figure.walk")
                                .madFont(size: 13, weight: .bold, maxScale: 1.3)
                                .accessibilityHidden(true)
                        }
                        Text(joinTitle(f))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .madFont(size: 15, weight: .bold, design: .rounded, maxScale: 1.3)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .background(Capsule().fill(accent.opacity(0.22)))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(joinBusy || joinDisabled(f))
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
        hypeLedger.markHyped(f.userId)
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
            // Already hyped today: the mark stands.
        } catch {
            hypeLedger.unmark(f.userId)
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

/// A small dot that breathes while someone is out.
private struct LiveDot: View {
    let color: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var on = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 7, height: 7)
            .opacity(on ? 0.35 : 1)
            .onAppear {
                guard !reduceMotion else { return }
                DispatchQueue.main.async {
                    withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { on = true }
                }
            }
            .accessibilityHidden(true)
    }
}
