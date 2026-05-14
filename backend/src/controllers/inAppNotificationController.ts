import { Request, Response } from 'express';
import { PostgresService } from '../services/DbService.js';

const db = PostgresService.getInstance();

interface HypeDerivation {
	hype_target_user_id: string | null;
	hype_context_type: 'mile' | 'badge' | 'pr' | null;
	hype_context_id: string | null;
	hype_context_label: string | null;
}

/**
 * Derive hype context from a notification row's type + data. Returns null fields
 * for notification types that aren't hype-able.
 */
function deriveHypeContext(row: { type: string; data: Record<string, any> | null; created_at: Date | string }): HypeDerivation {
	const data = row.data ?? {};
	const empty: HypeDerivation = {
		hype_target_user_id: null,
		hype_context_type: null,
		hype_context_id: null,
		hype_context_label: null
	};

	if (row.type === 'friend_activity') {
		// Only celebrate the mile-completion variant. Streak-broken is sympathetic.
		if (data.kind !== 'mile_completed') return empty;
		const targetId = data.user_id;
		if (!targetId) return empty;
		// Use user_id:YYYY-MM-DD as the context id since the push payload doesn't
		// carry a workout_id and a user only completes one daily mile per day.
		const localDate = new Date(row.created_at).toISOString().slice(0, 10);
		return {
			hype_target_user_id: targetId,
			hype_context_type: 'mile',
			hype_context_id: `${targetId}:${localDate}`,
			hype_context_label: "today's mile"
		};
	}

	if (row.type === 'friend_badge_earned') {
		const targetId = data.sender_id;
		const badgeId = data.badge_id;
		const badgeName = data.badge_name;
		if (!targetId || !badgeId) return empty;
		return {
			hype_target_user_id: targetId,
			hype_context_type: 'badge',
			hype_context_id: String(badgeId),
			hype_context_label: badgeName ? String(badgeName) : 'a medal'
		};
	}

	if (row.type === 'friend_personal_best') {
		const targetId = data.sender_id;
		const prType = data.pr_type;
		const workoutId = data.workout_id;
		const label = data.pr_label;
		if (!targetId || !prType || !workoutId) return empty;
		return {
			hype_target_user_id: targetId,
			hype_context_type: 'pr',
			hype_context_id: `${prType}:${workoutId}`,
			hype_context_label: label ? String(label) : 'personal best'
		};
	}

	return empty;
}

export async function getInAppNotifications(req: Request, res: Response) {
	try {
		const userId = (req as any).userId;
		const limit = parseInt(req.query.limit as string) || 50;
		const offset = parseInt(req.query.offset as string) || 0;

		const rows = await db.query<any>(
			`SELECT id, title, body, type, data, is_read, created_at
			FROM in_app_notifications
			WHERE user_id = $1
			ORDER BY created_at DESC
			LIMIT $2 OFFSET $3`,
			[userId, limit, offset]
		);

		// Pass 1: derive hype context for each row.
		const derived = rows.map(r => ({ row: r, hype: deriveHypeContext(r) }));

		// Pass 2: batch-query is_hyped for rows that have a context.
		const ctxKeys = derived
			.filter(
				d => d.hype.hype_target_user_id !== null && d.hype.hype_context_type !== null && d.hype.hype_context_id !== null
			)
			.map(d => ({
				targetId: d.hype.hype_target_user_id!,
				type: d.hype.hype_context_type!,
				id: d.hype.hype_context_id!
			}));

		const hypedSet = new Set<string>();
		if (ctxKeys.length > 0) {
			const targetIds = ctxKeys.map(k => k.targetId);
			const types = ctxKeys.map(k => k.type);
			const ids = ctxKeys.map(k => k.id);
			const hyped = await db.query<{ target_id: string; context_type: string; context_id: string }>(
				`SELECT target_id, context_type, context_id
				FROM hype_log
				WHERE sender_id = $1
					AND (target_id, context_type, context_id) IN (
						SELECT * FROM UNNEST($2::text[], $3::text[], $4::text[])
					)`,
				[userId, targetIds, types, ids]
			);
			for (const h of hyped) {
				hypedSet.add(`${h.target_id}|${h.context_type}|${h.context_id}`);
			}
		}

		const notifications = derived.map(({ row, hype }) => {
			const key =
				hype.hype_target_user_id && hype.hype_context_type && hype.hype_context_id
					? `${hype.hype_target_user_id}|${hype.hype_context_type}|${hype.hype_context_id}`
					: null;
			const isHyped = key !== null && hypedSet.has(key);
			return {
				id: row.id,
				title: row.title,
				body: row.body,
				type: row.type,
				data: row.data,
				is_read: row.is_read,
				created_at: row.created_at,
				hype_target_user_id: hype.hype_target_user_id,
				hype_context_type: hype.hype_context_type,
				hype_context_id: hype.hype_context_id,
				hype_context_label: hype.hype_context_label,
				is_hyped: isHyped
			};
		});

		const unreadCount = await db.query(
			`SELECT COUNT(*) as count FROM in_app_notifications
			WHERE user_id = $1 AND is_read = FALSE`,
			[userId]
		);

		res.json({
			notifications,
			unread_count: parseInt(unreadCount[0]?.count ?? '0')
		});
	} catch (error: any) {
		console.error('Error getting in-app notifications:', error.message);
		res.status(500).json({ error: 'Failed to get notifications' });
	}
}

export async function markNotificationRead(req: Request, res: Response) {
	try {
		const userId = (req as any).userId;
		const { notificationId } = req.params;

		await db.query('UPDATE in_app_notifications SET is_read = TRUE WHERE id = $1 AND user_id = $2', [notificationId, userId]);

		res.json({ success: true });
	} catch (error: any) {
		console.error('Error marking notification read:', error.message);
		res.status(500).json({ error: 'Failed to mark notification read' });
	}
}

export async function markAllRead(req: Request, res: Response) {
	try {
		const userId = (req as any).userId;

		await db.query('UPDATE in_app_notifications SET is_read = TRUE WHERE user_id = $1 AND is_read = FALSE', [userId]);

		res.json({ success: true });
	} catch (error: any) {
		console.error('Error marking all notifications read:', error.message);
		res.status(500).json({ error: 'Failed to mark all read' });
	}
}

export async function getUnreadCount(req: Request, res: Response) {
	try {
		const userId = (req as any).userId;

		const result = await db.query(
			'SELECT COUNT(*) as count FROM in_app_notifications WHERE user_id = $1 AND is_read = FALSE',
			[userId]
		);

		res.json({ unread_count: parseInt(result[0]?.count ?? '0') });
	} catch (error: any) {
		console.error('Error getting unread count:', error.message);
		res.status(500).json({ error: 'Failed to get unread count' });
	}
}
