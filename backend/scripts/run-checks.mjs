#!/usr/bin/env node
// `npm run check` — the backend CI job, locally.
//
// The step list is PARSED from .github/workflows/ci.yml (the backend job's
// `run: node …` / `run: npx drizzle-kit …` lines, in file order), so adding a
// check to CI adds it here and the two cannot drift. Order is CI's: build,
// drizzle check, migrator twice, ci-smoke, then every *-check.mjs.
//
// Usage (from backend/):
//   npm run check                              # against $DATABASE_URL (must be local)
//   npm run check -- --ephemeral-db            # throwaway Homebrew Postgres, torn down after
//   npm run check -- --ephemeral-db --port 54332
//   npm run check -- --only streak-check       # repeatable / comma-separated
//   npm run check -- --from buddy-live-check   # resume from a step
//   npm run check -- --no-build --no-migrate --bail --list
//
// --only/--from match a step's id (script basename: `ci-smoke`, `streak-check`,
// `migrate`, `migrate-rerun`, `drizzle-check`) or, failing that, a substring of
// its CI step name. The migrator is setup, so it still runs under --only/--from
// unless --no-migrate. Every check SEEDS and DELETES rows, so a non-ephemeral
// run refuses any DATABASE_URL that isn't localhost unless --allow-remote-db.
import { spawnSync, spawn } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const BACKEND = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const CI_YML = path.resolve(BACKEND, "..", ".github", "workflows", "ci.yml");

// ---------------------------------------------------------------------------
// Args
// ---------------------------------------------------------------------------
const argv = process.argv.slice(2);
const opts = {
  only: [],
  from: null,
  ephemeral: false,
  port: 54329,
  build: true,
  migrate: true,
  bail: false,
  list: false,
  allowRemote: false,
};
for (let i = 0; i < argv.length; i++) {
  const a = argv[i];
  const next = () => {
    const v = argv[++i];
    if (v === undefined) die(`${a} needs a value`);
    return v;
  };
  if (a === "--only") opts.only.push(...next().split(",").filter(Boolean));
  else if (a === "--from") opts.from = next();
  else if (a === "--ephemeral-db") opts.ephemeral = true;
  else if (a === "--port") opts.port = Number(next());
  else if (a === "--no-build") opts.build = false;
  else if (a === "--no-migrate") opts.migrate = false;
  else if (a === "--bail") opts.bail = true;
  else if (a === "--list") opts.list = true;
  else if (a === "--allow-remote-db") opts.allowRemote = true;
  else if (a === "-h" || a === "--help") {
    console.log(fs.readFileSync(fileURLToPath(import.meta.url), "utf8").split("\nimport ")[0]);
    process.exit(0);
  } else die(`unknown argument: ${a}`);
}

function die(msg) {
  console.error(`run-checks: ${msg}`);
  process.exit(2);
}

// ---------------------------------------------------------------------------
// Parse ci.yml's backend job
// ---------------------------------------------------------------------------
function parseCiSteps() {
  const lines = fs.readFileSync(CI_YML, "utf8").split("\n");
  const start = lines.findIndex((l) => /^ {2}backend:\s*$/.test(l));
  if (start < 0) die(`no \`backend:\` job in ${CI_YML}`);
  let end = lines.length;
  for (let i = start + 1; i < lines.length; i++) {
    if (/^ {2}\S[^:]*:\s*$/.test(lines[i])) {
      end = i;
      break;
    }
  }
  const steps = [];
  let pendingName = null;
  for (const line of lines.slice(start, end)) {
    const name = line.match(/^\s+- name:\s*(.+?)\s*$/);
    if (name) {
      pendingName = name[1];
      continue;
    }
    const run = line.match(/^\s+(?:- )?run:\s*(.+?)\s*$/);
    if (run) {
      steps.push({ name: pendingName, command: run[1] });
      pendingName = null;
    } else if (/^\s+- /.test(line)) {
      pendingName = null;
    }
  }
  const out = [];
  let migrateSeen = 0;
  for (const s of steps) {
    const cmd = s.command;
    let m;
    if (/^node dist\/db\/migrateCli\.js$/.test(cmd)) {
      out.push({
        id: migrateSeen++ === 0 ? "migrate" : "migrate-rerun",
        name: s.name ?? cmd,
        argv: ["node", "dist/db/migrateCli.js"],
        kind: "migrate",
      });
    } else if ((m = cmd.match(/^node (scripts\/[\w.-]+\.mjs)$/))) {
      out.push({
        id: path.basename(m[1], ".mjs"),
        name: s.name ?? cmd,
        argv: ["node", m[1]],
        kind: "check",
      });
    } else if (/^npx drizzle-kit check$/.test(cmd)) {
      out.push({ id: "drizzle-check", name: s.name ?? cmd, argv: ["npx", "drizzle-kit", "check"], kind: "check" });
    }
    // npm ci / npm run build (handled by --build) / psql pg_trgm (handled by
    // setup) are CI plumbing, not checks.
  }
  if (!out.some((s) => s.kind === "migrate")) die("ci.yml has no migrator step — parser out of date?");
  if (!out.some((s) => s.id === "ci-smoke")) die("ci.yml has no ci-smoke step — parser out of date?");
  return out;
}

