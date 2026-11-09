import { PostgresService } from "./DbService.js";
import { countedWorkoutSql } from "./mileTime.js";
import { STREAK_QUALIFYING_MILES } from "./streakFeatureCore.js";
import { deviceMeasuredDistanceSql, deviceMeasuredWorkoutSql } from "./workoutService.js";
import { getPlusStatus } from "./plusService.js";
import { referralHandleSql } from "./userService.js";
import { grantStreakAssist } from "./streakFeatureService.js";

const db = PostgresService.getInstance();

/**
 * Referrals. A new user picks the real account that sent them, and that person
 * earns credit once the new user has walked enough to show they're real.
 * See docs/specs/referrals.md.
 *
 * A referrer sees only a friend's name and days toward qualifying, which the
 * friend is told when they pick them.
 */

/** Walk this many different days... */
export const QUALIFYING_DAYS = 7;
/** ...within this many days of being linked. */
export const QUALIFYING_WINDOW_DAYS = 30;
/** This many accounts picking one person in a day gets a look in admin. */
const FLAG_LINKS_PER_DAY = 5;
/** How long after signing up someone can still name their referrer. */
export const LINK_WINDOW_DAYS = 14;

export type ReferralRewardKind = "medal" | "token" | "item" | "free_year" | "lifetime";

interface ReferralReward {
  count: number;
  kind: ReferralRewardKind;
  title: string;
  description: string;
  badgeId?: string;
  itemId?: string;
}

export const REFERRAL_REWARDS: readonly ReferralReward[] = [
  { count: 1, kind: "medal", title: "Trail Buddy medal", description: "For you and your friend.", badgeId: "referral_buddy" },
  { count: 3, kind: "token", title: "Streak Assist", description: "A token that helps cover a missed day." },
  { count: 5, kind: "item", title: "Trail Guide Hat", description: "A Flamey hat you can only earn by referring friends.", badgeId: "referral_guide", itemId: "trail_guide" },
  { count: 10, kind: "free_year", title: "A year of Mile A Day+", description: "Free, if you don't already have Plus." },
  { count: 15, kind: "token", title: "Streak Assist", description: "Another token for the day you need it." },
  { count: 25, kind: "lifetime", title: "Lifetime Mile A Day+", description: "Free, for good." },
  { count: 50, kind: "item", title: "Pathfinder Flamey", description: "The rarest form Flamey has.", badgeId: "referral_pathfinder", itemId: "pathfinder" },
];

/**
 * Lifetime stays out of the app until App Review confirms how it may be
 * delivered, so nobody sees a promise we can't keep yet.
 */
function offeredRewards(): readonly ReferralReward[] {
  const lifetime = process.env.REFERRAL_LIFETIME_ENABLED === "true";
  return REFERRAL_REWARDS.filter((r) => r.kind !== "lifetime" || lifetime);
}

export class ReferralError extends Error {
  constructor(public code: string, message: string, public status = 400) {
    super(message);
  }
}

/** Qualifying days since a referral was linked, for many friends at once. */
function progressSql(whereReferral: string): string {
  return `
    SELECT r.referee_id, r.referrer_id, r.status, r.origin, r.created_at,
           COUNT(*) FILTER (WHERE d.miles >= ${STREAK_QUALIFYING_MILES})::int AS days
      FROM referrals r
      LEFT JOIN LATERAL (
        SELECT w.local_date, SUM(${deviceMeasuredDistanceSql("w")}) AS miles
          FROM workouts w
         WHERE w.user_id = r.referee_id
           AND w.local_date >= (r.created_at - interval '1 day')::date
           AND w.local_date <= (r.created_at + interval '${QUALIFYING_WINDOW_DAYS} days')::date
           AND ${countedWorkoutSql("w")}
           AND ${deviceMeasuredWorkoutSql("w")}
         GROUP BY w.local_date
      ) d ON TRUE
     WHERE ${whereReferral}
     GROUP BY r.referee_id, r.referrer_id, r.status, r.origin, r.created_at`;
}

