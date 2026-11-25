import { PostgresService } from "../DbService.js";
import { plusActiveSql } from "../plusService.js";
import {
  ANTHROPIC_CAP_USD,
  ANTHROPIC_STOP_USD,
  ANTHROPIC_WARN_USD,
  AI_MODES,
  AiMode,
  currentMonth,
  getGlobalCoachSettings,
  monthSpend,
  setGlobalCoachSettings,
  setUserAiMode,
} from "./coachSettings.js";
import { RunPlanError, getPlanDetailForAdmin } from "./runPlanService.js";

/**
 * Admin Coach tab (mileaday.run/admin, role = admin) and the overseer
 * connector's read side. AI call logs are health-derived: admins only,
 * 90-day retention (`sweepAiCallLogs`). Bounded aggregates only.
 */

const db = PostgresService.getInstance();
const PREVIEW = 300;
const CALL_LIST_FIELDS = ["id", "user_id", "provider", "kind", "trigger", "model", "started_at", "created_at", "latency_ms", "tokens_in", "tokens_out", "tokens_cached", "cost_usd", "error", "daily_limit_hit", "proposal_ids"];
const callListCols = (a = "") => {
  const p = a ? `${a}.` : "";
  return [...CALL_LIST_FIELDS.map((f) => `${p}${f}`), `left(${p}input, ${PREVIEW}) AS input_preview`, `left(${p}output, ${PREVIEW}) AS output_preview`].join(", ");
};
const CALL_LIST_COLS = callListCols();

export async function coachUsage(days = 30) {
  days = Math.min(90, Math.max(1, Math.round(days)));
  const [byDay, limitHits, errors, totals] = await Promise.all([
    db.query(
      `SELECT (created_at AT TIME ZONE 'UTC')::date::text AS date, provider, kind, COUNT(*)::int AS calls,
              COUNT(*) FILTER (WHERE error IS NOT NULL)::int AS errors, ROUND(AVG(latency_ms))::int AS avg_latency_ms,
              COALESCE(SUM(cost_usd), 0)::float8 AS cost_usd
         FROM coach_ai_calls WHERE created_at >= now() - make_interval(days => $1)
        GROUP BY 1, 2, 3 ORDER BY 1, 2, 3`,
      [days],
    ),
    db.query(
      `SELECT (created_at AT TIME ZONE 'UTC')::date::text AS date, COUNT(DISTINCT user_id)::int AS users
         FROM coach_ai_calls WHERE daily_limit_hit AND created_at >= now() - make_interval(days => $1) GROUP BY 1 ORDER BY 1`,
      [days],
    ),
    db.query(
      `SELECT c.id, c.created_at AS at, c.user_id, u.username, c.provider, c.kind, c.error FROM coach_ai_calls c LEFT JOIN users u ON u.user_id = c.user_id
        WHERE c.error IS NOT NULL AND c.created_at >= now() - make_interval(days => $1) ORDER BY c.created_at DESC LIMIT 50`,
      [days],
    ),
    db.query(
      `SELECT COUNT(*)::int AS calls, COUNT(DISTINCT user_id)::int AS users, COUNT(*) FILTER (WHERE error IS NOT NULL)::int AS errors,
              ROUND(AVG(latency_ms))::int AS avg_latency_ms, COALESCE(SUM(cost_usd), 0)::float8 AS cost_usd
         FROM coach_ai_calls WHERE created_at >= now() - make_interval(days => $1)`,
      [days],
    ),
  ]);
  return { days, by_day: byDay, apple_limit_hits: limitHits, errors, totals: totals[0] };
}

