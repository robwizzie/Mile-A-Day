// Story Highlights: the profile rail, one highlight opened, and highlight
// writes.

import { PostgresService } from "../DbService.js";
import { VIEWER_MAY_SEE_WORKOUT_CONTENT_SQL, OWNER_NOT_PRIVATE_SQL } from "../visibilityService.js";
import { type PostRow } from "./postTypes.js";
import { POST_SELECT, URL_SAFE_CURSOR } from "./postSql.js";

const db = PostgresService.getInstance();

// ─── Story Highlights ────────────────────────────────────────────────────
//
// A highlight is a named, ordered list of the OWNER's own posts, pinned to
// their profile above the grid. It stores no media and copies nothing: every
// read re-resolves the member posts, so a post that is later deleted or made
// private simply leaves the highlight, with no orphaned copy to clean up.
//
// The reason the feature exists is the expiry. A story is the only content in
// this app with one, and `story_expires_at` retiring it from the rail is
// exactly why nobody bothers making one. Adding a story to a highlight is
// therefore a PUBLICATION decision — it takes a photo that was going to
// disappear and makes it permanent for whoever can already see the profile —
// which is why `highlightMemberWhere` deliberately drops the `share_to_feed`
// requirement the grid enforces while keeping every other rule (the owner's
// workout_visibility, blocks in either direction, and the caller's
// lockUnearnedPhotos gate on the way out) exactly as it is.

// Same shape check the controllers apply before a ::uuid cast, restated here
// rather than imported: a service reaching into a controller inverts the
// dependency, and this list arrives as a client-supplied array that never
// passes through a route param.
const HIGHLIGHT_UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const isUuid = (value: string): boolean => HIGHLIGHT_UUID_RE.test(value);

/** Enough for a profile rail; past this the row stops being scannable. */
export const MAX_HIGHLIGHTS_PER_USER = 20;
/** Per highlight. A highlight is a story, not an archive. */
export const MAX_HIGHLIGHT_ITEMS = 100;
export const MAX_HIGHLIGHT_TITLE = 30;

export interface PostHighlight {
  highlight_id: string;
  user_id: string;
  title: string;
  cover_post_id: string | null;
  /**
   * An uploaded cover image, or null when the cover comes from a member post.
   * Additive: `cover_media_url` already resolves it, so a client that ignores
   * this field still draws the right circle — it exists so the editor can say
   * "custom cover set" and offer to drop back to a member's photo.
   */
  cover_image_url: string | null;
  /**
   * Resolved cover photo — the uploaded cover if there is one, else the
   * chosen member post, else the first member. Every client reads this one
   * field, which is why a custom cover needs no client change to appear.
   */
  cover_media_url: string | null;
  item_count: number;
  sort_index: number;
  created_at: string;
  updated_at: string;
}

/**
 * SQL: is `owner` still credited on post `p` as an accepted participant?
 *
 * The multi-person arm only — a buddy walk's crew lives in `post_coauthors`,
 * and the scalar `coauthor_user_id` mirrors just the first of them. Same
 * liveness rule as everywhere else (`MULTI_COLLAB_ACTIVE`), restated against
 * an arbitrary owner expression because this one is not evaluated per viewer.
 *
 * Deliberately NOT gated on `coauthorOnProfileSql`: that switch is grid-only,
 * and putting a walk in a highlight is a publish decision of its own — the
 * same reason `share_to_feed` is dropped below. Hiding a collab from the
 * chronological grid must not silently empty a highlight the owner built.
 */
const highlightCoauthorSql = (owner: string) => `EXISTS (
			SELECT 1 FROM post_coauthors hpca
			WHERE hpca.post_id = p.post_id
				AND hpca.user_id = ${owner}
				AND hpca.status = 'accepted'
				AND NOT EXISTS (
					SELECT 1 FROM user_blocks hcb
					WHERE (hcb.blocker_id = p.user_id AND hcb.blocked_id = hpca.user_id)
						OR (hcb.blocker_id = hpca.user_id AND hcb.blocked_id = p.user_id)
				)
		)`;