/**
 * Connects people who named a friend before accounts could be picked, and
 * anyone still on an old app version. The name has to match one real account
 * or an admin alias, the referrer must have joined first, so a loop can't
 * form, and blocked pairs stay apart. The link starts from the friend's
 * sign-up date, so the 7-in-30 rule reads their real first month. Safe to
 * repeat, and it never touches a link that already exists.
 */
export async function linkTypedReferrals(): Promise<number> {
  const handle = referralHandleSql("friend.referral_detail");
  const rows = await db.query(
    `INSERT INTO referrals (referee_id, referrer_id, origin, created_at)
     SELECT friend.user_id, referrer.user_id, 'typed', friend.created_at
       FROM users friend
       LEFT JOIN referral_aliases alias ON alias.alias = ${handle}
       JOIN users referrer
         ON referrer.user_id = alias.user_id
         OR (alias.user_id IS NULL AND lower(referrer.username) = ${handle})
      WHERE friend.referral_source = 'friend'
        AND referrer.user_id <> friend.user_id
        AND referrer.created_at <= friend.created_at
        AND NOT EXISTS (
          SELECT 1 FROM user_blocks b
           WHERE (b.blocker_id = friend.user_id AND b.blocked_id = referrer.user_id)
              OR (b.blocker_id = referrer.user_id AND b.blocked_id = friend.user_id)
        )
     ON CONFLICT (referee_id) DO NOTHING
     RETURNING referee_id`,
  );
  return rows.length;
}

/** Links a new user to the account that referred them. Refuses anything iffy. */
export async function setReferrer(refereeId: string, username: string): Promise<void> {
  const handle = username.trim().replace(/^@/, "");
  const [me] = await db.query<{ recent: boolean }>(
    `SELECT created_at >= NOW() - interval '${LINK_WINDOW_DAYS} days' AS recent FROM users WHERE user_id = $1`,
    [refereeId],
  );
  if (!me?.recent) {
    throw new ReferralError("window_closed", "Referrers can only be added in your first 14 days.");
  }

  const [referrer] = await db.query<{ user_id: string }>(
    `SELECT user_id FROM users WHERE lower(username) = lower($1)`,
    [handle],
  );
  if (!referrer) throw new ReferralError("not_found", "We couldn't find that account.", 404);
  if (referrer.user_id === refereeId) throw new ReferralError("self", "You can't refer yourself.");

  const blocked = await db.query(
    `SELECT 1 FROM user_blocks WHERE (blocker_id = $1 AND blocked_id = $2) OR (blocker_id = $2 AND blocked_id = $1)`,
    [refereeId, referrer.user_id],
  );
  if (blocked.length > 0) throw new ReferralError("not_found", "We couldn't find that account.", 404);

  const loop = await db.query(`SELECT 1 FROM referrals WHERE referee_id = $1 AND referrer_id = $2`, [
    referrer.user_id,
    refereeId,
  ]);
  if (loop.length > 0) throw new ReferralError("loop", "That person already joined through you.");

  const inserted = await db.query(
    `INSERT INTO referrals (referee_id, referrer_id) VALUES ($1, $2)
     ON CONFLICT (referee_id) DO NOTHING RETURNING referee_id`,
    [refereeId, referrer.user_id],
  );
  if (inserted.length === 0) {
    throw new ReferralError("already_set", "You've already added who referred you.", 409);
  }
}

async function qualifiedCount(userId: string): Promise<number> {
  const [row] = await db.query<{ n: number }>(
    `SELECT COUNT(*)::int AS n FROM referrals WHERE referrer_id = $1 AND status = 'qualified'`,
    [userId],
  );
  return row?.n ?? 0;
}

/**
 * Marks friends who've walked enough as qualified and expires the rest, then
 * pays out. Returns the referrers to tell, with the friend they can thank.
 */
export async function settleReferrals(): Promise<
  Array<{ referrer_id: string; referee_id: string; count: number; notify: boolean }>
