import SwiftUI

/// Post-session results.
///
/// Shows reconciled numbers where they exist and live numbers until then —
/// `final_distance_miles` is stamped asynchronously once each participant's
/// real HKWorkout syncs, which can trail the session's end by a minute or two.
struct BuddyRecapView: View {
    let sessionId: String

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var buddy = BuddySessionService.shared

    @ObservedObject private var freshWindow = FreshPostWindowManager.shared

    @State private var recap: BuddyRecapResponse?
    @State private var isLoading = true
    /// Item-presented (ios.md): the wizard needs the loaded session, and an
    /// isPresented flag beside separate state can race to a stale value.
    @State private var wizardSession: BuddySessionState?

    var body: some View {
        NavigationStack {
            ZStack {
                MADTheme.Colors.appBackgroundGradient.ignoresSafeArea()

                if isLoading {
                    ProgressView().tint(MADTheme.Colors.madWhite)
                } else if let session = recap?.session {
                    ScrollView {
                        VStack(spacing: MADTheme.Spacing.lg) {
                            headline(session)
                            standings(session)
                            postSection(session)
                            Color.clear.frame(height: MADTheme.Spacing.lg)
                        }
                        .padding(MADTheme.Spacing.md)
                    }
                    .fullScreenCover(item: $wizardSession) { session in
                        BuddyPostWizardView(session: session)
                    }
                } else {
                    Text("Couldn't load the recap.")
                        .font(MADTheme.Typography.body)
                        .foregroundStyle(MADTheme.Colors.madWhite.opacity(0.7))
                }
            }
            .navigationTitle((recap?.session.isRunning ?? false) ? "Buddy Run" : "Buddy Walk")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        buddy.clearFinishedSession()
                        dismiss()
                    }
                }
            }
        }
        .task { await load() }
    }

    // MARK: - Sections

    /// The result as a celebration: ringed mode icon, the verdict, and the
    /// group total as the biggest number on the screen. Same visual family as
    /// the start sheet's summary header and the lobby's plan header — the walk
    /// should end looking like the thing you set up, not like a settings list.
    private func headline(_ session: BuddySessionState) -> some View {
        VStack(spacing: MADTheme.Spacing.sm) {
            ZStack {
                Circle()
                    .fill(session.accentColor.opacity(0.18))
                    .frame(width: 76, height: 76)
                Circle()
                    .strokeBorder(session.accentColor.opacity(0.45), lineWidth: 1.5)
                    .frame(width: 76, height: 76)
                Image(systemName: session.mode.icon)
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(session.accentColor)
            }

            Text(headlineText(session))
                .font(MADTheme.Typography.title2)
                .foregroundStyle(MADTheme.Colors.madWhite)
                .multilineTextAlignment(.center)

            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(session.groupDistanceMiles.milesText)
                    .font(.system(size: 46, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(MADTheme.Colors.madWhite)
                Text("mi")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(MADTheme.Colors.madWhite.opacity(0.55))
            }

            Text(subheadText(session))
                .font(MADTheme.Typography.subheadline)
                .foregroundStyle(MADTheme.Colors.madWhite.opacity(0.65))
                .multilineTextAlignment(.center)

            // A shared goal gets its bar — "did we make it" is the whole
            // question that mode asks, so answer it visually, not just in the
            // headline's wording.
            if session.mode == .coopGoal, let goal = session.goalValue, goal > 0 {
                progressCapsule(
                    fraction: session.groupDistanceMiles / goal,
                    tint: session.accentColor
                )
                .padding(.horizontal, MADTheme.Spacing.lg)
                .padding(.top, MADTheme.Spacing.xs)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, MADTheme.Spacing.lg)
        .padding(.horizontal, MADTheme.Spacing.md)
        .madLiquidGlass(cornerRadius: MADTheme.CornerRadius.extraLarge)
    }

    /// Everyone's share of the walk, in ONE card — divider rows like the start
    /// sheet's friend list, not floating slabs. Each row carries a thin bar
    /// scaled to the day's longest distance, so "how'd we compare" is read at
    /// a glance instead of by subtracting numbers.
    private func standings(_ session: BuddySessionState) -> some View {
        let rows = ranked(session)
        let top = rows.map(\.bestDistance).max() ?? 0

        return VStack(alignment: .leading, spacing: MADTheme.Spacing.sm) {
            Text(session.mode.isCooperative ? "The crew" : "How it finished")
                .font(MADTheme.Typography.headline)
                .foregroundStyle(MADTheme.Colors.madWhite)

            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, participant in
                    if index > 0 {
                        Divider().background(MADTheme.Colors.madWhite.opacity(0.08))
                    }
                    standingsRow(
                        participant,
                        session: session,
                        topDistance: top
                    )
                }
            }
            .background(
                RoundedRectangle(
                    cornerRadius: MADTheme.CornerRadius.large, style: .continuous
                )
                .fill(MADTheme.Colors.madWhite.opacity(0.06))
                .overlay(
                    RoundedRectangle(
                        cornerRadius: MADTheme.CornerRadius.large, style: .continuous
                    )
                    .strokeBorder(MADTheme.Colors.madWhite.opacity(0.10), lineWidth: 1)
                )
            )
        }
    }

    private func standingsRow(
        _ participant: BuddyParticipant,
        session: BuddySessionState,
        topDistance: Double
    ) -> some View {
        let isYou = participant.userId == buddy.currentUserId
        let isWinner = !session.mode.isCooperative && participant.place == 1

        return HStack(spacing: MADTheme.Spacing.md) {
            // Cooperative modes have no ranking to show — everybody either
            // made it or didn't, together.
            if !session.mode.isCooperative, let place = participant.place {
                Group {
                    if place == 1 {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.yellow)
                    } else {
                        Text("\(place)")
                            .font(MADTheme.Typography.title3)
                            .monospacedDigit()
                            .foregroundStyle(MADTheme.Colors.madWhite.opacity(0.5))
                    }
                }
                .frame(width: 24)
            }

            AvatarView(
                name: participant.displayName,
                imageURL: participant.profileImageUrl,
                size: 44
            )
            .overlay(
                Circle().strokeBorder(
                    isYou ? session.accentColor : .clear, lineWidth: 2)
            )

            VStack(alignment: .leading, spacing: 6) {
                Text(isYou ? "You" : participant.displayName)
                    .font(MADTheme.Typography.bodyBold)
                    .foregroundStyle(MADTheme.Colors.madWhite)
                    .lineLimit(1)

                progressCapsule(
                    fraction: topDistance > 0
                        ? participant.bestDistance / topDistance : 0,
                    tint: session.accentColor.opacity(isYou || isWinner ? 1 : 0.55)
                )
            }

            Spacer(minLength: MADTheme.Spacing.sm)

            VStack(alignment: .trailing, spacing: 3) {
                Text("\(participant.bestDistance.milesText) mi")
                    .font(MADTheme.Typography.bodyBold)
                    .monospacedDigit()
                    .foregroundStyle(session.accentColor)

                // Until the real workout syncs, the number on screen is the
                // one accumulated from live reports. Say so rather than let it
                // silently change a minute later — but quietly: it resolves
                // itself, so it must not read like an error.
                if participant.finalDistanceMiles == nil {
                    HStack(spacing: 4) {
                        ProgressView()
                            .controlSize(.mini)
                            .tint(MADTheme.Colors.madWhite.opacity(0.4))
                        Text("syncing")
                            .font(MADTheme.Typography.caption)
                            .foregroundStyle(MADTheme.Colors.madWhite.opacity(0.4))
                    }
                }
            }
        }
        .padding(.horizontal, MADTheme.Spacing.md)
        .padding(.vertical, MADTheme.Spacing.sm + 2)
    }

    /// Thin track-and-fill bar. GeometryReader because the fill's width IS a
    /// fraction of the track's — anything based on `.offset` or a guessed
    /// width draws outside what the row measured (ios.md).
    private func progressCapsule(fraction: Double, tint: Color) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(MADTheme.Colors.madWhite.opacity(0.12))
                Capsule()
                    .fill(tint)
                    .frame(
                        width: max(6, geo.size.width * min(1, max(0, fraction))))
            }
        }
        .frame(height: 6)
    }

    /// The post flow's front door — opens the crew-and-routes wizard
    /// (BuddyPostWizardView), which owns the composer hand-off. Posting
    /// follows the same 10-minute rule as every other photo post, and a recap
    /// is reachable long after the walk (deep link, notification, a screen
    /// left open) — so the CTA reflects the window rather than 403-ing on
    /// tap, and it says what closed rather than just going grey, since this
    /// is the screen's primary action.
    @ViewBuilder
    private func postSection(_ session: BuddySessionState) -> some View {
        if freshWindow.isOpen {
            Button {
                MADHaptics.action()
                wizardSession = session
            } label: {
                HStack(spacing: MADTheme.Spacing.md) {
                    ZStack {
                        Circle()
                            .fill(MADTheme.Colors.madWhite.opacity(0.18))
                            .frame(width: 40, height: 40)
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(session.isRunning ? "Post this run" : "Post this walk")
                            .font(MADTheme.Typography.bodyBold)
                        Text("Everyone's on it — see the crew and routes first")
                            .font(MADTheme.Typography.caption)
                            .opacity(0.85)
                    }
                    Spacer(minLength: MADTheme.Spacing.sm)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .bold))
                        .opacity(0.85)
                }
                .foregroundStyle(MADTheme.Colors.madWhite)
                .padding(MADTheme.Spacing.md)
                .background(
                    RoundedRectangle(
                        cornerRadius: MADTheme.CornerRadius.large, style: .continuous
                    )
                    .fill(session.accentColor)
                )
            }
            .buttonStyle(.plain)
        } else {
            Text("Photos share in the 10 minutes after a walk — that window has closed.")
                .font(MADTheme.Typography.caption)
                .foregroundStyle(MADTheme.Colors.madWhite.opacity(0.6))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.vertical, MADTheme.Spacing.md)
        }
    }

    // MARK: - Copy

    private func headlineText(_ session: BuddySessionState) -> String {
        switch session.mode {
        case .together:
            return "Nice walk together"
        case .coopGoal:
            let goal = session.goalValue ?? 0
            return session.groupDistanceMiles >= goal ? "Goal smashed" : "Good effort together"
        case .raceGoal, .raceTime:
            guard let winner = session.winnerUserId else { return "Dead heat" }
            if winner == buddy.currentUserId { return "You won" }
            let name =
                session.participants.first { $0.userId == winner }?.displayName ?? "Your buddy"
            return "\(name) won"
        }
    }

    /// The line under the big number. The number itself is rendered above at
    /// hero size, so this only has to say what it counts.
    private func subheadText(_ session: BuddySessionState) -> String {
        switch session.mode {
        case .together:
            return "miles between you"
        case .coopGoal:
            let goal = session.goalValue ?? 0
            let goalText =
                goal == goal.rounded() ? "\(Int(goal))" : String(format: "%.1f", goal)
            return "of your \(goalText) mile goal, together"
        case .raceGoal, .raceTime:
            return session.winnerUserId == nil
                ? "miles in total — too close to call"
                : "miles covered in total"
        }
    }

    private func ranked(_ session: BuddySessionState) -> [BuddyParticipant] {
        session.activeParticipants.sorted { $0.bestDistance > $1.bestDistance }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        recap = try? await buddy.recap(sessionId: sessionId)
    }
}
