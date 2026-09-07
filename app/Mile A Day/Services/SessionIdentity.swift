import Foundation

/// Reconciles "who the access token says we are" against "who the app thinks we
/// are" and tears the session down when they disagree.
///
/// Every self-scoped endpoint (`/friends/:userId`, `/users/:userId/challenges`,
/// `/workouts/:userId/...`) is built from a locally cached id — either
/// `UserManager.currentUser.backendUserId` or `UserDefaults["backendUserId"]` —
/// while the server authorizes against the JWT's `sub` claim. When those drift
/// apart the server answers **403**, not 401, so the token-refresh/sign-out path
/// in `APIClient` never fires: the app stays "logged in" while friends and daily
/// challenges silently fail to load forever.
///
/// Drift is reachable in practice. Two people sharing one Apple account resolve
/// to a single backend user, and `signOut()` historically left
/// `UserDefaults["backendUserId"]` behind, so a stale id could outlive the
/// session that created it.
///
/// The token is authoritative for authorization but the cached profile (name,
/// streak, Apple id, friends) belongs to whoever the cached id points at, so a
/// mismatch can't be healed by adopting one side — the only honest outcome is to
/// sign out and send the user back to the auth screen.
enum SessionIdentity {

    /// The backend user id the current access token was actually minted for.
    /// `nil` when there's no token or it isn't a decodable JWT.
    static var tokenUserId: String? {
        guard let accessToken = TokenStore.accessToken else { return nil }
        return TokenUtils.subject(from: accessToken)
    }

    /// The id the client puts into self-scoped URL paths.
    static var cachedUserId: String? {
        let stored = UserDefaults.standard.string(forKey: "backendUserId")
        if let stored, !stored.isEmpty { return stored }
        let onUser = UserManager.shared.currentUser.backendUserId
        return (onUser?.isEmpty == false) ? onUser : nil
    }

    /// True only when both ids are known AND they disagree.
    ///
    /// Fails open on every "unknown" case: no token, an opaque token, or no
    /// cached id at all. Those are handled elsewhere (`TokenStore.hasTokens`
    /// gates `isAuthenticated`; an undecodable token is already treated as
    /// expired by `TokenUtils.isTokenExpired`), and signing out on them would
    /// punish users for transient states rather than a real account mismatch.
    static var isMismatched: Bool {
        guard let tokenUserId, let cachedUserId else { return false }
        return tokenUserId != cachedUserId
    }

    /// The local user record was LOST rather than never written: a stored blob
    /// existed and could not be decoded, so `currentUser` is the "You"
    /// placeholder while real tokens sit in the Keychain.
    ///
    /// This is a signed-in session wearing a stranger's record. Everything
    /// read from `currentUser` is wrong in a way nothing surfaces — a streak
    /// of 0, a 1-mile goal the user never chose, and an auto post whose baked
    /// route card carries the initials "YO" over their own walk. The id
    /// comparison above cannot catch it, because the separate `backendUserId`
    /// key survives and still agrees with the token.
    ///
    /// Gated on tokens existing: without them the user is not signed in and
    /// there is nothing to sign out of. That also makes the pre-first-unlock
    /// background launch safe — `TokenStore` reads nil there
    /// (`kSecAttrAccessibleAfterFirstUnlock`), so this fails OPEN, which is
    /// the direction a false answer should err in.
    static var hasLostLocalIdentity: Bool {
        UserManager.shared.restoreFailed && TokenStore.hasTokens
    }

    /// Signs out when the session can no longer be trusted to name its own
    /// user: the token and the cached id name different accounts, or the local
    /// user record was lost. Returns `true` when it signed the user out.
    ///
    /// Safe to call often; both checks are local with no network cost.
    ///
    /// Signing out rather than re-fetching the profile is the deliberate
    /// choice: a decode failure means we do not know this person's goal,
    /// units, privacy settings or streak, and continuing to act as somebody is
    /// how a wrong avatar got baked into a real post. Signing in again is one
    /// tap of Sign in with Apple and restores all of it from the server.
    @discardableResult
    @MainActor
    static func enforce() -> Bool {
        let lostIdentity = hasLostLocalIdentity
        guard isMismatched || lostIdentity else { return false }

        if lostIdentity {
            print("[SessionIdentity] ⚠️ Stored user could not be decoded while tokens exist — signing out")
        } else {
            print("[SessionIdentity] ⚠️ Token subject does not match the cached user id — signing out")
        }
        UserManager.shared.signOut()
        AppStateManager.shared.signOut()
        return true
    }
}