const allSteps = parseCiSteps();

function matches(step, needle) {
  const n = needle.toLowerCase().replace(/\.mjs$/, "");
  if (step.id === n) return true;
  return step.id.includes(n) || (step.name ?? "").toLowerCase().includes(n);
}

let selected = allSteps.filter((s) => s.kind !== "migrate");
if (opts.from) {
  const i = selected.findIndex((s) => matches(s, opts.from));
  if (i < 0) die(`--from ${opts.from}: no such step (try --list)`);
  selected = selected.slice(i);
}
if (opts.only.length) {
  selected = selected.filter((s) => opts.only.some((n) => matches(s, n)));
  if (!selected.length) die(`--only ${opts.only.join(",")}: no such step (try --list)`);
}
const migrations = opts.migrate ? allSteps.filter((s) => s.kind === "migrate") : [];
// Keep CI order: drizzle check sits before the migrator there.
const plan = [
  ...selected.filter((s) => s.id === "drizzle-check"),
  ...migrations,
  ...selected.filter((s) => s.id !== "drizzle-check"),
];

if (opts.list) {
  for (const s of allSteps) console.log(`${s.id.padEnd(40)} ${s.name}`);
  process.exit(0);
}

// ---------------------------------------------------------------------------
// Database
// ---------------------------------------------------------------------------
let teardown = () => {};

function sh(cmd, args, extra = {}) {
  const r = spawnSync(cmd, args, { encoding: "utf8", ...extra });
  if (r.error || r.status !== 0) {
    throw new Error(`${cmd} ${args.join(" ")} failed:\n${r.stderr || r.stdout || r.error}`);
  }
  return r.stdout;
}

function startEphemeralDb() {
  for (const bin of ["initdb", "pg_ctl", "createdb", "psql"]) {
    if (spawnSync("which", [bin]).status !== 0) {
      die(`--ephemeral-db needs \`${bin}\` on PATH (brew install postgresql@16)`);
    }
  }
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "mad-checks-"));
  const pgdata = path.join(dir, "pgdata");
  const port = String(opts.port);
  console.log(`[db] ephemeral Postgres in ${dir} on 127.0.0.1:${port}`);
  sh("initdb", ["-D", pgdata, "-U", "postgres", "--auth=trust", "-E", "UTF8"]);
  let started = false;
  teardown = () => {
    if (started) {
      spawnSync("pg_ctl", ["-D", pgdata, "-m", "fast", "-w", "stop"], { stdio: "ignore" });
      started = false;
    }
    fs.rmSync(dir, { recursive: true, force: true });
    console.log("[db] ephemeral Postgres stopped and removed");
    teardown = () => {};
  };
  // -k /tmp: a temp path easily exceeds the 103-byte Unix socket limit.
  sh("pg_ctl", [
    "-D", pgdata, "-w", "-l", path.join(dir, "postgres.log"),
    "-o", `-p ${port} -k /tmp -c listen_addresses=127.0.0.1 -c timezone=UTC -c log_timezone=UTC`,
    "start",
  ]);
  started = true;
  sh("createdb", ["-h", "127.0.0.1", "-p", port, "-U", "postgres", "mad_ci"]);
  return {
    DATABASE_URL: `postgres://postgres@127.0.0.1:${port}/mad_ci`,
    APP_JWT_SECRET: "ci-secret",
    MEDIA_SIGNING_SECRET: "ci-media-secret",
  };
}

function cleanupAndExit(code) {
  try {
    teardown();
  } finally {
    process.exit(code);
  }
}
process.on("SIGINT", () => cleanupAndExit(130));
process.on("SIGTERM", () => cleanupAndExit(143));

