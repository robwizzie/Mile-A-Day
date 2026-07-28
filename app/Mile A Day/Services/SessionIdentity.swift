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

    /// Signs out if — and only if — the token and the cached id name different
    /// accounts. Returns `true` when it signed the user out.
    ///
    /// Safe to call often; it's a pure local comparison with no network cost.
    @discardableResult
    @MainActor
    static func enforce() -> Bool {
        guard isMismatched else { return false }

        print("[SessionIdentity] ⚠️ Token subject does not match the cached user id — signing out")
        UserManager.shared.signOut()
        AppStateManager.shared.signOut()
        return true
    }
}
