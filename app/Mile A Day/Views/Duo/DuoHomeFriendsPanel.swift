import SwiftUI

/// Home at a glance: with friends, the dashboard on one page and their day on
/// the other, so anyone about to lose a streak is one look and one Nudge away.
/// With none there is no second page at all: the dashboard takes the whole
/// spread (`\.duoHomeWide`) instead of sitting beside an empty half.
struct DuoHomeSplit<Home: View>: View {
    @ObservedObject var friendService: FriendService
    @ViewBuilder let home: () -> Home
    @Environment(\.duoSpread) private var duoSpread
    @Environment(\.scenePhase) private var scenePhase
    @State private var friends: [FriendActivityItem] = []
    @State private var fetchedAt = Date()

    var body: some View {
        // Inside the NavigationStack, so a pushed screen gets the whole
        // display. One HStack at every width: the dashboard keeps its identity
        // and scroll position through a fold.
        HStack(spacing: 0) {
            home()
                .frame(maxWidth: .infinity)
                .environment(\.duoHomeWide, duoSpread && friends.isEmpty)
            if duoSpread, !friends.isEmpty {
                DuoFriendsTodayPanel(friendService: friendService, friends: friends, fetchedAt: fetchedAt)
                    .frame(maxWidth: .infinity)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: friends.isEmpty)
        // Only while unfolded: nowhere else does this view make a request.
        .task(id: duoSpread) {
            guard duoSpread else { return }
            // The first try can beat sign-in restoring the user id at launch.
            for _ in 0..<3 where friends.isEmpty {
                await load()
                if friends.isEmpty { try? await Task.sleep(for: .seconds(2)) }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, duoSpread { Task { await load() } }
        }
        .onChange(of: friendService.friends.count) {
            if duoSpread { Task { await load() } }
        }
    }

    private func load() async {
        guard let fresh = try? await friendService.fetchFriendsActivityToday() else { return }
        friends = fresh
        fetchedAt = Date()
    }
}

private struct DuoFriendsTodayPanel: View {
    @ObservedObject var friendService: FriendService
    let friends: [FriendActivityItem]
    let fetchedAt: Date
    @ObservedObject private var nudges = NudgeStatusStore.shared

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
                ForEach(sorted) { friend in
                    row(friend)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(MADTheme.Colors.appBackgroundGradient.ignoresSafeArea())
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
}
