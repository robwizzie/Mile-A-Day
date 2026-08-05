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