/**
 * SQL: may viewer `viewer` see owner `owner`'s post `p` AS A HIGHLIGHT MEMBER?
 *
 * The grid's rules minus `share_to_feed` (membership is the publish decision,
 * see above). Everything that protects another person — the AUTHOR's
 * visibility, their privacy setting, blocks in either direction — is unchanged
 * and stated here rather than assumed.
 *
 * The owner arm has two halves now: a post they wrote, or one they are an
 * accepted participant on. A buddy walk is ONE shared card, so the walks
 * people most want to keep are routinely authored by somebody else — gating on
 * authorship alone meant the whole buddy feature was the one thing a highlight
 * could not hold, and the picker offered those posts anyway (it reads the
 * profile grid, which has always included them), so choosing one silently
 * dropped it on save.
 *
 * This widens what a highlight may POINT AT, never what a viewer may SEE.
 * Every gate below still names `p.user_id` — the author — so a post whose
 * author goes private, blocks the viewer or deletes it leaves the highlight
 * exactly as it always did, and a collab that ends takes the pointer with it.
 */
const highlightMemberWhere = (viewer: string, owner: string) => `(
			(p.user_id = ${owner} OR ${highlightCoauthorSql(owner)})
			AND p.deleted_at IS NULL
			AND ${VIEWER_MAY_SEE_WORKOUT_CONTENT_SQL("p.user_id", viewer)}
			AND (p.user_id = ${viewer} OR ${OWNER_NOT_PRIVATE_SQL("p.user_id")})
			AND (p.user_id = ${viewer} OR NOT EXISTS (
				SELECT 1 FROM user_blocks b
				WHERE (b.blocker_id = ${viewer} AND b.blocked_id = p.user_id)
					OR (b.blocker_id = p.user_id AND b.blocked_id = ${viewer})
			))
		)`;

/**
 * The owner's highlight rail. Counts and covers are resolved against the same
 * visibility rule the members are, so a highlight whose every post has become
 * invisible to this viewer reports 0 rather than a count they can't reach —
 * and the caller drops those, instead of drawing a circle that opens empty.
 */
export async function listUserHighlights(
  viewerId: string,
  ownerId: string,
): Promise<PostHighlight[]> {
  return db.query<PostHighlight>(
    `
		SELECT h.highlight_id,
			h.user_id,
			h.title,
			h.cover_post_id,
			h.cover_image_url,
			COALESCE(h.cover_image_url, (
				-- The circle shows the FACE the owner kept, not the post's lead
				-- photo: a highlight of buddy walks whose members are all "my
				-- slide of it" would otherwise wear a friend's picture on every
				-- one. A crew slide resolves to that person's photo; the whole
				-- post and the map fall back to the post's own, which is what
				-- every pre-slide row means and the only image a map has.
				SELECT COALESCE(
					(SELECT cpca.media_url FROM post_coauthors cpca
						WHERE cpca.post_id = p.post_id
							AND cpca.user_id = i.slide_key
							AND cpca.status = 'accepted'),
					-- A live auto card has no picture ('') — it is drawn from the
					-- walk on the phone — so it can't be a circle's face.
					NULLIF(p.media_url, '')
				)
				FROM post_highlight_items i
				JOIN posts p ON p.post_id = i.post_id
				WHERE i.highlight_id = h.highlight_id
					AND ${highlightMemberWhere("$1", "h.user_id")}
				-- A member that HAS a picture first; then the chosen cover wins,
				-- otherwise the first member does, so a highlight always has a
				-- face even after its cover is deleted.
				ORDER BY (NULLIF(p.media_url, '') IS NOT NULL OR EXISTS (
						SELECT 1 FROM post_coauthors cpcb
						WHERE cpcb.post_id = p.post_id AND cpcb.user_id = i.slide_key
							AND cpcb.status = 'accepted' AND cpcb.media_url IS NOT NULL)) DESC,
					(p.post_id = h.cover_post_id) DESC, i.sort_index, i.added_at
				LIMIT 1
			)) AS cover_media_url,
			(
				SELECT COUNT(*)::int FROM post_highlight_items i
				JOIN posts p ON p.post_id = i.post_id
				WHERE i.highlight_id = h.highlight_id
					AND ${highlightMemberWhere("$1", "h.user_id")}
			) AS item_count,
			h.sort_index,
			h.created_at,
			h.updated_at
		FROM post_highlights h
		WHERE h.user_id = $2
		ORDER BY h.sort_index ASC, h.created_at ASC
		LIMIT $3
		`,
    [viewerId, ownerId, MAX_HIGHLIGHTS_PER_USER],
  );
}

/**
 * A highlight member: the whole post row, plus WHICH FACE of it the owner
 * kept.
 *
 * The face is served as a key, never as a resolved media url, on purpose. The
 * url for every face is already on the row — `media_url` for the post's own
 * photo, `coauthors[].media_url` for a participant's, `route` for the map —
 * and those are exactly the fields `lockUnearnedPhotos` blanks on the way out.
 * A second, pre-resolved copy of the same photo would be a field the lock
 * doesn't know about, i.e. a way to read a withheld picture, so the client
 * picks the face out of the row it was already given.
 */
