/**
 * Morning briefing check — what was held overnight (quiet hours / the daily
 * cap) must come back as the notifications themselves, not as a count.
 *
 * Every failure here is silent: the phone just shows a vaguer push, or none.
 *   1. "For you" news (requests, mentions, comments…) rings as ITSELF — its
 *      own title, body and data, so the tap lands on the post/person — in
 *      priority order, at most three kinds, several of a kind folded into the
 *      newest with "+N more".
 *   2. Everything else becomes ONE summary line that names what it holds.
 *   3. Yesterday's nudges and lead changes are dropped (moot by morning).
 *   4. Quiet hours are the USER's local hours, not New York's.
 *   5. Held rows keep their full payload.
 *
 * Usage (same env as ci-smoke):
 *   DATABASE_URL=... node scripts/morning-briefing-check.mjs
 */
import { PostgresService } from "../dist/services/DbService.js";
import {
  hourInWindow,
  localHourFor,
  planBriefing,
  sendPush,
} from "../dist/services/pushNotificationService.js";

const db = PostgresService.getInstance();
const USER = "briefing-check-user";

let failures = 0;
function check(label, actual, expected) {
  const ok = JSON.stringify(actual) === JSON.stringify(expected);
  if (!ok) failures++;
  console.log(
    `${ok ? "ok  " : "FAIL"}  ${label} → ${JSON.stringify(actual)} (expected ${JSON.stringify(expected)})`,
  );
}

let seq = 0;
function row(
  type,
  {
    title = type,
    body = `${type} body`,
    data = null,
    hoursAgo = 1,
    reason = "quiet",
  } = {},
) {
  seq += 1;
  return {
    id: `id-${seq}`,
    user_id: USER,
    type,
    competition_id: null,
    competition_name: title,
    body,
    data,
    category: null,
    reason,
    created_at: new Date(
      NOW.getTime() - hoursAgo * 3600_000 + seq * 1000,
    ).toISOString(),
  };
}

// Mid-morning UTC on a fixed day, so "yesterday" is unambiguous.
const NOW = new Date("2026-10-01T14:00:00Z");

async function main() {
  // ── 1-3: the plan ─────────────────────────────────────────────────────
  const rows = [
    row("hype_received"),
    row("hype_received"),
    row("friend_activity"),
    row("post_comment", {
      title: "Sam commented",
      body: "Sam: nice walk!",
      data: { post_id: "p1" },
    }),
    row("post_comment", {
      title: "Jo commented",
      body: "Jo: 🔥",
      data: { post_id: "p2" },
    }),
    row("mention", {
      title: "Ava mentioned you",
      body: "@you come walk",
      data: { post_id: "p3" },
    }),
    row("friend_request", {
      title: "New friend request",
      body: "Lee wants to be friends",
      data: { sender_id: "lee" },
    }),
    row("badge_earned", { title: "Medal", body: "Elite Runner" }),
    row("friend_nudge", { hoursAgo: 20 }), // yesterday → stale
    row("lead_change", { hoursAgo: 1 }), // today → kept, chatter
  ];
  const plan = planBriefing(rows, NOW, 0);

  check(
    "for-you news rings as itself, in priority order",
    plan.individual.map((p) => p.type),
    ["friend_request", "mention", "post_comment"],
  );
  check("...with its own title", plan.individual[1].title, "Ava mentioned you");
  check("...and its own data, so the tap lands", plan.individual[1].data, {
    post_id: "p3",
  });
  check(
    "several of one kind fold into the newest + count",
    plan.individual[2].body,
    "Jo: 🔥 · +1 more",
  );
  check("...tapping through to the NEWEST one", plan.individual[2].data, {
    post_id: "p2",
  });
  check("yesterday's nudge is dropped", plan.droppedStale, 1);
  check(
    "the rest is one summary",
    plan.summary?.title,
    "Also while you were away",
  );
  check(
    "...naming for-you news first, then the chatter",
    plan.summary?.body,
    "1 badge, 2 hypes and 2 more",
  );

  // A lone non-for-you item still arrives as itself.
  const lone = planBriefing(
    [
      row("friend_post", {
        title: "Sam posted",
        body: "Sam shared a walk",
        data: { post_id: "p9" },
      }),
    ],
    NOW,
    0,
  );
  check(
    "a single held item is delivered as itself",
    lone.individual[0]?.body,
    "Sam shared a walk",
  );
  check("...with no summary", lone.summary, null);

  // ── 4: local quiet hours ──────────────────────────────────────────────
  // 14:00 UTC is 07:00 in Los Angeles (-420) — inside a 22–8 window — but
  // 10:00 in New York, which is where the old check ran for everyone.
  check("local hour honours the user's own offset", localHourFor(-420, NOW), 7);
  check(
    "...so 7 AM in LA is still quiet",
    hourInWindow(localHourFor(-420, NOW), 22, 8),
    true,
  );
  check(
    "...while 3 PM in London isn't",
    hourInWindow(localHourFor(60, NOW), 22, 8),
    false,
  );

  // ── 5: a held push keeps its whole payload ────────────────────────────
  await db.query(`DELETE FROM in_app_notifications WHERE user_id = $1`, [USER]);
  await db.query(`DELETE FROM pending_notifications WHERE user_id = $1`, [
    USER,
  ]);
  await db.query(`DELETE FROM notification_settings WHERE user_id = $1`, [
    USER,
  ]);
  await db.query(`DELETE FROM users WHERE user_id = $1`, [USER]);
  await db.query(
    `INSERT INTO users (user_id, apple_sub, email, username, first_name)
     VALUES ($1, 'sub-briefing', 'briefing@example.com', 'briefing', 'Briefing')`,
    [USER],
  );
  // A quiet window covering the current UTC hour, in a UTC zone, so the
  // push below is held.
  const h = new Date().getUTCHours();
  await db.query(
    `INSERT INTO notification_settings (user_id, quiet_hours_start, quiet_hours_end, timezone_offset_minutes)
     VALUES ($1, $2, $3, 0)`,
    [USER, h, (h + 2) % 24],
  );
  await sendPush(USER, {
    title: "Sam commented",
    body: "Sam: nice walk!",
    type: "post_comment",
    data: { post_id: "p1" },
  });
  const held = await db.query(
    `SELECT type, competition_name, body, data, reason FROM pending_notifications WHERE user_id = $1`,
    [USER],
  );
  check("a quiet-hours push is held", held.length, 1);
  check("...with its body", held[0]?.body, "Sam: nice walk!");
  check("...and its data", held[0]?.data, { post_id: "p1" });
  check("...and why", held[0]?.reason, "quiet");

  await new Promise((r) => setTimeout(r, 300));
  await db.query(`DELETE FROM in_app_notifications WHERE user_id = $1`, [USER]);
  await db.query(`DELETE FROM pending_notifications WHERE user_id = $1`, [
    USER,
  ]);
  await db.query(`DELETE FROM notification_log WHERE user_id = $1`, [USER]);
  await db.query(`DELETE FROM notification_settings WHERE user_id = $1`, [
    USER,
  ]);
  await db.query(`DELETE FROM users WHERE user_id = $1`, [USER]);

  console.log(
    failures === 0
      ? "morning-briefing-check: all assertions passed"
      : `morning-briefing-check: ${failures} FAILED`,
  );
  process.exit(failures === 0 ? 0 : 1);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
