import SwiftUI
import CoreLocation

/// Posting a buddy walk — the SAME photo prompt as the solo finale
/// (`PhotoPromptView`), in crew mode.
///
/// This used to be its own crew-and-routes screen ("Step 1 of 3 · the
/// crew") with a look nothing like the solo prompt, so a buddy walk never got
/// the redesign. Now the prompt's preview card IS the crew card — everyone's
/// routes on one map, coloured and keyed exactly as the published card draws
/// them — the line under it says who's credited, and Take a photo / Choose
/// from this walk open the composer with the crew attached. "Not now" goes
/// back to the recap, whose Done is the walk's real skip.
///
/// Routes come from the SERVER for every row except the poster's own (read
/// from HealthKit, since the server's copy lands a minute or two after the
/// walk) — the friend/consent/block gating stays server truth
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

    var body: some View {
        PhotoPromptView(
            workoutId: myWorkoutId,
            workoutType: session.isRunning ? "running" : "walking",
            stats: composerStats(),
            crew: PhotoPromptView.Crew(
                sessionId: session.id,
                coauthorIds: coauthorIds(),
                coauthorNames: coauthorNames(),
                walkCard: combinedRouteCard,
                note: crewNote
            ),
            skipTitle: "Not now",
            // The recap already checked the day's posting window before
            // offering this step.
            resolvesWithoutPostingWindow: false,
            onFinish: { outcome in
                switch outcome {
                case .skipped:
                    dismiss()
                case .published:
                    // The walk's snaps were offered here; once one is on the
                    // walk's post they're spent, as on the solo prompt.
                    MidRunPhotoStash.clear()
                    // Deferred a beat, NOT inline: the composer closing and
                    // this screen dismissing are two presentation changes in
                    // one transaction, and SwiftUI drops one of them — the
                    // one it dropped was this dismiss, which left the screen
                    // sitting there after a published post.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        // Tell the recap BEFORE dismissing: it re-reads and
                        // has its confirmation ready by the time it's on top.
                        onPosted()
                        dismiss()
                    }
                }
            }
        )
        .task { await loadRoutes() }
    }

    // MARK: - Preview card

    /// Everyone's routes on ONE card, coloured and keyed exactly as the
    /// published card will draw them. nil until at least one line has
    /// loaded — the prompt shows the stats card meanwhile.
    private var combinedRouteCard: AnyView? {
        let drawn = drawnRoutes
        guard let first = drawn.first else { return nil }
        let avatars = crewRouteAvatars
        return AnyView(
            RouteArtView(
                coordinates: first.coordinates,
                routeColor: first.color,
                companionRoutes: Array(drawn.dropFirst()),
                authorAvatar: avatars[first.id],
                companionAvatars: avatars,
                showsMileMarkers: false
            )
        )
    }

    /// Who's credited on the post, and anyone still out — the crew list this
    /// screen used to draw as cards, said in one line under the preview.
    private var crewNote: String? {
        let others = crewExcludingMe.map(\.displayName)
        guard !others.isEmpty else { return nil }
        let names: String
        switch others.count {
        case 1: names = others[0]
        case 2: names = "\(others[0]) and \(others[1])"
        default: names = "\(others[0]), \(others[1]) and \(others.count - 2) more"
        }
        var line = "With \(names) — everyone's on this one post."
        if !stillOut.isEmpty { line += " \(stillOutText)" }
        return line
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
        // Assigned across the whole crew, then filtered by what loaded — the
        // published card does the same, and colouring the FILTERED list here
        // would hand the preview a different key from the post whenever one
        // person's route hadn't arrived yet.
        let palette = CrewRoutePalette.companionColors(
            count: crewExcludingMe.count,
            avoiding: session.accentColor
        )
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
                color: palette[index]
            ))
        }
        return out
    }

    /// user id → the badge riding their line on the combined art card.
    private var crewRouteAvatars: [String: RouteArtAvatar] {
        var out: [String: RouteArtAvatar] = [:]
        for participant in crew {
            out[participant.userId] = RouteArtAvatar(
                name: participant.displayName,
                imageURL: participant.profileImageUrl
            )
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
        return "\(list) \(verb) still out, so their distance is where they'd got to."
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
        // Stealth Mode: the poster's own line stays on their phone, and the
        // server pass would find nothing for it either.
        if StealthModeStore.shared.isStealth(workout) {
            routes[me] = .unavailable
            return
        }
        routes[me] = .loading
        let coords = await HealthKitManager.shared
            .fetchAllRouteLocations(for: workout)
            .map(\.coordinate)
        routes[me] = coords.count >= 2 ? .loaded(coords) : .unavailable
    }
}
