import SwiftUI

/// Duolingo-style post-mile moment: today's-miles leaderboard among you + your
/// friends. Your row animates up into its spot with a glow. Top 3 are always
/// shown; if you're lower, we show the top 3, the friend just ahead of you, and
/// you — plus how far you are behind 3rd.
struct LeaderboardMoveUpView: View {
    let stats: GoalCompletionStats
    @ObservedObject private var manager = CelebrationManager.shared

    @State private var rows: [LBRow] = []
    @State private var loaded = false
    @State private var showOverlay = false
    @State private var showBoard = false
    @State private var animateMe = false
    @State private var showButton = false

    private var myId: String? { UserDefaults.standard.string(forKey: "backendUserId") }
    private var myRank: Int { (rows.firstIndex { $0.isMe }.map { $0 + 1 }) ?? 0 }
    private var totalCount: Int { rows.count }

    struct LBRow: Identifiable {
        let user_id: String
        let name: String
        let imageURL: String?
        let miles: Double
        let completed: Bool
        let isMe: Bool
        var id: String { user_id }
    }

    private enum DisplayItem: Identifiable {
        case row(LBRow, rank: Int)
        case gap
        var id: String {
            switch self {
            case .row(let r, _): return r.user_id
            case .gap: return "gap"
            }
        }
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.10, green: 0.05, blue: 0.08), .black],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
                .opacity(showOverlay ? 1 : 0)

            VStack(spacing: MADTheme.Spacing.lg) {
                Spacer(minLength: MADTheme.Spacing.xl)

                header

                if !loaded {
                    ProgressView().tint(.white).padding(.vertical, MADTheme.Spacing.xxl)
                } else if rows.count <= 1 {
                    soloState
                } else {
                    board
                    gapLine
                }

                Spacer()

                if showButton {
                    Button { dismiss() } label: {
                        Text("Continue").frame(maxWidth: .infinity)
                    }
                    .madPrimaryButton(fullWidth: true)
                    .padding(.horizontal, MADTheme.Spacing.lg)
                    .padding(.bottom, MADTheme.Spacing.xl)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .onAppear { runIntro() }
        .task { await load() }
    }

    private var header: some View {
        VStack(spacing: 6) {
            Image(systemName: "trophy.fill")
                .font(.system(size: 34, weight: .black))
                .foregroundStyle(LinearGradient(colors: [.yellow, .orange], startPoint: .top, endPoint: .bottom))
                .shadow(color: .orange.opacity(0.5), radius: 10)
            Text("Today's Leaderboard")
                .font(.system(size: 22, weight: .black, design: .rounded))
                .foregroundColor(.white)
            if loaded && rows.count > 1 {
                Text(myRank <= 3 ? "You're in the top 3! 🔥" : "You're #\(myRank) of \(totalCount) today")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.65))
            }
        }
        .opacity(showBoard ? 1 : 0)
    }

    private var board: some View {
        VStack(spacing: MADTheme.Spacing.sm) {
            ForEach(displayItems) { item in
                switch item {
                case .row(let row, let rank):
                    rowView(row, rank: rank)
                        .offset(y: row.isMe && !animateMe ? 90 : 0)
                        .opacity(row.isMe && !animateMe ? 0 : 1)
                        .scaleEffect(row.isMe && animateMe ? 1.0 : (row.isMe ? 0.9 : 1.0))
                case .gap:
                    Image(systemName: "ellipsis")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white.opacity(0.3))
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.horizontal, MADTheme.Spacing.lg)
        .opacity(showBoard ? 1 : 0)
    }

    private func rowView(_ row: LBRow, rank: Int) -> some View {
        HStack(spacing: MADTheme.Spacing.md) {
            rankBadge(rank)
            AvatarView(name: row.name, imageURL: row.imageURL, size: 40)
                .opacity(row.completed || row.isMe ? 1 : 0.5)
            VStack(alignment: .leading, spacing: 1) {
                Text(row.isMe ? "You" : row.name)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
                if !row.completed && !row.isMe {
                    Text("not yet today")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.4))
                }
            }
            Spacer()
            Text("\(String(format: "%.2f", row.miles)) mi")
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
                .monospacedDigit()
        }
        .padding(.vertical, 10)
        .padding(.horizontal, MADTheme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium, style: .continuous)
                .fill(row.isMe ? AnyShapeStyle(MADTheme.Colors.madRed.opacity(0.22)) : AnyShapeStyle(Color.white.opacity(0.05)))
                .overlay(
                    RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium, style: .continuous)
                        .strokeBorder(row.isMe ? MADTheme.Colors.madRed.opacity(0.7) : .clear, lineWidth: 1.5)
                )
        )
        .shadow(color: row.isMe && animateMe ? MADTheme.Colors.madRed.opacity(0.5) : .clear, radius: 12)
    }

    private func rankBadge(_ rank: Int) -> some View {
        ZStack {
            Circle()
                .fill(rankColor(rank))
                .frame(width: 28, height: 28)
            Text("\(rank)")
                .font(.system(size: 13, weight: .black, design: .rounded))
                .foregroundColor(rank <= 3 ? .black : .white)
                .monospacedDigit()
        }
    }

    private func rankColor(_ rank: Int) -> Color {
        switch rank {
        case 1: return Color(red: 1.0, green: 0.84, blue: 0.0)
        case 2: return Color(white: 0.8)
        case 3: return Color(red: 0.8, green: 0.5, blue: 0.2)
        default: return Color.white.opacity(0.12)
        }
    }

    @ViewBuilder
    private var gapLine: some View {
        if myRank > 3, let third = rows.indices.contains(2) ? rows[2] : nil {
            let behind = max(0, third.miles - (rows.first { $0.isMe }?.miles ?? 0))
            Text(behind <= 0 ? "You're right on the podium!" : "\(String(format: "%.2f", behind)) mi behind 3rd place 🏅")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(.orange)
                .padding(.top, 4)
                .opacity(showBoard ? 1 : 0)
        }
    }

    private var soloState: some View {
        VStack(spacing: MADTheme.Spacing.sm) {
            Text("You're flying solo! 🚀")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            Text("Add friends to race up today's miles leaderboard together.")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.5))
                .multilineTextAlignment(.center)
                .padding(.horizontal, MADTheme.Spacing.xl)
        }
        .opacity(showBoard ? 1 : 0)
    }

    // The visible window: top 3 always, then (if you're lower) the friend just
    // ahead of you and your row.
    private var displayItems: [DisplayItem] {
        guard !rows.isEmpty else { return [] }
        let ranked = rows.enumerated().map { (idx, r) in (rank: idx + 1, row: r) }
        if rows.count <= 5 || myRank <= 4 {
            return ranked.prefix(5).map { .row($0.row, rank: $0.rank) }
        }
        var items: [DisplayItem] = ranked.prefix(3).map { .row($0.row, rank: $0.rank) }
        items.append(.gap)
        // friend directly ahead of me (rank myRank-1) then me
        if myRank - 2 >= 3, myRank - 2 < ranked.count {
            let above = ranked[myRank - 2]
            items.append(.row(above.row, rank: above.rank))
        }
        let me = ranked[myRank - 1]
        items.append(.row(me.row, rank: me.rank))
        return items
    }

    // MARK: - Data + sequence

    private func load() async {
        var entries: [LBRow] = []
        if let items = try? await FriendService().fetchFriendsActivityToday() {
            for it in items where it.user_id != myId {
                entries.append(LBRow(
                    user_id: it.user_id,
                    name: it.displayName,
                    imageURL: it.profile_image_url,
                    miles: it.today_miles,
                    completed: it.completed_today,
                    isMe: false
                ))
            }
        }
        let me = LBRow(
            user_id: myId ?? "me",
            name: UserManager.shared.currentUser.username ?? UserManager.shared.currentUser.name,
            imageURL: UserManager.shared.currentUser.profileImageUrl,
            miles: stats.todaysDistance,
            completed: true,
            isMe: true
        )
        entries.append(me)
        entries.sort { $0.miles > $1.miles }

        await MainActor.run {
            rows = entries
            loaded = true
            // Animate the board in, then my row climbing into place.
            withAnimation(.easeOut(duration: 0.3)) { showBoard = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) { animateMe = true }
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { showButton = true }
            }
        }
    }

    private func runIntro() {
        withAnimation(.easeOut(duration: 0.3)) { showOverlay = true }
    }

    private func dismiss() {
        withAnimation(.easeOut(duration: 0.25)) { showOverlay = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            manager.dismissCurrentCelebration()
        }
    }
}
