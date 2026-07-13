import { PostgresService } from "./DbService.js";
import { sendPush } from "./pushNotificationService.js";
import {
  ChallengeRow,
  SOCIAL_CHALLENGE_KEYS,
  FEED_CHALLENGE_KEYS,
  ADD_FRIEND_CHALLENGE_KEY,
  walkRotation,
  edgeScore,
} from "./challengeRotation.js";

const db = PostgresService.getInstance();

/**
 * Head-to-Head daily matchups.
 *
 * Rivals are PINNED in `h2h_matchups`, one row per (local_date, user): the
 * duel a user sees in the morning is the duel that gets scored, even if their
 * friend list changes mid-day. Pins are created by a once-per-day global
 * matching that pairs users RECIPROCALLY wherever possible (both users get
 * each other, `mutual = TRUE`). Reciprocity for everyone is mathematically
 * impossible (odd counts, star-shaped friend graphs), so unpaired users fall
 * back to a deterministic one-sided rival (`mutual = FALSE`) — same experience
 * as the legacy behavior, never worse.
 *
 * The duel is scored by the end-of-day cron (see resolveDueMatchups), NOT at
 * workout-sync time: it's a whole-day mileage total, so nobody can "win" while
 * the other side still has hours left to run.
 */

export interface PinnedRival {
  rivalId: string;
  mutual: boolean;
}

/**
 * WHERE fragment selecting user $1's eligible Head-to-Head rivals: accepted
 * friends, narrowed to their close-friends list when the user's
 * h2h_close_friends_only preference is on. Shared by the existence probe and
 * the fallback pick so the two can never disagree.
 */
const H2H_CANDIDATE_WHERE = `
	f.user_id = $1 AND f.status = 'accepted'
	AND (
		NOT COALESCE((SELECT ns.h2h_close_friends_only FROM notification_settings ns WHERE ns.user_id = $1), FALSE)
		OR EXISTS (SELECT 1 FROM close_friends cf WHERE cf.user_id = $1 AND cf.close_friend_id = f.friend_id)
	)`;

/**
 * TRUE when the user has at least one eligible Head-to-Head rival. Gates the
 * challenge in the rotation walk: a user restricting to close friends who has
 * none (left) simply rotates onto the next challenge instead of getting an
 * unwinnable duel-less card.
 */
export async function hasH2hRivalCandidates(userId: string): Promise<boolean> {
  const rows = await db.query<{ ok: boolean }>(
    `SELECT EXISTS (SELECT 1 FROM friendships f WHERE ${H2H_CANDIDATE_WHERE}) AS ok`,
    [userId],
  );
  return rows[0]?.ok === true;
}

/**
 * The user's pinned rival for the date, creating pins if this is the first
 * Head-to-Head read of the day. Returns null only for users with no eligible
 * rivals (no accepted friends, or none on their close list while restricting).
 * A pin whose friendship has since ended (unfriend/block deletes both
 * friendship rows) is treated as absent and deterministically re-pinned;
 * close-list edits alone do NOT re-roll an already-pinned day — the
 * preference shapes pin creation, starting with the next matchup.
 */
