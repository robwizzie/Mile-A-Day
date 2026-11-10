import cron from "node-cron";
import { PostgresService } from "../services/DbService.js";
import { runJob } from "./cronRunner.js";
import { sendPush } from "../services/pushNotificationService.js";
import { shouldSendNotification } from "../services/notificationSettingsService.js";
import { userOffsetMinutesOrNullSql } from "../services/dailyResetTime.js";
import {
  SPECIAL_EVENTS,
  SpecialEvent,
  claimEventPush,
  eventTargetMiles,
  milesOnEventDay,
} from "../services/specialEventService.js";

const db = PostgresService.getInstance();

/**
 * Special-event pushes, each at a local hour on a local day, claimed per
 * event+person+kind so a re-run or a restart never repeats one:
 *   announce  3 days before, 10:00  — every user
 *   day_of    on the day,    08:00  — every user who hasn't finished
 *   evening   on the day,    18:00  — started but not finished
 * The medal itself pushes through the ordinary `badge_earned` path.
 *
 * `special_event` is a new type: builds with the event screen route it there
 * (NotificationDestination); older builds have no route and open the app,
 * which is what an announcement wants anyway, so it is not gated per device.
 * Muted with the challenges switch (`weekly_challenge`), like community goals.
 */
interface EventPush {
  kind: "announce" | "day_of" | "evening";
  /** Days from the event's date to the push's local day. */
  offsetDays: number;
  hour: number;
  copy: (e: SpecialEvent, milesLeft: number) => { title: string; body: string };
  /** Who on the due list gets it, given their miles so far that day. */
  wants: (miles: number, target: number) => boolean;
}

const WEEKDAY = (date: string) =>
  new Date(`${date}T12:00:00Z`).toLocaleDateString("en-US", { weekday: "long", timeZone: "UTC" });
const MONTH_DAY = (date: string) =>
  new Date(`${date}T12:00:00Z`).toLocaleDateString("en-US", { month: "short", day: "numeric", timeZone: "UTC" });

const PUSHES: EventPush[] = [
  {
    kind: "announce",
    offsetDays: -3,
    hour: 10,
    copy: (e) => ({
      title: `${e.title} is ${WEEKDAY(e.date)}`,
      body: `Walk or run a 5K on ${MONTH_DAY(e.date)} to unlock Champ Shorts and Boxing Gloves for Flamey.`,
    }),
    wants: () => true,
  },
  {
    kind: "day_of",
    offsetDays: 0,
    hour: 8,
    copy: (e) => ({
      title: `Today's the day: ${e.title}`,
      body: `Every walk and run today adds up. Hit ${e.miles} mi by midnight to earn the gear.`,
    }),
    wants: (miles, target) => miles < target,
  },
  {
    kind: "evening",
    offsetDays: 0,
    hour: 18,
    copy: (e, left) => ({
      title: `${left.toFixed(1)} mi to the gear`,
      body: `You're on your way on ${e.title}. One more walk does it.`,
    }),
    wants: (miles, target) => miles > 0 && miles < target,
  },
];

function addDays(day: string, n: number): string {
  return new Date(Date.parse(`${day}T00:00:00Z`) + n * 86_400_000).toISOString().slice(0, 10);
}

/** People whose local clock is in `hour` on `day`. */
async function dueUsers(day: string, hour: number): Promise<string[]> {
  const rows = await db.query<{ user_id: string }>(
    `WITH user_tz AS (
       SELECT u.user_id, ${userOffsetMinutesOrNullSql("u.user_id")} AS tz_offset FROM users u
     )
     SELECT t.user_id
       FROM user_tz t
      WHERE t.tz_offset IS NOT NULL
        AND (NOW() + (t.tz_offset || ' minutes')::interval)::date = $1::date
        AND EXTRACT(HOUR FROM (NOW() + (t.tz_offset || ' minutes')::interval)) = $2`,
    [day, hour],
  );
  return rows.map((r) => r.user_id);
}

export async function sendSpecialEventPushes(): Promise<void> {
  for (const e of SPECIAL_EVENTS) {
    const target = eventTargetMiles(e);
    for (const push of PUSHES) {
      const users = await dueUsers(addDays(e.date, push.offsetDays), push.hour);
      if (users.length === 0) continue;
      const miles = push.offsetDays === 0 ? await milesOnEventDay(e, users) : new Map<string, number>();
      for (const userId of users) {
        const mine = miles.get(userId) ?? 0;
        if (!push.wants(mine, target)) continue;
        try {
          if (!(await shouldSendNotification(userId, null, "weekly_challenge"))) continue;
          if (!(await claimEventPush(e.id, userId, push.kind))) continue;
          const { title, body } = push.copy(e, Math.max(0, e.miles - mine));
          await sendPush(userId, {
            title,
            body,
            type: "special_event",
            data: { type: "special_event", event_id: e.id, kind: push.kind },
          });
        } catch (error: any) {
          console.error(`[special-events] ${push.kind} push failed for ${userId}:`, error?.message ?? error);
        }
      }
    }
  }
}

export function startSpecialEventCron(): void {
  cron.schedule("7 * * * *", () => {
    void runJob("special-event-pushes", sendSpecialEventPushes);
  });
}
