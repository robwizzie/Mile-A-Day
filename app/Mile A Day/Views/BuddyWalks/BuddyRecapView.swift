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

    @State private var recap: BuddyRecapResponse?
    @State private var isLoading = true

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