let dbEnv;
try {
  if (opts.ephemeral) {
    dbEnv = startEphemeralDb();
  } else {
    const url = process.env.DATABASE_URL;
    if (!url) die("DATABASE_URL is not set (or pass --ephemeral-db)");
    const host = (() => {
      try {
        return new URL(url).hostname;
      } catch {
        return "";
      }
    })();
    if (!["localhost", "127.0.0.1", "::1", "[::1]", ""].includes(host) && !opts.allowRemote) {
      die(
        `refusing to run against ${host}: every check seeds and DELETES rows. ` +
          "Use --ephemeral-db, or --allow-remote-db if this really is a throwaway database.",
      );
    }
    dbEnv = {
      DATABASE_URL: url,
      APP_JWT_SECRET: process.env.APP_JWT_SECRET ?? "ci-secret",
      MEDIA_SIGNING_SECRET: process.env.MEDIA_SIGNING_SECRET ?? "ci-media-secret",
    };
  }
} catch (err) {
  console.error(`[db] setup failed: ${err.message}`);
  cleanupAndExit(1);
}

// CI runs in UTC (runner and the postgres:16 service alike). Several checks
// seed "today" / "10 PM local" against the wall clock, and last-call-check and
// ci-smoke's stealth-window section fail on a machine sitting in
// America/New_York — so every step runs in UTC, as CI does.
const env = { ...process.env, ...dbEnv, TZ: "UTC" };

// ---------------------------------------------------------------------------
// Run
// ---------------------------------------------------------------------------
function runStep(argvList) {
  return new Promise((resolve) => {
    const child = spawn(argvList[0], argvList.slice(1), { cwd: BACKEND, env, stdio: "inherit" });
    child.on("close", (code, signal) => resolve(signal ? 1 : code ?? 1));
    child.on("error", () => resolve(1));
  });
}

async function ensureTrgm() {
  // Migration 0000 uses gin_trgm_ops; CI creates the extension as a step.
  const { default: pg } = await import("pg");
  const client = new pg.Client({ connectionString: env.DATABASE_URL });
  await client.connect();
  try {
    await client.query("CREATE EXTENSION IF NOT EXISTS pg_trgm");
  } finally {
    await client.end();
  }
}

const results = [];
const fmt = (ms) => (ms < 1000 ? `${ms}ms` : `${(ms / 1000).toFixed(1)}s`);

async function record(id, name, fn, { fatal = false } = {}) {
  console.log(`\n▶ ${id}${name && name !== id ? `  (${name})` : ""}`);
  const t0 = Date.now();
  const code = await fn();
  const ms = Date.now() - t0;
  results.push({ id, ok: code === 0, ms });
  console.log(`${code === 0 ? "✔" : "✘"} ${id} ${fmt(ms)}`);
  if (code !== 0 && (fatal || opts.bail)) return false;
  return true;
}

const t0 = Date.now();
let proceed = true;
if (opts.build) {
  proceed = await record("build", "npm run build", () => runStep(["npm", "run", "build"]), { fatal: true });
} else if (!fs.existsSync(path.join(BACKEND, "dist", "db", "migrateCli.js"))) {
  console.error("run-checks: dist/ is missing — run without --no-build");
  cleanupAndExit(2);
}
if (proceed && migrations.length) {
  proceed = await record("pg_trgm", "CREATE EXTENSION pg_trgm", async () => {
    try {
      await ensureTrgm();
      return 0;
    } catch (err) {
      console.error(err.message);
      return 1;
    }
  }, { fatal: true });
}
for (const step of plan) {
  if (!proceed) break;
  proceed = await record(step.id, step.name, () => runStep(step.argv), {
    fatal: step.kind === "migrate",
  });
}

// ---------------------------------------------------------------------------
// Summary
// ---------------------------------------------------------------------------
const ran = new Set(results.map((r) => r.id));
const skipped = plan.filter((s) => !ran.has(s.id)).map((s) => s.id);
console.log("\n──────── summary ────────");
for (const r of results) console.log(`${r.ok ? "PASS" : "FAIL"}  ${fmt(r.ms).padStart(7)}  ${r.id}`);
for (const id of skipped) console.log(`SKIP           ${id}`);
const failed = results.filter((r) => !r.ok);
console.log(
  `\n${results.length - failed.length}/${results.length} passed` +
    (skipped.length ? `, ${skipped.length} not run` : "") +
    ` in ${fmt(Date.now() - t0)}`,
);
cleanupAndExit(failed.length || skipped.length ? 1 : 0);
