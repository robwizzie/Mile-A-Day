/**
 * Who may see one user's workout CONTENT — routes and photos.
 *
 * Before this, "friends only" was a property of individual queries: the feed,
 * the profile grid and the stories rail each JOINed the circle, while
 * /workouts/:userId/recent (and /stats, /streak, /race-records) were readable by
 * any authenticated account. Same underlying runs, two different answers.
 *
 * `notification_settings.workout_visibility` makes it one decision:
 *   'friends'  — accepted friends only (the DEFAULT, and what every existing
 *                user effectively has today, so the column changes nothing on
 *                its own)
 *   'public'   — any signed-in user
 *   'private'  — nobody but the owner
 *
 * Blocks always win, in both directions, whatever the visibility.
 */
export type WorkoutVisibility = "public" | "friends" | "private";

export const WORKOUT_VISIBILITY_VALUES: WorkoutVisibility[] = [
  "public",
  "friends",
  "private",
];

export const DEFAULT_WORKOUT_VISIBILITY: WorkoutVisibility = "friends";

export function isWorkoutVisibility(v: unknown): v is WorkoutVisibility {
  return (
    typeof v === "string" && (WORKOUT_VISIBILITY_VALUES as string[]).includes(v)
  );
}

/**
 * SQL predicate: may `viewerParam` see `ownerCol`'s workout content?
 *
 * `ownerCol` is any SQL expression naming the owner (a column like `p.user_id`
 * or a parameter like `$1`); `viewerParam` names the viewer. Both are spliced
 * as SQL, so they must ALWAYS be literals you wrote — never user input.
 *
 * Fail-closed by construction: an unknown visibility value and a NULL viewer
 * both fall through to false, and a missing settings row reads as the
 * 'friends' default rather than as open.
 */
export const VIEWER_MAY_SEE_WORKOUT_CONTENT_SQL = (
  ownerCol: string,
  viewerParam: string,
) => `(
	${ownerCol} = ${viewerParam}
	OR (
		NOT EXISTS (
			SELECT 1 FROM user_blocks b
			WHERE (b.blocker_id = ${viewerParam} AND b.blocked_id = ${ownerCol})
				OR (b.blocker_id = ${ownerCol} AND b.blocked_id = ${viewerParam})
		)
		AND CASE COALESCE(
			(SELECT nsv.workout_visibility FROM notification_settings nsv
				WHERE nsv.user_id = ${ownerCol}),
			'${DEFAULT_WORKOUT_VISIBILITY}'
		)
			WHEN 'public' THEN true
			WHEN 'friends' THEN EXISTS (
				SELECT 1 FROM friendships f
				WHERE f.user_id = ${viewerParam}
					AND f.friend_id = ${ownerCol}
					AND f.status = 'accepted'
			)
			ELSE false
		END
	)
)`;

/**
 * SQL predicate: is `ownerCol` NOT fully private?
 *
 * The feed is always your own circle — 'public' must never pour strangers into
 * it — so the feed doesn't use the full predicate above. It only needs to honor
 * the one direction that tightens: a user who went 'private' disappears from
 * their friends' feeds.
 */
export const OWNER_NOT_PRIVATE_SQL = (ownerCol: string) => `(
	COALESCE(
		(SELECT nsp2.workout_visibility FROM notification_settings nsp2
			WHERE nsp2.user_id = ${ownerCol}),
		'${DEFAULT_WORKOUT_VISIBILITY}'
	) <> 'private'
)`;
