import Foundation

// MARK: - Friend Notification Audience Models
//
// Mirrors the backend contract in:
//   backend/src/services/audienceSettingsService.ts
//   backend/src/services/pendingNotificationService.ts
//
// Per-event-type "audience" controls who hears about your activity (outgoing)
// and whose activity you hear about (incoming), plus a private close-friends
// list and an "ask each time" confirmation flow. Only explicitly-set rows are
// returned by the API; everything else inherits via the cascade
// (event+activity → event → global `*` → system default). See
// AudienceSettingsService for the client-side resolver.

/// Who an event is shared with / heard from.
/// `matchRun` ("Same as Running") is walk-only and tracks the run setting.
/// `ask` is outgoing-only (prompts per-workout before notifying).
enum Audience: String, Codable, CaseIterable {
	case none
	case close
	case all
	case ask
	case matchRun = "match_run"

	/// Short label for menus/buttons.
	var displayName: String {
		switch self {
		case .none: return "No one"
		case .close: return "Close friends"
		case .all: return "All friends"
		case .ask: return "Ask each time"
		case .matchRun: return "Same as Running"
		}
	}
}

/// Direction of an audience setting.
enum AudienceDirection: String, Codable {
	case outgoing
	case incoming
}

/// Event types that can carry an audience setting. `global` maps to the `*` row.
enum AudienceEventType: String, CaseIterable {
	case mileCompleted = "mile_completed"
	case extraWorkout = "extra_workout"
	case workout = "workout"
	case personalBest = "personal_best"
	case badgeEarned = "badge_earned"
	case challengeCompleted = "challenge_completed"
	case streakBroken = "streak_broken"
	case global = "*"

	/// Workout-type events have separate run/walk audiences.
	var isActivityAware: Bool {
		switch self {
		case .mileCompleted, .extraWorkout, .workout: return true
		default: return false
		}
	}

	var displayName: String {
		switch self {
		case .mileCompleted: return "Mile completed"
		case .extraWorkout: return "Extra workout"
		case .workout: return "Other workouts"
		case .personalBest: return "Personal best"
		case .badgeEarned: return "Badge earned"
		case .challengeCompleted: return "Challenge completed"
		case .streakBroken: return "Streak broken"
		case .global: return "Everything"
		}
	}
}

/// Activity dimension for workout-type events.
enum AudienceActivity: String {
	case none = ""
	case run = "run"
	case walk = "walk"
}

// MARK: - DTOs

/// A single explicitly-set audience row, as returned by the API.
struct AudienceSetting: Codable, Identifiable, Hashable {
	let direction: String
	let eventType: String
	let activityType: String
	let audience: Audience
	let updatedAt: String?

	enum CodingKeys: String, CodingKey {
		case direction
		case eventType = "event_type"
		case activityType = "activity_type"
		case audience
		case updatedAt = "updated_at"
	}

	var id: String { "\(direction)|\(eventType)|\(activityType)" }
}

/// Response shape for GET /notifications/audience and PUT /notifications/audience.
struct AudienceSettingsResponse: Codable {
	let settings: Settings
	let systemDefaults: SystemDefaults

	struct Settings: Codable {
		let outgoing: [AudienceSetting]
		let incoming: [AudienceSetting]
	}

	/// event_type → resolved audience (never `ask`/`match_run`).
	struct SystemDefaults: Codable {
		let outgoing: [String: Audience]
		let incoming: [String: Audience]
	}
}

/// A queued ("ask"-mode) friend notification awaiting the user's confirmation.
struct PendingFriendNotification: Codable, Identifiable, Hashable {
	let id: String
	let eventType: String
	let activityType: String
	let workoutId: String?
	let payload: PendingPayload
	let localDate: String
	let createdAt: String

	enum CodingKeys: String, CodingKey {
		case id
		case eventType = "event_type"
		case activityType = "activity_type"
		case workoutId = "workout_id"
		case payload
		case localDate = "local_date"
		case createdAt = "created_at"
	}

	init(from decoder: Decoder) throws {
		let c = try decoder.container(keyedBy: CodingKeys.self)
		// `id` is a Postgres bigint — pg may serialize it as a string or a number
		// depending on column type. Accept either so decoding never fails.
		if let s = try? c.decode(String.self, forKey: .id) {
			id = s
		} else {
			id = String(try c.decode(Int.self, forKey: .id))
		}
		eventType = try c.decode(String.self, forKey: .eventType)
		activityType = (try? c.decode(String.self, forKey: .activityType)) ?? ""
		workoutId = try? c.decode(String.self, forKey: .workoutId)
		payload = (try? c.decode(PendingPayload.self, forKey: .payload)) ?? PendingPayload(title: nil, body: nil)
		localDate = try c.decode(String.self, forKey: .localDate)
		createdAt = try c.decode(String.self, forKey: .createdAt)
	}
}

/// Display fields from a pending notification's stored push payload. Other
/// payload fields (type/category/data) are intentionally ignored for the UI.
struct PendingPayload: Codable, Hashable {
	let title: String?
	let body: String?
}
