# Desk display feed

The LED desk counters (Matrix Portal M4 + 64x32 panel) read one endpoint:

```
GET /display/feed
Authorization: Display madk_<43 chars>
```

Each key belongs to one user. Rob's board shows Rob's mile, streak, nudges and
hypes; Dave's board shows Dave's. Without a key a board falls back to the
public `/public/stats` numbers.

## Setup

1. Deploy (merging to `main` runs migration `0086_display_keys`).
2. Admin dashboard → **Displays** → username + label → **Create key**.
   The key is shown once (it hides after 2 minutes). Copy it.
3. On the board's `CIRCUITPY` drive, in `settings.toml`:
   `MAD_DISPLAY_KEY = "madk_..."`. The board restarts and switches to the feed.
4. Lost a board or leaked a key? **Revoke** it in Admin → Displays. The board
   gets a 401 on its next poll, shows "KEY REJECTED" and falls back to public
   stats.

## What the feed returns (exact whitelist)

| Field | Contents |
|---|---|
| `v` | `1` |
| `community` | numbers only: `total_users`, `total_miles`, `miles_today`, `active_7d`, `longest_streak`, `total_hypes`, `photos_shared`, `out_running_now`, `tokens_spent_today`, `badges_today`, `new_friends_today`, `hypes_today`, `nudges_today`, `miles_yesterday_same_time`, `run_miles_today`, `walk_miles_today`, `run_miles_total`, `walk_miles_total` (community-wide sums by workout type; the RUN VS WALK bar-chart card) |
| `me` | the key owner only: `username`, `mile_done`, `miles_today`, `streak`, `running_now`, `local_time` (`HH:MM:SS`), `minutes_to_midnight`, `year_ago_miles` (their own miles on this date last year, or null), `local_date` (for seasonal looks), `live_miles` (their own live distance while running, else null), `live_kind` (`run`/`walk` for that live session), `longest_run`, `fastest_mile_month` (seconds, full-mile splits only), `days` (their own last 64 local days of miles, -1 = streak-token day; the heatmap), `flamey` (their Flamey's Closet look, only the `color`/`head`/`eyes`/`costume` item ids they own and wear, or null), `medals` (≤ 3 × `{id, name, age_s}`: their own medals from the last 48 h; `id` is an opaque hash, `name` the cleaned medal name) |
| `friends_running` | ≤ 3 × `{name, miles, kind}` (`kind` = `run` or `walk`, so the box says IS RUNNING / IS WALKING): accepted friends who are live right now, share live presence, and are not blocked in either direction |
| `friends_at_risk` | `{count, top}`: how many of the owner's friends (streak ≥ 3, not blocked either way, not paused) have nothing logged on their own local day yet; `top` = up to 3 `{name, streak}`, longest first. Friends already see each other's daily miles in the app. |
| `friends_finished` | ≤ 3 × `{id, name, miles, kind}` — same friends rules as above, for sessions that ended in the last 30 min; `id` is an opaque hash |
| `comments` | ≤ 3 × `{id, from, text, age_s}`: comments from the last 24 h on posts the owner is tagged in (someone else's collab or buddy-walk post where the owner is an accepted coauthor). Commenter by username only, text cleaned to the panel's characters; never the owner's own comments; blocks either way hide a comment, as in the thread. `id` is an opaque hash. |
| `desk` | `{style, mascot, rev, sleep_start, sleep_end, never_sleep}` set for THIS box from the phone remote, or null. Style/mascot apply once per `rev`; sleep hours (minutes, owner's local time; null = the box's own `MAD_NIGHT`) apply as they are |
| `commands` | ≤ 5 × `{id, kind}`: remote taps for this box from the last 3 min; `kind` is `show` (run the stat show) or `wake` (bright for 30 min) |
| `friends_miles` | ≤ 3 × `{id, name, miles, seconds, best_pace, age_s, kind}` (`kind` from their latest run/walk today): friends who "got their mile in" in the last hour — the owner's own announcements (so the friend's audience settings already applied, blocks excluded) — with that friend's day so far (the same numbers the notification shows) |
| `messages` | ≤ 3 × `{id, from, text, age_s}`: unexpired desk messages sent TO the owner from Admin → Displays (sender username only, text cleaned to the panel's characters, 24 h expiry) |
| `reviews` | founder mode, admin owners only (everyone else gets `[]`): ≤ 3 × `{id, stars, title}` from Apple's public App Store reviews feed for the app, newest first. `id` is an opaque hash, `title` is cleaned to the panel's characters; reviewer names and review text are never passed on. Fetched server-side at most every 15 min. |
| `alerts` | ≤ 5 × `{id, kind, from, at}`: the owner's own `nudge`/`hype` notifications from the last 24 h. `from` is the sender's username, `id` is an opaque hash. Blocked senders are excluded. |

It never returns emails, real names, user ids, Apple ids, notification
titles or bodies, locations or routes, or anything from another user's
account. `backend/scripts/display-check.mjs` (run in CI) asserts this over
real HTTP.

## Security model

- **Keys:** 256-bit random. Only the SHA-256 hash is stored. The admin list
  shows a 4-character prefix and never the hash.
- **Transport:** keys are accepted only in the `Authorization: Display` header
  (never in the query string), the response is `Cache-Control: no-store`, and
  `/display` has no CORS. The board refuses to send its key to a non-https
  URL and never prints it.
- **Mounting:** `/display` is mounted before `authenticateToken` and ends in a
  404 catch-all, so a display key can't reach any other API route. A user JWT
  doesn't open the feed either.
- **Throttling:** an IP rate limit (240 per 15 min) runs before the key
  lookup.
- **Offline status:** `last_used_at` is stamped at most every 2 min; Admin → Displays marks a board offline after 10 min of silence.
- **Revocation:** a revoked key, or the key of a deleted user (the rows
  cascade), gets the same generic 401 as a wrong key.
- **Key management:** create, list and revoke all require `role = admin`.
- **Desk messages:** only admins can send or list them (`POST/GET /admin/display-messages`); a message is readable only through the recipient's own display key and expires after 24 h. Text is reduced to upper-case letters, digits, a little punctuation and four emoji tokens before it is stored.
- **Closet, medals, reviews:** the closet look is filtered to items the owner actually owns (same rule as the app), medals are the owner's own, and the App Store reviews (already public) only go to desks whose owner has `role = admin`.
- **Box state:** the only thing a box sends is that one `X-Desk-State` line
  about its own screen; it's stored on its key row and shown in the remote.
- **Read-only:** the display never marks notifications read and never writes
  user data. The only write is a throttled `last_used_at` stamp on the key.
  (Desk messages are written by admins in Admin → Displays, never by a display.)

## The phone remote (mileaday.run/admin/desk)

A phone-first page for your own desk box. Each admin signs in with their own
account and sees and controls only the boxes whose display key belongs to
them (Rob's box for Rob, Dave's for Dave); anyone else's box answers 404 on
every endpoint. Messages can still go to any other box (by name only). If you
own more than one box, pick one (remembered on that phone), then:

- **The real screen.** The page runs the box's own code (`desk/firmware/mad`,
  copied to `website/public/desk/py`) in MicroPython WebAssembly on the box's
  real feed, so the preview is exactly what the desk shows: real numbers,
  Flamey's closet look, the season. Pick a style or mascot to preview it, then
  "Show on desk".
- **Sleep**: wake it now (30 min), set its sleep and wake times, or keep it
  awake all night. The box reports what's on its screen with each poll
  (`X-Desk-State: style,mascot,awake,sleep_start,sleep_end`, strictly parsed,
  stored on its key), so the preview follows its buttons and its sleep.
- **Stat show** on demand (real numbers). Nothing else can be triggered:
  nudges, hypes, runs, medals and messages only come from real activity.
- **Messages** from this box's owner to another box, and the last two weeks
  of messages to and from them.
- **Live now**: the same data the box has (friends running / finished / at
  risk, the owner's mile, community numbers).
- **Activity**: the last 7 days on this box, from the same sources as its
  feed (nudges, hypes, messages, medals, the owner's runs, friends' finished
  runs) plus every change made from the remote.

API (admin only): `GET /admin/desk/boxes`, `GET /admin/desk/box/:id`,
`POST /admin/desk/box/:id/settings {style?, mascot?}`,
`POST /admin/desk/box/:id/show`, `POST /admin/desk/box/:id/message {to, text}`.
Settings and taps are per box (key id); a box only ever sees its own. Taps
are rate-limited (30 per 10 min) and expire after 3 minutes; the box polls
every ~15 s. Its buttons still work: a remote change applies once (by `rev`).
