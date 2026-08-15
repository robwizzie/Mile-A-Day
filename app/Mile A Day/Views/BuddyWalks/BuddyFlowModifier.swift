import SwiftUI

/// The whole Buddy Walks presentation flow — start sheet, lobby, recap, and the
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
struct BuddyFlowModifier: ViewModifier {
    @Binding var showStartSheet: Bool
    @Binding var showLobby: Bool
    /// Non-nil turns the ORDINARY tracker into a buddy walk — one flag, same
    /// tracker, which is the entire integration.
    @Binding var activeSessionId: String?
    @Binding var recapSessionId: String?
    @Binding var showWorkoutView: Bool
    @ObservedObject var deepLinkRouter: DeepLinkRouter
    /// `consumePendingBuddyLink(code:sessionId:)` — the dashboard owns it
    /// because it also clears the router's parked intent.
    let onPendingLink: (String?, String?) -> Void

    func body(content: Content) -> some View {
        content
            .background(
                Color.clear
                    .sheet(isPresented: $showStartSheet) {
                        BuddyStartSheet { _ in
                            showStartSheet = false
                            showLobby = true
                        }
                    }
            )
            .background(
                Color.clear
                    .fullScreenCover(isPresented: $showLobby) {
                        BuddyLobbyView { session in
                            activeSessionId = session.id
                            showLobby = false
                            showWorkoutView = true
                        }
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
            .onReceive(NotificationCenter.default.publisher(for: .madOpenBuddyLobby)) { _ in
                showLobby = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .madStartBuddyWalk)) { _ in
                // An invite already waiting goes straight to the lobby; there is
                // nothing left to configure. Re-enterable only — a session THIS
                // user already finished stays `active` while friends walk on,
                // and the lobby hands a long-started session straight into
                // tracking, which is how a finished walk restarted itself.
                let open: () -> Void = {
                    if BuddySessionService.shared.canReenterLiveSession {
                        showLobby = true
                    } else {
                        showStartSheet = true
                    }
                }
                // Setting up a NEW walk closes the last one's recap first. The
                // request reaches here from inside that recap ("walks together"
                // → "walk again"), and a dismissal plus a presentation in one
                // transaction race — SwiftUI drops one, which showed up as the
                // button doing nothing at all.
                guard recapSessionId != nil else { return open() }
                recapSessionId = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: open)
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
