// One-time baseline for adopting Drizzle migrations on an EXISTING database.
//
// The `0000` migration is the snapshot produced by `drizzle-kit pull` — it
// describes the schema that ALREADY exists in production. Running it would
// `CREATE TABLE` over live tables and fail. Instead we record it as
// already-applied in Drizzle's bookkeeping table, so future `drizzle-kit migrate`
// runs start from `0001` and never touch the existing schema.
//
// This mirrors drizzle-orm's migrator exactly: the migration hash is the
// SHA-256 of the full .sql file contents; bookkeeping lives in
// drizzle.__drizzle_migrations (hash text, created_at bigint).
//
// Idempotent: re-running skips migrations already recorded. Safe + additive —
// it creates one schema + one tracking table and inserts one row. It does NOT
// read, alter, or delete any application data.
//
// Usage (from backend/):  node scripts/drizzle-baseline.mjs
// By default it baselines ONLY migration idx 0 (the introspection snapshot).

import 'dotenv/config';
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import pg from 'pg';

const __dirname = dirname(fileURLToPath(import.meta.url));
const MIGRATIONS_DIR = join(__dirname, '..', 'src', 'db', 'drizzle');

// Only the introspection snapshot is part of the baseline. Anything newer is a
// real migration that must run normally via `drizzle-kit migrate`.
const BASELINE_THROUGH_IDX = 0;

const journal = JSON.parse(readFileSync(join(MIGRATIONS_DIR, 'meta', '_journal.json'), 'utf8'));
const entries = journal.entries.filter(e => e.idx <= BASELINE_THROUGH_IDX);

if (!entries.length) {
	console.error('No journal entries to baseline. Did you run `npm run db:pull` first?');
	process.exit(1);
}

const pool = new pg.Pool({ connectionString: process.env.DATABASE_URL });

try {
	await pool.query('CREATE SCHEMA IF NOT EXISTS "drizzle"');
	await pool.query(
		`CREATE TABLE IF NOT EXISTS "drizzle"."__drizzle_migrations" (
			id SERIAL PRIMARY KEY,
			hash text NOT NULL,
			created_at bigint
		)`
	);

	for (const entry of entries) {
		const sql = readFileSync(join(MIGRATIONS_DIR, `${entry.tag}.sql`), 'utf8');
		const hash = createHash('sha256').update(sql).digest('hex');

		const existing = await pool.query('SELECT 1 FROM "drizzle"."__drizzle_migrations" WHERE hash = $1', [hash]);
		if (existing.rowCount > 0) {
			console.log(`• ${entry.tag} already recorded — skipping`);
			continue;
		}

		await pool.query('INSERT INTO "drizzle"."__drizzle_migrations" ("hash", "created_at") VALUES ($1, $2)', [hash, entry.when]);
		console.log(`✓ Baselined ${entry.tag} (recorded as applied, NOT executed)`);
	}

	console.log('\nDone. `npm run db:migrate` will now start from the next migration.');
} catch (err) {
	console.error('Baseline failed:', err);
	process.exitCode = 1;
} finally {
	await pool.end();
}
