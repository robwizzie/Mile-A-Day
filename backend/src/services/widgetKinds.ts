/**
 * The home-screen widget kinds the app can report as installed at
 * `POST /devices/register` (`widget_kinds`). These strings are the `kind` each
 * iOS `Widget` declares — WidgetCenter hands them back verbatim — so they must
 * match the app exactly, and renaming one on either side silently stops that
 * widget's refresh pushes.
 *
 * Kept in its own dependency-free module because both the registration path
 * (pushNotificationService) and widgetRefreshService need it, and the latter
 * imports the former.
 */
export const WIDGET_KINDS = {
  competition: "CompetitionWidget",
  dailyLeaderboard: "DailyLeaderboardWidget",
  todayProgress: "TodayProgressWidget",
  streakCount: "StreakCountWidget",
  streakFlame: "StreakFlameWidget",
} as const;

const KNOWN_WIDGET_KINDS = new Set<string>(Object.values(WIDGET_KINDS));

/**
 * Sanitize a registration's `widget_kinds`. NOT an array ⇒ null ("this build
 * doesn't report widgets"), which is different from [] ("it reported none").
 * Unknown strings are dropped for the same reason as client_features: the
 * column is read back into SQL predicates.
 */
export function normalizeWidgetKinds(raw: unknown): string[] | null {
  if (!Array.isArray(raw)) return null;
  const kinds = new Set<string>();
  for (const value of raw) {
    if (typeof value === "string" && KNOWN_WIDGET_KINDS.has(value)) {
      kinds.add(value);
    }
  }
  return [...kinds];
}
