import Foundation
import SwiftUI

/// Manages the user's private, one-directional close-friends list.
///
/// Close friends are Instagram-style: you pick yours, the other person is never
/// told. Backend contract (all Bearer-authed):
///   GET    /friends/close            → [BackendUser]
///   POST   /friends/close/:friendId  → { message } | 400 { error }
///   DELETE /friends/close/:friendId  → { message }
///
/// Shared singleton so the profile star toggle, the close-friends list screen,
/// and the audience settings UI all read one source of truth.
@MainActor
class CloseFriendsService: ObservableObject {
	static let shared = CloseFriendsService()

	@Published private(set) var closeFriends: [BackendUser] = []
	@Published private(set) var closeFriendIds: Set<String> = []
	@Published private(set) var hasLoadedOnce = false
	@Published var isLoading = false
	@Published var errorMessage: String?

	private init() {}

	/// True when `userId` is on the current user's close list.
	func isClose(_ userId: String) -> Bool {
		closeFriendIds.contains(userId)
	}

	/// Load once per session if we haven't already (e.g. when a profile opens).
	/// Silently ignores errors — callers that need to surface failures use `load()`.
	func loadIfNeeded() async {
		guard !hasLoadedOnce else { return }
		try? await load()
	}

	/// Load the full close-friends list from the backend.
	func load() async throws {
		isLoading = true
		defer { isLoading = false }
		do {
			let friends = try await APIClient.fancyFetch(
				endpoint: "/friends/close",
				responseType: [BackendUser].self
			)
			closeFriends = friends
			closeFriendIds = Set(friends.map { $0.user_id })
			hasLoadedOnce = true
		} catch {
			errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
			throw error
		}
	}

	/// Add a friend to the close list. Optimistically flips local state, then
	/// reverts on failure. Only accepted friends are allowed (server enforces).
	func add(_ user: BackendUser) async throws {
		guard !closeFriendIds.contains(user.user_id) else { return }
		// Optimistic
		closeFriendIds.insert(user.user_id)
		if !closeFriends.contains(where: { $0.user_id == user.user_id }) {
			closeFriends.append(user)
		}
		do {
			struct Message: Decodable { let message: String }
			let _: Message = try await APIClient.fancyFetch(
				endpoint: "/friends/close/\(user.user_id)",
				method: .POST,
				responseType: Message.self
			)
		} catch {
			// Revert
			closeFriendIds.remove(user.user_id)
			closeFriends.removeAll { $0.user_id == user.user_id }
			errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
			throw error
		}
	}

	/// Remove a friend from the close list (optimistic, reverts on failure).
	func remove(_ userId: String) async throws {
		let removedUser = closeFriends.first { $0.user_id == userId }
		// Optimistic
		closeFriendIds.remove(userId)
		closeFriends.removeAll { $0.user_id == userId }
		do {
			struct Message: Decodable { let message: String }
			let _: Message = try await APIClient.fancyFetch(
				endpoint: "/friends/close/\(userId)",
				method: .DELETE,
				responseType: Message.self
			)
		} catch {
			// Revert
			closeFriendIds.insert(userId)
			if let user = removedUser, !closeFriends.contains(where: { $0.user_id == userId }) {
				closeFriends.append(user)
			}
			errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
			throw error
		}
	}

	/// Toggle close-friend status for a user. Returns the new state.
	@discardableResult
	func toggle(_ user: BackendUser) async throws -> Bool {
		if closeFriendIds.contains(user.user_id) {
			try await remove(user.user_id)
			return false
		} else {
			try await add(user)
			return true
		}
	}
}
