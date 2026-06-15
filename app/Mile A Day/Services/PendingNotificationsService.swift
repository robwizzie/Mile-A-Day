import Foundation
import SwiftUI

/// Manages "ask"-mode pending friend notifications: the stash of workouts the
/// user hasn't yet decided to broadcast. Server is authoritative — it never
/// auto-sends an `ask` event; it queues a row instead. The user confirms here,
/// or the row expires at their local midnight (same calendar day only).
///
/// Backend contract (Bearer-authed):
///   GET    /notifications/pending          → { pending: [row] }  (lazy-expires stale)
///   POST   /notifications/pending/:id/send  body { audience?: "close"|"all" } → { sent: N }
///   DELETE /notifications/pending/:id       → { ok: true }
///   DELETE /notifications/pending           → { dismissed: N }
///
/// Shared singleton so the celebration embed and the standalone sheet share one
/// pending list and stay in sync after a send/dismiss.
@MainActor
class PendingNotificationsService: ObservableObject {
	static let shared = PendingNotificationsService()

	@Published private(set) var pending: [PendingFriendNotification] = []
	@Published var isLoading = false
	@Published var errorMessage: String?

	private init() {}

	var hasPending: Bool { !pending.isEmpty }

	/// The pending item (if any) for today's mile completion — used by the
	/// celebration embed.
	var mileCompletedPending: PendingFriendNotification? {
		pending.first { $0.eventType == AudienceEventType.mileCompleted.rawValue }
	}

	/// Fetch the current pending list. Stale rows are expired server-side on read.
	func load() async throws {
		isLoading = true
		defer { isLoading = false }
		do {
			struct Response: Decodable { let pending: [PendingFriendNotification] }
			let response = try await APIClient.fancyFetch(
				endpoint: "/notifications/pending",
				responseType: Response.self
			)
			pending = response.pending
		} catch {
			errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
			throw error
		}
	}

	/// Confirm and send a pending notification. `audience` may narrow to "close"
	/// or "all" (default all); the server caps it to the sender's current setting.
	/// Removes the item locally on success. Returns the recipient count.
	@discardableResult
	func send(_ item: PendingFriendNotification, audience: Audience? = nil) async throws -> Int {
		struct Body: Encodable { let audience: String? }
		// Only "close"/"all" are valid send audiences; anything else → default (all).
		let sendAudience: String? = (audience == .close || audience == .all) ? audience?.rawValue : nil
		let bodyData = try JSONEncoder().encode(Body(audience: sendAudience))
		do {
			struct Response: Decodable { let sent: Int }
			let response = try await APIClient.fancyFetch(
				endpoint: "/notifications/pending/\(item.id)/send",
				method: .POST,
				body: bodyData,
				responseType: Response.self
			)
			pending.removeAll { $0.id == item.id }
			return response.sent
		} catch {
			// On 409/410 the item is no longer actionable — drop it locally so the
			// UI doesn't keep offering a dead action.
			if case APIError.conflict = error { pending.removeAll { $0.id == item.id } }
			if case APIError.apiError = error { pending.removeAll { $0.id == item.id } }
			errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
			throw error
		}
	}

	/// Dismiss (decline) a single pending notification. Removes it locally.
	func dismiss(_ item: PendingFriendNotification) async throws {
		do {
			struct Response: Decodable { let ok: Bool }
			let _: Response = try await APIClient.fancyFetch(
				endpoint: "/notifications/pending/\(item.id)",
				method: .DELETE,
				responseType: Response.self
			)
			pending.removeAll { $0.id == item.id }
		} catch {
			errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
			throw error
		}
	}

	/// Dismiss all pending notifications. Clears the local list. Returns the count.
	@discardableResult
	func dismissAll() async throws -> Int {
		do {
			struct Response: Decodable { let dismissed: Int }
			let response = try await APIClient.fancyFetch(
				endpoint: "/notifications/pending",
				method: .DELETE,
				responseType: Response.self
			)
			pending.removeAll()
			return response.dismissed
		} catch {
			errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
			throw error
		}
	}
}