export interface HighlightItem extends PostRow {
  slide_key: string;
}

export interface HighlightDetail {
  highlight_id: string;
  user_id: string;
  title: string;
  items: HighlightItem[];
}

/** One highlight, opened. Members in the owner's chosen order. */
export async function getHighlight(
  viewerId: string,
  highlightId: string,
): Promise<HighlightDetail | null> {
  const head = await db.query<{
    highlight_id: string;
    user_id: string;
    title: string;
  }>(
    `SELECT highlight_id, user_id, title FROM post_highlights WHERE highlight_id = $1`,
    [highlightId],
  );
  if (head.length === 0) return null;

  const items = await db.query<HighlightItem>(
    `
		SELECT ${POST_SELECT},
			i.slide_key,
			${URL_SAFE_CURSOR("p.created_at")} AS cursor
		FROM post_highlight_items i
		JOIN posts p ON p.post_id = i.post_id
		JOIN users u ON u.user_id = p.user_id
		WHERE i.highlight_id = $2
			AND ${highlightMemberWhere("$1", "$3")}
		ORDER BY i.sort_index ASC, i.added_at ASC
		LIMIT $4
		`,
    [viewerId, highlightId, head[0].user_id, MAX_HIGHLIGHT_ITEMS],
  );

  return {
    highlight_id: head[0].highlight_id,
    user_id: head[0].user_id,
    title: head[0].title,
    items,
  };
}

export type HighlightWriteResult =
  | { ok: true; highlight_id: string }
  | { ok: false; error: "not_found" | "limit" | "invalid_title" | "no_posts" };

function normalizeHighlightTitle(raw: unknown): string | null {
  const title = typeof raw === "string" ? raw.trim() : "";
  if (!title || title.length > MAX_HIGHLIGHT_TITLE) return null;
  return title;
}

/** The whole post — its own lead photo. What every shipped client asks for. */
export const HIGHLIGHT_SLIDE_WHOLE_POST = "";
/** The walk's route face rather than anybody's photograph. */
export const HIGHLIGHT_SLIDE_MAP = "map";

/** One member of a highlight: a post, and which face of it. */
export interface HighlightSlide {
  post_id: string;
  slide_key: string;
}

/**
 * The client's `post_ids` / `slides` input as one normalized list.
 *
 * `slides` wins when it is there; `post_ids` remains the whole wire format for
 * every build already in the field, and each of its entries means the whole
 * post. Both are capped and de-duplicated on the PAIR, since the same post may
 * legitimately appear twice under two different faces — that is the point of
 * the column.
 */
function requestedSlides(input: {
  post_ids?: unknown;
  slides?: unknown;
}): HighlightSlide[] {
  const raw: HighlightSlide[] = Array.isArray(input.slides)
    ? input.slides.flatMap((entry) => {
        if (!entry || typeof entry !== "object") return [];
        const postId = String((entry as any).post_id ?? "");
        const key = (entry as any).slide_key;
        return [
          {
            post_id: postId,
            slide_key:
              typeof key === "string" ? key : HIGHLIGHT_SLIDE_WHOLE_POST,
          },
        ];
      })
    : Array.isArray(input.post_ids)
      ? input.post_ids.map((id) => ({
          post_id: String(id),
          slide_key: HIGHLIGHT_SLIDE_WHOLE_POST,
        }))
      : [];

  const seen = new Set<string>();
  const out: HighlightSlide[] = [];
  for (const slide of raw) {
    if (!isUuid(slide.post_id)) continue;
    const dedupeKey = `${slide.post_id} ${slide.slide_key}`;
    if (seen.has(dedupeKey)) continue;
    seen.add(dedupeKey);
    out.push(slide);
    if (out.length >= MAX_HIGHLIGHT_ITEMS) break;
  }
  return out;
}

/**
 * Which of the requested slides the caller may actually keep, in the order
 * they were given. Everything else is DROPPED rather than rejected: the client
 * builds this list from a grid it may have loaded minutes ago, and a post
 * deleted in the meantime should not fail the whole save.
 *
 * A post qualifies when the caller AUTHORED it or is an accepted participant
 * on it — a buddy walk is one shared card, so "my walk" and "my post" are
 * routinely not the same row, and requiring authorship made the buddy feature
 * the one thing a highlight could not hold.
 *
 * A slide key qualifies when it names a face that post actually has: the whole
 * post, its map, or one of the people on it (the author or an accepted
 * participant). An unrecognised key falls back to the whole post rather than
 * dropping the member — the walk the user picked is what they asked to keep,
 * and losing it entirely over a face we can't resolve is the worse failure.
 */
