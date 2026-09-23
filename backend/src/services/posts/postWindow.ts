// The photo-posting window (camera tier vs photo tier) and the photo-source
// rule that picks between them.

import { PostgresService } from "../DbService.js";

const db = PostgresService.getInstance();

/**
 * How long after a qualifying walk/run a photo may be CAPTURED and posted.
 *
 * This bounds the live camera only. A photo the user already took on the walk
 * and picks out of their camera roll is not on a clock — see
 * `photoSourceRequiresCameraWindow`.
 *
 * The client owns the same number (`FreshPostWindowManager.duration`) and runs
 * the visible countdown off it — keep the two equal.
 */
export const POST_WINDOW_MS = 10 * 60 * 1000;

/**
 * Where the photo being posted came from, as declared by the client.
 *
 *  - `camera`   — shot just now with the in-app camera. Held to the ten
 *                 minutes: that's the whole claim the countdown makes.
 *  - `library`  — picked out of the camera roll. The client's importer only
 *                 ever SHOWS photos whose library creation time falls inside
 *                 the workout, so it's still a photo of the walk; the user just
 *                 got to it later. Open for the rest of the day.
 *  - `existing` — a photo already posted (a story being promoted onto the
 *                 feed). It was captured under whichever rule applied then, so
 *                 re-charging it the camera window would only punish the user
 *                 for having shared to their story first.
 *
 * Absent or unrecognised means an older build that predates the split, and
 * those only ever post live captures — so the default is the camera window,
 * i.e. exactly the behaviour those builds already ship against.
 */
export type PostPhotoSource = "camera" | "library" | "existing";

export function photoSourceRequiresCameraWindow(source: unknown): boolean {
  return source !== "library" && source !== "existing";
}

/**
 * Slack past the visible window, server-side only and never shown to the user.
 *
 * The client's countdown starts when the APP first sees the finished workout;
 * this one starts when the SERVER first does, which is necessarily the same
 * instant or later — so our window already closes no earlier than theirs. The
 * grace covers the round trip on top of that: someone who taps Share with five
 * seconds left still has to upload a 1080x1350 JPEG before the create call
 * lands. Rejecting that would be punishing a slow network, not a late post.
 */
export const POST_WINDOW_GRACE_MS = 2 * 60 * 1000;

export interface PostWindowStatus {
  /**
   * May a LIVE CAPTURE be posted right now? The ten-minute window, plus the
   * private grace. This is what the visible countdown counts down to.
   */
  cameraOpen: boolean;
  /**
   * May a photo be posted at all? True for the rest of the day once a
   * qualifying walk or run has landed — that's what a camera-roll pick and a
   * story promotion answer to. False all day for someone who hasn't moved,
   * which is the rule that actually keeps the feed about moving.
   */
  photoOpen: boolean;
  /** The qualifying workout whose window is the most recent one today. */
  workoutId: string | null;
  /** When that window opened, and when it closes for DISPLAY (no grace). */
  openedAt: string | null;
  closesAt: string | null;
  /** Countdown to the displayed close, floored at 0. */
  secondsRemaining: number;
}

const CLOSED_WINDOW: PostWindowStatus = {
  cameraOpen: false,
  photoOpen: false,
  workoutId: null,
  openedAt: null,
  closesAt: null,
  secondsRemaining: 0,
};

/**
 * The photo-posting window for a user's day. TWO tiers, not one.
 *
 * A photo post has to belong to a walk or run — that is the whole point of the
 * feed, and an unbounded composer turns it into a general-purpose photo stream
 * that happens to sit next to some mileage. But "belongs to the walk" is a
 * claim about the PHOTO, and only one of the two ways to get a photo needs a
 * clock to make that claim:
 *
 *  - The live camera claims "this is happening now", so it's bounded to ten
 *    minutes (`cameraOpen`). Past that the claim isn't true any more.
 *  - A camera-roll pick claims "I took this on the walk", which the client
 *    proves by capture time, not by how fast the user got to their phone. It
 *    stays open for the rest of the day (`photoOpen`). Being made to choose
 *    between finishing your cooldown and keeping your photo was the whole
 *    complaint — nothing about the photo changes at minute eleven.
 *
 * Both tiers still require a qualifying workout today, so neither is a way to
 * post without moving.
 *
 * "Qualifying" is already computed and maintained for us: `feed_role` is
 * `daily_mile` on the workout that reached the day's goal and `extra` on every
 * substantive one after it, which is exactly "the goal, plus each additional
 * goal reached". Reusing it means this can never disagree with what the feed
 * shows, and it inherits the anchor's stickiness and sub-floor filtering for
 * free. `rolled_up` and `hidden` deliberately don't open a window: the first is
 * a leg folded into the anchor's card, the second is a phantom.
 *
 * The window is anchored to whichever came LAST, the workout ending or the
 * server first hearing about it. A Watch run that syncs twenty minutes after it
 * ended is not a late post — it's the first moment the user could have posted
 * it at all, and `created_at` survives re-uploads (it isn't in the sync
 * upsert's DO UPDATE list) so a fullSync can't reopen a window that closed.
 */
