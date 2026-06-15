import Foundation
import SwiftUI

/// Loads and mutates per-event-type notification audience settings, and resolves
/// the cascade client-side so the UI can render "Default · <resolved>" labels.
///
/// Backend contract (Bearer-authed):
///   GET /notifications/audience
///     → { settings: { outgoing: [row], incoming: [row] }, systemDefaults: {...} }
///   PUT /notifications/audience  body { direction, event_type, activity_type?, audience }
///     → same shape as GET. `audience` omitted/null resets the row.
///
/// The resolver MUST mirror `resolveFromRows` in
/// backend/src/services/audienceSettingsService.ts exactly.
@MainActor
class AudienceSettingsService: ObservableObject {
	@Published private(set) var outgoing: [AudienceSetting] = []
	@Published private(set) var incoming: [AudienceSetting] = []
	@Published private(set) var systemDefaults: AudienceSettingsResponse.SystemDefaults =
		AudienceSettingsResponse.SystemDefaults(outgoing: [:], incoming: [:])
	@Published private(set) var hasLoaded = false
	@Published var isLoading = false
	@Published var errorMessage: String?

	/// True when the user has ANY outgoing `ask` row — used as a cheap guard
	/// before fetching pending notifications on foreground.
	var hasAskSettings: Bool {
		outgoing.contains { $0.audience == .ask }
	}

	// MARK: - Loading

	func load() async throws {
		isLoading = true
		defer { isLoading = false }
		do {
			let response = try await APIClient.fancyFetch(
				endpoint: "/notifications/audience",
				responseType: AudienceSettingsResponse.self
			)
			apply(response)
		} catch {
			errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
			throw error
		}
	}

	private func apply(_ response: AudienceSettingsResponse) {
		outgoing = response.settings.outgoing
		incoming = response.settings.incoming
		systemDefaults = response.systemDefaults
		hasLoaded = true
	}

	// MARK: - Mutation

	/// Set (or reset) a single audience row. Pass `audience: nil` to reset to the
	/// inherited/default value (deletes the row server-side). Returns after the
	/// server echoes the full updated settings.
	func set(
		direction: AudienceDirection,
		eventType: AudienceEventType,
		activity: AudienceActivity = .none,
		audience: Audience?
	) async throws {
		struct Body: Encodable {
			let direction: String
			let event_type: String
			let activity_type: String
			let audience: String?  // nil → synthesized encoder omits → server resets
		}
		let body = Body(
			direction: direction.rawValue,
			event_type: eventType.rawValue,
			activity_type: activity.rawValue,
			audience: audience?.rawValue
		)
		let bodyData = try JSONEncoder().encode(body)
		do {
			let response = try await APIClient.fancyFetch(
				endpoint: "/notifications/audience",
				method: .PUT,
				body: bodyData,
				responseType: AudienceSettingsResponse.self
			)
			apply(response)
		} catch {
			errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
			throw error
		}
	}

	// MARK: - Lookup

	private func rows(for direction: AudienceDirection) -> [AudienceSetting] {
		direction == .outgoing ? outgoing : incoming
	}

	/// The explicitly-set value for a row, or nil if it inherits (= "Default").
	func explicitAudience(
		direction: AudienceDirection,
		eventType: AudienceEventType,
		activity: AudienceActivity = .none
	) -> Audience? {
		rows(for: direction).first {
			$0.eventType == eventType.rawValue && $0.activityType == activity.rawValue
		}?.audience
	}

	// MARK: - Cascade resolver (mirrors backend resolveFromRows)

	/// Resolve the effective audience for an (event, activity) pair.
	func resolve(
		direction: AudienceDirection,
		eventType: AudienceEventType,
		activity: AudienceActivity = .none
	) -> Audience {
		resolveFromRows(rows(for: direction), direction, eventType.rawValue, activity.rawValue, depth: 0)
	}

	private func systemDefault(_ direction: AudienceDirection, _ eventType: String) -> Audience {
		let map = direction == .outgoing ? systemDefaults.outgoing : systemDefaults.incoming
		return map[eventType] ?? .all
	}

	private func resolveFromRows(
		_ rows: [AudienceSetting],
		_ direction: AudienceDirection,
		_ eventType: String,
		_ activity: String,
		depth: Int
	) -> Audience {
		if depth > 1 { return systemDefault(direction, eventType) }

		func byKey(_ et: String, _ at: String) -> Audience? {
			rows.first { $0.eventType == et && $0.activityType == at }?.audience
		}

		// 1. Exact row (eventType, activity)
		if let exact = byKey(eventType, activity) {
			if exact == .matchRun {
				if activity == AudienceActivity.walk.rawValue {
					return resolveFromRows(rows, direction, eventType, AudienceActivity.run.rawValue, depth: depth + 1)
				}
				// match_run on a non-walk row → continue cascade
			} else if exact == .ask && direction == .incoming {
				return .all  // 'ask' illegal for incoming → permissive
			} else {
				return exact
			}
		}

		// 2. Event-level row (eventType, '')
		if let eventLevel = byKey(eventType, "") {
			if eventLevel == .matchRun {
				// invalid on event-level row → continue
			} else if eventLevel == .ask && direction == .incoming {
				return .all
			} else {
				return eventLevel
			}
		}

		// 3. Global row ('*', '')
		if let global = byKey("*", "") {
			if global == .matchRun {
				// invalid on global row → continue
			} else if global == .ask && direction == .incoming {
				return .all
			} else {
				return global
			}
		}

		// 4. System default
		return systemDefault(direction, eventType)
	}
}