> {
  await linkTypedReferrals();
  const rows = await db.query<{ referee_id: string; referrer_id: string; days: number; origin: string }>(
    `${progressSql("r.status = 'pending'")} HAVING COUNT(*) FILTER (WHERE d.miles >= ${STREAK_QUALIFYING_MILES}) >= ${QUALIFYING_DAYS}`,
  );

  const settled: Array<{ referrer_id: string; referee_id: string; count: number; notify: boolean }> = [];
  for (const row of rows) {
    const updated = await db.query(
      `UPDATE referrals SET status = 'qualified', qualified_at = NOW()
        WHERE referee_id = $1 AND status = 'pending' RETURNING referee_id`,
      [row.referee_id],
    );
    if (updated.length === 0) continue;
    // The friend who joined and stuck with it earns the first medal too.
    await db.query(
      `INSERT INTO user_badges (user_id, badge_id, earned_at) VALUES ($1, 'referral_buddy', NOW())
       ON CONFLICT (user_id, badge_id) DO NOTHING`,
      [row.referee_id],
    );
    const count = await qualifiedCount(row.referrer_id);
    await grantEarned(row.referrer_id, count);
    // A backfilled referral may be months old, and one person could have many,
    // so those arrive quietly instead of as a burst of pushes.
    settled.push({ referrer_id: row.referrer_id, referee_id: row.referee_id, count, notify: row.origin === "picked" });
  }

  await db.query(
    `UPDATE referrals SET status = 'expired'
      WHERE status = 'pending' AND created_at < NOW() - interval '${QUALIFYING_WINDOW_DAYS + 3} days'`,
  );
  return settled;
}

/** Records every reward reached and applies the automatic ones, once each. */
async function grantEarned(userId: string, count: number): Promise<void> {
  for (const reward of REFERRAL_REWARDS.filter((r) => r.count <= count)) {
    const fresh = await db.query(
      `INSERT INTO referral_rewards (user_id, reward_count) VALUES ($1, $2)
       ON CONFLICT (user_id, reward_count) DO NOTHING RETURNING reward_count`,
      [userId, reward.count],
    );
    if (fresh.length === 0) continue;
    if (reward.badgeId) {
      await db.query(
        `INSERT INTO user_badges (user_id, badge_id, earned_at) VALUES ($1, $2, NOW())
         ON CONFLICT (user_id, badge_id) DO NOTHING`,
        [userId, reward.badgeId],
      );
    }
    if (reward.kind === "token") await grantStreakAssist([userId]);
  }
}

export async function getReferralStatus(userId: string) {
  const [me] = await db.query<{ username: string | null; can_link: boolean }>(
    `SELECT username, created_at >= NOW() - interval '${LINK_WINDOW_DAYS} days' AS can_link
       FROM users WHERE user_id = $1`,
    [userId],
  );
  const [friends, mine, earned, code, plus] = await Promise.all([
    db.query<{ username: string | null; first_name: string | null; profile_image_url: string | null; status: string; days: number; created_at: string }>(
      `SELECT u.username, u.first_name, u.profile_image_url, p.status, p.days, p.created_at
         FROM (${progressSql("r.referrer_id = $1 AND r.status <> 'rejected'")}) p
         JOIN users u ON u.user_id = p.referee_id
        ORDER BY CASE p.status WHEN 'pending' THEN 0 WHEN 'qualified' THEN 1 ELSE 2 END, p.created_at DESC`,
      [userId],
    ),
    db.query<{ username: string | null; first_name: string | null; status: string; days: number }>(
      `SELECT u.username, u.first_name, p.status, p.days
         FROM (${progressSql("r.referee_id = $1")}) p
         JOIN users u ON u.user_id = p.referrer_id`,
      [userId],
    ),
    db.query<{ reward_count: number; claimed_at: string | null }>(
      `SELECT reward_count, claimed_at FROM referral_rewards WHERE user_id = $1`,
      [userId],
    ),
    db.query<{ code: string }>(`SELECT code FROM referral_offer_codes WHERE assigned_to = $1 LIMIT 1`, [userId]),
    getPlusStatus(userId),
  ]);

  const qualified = friends.filter((f) => f.status === "qualified").length;
  const reached = new Map(earned.map((r) => [r.reward_count, r.claimed_at]));
  return {
    username: me?.username ?? null,
    days_needed: QUALIFYING_DAYS,
    window_days: QUALIFYING_WINDOW_DAYS,
    qualified,
    has_plus: plus?.is_plus === true,
    can_add_referrer: Boolean(me?.can_link) && mine.length === 0,
    referred_by: mine[0] ?? null,
    friends: friends.map((f) => ({
      username: f.username,
      first_name: f.first_name,
      profile_image_url: f.profile_image_url,
      status: f.status,
      days: Math.min(f.days, QUALIFYING_DAYS),
    })),
    rewards: offeredRewards().map((r) => ({
      count: r.count,
      kind: r.kind,
      title: r.title,
      description: r.description,
      item_id: r.itemId ?? null,
      state: !reached.has(r.count) ? "locked" : reached.get(r.count) ? "claimed" : "earned",
      // Only ever the owner's own code, and only for the reward that gave it.
      code: r.kind === "free_year" ? (code[0]?.code ?? null) : null,
    })),
  };
}

