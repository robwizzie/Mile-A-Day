import Foundation

/// What this build tells the server it can handle, sent with every device-token
/// registration (`POST /devices/register`, `client_features`).
///
/// The server deploys weeks before an App Store release and some users never
/// update at all, so "is the new API live?" can't answer "is it safe to send
/// this payload to this phone?". Only the phone can. Anything the server has
/// no declaration for is treated as a legacy client forever, which is the safe
/// default — see `backend/src/services/clientFeatures.ts`, which must stay in
/// sync with this list.
enum ClientFeatures {
    /// This build clears its own app-icon badge (launch, foreground, and on
    /// every change to the pending-request count) and registers the
    /// FRIEND_REQUEST notification category, so Accept/Decline actions render
    /// and route. Without both halves a server-set badge would stick forever.
    static let friendRequestV2 = "friend_request_v2"

    /// This build registers the COAUTHOR_TAG category, so a collab-tag push
    /// carries a "Remove me" action the user can resolve from the banner
    /// without opening the app. Older builds get the same push with no
    /// buttons — it still opens the post, which is the safe direction.
    static let collabTagV1 = "collab_tag_v1"

    /// This build understands the `ghost_beaten` push — "Alex beat your mile by
    /// 6s" — and can race a friend's mile as its ghost in the first place.
    ///
    /// The meaning here is deliberately "won't be confused by the push", not
    /// "can act on it": tapping it just opens the app, which is what every
    /// other informational push does. A rematch deep-link is a later addition
    /// and would need its OWN string if it ever needs gating, because reusing
    /// this one with a new meaning would silently mis-describe every install
    /// that already sent it.
    static let ghostFriendRaceV1 = "ghost_friend_race_v1"

    /// This build binds photo posting to the 10-minute window that opens when a
    /// qualifying walk/run lands: it locks its own compose affordances when the
    /// window closes, and it explains the server's `post_window_closed` 403
    /// instead of surfacing it as a generic failure.
    ///
    /// Declaring it is what OPTS THIS DEVICE IN to the restriction — the server
    /// leaves undeclared builds on the old all-day rule, because they'd let a
    /// user shoot and edit a photo before failing at publish with nothing able
    /// to say why.
    static let postWindowV1 = "post_window_v1"

    /// Declared on registration. Add a string here only in the same build that
    /// actually implements the behavior.
    static let supported: [String] = [
        friendRequestV2, collabTagV1, ghostFriendRaceV1, postWindowV1,
    ]
}
