/**
 * Widget refresh silent-push check (widgetRefreshService).
 *
 * Every failure here is invisible: a silent push renders nothing, so a push
 * to the wrong device, a missing coalescing claim or a wrong APNs header just
 * means a widget that never moves — or an app woken 60 times an hour until
 * Apple starts dropping its pushes. So the rules are pinned against a real DB
 * with the APNs transport swapped for a recorder:
 *
 *   - registration stores `widget_kinds` (sanitized; absent ⇒ NULL);
 *   - only devices declaring `widget_refresh_push_v1` AND reporting the
 *     affected widget kind are pushed (NULL widget_kinds never is);
 *   - one push per user per coalescing window, across reasons;
 *   - the actor is excluded; the kill switch stops everything;
 *   - nothing lands in the inbox or notification_log;
 *   - the built APNs request is background / priority 5 / content-available
 *     only, with string-valued data.
 *
 * Usage (same env as ci-smoke):
 *   DATABASE_URL=... node scripts/widget-refresh-check.mjs
 */
import { PostgresService } from "../dist/services/DbService.js";
import {
  buildSilentPushRequest,
  registerDeviceToken,
  setSilentPushTransportForTesting,
} from "../dist/services/pushNotificationService.js";
import {
  requestWidgetRefresh,
  refreshFriendsLeaderboardWidgets,
  WIDGET_REFRESH_WINDOW_MINUTES,
} from "../dist/services/widgetRefreshService.js";

const db = PostgresService.getInstance();

const ACTOR = "wr-actor"; // the syncing user
const FULL = "wr-full"; // new build, both widgets → pushed
const LB_ONLY = "wr-lbonly"; // new build, leaderboard widget only
const OLD = "wr-old"; // shipped build: no feature, no widget_kinds
const NO_WIDGET = "wr-nowidget"; // new build, reported NO widgets
const NULL_KINDS = "wr-nullkinds"; // feature declared but widget_kinds absent
const MIXED = "wr-mixed"; // two devices: one eligible, one shipped build
const ALL = [ACTOR, FULL, LB_ONLY, OLD, NO_WIDGET, NULL_KINDS, MIXED];

const FEATURE = "widget_refresh_push_v1";
const COMP = "CompetitionWidget";
const LB = "DailyLeaderboardWidget";

let failures = 0;
function check(label, actual, expected) {
  const a = JSON.stringify(actual);
  const e = JSON.stringify(expected);
  const ok = a === e;
  if (!ok) failures++;
  console.log(`${ok ? "ok  " : "FAIL"}  ${label} → ${a}${ok ? "" : ` (expected ${e})`}`);
}

const sent = [];
setSilentPushTransportForTesting(async (token, type, data, environment) => {
  sent.push({ token, type, data, environment });
  return true;
});
const drain = () => sent.splice(0, sent.length);
const tokensOf = (pushes) => pushes.map((p) => p.token).sort();

async function cleanup() {
  await db.query(`DELETE FROM widget_refresh_pushes WHERE user_id = ANY($1)`, [ALL]);
  await db.query(`DELETE FROM in_app_notifications WHERE user_id = ANY($1)`, [ALL]);
  await db.query(`DELETE FROM notification_log WHERE user_id = ANY($1)`, [ALL]);
  await db.query(`DELETE FROM friendships WHERE user_id = ANY($1) OR friend_id = ANY($1)`, [ALL]);
  await db.query(`DELETE FROM device_tokens WHERE user_id = ANY($1)`, [ALL]);
  await db.query(`DELETE FROM users WHERE user_id = ANY($1)`, [ALL]);
}

async function seed() {
  for (const id of ALL) {
    await db.query(
      `INSERT INTO users (user_id, username, apple_sub, email) VALUES ($1, $2, $3, $4)`,
      [id, id, id, `${id}@example.com`],
    );
  }
  // Through the real registration path, so the sanitizing is under test too.
  await registerDeviceToken(FULL, "wr-t-full", "sandbox", [FEATURE], [COMP, LB, "NotAWidget"]);
  await registerDeviceToken(LB_ONLY, "wr-t-lbonly", "production", [FEATURE], [LB]);
  await registerDeviceToken(OLD, "wr-t-old", "production", ["friend_request_v2"]);
  await registerDeviceToken(NO_WIDGET, "wr-t-nowidget", "production", [FEATURE], []);
  await registerDeviceToken(NULL_KINDS, "wr-t-nullkinds", "production", [FEATURE]);
  await registerDeviceToken(MIXED, "wr-t-mixed-new", "production", [FEATURE], [COMP, LB]);
  await registerDeviceToken(MIXED, "wr-t-mixed-old", "production", []);
  await registerDeviceToken(ACTOR, "wr-t-actor", "production", [FEATURE], [COMP, LB]);
  for (const friend of [FULL, LB_ONLY, OLD, NO_WIDGET, NULL_KINDS, MIXED]) {
    await db.query(
      `INSERT INTO friendships (user_id, friend_id, status) VALUES ($1, $2, 'accepted'), ($2, $1, 'accepted')`,
      [ACTOR, friend],
    );
  }
}