export async function getPostWindowStatus(
  userId: string,
  localDate: string,
  now: number = Date.now(),
): Promise<PostWindowStatus> {
  const rows = await db.query<{
    workout_id: string;
    opened_at: Date | string | null;
  }>(
    `SELECT workout_id,
			GREATEST(device_end_date, COALESCE(created_at, device_end_date)) AS opened_at
		 FROM workouts
		 WHERE user_id = $1 AND local_date = $2::date
			 AND deleted_at IS NULL AND exclusion_reason IS NULL
			 AND feed_role IN ('daily_mile', 'extra')
		 ORDER BY opened_at DESC, workout_id DESC
		 LIMIT 1`,
    [userId, localDate],
  );
  const row = rows[0];

  // A buddy walk's window is the WALK's, not one leg's. The camera used to
  // close ten minutes after this user's own workout landed — so on a group
  // walk the early finisher's shutter was shut by the time the crew photo
  // was taken at the end, and someone whose walk hadn't synced yet had no
  // window at all ("past 10 minutes", about a walk they had just finished).
  // The walk counts as the day's qualifying workout the moment they finish
  // it, and its window runs from the LAST person's finish: open while the
  // session is still live, ten minutes after it closes.
  const walk = await db.query<{
    workout_id: string | null;
    opened_at: Date | string | null;
  }>(
    `SELECT bsp.workout_id,
			CASE WHEN s.status = 'active' THEN NOW()
			     ELSE GREATEST(
			       COALESCE(s.ended_at, bsp.finished_at),
			       (SELECT MAX(o.finished_at) FROM buddy_session_participants o
			         WHERE o.session_id = s.id AND o.status = 'finished'))
			END AS opened_at
		 FROM buddy_session_participants bsp
		 JOIN buddy_sessions s ON s.id = bsp.session_id
		 WHERE bsp.user_id = $1
			 AND bsp.status IN ('active', 'finished')
			 AND s.status IN ('active', 'completed')
			 AND s.started_at IS NOT NULL
			 -- The session's local_date is the HOST's day; the caller's day is
			 -- their own. A walk taken with a friend two zones over must still
			 -- count, so match loosely on the calendar and tightly on the clock.
			 AND s.local_date BETWEEN ($2::date - 1) AND ($2::date + 1)
			 AND s.started_at > NOW() - INTERVAL '30 hours'
			 -- Only a walk they actually took: a live report puts them on it,
			 -- and a sub-floor leg isn't a mile any more than a solo one is.
			 AND COALESCE(bsp.final_distance_miles, bsp.distance_miles, 0) >= 0.2
		 ORDER BY opened_at DESC
		 LIMIT 1`,
    [userId, localDate],
  );
  const walkRow = walk[0];

  const candidates: Array<{ workoutId: string | null; openedAt: Date }> = [];
  if (row?.opened_at) {
    // Raw-SQL timestamptz comes back as a Date; be tolerant of either shape.
    const openedAt = new Date(row.opened_at);
    if (!Number.isNaN(openedAt.getTime())) {
      candidates.push({ workoutId: row.workout_id, openedAt });
    }
  }
  if (walkRow?.opened_at) {
    const openedAt = new Date(walkRow.opened_at);
    if (!Number.isNaN(openedAt.getTime())) {
      // The synced workout is the better id when both exist; the walk's
      // participant row may not be linked yet.
      candidates.push({
        workoutId: walkRow.workout_id ?? row?.workout_id ?? null,
        openedAt,
      });
    }
  }
  if (candidates.length === 0) return CLOSED_WINDOW;
  const latest = candidates.reduce((a, b) =>
    b.openedAt.getTime() > a.openedAt.getTime() ? b : a,
  );

  const closesAt = latest.openedAt.getTime() + POST_WINDOW_MS;
  return {
    cameraOpen: now < closesAt + POST_WINDOW_GRACE_MS,
    // A qualifying workout (or a finished buddy walk) exists for this local
    // day, which is the entire condition. It stops being true when the day
    // rolls over, since `localDate` is what scopes both queries.
    photoOpen: true,
    workoutId: latest.workoutId,
    openedAt: latest.openedAt.toISOString(),
    closesAt: new Date(closesAt).toISOString(),
    secondsRemaining: Math.max(0, Math.round((closesAt - now) / 1000)),
  };
}
