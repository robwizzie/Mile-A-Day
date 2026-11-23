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
    static func ranked(
        buddy: BuddySessionService, walkAgainUserId: String?, nearby: [BuddyCandidate] = []
    ) -> [BuddySuggestion] {
        var out: [BuddySuggestion] = []
        var seen = Set<String>()
        func add(_ s: BuddySuggestion) {
            guard !seen.contains(s.userId), out.count < limit else { return }
            seen.insert(s.userId)
            out.append(s)
        }
        let me = buddy.currentUserId

        // Physically next to you (Bluetooth, opt-in, `BuddyNearbyScanner`):
        // the strongest signal there is, so it outranks even an invite —
        // unless that same friend invited you, which the loop below names.
        let invitingHosts = Set(buddy.invites.compactMap { invite in
            invite.participants.first(where: { $0.isHost })?.userId
        })
        for friend in nearby where !invitingHosts.contains(friend.userId) {
            add(BuddySuggestion(
                userId: friend.userId, name: friend.displayName, imageURL: friend.profileImageUrl,
                reason: String(localized: "Right next to you"), isLive: true,
                actionTitle: "Walk with \(friend.displayName)", shortActionTitle: "Walk",
                action: .invite(userId: friend.userId, activityType: nil)))
        }

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

/// "Walk with everyone around": one lobby inviting every friend who is
/// deciding right now or already out on their own.
///
/// The single-friend hero made a group walk N taps through the picker even
/// when the app could see the whole group: three friends with setup open at
/// once is exactly the "let's all go" moment, and the find step used to offer
/// only the first of them. Same signals as `BuddySuggestion.ranked` (friends
/// only, `share_live_presence`, no location), just not cut to one.
///
/// Friends in a room of their own aren't swept in — that walk exists, and
/// joining it is the hero's job — and neither is someone who invited you.
struct BuddyGroupSuggestion {
    struct Person: Identifiable {
        let userId: String
        let name: String
        let imageURL: String?
        var id: String { userId }
    }

    let people: [Person]
    /// Running when every one of them said running; walking otherwise.
    let activityType: String?

    /// Below this it's the single-friend hero's job.
    static let minimum = 2
    /// The server's `BUDDY_MAX_PARTICIPANTS` (8) less the host.
    static let maximumInvitees = 7

    @MainActor
    static func around(
        buddy: BuddySessionService, nearby: [BuddyCandidate] = []
    ) -> BuddyGroupSuggestion? {
        let me = buddy.currentUserId
        var seen = Set<String>()
        var people: [Person] = []
        var activities: [String] = []
        func add(_ person: Person, activity: String?) {
            guard person.userId != me, !seen.contains(person.userId),
                  people.count < maximumInvitees else { return }
            seen.insert(person.userId)
            people.append(person)
            if let activity { activities.append(activity) }
        }
        // Whoever invited you is answered by joining THEIR walk.
        for invite in buddy.invites {
            for p in invite.participants where invite.isHost(p.userId) { seen.insert(p.userId) }
        }
        for friend in nearby {
            add(Person(userId: friend.userId, name: friend.displayName, imageURL: friend.profileImageUrl),
                activity: nil)
        }
        for friend in buddy.lookingFriends {
            add(Person(userId: friend.userId, name: friend.displayName, imageURL: friend.profileImageUrl),
                activity: friend.activityType)
        }
        for friend in buddy.friendsOutNow where !friend.hasJoinableRoom {
            add(Person(userId: friend.userId, name: friend.displayName, imageURL: friend.profileImageUrl),
                activity: friend.isRunning ? "running" : "walking")
        }
        guard people.count >= minimum else { return nil }
        let allRunning = !activities.isEmpty && activities.count == people.count
            && activities.allSatisfy { $0 == "running" }
        return BuddyGroupSuggestion(people: people, activityType: allRunning ? "running" : nil)
    }

    /// "Alex, Sam and 2 others".
    var namesLine: String {
        let names = people.map(\.name)
        switch names.count {
        case 0: return ""
        case 1: return names[0]
        case 2: return String(localized: "\(names[0]) and \(names[1])")
        case 3: return String(localized: "\(names[0]), \(names[1]) and \(names[2])")
        default: return String(localized: "\(names[0]), \(names[1]) and \(names.count - 2) others")
        }
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
    /// Everyone around at once, when there are two or more.
    var group: BuddyGroupSuggestion? = nil
    var onActGroup: (BuddyGroupSuggestion) -> Void = { _ in }

    /// `actingId` while the group invite is in flight.
    static let groupActingId = "__everyone__"

    /// Friends physically next to you (Bluetooth, opt-in).
    @ObservedObject private var nearbyScanner = BuddyNearbyScanner.shared

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
            } else if let group {
                // The whole group is around: lead with going together, and
                // keep the one-at-a-time list under it.
                VStack(spacing: 20) {
                    nearbyRow
                    groupHero(group)
                    if !suggestions.isEmpty { more(suggestions) }
                    chooseOthersButton(title: "Choose who's coming")
                }
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            } else if let top = suggestions.first {
                VStack(spacing: 20) {
                    nearbyRow
                    hero(top)
                    if suggestions.count > 1 { more(Array(suggestions.dropFirst())) }
                    chooseOthersButton(title: "Choose someone else")
                }
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            } else {
                VStack(spacing: 20) {
                    nearbyRow
                    empty
                }
                .transition(.opacity)
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

    // MARK: Nearby

    /// The Bluetooth "next to you" control: an offer until it's on, then a
    /// quiet status with a way to switch it off.
    @ViewBuilder
    private var nearbyRow: some View {
        switch nearbyScanner.state {
        case .off:
            if nearbyScanner.isEnabled {
                EmptyView()
            } else {
                Button {
                    MADHaptics.action()
                    nearbyScanner.enableAndStart()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "dot.radiowaves.left.and.right")
                            .font(.system(size: 16, weight: .bold))
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Find friends next to me")
                                .font(MADTheme.Typography.smallBold)
                            Text("Uses Bluetooth only while this screen is open. Only friends can see it's you.")
                                .font(MADTheme.Typography.caption)
                                .foregroundStyle(Color.white.opacity(0.65))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(Color.white)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(panel(18))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        case .starting, .scanning:
            HStack(spacing: 8) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .accessibilityHidden(true)
                Text(nearbyScanner.nearbyFriends.isEmpty
                     ? String(localized: "Looking for friends next to you…")
                     : String(localized: "\(nearbyScanner.nearbyFriends.count) next to you"))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                Button("Stop") {
                    MADHaptics.tap()
                    nearbyScanner.disable()
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.white.opacity(0.7))
            }
            .font(MADTheme.Typography.caption)
            .foregroundStyle(Color.white.opacity(0.85))
            .padding(.horizontal, 14)
            .frame(minHeight: 40)
            .background(Capsule().fill(Color.white.opacity(0.08)))
        case .unavailable(let why):
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.circle")
                    .accessibilityHidden(true)
                Text(why)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button("Hide") { nearbyScanner.disable() }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.white.opacity(0.7))
            }
            .font(MADTheme.Typography.caption)
            .foregroundStyle(Color.white.opacity(0.75))
            .padding(12)
            .background(panel(16))
        }
    }

    // MARK: Group hero

    private func groupHero(_ group: BuddyGroupSuggestion) -> some View {
        let busy = actingId == Self.groupActingId
        return VStack(spacing: 14) {
            // Overlapping faces, up to four, then "+N".
            HStack(spacing: -16) {
                ForEach(group.people.prefix(4)) { person in
                    AvatarView(name: person.name, imageURL: person.imageURL, size: 60)
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.85), lineWidth: 2))
                }
                if group.people.count > 4 {
                    Text("+\(group.people.count - 4)")
                        .madFont(size: 16, weight: .bold, design: .rounded)
                        .foregroundStyle(Color.white)
                        .frame(width: 60, height: 60)
                        .background(Circle().fill(Color.white.opacity(0.2)))
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.85), lineWidth: 2))
                }
            }
            .frame(height: 72)
            .accessibilityHidden(true)
            VStack(spacing: 4) {
                Text("Walk with everyone around")
                    .madFont(size: 24, weight: .bold, design: .rounded, maxScale: 1.3)
                    .foregroundStyle(Color.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                Text(String(localized: "\(group.namesLine) are looking for a buddy or out right now"))
                    .font(MADTheme.Typography.caption)
                    .foregroundStyle(Color.white.opacity(0.75))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
            }
            WizardPrimaryButton(
                title: busy ? "Starting…" : String(localized: "Invite all \(group.people.count)"),
                icon: "person.3.fill",
                isBusy: busy,
                isEnabled: actingId == nil
            ) { onActGroup(group) }
            Text("Makes one lobby and invites all of them. Change the plan there before anyone starts.")
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