try {
  await cleanup();
  await seed();

  // ── 1. The APNs request shape (pure).
  const req = buildSilentPushRequest("tok", "widget_refresh", { type: "widget_refresh", reason: "h2h" }, "com.example.app", "jwt");
  check("push type is background", req.headers["apns-push-type"], "background");
  check("priority is 5", req.headers["apns-priority"], "5");
  check("topic is the bundle id", req.headers["apns-topic"], "com.example.app");
  const body = JSON.parse(req.body);
  check("aps carries ONLY content-available", body.aps, { "content-available": 1 });
  check("top-level type", body.type, "widget_refresh");
  check("data is string-valued", Object.values(body.data).every((v) => typeof v === "string"), true);

  // ── 2. Registration stores widget kinds, sanitized; absent ⇒ NULL.
  const kinds = async (token) =>
    (await db.query(`SELECT widget_kinds FROM device_tokens WHERE device_token = $1`, [token]))[0]?.widget_kinds ?? null;
  check("unknown kinds dropped", (await kinds("wr-t-full")).sort(), [COMP, LB].sort());
  check("absent widget_kinds stores NULL", await kinds("wr-t-nullkinds"), null);
  check("reported-none stores []", await kinds("wr-t-nowidget"), []);

  // ── 3. Competition refresh: feature + CompetitionWidget only.
  let r = await requestWidgetRefresh([FULL, LB_ONLY, OLD, NO_WIDGET, NULL_KINDS, MIXED], "competition");
  let pushes = drain();
  check("competition pushes only eligible devices", tokensOf(pushes), ["wr-t-full", "wr-t-mixed-new"]);
  check("…claims exactly those users", r.claimed.sort(), [FULL, MIXED].sort());
  check("…with the reason in string data", pushes[0]?.data, { type: "widget_refresh", reason: "competition" });
  check("…typed widget_refresh", pushes[0]?.type, "widget_refresh");
  check("…to the token's own environment", pushes.find((p) => p.token === "wr-t-full")?.environment, "sandbox");

  // ── 4. Coalescing: inside the window, nobody already pushed is pushed again
  //       — for ANY reason — while a user not yet pushed still is.
  r = await requestWidgetRefresh([FULL, MIXED, LB_ONLY], "leaderboard");
  pushes = drain();
  check("second event inside the window only reaches the unclaimed user", tokensOf(pushes), ["wr-t-lbonly"]);
  r = await requestWidgetRefresh([FULL, LB_ONLY], "h2h");
  check("third event: everybody coalesced", drain().length, 0);
  check("…still reported eligible", r.eligible, 2);

  // Age FULL's claim past the window → pushable again.
  await db.query(
    `UPDATE widget_refresh_pushes SET last_sent_at = NOW() - make_interval(mins => $2) - INTERVAL '1 second' WHERE user_id = $1`,
    [FULL, WIDGET_REFRESH_WINDOW_MINUTES],
  );
  await requestWidgetRefresh([FULL, LB_ONLY], "h2h");
  check("after the window, the aged user is pushed again", tokensOf(drain()), ["wr-t-full"]);
  check(
    "…and the claim records the reason",
    (await db.query(`SELECT last_reason FROM widget_refresh_pushes WHERE user_id = $1`, [FULL]))[0]?.last_reason,
    "h2h",
  );

  // ── 5. Friends leaderboard fan-out: friends with the widget, never the actor.
  await db.query(`DELETE FROM widget_refresh_pushes WHERE user_id = ANY($1)`, [ALL]);
  r = await refreshFriendsLeaderboardWidgets(ACTOR);
  pushes = drain();
  check("leaderboard fan-out reaches friends with the widget", tokensOf(pushes), ["wr-t-full", "wr-t-lbonly", "wr-t-mixed-new"]);
  check("…never the actor", pushes.some((p) => p.token === "wr-t-actor"), false);
  check("explicit exclusion of the actor", (await requestWidgetRefresh([ACTOR], "competition", ACTOR)).eligible, 0);

  // ── 6. Kill switch.
  await db.query(`DELETE FROM widget_refresh_pushes WHERE user_id = ANY($1)`, [ALL]);
  process.env.WIDGET_REFRESH_PUSH_DISABLED = "true";
  r = await requestWidgetRefresh([FULL], "competition");
  check("kill switch sends nothing", drain().length, 0);
  check("…and claims nothing", (await db.query(`SELECT 1 FROM widget_refresh_pushes WHERE user_id = ANY($1)`, [ALL])).length, 0);
  delete process.env.WIDGET_REFRESH_PUSH_DISABLED;

  // ── 7. Silent means silent: no inbox rows, no cap consumption.
  check("no inbox rows written", (await db.query(`SELECT 1 FROM in_app_notifications WHERE user_id = ANY($1)`, [ALL])).length, 0);
  check("no notification_log rows written", (await db.query(`SELECT 1 FROM notification_log WHERE user_id = ANY($1)`, [ALL])).length, 0);
} finally {
  setSilentPushTransportForTesting(null);
  await cleanup();
  await db.close();
}

if (failures) {
  console.error(`\n${failures} check(s) failed`);
  process.exit(1);
}
console.log("\nwidget-refresh check passed");
process.exit(0);
