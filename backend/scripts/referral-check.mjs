/**
 * Referral check.
 *
 * Free Plus hangs off these rules, so each way to game them is pinned:
 *
 *   1. Only a real, unblocked account can be picked, and never yourself.
 *   2. One referrer per person, no loops, and only while the account is new.
 *   3. Nothing counts until the friend walks 7 different days within 30.
 *   4. Manual workouts and short days don't count toward that.
 *   5. Every reward lands once, and the friend gets their medal.
 *   6. Offer codes reach one person, repeat claims return the same code, and
 *      someone with Plus keeps the reward for later.
 *   7. Lifetime stays hidden until it's switched on.
 *   8. Routes are self-only.
 *   9. Past typed names link to real accounts only, and never reverse a
 *      signup order, cross a block or replace a picked referrer.
 */
import express from "express";
import { PostgresService } from "../dist/services/DbService.js";
import { authenticateToken } from "../dist/middleware/auth.js";
import referralRoutes from "../dist/routes/referralRoutes.js";
import { generateAccessToken } from "../dist/services/tokenService.js";
import { seedExtraBadges } from "../dist/services/badgeService.js";
import {
  claimFreeYear,
  getReferralStatus,
  linkTypedReferrals,
  setReferrer,
  settleReferrals,
} from "../dist/services/referralService.js";

const db = PostgresService.getInstance();

const REFERRER = "rf-referrer";
const FRIEND = "rf-friend";
const BLOCKED = "rf-blocked";
const OLD = "rf-old";
const LAZY = "rf-lazy";
const TYPED = "rf-typed";
const EARLY = "rf-early";
const GHOST = "rf-ghost";
const TEAM = "rf-team";
const BLOCKED_TYPED = "rf-blocked-typed";
const LATE = "rf-late";
const FRIENDS = Array.from({ length: 10 }, (_, i) => `rf-extra-${i}`);
const ALL = [REFERRER, FRIEND, BLOCKED, OLD, LAZY, TYPED, EARLY, GHOST, TEAM, BLOCKED_TYPED, LATE, ...FRIENDS];
const CODES = ["CHECKCODE1", "CHECKCODE2"];

let failures = 0;
function check(label, actual, expected) {
  const a = JSON.stringify(actual);
  const e = JSON.stringify(expected);
  const ok = a === e;
  if (!ok) failures++;
  console.log(`${ok ? "ok  " : "FAIL"}  ${label} → ${a}${ok ? "" : ` (expected ${e})`}`);
}
const errorCode = (fn) => fn().then(() => null, (e) => e.code ?? String(e));
const iso = (offset) => new Date(Date.now() + offset * 86_400_000).toISOString().slice(0, 10);
const handle = (u) => u.replaceAll("-", "_");

let seq = 0;
async function walk(userId, day, miles = 1, source = "healthkit") {
  await db.query(
    `INSERT INTO workouts (workout_id, user_id, distance, local_date, date, timezone_offset, workout_type,
                           device_end_date, calories, total_duration, source)
     VALUES ($1, $2, $3, $4::date, $4::date, 0, 'walking', $4::date + interval '12 hours', 100, 1200, $5)`,
    [`rf-w-${++seq}`, userId, miles, day, source],
  );
}
async function walkDays(userId, n) {
  for (let i = 0; i < n; i++) await walk(userId, iso(i));
}

async function cleanup() {
  await db.query(`DELETE FROM referral_offer_codes WHERE code = ANY($1) OR assigned_to = ANY($2)`, [CODES, ALL]);
  await db.query(`DELETE FROM user_blocks WHERE blocker_id = ANY($1) OR blocked_id = ANY($1)`, [ALL]);
  await db.query(`DELETE FROM workouts WHERE user_id = ANY($1)`, [ALL]);
  await db.query(`DELETE FROM users WHERE user_id = ANY($1)`, [ALL]);
}

const app = express();
app.use(express.json());
app.use(authenticateToken);
app.use("/users", referralRoutes);
const server = await new Promise((resolve) => {
  const s = app.listen(0, "127.0.0.1", () => resolve(s));
});
const base = `http://127.0.0.1:${server.address().port}`;

