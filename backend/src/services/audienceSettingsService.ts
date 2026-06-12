import { PostgresService } from './DbService.js';

const db = PostgresService.getInstance();

// ─── Types ───────────────────────────────────────────────────────────

export type AudienceDirection = 'outgoing' | 'incoming';
export type AudienceEventType =
	| 'mile_completed'
	| 'extra_workout'
	| 'workout'
	| 'personal_best'
	| 'badge_earned'
	| 'challenge_completed'
	| 'streak_broken';
export type AudienceActivity = 'run' | 'walk' | '';
export type Audience = 'none' | 'close' | 'all' | 'ask' | 'match_run';
export type ResolvedAudience = 'none' | 'close' | 'all' | 'ask';

// ─── Constants ───────────────────────────────────────────────────────

const VALID_EVENT_TYPES: ReadonlySet<string> = new Set([
	'mile_completed',
	'extra_workout',
	'workout',
	'personal_best',
	'badge_earned',
	'challenge_completed',
	'streak_broken'
]);

// Event types for which activity_type rows ('run'/'walk') are valid
const ACTIVITY_AWARE_EVENTS: ReadonlySet<string> = new Set(['mile_completed', 'extra_workout', 'workout']);

const VALID_AUDIENCES: ReadonlySet<string> = new Set(['none', 'close', 'all', 'ask', 'match_run']);

export type SystemDefaultsMap = {
	outgoing: Record<AudienceEventType, ResolvedAudience>;
	incoming: Record<AudienceEventType, ResolvedAudience>;
};

export const SYSTEM_DEFAULTS: SystemDefaultsMap = {
	outgoing: {
		mile_completed: 'all',
		extra_workout: 'all',
		workout: 'none', // new pre-goal trigger — opt-in
		personal_best: 'all',
		badge_earned: 'all',
		challenge_completed: 'all',
		streak_broken: 'all'
	},
	incoming: {
		mile_completed: 'all',
		extra_workout: 'all',
		workout: 'all',
		personal_best: 'all',
		badge_earned: 'all',
		challenge_completed: 'all',
		streak_broken: 'all'
	}
};

// ─── DB row type ─────────────────────────────────────────────────────

interface AudienceRow {
	user_id: string;
	direction: AudienceDirection;
	event_type: string;
	activity_type: string;
	audience: Audience;
	updated_at: string;
}

// ─── Cascade resolution helpers ──────────────────────────────────────

/**
 * Resolve a single (eventType, activity) pair given the user's rows for that event and '*'.
 * Mutually recursive via tryResolveActivity for the match_run case.
 */
function resolveFromRows(
	rows: AudienceRow[],
	direction: AudienceDirection,
	eventType: AudienceEventType,
	activity: AudienceActivity,
	depth = 0
): ResolvedAudience {
	if (depth > 1) {
		// Safety: avoid infinite recursion in weird data
		return SYSTEM_DEFAULTS[direction][eventType];
	}

	const byKey = (et: string, at: string): Audience | undefined =>
		rows.find(r => r.event_type === et && r.activity_type === at)?.audience;

	// 1. Exact row (eventType, activity)
	const exact = byKey(eventType, activity);
	if (exact !== undefined) {
		if (exact === 'match_run') {
			if (activity === 'walk') {
				// Restart resolution as (eventType, 'run')
				return resolveFromRows(rows, direction, eventType, 'run', depth + 1);
			}
			// match_run on non-walk row → continue cascade
		} else if (exact === 'ask' && direction === 'incoming') {
			// 'ask' is illegal for incoming — treat as permissive
			return 'all';
		} else {
			return exact as ResolvedAudience;
		}
	}

	// 2. Event-level row (eventType, '')
	const eventLevel = byKey(eventType, '');
	if (eventLevel !== undefined) {
		if (eventLevel === 'match_run') {
			// match_run shouldn't be on event-level row with '' activity, treat as invalid → continue
		} else if (eventLevel === 'ask' && direction === 'incoming') {
			// 'ask' is illegal for incoming — treat as permissive
			return 'all';
		} else {
			return eventLevel as ResolvedAudience;
		}
	}

	// 3. Global row ('*', '')
	const global = byKey('*', '');
	if (global !== undefined) {
		if (global === 'match_run') {
			// invalid for global row → continue
		} else if (global === 'ask' && direction === 'incoming') {
			// 'ask' is illegal for incoming — treat as permissive
			return 'all';
		} else {
			return global as ResolvedAudience;
		}
	}

	// 4. System default
	return SYSTEM_DEFAULTS[direction][eventType];
}

// ─── resolveAudience ─────────────────────────────────────────────────

export async function resolveAudience(
	userId: string,
	direction: AudienceDirection,
	eventType: AudienceEventType,
	activity: AudienceActivity
): Promise<ResolvedAudience> {
	const rows = await db.query<AudienceRow>(
		`SELECT event_type, activity_type, audience
		 FROM notification_audience_settings
		 WHERE user_id = $1
		   AND direction = $2
		   AND event_type = ANY($3::text[])`,
		[userId, direction, [eventType, '*']]
	);

	return resolveFromRows(rows, direction, eventType, activity);
}

// ─── filterByIncomingAudience ─────────────────────────────────────────

