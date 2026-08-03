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
                // nothing left to configure.
                if BuddySessionService.shared.hasLiveSession {
                    showLobby = true
                } else {
                    showStartSheet = true
                }
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
                await BuddySessionService.shared.refreshMySessions()
                // "Alex is walking right now" — pulled, never pushed, so this
                // is the only thing that surfaces the offer.
                await BuddySessionService.shared.refreshJoinableFriendSessions()

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
