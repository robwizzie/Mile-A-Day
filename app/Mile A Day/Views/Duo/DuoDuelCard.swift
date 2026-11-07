import SwiftUI

/// Duel view: two people, one on each page of the Duo, racing toward the
/// crease. Whoever leads sits closest to the finish line down the middle.
struct DuoDuelCard: View {
    let competition: Competition

    /// A duel is exactly two accepted people with no teams: the app has no
    /// separate head-to-head type.
    static func isDuel(_ competition: Competition) -> Bool {
        !competition.hasTeams && competition.acceptedRanked.count == 2
    }

    private var myId: String? { UserDefaults.standard.string(forKey: "backendUserId") }

    /// Me on the left, whatever the standings. A viewer outside the duel keeps
    /// the standings order.
    private var sides: (left: CompetitionUser, right: CompetitionUser)? {
        let ranked = competition.acceptedRanked
        guard ranked.count == 2 else { return nil }
        return ranked[1].user_id == myId ? (ranked[1], ranked[0]) : (ranked[0], ranked[1])
    }

    private var leadingScore: Double {
        max(competition.acceptedRanked.map { $0.score ?? 0 }.max() ?? 0, 0.01)
    }

    var body: some View {
        if let sides {
            HStack(spacing: 0) {
                side(sides.left, runsRight: true)
                finishLine
                side(sides.right, runsRight: false)
            }
            .frame(height: 200)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.white.opacity(0.05)))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }

    private var finishLine: some View {
        VStack(spacing: 0) {
            ForEach(0..<14, id: \.self) { index in
                HStack(spacing: 0) {
                    Rectangle().fill(index.isMultiple(of: 2) ? Color.white : .black)
                    Rectangle().fill(index.isMultiple(of: 2) ? Color.black : .white)
                }
            }
        }
        .frame(width: 10)
        .accessibilityHidden(true)
    }

    private func side(_ user: CompetitionUser, runsRight: Bool) -> some View {
        let name = user.username ?? "Friend"
        let share = min(max((user.score ?? 0) / leadingScore, 0), 1)
        return GeometryReader { geo in
            let travel = max(geo.size.width - 64, 0)
            ZStack(alignment: runsRight ? .leading : .trailing) {
                Capsule()
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 8)
                    .padding(.horizontal, 12)
                Capsule()
                    .fill(MADTheme.Colors.madRed)
                    .frame(width: travel * share + 24, height: 8)
                    .padding(.horizontal, 12)
                AvatarWithRing(name: name, imageURL: user.profile_image_url, progress: share, size: 52)
                    .padding(.horizontal, 6)
                    .offset(x: (runsRight ? 1 : -1) * travel * share)
            }
            .frame(maxHeight: .infinity)
            .overlay(alignment: runsRight ? .topLeading : .topTrailing) {
                Text(name)
                    .madFont(size: 15, weight: .bold, design: .rounded, maxScale: 1.3)
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .padding(14)
            }
            .overlay(alignment: runsRight ? .bottomLeading : .bottomTrailing) {
                Text(competition.memberScoreLabel(user))
                    .madFont(size: 26, weight: .heavy, design: .rounded, maxScale: 1.3, monospacedDigit: true)
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(14)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name), \(competition.memberScoreLabel(user))")
    }
}
