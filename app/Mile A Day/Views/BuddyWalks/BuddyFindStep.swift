import SwiftUI

/// The first thing buddy setup does: look for friends to walk with RIGHT NOW,
/// then offer the best one in a single card, the way Spotify offers a Jam
/// with whoever's around.
///
/// Every signal is one the app already has, plus one new heartbeat: no
/// location, no Bluetooth, no new permission (proximity sensing was rejected
/// on purpose; see `BuddyJoinFriendCard`). In order:
///   1. a friend who has invited you (the answer is already waiting),
///   2. the friend you tapped "Walk with … again" for,
///   3. friends whose setup is open too (`POST /buddy/looking`): the Jam
///      moment, two people deciding at once,
///   4. friends' rooms starting or running now,
///   5. friends out on their own right now,
///   6. the people you walk with most.
/// Friends only, deduped by person, at most `limit`.
struct BuddySuggestion: Identifiable {
    enum Action {
        case acceptInvite(sessionId: String)
        case join(JoinableFriendSession)
        case askOutNow(FriendOutNow)
        /// Make a Just Together lobby and invite them, in one tap.
        /// `activityType` mirrors theirs when they said.
        case invite(userId: String, activityType: String?)
    }

    let userId: String
    let name: String
    let imageURL: String?
    /// Why them, in a few words: "Looking for a walk buddy too".
    let reason: String
    /// They're doing something right now (looking, out, in a room).
    let isLive: Bool
    /// The hero button: "Walk with Alex", "Join Alex's walk".
    let actionTitle: String
    /// The compact row's button: "Walk", "Join".
    let shortActionTitle: String
    let action: Action

    var id: String { userId }

    static let limit = 4

    @MainActor
    static func ranked(buddy: BuddySessionService, walkAgainUserId: String?) -> [BuddySuggestion] {
        var out: [BuddySuggestion] = []
        var seen = Set<String>()
        func add(_ s: BuddySuggestion) {
            guard !seen.contains(s.userId), out.count < limit else { return }
            seen.insert(s.userId)
            out.append(s)
        }
        let me = buddy.currentUserId

        for invite in buddy.invites {
            guard let host = invite.participants.first(where: { $0.isHost && $0.userId != me })
                ?? invite.participants.first(where: { $0.userId != me }) else { continue }
            add(BuddySuggestion(
                userId: host.userId, name: host.displayName, imageURL: host.profileImageUrl,
                reason: "Invited you to \(invite.activityType == "running" ? "run" : "walk")",
                isLive: true, actionTitle: "Join \(host.displayName)", shortActionTitle: "Join",
                action: .acceptInvite(sessionId: invite.id)))
        }

        if let walkAgainUserId,
           let friend = buddy.candidates.first(where: { $0.userId == walkAgainUserId }) {
            add(BuddySuggestion(
                userId: friend.userId, name: friend.displayName, imageURL: friend.profileImageUrl,
                reason: "Walk together again", isLive: false,
                actionTitle: "Walk with \(friend.displayName)", shortActionTitle: "Walk",
                action: .invite(userId: friend.userId, activityType: nil)))
        }

        for friend in buddy.lookingFriends {
            let activity = friend.activityType == "running" || friend.activityType == "walking"
                ? friend.activityType : nil
            add(BuddySuggestion(
                userId: friend.userId, name: friend.displayName, imageURL: friend.profileImageUrl,
                reason: "Looking for a \(friend.isRunning ? "run" : "walk") buddy right now",
                isLive: true, actionTitle: "Walk with \(friend.displayName)", shortActionTitle: "Walk",
                action: .invite(userId: friend.userId, activityType: activity)))
        }

        let invited = Set(buddy.invites.map(\.id))
        for open in buddy.joinableFriendSessions
        where !invited.contains(open.sessionId) && (open.hostIsFriend ?? true) {
            let noun = open.isRunning ? "run" : "walk"
            add(BuddySuggestion(
                userId: open.hostUserId, name: open.hostDisplayName, imageURL: open.hostProfileImageUrl,
                reason: open.status == .active
                    ? "Out on a \(noun) now · \(open.participantCount) in"
                    : "Starting a \(noun) · \(open.participantCount) in",
                isLive: true, actionTitle: "Join \(open.hostDisplayName)'s \(noun)", shortActionTitle: "Join",
                action: .join(open)))
        }

        for friend in buddy.friendsOutNow where !friend.hasJoinableRoom {
            let verb = friend.isRunning ? "running" : "walking"
            let progress = (friend.distanceMiles ?? 0) > 0
                ? " · \((friend.distanceMiles ?? 0).distanceFormatted)" : ""
            add(BuddySuggestion(
                userId: friend.userId, name: friend.displayName, imageURL: friend.profileImageUrl,
                reason: "Out \(verb) now\(progress)", isLive: true,
                actionTitle: "Walk with \(friend.displayName)", shortActionTitle: "Ask",
                action: .askOutNow(friend)))
        }

        let invitable = Set(buddy.candidates.map(\.userId))
        for partner in buddy.partners where invitable.contains(partner.userId) {
            add(BuddySuggestion(
                userId: partner.userId, name: partner.displayName, imageURL: partner.profileImageUrl,
                reason: partner.summary, isLive: false,
                actionTitle: "Walk with \(partner.displayName)", shortActionTitle: "Walk",
                action: .invite(userId: partner.userId, activityType: nil)))
        }
        return out
    }
}

