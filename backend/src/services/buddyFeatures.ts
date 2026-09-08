/**
 * Kill switch for Buddy Walks & Runs.
 *
 * Defaults to ON. Set `BUDDY_SESSIONS=false` to take the whole feature down
 * without a deploy; anything else (including unset) leaves it up.
 *
 * This used to default to OFF, as an opt-in staging gate while the app build
 * carrying the Buddy Walks screens worked its way through review. That cost the
 * feature weeks of being silently dead in production: with the flag unset,
 * every buddy endpoint 404s (see `requireEnabled` in buddyController), and the
 * client renders a 404 as "We couldn't find that buddy walk" — including the
 * 404 from POST /buddy/enroll, which meant nobody was ever enrolled, so every
 * invite picker was also empty. One unset variable, three unrelated-looking
 * bugs, no error anywhere.
 *
 * Defaulting ON is safe because this flag was never the thing protecting older
 * installs — the per-user capability gate is. A build without the buddy screens
 * does not declare `buddy_walks_v1` at POST /devices/register, so it never gets
 * `users.buddy_enrolled_at` stamped, and an unstamped user is never offered as
 * an invite candidate and never sent a buddy push. That gate holds regardless
 * of this flag. All this one decides is whether the endpoints exist at all,
 * which is exactly what a kill switch should decide.
 */
export function buddySessionsEnabled(): boolean {
  return process.env.BUDDY_SESSIONS !== "false";
}

/**
 * When a walk is open to somebody who isn't in it yet.
 *
 * ONE rule, referenced from every place that answers "can they come in":
 * the Friends-tab offers (`friendsOutNow`), the joinable list, and the
 * request-to-join door. They used to be three hand-copied blocks, and the
 * documented failure of that arrangement is a Join button drawn for an offer
 * its own endpoint rejects. A running walk stays open while anyone is still
 * in it — "late" is not "too late" for three of the four modes — and a lobby
 * for as long as the abandoned-lobby sweep would leave it standing
 * (unscheduled: 3h from creation; scheduled: ±30 min of its start).
 *
 * `alias` is the `buddy_sessions` row in the caller's query.
 */
export function JOINABLE_WINDOW_SQL(alias: string): string {
  return `(
    (${alias}.status = 'active' AND EXISTS (
       SELECT 1 FROM buddy_session_participants live
        WHERE live.session_id = ${alias}.id AND live.status = 'active'
     ))
    OR (${alias}.status = 'lobby' AND (
          (${alias}.scheduled_start_at IS NULL
           AND ${alias}.created_at > NOW() - INTERVAL '3 hours')
       OR (${alias}.scheduled_start_at IS NOT NULL
           AND ${alias}.scheduled_start_at BETWEEN NOW() - INTERVAL '30 minutes'
                                                AND NOW() + INTERVAL '30 minutes')))
  )`;
}

/**
 * Participant rows that OCCUPY a slot. 'left'/'declined' freed theirs, and a
 * 'requested' row never held one — somebody waiting at the door must not make
 * the room read as full, or the host is refused the very invite that would
 * let them in.
 */
export const OCCUPYING_STATUSES_SQL = `('invited', 'joined', 'ready', 'active', 'finished')`;
