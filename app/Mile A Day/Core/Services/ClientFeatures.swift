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

    /// Declared on registration. Add a string here only in the same build that
    /// actually implements the behavior.
    static let supported: [String] = [friendRequestV2]
}
