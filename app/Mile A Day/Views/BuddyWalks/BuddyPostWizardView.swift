import SwiftUI
import CoreLocation

/// Step 1 of posting a buddy walk — the crew and their routes.
///
/// The recap used to jump straight into the composer from a bare share
/// button, which meant WHO was being credited was invisible until the post
/// existed. This makes the flow an explicit wizard: settle WHO here (everyone
/// who finished, shown by name — the server still re-validates each id), see
/// WHERE each of them went (their route, once their workout has synced and
/// their "Share route maps" consent allows the server to hand it over), then
/// move on to the photo and share steps the composer already owns.
///
/// Routes come from the SERVER for every row, the poster's own included —
/// one code path, and the friend/consent/block gating stays server truth
/// (`GET /workouts/:userId/workout/:id/route` answers `route: null` rather
/// than erroring when the owner doesn't share).
struct BuddyPostWizardView: View {
    let session: BuddySessionState

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var buddy = BuddySessionService.shared
    @StateObject private var friendService = FriendService()

    /// Per-participant route state, keyed by user id.
    private enum RouteState {
        /// Their workout hasn't reached the backend yet (`workoutId` nil).
        case pending
        case loading
        case loaded([CLLocationCoordinate2D])
        /// Synced, but the server handed back nothing — an indoor walk with
        /// no GPS, or route maps not shared. Deliberately one quiet state:
        /// the wizard must not out a friend's privacy choice.
        case unavailable
    }

    @State private var routes: [String: RouteState] = [:]
    @State private var showComposer = false

