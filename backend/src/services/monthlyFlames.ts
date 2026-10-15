import { PostgresService } from "./DbService.js";
import {
  STREAK_QUALIFYING_MILES,
  stepGoalDaysSql,
} from "./streakFeatureCore.js";
import { getUserLocalToday } from "./workoutService.js";

const db = PostgresService.getInstance();

/**
 * Monthly Flames — a Flamey FORM for every calendar month, earned by a
 * PERFECT month: every day of that month, from the 1st to the last, done.
 *
 * "Done" is the streak's own rule (a 0.95-mile day, a 10,000-step day, or a
 * token-covered day), read from the same three sources as `streakEndingAt`, so
 * a day that keeps the streak alive also keeps the month perfect. Injury
 * pauses don't count: a paused day is a day off, not a day done.
 *
 * Evergreen like the holiday medals: a perfect October in ANY year unlocks
 * the Jack-o'-Lantern for good. Derived at read — nothing is stored — so a
 * deleted workout that breaks the month takes the form back with it, exactly
 * like a revoked medal. Item ids are Flamey catalog ids (flameyCatalog.ts)
 * and must never be renamed.
 */
export interface MonthlyFlame {
  month: number;
  itemId: string;
  name: string;
}

/** Calendar order. The iOS mirror is `FlameyItem.monthlyFlames`. */
export const MONTHLY_FLAMES: readonly MonthlyFlame[] = [
  { month: 1, itemId: "frostbite", name: "Frostbite" },
  { month: 2, itemId: "sweetheart", name: "Sweetheart" },
  { month: 3, itemId: "lucky_clover", name: "Lucky Clover" },
  { month: 4, itemId: "april_showers", name: "April Showers" },
  { month: 5, itemId: "wildflower", name: "Wildflower" },
  { month: 6, itemId: "sunburst", name: "Sunburst" },
  { month: 7, itemId: "firecracker", name: "Firecracker" },
  { month: 8, itemId: "watermelon", name: "Watermelon" },
  { month: 9, itemId: "falling_leaves", name: "Falling Leaves" },
  { month: 10, itemId: "jack_o_lantern", name: "Jack-o'-Lantern" },
  { month: 11, itemId: "sweater_weather", name: "Sweater Weather" },
  { month: 12, itemId: "twinkle_lights", name: "Twinkle Lights" },
];

export function monthlyFlameFor(month: number): MonthlyFlame | undefined {
  return MONTHLY_FLAMES.find((m) => m.month === month);
}

// A "no upper bound" for stepGoalDaysSql's `local_date <= $n`.
const FOREVER = "9999-12-31";

/** The streak's done-day rule as one UNION of local dates for user $1. */
const DONE_DAYS_SQL = `
  SELECT local_date FROM workouts
   WHERE user_id = $1 AND deleted_at IS NULL AND exclusion_reason IS NULL
   GROUP BY local_date HAVING SUM(distance) >= ${STREAK_QUALIFYING_MILES}
  UNION
  ${stepGoalDaysSql("$1", "$2")}
  UNION
  SELECT local_date FROM streak_coverage WHERE user_id = $1`;

/**
 * Months (1–12) this user has had at least one perfect run of, with the
 * FIRST year they did it. One grouped read over their done days.
 */
export async function perfectMonths(
  userId: string,
): Promise<Map<number, number>> {
  const rows = await db.query<{ month: number; year: number }>(
    `WITH days AS (${DONE_DAYS_SQL}),
          months AS (
            SELECT date_trunc('month', local_date)::date AS m, COUNT(*)::int AS n
              FROM days GROUP BY 1
          )
     SELECT EXTRACT(MONTH FROM m)::int AS month, MIN(EXTRACT(YEAR FROM m))::int AS year
       FROM months
      WHERE n = EXTRACT(DAY FROM (m + interval '1 month' - interval '1 day'))::int
      GROUP BY 1`,
    [userId, FOREVER],
  );
  return new Map(rows.map((r) => [Number(r.month), Number(r.year)]));
}

export interface MonthlyFlamesProgress {
  year: number;
  month: number;
  item_id: string;
  name: string;
  days_in_month: number;
  /** Today's day of the month in the user's local calendar (1-based). */
  day_of_month: number;
  /** Done days this month so far, today included. */
  days_done: number;
  today_done: boolean;
  /** Every day from the 1st through yesterday is done — still on track. */
  still_perfect: boolean;
}

export interface MonthlyFlamesStatus {
  months: Array<{
    month: number;
    item_id: string;
    name: string;
    earned: boolean;
    /** The first year this month was perfect; null when not earned. */
    earned_year: number | null;
  }>;
  current: MonthlyFlamesProgress;
}

/** The whole Monthly Flames picture for the Closet (self only). */
export async function monthlyFlamesStatus(
  userId: string,
  earned?: Map<number, number>,
): Promise<MonthlyFlamesStatus> {
  const [have, today] = await Promise.all([
    earned ?? perfectMonths(userId),
    getUserLocalToday(userId),
  ]);
  const [y, m, d] = today.split("-").map(Number);
  const monthStart = `${today.slice(0, 7)}-01`;
  const rows = await db.query<{ d: string }>(
    `SELECT to_char(local_date, 'YYYY-MM-DD') AS d FROM (${DONE_DAYS_SQL}) days
      WHERE local_date >= $3::date AND local_date <= $4::date`,
    [userId, FOREVER, monthStart, today],
  );
  const done = new Set(rows.map((r) => r.d));
  const daysInMonth = new Date(Date.UTC(y, m, 0)).getUTCDate();
  const flame = monthlyFlameFor(m)!;
  return {
    months: MONTHLY_FLAMES.map((f) => ({
      month: f.month,
      item_id: f.itemId,
      name: f.name,
      earned: have.has(f.month),
      earned_year: have.get(f.month) ?? null,
    })),
    current: {
      year: y,
      month: m,
      item_id: flame.itemId,
      name: flame.name,
      days_in_month: daysInMonth,
      day_of_month: d,
      days_done: done.size,
      today_done: done.has(today),
      // Done days before today = the day number minus one, all of them.
      still_perfect: done.size - (done.has(today) ? 1 : 0) === d - 1,
    },
  };
}
