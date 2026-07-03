import { createHash } from "node:crypto";
import { existsSync, readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { PostgresService } from "../services/DbService.js";

// Deploys are git-driven with no shell access to the host, so the server owns
// its own schema migrations: at boot, every journal entry not yet recorded in
// drizzle.__drizzle_migrations is applied, before traffic is accepted.
//
// The applier is a statement-level idempotent catch-up, NOT drizzle's strict
// migrator, because production's bookkeeping state is unknowable (it may be
// empty, partial, or current — nobody has ever been able to run `db:migrate`
// there). Each migration runs in a transaction with a savepoint per statement;
// a statement failing with an "already exists" error class is skipped (that
// object predates the bookkeeping), anything else aborts the migration. This
// converges ANY additive-schema state onto the journal without ever touching
// data it shouldn't.
//
// Bookkeeping stays byte-compatible with drizzle-kit migrate (same table, the
// hash is sha256 of the .sql file, created_at is the journal `when`).

// PG error codes meaning "this object already exists" — safe to treat the
// statement as already applied. Anything else is a real failure.
const ALREADY_EXISTS_CODES = new Set([
  "42P07", // duplicate table / index
  "42701", // duplicate column
  "42710", // duplicate object (constraint, extension, ...)
  "42P06", // duplicate schema
  "42723", // duplicate function
]);

interface JournalEntry {
  idx: number;
  when: number;
  tag: string;
}

/** Boot report, exposed via /status/schema so it can be read without host access. */
export interface MigrationReport {
  at: string;
  ok: boolean;
  migrationsDir: string | null;
  journalCount: number;
  alreadyRecorded: number;
  appliedNow: string[];
  skippedStatements: number;
  error: string | null;
}

let lastReport: MigrationReport | null = null;
export function getMigrationReport(): MigrationReport | null {
  return lastReport;
}

function resolveMigrationsDir(): string | null {
  const moduleDir = path.dirname(fileURLToPath(import.meta.url));
  const candidates = [
    path.join(process.cwd(), "src", "db", "drizzle"),
    // dist/db/runMigrations.js → <backend root>/src/db/drizzle
    path.join(moduleDir, "..", "..", "src", "db", "drizzle"),
    path.join(moduleDir, "..", "..", "..", "src", "db", "drizzle"),
  ];
  for (const dir of candidates) {
    if (existsSync(path.join(dir, "meta", "_journal.json"))) return dir;
  }
  return null;
}

/**
 * Apply pending migrations. Returns true when the schema is up to date.
 * Never throws — failures are logged loudly and captured in the boot report,
 * and the server still starts (endpoints not touching new columns keep
 * working; crashing the process would take those down too).
 */
export async function runPendingMigrations(): Promise<boolean> {
  const report: MigrationReport = {
    at: new Date().toISOString(),
    ok: false,
    migrationsDir: null,
    journalCount: 0,
    alreadyRecorded: 0,
    appliedNow: [],
    skippedStatements: 0,
    error: null,
  };
  lastReport = report;

  try {
    const dir = resolveMigrationsDir();
    if (!dir) {
      report.error = "migrations folder not found (src/db/drizzle)";
      console.error(`[migrations] ❌ ${report.error}`);
      return false;
    }
    report.migrationsDir = dir;

    const db = PostgresService.getInstance();

    await db.query(`CREATE SCHEMA IF NOT EXISTS "drizzle"`);
    await db.query(
      `CREATE TABLE IF NOT EXISTS "drizzle"."__drizzle_migrations" (
				id SERIAL PRIMARY KEY,
				hash text NOT NULL,
				created_at bigint
			)`,
    );

    const journal = JSON.parse(
      readFileSync(path.join(dir, "meta", "_journal.json"), "utf8"),
    ) as { entries: JournalEntry[] };
    const entries = [...journal.entries].sort((a, b) => a.idx - b.idx);
    report.journalCount = entries.length;

    const recorded = new Set(
      (
        await db.query<{ hash: string }>(
          `SELECT hash FROM "drizzle"."__drizzle_migrations"`,
        )
      ).map((r) => r.hash),
    );

    for (const entry of entries) {
      const sql = readFileSync(path.join(dir, `${entry.tag}.sql`), "utf8");
      const hash = createHash("sha256").update(sql).digest("hex");
      if (recorded.has(hash)) {
        report.alreadyRecorded++;
        continue;
      }

      const skipped = await applyMigration(db, entry.tag, sql);
      report.skippedStatements += skipped;
      await db.query(
        `INSERT INTO "drizzle"."__drizzle_migrations" ("hash", "created_at") VALUES ($1, $2)`,
        [hash, entry.when],
      );
      report.appliedNow.push(entry.tag);
      console.log(
        `[migrations] ✓ ${entry.tag}${skipped > 0 ? ` (${skipped} statement(s) already existed)` : ""}`,
      );
    }

    report.ok = true;
    console.log(
      report.appliedNow.length > 0
        ? `[migrations] ✅ Applied ${report.appliedNow.length} migration(s): ${report.appliedNow.join(", ")}`
        : "[migrations] ✅ Schema is up to date",
    );
    return true;
  } catch (err: any) {
    report.error = String(err?.message ?? err);
    console.error(
      "[migrations] ❌ FAILED — schema may be behind the code:",
      report.error,
    );
    return false;
  }
}

/**
 * Run one migration's statements in a single transaction, with a savepoint
 * around each statement so "already exists" failures can be skipped without
 * aborting the rest. Returns the number of skipped statements.
 */
async function applyMigration(
  db: PostgresService,
  tag: string,
  sql: string,
): Promise<number> {
  const statements = sql
    .split("--> statement-breakpoint")
    .map((s) => s.trim())
    .filter((s) => s.length > 0);

  let skipped = 0;
  const client = await db.getClient();
  try {
    await client.query("BEGIN");
    for (const statement of statements) {
      await client.query("SAVEPOINT mig_stmt");
      try {
        await client.query(statement);
      } catch (err: any) {
        if (err?.code && ALREADY_EXISTS_CODES.has(err.code)) {
          await client.query("ROLLBACK TO SAVEPOINT mig_stmt");
          skipped++;
          console.log(
            `[migrations]   • ${tag}: skipped already-existing object (${err.code}): ${statement.slice(0, 80).replace(/\s+/g, " ")}…`,
          );
        } else {
          throw err;
        }
      }
      await client.query("RELEASE SAVEPOINT mig_stmt");
    }
    await client.query("COMMIT");
  } catch (err) {
    await client.query("ROLLBACK");
    throw err;
  } finally {
    client.release();
  }
  return skipped;
}
