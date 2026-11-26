import { CLIENT_FEATURES } from "../clientFeatures.js";
import { PostgresService } from "../DbService.js";
import { sendPush } from "../pushNotificationService.js";
import { addDays, notificationDueAt, notificationLocalTime } from "./engine.js";
import { claimProposalNotification, nextRunFor, notificationCandidates } from "./runPlanService.js";

/**
 * Spec §6: a push only when a pending proposal changes the NEXT run, at the
 * learned time — typical run hour before 9 → 8 PM local the evening before,
 * otherwise 9 AM local on the day. Once per proposal (notified_at claim);
 * only to devices declaring `run_plans_v2`; quiet hours and the daily cap
 * apply through sendPush like any other push.
 */

const db = PostgresService.getInstance();

export interface DueDecision {
  send: boolean;
  due_at: Date;
  when: "today" | "tonight" | "tomorrow";
}
/** Pure: is a proposal for `runDate` due at `now`? Sent from the due time until the run day ends (local). */
export function notificationDecision(typicalHour: number | null, runDate: string, offsetMinutes: number, now: Date): DueDecision {
  const due = notificationDueAt(typicalHour, runDate, offsetMinutes);
  const endOfRunDay = notificationDueAt(null, addDays(runDate, 1), offsetMinutes); // 9 AM next day: well past
  const t = notificationLocalTime(typicalHour, runDate);
  const when = t.local_date < runDate ? "tomorrow" : typicalHour != null && typicalHour >= 17 ? "tonight" : "today";
  return { send: now >= due && now < endOfRunDay, due_at: due, when };
}

export function proposalPushBody(when: string, before: string | null, after: string, reason: string): string {
  const swap = before ? `${after} instead of ${before}` : after;
  return `Suggested for ${when}: ${swap}. ${reason.replace(/\.$/, "")}. Tap to decide.`.slice(0, 240);
}

export async function sendRunPlanProposalNotifications(now: Date = new Date()): Promise<{ candidates: number; sent: number }> {
  const cands = await notificationCandidates();
  let sent = 0;
  const nextCache = new Map<string, Awaited<ReturnType<typeof nextRunFor>>>();
  for (const c of cands) {
    const localToday = new Date(now.getTime() + c.offset_minutes * 60_000).toISOString().slice(0, 10);
    if (!nextCache.has(c.user_id)) nextCache.set(c.user_id, await nextRunFor(c.user_id, localToday));
    const next = nextCache.get(c.user_id);
    if (!next) continue;
    const change = c.changes.find((x) => x.local_date === next.date);
    if (!change) continue; // only proposals for the next run notify
    const d = notificationDecision(c.typical_hour, next.date, c.offset_minutes, now);
    if (!d.send) continue;
    const supports = await db.query(`SELECT 1 FROM device_tokens WHERE user_id = $1 AND $2 = ANY(client_features) LIMIT 1`, [c.user_id, CLIENT_FEATURES.runPlansV2]);
    if (!supports.length) continue;
    if (!(await claimProposalNotification(c.proposal_id))) continue;
    const afterTitle = change.after.kind === "walk" ? "a walk day" : change.after.title;
    const beforeTitle = change.before ? (change.before.kind === "walk" ? "a walk day" : change.before.title) : null;
    await sendPush(
      c.user_id,
      {
        title: "Suggested change",
        body: proposalPushBody(d.when, beforeTitle, afterTitle, c.reason),
        type: "run_plan_proposal",
        category: "RUN_PLAN_PROPOSAL",
        data: { kind: "run_plan_proposal", proposal_id: c.proposal_id, local_date: next.date },
      },
      { deviceFeature: { feature: CLIENT_FEATURES.runPlansV2, supported: true } },
    );
    sent++;
  }
  return { candidates: cands.length, sent };
}
