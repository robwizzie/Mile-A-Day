import SwiftUI

/// The live roster, composed INTO the existing workout tracker rather than
/// presented as its own screen.
///
/// A buddy session decorates a normal workout — the user is still looking at
/// their own distance, ring and timer, with the crew shown alongside. Rendering
/// this as a separate screen would mean two sources of truth for "how far have
/// I gone".
struct BuddyRosterStrip: View {
    let session: BuddySessionState
    let currentUserId: String?

    var body: some View {
        VStack(spacing: MADTheme.Spacing.sm) {
            header

            if session.mode == .coopGoal {
                CoopGoalBar(session: session)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: MADTheme.Spacing.md) {
                    ForEach(orderedParticipants) { participant in
                        BuddyRosterAvatar(
                            participant: participant,
                            session: session,
                            isMe: participant.userId == currentUserId
                        )
                    }
                }
                .padding(.horizontal, MADTheme.Spacing.xs)
            }
        }
        .padding(MADTheme.Spacing.md)
        .madLiquidGlassCard()
    }

    /// Own card first, then by distance. Seeing yourself in a stable position
    /// matters more than strict ranking while you're moving.
    private var orderedParticipants: [BuddyParticipant] {
        let others = session.activeParticipants
            .filter { $0.userId != currentUserId }
            .sorted { $0.distanceMiles > $1.distanceMiles }
        if let me = session.activeParticipants.first(where: { $0.userId == currentUserId }) {
            return [me] + others
        }
        return others
    }

    private var header: some View {
        HStack(spacing: MADTheme.Spacing.xs) {
            Image(systemName: session.mode.icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(session.accentColor)

            Text(headerText)
                .font(MADTheme.Typography.smallBold)
                .foregroundStyle(MADTheme.Colors.madWhite.opacity(0.9))

            Spacer()

            if session.mode == .raceTime, let endsAt = session.endsAtDate {
                Text(endsAt, style: .timer)
                    .font(MADTheme.Typography.smallBold)
                    .monospacedDigit()
                    .foregroundStyle(session.accentColor)
            }
        }
    }

    private var headerText: String {
        switch session.mode {
        case .together:
            let n = session.activeParticipants.count
            return n == 2 ? "Walking together" : "\(n) walking together"
        case .coopGoal:
            let goal = session.goalValue ?? 0
            return String(format: "%.2f of %.1f mi together", session.groupDistanceMiles, goal)
        case .raceGoal:
            return String(format: "Race to %.1f mi", session.goalValue ?? 0)
        case .raceTime:
            return "Furthest wins"
        }
    }
}

/// One participant. Ring fills with their progress; the leader gets a glow.
private struct BuddyRosterAvatar: View {
    let participant: BuddyParticipant
    let session: BuddySessionState
    let isMe: Bool

    var body: some View {
        VStack(spacing: MADTheme.Spacing.xs) {
            AvatarWithRing(
                name: participant.displayName,
                imageURL: participant.profileImageUrl,
                progress: ringProgress,
                size: 52,
                ringWidth: isMe ? 4 : 3,
                accent: session.accentColor,
                badge: participant.status == .finished ? .check : .live
            )
            // Stale = no report in 90s. Dimmed to a hairline, never removed:
            // a friend who vanishes mid-walk reads as a crash.
            .opacity(participant.isStale ? 0.4 : 1)
            .overlay(alignment: .topTrailing) {
                if isLeader && !session.mode.isCooperative {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.yellow)
                        .offset(x: 2, y: -2)
                }
            }

            Text(isMe ? "You" : participant.displayName)
                .font(MADTheme.Typography.caption)
                .foregroundStyle(MADTheme.Colors.madWhite.opacity(isMe ? 1 : 0.75))
                .lineLimit(1)

            Text(participant.isStale ? "—" : String(format: "%.2f", participant.distanceMiles))
                .font(MADTheme.Typography.smallBold)
                .monospacedDigit()
                .foregroundStyle(
                    participant.isStale
                        ? MADTheme.Colors.madWhite.opacity(0.4)
                        : session.accentColor
                )
        }
        .frame(width: 64)
        .animation(MADTheme.Animation.standard, value: participant.distanceMiles)
    }

    private var isLeader: Bool {
        guard let best = session.activeParticipants.map(\.distanceMiles).max(), best > 0
        else { return false }
        return participant.distanceMiles >= best
    }

    /// Co-op has no individual target, so the ring shows each person's share of
    /// the group total instead of progress toward a goal they don't own.
    private var ringProgress: Double {
        switch session.mode {
        case .together:
            let best = session.activeParticipants.map(\.distanceMiles).max() ?? 0
            return best > 0 ? participant.distanceMiles / best : 0
        case .coopGoal:
            guard session.groupDistanceMiles > 0 else { return 0 }
            return participant.distanceMiles / session.groupDistanceMiles
        case .raceGoal:
            guard let goal = session.goalValue, goal > 0 else { return 0 }
            return participant.distanceMiles / goal
        case .raceTime:
            let best = session.activeParticipants.map(\.distanceMiles).max() ?? 0
            return best > 0 ? participant.distanceMiles / best : 0
        }
    }
}

/// Co-op's distinguishing visual: one shared bar, segmented per person, so you
/// read both the group total and who contributed what.
private struct CoopGoalBar: View {
    let session: BuddySessionState

    private let segmentColors: [Color] = [
        MADTheme.Colors.madRed,
        MADTheme.Colors.walkBlue,
        MADTheme.Colors.success,
        MADTheme.Colors.warning,
        .purple, .pink, .teal, .indigo,
    ]

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(MADTheme.Colors.madWhite.opacity(0.12))

                HStack(spacing: 0) {
                    ForEach(Array(contributors.enumerated()), id: \.element.id) { index, p in
                        Rectangle()
                            .fill(segmentColors[index % segmentColors.count])
                            .frame(width: max(0, geo.size.width * fraction(for: p)))
                    }
                }
                .clipShape(Capsule())
            }
        }
        .frame(height: 10)
        .animation(MADTheme.Animation.standard, value: session.groupDistanceMiles)
    }

    private var contributors: [BuddyParticipant] {
        session.activeParticipants.sorted { $0.userId < $1.userId }
    }

    private func fraction(for participant: BuddyParticipant) -> Double {
        guard let goal = session.goalValue, goal > 0 else { return 0 }
        return min(participant.distanceMiles / goal, 1)
    }
}
