import SwiftUI

/// The whole Buddy Walks presentation flow — setup, lobby, recap, and the
/// four events that open them — as ONE node on the dashboard's modifier chain.
///
/// Why a ViewModifier instead of writing these inline: `DashboardView.body`
/// already carries a ~40-modifier chain, and every modifier wraps the body in
/// another generic type the solver has to unify. Adding these seven inline tips
/// it past the limit and the whole body fails with "unable to type-check this
/// expression in reasonable time" — with the error pinned to some innocent
/// `.onReceive` far from the real cause. Collapsing them here makes the chain
/// see a single `.modifier(...)`, and gives the buddy flow one place to live.
///
/// Each presentation still hangs off its OWN invisible node. This chain already
/// carries a `.sheet` (manual entry) and a `.fullScreenCover` (the tracker);
/// stacking more of either on the same node makes SwiftUI silently drop one.
/// Where "open my buddy walk" should actually land.
///
/// The lobby is a PRE-start screen — its job is to hold people until the walk
/// begins — so it has no answer for someone whose walk is already recording.
/// Shown to them anyway it offered two controls and both misled: "Start my
/// walk" only releases the lobby's hand-off gate, and `startBuddyWorkoutIfReady`
/// then declines because `isTracking` is already true, so it read as being sent
/// back a step; and "Cancel walk" asked the server to cancel a session it
/// bounds to `status = 'lobby'` or a countdown that hasn't elapsed, so it came
/// back "already underway" — the app contradicting the screen it had just
/// drawn. Nothing on that screen could reach the walk in progress.
///
/// So the question is asked BEFORE presenting, in one place, because the lobby
/// is opened from several (the pill, a push, an inbox row, a deep link) and a
/// guard added to some of them is a bug that comes back through whichever one
/// was missed.
enum BuddyWalkOpenTarget: Equatable {
    /// No live session to re-enter: build one.
    case setup
    /// A live session and no workout of our own yet — the lobby is correct.
    case lobby
    /// Already walking. Adopt the session into the tracker that is ALREADY
    /// recording and show it; never start a second one.
    case resumeTracking(sessionId: String?)
}

/// `@MainActor` because it reads `BuddySessionService`, whose state is
/// main-actor isolated — the isolation the call sites already had when this
/// decision was written inline in each of them, and which a plain static func
/// silently dropped. Every caller is view code on the main actor, so this only
/// restores what was true before it was extracted.
@MainActor
enum BuddyWalkRouting {
    /// Is a workout of this user's own already recording?
    ///
    /// Read from the persisted state rather than from `showWorkoutView`: the
    /// tracker is a fullScreenCover and is destroyed every time the user peeks
    /// at the dashboard, so "is the cover up" answers a different question and
    /// answers it wrong exactly when someone has stepped out of the tracker to
    /// look at the walk — which is the case this exists for.
    static var isWalking: Bool {
        InProgressWorkoutStore.load()?.isActive == true
    }

    static func openTarget(
        _ service: BuddySessionService = .shared
    ) -> BuddyWalkOpenTarget {
        guard service.canReenterLiveSession else { return .setup }
        guard isWalking else { return .lobby }
        return .resumeTracking(sessionId: service.session?.id)
    }
}

struct BuddyFlowModifier: ViewModifier {
    /// Non-nil = the buddy flow is up, and says which end of it opened.
    ///
    /// ONE piece of state where there were two bools, because there is now one
    /// screen where there were two presentations: setup and the lobby are
    /// stages of `BuddyWalkFlowView`, not a sheet and a cover that had to be
    /// flipped in the right order.
    @Binding var flowEntry: BuddyWalkFlowEntry?
    /// Non-nil turns the ORDINARY tracker into a buddy walk — one flag, same
    /// tracker, which is the entire integration.
    @Binding var activeSessionId: String?
    @Binding var recapSessionId: String?
    @Binding var showWorkoutView: Bool
    @ObservedObject var deepLinkRouter: DeepLinkRouter
    /// Why a tapped buddy link went nowhere. Presented HERE rather than on the
    /// dashboard's own chain for the same reason everything else in this file
    /// is: that chain is already at the type-checker's limit.
    @Binding var linkError: String?
    /// `consumePendingBuddyLink(code:sessionId:)` — the dashboard owns it
    /// because it also clears the router's parked intent.
    let onPendingLink: (String?, String?) -> Void

    /// Present whichever screen the target names. The `resumeTracking` case is
    /// the whole point: it puts the user back in the workout that is already
    /// recording — adopting the session into it on the way, so a walk joined
    /// from a push still gets its crew — instead of covering it with a lobby
    /// that cannot act on it.
    private func open(_ target: BuddyWalkOpenTarget) {
        switch target {
        case .setup:
            flowEntry = .setup
        case .lobby:
            flowEntry = .lobby
        case .resumeTracking(let sessionId):
            if let sessionId { activeSessionId = sessionId }
            flowEntry = nil
            showWorkoutView = true
        }
    }

