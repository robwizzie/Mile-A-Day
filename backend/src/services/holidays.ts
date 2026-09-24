/**
 * The holiday catalog behind the `holiday_<key>` medals ("walked your mile on
 * Halloween"). Pure date math over a `local_date` string — the day the WALKER
 * was on, which is how `workouts.local_date` is already filed — so a
 * Halloween walk in Tokyo and one in Denver each count on their own Oct 31.
 *
 * Evergreen: a medal is earned once, ever, not once per year. The key is the
 * badge id's suffix and must never be renamed (shipped builds and
 * `user_badges` rows carry it).
 */

export type HolidayKey =
  | "new_years_day"
  | "valentines_day"
  | "st_patricks_day"
  | "easter"
  | "independence_day"
  | "halloween"
  | "thanksgiving"
  | "christmas_eve"
  | "christmas"
  | "new_years_eve";

export interface Holiday {
  key: HolidayKey;
  /** The holiday's own name, e.g. "Halloween". */
  holidayName: string;
  /** The medal's name, e.g. "Spooky Mile". */
  medalName: string;
  /** SF Symbol the app draws for the medal. */
  icon: string;
}

/** Catalog order = calendar order, which is also the medals' sort order. */
export const HOLIDAYS: readonly Holiday[] = [
  { key: "new_years_day", holidayName: "New Year's Day", medalName: "First Mile of the Year", icon: "sparkles" },
  { key: "valentines_day", holidayName: "Valentine's Day", medalName: "Sweetheart Mile", icon: "heart.fill" },
  { key: "st_patricks_day", holidayName: "St. Patrick's Day", medalName: "Lucky Mile", icon: "leaf.fill" },
  { key: "easter", holidayName: "Easter", medalName: "Egg-cellent Mile", icon: "hare.fill" },
  { key: "independence_day", holidayName: "Independence Day", medalName: "Freedom Mile", icon: "flag.fill" },
  { key: "halloween", holidayName: "Halloween", medalName: "Spooky Mile", icon: "moon.stars.fill" },
  { key: "thanksgiving", holidayName: "Thanksgiving", medalName: "Gobble Mile", icon: "fork.knife" },
  { key: "christmas_eve", holidayName: "Christmas Eve", medalName: "Night Before Mile", icon: "moon.fill" },
  { key: "christmas", holidayName: "Christmas", medalName: "Santa's Mile", icon: "gift.fill" },
  { key: "new_years_eve", holidayName: "New Year's Eve", medalName: "Last Mile of the Year", icon: "party.popper.fill" },
];

export const HOLIDAY_BADGE_PREFIX = "holiday_";

export function holidayBadgeId(key: HolidayKey): string {
  return `${HOLIDAY_BADGE_PREFIX}${key}`;
}

/** Inverse of holidayBadgeId; null for anything that isn't a holiday medal. */
export function holidayKeyFromBadgeId(badgeId: string): HolidayKey | null {
  if (!badgeId.startsWith(HOLIDAY_BADGE_PREFIX)) return null;
  const key = badgeId.slice(HOLIDAY_BADGE_PREFIX.length);
  return HOLIDAYS.some((h) => h.key === key) ? (key as HolidayKey) : null;
}

const pad = (n: number) => String(n).padStart(2, "0");
const ymd = (y: number, m: number, d: number) => `${y}-${pad(m)}-${pad(d)}`;

/**
 * Western (Gregorian) Easter Sunday — the anonymous Gregorian algorithm
 * (Meeus/Jones/Butcher). Returns [month, day].
 */
export function easterMonthDay(year: number): [number, number] {
  const a = year % 19;
  const b = Math.floor(year / 100);
  const c = year % 100;
  const d = Math.floor(b / 4);
  const e = b % 4;
  const f = Math.floor((b + 8) / 25);
  const g = Math.floor((b - f + 1) / 3);
  const h = (19 * a + b - d - g + 15) % 30;
  const i = Math.floor(c / 4);
  const k = c % 4;
  const l = (32 + 2 * e + 2 * i - h - k) % 7;
  const m = Math.floor((a + 11 * h + 22 * l) / 451);
  const month = Math.floor((h + l - 7 * m + 114) / 31);
  const day = ((h + l - 7 * m + 114) % 31) + 1;
  return [month, day];
}

/** US Thanksgiving: the 4th Thursday of November. Returns the day of month. */
export function thanksgivingDay(year: number): number {
  // Day of week of Nov 1 (0 = Sunday). UTC so no host timezone leaks in.
  const nov1 = new Date(Date.UTC(year, 10, 1)).getUTCDay();
  const firstThursday = 1 + ((4 - nov1 + 7) % 7);
  return firstThursday + 21;
}

/** Every holiday date in `year`, as `YYYY-MM-DD` → key. */
export function holidaysInYear(year: number): Array<{ date: string; key: HolidayKey }> {
  const [em, ed] = easterMonthDay(year);
  return [
    { date: ymd(year, 1, 1), key: "new_years_day" },
    { date: ymd(year, 2, 14), key: "valentines_day" },
    { date: ymd(year, 3, 17), key: "st_patricks_day" },
    { date: ymd(year, em, ed), key: "easter" },
    { date: ymd(year, 7, 4), key: "independence_day" },
    { date: ymd(year, 10, 31), key: "halloween" },
    { date: ymd(year, 11, thanksgivingDay(year)), key: "thanksgiving" },
    { date: ymd(year, 12, 24), key: "christmas_eve" },
    { date: ymd(year, 12, 25), key: "christmas" },
    { date: ymd(year, 12, 31), key: "new_years_eve" },
  ];
}

/**
 * The holiday a local calendar day falls on, or null. `ymd` is a
 * `YYYY-MM-DD` local date (a `workouts.local_date`); anything else is null.
 * No two catalog holidays can share a date (Easter is Mar 22–Apr 25).
 */
export function holidayKeyForLocalDate(ymdStr: string): HolidayKey | null {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(ymdStr);
  if (!m) return null;
  const year = Number(m[1]);
  const hit = holidaysInYear(year).find((h) => h.date === ymdStr);
  return hit ? hit.key : null;
}

/**
 * Every holiday date in [fromYear, toYear] — the bounded date set the
 * backfill and revocation probe `workouts.local_date` with.
 */
export function holidayDatesBetween(
  fromYear: number,
  toYear: number,
): Array<{ date: string; key: HolidayKey }> {
  const out: Array<{ date: string; key: HolidayKey }> = [];
  for (let y = fromYear; y <= toYear; y++) out.push(...holidaysInYear(y));
  return out;
}
