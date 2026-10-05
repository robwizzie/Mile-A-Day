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
| `community` | numbers only: `total_users`, `total_miles`, `miles_today`, `active_7d`, `longest_streak`, `total_hypes`, `photos_shared`, `out_running_now`, `tokens_spent_today`, `badges_today`, `new_friends_today`, `hypes_today`, `nudges_today`, `miles_yesterday_same_time` |
| `me` | the key owner only: `username`, `mile_done`, `miles_today`, `streak`, `running_now`, `local_time` (`HH:MM:SS`), `minutes_to_midnight`, `year_ago_miles` (their own miles on this date last year, or null), `local_date` (for seasonal looks), `live_miles` (their own live distance while running, else null), `longest_run`, `fastest_mile_month` (seconds, full-mile splits only) |
| `friends_running` | ≤ 3 × `{name, miles}`: accepted friends who are live right now, share live presence, and are not blocked in either direction |
| `friends_at_risk` | `{count, top}`: how many of the owner's friends (streak ≥ 3, not blocked either way, not paused) have nothing logged on their own local day yet; `top` = up to 3 `{name, streak}`, longest first. Friends already see each other's daily miles in the app. |
| `friends_finished` | ≤ 3 × `{id, name, miles}` — same friends rules as above, for sessions that ended in the last 30 min; `id` is an opaque hash |
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
- **Read-only:** the display never marks notifications read and never writes
  user data. The only write is a throttled `last_used_at` stamp on the key.