export async function getOrAssignRival(
  userId: string,
  localDate: string,
): Promise<PinnedRival | null> {
  const readPin = async (): Promise<PinnedRival | null> => {
    const rows = await db.query<{ rival_id: string; mutual: boolean }>(
      `SELECT m.rival_id, m.mutual
			FROM h2h_matchups m
			JOIN friendships f
				ON f.user_id = m.user_id AND f.friend_id = m.rival_id AND f.status = 'accepted'
			WHERE m.local_date = $1 AND m.user_id = $2`,
      [localDate, userId],
    );
    return rows[0]
      ? { rivalId: rows[0].rival_id, mutual: rows[0].mutual === true }
      : null;
  };

  let pin = await readPin();
  if (pin) return pin;

  // First Head-to-Head read of this date anywhere → compute the day's matching.
  try {
    await ensureMatchupsForDate(localDate);
  } catch (e: any) {
    console.error(
      `[H2H] ensureMatchupsForDate(${localDate}) failed:`,
      e?.message ?? e,
    );
  }
  pin = await readPin();
  if (pin) return pin;

  // Still no usable pin: the user joined the pool after matching ran (new
  // friendship, eligibility flip) or their pinned rival unfriended them.
  // Deterministic one-sided fallback among current accepted friends, then pin
  // it so the rest of the day (and the resolver) sees the same duel.
  const friends = await db.query<{ friend_id: string }>(
    `SELECT f.friend_id FROM friendships f WHERE ${H2H_CANDIDATE_WHERE}`,
    [userId],
  );
  if (friends.length === 0) return null;

  // Prefer a recently-active rival (same 7-days-before-date signal as the
  // matchmaker's leftover ranking), then the day's edge score.
  const candidateIds = friends.map((f) => f.friend_id);
  const activeRows = await db.query<{ user_id: string }>(
    `SELECT DISTINCT user_id FROM workouts
		WHERE user_id = ANY($1::text[])
			AND local_date >= ($2::date - INTERVAL '7 days') AND local_date < $2::date
			AND deleted_at IS NULL AND exclusion_reason IS NULL`,
    [candidateIds, localDate],
  );
  const recentlyActive = new Set(activeRows.map((r) => r.user_id));

  let rivalId = candidateIds[0];
  let bestTier = Number.POSITIVE_INFINITY;
  let bestScore = Number.POSITIVE_INFINITY;
  for (const c of candidateIds) {
    const t = recentlyActive.has(c) ? 0 : 1;
    const s = edgeScore(userId, c, localDate);
    const better =
      t < bestTier ||
      (t === bestTier && (s < bestScore || (s === bestScore && c < rivalId)));
    if (better) {
      bestTier = t;
      bestScore = s;
      rivalId = c;
    }
  }

  // Upsert replaces a dead pin (unfriended rival). Never rewrite a row the
  // resolver already scored — by then the user's local date has moved past
  // this date anyway, so live reads can't reach here; belt and suspenders.
  const upserted = await db.query<{ rival_id: string; mutual: boolean }>(
    `INSERT INTO h2h_matchups (local_date, user_id, rival_id, mutual)
		VALUES ($1, $2, $3, FALSE)
		ON CONFLICT (local_date, user_id) DO UPDATE
			SET rival_id = EXCLUDED.rival_id, mutual = FALSE
			WHERE h2h_matchups.resolved_at IS NULL
		RETURNING rival_id, mutual`,
    [localDate, userId, rivalId],
  );
  if (upserted[0]) {
    return { rivalId: upserted[0].rival_id, mutual: false };
  }
  // Upsert was blocked by the resolved guard — surface whatever is stored.
  const stored = await db.query<{ rival_id: string; mutual: boolean }>(
    `SELECT rival_id, mutual FROM h2h_matchups WHERE local_date = $1 AND user_id = $2`,
    [localDate, userId],
  );
  return stored[0]
    ? { rivalId: stored[0].rival_id, mutual: stored[0].mutual === true }
    : null;
}

// ─── Once-per-day global matching ───────────────────────────────────

/**
 * Compute and insert the day's matchups exactly once, serialized by an
 * advisory lock. Concurrent first-readers block on the lock, then see the
 * winner's rows and skip. Rows for a date existing at all means the matching
 * already ran (individual fallback pins can only be created AFTER this).
 */
async function ensureMatchupsForDate(localDate: string): Promise<void> {
  const existing = await db.query(
    `SELECT 1 FROM h2h_matchups WHERE local_date = $1 LIMIT 1`,
    [localDate],
  );
  if (existing.length > 0) return;

  const client = await db.getClient();
  try {
    await client.query("BEGIN");
    await client.query(`SELECT pg_advisory_xact_lock(hashtext($1))`, [
      `h2h_matchups:${localDate}`,
    ]);
    const again = await client.query(
      `SELECT 1 FROM h2h_matchups WHERE local_date = $1 LIMIT 1`,
      [localDate],
    );
    if (again.rows.length === 0) {
      await computeAndInsertMatchups(client, localDate);
    }
    await client.query("COMMIT");
  } catch (e) {
    try {
      await client.query("ROLLBACK");
    } catch {
      /* connection-level failure; release below */
    }
    throw e;
  } finally {
    client.release();
  }
}

