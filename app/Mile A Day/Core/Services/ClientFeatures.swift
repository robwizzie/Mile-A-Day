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

    /// This build has the Buddy Walks & Runs screens — it can render a lobby, a
    /// live roster and a recap, and it registers the BUDDY_INVITE category.
    ///
    /// This one does more than gate a payload: declaring it is what ENROLLS the
    /// user (the server stamps `users.buddy_enrolled_at` on registration), and
    /// an enrolled user is offered to their friends as someone who can be pulled
    /// into a walk. So a build that sends this string without the screens would
    /// have its owner invited to something their app cannot open.
    ///
    /// It is also the only thing standing between an older install and a buddy
    /// invite now that the server-side `BUDDY_SESSIONS` flag defaults on.
    static let buddyWalksV1 = "buddy_walks_v1"

    /// This build renders the weekly challenge — the Compete-tab hero, the
    /// friends leaderboard and the history — so a `weekly_challenge_*` push has
    /// somewhere to open.
    ///
    /// All three types are brand new strings. Unlike `lead_change`, which
    /// head-to-head deliberately reuses because every shipped build already
    /// routes it, there is no existing weekly route to piggyback on: without
    /// this gate an older install would get a banner that does nothing.
    static let weeklyChallengeV1 = "weekly_challenge_v1"

    /// This build treats a buddy walk as ONE post: it draws the crew's routes
    /// on a single combined map, shows each participant's photo as its own
    /// slide, and — the half that matters — asks the SERVER whether the walk
    /// has already been posted, offering "add your photo" instead of a second
    /// Post CTA when it has.
    ///
    /// Gated because the one-post rule is a RESTRICTION on what a shipped build
    /// already does. Those builds answer "already posted?" from a device-local
    /// registry that cannot see a friend's phone, and have no way to put a
    /// photo on someone else's card — so if a newer build posts the walk first,
    /// the older one must still be allowed its own post rather than be left
    /// with a CTA that 409s. They keep today's behaviour until they update.
    static let buddyGroupPostV1 = "buddy_group_post_v1"

    /// Declared on registration. Add a string here only in the same build that
    /// actually implements the behavior.
    static let supported: [String] = [
        friendRequestV2, collabTagV1, ghostFriendRaceV1, postWindowV1, buddyWalksV1,
        weeklyChallengeV1, buddyGroupPostV1,
    ]
}
