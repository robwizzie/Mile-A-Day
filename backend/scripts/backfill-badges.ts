import 'dotenv/config';
import { PostgresService } from '../src/services/DbService.js';
import { evaluateForUser } from '../src/services/badgeService.js';

const db = PostgresService.getInstance();

async function main() {
	const users = await db.query<{ user_id: string; username: string | null }>(
		`SELECT user_id, username FROM users ORDER BY user_id ASC`
	);
	console.log(`[backfill] starting for ${users.length} users`);

	let totalBadges = 0;
	let processed = 0;
	let errors = 0;

	for (const { user_id, username } of users) {
		try {
			const { newlyEarnedBadges } = await evaluateForUser(user_id, []);
			if (newlyEarnedBadges.length > 0) {
				console.log(
					`[backfill] ${username ?? user_id}: +${newlyEarnedBadges.length} ` +
						`(${newlyEarnedBadges.map(b => b.badgeId).join(', ')})`
				);
			}
			totalBadges += newlyEarnedBadges.length;
			processed++;
		} catch (err: any) {
			errors++;
			console.error(`[backfill] ${username ?? user_id} failed:`, err.message);
		}
	}

	console.log(`[backfill] done — ${processed}/${users.length} users, ${totalBadges} badges awarded, ${errors} errors`);
	await db.close();
}

main().catch(err => {
	console.error('[backfill] fatal:', err);
	process.exit(1);
});
