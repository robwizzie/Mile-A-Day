/**
 * Overseer tools on the admin connector (src/mcp/runPlanTools.ts, spec §11).
 *
 * Drives the REAL tool handlers through the MCP SDK (in-memory transport, the
 * same registerRunPlanTools the /mcp server registers; mcp-check covers the
 * sign-in in front of them and that they're listed there):
 *   - a non-admin caller is refused by every tool, nothing written
 *   - a read-only sign-in can't call the write tools
 *   - set_plan refuses without confirmed_in_chat: true, without a summary,
 *     and on another user's plan; with all three it applies to the admin's
 *     own plan and the history keeps the summary
 *   - propose_plan_change creates a PENDING overseer proposal and leaves the
 *     user's days untouched; hard-rule violations come back with details
 *   - review_note is saved (source overseer) and listed for the Coach tab
 *   - get_coach_calls returns the full input/output; every call is audited
 *
 * Usage: npm run build && DATABASE_URL=... node scripts/overseer-check.mjs
 */
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { InMemoryTransport } from "@modelcontextprotocol/sdk/inMemory.js";
import { PostgresService } from "../dist/services/DbService.js";
import { registerRunPlanTools, RUN_PLAN_TOOL_NAMES } from "../dist/mcp/runPlanTools.js";
import * as S from "../dist/services/runPlans/runPlanService.js";
import * as E from "../dist/services/runPlans/engine.js";
import * as Admin from "../dist/services/runPlans/adminCoachService.js";
import { recordAiCall } from "../dist/services/runPlans/coachSettings.js";
import { FOUNDING_CUTOFF } from "../dist/services/plusCatalog.js";

const db = PostgresService.getInstance();
let failures = 0;
function check(label, actual, expected) {
  const ok = JSON.stringify(actual) === JSON.stringify(expected);
  if (!ok) failures++;
  console.log(`${ok ? "ok  " : "FAIL"}  ${label} → ${JSON.stringify(actual)}${ok ? "" : ` (expected ${JSON.stringify(expected)})`}`);
}

const ADMIN = "ovs-admin-user";
const RUNNER = "ovs-runner-user";
const MAL = "ovs-mal-user"; // on no list, role user
const ALL = [ADMIN, RUNNER, MAL];
const today = new Date().toISOString().slice(0, 10);
const PROFILE = { weekly_miles_4w: 15, longest_run_30d_mi: 6, has_hr: true, max_hr: 189, resting_hr: 58, vdot: 40, experience: "experienced", typical_run_hour: 18 };

async function cleanup() {
  await db.query(`DELETE FROM mcp_audit_log WHERE user_id = ANY($1)`, [ALL]);
  await db.query(`DELETE FROM coach_review_notes WHERE author_id = ANY($1) OR user_id = ANY($1)`, [ALL]);
  await db.query(`DELETE FROM coach_ai_calls WHERE user_id = ANY($1)`, [ALL]);
  await db.query(`DELETE FROM coach_settings WHERE user_id = ANY($1)`, [ALL]);
  await db.query(`DELETE FROM run_plans WHERE user_id = ANY($1)`, [ALL]);
  await db.query(`DELETE FROM run_fitness_profiles WHERE user_id = ANY($1)`, [ALL]);
  await db.query(`DELETE FROM plus_purchases WHERE user_id = ANY($1)`, [ALL]);
  await db.query(`DELETE FROM users WHERE user_id = ANY($1)`, [ALL]);
}

/** One connector session as `userId` with these scopes. */
async function connect(userId, scopes = ["db:read", "db:write"]) {
  const server = new McpServer({ name: "overseer-check", version: "1" });
  registerRunPlanTools(server, { userId, grantId: "00000000-0000-4000-8000-000000000000" }, (s) => scopes.includes(s));
  const [a, b] = InMemoryTransport.createLinkedPair();
  await server.connect(a);
  const client = new Client({ name: "overseer-check", version: "1" });
  await client.connect(b);
  return {
    names: async () => (await client.listTools()).tools.map((t) => t.name).sort(),
    describe: async (name) => (await client.listTools()).tools.find((t) => t.name === name)?.description ?? "",
    call: async (name, args = {}) => {
      const r = await client.callTool({ name, arguments: args });
      const text = r.content?.[0]?.text ?? "";
      let json = null;
      try { json = JSON.parse(text); } catch {}
      return { isError: r.isError === true, text, json };
    },
    close: async () => { await client.close(); await server.close(); },
  };
}

const daysOf = async (uid) =>
  JSON.stringify(await db.query(`SELECT d.local_date::text, d.version, d.day FROM run_plan_days d JOIN run_plans p ON p.plan_id = d.plan_id WHERE p.user_id = $1 AND p.status = 'active' ORDER BY 1`, [uid]));
