import SwiftUI

/// "Who can join" — the one place a buddy walk says whether friends can drop
/// in, and (for the host) the one control that changes it.
///
/// It exists because joining a walk in progress is invisible until it
/// happens: a friend sees you're out, taps Join, and appears on your roster.
/// Between regulars that's the feature; for someone on their first walk it's
/// a stranger-shaped surprise. So the lobby and the live roster both SAY it,
/// in a sentence, and the host can tighten it at any point — before the walk
/// or halfway through — without a setup step of its own.
struct BuddyJoinPolicyControl: View {
    let session: BuddySessionState
    /// `.full` in the lobby (the sentence under the choice); `.compact` on the
    /// live roster, where there's one line to spare.
    var style: Style = .full

    enum Style { case full, compact }

    @ObservedObject private var buddy = BuddySessionService.shared
    @ObservedObject private var closeFriends = CloseFriendsService.shared

    private var isHost: Bool { session.isHost(buddy.currentUserId) }
    private var policy: BuddyJoinPolicy { session.joinPolicy }
    private var hasCloseFriends: Bool { !closeFriends.closeFriendIds.isEmpty }

    var body: some View {
        Group {
            if isHost {
                Menu {
                    Picker("Who can join", selection: Binding(
                        get: { policy },
                        set: { choice in
                            guard choice != policy else { return }
                            MADHaptics.tap()
                            Task { await buddy.setJoinPolicy(choice) }
                        }
                    )) {
                        ForEach(BuddyJoinPolicy.allCases) { option in
                            Label(optionTitle(option), systemImage: option.icon)
                                .tag(option)
                                // A close-friends walk with no close friends is
                                // an invite-only walk with a confusing name.
                                .disabled(option == .closeFriends && !hasCloseFriends)
                        }
                    }
                } label: {
                    row(showsChevron: true)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Who can join: \(policy.title)")
                .accessibilityHint("Changes who can join this walk without an invite")
            } else {
                row(showsChevron: false)
                    .accessibilityElement(children: .combine)
            }
        }
        .task { if isHost { await closeFriends.loadIfNeeded() } }
    }

    private func optionTitle(_ option: BuddyJoinPolicy) -> String {
        option == .closeFriends && !hasCloseFriends ? "Close friends (add some first)" : option.title
    }

    /// From a guest's side the sentence is about the host's friends, not "yours".
    private var sentence: String {
        if isHost { return policy.explanation }
        let host = session.participants.first(where: \.isHost)?.displayName ?? "the host"
        switch policy {
        case .friends: return "\(host)'s friends can join in while you're out."
        case .closeFriends: return "Only \(host)'s close friends can join in."
        case .inviteOnly: return "Only people \(host) invites can join."
        }
    }

    @ViewBuilder
    private func row(showsChevron: Bool) -> some View {
        switch style {
        case .full:
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: policy.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.85))
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color.white.opacity(0.12)))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text("Who can join: ")
                            .foregroundStyle(Color.white.opacity(0.6))
                        + Text(policy.title)
                            .foregroundStyle(Color.white)
                        if showsChevron {
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Color.white.opacity(0.5))
                                .accessibilityHidden(true)
                        }
                    }
                    .font(MADTheme.Typography.smallBold)
                    Text(sentence)
                        .font(MADTheme.Typography.caption)
                        .foregroundStyle(Color.white.opacity(0.6))
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        case .compact:
            HStack(spacing: 5) {
                Image(systemName: policy.icon)
                    .font(.system(size: 10, weight: .bold))
                    .accessibilityHidden(true)
                Text(policy == .friends ? "Open to friends" : policy.title)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                if showsChevron {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .heavy))
                        .accessibilityHidden(true)
                }
            }
            .foregroundStyle(Color.white.opacity(0.75))
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color.white.opacity(0.10)))
            .fixedSize()
        }
    }
}