type PoolClient = Awaited<ReturnType<PostgresService["getClient"]>>;

/**
 * Global greedy matching for one date.
 *
 * Pool = users whose rotation selection for the date is head_to_head. All pool
 * candidates have friends (social challenges are skipped otherwise), so
 * selection varies only by the feed flag and by Head-to-Head rival
 * eligibility (the close-friends restriction) — the rotation is walked once
 * per flag combination instead of once per user (see selectChallengeForUser,
 * whose semantics this mirrors via the shared walkRotation).
 *
 * Matching: every undirected friendship edge inside the pool — allowed by
 * BOTH endpoints' close-friends preferences — gets the deterministic per-day
 * edgeScore; ascending greedy pass pairs both-free endpoints (mutual).
 * Leftover pool users get a one-sided rival: their best-scored allowed pool
 * neighbor (someone also dueling today) if any, else their best-scored
 * allowed friend overall.
 */
async function computeAndInsertMatchups(
  client: PoolClient,
  localDate: string,
): Promise<void> {
  const challengeRows = (
    await client.query<ChallengeRow>(
      `SELECT challenge_key, title, description_template, icon, gradient_start, gradient_end, type
			FROM daily_challenges WHERE active = TRUE ORDER BY rotation_index ASC`,
    )
  ).rows;
  if (challengeRows.length === 0) return;

  // Selection varies by two per-user flags: the feed signal (share_journey
  // gate) and Head-to-Head rival eligibility (close-friends restriction —
  // see hasH2hRivalCandidates). Everyone in the candidate set has accepted
  // friends, so the plain social gate always passes. Walk the rotation once
  // per flag combination instead of once per user.
  const selectsH2h = async (
    userHasFeed: boolean,
    h2hOk: boolean,
  ): Promise<boolean> => {
    const picked = await walkRotation(challengeRows, localDate, (row) => {
      if (row.challenge_key === "head_to_head") return h2hOk;
      return FEED_CHALLENGE_KEYS.has(row.challenge_key) ? userHasFeed : true;
    });
    return picked.challenge_key === "head_to_head";
  };
  const h2hSelected = new Map<string, boolean>();
  for (const feedFlag of [true, false]) {
    for (const h2hOk of [true, false]) {
      h2hSelected.set(
        `${feedFlag}:${h2hOk}`,
        await selectsH2h(feedFlag, h2hOk),
      );
    }
  }
  if (![...h2hSelected.values()].some(Boolean)) return; // nobody duels on this date

  // Undirected accepted-friendship edges (accepted rows exist in both
  // directions; user_id < friend_id keeps one per pair).
  const edges = (
    await client.query<{ user_id: string; friend_id: string }>(
      `SELECT user_id, friend_id FROM friendships
			WHERE status = 'accepted' AND user_id < friend_id`,
    )
  ).rows;
  if (edges.length === 0) return;

  const userIds = [...new Set(edges.flatMap((e) => [e.user_id, e.friend_id]))];

  // Feed flags in one batch — same signal as userHasFeedFeature.
  const feedRows = (
    await client.query<{ user_id: string; has_feed: boolean }>(
      `SELECT u.user_id,
				(EXISTS (SELECT 1 FROM posts p WHERE p.user_id = u.user_id)
					OR u.terms_accepted_at IS NOT NULL) AS has_feed
			FROM users u WHERE u.user_id = ANY($1::text[])`,
      [userIds],
    )
  ).rows;
  const hasFeed = new Map(
    feedRows.map((r) => [r.user_id, r.has_feed === true]),
  );

  // Close-friends restriction, in batch — mirrors H2H_CANDIDATE_WHERE.
  const restrictedRows = (
    await client.query<{ user_id: string }>(
      `SELECT user_id FROM notification_settings
				WHERE h2h_close_friends_only = TRUE AND user_id = ANY($1::text[])`,
      [userIds],
    )
  ).rows;
  const restricted = new Set(restrictedRows.map((r) => r.user_id));
  const closeOf = new Map<string, Set<string>>();
  if (restricted.size > 0) {
    const closeRows = (
      await client.query<{ user_id: string; close_friend_id: string }>(
        `SELECT user_id, close_friend_id FROM close_friends WHERE user_id = ANY($1::text[])`,
        [[...restricted]],
      )
    ).rows;
    for (const r of closeRows) {
      const set = closeOf.get(r.user_id);
      if (set) set.add(r.close_friend_id);
      else closeOf.set(r.user_id, new Set([r.close_friend_id]));
    }
  }
  /** May x duel y? Only x's own preference matters (one direction). */
  const allows = (x: string, y: string): boolean =>
    !restricted.has(x) || closeOf.get(x)?.has(y) === true;

  // Fallback quality signal: friends who logged a workout in the 7 days
  // BEFORE this date make livelier one-sided rivals than dormant accounts.
  // Strictly before the date, so the ranking is stable for the whole day.
  const activeRows = (
    await client.query<{ user_id: string }>(
      `SELECT DISTINCT user_id FROM workouts
				WHERE user_id = ANY($1::text[])
					AND local_date >= ($2::date - INTERVAL '7 days') AND local_date < $2::date
					AND deleted_at IS NULL AND exclusion_reason IS NULL`,
      [userIds, localDate],
    )
  ).rows;
  const recentlyActive = new Set(activeRows.map((r) => r.user_id));

  // Restricted users are h2h-eligible only with >= 1 close friend among
  // their accepted friends (edge endpoints), matching hasH2hRivalCandidates.
  const h2hEligible = new Set<string>(
    userIds.filter((u) => !restricted.has(u)),
  );
  for (const e of edges) {
    if (allows(e.user_id, e.friend_id)) h2hEligible.add(e.user_id);
    if (allows(e.friend_id, e.user_id)) h2hEligible.add(e.friend_id);
  }

  const pool = new Set(
    userIds.filter((uid) =>
      h2hSelected.get(`${hasFeed.get(uid) === true}:${h2hEligible.has(uid)}`),
    ),
  );
  if (pool.size === 0) return;

  // Mutual pairs need BOTH directions allowed — each side must see the other.
  const scored = edges
    .filter(
      (e) =>
        pool.has(e.user_id) &&
        pool.has(e.friend_id) &&
        allows(e.user_id, e.friend_id) &&
        allows(e.friend_id, e.user_id),
    )
    .map((e) => ({
      a: e.user_id,
      b: e.friend_id,
      score: edgeScore(e.user_id, e.friend_id, localDate),
    }))
    .sort(
      (x, y) =>
        x.score - y.score || x.a.localeCompare(y.a) || x.b.localeCompare(y.b),
    );

  const rivalOf = new Map<string, { rivalId: string; mutual: boolean }>();
  for (const { a, b } of scored) {
    if (!rivalOf.has(a) && !rivalOf.has(b)) {
      rivalOf.set(a, { rivalId: b, mutual: true });
      rivalOf.set(b, { rivalId: a, mutual: true });
    }
  }

  // Leftovers get a one-sided rival (mutual = FALSE); only the chooser's
  // close-friends preference filters their candidates. Ranking: recently
  // active beats dormant, then someone also dueling today (pool) beats
  // someone who isn't, then the day's edge score keeps it deterministic.
  const neighbors = new Map<string, string[]>();
  const addNeighbor = (from: string, to: string) => {
    const list = neighbors.get(from);
    if (list) list.push(to);
    else neighbors.set(from, [to]);
  };
  for (const e of edges) {
    addNeighbor(e.user_id, e.friend_id);
    addNeighbor(e.friend_id, e.user_id);
  }
  for (const uid of pool) {
    if (rivalOf.has(uid)) continue;
    let rival: string | null = null;
    let bestTier = Number.POSITIVE_INFINITY;
    let bestScore = Number.POSITIVE_INFINITY;
    for (const c of neighbors.get(uid) ?? []) {
      if (!allows(uid, c)) continue;
      const t = (recentlyActive.has(c) ? 0 : 2) + (pool.has(c) ? 0 : 1);
      const s = edgeScore(uid, c, localDate);
      const better =
        t < bestTier ||
        (t === bestTier &&
          (s < bestScore ||
            (s === bestScore && (rival === null || c < rival))));
      if (better) {
        bestTier = t;
        bestScore = s;
        rival = c;
      }
    }
    if (rival) rivalOf.set(uid, { rivalId: rival, mutual: false });
  }

  const entries = [...rivalOf.entries()];
  const CHUNK = 2000;
  for (let i = 0; i < entries.length; i += CHUNK) {
    const chunk = entries.slice(i, i + CHUNK);
    const values: string[] = [];
    const params: any[] = [localDate];
    for (const [uid, { rivalId, mutual }] of chunk) {
      values.push(
        `($1, $${params.length + 1}, $${params.length + 2}, $${params.length + 3})`,
      );
      params.push(uid, rivalId, mutual);
    }
    await client.query(
      `INSERT INTO h2h_matchups (local_date, user_id, rival_id, mutual)
			VALUES ${values.join(", ")}
			ON CONFLICT (local_date, user_id) DO NOTHING`,
      params,
    );
  }
  console.log(
    `[H2H] Matched ${entries.length} user(s) for ${localDate} (${
      [...rivalOf.values()].filter((r) => r.mutual).length
    } in mutual pairs).`,
  );
}

