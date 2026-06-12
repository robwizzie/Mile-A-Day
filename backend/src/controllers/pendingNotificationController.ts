import { Response } from 'express';
import { AuthenticatedRequest } from '../middleware/auth.js';
import { listPending, sendPending, dismissPending, dismissAllPending } from '../services/pendingNotificationService.js';

// ─── Helpers ──────────────────────────────────────────────────────────

/** Validate that a route :id param is a numeric bigint string. */
function parseId(raw: string): string | null {
	return /^\d+$/.test(raw) ? raw : null;
}

// ─── GET /notifications/pending ───────────────────────────────────────

export async function getPendingNotifications(req: AuthenticatedRequest, res: Response) {
	try {
		const rows = await listPending(req.userId!);
		res.status(200).json({ pending: rows });
	} catch (err: any) {
		console.error('[PendingNotif] Error listing pending:', err.message);
		res.status(500).json({ error: 'Error fetching pending notifications' });
	}
}

// ─── POST /notifications/pending/:id/send ────────────────────────────

export async function sendPendingNotification(req: AuthenticatedRequest, res: Response) {
	const id = parseId(req.params.id);
	if (!id) return res.status(400).json({ error: 'Invalid notification id' });

	const { audience } = req.body ?? {};
	if (audience !== undefined && audience !== 'close' && audience !== 'all') {
		return res.status(400).json({ error: 'audience must be "close" or "all"' });
	}

	try {
		const result = await sendPending(req.userId!, id, audience ?? 'all');
		if (!result.ok) {
			if (result.reason === 'not_found') return res.status(404).json({ error: 'Pending notification not found' });
			if (result.reason === 'not_owner') return res.status(403).json({ error: 'Forbidden' });
			if (result.reason === 'expired')
				return res.status(410).json({ error: 'Notification expired — same-day window has passed' });
			if (result.reason === 'already_processed')
				return res.status(409).json({ error: 'Notification already sent or dismissed' });
			if (result.reason === 'audience_blocked')
				return res.status(409).json({ error: "Your current settings don't allow sending this notification" });
		}
		res.status(200).json({ sent: (result as any).sent });
	} catch (err: any) {
		console.error('[PendingNotif] Error sending pending:', err.message);
		res.status(500).json({ error: 'Error sending pending notification' });
	}
}

// ─── DELETE /notifications/pending/:id ───────────────────────────────

export async function deletePendingNotification(req: AuthenticatedRequest, res: Response) {
	const id = parseId(req.params.id);
	if (!id) return res.status(400).json({ error: 'Invalid notification id' });

	try {
		const result = await dismissPending(req.userId!, id);
		if (!result.ok) {
			if (result.reason === 'not_found') return res.status(404).json({ error: 'Pending notification not found' });
			if (result.reason === 'not_owner') return res.status(403).json({ error: 'Forbidden' });
			if (result.reason === 'already_processed')
				return res.status(409).json({ error: 'Notification already sent or dismissed' });
		}
		res.status(200).json({ ok: true });
	} catch (err: any) {
		console.error('[PendingNotif] Error dismissing pending:', err.message);
		res.status(500).json({ error: 'Error dismissing pending notification' });
	}
}

// ─── DELETE /notifications/pending ───────────────────────────────────

export async function deleteAllPendingNotifications(req: AuthenticatedRequest, res: Response) {
	try {
		const result = await dismissAllPending(req.userId!);
		res.status(200).json({ dismissed: result.dismissed });
	} catch (err: any) {
		console.error('[PendingNotif] Error dismissing all pending:', err.message);
		res.status(500).json({ error: 'Error dismissing pending notifications' });
	}
}
