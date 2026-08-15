import SwiftUI

/// The buddy option's copy for the Start Mile wizard.
///
/// Buddy Walks used to be reachable only from a pill under the dashboard's
/// start button, which had two problems: it was absent from the Fun dashboard
/// entirely (the pill's own comment claimed otherwise), and it sat *beside* the
/// core action rather than inside it — so the moment someone tapped Start Mile,
/// walking with a friend stopped being an option they could see. Starting one
/// is now the third card on the wizard's first step, next to Run and Walk, and
/// the whole flow — setup, lobby, countdown, tracking — plays out inside the
/// Start Mile cover (see `BuddyWizardFlowModifier` below).
///
/// The copy lives here rather than in `WorkoutTrackingView` for the reason
/// `BuddyFlowModifier` gives: that view's body is already near the type
/// checker's limit, and every inline closure and conditional it grows makes the
/// whole file fail to compile with an error pinned somewhere innocent.
///
/// Deliberately says nothing about who is out walking right now. That belongs
/// on the Friends tab, where presence is the subject rather than a decoration —
/// this card only has to answer "can I do this mile with someone."
enum BuddyStartPrompt {
    /// What the card says underneath "With a Buddy".
    ///
    /// An invite outranks the pitch: it's a room already waiting on an answer,
    /// which is a different and much more urgent thing than the feature
    /// existing. Naming the person is the point — "1 invite" is a count,
    /// "Alex invited you" is someone waiting.
    static func subtitle(invites: [BuddySessionState]) -> String {
        guard let first = invites.first else {
            return "Walk or run together, wherever you both are"
        }
        if invites.count == 1 {
            return "\(inviterName(first)) invited you — jump in"
        }
        return "\(invites.count) buddy invites waiting"
    }

    /// The pill beside the title. Invites outrank the first-run flag: someone
    /// waiting on you is more urgent than a feature being new.
    static func badge(invites: [BuddySessionState], hasStartedOnce: Bool) -> String? {
        if !invites.isEmpty {
            return invites.count == 1 ? "1 INVITE" : "\(invites.count) INVITES"
        }
        return hasStartedOnce ? nil : "NEW"
    }

    /// Whoever sent the invite. The participant list flags its own host, so
    /// this reads `isHost` rather than matching against the session's optional
    /// `hostUserId` — which is nil on older payloads and would silently make
    /// every invite read "A friend".
    private static func inviterName(_ session: BuddySessionState) -> String {
        if let host = session.participants.first(where: { $0.isHost }) {
            return host.displayName
        }
        return "A friend"
    }
}

/// Presents the buddy start sheet and lobby from INSIDE the Start Mile cover.
///
/// The dashboard hangs this same pair off its own chain (`BuddyFlowModifier`)
/// for the entry points that don't go through the wizard — the invite pill,
/// pushes, deep links. The wizard's buddy card used to route through that
/// chain by dismissing the whole tracker first, which is what made the flow
/// feel like leaving: Start Mile slid away, the dashboard flashed, and the
/// setup sheet rose out of nowhere 350ms later. Presented from nodes inside
/// the cover instead, the wizard stays underneath the whole time — Cancel and
/// Leave land back on the step you left, and the lobby's shared countdown
/// hands the session to the tracker that is ALREADY hosting it, with no
/// dismiss-and-re-present in between.
///
/// Same screens, second presentation site: both paths drive the
/// `BuddySessionService` singleton, so there is nothing to keep in sync. Each
/// presentation sits on its own invisible node — the tracker's content
/// already carries sheets of its own, and stacking two on one node makes
/// SwiftUI silently drop one.
struct BuddyWizardFlowModifier: ViewModifier {
    @Binding var showStartSheet: Bool
    @Binding var showLobby: Bool
    /// The lobby's countdown just hit zero for this session — start moving.
    let onStarted: (BuddySessionState) -> Void
    /// Nil once the workout has adopted a buddy session; while it's nil there
    /// is an offer to keep fresh.
    var activeSessionId: String? = nil

    func body(content: Content) -> some View {
        content
            // Keeps `BuddyMidWalkJoinStrip`'s offer live while a workout is
            // running and NOT in a buddy session.
            //
            // Hosted on this modifier rather than on the tracker's own chain
            // for the reason this modifier exists at all: WorkoutTrackingView's
            // body already carries a ~40-modifier chain, and each one wraps the
            // body in another generic the solver has to unify — one more tips
            // it into "unable to type-check this expression in reasonable
            // time", pinned to some innocent line far from the cause.
            //
            // And NOT on the strip itself: that view renders nothing when
            // there's nobody to join, and a view with an empty body gets no
            // lifecycle at all (ios.md), so a `.task` there would only ever run
            // once the offer it was meant to discover had already appeared.
            //
            // A view-level loop is right for this one and wrong for the
            // tracker's other periodic work: that must survive backgrounding
            // and so rides the location callbacks, whereas this exists solely
            // to keep a button honest on a screen someone is looking at.
            .task(id: activeSessionId) {
                guard activeSessionId == nil else { return }
                while !Task.isCancelled {
                    await BuddySessionService.shared.refreshFriendsOutNow()
                    try? await Task.sleep(for: .seconds(60))
                }
            }
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
                            showLobby = false
                            onStarted(session)
                        }
                    }
            )
    }
}