async function highlightableSlides(
  userId: string,
  wanted: HighlightSlide[],
): Promise<HighlightSlide[]> {
  if (wanted.length === 0) return [];
  const postIds = Array.from(new Set(wanted.map((s) => s.post_id)));
  const rows = await db.query<{
    post_id: string;
    author_id: string;
    crew: string[] | null;
  }>(
    `SELECT p.post_id, p.user_id AS author_id,
			(SELECT array_agg(pca.user_id) FROM post_coauthors pca
				WHERE pca.post_id = p.post_id AND pca.status = 'accepted') AS crew
		 FROM posts p
		 WHERE p.post_id = ANY($1::uuid[])
			AND p.deleted_at IS NULL
			AND (p.user_id = $2 OR EXISTS (
				SELECT 1 FROM post_coauthors mine
				WHERE mine.post_id = p.post_id
					AND mine.user_id = $2
					AND mine.status = 'accepted'
			))`,
    [postIds, userId],
  );
  const faces = new Map<string, Set<string>>();
  for (const row of rows) {
    faces.set(
      row.post_id,
      new Set([
        HIGHLIGHT_SLIDE_WHOLE_POST,
        HIGHLIGHT_SLIDE_MAP,
        row.author_id,
        ...(row.crew ?? []),
      ]),
    );
  }

  const seen = new Set<string>();
  const out: HighlightSlide[] = [];
  for (const slide of wanted) {
    const allowed = faces.get(slide.post_id);
    if (!allowed) continue;
    const key = allowed.has(slide.slide_key)
      ? slide.slide_key
      : HIGHLIGHT_SLIDE_WHOLE_POST;
    const dedupeKey = `${slide.post_id} ${key}`;
    if (seen.has(dedupeKey)) continue;
    seen.add(dedupeKey);
    out.push({ post_id: slide.post_id, slide_key: key });
  }
  return out;
}

/**
 * The uploaded cover image for a write, or `undefined` for "leave it alone".
 *
 * `cover_image_url` is validated by the CONTROLLER (same ownership + on-disk
 * checks a post's media gets) and reaches here already stripped of its
 * signature, so a service that can't do filesystem checks never has to guess.
 * An empty string means "drop the custom cover and go back to a member's
 * photo" — the client can't express a JSON null through an encoder that omits
 * nil, so the empty string is the clear.
 */
function normalizeCoverImage(raw: unknown): string | null | undefined {
  if (typeof raw !== "string") return undefined;
  return raw.trim() === "" ? null : raw;
}

export async function createHighlight(
  userId: string,
  input: {
    title: unknown;
    post_ids?: unknown;
    slides?: unknown;
    cover_post_id?: unknown;
    cover_image_url?: unknown;
  },
): Promise<HighlightWriteResult> {
  const title = normalizeHighlightTitle(input.title);
  if (!title) return { ok: false, error: "invalid_title" };

  const count = await db.query<{ n: string }>(
    `SELECT COUNT(*) AS n FROM post_highlights WHERE user_id = $1`,
    [userId],
  );
  if (Number(count[0]?.n ?? 0) >= MAX_HIGHLIGHTS_PER_USER) {
    return { ok: false, error: "limit" };
  }

  const slides = await highlightableSlides(userId, requestedSlides(input));
  if (slides.length === 0) return { ok: false, error: "no_posts" };
  const memberIds = slides.map((s) => s.post_id);
  const cover =
    typeof input.cover_post_id === "string" &&
    memberIds.includes(input.cover_post_id)
      ? input.cover_post_id
      : memberIds[0];

  const created = await db.query<{ highlight_id: string }>(
    `INSERT INTO post_highlights (user_id, title, cover_post_id, cover_image_url, sort_index)
		 VALUES ($1, $2, $3, $4,
			COALESCE((SELECT MAX(sort_index) + 1 FROM post_highlights WHERE user_id = $1), 0))
		 RETURNING highlight_id`,
    [userId, title, cover, normalizeCoverImage(input.cover_image_url) ?? null],
  );
  const highlightId = created[0].highlight_id;
  await replaceHighlightItems(highlightId, slides);
  return { ok: true, highlight_id: highlightId };
}

/**
 * Membership rewrite as one statement pair: delete what's no longer a member,
 * then upsert the given order. `sort_index` comes from the array position, so
 * reordering is the same call as adding — the client always sends the list it
 * wants to end up with, which is the only shape a drag-to-reorder UI can
 * honestly produce.
 */
