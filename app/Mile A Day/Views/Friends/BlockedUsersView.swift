import SwiftUI

// File intentionally left empty. The previous BlockedUsersView referenced
// FriendService.loadBlockedUsers() / unblockUser(_:) — methods that were
// never implemented on the service or the backend. The view was orphaned
// (only referenced by its own #Preview), so emptying it unblocks the build
// without losing any wired functionality.
//
// To bring blocking back: design backend endpoints, add the service methods,
// then rebuild this view. Safe to delete from the Xcode project at your
// next cleanup pass.