export async function coachSpend(month = currentMonth()) {
  if (!/^\d{4}-\d{2}$/.test(month)) throw new RunPlanError("invalid_today", 400, { field: "month" });
  const start = `${month}-01`;
  const [spend, byDay, byModel, byUser] = await Promise.all([
    monthSpend(month),
    db.query(`SELECT (created_at AT TIME ZONE 'UTC')::date::text AS date, COALESCE(SUM(cost_usd),0)::float8 AS cost_usd FROM coach_ai_calls
               WHERE provider = 'anthropic' AND created_at >= $1::date AND created_at < ($1::date + interval '1 month') GROUP BY 1 ORDER BY 1`, [start]),
    db.query(`SELECT model, COUNT(*)::int AS calls, COALESCE(SUM(cost_usd),0)::float8 AS cost_usd FROM coach_ai_calls
               WHERE provider = 'anthropic' AND created_at >= $1::date AND created_at < ($1::date + interval '1 month') GROUP BY 1 ORDER BY 3 DESC`, [start]),
    db.query(`SELECT c.user_id, u.username, COUNT(*)::int AS calls, COALESCE(SUM(c.cost_usd),0)::float8 AS cost_usd FROM coach_ai_calls c LEFT JOIN users u ON u.user_id = c.user_id
               WHERE c.provider = 'anthropic' AND c.created_at >= $1::date AND c.created_at < ($1::date + interval '1 month') GROUP BY 1, 2 ORDER BY 4 DESC LIMIT 100`, [start]),
  ]);
  return {
    month,
    spent_usd: Math.round(spend.spent_usd * 10000) / 10000,
    calls: spend.calls,
    cap_usd: ANTHROPIC_CAP_USD(),
    stop_at_usd: ANTHROPIC_STOP_USD(),
    warn_at_usd: ANTHROPIC_WARN_USD(),
    stopped: spend.spent_usd >= ANTHROPIC_STOP_USD(),
    stopped_at: spend.stopped_at,
    by_day: byDay,
    by_model: byModel,
    by_user: byUser,
  };
}

/** Plus members with their AI Coach mode and 30-day call counts. */
export async function coachUsers(q: string | null, limit = 50, offset = 0) {
  limit = Math.min(200, Math.max(1, limit));
  offset = Math.max(0, offset);
  const where = `${plusActiveSql("u")} AND ($1::text IS NULL OR u.username ILIKE '%' || $1 || '%' OR u.first_name ILIKE '%' || $1 || '%')`;
  const [rows, total] = await Promise.all([
    db.query(
      `SELECT u.user_id, u.username, NULLIF(trim(concat_ws(' ', u.first_name, left(u.last_name, 1) || CASE WHEN u.last_name <> '' THEN '.' END)), '') AS display_name,
              true AS plus, COALESCE(cs.ai_mode, 'apple') AS ai_mode, COALESCE(cs.user_opt_out, false) AS user_opt_out,
              EXISTS (SELECT 1 FROM run_plans rp WHERE rp.user_id = u.user_id AND rp.status = 'active') AS has_plan,
              COALESCE(a.calls, 0)::int AS calls_30d, COALESCE(a.cost, 0)::float8 AS cost_30d_usd, a.last_call_at
         FROM users u
         LEFT JOIN coach_settings cs ON cs.user_id = u.user_id
         LEFT JOIN LATERAL (SELECT COUNT(*) AS calls, SUM(cost_usd) AS cost, MAX(created_at) AS last_call_at FROM coach_ai_calls c
                             WHERE c.user_id = u.user_id AND c.created_at >= now() - interval '30 days') a ON true
        WHERE ${where}
        ORDER BY (cs.ai_mode = 'anthropic') DESC NULLS LAST, a.calls DESC NULLS LAST, u.username
        LIMIT $2 OFFSET $3`,
      [q || null, limit, offset],
    ),
    db.query<{ n: number }>(`SELECT COUNT(*)::int AS n FROM users u WHERE ${where}`, [q || null]),
  ]);
  return { users: rows, total: total[0]?.n ?? 0 };
}

export async function listCoachCalls(userId: string, limit = 100, before: string | null = null) {
  return db.query(
    `SELECT ${CALL_LIST_COLS} FROM coach_ai_calls WHERE user_id = $1 AND ($2::timestamptz IS NULL OR created_at < $2::timestamptz)
      ORDER BY created_at DESC LIMIT $3`,
    [userId, before, Math.min(500, Math.max(1, limit))],
  );
}