const pickDay = async (uid) => (await S.getDays(uid, E.addDays(today, 2), E.addDays(today, 9), today)).find((d) => d.kind !== "walk" && d.kind !== "race");
const easyFor = (d) => ({ local_date: d.local_date, day: { kind: "easy", distance_mi: Math.max(1, Math.min(d.distance_mi, 4)) } });

async function main() {
  await cleanup();
  const afterCutoff = new Date(Date.parse(FOUNDING_CUTOFF) + 86_400_000).toISOString();
  for (const id of ALL) {
    await db.query(`INSERT INTO users (user_id, apple_sub, email, username, first_name, created_at, role) VALUES ($1::text, $1::text, $1::text || '@example.com', $1::text, 'OV', GREATEST(now(), $2::timestamptz), $3)`, [id, afterCutoff, id === ADMIN ? "admin" : "user"]);
  }
  for (const id of [ADMIN, RUNNER]) {
    await db.query(
      `INSERT INTO plus_purchases (original_transaction_id, user_id, product_id, transaction_id, kind, ownership, environment, purchased_at)
       VALUES ($1, $2, 'mad_plus_lifetime', $1, 'lifetime', 'PURCHASED', 'Sandbox', now())`,
      [`ovs-tx-${id}`, id],
    );
    await S.putProfile(id, PROFILE, today);
    await S.createPlan(id, { goals: [{ type: "distance_time", distance: "5k" }], runs_per_week: 4, difficulty: 3, walk_mode: "built_in" }, today);
  }
  const callId = await recordAiCall(RUNNER, { provider: "anthropic", kind: "adjust", trigger: "nightly", model: "claude-sonnet-5-5", latency_ms: 1200, tokens_in: 900, tokens_out: 300, cost_usd: 0.004, input: "INPUT-" + "x".repeat(2000) + "-END", output: "OUTPUT-full-text-END" });

  const admin = await connect(ADMIN);
  console.log("\n— tools");
  check("six run-plan tools registered", await admin.names(), RUN_PLAN_TOOL_NAMES);
  check("set_plan tells Claude to get an explicit yes in the chat first", /MUST show the admin, in the chat, the exact change/.test(await admin.describe("set_plan")), true);

  console.log("\n— a non-admin is refused by every tool, nothing written");
  const mal = await connect(MAL);
  const runnerDays = await daysOf(RUNNER);
  const d0 = await pickDay(RUNNER);
  const malCalls = {
    list_run_plans: {},
    get_run_plan_detail: { user: RUNNER },
    get_coach_calls: { user: RUNNER },
    review_note: { user: RUNNER, body: "sneaky" },
    propose_plan_change: { user: RUNNER, title: "x", reason: "x", changes: [easyFor(d0)] },
    set_plan: { title: "x", reason: "x", changes: [easyFor(d0)], confirmed_in_chat: true, summary: "x" },
  };
  const refused = [];
  for (const [name, args] of Object.entries(malCalls)) {
    const r = await mal.call(name, args);
    if (r.isError && /admin_required/.test(r.text)) refused.push(name);
  }
  check("every tool → admin_required", refused.sort(), RUN_PLAN_TOOL_NAMES);
  check("…and the runner's plan is untouched", (await daysOf(RUNNER)) === runnerDays, true);
  check("…no review note saved", (await db.query(`SELECT count(*)::int AS n FROM coach_review_notes WHERE author_id = $1`, [MAL]))[0].n, 0);
  await mal.close();

  console.log("\n— a read-only sign-in can read but not write");
  const ro = await connect(ADMIN, ["db:read"]);
  check("list_run_plans works", (await ro.call("list_run_plans")).isError, false);
  const roW = await ro.call("review_note", { user: RUNNER, body: "x" });
  check("review_note → lacks db:write", [roW.isError, /db:write/.test(roW.text)], [true, true]);
  await ro.close();

  console.log("\n— reads");
  const plans = await admin.call("list_run_plans");
  check("list_run_plans has both plans", ["ovs-admin-user", "ovs-runner-user"].every((u) => plans.json?.plans?.some((p) => p.user_id === u)), true);
  const det = await admin.call("get_run_plan_detail", { user: `@${RUNNER}` });
  check("get_run_plan_detail by @username: plan + days + history", [det.isError, Boolean(det.json?.plan), det.json?.days?.length > 0, Array.isArray(det.json?.history)], [false, true, true, true]);
  const calls = await admin.call("get_coach_calls", { user: RUNNER });
  check("get_coach_calls carries the FULL input and output", [calls.json?.calls?.[0]?.input?.endsWith("-END"), calls.json?.calls?.[0]?.input?.length, calls.json?.calls?.[0]?.output], [true, 2010, "OUTPUT-full-text-END"]);
  const one = await admin.call("get_coach_calls", { call_id: callId });
  check("get_coach_calls by call_id", one.json?.call?.id, callId);
  check("unknown user → user_not_found", /user_not_found/.test((await admin.call("get_run_plan_detail", { user: "nobody-here" })).text), true);

  console.log("\n— review_note");
  const note = await admin.call("review_note", { user: RUNNER, body: "Nov 20 adjustment passed the spike rule by 0.1 mi.", plan_id: det.json.plan.plan_id });
  check("saved with source overseer, author = admin", [note.isError, note.json?.note?.source, note.json?.note?.author_id, note.json?.note?.status], [false, "overseer", ADMIN, "open"]);
  check("listed on the Coach tab", (await Admin.listReviewNotes("open")).some((n) => n.id === note.json?.note?.id), true);

  console.log("\n— propose_plan_change: pending only");
  const before = await daysOf(RUNNER);
  const prop = await admin.call("propose_plan_change", { user: RUNNER, title: "Easier Thursday", reason: "Soreness 7/10.", changes: [easyFor(d0)], deviation_reason: "Overseer review.", today });
  check("pending, source overseer", [prop.isError, prop.json?.proposal?.status, prop.json?.proposal?.source], [false, "pending", "overseer"]);
  check("the runner's days did not change", (await daysOf(RUNNER)) === before, true);
  const bad = await admin.call("propose_plan_change", { user: RUNNER, title: "Huge", reason: "x", changes: [{ local_date: d0.local_date, day: { kind: "long", distance_mi: 25 } }], deviation_reason: "x", today });
  check("hard-rule violation comes back with the violations", [bad.isError, bad.json?.error, Array.isArray(bad.json?.violations)], [true, "hard_rule_violation", true]);

  console.log("\n— set_plan: own plan, confirmed in chat");
  const ad = await pickDay(ADMIN);
  const base = { title: "Easy instead", reason: "Soreness 7/10.", changes: [easyFor(ad)], deviation_reason: "Overseer review.", today };
  const adminBefore = await daysOf(ADMIN);
  const noConfirm = await admin.call("set_plan", { ...base, confirmed_in_chat: false, summary: "Thu → easy" });
  check("confirmed_in_chat false → confirmation_required", [noConfirm.isError, noConfirm.json?.error], [true, "confirmation_required"]);
  const missing = await admin.call("set_plan", { ...base, summary: "Thu → easy" });
  check("confirmed_in_chat missing → refused by the schema", missing.isError, true);
  const noSummary = await admin.call("set_plan", { ...base, confirmed_in_chat: true, summary: "  " });
  check("blank summary → summary_required", noSummary.json?.error, "summary_required");
  const other = await admin.call("set_plan", { ...base, changes: [easyFor(d0)], confirmed_in_chat: true, summary: "x", user: RUNNER });
  check("another user's plan → own_plan_only", other.json?.error, "own_plan_only");
  check("…nothing applied to either plan", [await daysOf(ADMIN) === adminBefore, (await db.query(`SELECT count(*)::int AS n FROM run_plan_proposals WHERE user_id = $1 AND status = 'applied'`, [RUNNER]))[0].n], [true, 0]);
  const ok = await admin.call("set_plan", { ...base, confirmed_in_chat: true, summary: "Thu tempo → easy 4 mi (you said yes)", user: `@${ADMIN}` });
  check("confirmed, own plan → applied, source overseer", [ok.isError, ok.json?.proposal?.status, ok.json?.proposal?.source, ok.json?.days?.[0]?.kind], [false, "applied", "overseer", "easy"]);
  const hist = await db.query(`SELECT h.summary, h.detail FROM run_plan_history h JOIN run_plans p ON p.plan_id = h.plan_id WHERE p.user_id = $1 AND h.event = 'overseer_set_plan'`, [ADMIN]);
  check("history keeps the summary shown", [hist.length, hist[0]?.summary, hist[0]?.detail?.confirmed_in_chat], [1, "Thu tempo → easy 4 mi (you said yes)", true]);

  console.log("\n— audit");
  const audit = await db.query(`SELECT tool, error IS NOT NULL AS failed, finished_at IS NOT NULL AS finished FROM mcp_audit_log WHERE user_id = $1`, [ADMIN]);
  check("every admin tool call has a finished audit row", audit.length >= 12 && audit.every((a) => a.finished), true);
  check("set_plan calls audited, refusals with their error", audit.filter((a) => a.tool === "set_plan").map((a) => a.failed).sort(), [false, true, true, true]);
  check("refused (non-admin) calls never reached the audit/service path", (await db.query(`SELECT count(*)::int AS n FROM mcp_audit_log WHERE user_id = $1`, [MAL]))[0].n, 0);
  await admin.close();
}

main()
  .then(async () => {
    await cleanup();
    console.log(failures ? `\n${failures} check(s) FAILED` : "\nAll overseer checks passed");
    process.exit(failures ? 1 : 0);
  })
  .catch(async (err) => {
    console.error(err);
    await cleanup().catch(() => {});
    process.exit(1);
  });
