// Post row shapes shared by every post read, plus the ghost-claim sanitizer
// that guards the stats snapshot.

import { MIN_PLAUSIBLE_MILE_SECONDS, MAX_PLAUSIBLE_MILE_SECONDS } from "../mileTime.js";

export interface PostStatsSnapshot {
  distance?: number;
  pace?: number | null;
  duration?: number | null;
  streak?: number | null;
  date?: string | null;
  /**
   * Ghost race, present only when the ghost was BEATEN: seconds of margin and
   * the ghost's mile time.
   *
   * Deliberately carried in the snapshot rather than in its own column. The
   * snapshot is jsonb that every feed projection already returns verbatim, so
   * a ghost win reaches the feed, the profile grid, stories and post detail
   * without touching one of those guard-heavy SELECTs.
   *
   * Display only, and client-asserted — `sanitizeGhostStats` clamps it to
   * plausible values so a bad client can only brag with a believable number on
   * its OWN post. Anything that must be TRUSTED (medals) counts
   * `workouts.ghost_margin_seconds` instead, which arrives from the synced
   * HKWorkout on the same footing as distance.
   */
  ghost_margin_seconds?: number | null;
  ghost_target_seconds?: number | null;
}

/**
 * Drop a ghost claim that isn't plausible, keeping the rest of the snapshot.
 * Bounds mirror the client's `GhostTarget.isPlausible` (4:01…40:00); a margin
 * can never exceed the ghost it beat.
 */
export function sanitizeGhostStats(
  stats: PostStatsSnapshot | null,
): PostStatsSnapshot | null {
  if (!stats) return stats;
  const margin = Number(stats.ghost_margin_seconds);
  const target = Number(stats.ghost_target_seconds);
  const ok =
    Number.isFinite(margin) &&
    Number.isFinite(target) &&
    margin > 0 &&
    target >= MIN_PLAUSIBLE_MILE_SECONDS &&
    target <= MAX_PLAUSIBLE_MILE_SECONDS &&
    margin <= target;
  if (ok) return stats;
  const { ghost_margin_seconds, ghost_target_seconds, ...rest } = stats;
  return rest;
}

/**
 * One credited participant on a multi-person collab post.
 *
 * Cap of 8 matches BUDDY_MAX_PARTICIPANTS — a collab post exists to credit a
 * buddy walk, so it can never need more names than a walk can hold.
 */
export const MAX_POST_COAUTHORS = 8;

/**
 * One competition the post's author was in on the post's day — the card's
 * "COMPETING" flair. Bounded to the three ending soonest; `viewer_in` lets the
 * card say "you too" when the viewer is in the same one.
 */
export interface PostCompetitionRef {
  id: string;
  name: string | null;
  type: string;
  ended: boolean;
  /** The author's team name when the competition has teams, else null. */
  team_name: string | null;
  viewer_in: boolean;
}

export interface PostCoauthor {
  user_id: string;
  username: string | null;
  first_name: string | null;
  last_name: string | null;
  profile_image_url: string | null;
  status: "pending" | "accepted" | "declined";
  // THIS participant's own photo on the shared post — the slide that makes a
  // buddy walk one post with everyone's pictures on it instead of one post per
  // person. Null until they add one (and for every pre-existing collab).
  // Blanked to "" by lockUnearnedPhotos alongside the author's, so the
  // earn-to-view gate can't be walked around by reading the crew.
  media_url?: string | null;
  // Their GPS trace for the walk, resolved at READ time from the buddy
  // session's participant row rather than stored — the sync reconciler stamps
  // that workout id a minute or two after the walk ends, which is AFTER the
  // person who posts the moment they finish has already posted. Honors their
  // own "Share route maps" consent, so this is null for anyone who opted out
  // and for an indoor walk with nothing to draw.
  route?: unknown;
  // Seconds since THEIR first route point, one per point of `route`, plus
  // that first point's absolute time as epoch seconds. What lets the Flyover
  // replay a crew on ONE clock — each rider where they actually were, and
  // stopped where they stopped. Null on routes uploaded before clients sent
  // them; a length mismatch with `route` means "no times".
  route_times?: number[] | null;
  route_started_at?: number | null;
  // THIS participant's own two switches on the shared post, and null for
  // everybody except the participant themselves — one person's curation is not
  // another's to read. `on_feed` = does the post reach MY friends' feeds
  // (nothing else moves when it's off: the tag stays, the author's circle
  // keeps it, and I still see it). `include_route` = is MY trace drawn on it,
  // overriding my global "Share route maps" for this one walk; null there
  // means "follow my setting", which is what every pre-existing row does.
  on_feed?: boolean | null;
  include_route?: boolean | null;
  // HOW FAR this person went and HOW LONG it took, so a card about several
  // people walking together can say what each of them did. Distance comes
  // from the participant row — the same figure `buddy_group.distance_miles`
  // SUMS, so the parts add up to the total on the same card. Null on a collab
  // with no buddy session and no linked workout.
  distance_miles?: number | null;
  duration_seconds?: number | null;
  // Their display-pace divisor, under the same >=50%-of-elapsed rule the
  // author's is served under (`displayMovingSecondsSql`). Null means "use
  // elapsed", which is what every client already falls back to.
  moving_seconds?: number | null;
  // Their own per-mile splits, shaped exactly like the entry's `splits`.
  // Null when their leg has none (indoor, unlinked, or an older upload).
  splits?: unknown;
}