/** Overseer `get_coach_calls`: a user's calls with FULL input/output (small pages; the text can be long). */
export async function listCoachCallsFull(userId: string, limit = 10, before: string | null = null) {
  if (before !== null && Number.isNaN(Date.parse(before))) throw new RunPlanError("invalid_today", 400, { field: "before" });
  return db.query(
    `SELECT ${CALL_LIST_FIELDS.join(", ")}, input, output FROM coach_ai_calls
      WHERE user_id = $1 AND ($2::timestamptz IS NULL OR created_at < $2::timestamptz)
      ORDER BY created_at DESC LIMIT $3`,
    [userId, before, Math.min(25, Math.max(1, limit))],
  );
}

/** Recent AI calls across every user (Coach tab call log), previews only. */
export async function listRecentCoachCalls(limit = 50, before: string | null = null, provider: string | null = null) {
  if (before !== null && Number.isNaN(Date.parse(before))) before = null;
  if (provider !== null && provider !== "apple" && provider !== "anthropic") provider = null;
  return db.query(
    `SELECT ${callListCols("c")}, u.username
       FROM coach_ai_calls c LEFT JOIN users u ON u.user_id = c.user_id
      WHERE ($1::timestamptz IS NULL OR c.created_at < $1::timestamptz) AND ($2::text IS NULL OR c.provider = $2)
      ORDER BY c.created_at DESC LIMIT $3`,
    [before, provider, Math.min(200, Math.max(1, limit))],
  );
}

export async function coachCallDetail(id: string) {
  if (!/^[0-9a-f-]{36}$/i.test(id)) throw new RunPlanError("call_not_found", 404);
  const rows = await db.query(`SELECT *, cost_usd::float8 AS cost_usd FROM coach_ai_calls WHERE id = $1`, [id]);
  if (!rows[0]) throw new RunPlanError("call_not_found", 404);
  return { call: rows[0] };
}

export async function coachUserDetail(userId: string) {
  const u = await db.query(
    `SELECT u.user_id, u.username, u.first_name, ${plusActiveSql("u")} AS plus, COALESCE(cs.ai_mode, 'apple') AS ai_mode,
            COALESCE(cs.user_opt_out, false) AS user_opt_out, cs.anthropic_consent_at
       FROM users u LEFT JOIN coach_settings cs ON cs.user_id = u.user_id WHERE u.user_id = $1`,
    [userId],
  );
  if (!u[0]) throw new RunPlanError("user_not_found", 404);
  const [detail, calls] = await Promise.all([getPlanDetailForAdmin(userId), listCoachCalls(userId, 100)]);
  return { user: u[0], ...detail, calls };
}

export async function adminSetAiMode(adminId: string, userId: string, mode: unknown) {
  if (!AI_MODES.includes(mode as AiMode)) throw new RunPlanError("invalid_ai_mode", 400);
  const u = await db.query(`SELECT 1 FROM users WHERE user_id = $1`, [userId]);
  if (!u.length) throw new RunPlanError("user_not_found", 404);
  return { ai_mode: await setUserAiMode(userId, mode as AiMode, adminId) };
}

export async function adminGetCoachSettings() {
  return getGlobalCoachSettings();
}
export async function adminPutCoachSettings(adminId: string, body: any) {
  const patch: { ai_enabled?: boolean; anthropic_enabled?: boolean } = {};
  if (body?.ai_enabled !== undefined) {
    if (typeof body.ai_enabled !== "boolean") throw new RunPlanError("invalid_settings", 400);
    patch.ai_enabled = body.ai_enabled;
  }
  if (body?.anthropic_enabled !== undefined) {
    if (typeof body.anthropic_enabled !== "boolean") throw new RunPlanError("invalid_settings", 400);
    patch.anthropic_enabled = body.anthropic_enabled;
  }
  return setGlobalCoachSettings(patch, adminId);
}

