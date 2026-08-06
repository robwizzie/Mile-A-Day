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

            // The rings were unexplained, which is most of why they read as
            // decoration with a hidden meaning. One line fixes that.
            Text(ringLegend)
                .font(MADTheme.Typography.caption)
                .foregroundStyle(MADTheme.Colors.madWhite.opacity(0.5))
                .frame(maxWidth: .infinity, alignment: .leading)

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

    /// What the rings are measuring, in words.
    private var ringLegend: String {
        if session.mode == .raceTime { return "Rings fill toward a mile" }
        if let goal = session.goalValue, goal > 0 {
            return String(format: "Rings fill toward %.1f mi", goal)
        }
        return "Rings fill toward a mile"
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
                // No `.live` dot for everyone else. It marked "workout in
                // progress" on every face, during a workout — a red dot that is
                // always present on every tile carries no information and read
                // as a warning badge. The check still means something: they
                // finished.
                badge: participant.status == .finished ? .check : nil
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

            Text(participant.isStale ? "—" : String(format: "%.2f mi", participant.distanceMiles))
                .font(MADTheme.Typography.smallBold)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(
                    participant.isStale
                        ? MADTheme.Colors.madWhite.opacity(0.4)
                        : session.accentColor
                )
        }
        // 52pt ring + a 4pt stroke + the badge's 2pt overhang needs more than
        // 64 to sit in, and `.offset` draws OUTSIDE layout bounds — so at 64
        // the ring and the two-decimal distance were both being cropped.
        .frame(width: 78)
        .animation(MADTheme.Animation.standard, value: participant.distanceMiles)
    }

    private var isLeader: Bool {
        guard let best = session.activeParticipants.map(\.distanceMiles).max(), best > 0
        else { return false }
        return participant.distanceMiles >= best
    }

    /// Everyone's ring measures the SAME distance, so comparing two of them
    /// means something.
    ///
    /// It used to be `yourDistance / furthestPersonsDistance`, which quietly
    /// made the leader's ring full — and `AvatarWithRing` paints a full ring
    /// solid GREEN. So in "Just Together", a mode whose own subtitle is "No
    /// goal — just move together", whoever was a few feet ahead got a green
    /// trophy ring and everyone else got a partial blue arc, with nothing on
    /// screen explaining either. It turned a walk into a scoreboard nobody
    /// asked for, and it also meant the rings rescaled every time somebody
    /// moved, so they never sat still.
    ///
    /// Now it's progress toward a fixed target: the session's goal where there
    /// is one, otherwise the daily mile. Green-at-full then means "they
    /// finished their mile", which is worth showing.
    private var ringProgress: Double {
        guard ringTarget > 0 else { return 0 }
        return participant.distanceMiles / ringTarget
    }

    private var ringTarget: Double {
        // race_time's goal is MINUTES, not miles — using it here would compare
        // a distance against a duration and produce a meaningless ring.
        if session.mode == .raceTime { return BuddyRosterAvatar.dailyMile }
        if let goal = session.goalValue, goal > 0 { return goal }
        return BuddyRosterAvatar.dailyMile
    }

    /// The app's whole premise, and the only target every participant shares
    /// when the session itself declares none.
    static let dailyMile: Double = 1.0
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
