import SwiftUI

/// Home at a glance: the dashboard on one page, friends' day on the other, so
/// anyone about to lose a streak is one look and one Nudge away.
struct DuoHomeSplit<Home: View>: View {
    @ObservedObject var friendService: FriendService
    @ViewBuilder let home: () -> Home
    @Environment(\.duoSpread) private var duoSpread

    var body: some View {
        // One HStack whatever the width: the dashboard must keep its identity
        // (and its scroll position) as the phone folds and unfolds.
        HStack(spacing: 0) {
            home()
            if duoSpread {
                DuoFriendsTodayPanel(friendService: friendService)
                    .frame(maxWidth: .infinity)
            }
        }
    }
}

private struct DuoFriendsTodayPanel: View {
    @ObservedObject var friendService: FriendService
    @ObservedObject private var nudges = NudgeStatusStore.shared
    @State private var friends: [FriendActivityItem] = []
    @State private var fetchedAt = Date()
    @Environment(\.scenePhase) private var scenePhase

    /// At risk first, longest streak leading; then not yet done; done last.
    private var sorted: [FriendActivityItem] {
        friends.sorted { lhs, rhs in
            let l = rank(lhs), r = rank(rhs)
            if l != r { return l < r }
            return (lhs.current_streak ?? 0) > (rhs.current_streak ?? 0)
        }
    }

    private func rank(_ friend: FriendActivityItem) -> Int {
        if friend.completed_today { return 2 }
        return friend.streakAtRisk(since: fetchedAt) ? 0 : 1
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Friends today")
                    .madFont(size: 22, weight: .heavy, design: .rounded, maxScale: 1.4)
                    .foregroundColor(.white)
                    .padding(.top, 16)
                if friends.isEmpty {
                    Text("Add friends to see their day here.")
                        .madFont(size: 15, weight: .medium, design: .rounded, maxScale: 1.4)
                        .foregroundColor(.white.opacity(0.65))
                }
                ForEach(sorted) { friend in
                    row(friend)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(MADTheme.Colors.appBackgroundGradient.ignoresSafeArea())
        .task {
            // The first try can beat sign-in restoring the user id at launch.
            for _ in 0..<3 where friends.isEmpty {
                await load()
                if friends.isEmpty { try? await Task.sleep(for: .seconds(2)) }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await load() } }
        }
    }

    private func row(_ friend: FriendActivityItem) -> some View {
        let name = friend.first_name ?? friend.username ?? "Friend"
        let atRisk = friend.streakAtRisk(since: fetchedAt)
        return HStack(spacing: 12) {
            AvatarWithRing(name: name, imageURL: friend.profile_image_url,
                           progress: friend.completed_today ? 1 : min(friend.today_miles, 0.99), size: 46)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(name)
                        .madFont(size: 15, weight: .bold, design: .rounded, maxScale: 1.3)
                        .foregroundColor(.white)
                        .lineLimit(1)
                    StreakFlameChip(streak: friend.current_streak ?? 0, color: atRisk ? .red : .orange)
                }
                Text(friend.today_miles.distanceFormatted)
                    .madFont(size: 13, weight: .medium, design: .rounded, maxScale: 1.3)
                    .foregroundColor(.white.opacity(0.7))
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if !friend.completed_today {
                nudgeButton(friend, urgent: atRisk)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.06)))
        .overlay {
            if atRisk {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.red.opacity(0.75), lineWidth: 1.5)
            }
        }
    }

    private func nudgeButton(_ friend: FriendActivityItem, urgent: Bool) -> some View {
        let nudged = nudges.hasNudgedToday(friend.user_id)
        return Button {
            MADHaptics.action()
            Task { try? await friendService.nudgeFriend(friend.user_id) }
        } label: {
            Text(nudged ? "Nudged" : "Nudge")
                .madFont(size: 13, weight: .heavy, design: .rounded, maxScale: 1.2)
                .foregroundColor(.white)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Capsule().fill(nudged ? Color.white.opacity(0.12) : (urgent ? Color.red : MADTheme.Colors.madRed)))
        }
        .buttonStyle(.plain)
        .disabled(nudged)
    }

    private func load() async {
        guard let fresh = try? await friendService.fetchFriendsActivityToday() else { return }
        friends = fresh
        fetchedAt = Date()
    }
}