/** One comment in a card's inline preview. */
export interface CommentPreview {
  comment_id: string;
  user_id: string;
  username: string | null;
  content: string;
}

export interface PostRow {
  post_id: string;
  user_id: string;
  username: string | null;
  first_name: string | null;
  last_name: string | null;
  profile_image_url: string | null;
  media_url: string;
  caption: string | null;
  workout_id: string | null;
  // Linked workout's feed_role — display framing only (see the projection
  // comments); null when the post has no workout.
  feed_role: string | null;
  stats_snapshot: PostStatsSnapshot | null;
  local_date: string;
  share_to_feed: boolean;
  share_to_story: boolean;
  story_expires_at: string | null;
  created_at: string;
  is_auto: boolean;
  include_route: boolean;
  // Additive: the author's simplified route (AUTHOR_ROUTE_SQL), null when
  // withheld/absent. Every post-shaped read ships it now, not just the feed.
  route?: number[][] | null;
  // Additive, beside `route`: seconds per point since the first fix and the
  // first fix's epoch seconds (see PostCoauthor.route_times). Null when the
  // uploading client sent none.
  route_times?: number[] | null;
  route_started_at?: number | null;
  // Additive: the competitions the AUTHOR was in on the post's day, so a
  // card can say "competing in …" (see COMPETITIONS_JSON). Null when none.
  competitions?: PostCompetitionRef[] | null;
  // Additive: the ONE competition the poster stickered onto the photo, or
  // null. Meaningful only alongside `competitions` — the matching entry's
  // `viewer_in` is what decides whether this viewer gets a tappable chip.
  competition_id?: string | null;
  workout_type: string | null;
  is_self: boolean;
  is_hyped: boolean;
  hype_count: number;
  comment_count: number;
  // The last two comments, oldest-first, for the feed's inline preview —
  // Instagram's rule, so a conversation is visible on the card instead of
  // behind a tap. Blocked users' comments are already filtered out. Null when
  // there are none.
  comment_preview?: CommentPreview[] | null;
  // Collab post fields — null unless a coauthor exists AND (accepted, or the
  // viewer is one of the two authors; pending invites are private to them).
  coauthor_user_id?: string | null;
  coauthor_status?: "pending" | "accepted" | null;
  coauthor_username?: string | null;
  coauthor_first_name?: string | null;
  coauthor_last_name?: string | null;
  coauthor_profile_image_url?: string | null;
  // Multi-person collab (Buddy Walks). NULL for every post that predates the
  // feature, so the payload shape is unchanged for the legacy corpus and old
  // clients go on reading the scalar fields above.
  coauthors?: PostCoauthor[] | null;
  // The WALK's combined figures on a buddy post — "3.2 mi between us", the
  // number the recap headlines and the card never showed. Null on every
  // non-buddy post and on every older server.
  buddy_group?: { distance_miles: number; crew_size: number } | null;
  // Resolved "is this collab on MY profile grid?" — only populated when the
  // VIEWER is the coauthor (it's their setting to read), null otherwise.
  // Drives the card's Hide/Show-on-profile action. Additive field.
  coauthor_on_profile?: boolean | null;
  // Sibling of coauthor_on_profile, same rule: only populated when the VIEWER
  // is the coauthor. "Does this collab reach my own friends' feeds?" Additive.
  coauthor_on_feed?: boolean | null;
  // Non-null when the AUTHOR has pinned this post to the top of their grid.
  // Everyone sees the pins (that's the point of a pin) — only the author can
  // set them. Additive field; null on every post that isn't pinned.
  pinned_at?: string | null;
  is_viewed?: boolean;
  // The viewer's own emoji reaction to this story (getUserActiveStories only),
  // so re-opening a story they already reacted to shows the reaction. null/absent
  // = they haven't reacted.
  viewer_reaction?: string | null;
  // Set by lockUnearnedPhotos: this post's photo is withheld because it's from
  // the viewer's local today and they haven't finished their own mile yet.
  photo_locked?: boolean;
  // Microsecond-precise created_at (Postgres text form) for keyset pagination.
  // node-pg parses timestamptz to a ms-truncated JS Date, and a truncated
  // `before` cursor silently skips same-millisecond rows at page boundaries.
  cursor?: string;
  // The run's active story photo (getUserPosts only) — lets profile surfaces
  // lead with the real picture like the feed does.
  story_photo_url?: string | null;
  // getUserActiveStories only: does this story's workout already have a live
  // DELIBERATE feed post? Drives hiding the story viewer's "Add to feed"
  // button so it isn't offered (then 409'd) when the run is already on the
  // feed. The auto route/stats card does NOT count — promoting a story photo
  // replaces the auto card in place, which is the button's whole point.
  workout_on_feed?: boolean;
}

export interface StoryGroup {
  user_id: string;
  username: string | null;
  first_name: string | null;
  last_name: string | null;
  profile_image_url: string | null;
  story_count: number;
  has_unviewed: boolean;
  latest_at: string;
  /** Distinct author-local days ("yyyy-MM-dd") this group's stories span —
   *  lets the client gate viewing PER DAY (yesterday's stories stay viewable
   *  for a viewer who completed yesterday). Additive field. */
  story_local_dates: string[];
  /** Author-local days with at least one story the viewer HASN'T seen —
   *  lets the client light the "unviewed" ring only for days the viewer can
   *  actually watch, so an unearned today-story can't leave a permanently
   *  unclearable ring. Additive field. */
  unviewed_local_dates: string[];
}
