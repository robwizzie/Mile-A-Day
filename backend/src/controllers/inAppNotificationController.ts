import { Request, Response } from 'express';
import { PostgresService } from '../services/DbService.js';

const db = PostgresService.getInstance();

export async function getInAppNotifications(req: Request, res: Response) {
	try {
		const userId = (req as any).userId;
		const limit = parseInt(req.query.limit as string) || 50;
		const offset = parseInt(req.query.offset as string) || 0;

		const notifications = await db.query(
			`SELECT id, title, body, type, data, is_read, created_at
			FROM in_app_notifications
			WHERE user_id = $1
			ORDER BY created_at DESC
			LIMIT $2 OFFSET $3`,
			[userId, limit, offset]
		);

		const unreadCount = await db.query(
			`SELECT COUNT(*) as count FROM in_app_notifications
			WHERE user_id = $1 AND is_read = FALSE`,
			[userId]
		);

		res.json({
			notifications,
			unread_count: parseInt(unreadCount[0]?.count ?? '0'),
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

		await db.query(
			'UPDATE in_app_notifications SET is_read = TRUE WHERE id = $1 AND user_id = $2',
			[notificationId, userId]
		);

		res.json({ success: true });
	} catch (error: any) {
		console.error('Error marking notification read:', error.message);
		res.status(500).json({ error: 'Failed to mark notification read' });
	}
}

export async function markAllRead(req: Request, res: Response) {
	try {
		const userId = (req as any).userId;

		await db.query(
			'UPDATE in_app_notifications SET is_read = TRUE WHERE user_id = $1 AND is_read = FALSE',
			[userId]
		);

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