export async function listReviewNotes(status: string = "open", limit = 100) {
  const s = status === "all" ? null : status === "resolved" ? "resolved" : "open";
  return db.query(
    `SELECT n.id, n.user_id, u.username, n.plan_id, n.proposal_id, n.body, n.status, n.source, n.author_id, n.created_at, n.resolved_at
       FROM coach_review_notes n LEFT JOIN users u ON u.user_id = n.user_id
      WHERE ($1::text IS NULL OR n.status = $1) ORDER BY n.created_at DESC LIMIT $2`,
    [s, Math.min(500, Math.max(1, limit))],
  );
}

/** Also the overseer's `review_note` tool (source 'overseer'). */
export async function createReviewNote(authorId: string, input: { user_id?: string | null; plan_id?: string | null; proposal_id?: string | null; body: string }, source: "admin" | "overseer" = "admin") {
  if (typeof input?.body !== "string" || !input.body.trim() || input.body.length > 4000) throw new RunPlanError("invalid_note", 400);
  const uuid = (v: unknown) => (v == null ? null : typeof v === "string" && /^[0-9a-f-]{36}$/i.test(v) ? v : (() => { throw new RunPlanError("invalid_note", 400); })());
  const rows = await db.query(
    `INSERT INTO coach_review_notes (user_id, plan_id, proposal_id, body, source, author_id) VALUES ($1, $2, $3, $4, $5, $6)
     RETURNING id, user_id, plan_id, proposal_id, body, status, source, author_id, created_at, resolved_at`,
    [input.user_id ?? null, uuid(input.plan_id), uuid(input.proposal_id), input.body.trim(), source, authorId],
  );
  return rows[0];
}

export async function setReviewNoteStatus(id: string, status: unknown) {
  if (status !== "open" && status !== "resolved") throw new RunPlanError("invalid_note", 400);
  if (!/^[0-9a-f-]{36}$/i.test(id)) throw new RunPlanError("note_not_found", 404);
  const rows = await db.query(
    `UPDATE coach_review_notes SET status = $2, resolved_at = CASE WHEN $2 = 'resolved' THEN now() END WHERE id = $1
     RETURNING id, user_id, plan_id, proposal_id, body, status, source, author_id, created_at, resolved_at`,
    [id, status],
  );
  if (!rows[0]) throw new RunPlanError("note_not_found", 404);
  return rows[0];
}

/** Overseer `list_run_plans`: every active plan with tier, adherence, grades, last change. */
export async function listRunPlansForAdmin(limit = 200) {
  return db.query(
    `SELECT rp.plan_id, rp.user_id, u.username, rp.goals, rp.target_date::text AS target_date, rp.runs_per_week, rp.difficulty, rp.walk_mode,
            rp.start_date::text AS start_date, COALESCE(cs.ai_mode, 'apple') AS ai_mode,
            g.graded, g.avg_score, g.last_graded,
            (SELECT MAX(at) FROM run_plan_history h WHERE h.plan_id = rp.plan_id AND h.event IN ('proposal_applied','overseer_set_plan','settings_changed')) AS last_change_at,
            (SELECT COUNT(*)::int FROM run_plan_proposals p WHERE p.plan_id = rp.plan_id AND p.status = 'pending') AS pending_proposals
       FROM run_plans rp
       JOIN users u ON u.user_id = rp.user_id
       LEFT JOIN coach_settings cs ON cs.user_id = rp.user_id
       LEFT JOIN LATERAL (SELECT COUNT(*)::int AS graded, ROUND(AVG(score))::int AS avg_score, MAX(local_date)::text AS last_graded
                            FROM run_plan_grades gr WHERE gr.plan_id = rp.plan_id AND gr.local_date >= CURRENT_DATE - 28) g ON true
      WHERE rp.status = 'active' ORDER BY rp.updated_at DESC LIMIT $1`,
    [Math.min(1000, Math.max(1, limit))],
  );
}