async function replaceHighlightItems(
  highlightId: string,
  slides: HighlightSlide[],
): Promise<void> {
  const postIds = slides.map((s) => s.post_id);
  const slideKeys = slides.map((s) => s.slide_key);
  // Membership is keyed on the PAIR now, so the delete has to be too: a walk
  // kept twice under two faces would otherwise lose one of them whenever the
  // other was re-sent.
  await db.query(
    `DELETE FROM post_highlight_items i
		 WHERE i.highlight_id = $1
			AND NOT EXISTS (
				SELECT 1 FROM UNNEST($2::uuid[], $3::text[]) AS v(post_id, slide_key)
				WHERE v.post_id = i.post_id AND v.slide_key = i.slide_key
			)`,
    [highlightId, postIds, slideKeys],
  );
  if (slides.length === 0) return;
  await db.query(
    `INSERT INTO post_highlight_items (highlight_id, post_id, slide_key, sort_index)
		 SELECT $1, v.post_id, v.slide_key, v.ord
		 FROM UNNEST($2::uuid[], $3::text[]) WITH ORDINALITY AS v(post_id, slide_key, ord)
		 ON CONFLICT (highlight_id, post_id, slide_key)
			DO UPDATE SET sort_index = EXCLUDED.sort_index`,
    [highlightId, postIds, slideKeys],
  );
}

export async function updateHighlight(
  userId: string,
  highlightId: string,
  input: {
    title?: unknown;
    post_ids?: unknown;
    slides?: unknown;
    cover_post_id?: unknown;
    cover_image_url?: unknown;
    sort_index?: unknown;
  },
): Promise<HighlightWriteResult> {
  const owned = await db.query<{ highlight_id: string }>(
    `SELECT highlight_id FROM post_highlights WHERE highlight_id = $1 AND user_id = $2`,
    [highlightId, userId],
  );
  if (owned.length === 0) return { ok: false, error: "not_found" };

  let title: string | null = null;
  if (input.title !== undefined) {
    title = normalizeHighlightTitle(input.title);
    if (!title) return { ok: false, error: "invalid_title" };
  }

  if (input.post_ids !== undefined || input.slides !== undefined) {
    const slides = await highlightableSlides(userId, requestedSlides(input));
    // An empty highlight is a circle that opens onto nothing, so emptying one
    // is a delete in disguise — say so instead of leaving the shell behind.
    if (slides.length === 0) return { ok: false, error: "no_posts" };
    await replaceHighlightItems(highlightId, slides);
  }

  const cover =
    typeof input.cover_post_id === "string" && isUuid(input.cover_post_id)
      ? input.cover_post_id
      : null;
  const sortIndex =
    typeof input.sort_index === "number" && Number.isFinite(input.sort_index)
      ? Math.max(0, Math.trunc(input.sort_index))
      : null;

  // Three states, not two: absent leaves the uploaded cover alone, a path
  // replaces it, and the empty string drops it so the member photo shows again.
  const coverImage = normalizeCoverImage(input.cover_image_url);

  await db.query(
    `UPDATE post_highlights SET
			title = COALESCE($3, title),
			-- Only ever a member post: a cover pointing at something that isn't
			-- in the highlight would render a photo the highlight doesn't hold.
			cover_post_id = CASE
				WHEN $4::uuid IS NULL THEN cover_post_id
				WHEN EXISTS (SELECT 1 FROM post_highlight_items i
					WHERE i.highlight_id = $1 AND i.post_id = $4::uuid) THEN $4::uuid
				ELSE cover_post_id END,
			cover_image_url = CASE WHEN $6::boolean THEN $7::text ELSE cover_image_url END,
			sort_index = COALESCE($5, sort_index),
			updated_at = NOW()
		 WHERE highlight_id = $1 AND user_id = $2`,
    [
      highlightId,
      userId,
      title,
      cover,
      sortIndex,
      coverImage !== undefined,
      coverImage ?? null,
    ],
  );
  return { ok: true, highlight_id: highlightId };
}

/** Hard delete — the posts themselves are untouched, only the grouping goes. */
export async function deleteHighlight(
  userId: string,
  highlightId: string,
): Promise<boolean> {
  const rows = await db.query<{ highlight_id: string }>(
    `DELETE FROM post_highlights WHERE highlight_id = $1 AND user_id = $2
		 RETURNING highlight_id`,
    [highlightId, userId],
  );
  return rows.length > 0;
}