/**
 * For the admin view: who's referring, what they've earned, and anything that
 * looks off. Flags are prompts for a human, never automatic decisions.
 */
export async function getReferralOverview() {
  const [totals, referrers, recent, codes] = await Promise.all([
    db.query<{ pending: number; qualified: number; expired: number; rejected: number }>(
      `SELECT COUNT(*) FILTER (WHERE status = 'pending')::int AS pending,
              COUNT(*) FILTER (WHERE status = 'qualified')::int AS qualified,
              COUNT(*) FILTER (WHERE status = 'expired')::int AS expired,
              COUNT(*) FILTER (WHERE status = 'rejected')::int AS rejected
         FROM referrals`,
    ),
    db.query<{
      user_id: string;
      username: string | null;
      qualified: number;
      pending: number;
      expired: number;
      biggest_day: number;
      free_year: boolean;
    }>(
      `WITH per_day AS (
         SELECT referrer_id, created_at::date AS day, COUNT(*)::int AS n
           FROM referrals WHERE origin = 'picked' GROUP BY 1, 2
       )
       SELECT r.referrer_id AS user_id, u.username,
              COUNT(*) FILTER (WHERE r.status = 'qualified')::int AS qualified,
              COUNT(*) FILTER (WHERE r.status = 'pending')::int AS pending,
              COUNT(*) FILTER (WHERE r.status = 'expired')::int AS expired,
              COALESCE((SELECT MAX(n) FROM per_day p WHERE p.referrer_id = r.referrer_id), 0)::int AS biggest_day,
              EXISTS (SELECT 1 FROM referral_offer_codes c WHERE c.assigned_to = r.referrer_id) AS free_year
         FROM referrals r
         JOIN users u ON u.user_id = r.referrer_id
        WHERE r.status <> 'rejected'
        GROUP BY r.referrer_id, u.username
        ORDER BY qualified DESC, pending DESC
        LIMIT 100`,
    ),
    db.query<{ referee: string | null; referrer: string | null; status: string; origin: string; created_at: string }>(
      `SELECT friend.username AS referee, referrer.username AS referrer, r.status, r.origin, r.created_at
         FROM referrals r
         JOIN users friend ON friend.user_id = r.referee_id
         JOIN users referrer ON referrer.user_id = r.referrer_id
        ORDER BY r.created_at DESC LIMIT 50`,
    ),
    db.query<{ left: number; used: number }>(
      `SELECT COUNT(*) FILTER (WHERE assigned_to IS NULL)::int AS left,
              COUNT(*) FILTER (WHERE assigned_to IS NOT NULL)::int AS used
         FROM referral_offer_codes`,
    ),
  ]);
  return {
    totals: totals[0],
    codes: codes[0],
    referrers: referrers.map((r) => ({ ...r, flagged: r.biggest_day >= FLAG_LINKS_PER_DAY })),
    recent,
  };
}

