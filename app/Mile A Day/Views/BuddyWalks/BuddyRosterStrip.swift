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
    /// MY pause, straight from the tracker — manual or the movement gate.
    ///
    /// Deliberately not optional and not defaulted: every host has to hand it
    /// over. My own tile is the one that must never wait for the server to
    /// agree with a fact this device decided, and a default would let the next
    /// host quietly reintroduce the round trip.
    let myPause: Bool

    @State private var confirmLeave = false
    /// The invite picker. A sheet from INSIDE the tracker's cover, so it
    /// presents over the workout rather than under it.
    @State private var showInvite = false
    @State private var answeringIds: Set<String> = []

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
                            isMe: participant.userId == currentUserId,
                            localPause: participant.userId == currentUserId ? myPause : nil
                        )
                    }

                    // The way to pull someone in from HERE — the screen a
                    // walker is actually looking at. It used to exist only in
                    // the lobby, which is gone the moment the walk starts, so
                    // "text Sam to join" was the whole feature mid-walk.
                    inviteTile
                }
                .padding(.horizontal, MADTheme.Spacing.xs)
                // A ScrollView CLIPS its content, and these tiles deliberately
                // draw outside their own bounds: the leader's crown is an
                // `.offset` overlay above the ring, and a badge sits proud of
                // the bottom-right. Without this the crown lost its points and
                // the badge lost its edge, both cut flat along the scroll's
                // own boundary.
                .padding(.vertical, 4)
            }

            // Somebody at the door. A friend of one of us asked in; the host
            // or that friend answers, right here, without leaving the walk.
            ForEach(session.pendingJoinRequests) { request in
                joinRequestRow(request)
            }
        }
        .padding(MADTheme.Spacing.md)
        .madLiquidGlassCard()
        .sheet(isPresented: $showInvite) {
            BuddyInviteSheet(session: session)
        }
    }

    private var inviteTile: some View {
        Button {
            MADHaptics.tap()
            showInvite = true
        } label: {
            VStack(spacing: MADTheme.Spacing.xs) {
                ZStack {
                    Circle()
                        .strokeBorder(
                            MADTheme.Colors.madWhite.opacity(0.35),
                            style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
                        .frame(width: 52, height: 52)
                    Image(systemName: "plus")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(MADTheme.Colors.madWhite.opacity(0.85))
                }
                Text("Invite")
                    .font(MADTheme.Typography.caption)
                    .foregroundStyle(MADTheme.Colors.madWhite.opacity(0.75))
                Text(" ")
                    .font(MADTheme.Typography.smallBold)
            }
            .frame(width: 78)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Invite friends to this walk")
    }

    private func joinRequestRow(_ request: BuddyJoinRequest) -> some View {
        let canAnswer = session.canAnswerJoinRequest(request, as: currentUserId)
        let busy = answeringIds.contains(request.userId)
        let via = request.friendUserIds.compactMap { id -> String? in
            if id == currentUserId { return "you" }
            return session.participants.first { $0.userId == id }?.displayName
        }.first
        return HStack(spacing: MADTheme.Spacing.sm) {
            AvatarView(name: request.displayName, imageURL: request.profileImageUrl, size: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(request.displayName) wants to join")
                    .font(MADTheme.Typography.smallBold)
                    .foregroundStyle(MADTheme.Colors.madWhite)
                    .lineLimit(1)
                Text(via.map { "Friends with \($0)" } ?? "A friend of the group")
                    .font(MADTheme.Typography.caption)
                    .foregroundStyle(MADTheme.Colors.madWhite.opacity(0.6))
                    .lineLimit(1)
            }
            Spacer(minLength: MADTheme.Spacing.xs)
            if canAnswer {
                HStack(spacing: 6) {
                    rosterAnswerButton("Not now", filled: false, busy: busy) {
                        answer(request, accept: false)
                    }
                    rosterAnswerButton("Let in", filled: true, busy: busy) {
                        answer(request, accept: true)
                    }
                }
                .fixedSize()
            } else {
                Text("Waiting on the host")
                    .font(MADTheme.Typography.caption)
                    .foregroundStyle(MADTheme.Colors.madWhite.opacity(0.5))
            }
        }
        .padding(.horizontal, MADTheme.Spacing.sm)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium, style: .continuous)
                .fill(MADTheme.Colors.warning.opacity(0.14))
        )
    }

    private func rosterAnswerButton(
        _ title: String, filled: Bool, busy: Bool, action: @escaping () -> Void
    ) -> some View {
        Button {
            guard !busy else { return }
            MADHaptics.action()
            action()
        } label: {
            Text(title)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(filled ? MADTheme.Colors.madBlack : MADTheme.Colors.madWhite)
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(
                    Capsule().fill(
                        filled ? MADTheme.Colors.warning : MADTheme.Colors.madWhite.opacity(0.14)))
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .opacity(busy ? 0.5 : 1)
    }

    private func answer(_ request: BuddyJoinRequest, accept: Bool) {
        answeringIds.insert(request.userId)
        Task {
            do {
                try await BuddySessionService.shared.respondToJoinRequest(
                    userId: request.userId, accept: accept, sessionId: session.id)
                if accept { MADHaptics.success() }
            } catch {
                BuddySessionService.shared.errorMessage =
                    (error as? LocalizedError)?.errorDescription ?? "Couldn't answer that."
            }
            answeringIds.remove(request.userId)
        }
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

            leaveButton
        }
    }

    /// Step out of the GROUP without ending the walk.
    ///
    /// The lobby's Leave stopped being reachable the moment the tracker took
    /// over, so once a buddy walk started the only way out of it was to finish
    /// the whole workout — which is the wrong trade for the ordinary case of
    /// two people who set off together and separate at the corner. Leaving here
    /// keeps the workout, the distance and the streak exactly as they are; it
    /// only stops the shared roster.
    private var leaveButton: some View {
        Button {
            MADHaptics.tap()
            confirmLeave = true
        } label: {
            Image(systemName: "person.fill.xmark")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(MADTheme.Colors.madWhite.opacity(0.5))
                .frame(width: 30, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Leave buddy walk")
        .confirmationDialog(
            "Leave this buddy walk?",
            isPresented: $confirmLeave,
            titleVisibility: .visible
        ) {
            Button("Leave", role: .destructive) {
                Task { await BuddySessionService.shared.leave() }
            }
            Button("Stay", role: .cancel) {}
        } message: {
            Text(
                "Your walk keeps going and every mile still counts — you just "
                    + "stop sharing this one. You can rejoin while they're still out."
            )
        }
    }

    /// What the rings are measuring, in words.
    private var ringLegend: String {
        if session.mode == .raceTime { return "Rings fill toward a mile" }
        if let goal = session.goalValue, goal > 0 {
            // The card's own tiles are in the reader's unit now; a header
            // still printing miles would leave one card speaking two units.
            return "Rings fill toward \(goal.distanceFormatted1)"
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
            return "\(session.groupDistanceMiles.distanceText) of \(goal.distanceFormatted1) together"
        case .raceGoal:
            return "Race to \((session.goalValue ?? 0).distanceFormatted1)"
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
    /// Non-nil for ME only: the device's own answer, which outranks the
    /// server's copy of it.
    let localPause: Bool?

    var body: some View {
        VStack(spacing: MADTheme.Spacing.xs) {
            AvatarWithRing(
                name: participant.displayName,
                imageURL: participant.profileImageUrl,
                progress: ringProgress,
                size: 52,
                ringWidth: isMe ? 4 : 3,
                // A paused walker's ring is drained of the session colour: it
                // is not filling right now, and a bright arc says it is.
                accent: isPaused ? MADTheme.Colors.madWhite.opacity(0.35) : session.accentColor,
                // No `.live` dot for everyone else. It marked "workout in
                // progress" on every face, during a workout — a red dot that is
                // always present on every tile carries no information and read
                // as a warning badge. The check still means something: they
                // finished.
                badge: badge
            )
            // Stale = no report in 90s. Dimmed to a hairline, never removed:
            // a friend who vanishes mid-walk reads as a crash. Never ME: a
            // report of mine can fail to land, but I am plainly here, and
            // dimming my own face over a dropped request says otherwise.
            .opacity(isStale ? 0.4 : 1)
            .overlay(alignment: .topTrailing) {
                if isLeader && !session.mode.isCooperative {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.yellow)
                        .offset(x: 2, y: -2)
                }
            }

            HStack(spacing: 3) {
                // Only the exception is marked. Outdoors is the overwhelming
                // default, so a badge on every face would carry no information
                // — but "they're on a treadmill" is exactly what explains a
                // pace that otherwise looks like a broken tracker.
                if participant.resolvedLocationType == .indoor {
                    Image(systemName: BuddyLocationType.indoor.icon)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(MADTheme.Colors.madWhite.opacity(0.55))
                }
                Text(isMe ? "You" : participant.displayName)
                    .font(MADTheme.Typography.caption)
                    .foregroundStyle(MADTheme.Colors.madWhite.opacity(isMe ? 1 : 0.75))
                    .lineLimit(1)
            }

            // A paused walker KEEPS their number. Stale replaces it with "—"
            // because a stale figure is a lie — they may have walked a mile
            // since we last heard from them. A paused one is exactly true, so
            // it stays and only changes colour; the badge on the circle is
            // what explains why it has stopped moving.
            Text(distanceLine)
                .font(MADTheme.Typography.smallBold)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(distanceTint)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
        // 52pt ring + a 4pt stroke + the badge's 2pt overhang needs more than
        // 64 to sit in, and `.offset` draws OUTSIDE layout bounds — so at 64
        // the ring and the two-decimal distance were both being cropped.
        .frame(width: 78)
        .animation(MADTheme.Animation.standard, value: participant.distanceMiles)
    }

    /// Paused: manual, or the movement gate quiet for a full evidence window
    /// (`WorkoutLocationManager.isPausedForCrew`). Still only while they are
    /// walking — the server serves `is_paused` false for anyone finished.
    ///
    /// MY tile answers from this device and everyone else's from their last
    /// report. Reading my own pause off the server made the badge a round
    /// trip: it appeared on the edge, then any report that forgot to mention
    /// the pause took it away again, on the one tile whose truth was sitting
    /// in memory the whole time.
    private var isPaused: Bool {
        if let localPause { return localPause }
        return participant.isPaused == true
    }

    /// Finished outranks paused: a walk that is over is over.
    private var badge: AvatarWithRing.Badge? {
        if participant.status == .finished { return .check }
        if isPaused { return .paused }
        return nil
    }

    /// Nobody is ever out of range from their own phone.
    private var isStale: Bool { !isMe && participant.isStale }

    /// Extracted rather than nested in the modifier: a three-way ternary of
    /// `Color`s inside `.foregroundStyle` is exactly the shape that tips this
    /// file's type-checker budget, and the error it produces names an
    /// innocent line elsewhere.
    private var distanceTint: Color {
        if isStale { return MADTheme.Colors.madWhite.opacity(0.4) }
        if isPaused { return MADTheme.Colors.warning }
        return session.accentColor
    }

    /// The app's own formatter: truncated to two decimals, in the reader's
    /// unit. `%.2f` ROUNDS, so a walk sitting on 0.825 put "0.83" on my tile
    /// over a tracker reading "0.82" — one screen, one number, two answers —
    /// and the hardcoded "mi" printed miles to someone whose every other
    /// screen is in kilometres.
    private var distanceLine: String {
        if isStale { return "—" }
        return participant.distanceMiles.distanceFormatted
    }

    private var accessibilityDescription: String {
        let who = isMe ? "You" : participant.displayName
        // Spoken, not abbreviated: VoiceOver reads "mi" as a word, not as
        // "miles". Still the reader's own unit.
        let miles = "\(participant.distanceMiles.distanceText) \(DistanceUnits.current.plural)"
        if isStale { return "\(who), out of range" }
        if participant.status == .finished { return "\(who), finished, \(miles)" }
        if isPaused { return "\(who), paused at \(miles)" }
        return "\(who), \(miles)"
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
