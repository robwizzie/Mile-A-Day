import { PostgresService } from "./DbService.js";
import { TODAY_ET_DATE_SQL } from "./dailyResetTime.js";
import { getTodayMiles } from "./workoutService.js";
import { getGrowth, getRival, latestReviews, listDeskBoxes } from "./displayService.js";
import { getState, pruneDeskPushLog, pushConfigured, pushTo, pushToAdmins, setState } from "./deskPushService.js";

const db = PostgresService.getInstance();

/**
 * The desk push poller (once a minute, see cron/deskPushCron.ts): looks for
 * events nothing else announces and pushes each one once. Its memory lives
 * in desk_push_state, so a restart never repeats or floods: a key it has
 * never seen is only recorded (no push) the first time.
 */
export async function runDeskPushChecks(): Promise<void> {
  if (!pushConfigured()) return;
  await pruneDeskPushLog();
  const subs = await db.query<{ user_id: string; kinds: string[] }>(
    `SELECT user_id, kinds FROM desk_push_subscriptions`);
  if (subs.length === 0) return;
  const wants = (kind: string) => [...new Set(subs.filter((s) => s.kinds.includes(kind)).map((s) => s.user_id))];
  await checkUsers();
  await checkReviews();
  await checkRecord();
  for (const owner of wants("lead")) await checkLead(owner);
  for (const owner of wants("box_offline")) await checkBoxes(owner);
}

async function checkUsers() {
  const [{ n }] = await db.query<{ n: number }>(`SELECT COUNT(*)::int AS n FROM users`);
  const prev = Number(await getState("users"));
  await setState("users", String(n));
  if (!prev || n <= prev) return;
  const diff = n - prev;
  await pushToAdmins("new_user", diff === 1
    ? { title: "New user! 🎉", body: `#${n.toLocaleString("en-US")} just joined Mile A Day`, tag: "new_user" }
    : { title: `${diff} new users 🎉`, body: `Mile A Day is at ${n.toLocaleString("en-US")} people`, tag: "new_user" });
  if (Math.floor(n / 50) > Math.floor(prev / 50)) {
    const m = Math.floor(n / 50) * 50;
    await pushToAdmins("user_milestone", { title: `${m.toLocaleString("en-US")} users!`, body: "Another milestone for Mile A Day. Party on the desks 🎉", tag: "milestone" });
  }
}

async function checkReviews() {
  const reviews = await latestReviews();
  if (!reviews.length) return;
  const seen: string[] = JSON.parse((await getState("reviews")) ?? "null") ?? [];
  const first = !(await getState("reviews"));
  await setState("reviews", JSON.stringify([...new Set([...reviews.map((r) => r.id), ...seen])].slice(0, 30)));
  if (first) return;
  for (const r of reviews.filter((r) => !seen.includes(r.id)).reverse()) {
    await pushToAdmins("review", { title: `${"★".repeat(r.stars)}${"☆".repeat(5 - r.stars)} New App Store review`, body: r.title || "(no title)", tag: `review-${r.id}` });
  }
}

async function checkRecord() {
  const g = await getGrowth();
  const [{ day }] = await db.query<{ day: string }>(`SELECT (${TODAY_ET_DATE_SQL})::text AS day`);
  if (!(g.best_30 > 0 && g.today > g.best_30) || (await getState("record_day")) === day) return;
  await setState("record_day", day);
  await pushToAdmins("record", { title: "Record signup day! 📈", body: `${g.today} new people today (best of the last 30 days was ${g.best_30})`, tag: "record" });
}

async function checkLead(owner: string) {
  const rival = await getRival(owner);
  const key = `lead:${owner}`;
  if (!rival) return;
  const a = Number(await getTodayMiles(owner)) || 0;
  const b = rival.miles_today;
  const leader = Math.abs(a - b) < 0.005 ? null : a > b ? "me" : "rival";
  const prev = JSON.parse((await getState(key)) ?? "null") as { leader: string | null; a: number; b: number } | null;
  await setState(key, JSON.stringify({ leader, a, b }));
  if (!prev || !leader || leader === prev.leader) return;
  const ran = leader === "me" ? a > prev.a + 0.005 : b > prev.b + 0.005;     // midnight resets don't count
  if (!ran) return;
  await pushTo([owner], "lead", leader === "me"
    ? { title: "You took the lead 👑", body: `${a.toFixed(2)} vs ${b.toFixed(2)} mi today against @${rival.name}`, tag: "lead" }
    : { title: `@${rival.name} took the lead`, body: `${b.toFixed(2)} vs your ${a.toFixed(2)} mi today. Time for a run?`, tag: "lead" });
}

async function checkBoxes(owner: string) {
  for (const box of await listDeskBoxes(owner)) {
    const key = `box:${box.id}`;
    const now = box.online ? "on" : "off";
    const prev = await getState(key);
    if (prev === now) continue;
    await setState(key, now);
    if (!prev) continue;
    const name = box.label || "Your desk";
    await pushTo([owner], "box_offline", now === "off"
      ? { title: `${name} went offline`, body: "It hasn't checked in for 10 minutes. Wi-Fi or power?", tag: `box-${box.id}` }
      : { title: `${name} is back online`, body: "Checking in again.", tag: `box-${box.id}` });
  }
}
