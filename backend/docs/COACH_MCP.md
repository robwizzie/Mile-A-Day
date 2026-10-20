# Coach MCP (Run Plans for Claude)

Lets any **Mile A Day+** member connect Claude (Claude Code, or claude.ai) to their own run plan:
Claude reads the plan, runs and check-ins and **proposes** plan changes, which the engine caps and
which wait for the runner's approval unless they turned on auto-apply. Code: `src/coachMcp/`.
Check: `scripts/coach-mcp-check.mjs` (in CI). App-side seam: `services/runPlans/coachConnection.ts`.

It is a separate thing from the admin-only DB connector (`src/mcp`, `docs/MCP_CONNECTOR.md`):
other tables (`coach_mcp_*`), router (`/coach`), issuer (`https://mileaday.run/`) and token
audience (`https://mileaday.run/mcp`). A coach token is never accepted at `/mcp` (DB tools) and a
DB-connector token is never accepted at the coach; the check asserts both directions.

```
Claude ──POST https://mileaday.run/mcp──► 401 + resource_metadata (mileaday.run URLs)
   │          (Vercel rewrite → https://mad.mindgoblin.tech/coach/mcp)
   ├─ /register            Claude Code registers itself (loopback redirect only)
   ├─ /authorize           parks the request, sets a browser-binding cookie (Path=/coach/oauth/,
   │                       SameSite=Lax), sends the browser to mileaday.run/connect/coach
   │      └─ Sign in with Apple (the website's Services ID + return URL, popup)
   │      └─ same-origin form POST /coach/oauth/apple/callback → cookie + nonce + Apple
   │         signature + users.apple_sub + Mile A Day+ active
   ├─ /token               code (PKCE S256) → 1-hour access token + rotating refresh token
   └─ POST /mcp            get_profile · get_plan · get_runs · get_checkins · list_proposals · propose_change
```

## Public URLs and the website proxy

Everything Claude sees is on `https://mileaday.run`. The website (`website/next.config.mjs`,
`coachMcpRewrites`) rewrites these exact paths to the backend's `/coach/*`:

| Public (mileaday.run) | Backend |
|---|---|
| `/mcp` | `/coach/mcp` |
| `/authorize`, `/token`, `/register`, `/revoke` | `/coach/authorize` … |
| `/.well-known/oauth-authorization-server` | `/coach/.well-known/oauth-authorization-server` |
| `/.well-known/oauth-protected-resource/mcp` (and the root one) | `/coach/.well-known/oauth-protected-resource/mcp` |
| `/coach/oauth/apple/callback` | `/coach/oauth/apple/callback` |

The MCP SDK's `mcpAuthRouter` is mounted inside the `/coach` router; it writes absolute URLs from
`issuerUrl`/`resourceServerUrl`, which are the public origin (`COACH_MCP_PUBLIC_URL`). So the
issuer, `authorization_endpoint`, `token_endpoint`, `registration_endpoint`, the RFC 9728
protected-resource document and the `WWW-Authenticate: … resource_metadata="https://mileaday.run/.well-known/oauth-protected-resource/mcp"`
on a 401 all name mileaday.run. The check drives the whole sign-in through a stand-in proxy built
from `coachMcpRewrites` itself, and fails if any metadata endpoint has no rewrite.

The callback path is the same on both sides so the browser-binding cookie's `Path=/coach/oauth/`
matches what the browser sees. The sign-in page posts to the relative `/coach/oauth/apple/callback`
(same origin), which is why the cookie can be `SameSite=Lax` (the DB connector needs `None`).

`https://mad.mindgoblin.tech/coach/mcp` also works directly (tokens are bound to the public
resource, not the request host); nothing advertises it.

## Who gets in