// ─── End-of-day resolution (cron) ───────────────────────────────────

/**
 * A user's local "now" as a tz-less timestamp, preferring the app-reported
 * notification offset and falling back to the last workout's offset (same
 * precedence as the weekly recap cron). `col` is a code-controlled column
 * reference, never user input.
 */
function localNowSql(col: string): string {
  return `((NOW() AT TIME ZONE 'UTC') + (COALESCE(
		(SELECT ns.timezone_offset_minutes FROM notification_settings ns WHERE ns.user_id = ${col}),
		(SELECT w.timezone_offset FROM workouts w WHERE w.user_id = ${col} ORDER BY w.device_end_date DESC LIMIT 1),
		0) || ' minutes')::interval)`;
}

/**
 * Hours past local midnight before a day's duel is scored. Late HealthKit
 * syncs (phone locked overnight, Watch backlog) can add workouts to a
 * finished day; waiting until 6 AM local absorbs most of them. There is no
 * revocation path for challenge completions, so scoring too early records a
 * wrong winner permanently.
 */
const RESOLVE_GRACE_HOURS = 6;

/**
 * Score every unresolved matchup whose day is over — for BOTH sides — plus the
 * grace period (the rival's late-night miles are part of the outcome, so their
 * clock matters too). Winner inserts the day's challenge completion; the push
 * is deferred to notifyPendingWinners. Hourly-cron safe: idempotent per row.
 */