    func body(content: Content) -> some View {
        content
            // ONE presentation for the whole flow. From here there is no
            // wizard for it to be a step OF — the dashboard is not the Start
            // Mile cover — so it arrives in the same full-screen container the
            // tracker itself does, and looks identical either way.
            //
            // `item:` rather than `isPresented:` plus a separate @State for
            // which end to open: that pair races to a stale value (ios.md).
            .background(
                Color.clear
                    .fullScreenCover(item: $flowEntry) { entry in
                        BuddyWalkFlowView(
                            entry: entry,
                            onExit: { flowEntry = nil },
                            onStart: { session in
                                activeSessionId = session.id
                                flowEntry = nil
                                showWorkoutView = true
                            }
                        )
                    }
            )
            .background(
                Color.clear
                    .sheet(
                        isPresented: Binding(
                            get: { recapSessionId != nil },
                            set: { if !$0 { recapSessionId = nil } }
                        )
                    ) {
                        if let id = recapSessionId {
                            BuddyRecapView(sessionId: id)
                        }
                    }
            )
            .alert(
                "Buddy Walk",
                isPresented: Binding(
                    get: { linkError != nil },
                    set: { if !$0 { linkError = nil } }
                )
            ) {
                Button("OK", role: .cancel) { linkError = nil }
            } message: {
                Text(linkError ?? "")
            }
            .onReceive(NotificationCenter.default.publisher(for: .madOpenBuddyLobby)) { _ in
                self.open(BuddyWalkRouting.openTarget())
            }
            .onReceive(NotificationCenter.default.publisher(for: .madStartBuddyWalk)) { _ in
                // An invite already waiting goes straight to the lobby; there is
                // nothing left to configure. Re-enterable only — a session THIS
                // user already finished stays `active` while friends walk on,
                // and the lobby hands a long-started session straight into
                // tracking, which is how a finished walk restarted itself.
                let present: () -> Void = {
                    self.open(BuddyWalkRouting.openTarget())
                }
                // Setting up a NEW walk closes the last one's recap first. The
                // request reaches here from inside that recap ("walks together"
                // → "walk again"), and a dismissal plus a presentation in one
                // transaction race — SwiftUI drops one, which showed up as the
                // button doing nothing at all.
                guard recapSessionId != nil else { return present() }
                recapSessionId = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: present)
            }
            // A buddy deep link or push can land before the dashboard exists
            // (cold launch), so the intent is parked on DeepLinkRouter and
            // consumed BOTH here and in the dashboard's `.task` — whichever
            // runs first wins.
            .onReceive(deepLinkRouter.$pendingBuddyCode.compactMap { $0 }) { code in
                onPendingLink(code, nil)
            }
            .onReceive(deepLinkRouter.$pendingBuddySessionId.compactMap { $0 }) { sessionId in
                onPendingLink(nil, sessionId)
            }
            .task {
                // Enrollment stamp: tells the backend this install has the Buddy
                // Walks UI, which is what makes the user eligible to be invited
                // at all. Idempotent, so it's safe on every appearance.
                await BuddySessionService.shared.enrollIfNeeded()

                // Everything after enrollment is INDEPENDENT, so it runs
                // concurrently rather than in a chain. Serially this was four
                // round trips deep before the dashboard settled, and the
                // candidate list — the one the start sheet blocks on — was
                // last in the queue.
                //
                // Warming the candidates HERE is the point: the sheet used to
                // fetch them in its own `.task`, so opening it showed an empty
                // "Who's coming?" for a round trip every single time. Prefetched,
                // it opens populated, which is most of what made setup feel slow.
                async let sessions: Void = BuddySessionService.shared.refreshMySessions()
                async let candidates: Void = BuddySessionService.shared.loadCandidates()
                async let routines: Void = BuddySessionService.shared.loadRoutines()
                // Who's out RIGHT NOW. Added because the dashboard pill now
                // offers "a friend is out — join", and without this it only
                // ever had data after a trip to the Friends tab — i.e. the
                // offer appeared for people who had already found the feature
                // elsewhere, which is the opposite of who it's for.
                async let out: Void = BuddySessionService.shared.refreshFriendsOutNow()
                _ = await (sessions, candidates, routines, out)

                // The `.onReceive` pair above only fires for values published
                // AFTER this mounts. On a cold launch the link is already
                // parked, so it has to be drained here too.
                if let code = deepLinkRouter.pendingBuddyCode {
                    onPendingLink(code, nil)
                } else if let sessionId = deepLinkRouter.pendingBuddySessionId {
                    onPendingLink(nil, sessionId)
                }
            }
    }
}
