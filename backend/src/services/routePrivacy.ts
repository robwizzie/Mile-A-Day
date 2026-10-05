/**
 * Route privacy ("hide start & end") — the ONE door a stored route leaves
 * the database through.
 *
 * Every read that serves `workout_routes` points to a viewer joins the row
 * through `servedRouteFrom`, which bounds it with `mad_route_view_bounds`
 * (migration 0085): the OWNER gets the stored row untouched; anyone else gets
 * it with a jittered stretch trimmed off each end (the owner's
 * `notification_settings.route_privacy_meters`, NULL = 1/8 mile), the replay
 * clock sliced and re-based in lockstep, or NO row at all when what's left
 * would be a sliver — which every caller's scalar subquery already reads as
 * "no route", indistinguishable from maps-off.
 *
 * Usage: `FROM ${servedRouteFrom("wr", workoutIdExpr, ownerExpr, viewerExpr)}`
 * (or `CROSS JOIN LATERAL ${…}` beside the workouts row it keys on) and select
 * from the alias exactly as from `workout_routes` (`wr.route`, `wr.times`,
 * `wr.started_at`) plus `wr.trimmed`. The key is INSIDE the fragment so the
 * primary-key lookup always drives it — the trim can only ever run on the one
 * row found, never across the table. No other module may select
 * `workout_routes.route` for a viewer who might not be its owner.
 *
 * No imports: posts/postSql (the bottom of the posts graph) and workoutService
 * both use it.
 */

/** The setting values the app offers, in metres. 0 = off. */
export const ROUTE_PRIVACY_OPTIONS = [0, 201, 402, 805, 1609] as const;
/** What a NULL setting means (1/8 mile). Must match mad_route_view_bounds. */
export const DEFAULT_ROUTE_PRIVACY_METERS = 201;

export function isRoutePrivacyMeters(v: unknown): v is number {
  return (
    typeof v === "number" &&
    (ROUTE_PRIVACY_OPTIONS as readonly number[]).includes(v)
  );
}

/**
 * SQL: a derived-table `FROM` item yielding the route of workout
 * `workoutIdExpr` as `viewerExpr` may see it, aliased `alias`. `ownerExpr` is
 * the route owner's user id. Exposes `workout_id`, `route`, `times`,
 * `started_at`, `trimmed`; zero rows when there is no route or the viewer may
 * not see any of it.
 */
export function servedRouteFrom(
  alias: string,
  workoutIdExpr: string,
  ownerExpr: string,
  viewerExpr: string,
): string {
  const raw = `${alias}_raw`;
  const b = `${alias}_b`;
  // A plain derived table, so the planner flattens it into the caller's
  // scalar subquery and evaluates ONLY the column that subquery selects —
  // the route column never pays for slicing the clock, and vice versa.
  return `(
		SELECT ${raw}.workout_id,
			CASE WHEN ${b}.full_route THEN ${raw}.route
				ELSE mad_route_slice(${raw}.route, ${b}.i_s, ${b}.i_e) END AS route,
			CASE WHEN ${b}.full_route THEN ${raw}.times
				ELSE mad_route_slice_times(${raw}.times, ${raw}.point_count, ${b}.i_s, ${b}.i_e) END AS times,
			CASE WHEN ${b}.full_route THEN ${raw}.started_at
				ELSE mad_route_shift_start(${raw}.started_at, ${raw}.times, ${raw}.point_count, ${b}.i_s) END AS started_at,
			NOT ${b}.full_route AS trimmed
		  FROM workout_routes ${raw}
		  CROSS JOIN LATERAL mad_route_view_bounds(
			${raw}.route, ${raw}.point_count, ${raw}.privacy_bounds,
			${raw}.workout_id, ${ownerExpr},
			COALESCE((${ownerExpr}) = (${viewerExpr}), false)
		  ) ${b}
		 WHERE ${raw}.workout_id = ${workoutIdExpr}
			AND ${b}.i_s IS NOT NULL
	) ${alias}`;
}