`isUserAllowed` (oauth.ts) = `isPlusActive(userId)`, derived live from `plus_purchases`. It runs
at sign-in, at code redemption, at every refresh (a lapse there revokes the sign-in and writes a
`plus_lapsed` audit row; renewing Plus later needs a new sign-in), and on every MCP request (a
lapsed member's access token gets 401).

Which Apple ID is which user comes from `users.apple_sub` (unique). The DB connector refuses to do
that because its sessions can rewrite `users`; nothing a coach session can do touches `users`, so
it is safe here. (A DB-connector admin could re-point `apple_sub`, but they can already edit
anything.)

Tools take no user argument: the user is the token's. Every tool goes through `runPlanService`, so
the engine sets every number and `planAction`/`validateChanges` cap every change. The service
never checks Plus; this module does, per request.

**Clients.**

- **Claude Code:** registers itself, loopback redirects only (`isLoopbackRedirectUri`).
- **claude.ai:** not self-registrable (its callback is shared by all claude.ai users). One
  pre-registered client, `mad-coach-claude-ai`, with its own secret
  `COACH_MCP_CLAUDE_AI_CLIENT_SECRET` (≥ 32 chars, must differ from the DB connector's). Unset =
  Claude Code only. See "Open decision" below.

## Tools

| Tool | Reads / does |
|---|---|
| `get_profile {today?}` | goals, effort, hard days, run_daily_mile, auto-apply, baseline, current fitness, checkpoints |
| `get_plan {today?, from?, to?}` | overview (today, this + next week, totals, checkpoints, pending proposals) or a ≤ 62-day range |
| `get_runs {today?, from?, to?, include_walks?}` | counted runs (default last 28 days, ≤ 120): pace, moving time, walk fraction, indoor, splits |
| `get_checkins {today?, from?, to?}` | feelings, messages, pain flags (default last 30 days) |
| `list_proposals {status?, source?, limit?}` | proposals on the active plan, any source |
| `propose_change {today?, action, params?, summary, rationale}` | `createProposal(…, 'claude')` → `{proposal, applied}`; 422 → error text with the engine's `cap_note` |

`today` is the runner's local date. If omitted, it is derived like every other "today" in the
backend (`userTodaySql`: the most recent workout's `timezone_offset`, else UTC). A given `today`
must be within 2 days of UTC (same rule as the app's `?today=`). The tool descriptions and the
server `instructions` teach Claude the action list, caps, units, that the engine sets numbers and
that proposals are pending by default.

## Audit

`coach_mcp_audit_log`: one row per tool call (`tool`, `args` (≤ 8 KB), `outcome` ok/error,
`detail` = the error text, `duration_ms`) and per auth event (`outcome = 'event'`; `tool` =
`sign_in`, `sign_in_denied`, `refresh_reuse`, `plus_lapsed`, `revoked`).

## The app's view (`coachConnection.ts`)

- `coachConnectionStatus(userId)` → `connected` = some unrevoked, unexpired sign-in still holds an
  unexpired access token or an unexpired, not-yet-rotated refresh token; `last_used_at` = the last
  MCP request (`coach_mcp_oauth_grants.last_used_at`, written on every request), ISO UTC.
- `revokeCoachTokens(userId)` (`DELETE /run-plans/claude`) revokes every sign-in and deletes
  in-flight codes; returns how many sign-ins it revoked. The tables exist (migration 0102) whether
  or not the connector is enabled, so both work with it off.

## Tokens

Same as the DB connector: random, opaque, stored only as SHA-256; request 10 min (single use,
cookie-bound), code 2 min (single use), access 1 hour, sign-in 30 days. Refresh tokens rotate under
a row lock; reuse more than 60 s after rotation revokes the sign-in (`refresh_reuse`). Revoked or
expired sign-ins are kept 30 days (so the app can still show `last_used_at`), then pruned.

All six `coach_mcp_*` tables have RLS on and no policies, so the DB connector's roles (which
don't bypass RLS) read them as empty and can't write them; `checkRoleBoundary` (src/mcp) now also
refuses to run if a `coach_mcp_*` table lacks RLS.

## Rate limits (behind the proxy)

The limiters on `/authorize`, `/token`, `/register`, `/revoke` (SDK handlers) and the Apple
callback key on `clientIp()` like everything else. Through Vercel's rewrite the backend's
peer is Vercel's egress, so in production a bucket is per **Vercel egress IP**, shared by everyone
connecting through that edge — not per person. The coach therefore sets its own maxes, well above
the SDK defaults (which would 429 a few hundred members' hourly refreshes): authorize 300 and
token 1000 per 15 min, register 200 per hour, revoke 300 per 15 min. Every secret is 256-bit
random, so these are flood control, not brute-force protection. The Apple callback has its own
limiter for the same reason (300 per 15 min; the app-wide `signInLimiter` is 30). If shared
buckets ever trip for legitimate traffic, the fix is a `website/proxy.ts` that forwards the
client IP in a header signed with a shared secret, and a `clientIp()` that trusts it only with
that secret.

## Env vars

**Backend (Coolify):**

| Var | Required | Meaning |
|---|---|---|
| `COACH_MCP_ENABLED` | yes, `1` | Off (nothing mounted under `/coach`) unless set. Deploying without it is dark. |
| `COACH_MCP_CLAUDE_AI_CLIENT_SECRET` | optional | `openssl rand -hex 32`. Enables the claude.ai client `mad-coach-claude-ai`. Must differ from `MCP_CLAUDE_AI_CLIENT_SECRET`. |
| `COACH_MCP_PUBLIC_URL` | optional | Public origin, default `https://mileaday.run`. No path. Must not equal `MCP_BASE_URL`. |
| `COACH_MCP_SIGNIN_PAGE_URL` | optional | Default `<public>/connect/coach`. |
| `APPLE_WEB_CLIENT_ID` | optional (shared) | Apple Services ID the id_token must be for; default `org.robertwiscount.Mile-A-Day.web` (the website's). |

**Website (Vercel):** nothing required. `COACH_MCP_BACKEND_URL` (else `NEXT_PUBLIC_API_URL`, else
`https://mad.mindgoblin.tech`) is where the rewrites point; rewrites are fixed at build time, so a
change needs a redeploy. `NEXT_PUBLIC_APPLE_WEB_CLIENT_ID` / `NEXT_PUBLIC_APPLE_WEB_REDIRECT_URI`
are the admin login's, reused by `/connect/coach`.

## Apple Developer

**Nothing new is required.** `/connect/coach` uses the same Services ID
(`org.robertwiscount.Mile-A-Day.web`) and the same registered return URL
(`https://mileaday.run/admin`) as the admin dashboard and `/admin/connect`, in popup mode, on the
same origin. The Apple `sub` it returns matches `users.apple_sub` from the app because the
Services ID is grouped with the app's primary App ID (the admin login already relies on this).

Optional: add `https://mileaday.run/connect/coach` as a return URL on that Services ID (Certificates,
Identifiers & Profiles → Identifiers → Services IDs → the web ID → Sign in with Apple → Configure →
Return URLs) and set `NEXT_PUBLIC_APPLE_WEB_REDIRECT_URI` accordingly — not needed for popup mode.

## Rollout

1. Merge → backend deploys with the migration (new tables only) and the coach **off**.
2. Website deploys with the rewrites. With the coach off, the rewritten paths reach the app's
   `authenticateToken` and 401; nothing else changes.
3. Coolify: set `COACH_MCP_ENABLED=1` (and optionally `COACH_MCP_CLAUDE_AI_CLIENT_SECRET`), redeploy.
   Boot log: `[coach-mcp] on: public https://mileaday.run/mcp → backend /coach/mcp; …`.
4. Smoke: `curl -si https://mileaday.run/mcp -X POST` → 401 with
   `resource_metadata="https://mileaday.run/.well-known/oauth-protected-resource/mcp"`;
   `curl -s https://mileaday.run/.well-known/oauth-authorization-server` → issuer
   `https://mileaday.run/`. Then connect once: `claude mcp add --transport http mad-coach https://mileaday.run/mcp`, `/mcp`.
5. claude.ai (if enabled): Settings → Connectors → Add custom connector, URL
   `https://mileaday.run/mcp`, Advanced: client ID `mad-coach-claude-ai` + the secret.

## Open decision: claude.ai for everyone

The pre-registered claude.ai client needs its secret entered in claude.ai. For admins that is a
real secret; for every Plus member it would have to be shown to them (e.g. on the app's Connect
Claude screen), at which point it no longer keeps strangers out, and the shared-callback phishing
case it guards against (a sign-in link from someone else's connector) rests on claude.ai binding
`state` to the user who started it, plus the sign-in page's "only continue if you started this"
line. Claude Code (loopback) has no such exposure.

## Turning it off

- **Everyone, now:** unset `COACH_MCP_ENABLED`, redeploy. Nothing is mounted.
- **One runner:** `DELETE /run-plans/claude` from the app (`revokeCoachTokens`).
- **Every live sign-in, without a deploy:** `UPDATE coach_mcp_oauth_grants SET revoked_at = now() WHERE revoked_at IS NULL`.