    var body: some View {
        NavigationStack {
            ZStack {
                MADTheme.Colors.appBackgroundGradient.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: MADTheme.Spacing.lg) {
                        header
                        crewSection
                        if !stillOut.isEmpty { stillOutNote }
                        continueButton
                        Color.clear.frame(height: MADTheme.Spacing.lg)
                    }
                    .padding(MADTheme.Spacing.md)
                }
                // The composer is a cover on the ScrollView node — the
                // NavigationStack stays free in case this wizard ever needs
                // a gate of its own (two covers on one node drop one).
                .fullScreenCover(isPresented: $showComposer) {
                    PostComposerView(
                        stats: composerStats(),
                        buddyCoauthorIds: coauthorIds(),
                        buddySessionId: session.id,
                        buddyCrewNames: coauthorNames()
                    ) { outcome in
                        showComposer = false
                        // Published → the wizard's job is done; fall back to
                        // the recap. Cancelled → stay here, nothing is lost.
                        if case .published = outcome { dismiss() }
                    }
                }
            }
            .navigationTitle(session.isRunning ? "Post Your Run" : "Post Your Walk")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(MADTheme.Colors.madWhite.opacity(0.7))
                }
            }
        }
        .task { await loadRoutes() }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("STEP 1 OF 3 · THE CREW")
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .tracking(1.2)
                .foregroundStyle(session.accentColor)
            Text("One post, everyone on it")
                .font(MADTheme.Typography.title2)
                .foregroundStyle(MADTheme.Colors.madWhite)
            Text("Everyone below is credited on the post — friends see all of you on one card, with each route your buddies chose to share.")
                .font(MADTheme.Typography.subheadline)
                .foregroundStyle(MADTheme.Colors.madWhite.opacity(0.65))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var crewSection: some View {
        VStack(spacing: MADTheme.Spacing.md) {
            ForEach(crew) { participant in
                crewCard(participant)
            }
        }
    }

    /// One participant: who they are, what they covered, where they went.
    private func crewCard(_ participant: BuddyParticipant) -> some View {
        let isYou = participant.userId == buddy.currentUserId

        return VStack(alignment: .leading, spacing: MADTheme.Spacing.sm) {
            HStack(spacing: MADTheme.Spacing.md) {
                AvatarView(
                    name: participant.displayName,
                    imageURL: participant.profileImageUrl,
                    size: 44
                )
                .overlay(
                    Circle().strokeBorder(
                        isYou ? session.accentColor : .clear, lineWidth: 2)
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(isYou ? "You" : participant.displayName)
                        .font(MADTheme.Typography.bodyBold)
                        .foregroundStyle(MADTheme.Colors.madWhite)
                        .lineLimit(1)
                    Text("\(participant.bestDistance.milesText) mi")
                        .font(MADTheme.Typography.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(session.accentColor)
                }

                Spacer(minLength: MADTheme.Spacing.sm)

                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(session.accentColor.opacity(0.9))
                    .accessibilityLabel("Included on the post")
            }

            routeView(for: participant)
        }
        .padding(MADTheme.Spacing.md)
        .madLiquidGlass(cornerRadius: MADTheme.CornerRadius.large)
    }

    @ViewBuilder
    private func routeView(for participant: BuddyParticipant) -> some View {
        switch routes[participant.userId] ?? .pending {
        case .loaded(let coordinates):
            WorkoutRouteMapView(
                coordinates: coordinates,
                routeColor: session.accentColor
            )
            .frame(height: 150)
            .clipShape(RoundedRectangle(
                cornerRadius: MADTheme.CornerRadius.medium, style: .continuous))
            .overlay(
                RoundedRectangle(
                    cornerRadius: MADTheme.CornerRadius.medium, style: .continuous)
                    .strokeBorder(MADTheme.Colors.madWhite.opacity(0.1), lineWidth: 1)
            )
        case .loading:
            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium, style: .continuous)
                .fill(MADTheme.Colors.madWhite.opacity(0.06))
                .frame(height: 150)
                .overlay(ProgressView().tint(MADTheme.Colors.madWhite.opacity(0.4)))
        case .pending:
            routeFootnote(
                icon: "arrow.triangle.2.circlepath",
                text: "Route appears once their workout finishes syncing."
            )
        case .unavailable:
            // Indoor walk, or maps not shared — one quiet message for both,
            // so the card never outs a privacy setting.
            routeFootnote(icon: "map", text: "No route map for this one.")
        }
    }

    private func routeFootnote(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
            Text(text)
                .font(MADTheme.Typography.caption)
        }
        .foregroundStyle(MADTheme.Colors.madWhite.opacity(0.45))
        .padding(.vertical, MADTheme.Spacing.xs)
    }

    /// Buddies still mid-walk can't be credited yet — a post made now simply
    /// won't carry them (coauthors are settled at create time, server-side).
    /// Say so instead of silently dropping them from the crew list.
    private var stillOutNote: some View {
        HStack(spacing: MADTheme.Spacing.sm) {
            Image(systemName: "figure.walk.motion")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(MADTheme.Colors.madWhite.opacity(0.5))
            Text(stillOutText)
                .font(MADTheme.Typography.caption)
                .foregroundStyle(MADTheme.Colors.madWhite.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(MADTheme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium, style: .continuous)
                .fill(MADTheme.Colors.madWhite.opacity(0.05))
        )
    }

    private var continueButton: some View {
        VStack(spacing: 6) {
            Button {
                MADHaptics.action()
                showComposer = true
            } label: {
                HStack(spacing: MADTheme.Spacing.sm) {
                    Image(systemName: "camera.fill")
                    Text("Continue — add your photo")
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .bold))
                }
                .font(MADTheme.Typography.bodyBold)
                .frame(maxWidth: .infinity)
                .padding(.vertical, MADTheme.Spacing.md)
                .background(Capsule().fill(session.accentColor))
                .foregroundStyle(MADTheme.Colors.madWhite)
            }
            .buttonStyle(.plain)

            Text("Step 2 · photo — Step 3 · caption & share")
                .font(MADTheme.Typography.caption)
                .foregroundStyle(MADTheme.Colors.madWhite.opacity(0.45))
        }
        .padding(.top, MADTheme.Spacing.sm)
    }

    // MARK: - Crew

    /// Everyone credited on the post, best distance first — the same people
    /// `coauthorIds()` sends (plus the poster), so what the wizard shows is
    /// exactly what the server is asked to write.
    private var crew: [BuddyParticipant] {
        session.participants
            .filter { $0.status == .finished }
            .sorted { $0.bestDistance > $1.bestDistance }
    }

    /// Participants still actively moving when this recap snapshot was taken.
    private var stillOut: [BuddyParticipant] {
        session.participants.filter { $0.status == .active }
    }

    private var stillOutText: String {
        let names = stillOut.map(\.displayName)
        let list = names.count <= 2
            ? names.joined(separator: " and ")
            : "\(names.count) buddies"
        let verb = names.count == 1 ? "is" : "are"
        return "\(list) \(verb) still out — a post made now won't include them."
    }

    // MARK: - Composer hand-off

    /// Everyone who finished except the poster. Mirrors what the crew list
    /// shows; the server validates every id and drops any that fail.
    private func coauthorIds() -> [String] {
        crew.filter { $0.userId != buddy.currentUserId }.map(\.userId)
    }

    /// Display names for `coauthorIds()`, same order — the share step's crew
    /// row says who's riding along without re-fetching anything.
    private func coauthorNames() -> [String] {
        crew.filter { $0.userId != buddy.currentUserId }.map(\.displayName)
    }

    /// The poster's OWN numbers — a collab post still shows one person's run,
    /// and using the group total here would credit everyone's miles to
    /// whoever happened to post.
    private func composerStats() -> RunStatsInput {
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
            // then, which just means the post isn't tied to a run — better
            // than guessing at an id and colliding with the
            // one-post-per-workout constraint.
            workoutId: me?.workoutId,
            dateText: nil
        )
    }

    // MARK: - Routes

    /// Fetch each finished participant's trace — sequentially, on purpose:
    /// crews are 2–5 people, every await hops back to the main actor anyway,
    /// and per-row `.loading` state keeps the screen honest while it fills.
    /// Explicitly @MainActor: it mutates `routes` (@State) and calls the
    /// @MainActor FriendService.
    @MainActor
    private func loadRoutes() async {
        for participant in crew {
            guard routes[participant.userId] == nil else { continue }
            guard let workoutId = participant.workoutId else {
                routes[participant.userId] = .pending
                continue
            }
            routes[participant.userId] = .loading
            let raw = try? await friendService.fetchWorkoutRoute(
                for: participant.userId, workoutId: workoutId)
            routes[participant.userId] =
                decodeRouteCoordinates(raw).map(RouteState.loaded) ?? .unavailable
        }
    }
}
