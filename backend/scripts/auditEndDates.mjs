// One-off audit: find finished competitions whose live-recomputed standings drift
// from the frozen competition_users.placement — the signature of the end_date
// off-by-one bug (early-resolved comps stamped end_date = resolution day).
import 'dotenv/config';
import pg from 'pg';
import { getCompetition } from '../dist/services/competitionService.js';

const pool = new pg.Pool({ connectionString: process.env.DATABASE_URL });

const { rows: comps } = await pool.query(
	`SELECT id, competition_name, type, start_date, end_date, winner
	 FROM competitions
	 WHERE ended = true AND winner IS NOT NULL AND start_date IS NOT NULL`
);

let affected = 0;
for (const c of comps) {
	const live = await getCompetition(c.id); // merges live getUserScores into users
	const { rows: frozen } = await pool.query(`SELECT user_id, placement FROM competition_users WHERE competition_id = $1`, [
		c.id
	]);
	const frozenMap = new Map(frozen.map(r => [r.user_id, r.placement]));

	// Re-rank from live scores (same tie logic as resolveCompetitionPlacements).
	const accepted = (live.users || []).filter(u => u.invite_status === 'accepted');
	const sorted = [...accepted].sort((a, b) => (b.score ?? 0) - (a.score ?? 0));
	let place = 1;
	const drift = [];
	for (let i = 0; i < sorted.length; i++) {
		if (i > 0 && (sorted[i].score ?? 0) < (sorted[i - 1].score ?? 0)) place = i + 1;
		const fp = frozenMap.get(sorted[i].user_id);
		if (fp !== place) {
			drift.push(`${sorted[i].username}: frozen #${fp} -> live #${place} (score ${sorted[i].score})`);
		}
	}
	if (drift.length) {
		affected++;
		console.log(`\n⚠️  ${c.competition_name} [${c.type}] ${c.start_date}..${c.end_date} (${c.id})`);
		drift.forEach(d => console.log(`    ${d}`));
	}
}

console.log(`\nScanned ${comps.length} finished competitions; ${affected} show placement drift.`);
await pool.end();