export async function filterByIncomingAudience(
	recipientIds: string[],
	senderId: string,
	eventType: AudienceEventType,
	activity: AudienceActivity
): Promise<string[]> {
	if (recipientIds.length === 0) return [];

	// Fetch all relevant audience rows for all recipients in one query
	const audienceRows = await db.query<AudienceRow>(
		`SELECT user_id, event_type, activity_type, audience
		 FROM notification_audience_settings
		 WHERE user_id = ANY($1::text[])
		   AND direction = 'incoming'
		   AND event_type = ANY($2::text[])`,
		[recipientIds, [eventType, '*']]
	);

	// Group rows by recipient
	const rowsByUser = new Map<string, AudienceRow[]>();
	for (const row of audienceRows) {
		if (!rowsByUser.has(row.user_id)) rowsByUser.set(row.user_id, []);
		rowsByUser.get(row.user_id)!.push(row);
	}

	// Resolve audience per recipient
	const resolved = new Map<string, ResolvedAudience>();
	for (const recipientId of recipientIds) {
		const userRows = rowsByUser.get(recipientId) ?? [];
		resolved.set(recipientId, resolveFromRows(userRows, 'incoming', eventType, activity));
	}

	// Collect recipients resolving to 'close' — need to verify sender is on THEIR close list
	const closeRecipients = recipientIds.filter(id => resolved.get(id) === 'close');

	// One query: which of the close-resolving recipients have senderId as their close friend
	// (also validates accepted friendship via the JOIN on friendships)
	let closeFriendSet = new Set<string>();
	if (closeRecipients.length > 0) {
		const closeRows = await db.query<{ user_id: string }>(
			`SELECT cf.user_id
			 FROM close_friends cf
			 JOIN friendships f ON f.user_id = cf.user_id AND f.friend_id = cf.close_friend_id AND f.status = 'accepted'
			 WHERE cf.user_id = ANY($1::text[])
			   AND cf.close_friend_id = $2`,
			[closeRecipients, senderId]
		);
		closeFriendSet = new Set(closeRows.map(r => r.user_id));
	}

	return recipientIds.filter(id => {
		const audience = resolved.get(id);
		if (audience === 'none') return false;
		if (audience === 'all') return true;
		if (audience === 'close') return closeFriendSet.has(id);
		// 'ask' resolved to incoming falls back to 'all' in resolveFromRows, but defensive:
		return true;
	});
}

// ─── getAudienceSettings ─────────────────────────────────────────────

export interface AudienceSetting {
	direction: AudienceDirection;
	event_type: string;
	activity_type: string;
	audience: Audience;
	updated_at: string;
}

export async function getAudienceSettings(userId: string): Promise<{ outgoing: AudienceSetting[]; incoming: AudienceSetting[] }> {
	const rows = await db.query<AudienceSetting>(
		`SELECT direction, event_type, activity_type, audience, updated_at
		 FROM notification_audience_settings
		 WHERE user_id = $1
		 ORDER BY direction, event_type, activity_type`,
		[userId]
	);

	return {
		outgoing: rows.filter(r => r.direction === 'outgoing'),
		incoming: rows.filter(r => r.direction === 'incoming')
	};
}

// ─── setAudienceSetting ───────────────────────────────────────────────

export type ValidationError = { validationError: string };

export async function setAudienceSetting(
	userId: string,
	direction: AudienceDirection,
	eventType: string,
	activityType: string,
	audience: Audience | null
): Promise<ValidationError | { outgoing: AudienceSetting[]; incoming: AudienceSetting[] }> {
	// Validate direction
	if (direction !== 'outgoing' && direction !== 'incoming') {
		return { validationError: 'direction must be "outgoing" or "incoming"' };
	}

	// Validate audience value (null = reset is allowed)
	if (audience !== null && !VALID_AUDIENCES.has(audience)) {
		return { validationError: `audience must be one of: ${[...VALID_AUDIENCES].join(', ')}` };
	}

	// Validate event_type
	if (eventType !== '*' && !VALID_EVENT_TYPES.has(eventType)) {
		return { validationError: `event_type must be one of: *, ${[...VALID_EVENT_TYPES].join(', ')}` };
	}

	// Validate activity_type
	if (activityType !== '' && activityType !== 'run' && activityType !== 'walk') {
		return { validationError: 'activity_type must be "", "run", or "walk"' };
	}

	// Activity rows only allowed for mile_completed, extra_workout, workout (or '*' global has no activity)
	if (activityType !== '' && !ACTIVITY_AWARE_EVENTS.has(eventType)) {
		return { validationError: `activity_type rows are only valid for: ${[...ACTIVITY_AWARE_EVENTS].join(', ')}` };
	}

	// 'ask' only valid for outgoing
	if (audience === 'ask' && direction === 'incoming') {
		return { validationError: '"ask" is only valid for direction="outgoing"' };
	}

	// 'match_run' only valid when activity_type is 'walk'
	if (audience === 'match_run' && activityType !== 'walk') {
		return { validationError: '"match_run" is only valid when activity_type="walk"' };
	}

	if (audience === null) {
		// Reset: delete the row
		await db.query(
			`DELETE FROM notification_audience_settings
			 WHERE user_id = $1 AND direction = $2 AND event_type = $3 AND activity_type = $4`,
			[userId, direction, eventType, activityType]
		);
	} else {
		// Upsert
		await db.query(
			`INSERT INTO notification_audience_settings (user_id, direction, event_type, activity_type, audience, updated_at)
			 VALUES ($1, $2, $3, $4, $5, NOW())
			 ON CONFLICT (user_id, direction, event_type, activity_type)
			 DO UPDATE SET audience = EXCLUDED.audience, updated_at = NOW()`,
			[userId, direction, eventType, activityType, audience]
		);
	}

	return getAudienceSettings(userId);
}
