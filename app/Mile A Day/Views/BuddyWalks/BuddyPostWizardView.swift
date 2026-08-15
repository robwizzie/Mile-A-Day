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
    /// Fired once the post is live, so the recap can re-read and swap its CTA
    /// for the confirmation + "See the post" link. Without it the screen the
    /// user lands back on looks exactly as it did before they posted, which is
    /// most of why the flow read as "did that work?".
    var onPosted: () -> Void = {}

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
                        combinedRouteCard
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
                        //
                        // Deferred a beat, NOT called inline: closing the
                        // composer and dismissing the wizard that presents it
                        // are two presentation changes in one transaction, and
                        // SwiftUI drops one of those (the same race the
                        // history screen's `startWalk` and the composer's
                        // stacked covers document). The one it dropped was
                        // this dismiss — so a published post left the crew
                        // screen sitting there afterwards, which reads as the
                        // wizard asking to be filled in a second time.
                        guard case .published = outcome else { return }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            // Tell the recap BEFORE dismissing: it re-reads and
                            // has its confirmation ready by the time it's the
                            // screen on top.
                            onPosted()
                            dismiss()
                        }
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
            Text(
                "Everyone below is credited on one card — your routes drawn "
                    + "together, and each of them can add their own photo to it."
            )
            .font(MADTheme.Typography.subheadline)
            .foregroundStyle(MADTheme.Colors.madWhite.opacity(0.65))
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The routes, on ONE map, coloured and keyed exactly as the published
    /// card will draw them.
    ///
    /// This screen used to stack a separate 150pt map per person and then
    /// publish a post carrying only the poster's — so the wizard's own preview
    /// was the clearest possible statement of a promise the post didn't keep.
    /// Showing the real thing here is half the fix; the other half is that the
    /// post now actually renders it.
    @ViewBuilder
    private var combinedRouteCard: some View {
        let drawn = drawnRoutes
        if !drawn.isEmpty {
            VStack(alignment: .leading, spacing: MADTheme.Spacing.sm) {
                WorkoutRouteMapView(
                    coordinates: drawn.first?.coordinates ?? [],
                    routeColor: drawn.first?.color ?? session.accentColor,
                    companionRoutes: Array(drawn.dropFirst())
                )
                .frame(height: 220)
                .clipShape(RoundedRectangle(
                    cornerRadius: MADTheme.CornerRadius.medium, style: .continuous))
                .overlay(
                    RoundedRectangle(
                        cornerRadius: MADTheme.CornerRadius.medium, style: .continuous)
                        .strokeBorder(MADTheme.Colors.madWhite.opacity(0.1), lineWidth: 1)
                )

                FlowLayout(spacing: 10) {
                    ForEach(drawn) { route in
                        HStack(spacing: 5) {
                            Capsule().fill(route.color).frame(width: 14, height: 4)
                            Text(routeNames[route.id] ?? "a friend")
                                .font(MADTheme.Typography.caption)
                                .foregroundStyle(MADTheme.Colors.madWhite.opacity(0.75))
                                .lineLimit(1)
                        }
                    }
                }

                if drawn.count < crew.count {
                    // Said once, for the group, without naming anyone: an
                    // indoor walk and a privacy choice must read the same.
                    Text("Routes appear for everyone who has one to share.")
                        .font(MADTheme.Typography.caption)
                        .foregroundStyle(MADTheme.Colors.madWhite.opacity(0.45))
                }
            }
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

                // Everyone on this list is credited, including someone still
                // walking — the glyph says which of those two they are without
                // implying the still-out one is any less on the post.
                Image(
                    systemName: participant.status == .active
                        ? "figure.walk.motion" : "checkmark.circle.fill"
                )
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(session.accentColor.opacity(0.9))
                .accessibilityLabel(
                    participant.status == .active
                        ? "Still out — included on the post"
                        : "Included on the post"
                )
            }

            // The per-person 150pt map that used to live here is gone: the
            // card above draws every route on ONE map, which is what the post
            // does. A stack of separate maps described a post that has never
            // existed. What's left per row is the state of THEIR route, in a
            // line — still honest about what's missing, without repeating the
            // picture.
            routeFootnoteRow(for: participant)
        }
        .padding(MADTheme.Spacing.md)
        .madLiquidGlass(cornerRadius: MADTheme.CornerRadius.large)
    }

    /// One line about this person's trace: the colour it's drawn in, or why
    /// there isn't one.
    @ViewBuilder
    private func routeFootnoteRow(for participant: BuddyParticipant) -> some View {
        switch routes[participant.userId] ?? .pending {
        case .loaded:
            if let color = drawnRoutes.first(where: { $0.id == participant.userId })?.color {
                HStack(spacing: 6) {
                    Capsule().fill(color).frame(width: 14, height: 4)
                    Text("Route on the map")
                        .font(MADTheme.Typography.caption)
                        .foregroundStyle(MADTheme.Colors.madWhite.opacity(0.55))
                }
                .padding(.vertical, MADTheme.Spacing.xs)
            }
        case .loading:
            routeFootnote(icon: "arrow.triangle.2.circlepath", text: "Loading their route…")
        case .pending:
            routeFootnote(
                icon: "arrow.triangle.2.circlepath",
                text: "Route appears once their workout finishes syncing."
            )
        case .unavailable:
            // Indoor walk, or maps not shared — one quiet message for both,
            // so the row never outs a privacy setting.
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

    /// Every crew route that actually loaded, poster FIRST.
    ///
    /// Order and colour mirror the published card exactly: the author's line
    /// takes the activity accent, everyone else takes `CrewRoutePalette` in
    /// the order the server credits them — which is `coauthorIds()`, which is
    /// `crew` minus the poster. Deriving it any other way here would let the
    /// preview and the post disagree about whose line is whose, which is worse
    /// than showing no key at all.
    private var drawnRoutes: [CompanionRoute] {
        var out: [CompanionRoute] = []
        if let mine = buddy.currentUserId,
           case .loaded(let coords)? = routes[mine] {
            out.append(CompanionRoute(
                id: mine, coordinates: coords, color: session.accentColor))
        }
        for (index, participant) in crewExcludingMe.enumerated() {
            guard case .loaded(let coords)? = routes[participant.userId] else { continue }
            out.append(CompanionRoute(
                id: participant.userId,
                coordinates: coords,
                color: CrewRoutePalette.color(at: index)
            ))
        }
        return out
    }

    /// user id → the name to print beside their line.
    private var routeNames: [String: String] {
        var out: [String: String] = [:]
        for participant in crew {
            out[participant.userId] =
                participant.userId == buddy.currentUserId ? "You" : participant.displayName
        }
        return out
    }

    /// The crew in the exact order `coauthorIds()` sends them, which is the
    /// order the server writes `post_coauthors` rows and therefore the order
    /// the card assigns colours in.
    private var crewExcludingMe: [BuddyParticipant] {
        crew.filter { $0.userId != buddy.currentUserId }
    }

    /// Everyone credited on the post, best distance first — the same people
    /// `coauthorIds()` sends (plus the poster), so what the wizard shows is
    /// exactly what the server is asked to write.
    ///
    /// EVERYONE WHO WAS ON THE WALK, not only those who have already tapped
    /// Finish. This used to require `.finished`, and the recap opens the moment
    /// THIS user's own workout ends — so on any walk where a friend was still
    /// out (which is most of them, since two people rarely stop on the same
    /// second) the crew was just the poster, `coauthorIds()` came back empty,
    /// and the "one post, everyone on it" screen produced a solo post. Waiting
    /// for stragglers is the wrong trade in the other direction too: coauthors
    /// are settled at create time, so a slower friend would simply never be
    /// credited. `.active` and `.finished` is the same membership every other
    /// surface uses — the roster, the pooled total, the standings.
    private var crew: [BuddyParticipant] {
        session.activeParticipants
            .sorted { $0.bestDistance > $1.bestDistance }
    }

    /// Participants still actively moving when this recap snapshot was taken.
    /// They ARE on the post — this note is about their numbers, not their
    /// credit.
    private var stillOut: [BuddyParticipant] {
        session.participants.filter { $0.status == .active }
    }

    private var stillOutText: String {
        let names = stillOut.map(\.displayName)
        let list = names.count <= 2
            ? names.joined(separator: " and ")
            : "\(names.count) buddies"
        let verb = names.count == 1 ? "is" : "are"
        return "\(list) \(verb) still out — still on the post, but the distance "
            + "shown is where they'd got to when you finished."
    }

    // MARK: - Composer hand-off

    /// Everyone who finished except the poster. Mirrors what the crew list
    /// shows; the server validates every id and drops any that fail.
    private func coauthorIds() -> [String] {
        crewExcludingMe.map(\.userId)
    }

    /// Display names for `coauthorIds()`, same order — the share step's crew
    /// row says who's riding along without re-fetching anything.
    private func coauthorNames() -> [String] {
        crewExcludingMe.map(\.displayName)
    }

    /// The workout this buddy walk was, for THIS user.
    ///
    /// Resolved locally when the server hasn't reconciled yet, which — because
    /// the recap opens seconds after the walk and reconciliation trails the
    /// HealthKit sync by a minute or two — was essentially always. See
    /// `RunPostService.buddyWorkoutId` for why an unlinked post is the thing
    /// that broke "one post per walk".
    private var myWorkoutId: String? {
        RunPostService.buddyWorkoutId(
            reconciled: session.me(buddy.currentUserId)?.workoutId,
            startedAt: session.startedAtDate,
            endedAt: session.endedAtDate
        )
    }

    /// The poster's OWN numbers — a collab post still shows one person's run,
    /// and using the group total here would credit everyone's miles to whoever
    /// happened to post.
    ///
    /// Built by `RunPostService.todayStats`, the SAME helper the solo photo
    /// prompt and the feed composer use, rather than from the buddy session's
    /// live figures. Two reasons, both bugs this used to have: the server
    /// restates a daily-mile anchor's card with the day's rollup, so a
    /// hand-built single-leg number reads as one figure in the composer and a
    /// different one in the feed (and can trip `auto_post_stats_mismatch`); and
    /// `currentUser.streak` must never be baked into a post — it is
    /// quarantine-gated and deliberately lags a real break, so a post made
    /// after a missed day claimed a streak its author no longer had (ios.md).
    ///
    /// Falls back to the session's own numbers only when no local workout can
    /// be matched at all, so the post still says something true.
    private func composerStats() -> RunStatsInput {
        if let workoutId = myWorkoutId {
            return RunPostService.todayStats(workoutId: workoutId)
        }

        let me = session.me(buddy.currentUserId)
        let distance = me?.bestDistance ?? 0
        let duration = Double(me?.durationSeconds ?? 0)
        return RunStatsInput(
            distance: distance,
            paceSecondsPerMile: distance > 0 && duration > 0 ? duration / distance : nil,
            durationSeconds: duration > 0 ? duration : nil,
            streak: UserManager.shared.freshBackendStreak
                ?? UserManager.shared.currentUser.streak,
            calories: nil,
            steps: nil,
            workoutId: nil,
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
        await loadMyRoute()
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

    /// The POSTER's own trace, read from HealthKit rather than fetched back
    /// from the server.
    ///
    /// The server route only exists once this walk has synced AND been given a
    /// `workout_routes` row, which is a minute or two out — so on the screen
    /// that opens seconds after finishing, asking the API for your own map
    /// reliably answered "nothing", and the preview showed everyone's line but
    /// yours. The device has the samples already.
    @MainActor
    private func loadMyRoute() async {
        guard let me = buddy.currentUserId, routes[me] == nil else { return }
        guard let workoutId = myWorkoutId,
              let workout = HealthKitManager.shared.todaysWorkouts
                  .first(where: { $0.uuid.uuidString == workoutId })
        else { return }  // Leave it unset so the server pass below can try.
        routes[me] = .loading
        let coords = await HealthKitManager.shared
            .fetchAllRouteLocations(for: workout)
            .map(\.coordinate)
        routes[me] = coords.count >= 2 ? .loaded(coords) : .unavailable
    }
}
