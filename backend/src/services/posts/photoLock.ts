// The earn-to-view gate: withhold today's photos from a viewer who hasn't done
// their own mile.

/** The viewer's mile status for a feed read — drives the photo gate. */
export interface ViewerGoalGate {
  completed: boolean;
  localDate: string;
}

/**
 * Withhold TODAY's real photos from a viewer who hasn't finished their own mile
 * yet — "run to see your friends' pictures". Mutates and returns the rows.
 *
 * Rules (per the product decision):
 *  - Only the viewer's LOCAL today is gated; older posts always show.
 *  - Own posts are never gated (you can always see your own).
 *  - PHOTOS ONLY: a real user photo (media_url on a non-auto post) and any
 *    story_photo_url are withheld; auto route/stats cards stay visible.
 *  - Once the viewer completes their mile, nothing is gated.
 *
 * media_url is blanked to "" rather than nulled so existing (non-optional)
 * clients still decode; new clients read `photo_locked` to draw the lock state.
 * `photo_locked` marks a row that LOST a photo here — not merely one that fell
 * under the gate — so a row whose every slide survived never renders as locked.
 */
export function lockUnearnedPhotos<
  T extends {
    user_id: string;
    local_date?: string | null;
    is_auto?: boolean | null;
    media_url?: string | null;
    dual_media_url?: string | null;
    dual_inset_corner?: string | null;
    story_photo_url?: string | null;
    photo_locked?: boolean;
    coauthors?: {
      user_id: string;
      media_url?: string | null;
      dual_media_url?: string | null;
      dual_inset_corner?: string | null;
    }[] | null;
  },
>(rows: T[], viewerId: string, gate: ViewerGoalGate): T[] {
  if (gate.completed || !gate.localDate) return rows;
  for (const r of rows) {
    if (r.user_id === viewerId) continue;
    if ((r.local_date ?? null) !== gate.localDate) continue;
    let withheld = false;
    if (r.story_photo_url) {
      r.story_photo_url = null;
      withheld = true;
    }
    // Leave auto route/stats cards visible; only real photos are locked.
    if (r.is_auto !== true && r.media_url) {
      r.media_url = "";
      withheld = true;
    }
    // The FRONT & BACK twin is the SAME withheld photo seen from the other
    // camera — handing it over would serve the picture the line above just
    // took away. NULLed rather than blanked: it is optional by contract, so
    // absent already means "no second frame" to every client.
    if (r.is_auto !== true && r.dual_media_url) {
      r.dual_media_url = null;
      r.dual_inset_corner = null;
      withheld = true;
    }
    // A buddy post carries the whole crew's photos, so gating only the
    // author's would hand the viewer three unearned pictures on the very card
    // the gate exists for. The viewer's OWN slide survives — same "you can
    // always see your own" rule the author gets one branch up.
    for (const c of r.coauthors ?? []) {
      if (c.user_id === viewerId) continue;
      if (c.dual_media_url) {
        c.dual_media_url = null;
        c.dual_inset_corner = null;
        withheld = true;
      }
      if (!c.media_url) continue;
      c.media_url = "";
      withheld = true;
    }
    // Only flag rows that actually LOST a photo. An auto route/stats card with
    // no story photo has nothing withheld, so it must not read as locked —
    // flagging it made clients hide a card they were meant to see.
    if (withheld) r.photo_locked = true;
  }
  return rows;
}