try {
  await cleanup();
  await seedExtraBadges();
  for (const u of ALL) {
    await db.query(
      `INSERT INTO users (user_id, email, apple_sub, username, first_name, streak_assist_last_used, created_at)
       VALUES ($1, $2, $3, $4, 'Rf', CURRENT_DATE, ${u === OLD ? "NOW() - interval '30 days'" : "NOW()"})`,
      [u, `${u}@example.test`, `${u}-sub`, handle(u)],
    );
  }
  await db.query(`INSERT INTO user_blocks (blocker_id, blocked_id) VALUES ($1, $2)`, [REFERRER, BLOCKED]);

  // 1 + 2. Picking someone.
  check("an account that doesn't exist", await errorCode(() => setReferrer(FRIEND, "nobody_here_xyz")), "not_found");
  check("yourself", await errorCode(() => setReferrer(FRIEND, handle(FRIEND))), "self");
  check("someone who blocked you", await errorCode(() => setReferrer(BLOCKED, handle(REFERRER))), "not_found");
  check("after the first 14 days", await errorCode(() => setReferrer(OLD, handle(REFERRER))), "window_closed");
  check("a real account, with an @", await errorCode(() => setReferrer(FRIEND, `@${handle(REFERRER).toUpperCase()}`)), null);
  check("only once", await errorCode(() => setReferrer(FRIEND, handle(LAZY))), "already_set");
  check("no loops", await errorCode(() => setReferrer(REFERRER, handle(FRIEND))), "loop");

  // 3 + 4. Earning it.
  await setReferrer(LAZY, handle(REFERRER));
  await walkDays(FRIEND, 6);
  await walk(FRIEND, iso(7), 5, "manual");
  await walk(FRIEND, iso(8), 0.3);
  await walkDays(LAZY, 2);
  await settleReferrals();
  let status = await getReferralStatus(REFERRER);
  check("6 real days doesn't count yet", status.qualified, 0);
  check("progress shows real days only", status.friends.find((f) => f.username === handle(FRIEND)).days, 6);
  check("no reward yet", status.rewards[0].state, "locked");

  await walk(FRIEND, iso(9));
  const settled = await settleReferrals();
  status = await getReferralStatus(REFERRER);
  check("the 7th day qualifies them", status.qualified, 1);
  check("the referrer is told once", settled.filter((s) => s.referee_id === FRIEND).length, 1);
  check("settling again changes nothing", (await settleReferrals()).filter((s) => s.referee_id === FRIEND).length, 0);
  check("first reward reached", status.rewards[0].state, "earned");
  check(
    "both people get the medal",
    (await db.query(`SELECT COUNT(*)::int AS n FROM user_badges WHERE badge_id = 'referral_buddy' AND user_id = ANY($1)`, [[REFERRER, FRIEND]]))[0].n,
    2,
  );
  check("the friend sees who referred them", (await getReferralStatus(FRIEND)).referred_by.username, handle(REFERRER));

  // 6. The free year.
  check("a locked reward can't be claimed", await errorCode(() => claimFreeYear(REFERRER)), "locked");
  for (const f of FRIENDS.slice(0, 9)) {
    await setReferrer(f, handle(REFERRER));
    await walkDays(f, 7);
  }
  await settleReferrals();
  status = await getReferralStatus(REFERRER);
  check("10 friends", status.qualified, 10);
  check("a Streak Assist landed at 3", (await db.query(`SELECT streak_assist_last_used FROM users WHERE user_id = $1`, [REFERRER]))[0].streak_assist_last_used, null);
  check("the free year is ready", status.rewards.find((r) => r.kind === "free_year").state, "earned");
  check("no codes left is said plainly", await errorCode(() => claimFreeYear(REFERRER)), "no_codes");

  await db.query(`INSERT INTO referral_offer_codes (code) SELECT unnest($1::text[])`, [CODES]);
  const code = await claimFreeYear(REFERRER);
  check("a code is handed out", CODES.includes(code), true);
  check("claiming again returns the same code", await claimFreeYear(REFERRER), code);
  check("only one code was used", (await db.query(`SELECT COUNT(*)::int AS n FROM referral_offer_codes WHERE assigned_to = $1`, [REFERRER]))[0].n, 1);
  check("the owner sees their code", (await getReferralStatus(REFERRER)).rewards.find((r) => r.kind === "free_year").code, code);
  check("nobody else does", (await getReferralStatus(FRIEND)).rewards.find((r) => r.kind === "free_year").code, null);

  // 7. Lifetime is hidden by default.
  check("lifetime is hidden", status.rewards.some((r) => r.kind === "lifetime"), false);
  process.env.REFERRAL_LIFETIME_ENABLED = "true";
  check("and shows once switched on", (await getReferralStatus(REFERRER)).rewards.some((r) => r.kind === "lifetime"), true);
  delete process.env.REFERRAL_LIFETIME_ENABLED;

  // 9. Names typed before accounts could be picked.
  const typed = (u, detail, source = "friend") =>
    db.query(`UPDATE users SET referral_source = $2, referral_detail = $3, created_at = NOW() - interval '200 days' WHERE user_id = $1`, [u, source, detail]);
  await db.query(`UPDATE users SET created_at = NOW() - interval '300 days' WHERE user_id = $1`, [OLD]);
  await typed(TYPED, ` @${handle(OLD).toUpperCase()} `);
  await typed(EARLY, handle(OLD));
  await db.query(`UPDATE users SET created_at = NOW() - interval '400 days' WHERE user_id = $1`, [EARLY]);
  await typed(GHOST, "somebody_not_real");
  await typed(TEAM, handle(OLD), "developer");
  await typed(BLOCKED_TYPED, handle(REFERRER));
  await db.query(`INSERT INTO user_blocks (blocker_id, blocked_id) VALUES ($1, $2)`, [REFERRER, BLOCKED_TYPED]);
  await typed(FRIEND, handle(OLD));

  // Days from the friend's real first month, not from today.
  for (let i = 0; i < 7; i++) await walk(TYPED, iso(-195 + i));
  await walk(TYPED, iso(-1));
  const newLinks = await linkTypedReferrals();
  const linkOf = async (u) => (await db.query(`SELECT referrer_id, origin FROM referrals WHERE referee_id = $1`, [u]))[0] ?? null;
  check("a typed name links, whatever its case or @", await linkOf(TYPED), { referrer_id: OLD, origin: "typed" });
  check("someone who joined before the referrer doesn't", await linkOf(EARLY), null);
  check("a name with no account doesn't", await linkOf(GHOST), null);
  check("a team referral isn't a friend referral", await linkOf(TEAM), null);
  check("a block keeps people apart", await linkOf(BLOCKED_TYPED), null);
  check("a picked referrer is never replaced", (await linkOf(FRIEND)).referrer_id, REFERRER);
  check("exactly one new link", newLinks >= 1, true);
  check("running it again changes nothing", await linkTypedReferrals(), 0);

  const retro = (await settleReferrals()).find((s) => s.referee_id === TYPED);
  check("7 days in their first month counts", retro?.count, 1);
  check("a backfilled referral stays quiet", retro?.notify, false);
  await typed(LATE, handle(OLD));
  await walkDays(LATE, 7);
  await settleReferrals();
  const oldFriends = (await getReferralStatus(OLD)).friends;
  check("everyone they referred is listed", oldFriends.map((f) => f.username).sort(), [handle(LATE), handle(TYPED)].sort());
  check("7 days long after signup doesn't count", oldFriends.find((f) => f.username === handle(LATE)).status, "expired");

  // 8. Routes.
  const headers = { authorization: `Bearer ${await generateAccessToken(FRIEND)}` };
  check("your own status", (await fetch(`${base}/users/${FRIEND}/referrals`, { headers })).status, 200);
  check("someone else's status", (await fetch(`${base}/users/${REFERRER}/referrals`, { headers })).status, 403);
  check(
    "someone else's code",
    (await fetch(`${base}/users/${REFERRER}/referrals/free-year`, { method: "POST", headers })).status,
    403,
  );
} catch (err) {
  failures++;
  console.error("FAIL  threw:", err);
} finally {
  await cleanup().catch(() => {});
  await new Promise((resolve) => server.close(resolve));
}

if (failures) {
  console.log(`referral-check: FAILED — ${failures} problem(s)`);
  process.exit(1);
}
console.log("referral-check: OK");
process.exit(0);