/**
 * Support's fix for a referral that didn't connect. Skips the 14-day window,
 * since that's usually why they're writing in, but no other rule. It starts
 * from the friend's sign-up date, like every other referral, and a pending
 * link can be corrected. A counted one can't: its rewards have gone out.
 */
export async function adminLinkReferral(refereeUsername: string, referrerUsername: string): Promise<void> {
  const find = (handle: string) =>
    db.query<{ user_id: string }>(
      `SELECT user_id FROM users WHERE lower(username) = lower($1)`,
      [handle.trim().replace(/^@/, "")],
    );
  const [[friend], [referrer]] = await Promise.all([find(refereeUsername), find(referrerUsername)]);
  if (!friend) throw new ReferralError("no_friend", "No account with the friend's username.", 404);
  if (!referrer) throw new ReferralError("no_referrer", "No account with the referrer's username.", 404);
  if (friend.user_id === referrer.user_id) throw new ReferralError("self", "Those are the same account.");

  const loop = await db.query(`SELECT 1 FROM referrals WHERE referee_id = $1 AND referrer_id = $2`, [
    referrer.user_id,
    friend.user_id,
  ]);
  if (loop.length > 0) throw new ReferralError("loop", "That would make a loop: they already referred each other.");

  const saved = await db.query(
    `INSERT INTO referrals (referee_id, referrer_id, origin, created_at)
     VALUES ($1, $2, 'admin', (SELECT created_at FROM users WHERE user_id = $1))
     ON CONFLICT (referee_id) DO UPDATE
       SET referrer_id = EXCLUDED.referrer_id, origin = 'admin'
       WHERE referrals.status <> 'qualified'
     RETURNING referee_id`,
    [friend.user_id, referrer.user_id],
  );
  if (saved.length === 0) throw new ReferralError("already_counted", "That referral already counted, so it can't be moved.", 409);

  // A link made late may already have enough days behind it.
  await settleReferrals();
}

/**
 * Takes a suspicious referral out of the count. Rewards already earned stay:
 * taking one back is a decision for a person, with the user told why.
 */
export async function adminRejectReferral(refereeUsername: string): Promise<void> {
  const rows = await db.query(
    `UPDATE referrals SET status = 'rejected'
      WHERE referee_id = (SELECT user_id FROM users WHERE lower(username) = lower($1))
      RETURNING referee_id`,
    [refereeUsername.trim().replace(/^@/, "")],
  );
  if (rows.length === 0) throw new ReferralError("no_referral", "That account has no referral.", 404);
}

/** Hands out the free year's offer code. Safe to repeat: the same code returns. */
export async function claimFreeYear(userId: string): Promise<string> {
  const reward = REFERRAL_REWARDS.find((r) => r.kind === "free_year")!;
  const [row] = await db.query<{ claimed_at: string | null }>(
    `SELECT claimed_at FROM referral_rewards WHERE user_id = $1 AND reward_count = $2`,
    [userId, reward.count],
  );
  if (!row) throw new ReferralError("locked", "You haven't reached this reward yet.", 403);

  const held = await db.query<{ code: string }>(`SELECT code FROM referral_offer_codes WHERE assigned_to = $1 LIMIT 1`, [userId]);
  if (held[0]) return held[0].code;

  if ((await getPlusStatus(userId))?.is_plus) {
    throw new ReferralError("already_plus", "You already have Mile A Day+. This reward stays here for later.", 409);
  }

  // SKIP LOCKED: two people claiming at once never get the same code.
  const assigned = await db.query<{ code: string }>(
    `UPDATE referral_offer_codes SET assigned_to = $1, assigned_at = NOW()
      WHERE code = (
        SELECT code FROM referral_offer_codes WHERE assigned_to IS NULL LIMIT 1 FOR UPDATE SKIP LOCKED
      ) RETURNING code`,
    [userId],
  );
  if (!assigned[0]) throw new ReferralError("no_codes", "We've run out of codes for a moment. Contact us and we'll sort it.", 503);

  await db.query(`UPDATE referral_rewards SET claimed_at = NOW() WHERE user_id = $1 AND reward_count = $2`, [
    userId,
    reward.count,
  ]);
  return assigned[0].code;
}