export async function resolveDueMatchups(): Promise<void> {
  const cutoff = `(m.local_date::timestamp + INTERVAL '1 day' + INTERVAL '${RESOLVE_GRACE_HOURS} hours')`;
  const due = await db.query<{
    local_date: string;
    user_id: string;
    rival_id: string;
  }>(
    `SELECT m.local_date::text AS local_date, m.user_id, m.rival_id
		FROM h2h_matchups m
		WHERE m.resolved_at IS NULL
			AND m.local_date >= (CURRENT_DATE - INTERVAL '7 days')
			AND ${localNowSql("m.user_id")} >= ${cutoff}
			AND ${localNowSql("m.rival_id")} >= ${cutoff}`,
  );
  if (due.length === 0) return;
  console.log(`[H2H] Resolving ${due.length} finished matchup(s)...`);

  for (const row of due) {
    try {
      await resolveOne(row.local_date, row.user_id, row.rival_id);
    } catch (e: any) {
      console.error(
        `[H2H] Failed to resolve ${row.user_id} @ ${row.local_date}:`,
        e?.message ?? e,
      );
    }
  }
}

async function resolveOne(
  localDate: string,
  userId: string,
  rivalId: string,
): Promise<void> {
  let awarded = false;

  // The pin can go stale between morning and scoring: friendship ended, or an
  // eligibility flip re-selected the user onto a different challenge (their
  // card stopped showing the duel). Only award what the user actually saw.
  const stillFriends = await db.query(
    `SELECT 1 FROM friendships WHERE user_id = $1 AND friend_id = $2 AND status = 'accepted'`,
    [userId, rivalId],
  );
  if (
    stillFriends.length > 0 &&
    (await selectedChallengeKey(userId, localDate)) === "head_to_head"
  ) {
    const [mineRaw, theirsRaw, goal] = await Promise.all([
      dayTotalDistance(userId, localDate),
      dayTotalDistance(rivalId, localDate),
      getGoalMiles(userId),
    ]);
    // Compare at display precision: the duel card shows 2-decimal miles, so
    // 2dp is the truth that decides it. A 2dp tie awards nobody ("Dead even").
    const mine = Math.round(mineRaw * 100) / 100;
    const theirs = Math.round(theirsRaw * 100) / 100;
    if (mine >= goal * 0.95 && mine > theirs) {
      const completingWorkoutId = await latestWorkoutId(userId, localDate);
      const inserted = await db.query<{ id: string }>(
        `INSERT INTO user_challenge_completions (user_id, local_date, challenge_key, completing_workout_id)
				VALUES ($1, $2, 'head_to_head', $3)
				ON CONFLICT (user_id, local_date) DO NOTHING
				RETURNING id`,
        [userId, localDate, completingWorkoutId],
      );
      awarded = inserted.length > 0;
    }
  }

  // `won` doubles as "notify this user": TRUE only when the completion row
  // was actually inserted by this resolution.
  await db.query(
    `UPDATE h2h_matchups SET resolved_at = NOW(), won = $3
		WHERE local_date = $1 AND user_id = $2`,
    [localDate, userId, awarded],
  );
}

