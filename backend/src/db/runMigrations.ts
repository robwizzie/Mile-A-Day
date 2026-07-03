import { createHash } from "node:crypto";
import { existsSync, readFileSync } from "node:fs";
import path from "node:path";
import { migrate } from "drizzle-orm/node-postgres/migrator";
import { PostgresService } from "../services/DbService.js";

// Deploys are git-driven with no shell access to the host, so the server owns
// its own schema migrations: any journal entry not yet recorded in
// drizzle.__drizzle_migrations is applied at boot, before traffic is accepted.
// Idempotent — an already-migrated database is a fast no-op.
const MIGRATIONS_DIR = path.join(process.cwd(), "src", "db", "drizzle");

/**
 * Mirror of scripts/drizzle-baseline.mjs, run automatically when the
 * bookkeeping table is empty: the `0000` migration is the introspection
 * snapshot of the schema that ALREADY exists in production — record it as
 * applied (never execute it) so the migrator starts from `0001`.
 */
async function baselineIfNeeded(db: PostgresService): Promise<void> {
  await db.query(`CREATE SCHEMA IF NOT EXISTS "drizzle"`);
  await db.query(
    `CREATE TABLE IF NOT EXISTS "drizzle"."__drizzle_migrations" (
			id SERIAL PRIMARY KEY,
			hash text NOT NULL,
			created_at bigint
		)`,
  );

  const applied = await db.query<{ count: string }>(
    `SELECT COUNT(*)::text AS count FROM "drizzle"."__drizzle_migrations"`,
  );
  if (parseInt(applied[0]?.count ?? "0", 10) > 0) return;

  const journal = JSON.parse(
    readFileSync(path.join(MIGRATIONS_DIR, "meta", "_journal.json"), "utf8"),
  ) as { entries: { idx: number; when: number; tag: string }[] };
  const baseline = journal.entries.find((e) => e.idx === 0);
  if (!baseline) return;

  const sql = readFileSync(
    path.join(MIGRATIONS_DIR, `${baseline.tag}.sql`),
    "utf8",
  );
  const hash = createHash("sha256").update(sql).digest("hex");
  await db.query(
    `INSERT INTO "drizzle"."__drizzle_migrations" ("hash", "created_at") VALUES ($1, $2)`,
    [hash, baseline.when],
  );
  console.log(
    `[migrations] Baselined ${baseline.tag} (recorded as applied, not executed)`,
  );
}

/**
 * Apply pending migrations. Returns true when the schema is up to date.
 * Never throws — a failure is logged loudly and the server still boots
 * (endpoints not touching new columns keep working; crashing the process
 * would take those down too).
 */
export async function runPendingMigrations(): Promise<boolean> {
  try {
    if (!existsSync(MIGRATIONS_DIR)) {
      console.error(
        `[migrations] ❌ Migrations folder missing at ${MIGRATIONS_DIR} — deploy must include src/db/drizzle`,
      );
      return false;
    }
    const db = PostgresService.getInstance();
    await baselineIfNeeded(db);
    await migrate(db.orm, { migrationsFolder: MIGRATIONS_DIR });
    console.log("[migrations] ✅ Schema is up to date");
    return true;
  } catch (err: any) {
    console.error(
      "[migrations] ❌ FAILED — schema may be behind the code:",
      err?.message ?? err,
    );
    return false;
  }
}