/// The find step's content: searching, then the suggestion.
struct BuddyFindContent: View {
    let isSearching: Bool
    let suggestions: [BuddySuggestion]
    /// The suggestion whose action is in flight.
    let actingId: String?
    let onAct: (BuddySuggestion) -> Void
    let onChooseOthers: () -> Void

    var body: some View {
        Group {
            if isSearching {
                VStack(spacing: 18) {
                    BuddyRadar()
                    Text("Checking who's around to walk with…")
                        .font(MADTheme.Typography.caption)
                        .foregroundStyle(Color.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .transition(.opacity)
            } else if let top = suggestions.first {
                VStack(spacing: 20) {
                    hero(top)
                    if suggestions.count > 1 { more(Array(suggestions.dropFirst())) }
                    chooseOthersButton(title: "Choose someone else")
                }
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            } else {
                empty.transition(.opacity)
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: isSearching)
    }

    // MARK: Hero

    private func hero(_ s: BuddySuggestion) -> some View {
        VStack(spacing: 14) {
            ZStack {
                if s.isLive { BuddyLiveRing(size: 104) }
                AvatarView(name: s.name, imageURL: s.imageURL, size: 88)
            }
            .frame(height: 112)
            VStack(spacing: 4) {
                Text(s.name)
                    .madFont(size: 26, weight: .bold, design: .rounded, maxScale: 1.3)
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(s.reason)
                    .font(MADTheme.Typography.caption)
                    .foregroundStyle(Color.white.opacity(0.75))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            WizardPrimaryButton(
                title: actingId == s.id ? "Starting…" : s.actionTitle,
                icon: "figure.2",
                isBusy: actingId == s.id,
                isEnabled: actingId == nil
            ) { onAct(s) }
            Text(heroCaption(for: s))
                .font(MADTheme.Typography.caption)
                .foregroundStyle(Color.white.opacity(0.55))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(panel(24))
        .accessibilityElement(children: .contain)
    }

    /// What the tap will actually do — it MAKES something, so it says so.
    private func heroCaption(for s: BuddySuggestion) -> String {
        switch s.action {
        case .invite:
            return "Makes a lobby and invites \(s.name). Change the plan there before anyone starts."
        case .askOutNow:
            return "Makes a lobby and asks \(s.name) to join you."
        case .join, .acceptInvite:
            return "You'll land in their lobby. Nobody moves until it starts."
        }
    }

    // MARK: More

    private func more(_ rest: [BuddySuggestion]) -> some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.sm) {
            Text("Also around")
                .font(MADTheme.Typography.headline)
                .foregroundStyle(Color.white)
            VStack(spacing: 0) {
                ForEach(Array(rest.enumerated()), id: \.element.id) { index, s in
                    if index > 0 { Divider().background(Color.white.opacity(0.12)) }
                    row(s)
                }
            }
            .background(panel(20))
        }
    }

    private func row(_ s: BuddySuggestion) -> some View {
        HStack(spacing: MADTheme.Spacing.md) {
            ZStack {
                if s.isLive {
                    Circle().strokeBorder(Color.white.opacity(0.7), lineWidth: 2).frame(width: 46, height: 46)
                }
                AvatarView(name: s.name, imageURL: s.imageURL, size: 40)
            }
            .frame(width: 46, height: 46)
            VStack(alignment: .leading, spacing: 2) {
                Text(s.name)
                    .font(MADTheme.Typography.bodyBold)
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                Text(s.reason)
                    .font(MADTheme.Typography.caption)
                    .foregroundStyle(Color.white.opacity(0.6))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button {
                MADHaptics.action()
                onAct(s)
            } label: {
                Group {
                    if actingId == s.id {
                        ProgressView().tint(WizardPalette.onAccent)
                    } else {
                        Text(s.shortActionTitle).lineLimit(1)
                    }
                }
                .font(MADTheme.Typography.smallBold)
                .frame(minWidth: 64, minHeight: 36)
                .padding(.horizontal, 6)
                .background(Capsule().fill(WizardPalette.accent))
                .foregroundStyle(WizardPalette.onAccent)
            }
            .buttonStyle(.plain)
            .disabled(actingId != nil)
            .accessibilityLabel(s.actionTitle)
        }
        .padding(.horizontal, MADTheme.Spacing.md)
        .padding(.vertical, MADTheme.Spacing.sm + 2)
    }

    // MARK: Empty

    private var empty: some View {
        VStack(spacing: 14) {
            Image(systemName: "person.2")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.85))
                .accessibilityHidden(true)
            Text("No friends around right now")
                .font(MADTheme.Typography.bodyBold)
                .foregroundStyle(Color.white)
            Text("Pick who's coming and they'll get an invite. If a friend opens buddy walks while you're here, they'll show up first.")
                .font(MADTheme.Typography.caption)
                .foregroundStyle(Color.white.opacity(0.65))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            WizardPrimaryButton(title: "Choose friends", icon: "arrow.right") { onChooseOthers() }
                .padding(.top, 4)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(panel(24))
    }

    private func chooseOthersButton(title: String) -> some View {
        Button {
            MADHaptics.tap()
            onChooseOthers()
        } label: {
            HStack(spacing: 4) {
                Text(title)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .accessibilityHidden(true)
            }
            .font(MADTheme.Typography.smallBold)
            .foregroundStyle(Color.white.opacity(0.85))
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(actingId != nil)
    }

    private func panel(_ radius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(Color.white.opacity(0.10))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
            )
    }
}

/// Ripples going out from the middle while the step looks for people.
private struct BuddyRadar: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { ring in
                Circle()
                    .stroke(Color.white.opacity(0.35), lineWidth: 2)
                    .frame(width: 96 + CGFloat(ring) * 40, height: 96 + CGFloat(ring) * 40)
                    .scaleEffect(pulse ? 1.15 : 0.85)
                    .opacity(pulse ? 0.15 : 0.6)
            }
            Circle()
                .fill(Color.white.opacity(0.14))
                .frame(width: 80, height: 80)
            Image(systemName: "figure.2")
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(Color.white)
        }
        .frame(height: 200)
        .accessibilityElement()
        .accessibilityLabel("Looking for friends to walk with")
        .onAppear {
            guard !reduceMotion else { return }
            // Next turn, inside withAnimation, so the loop never leaks into
            // the layout changes around it.
            DispatchQueue.main.async {
                withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { pulse = true }
            }
        }
    }
}

/// A slow pulse around someone who's live right now.
private struct BuddyLiveRing: View {
    let size: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        Circle()
            .strokeBorder(Color.white.opacity(0.8), lineWidth: 3)
            .frame(width: size, height: size)
            .scaleEffect(pulse ? 1.08 : 1)
            .opacity(pulse ? 0.35 : 0.9)
            .onAppear {
                guard !reduceMotion else { return }
                DispatchQueue.main.async {
                    withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) { pulse = true }
                }
            }
            .accessibilityHidden(true)
    }
}