/**
 * Re-derive which challenge the rotation gave this user for the date. Mirrors
 * dailyChallengeService.selectChallengeForUser exactly (shared walkRotation +
 * key sets); kept separate to avoid a service import cycle.
 */
async function selectedChallengeKey(
  userId: string,
  localDate: string,
): Promise<string | null> {
  const rows = await db.query<ChallengeRow>(
    `SELECT challenge_key, title, description_template, icon, gradient_start, gradient_end, type
		FROM daily_challenges WHERE active = TRUE ORDER BY rotation_index ASC`,
  );
  if (rows.length === 0) return null;

  let friendCount: number | null = null;
  let hasFeed: boolean | null = null;
  let h2hOk: boolean | null = null;
  let friendlessOnH2hDay = false;
  const picked = await walkRotation(rows, localDate, async (row) => {
    if (SOCIAL_CHALLENGE_KEYS.has(row.challenge_key)) {
      if (friendCount === null) {
        const r = await db.query<{ c: string }>(
          `SELECT COUNT(*)::text AS c FROM friendships WHERE user_id = $1 AND status = 'accepted'`,
          [userId],
        );
        friendCount = parseInt(r[0]?.c ?? "0", 10) || 0;
      }
      if (friendCount === 0) {
        // Friendless users get the add_friend substitute on h2h days —
        // mirror selectChallengeForUser so the resolver judges the same
        // challenge the user's card showed.
        if (row.challenge_key === "head_to_head") friendlessOnH2hDay = true;
        return false;
      }
    }
    // Head-to-Head additionally needs an eligible rival: with the
    // close-friends-only preference on, having friends isn't enough.
    if (row.challenge_key === "head_to_head") {
      h2hOk ??= await hasH2hRivalCandidates(userId);
      if (!h2hOk) return false;
    }
    if (FEED_CHALLENGE_KEYS.has(row.challenge_key)) {
      if (hasFeed === null) {
        const r = await db.query<{ ok: boolean }>(
          `SELECT (EXISTS (SELECT 1 FROM posts WHERE user_id = $1)
						OR EXISTS (SELECT 1 FROM users WHERE user_id = $1 AND terms_accepted_at IS NOT NULL)) AS ok`,
          [userId],
        );
        hasFeed = r[0]?.ok === true;
      }
      if (!hasFeed) return false;
    }
    return true;
  });
  if (friendlessOnH2hDay) return ADD_FRIEND_CHALLENGE_KEY;
  return picked.challenge_key;
}

