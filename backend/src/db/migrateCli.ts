import "dotenv/config";
import { runPendingMigrations, getMigrationReport } from "./runMigrations.js";
import { PostgresService } from "../services/DbService.js";

// Container-entrypoint migration step (replaces strict `drizzle-kit migrate`).
// Uses the same statement-level idempotent applier as the in-server safety
// net, so it converges ANY bookkeeping state instead of dying on objects that
// already exist — a dead entrypoint means Coolify silently keeps the OLD
// container serving, which is how a broken schema stayed live for hours.
// Exit code still gates the deploy: 0 = schema converged, 1 = real failure
// (Coolify then keeps the previous healthy container — the safe outcome).
const ok = await runPendingMigrations();
console.log(
  "[migrate-cli] report:",
  JSON.stringify(getMigrationReport(), null, 2),
);
await PostgresService.getInstance().close();
process.exit(ok ? 0 : 1);
