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
    @State private var showComposer = false

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
                            shareButton(session)
                            Color.clear.frame(height: MADTheme.Spacing.lg)
                        }
                        .padding(MADTheme.Spacing.md)
                    }
                } else {
                    Text("Couldn't load the recap.")
                        .font(MADTheme.Typography.body)
                        .foregroundStyle(MADTheme.Colors.madWhite.opacity(0.7))
                }
            }
            .navigationTitle("Buddy Walk")
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

    private func headline(_ session: BuddySessionState) -> some View {
        VStack(spacing: MADTheme.Spacing.sm) {
            Image(systemName: session.mode.icon)
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(session.accentColor)

            Text(headlineText(session))
                .font(MADTheme.Typography.title2)
                .foregroundStyle(MADTheme.Colors.madWhite)
                .multilineTextAlignment(.center)

            Text(subheadText(session))
                .font(MADTheme.Typography.body)
                .foregroundStyle(MADTheme.Colors.madWhite.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .padding(.top, MADTheme.Spacing.lg)
    }

    private func standings(_ session: BuddySessionState) -> some View {
        VStack(spacing: MADTheme.Spacing.sm) {
            ForEach(ranked(session)) { participant in
                HStack(spacing: MADTheme.Spacing.md) {
                    // Cooperative modes have no ranking to show — everybody
                    // either made it or didn't, together.
                    if !session.mode.isCooperative, let place = participant.place {
                        Text("\(place)")
                            .font(MADTheme.Typography.title3)
                            .monospacedDigit()
                            .foregroundStyle(
                                place == 1 ? .yellow : MADTheme.Colors.madWhite.opacity(0.5)
                            )
                            .frame(width: 24)
                    }

                    AvatarView(
                        name: participant.displayName,
                        imageURL: participant.profileImageUrl,
                        size: 40
                    )

                    Text(
                        participant.userId == buddy.currentUserId
                            ? "You" : participant.displayName
                    )
                    .font(MADTheme.Typography.bodyBold)
                    .foregroundStyle(MADTheme.Colors.madWhite)

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text(String(format: "%.2f mi", participant.bestDistance))
                            .font(MADTheme.Typography.bodyBold)
                            .monospacedDigit()
                            .foregroundStyle(session.accentColor)

                        // Until the real workout syncs, the number on screen is
                        // the one accumulated from live reports. Say so rather
                        // than let it silently change a minute later.
                        if participant.finalDistanceMiles == nil {
                            Text("syncing…")
                                .font(MADTheme.Typography.caption)
                                .foregroundStyle(MADTheme.Colors.madWhite.opacity(0.4))
                        }
                    }
                }
                .padding(MADTheme.Spacing.sm)
                .madLiquidGlass(cornerRadius: MADTheme.CornerRadius.medium)
            }
        }
    }

    /// Sharing follows the same 10-minute rule as every other photo post, and a
    /// recap is reachable long after the walk (deep link, notification, a
    /// screen left open). So the CTA reflects the window rather than 403-ing on
    /// tap — and it says what closed rather than just going grey, since this is
    /// the screen's primary action.
    @ViewBuilder
    private func shareButton(_ session: BuddySessionState) -> some View {
        if freshWindow.isOpen {
            shareCTA(session)
        } else {
            Text("Photos share in the 10 minutes after a walk — that window has closed.")
                .font(MADTheme.Typography.caption)
                .foregroundStyle(MADTheme.Colors.madWhite.opacity(0.6))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.vertical, MADTheme.Spacing.md)
        }
    }

    /// Post the walk as one collab crediting everyone who finished it.
    ///
    /// The participants are passed through rather than picked: the whole point
    /// of a buddy recap is that you didn't do it alone, so making the poster
    /// re-select the people they just walked with would be busywork. The
    /// server still validates every id (accepted friend, no block) and quietly
    /// drops any that fail, so a stale roster degrades instead of erroring.
    private func shareCTA(_ session: BuddySessionState) -> some View {
        Button {
            MADHaptics.action()
            showComposer = true
        } label: {
            HStack(spacing: MADTheme.Spacing.sm) {
                Image(systemName: "square.and.arrow.up")
                Text("Share this walk")
            }
            .font(MADTheme.Typography.bodyBold)
            .frame(maxWidth: .infinity)
            .padding(.vertical, MADTheme.Spacing.md)
            .background(Capsule().fill(session.accentColor))
            .foregroundStyle(MADTheme.Colors.madWhite)
        }
        .buttonStyle(.plain)
        .fullScreenCover(isPresented: $showComposer) {
            PostComposerView(
                stats: composerStats(session),
                buddyCoauthorIds: coauthorIds(session),
                buddySessionId: session.id
            ) { _ in
                showComposer = false
            }
        }
    }

    /// Everyone who finished except the poster.
    private func coauthorIds(_ session: BuddySessionState) -> [String] {
        session.participants
            .filter { $0.status == .finished && $0.userId != buddy.currentUserId }
            .map(\.userId)
    }

    /// The poster's OWN numbers — a collab post still shows one person's run,
    /// and using the group total here would credit everyone's miles to whoever
    /// happened to tap share.
    private func composerStats(_ session: BuddySessionState) -> RunStatsInput {
        let me = session.me(buddy.currentUserId)
        let distance = me?.bestDistance ?? 0
        let duration = Double(me?.durationSeconds ?? 0)
        return RunStatsInput(
            distance: distance,
            paceSecondsPerMile: distance > 0 && duration > 0 ? duration / distance : nil,
            durationSeconds: duration > 0 ? duration : nil,
            streak: UserManager.shared.currentUser.streak,
            calories: nil,
            steps: nil,
            // Links the post to the real workout once it has synced. Nil until
            // then, which just means the post isn't tied to a run — better than
            // guessing at an id and colliding with the one-post-per-workout
            // constraint.
            workoutId: me?.workoutId,
            dateText: nil
        )
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

    private func subheadText(_ session: BuddySessionState) -> String {
        switch session.mode {
        case .together:
            return String(format: "%.2f miles between you", session.groupDistanceMiles)
        case .coopGoal:
            return String(
                format: "%.2f of %.1f miles together",
                session.groupDistanceMiles, session.goalValue ?? 0)
        case .raceGoal, .raceTime:
            return session.winnerUserId == nil
                ? "Too close to call"
                : String(format: "%.2f miles covered in total", session.groupDistanceMiles)
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