// ─── Winner notification (cron) ─────────────────────────────────────

/**
 * Push the "you won" celebration during the winner's local morning/daytime
 * (9 AM–9:59 PM) rather than at the 6 AM scoring moment — a middle-of-the-
 * night push would only land in the quiet-hours queue and resurface as a
 * degraded digest. Claim-then-send keeps it exactly-once per matchup.
 */
export async function notifyPendingWinners(): Promise<void> {
  const winners = await db.query<{
    local_date: string;
    user_id: string;
    rival_id: string;
  }>(
    `SELECT m.local_date::text AS local_date, m.user_id, m.rival_id
		FROM h2h_matchups m
		WHERE m.won = TRUE AND m.notified_at IS NULL
			AND m.local_date >= (CURRENT_DATE - INTERVAL '7 days')
			AND EXTRACT(HOUR FROM ${localNowSql("m.user_id")}) BETWEEN 9 AND 21`,
  );

  for (const w of winners) {
    const claimed = await db.query<{ user_id: string }>(
      `UPDATE h2h_matchups SET notified_at = NOW()
			WHERE local_date = $1 AND user_id = $2 AND notified_at IS NULL
			RETURNING user_id`,
      [w.local_date, w.user_id],
    );
    if (claimed.length === 0) continue;

    try {
      const [rival] = await db.query<{ username: string | null }>(
        `SELECT username FROM users WHERE user_id = $1`,
        [w.rival_id],
      );
      const [mine, theirs] = await Promise.all([
        dayTotalDistance(w.user_id, w.local_date),
        dayTotalDistance(w.rival_id, w.local_date),
      ]);
      const name = rival?.username ?? "your rival";
      await sendPush(w.user_id, {
        title: "You won your Head-to-Head! 🏆",
        body: `You out-ran ${name} ${mine.toFixed(2)} to ${theirs.toFixed(2)} mi. Daily challenge complete!`,
        type: "challenge_won",
        data: {
          challenge_key: "head_to_head",
          local_date: w.local_date,
          rival_id: w.rival_id,
          rival_username: rival?.username ?? "",
        },
      });
    } catch (e: any) {
      console.error(
        `[H2H] Winner push failed for ${w.user_id} @ ${w.local_date}:`,
        e?.message ?? e,
      );
    }
  }
}

// ─── Local SQL helpers (mirrors of dailyChallengeService's) ─────────

async function dayTotalDistance(
  userId: string,
  localDate: string,
): Promise<number> {
  const rows = await db.query<{ total: string | null }>(
    `SELECT COALESCE(SUM(distance),0)::text AS total FROM workouts
		WHERE user_id = $1 AND local_date = $2 AND deleted_at IS NULL AND exclusion_reason IS NULL`,
    [userId, localDate],
  );
  return parseFloat(rows[0]?.total ?? "0") || 0;
}

async function getGoalMiles(userId: string): Promise<number> {
  const rows = await db.query<{ goal_miles: string }>(
    `SELECT goal_miles::text AS goal_miles FROM users WHERE user_id = $1`,
    [userId],
  );
  return parseFloat(rows[0]?.goal_miles ?? "1.0") || 1.0;
}

async function latestWorkoutId(
  userId: string,
  localDate: string,
): Promise<string | null> {
  const rows = await db.query<{ workout_id: string }>(
    `SELECT workout_id FROM workouts
		WHERE user_id = $1 AND local_date = $2 AND deleted_at IS NULL AND exclusion_reason IS NULL
		ORDER BY device_end_date DESC LIMIT 1`,
    [userId, localDate],
  );
  return rows[0]?.workout_id ?? null;
}
