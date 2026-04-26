# Mile A Day

Gamified fitness app: run a mile every day, build streaks, compete with friends.

## Project Structure

- `app/` - iOS app (Swift/SwiftUI, targets iOS + watchOS + Widgets)
- `backend/` - REST API (TypeScript, Express 5.1, PostgreSQL)
- `website/` - Marketing site (Next.js 16, React 19, Tailwind CSS 4)

## Quick Commands

### Backend (`cd backend`)
- Dev: `npm run dev` (tsx watch with hot reload)
- Build: `npm run build` (tsc)
- Start: `npm run start`
- No test runner configured

### Website (`cd website`)
- Dev: `npm run dev`
- Build: `npm run build`
- Lint: `npm run lint`

### iOS (`app/`)
- Build via Xcode only. Do not attempt `xcodebuild` from CLI.
- Main target: "Mile A Day", also has Watch App and Widget Extension.

## URLs

- Backend API: https://mad.mindgoblin.tech
- Website: https://mileaday.run
- GitHub: git@github.com:robwizzie/Mile-A-Day.git

## Key Gotchas

1. **Backend is ESM** - `"type": "module"` in package.json. All local imports MUST use `.js` extension (e.g., `import foo from './foo.js'`), even though source is `.ts`.
2. **Express 5.1** - Async errors propagate automatically. Controllers currently use explicit try/catch but it's not strictly required.
3. **JWT uses `jose`** - Auth middleware uses `jwtVerify` from `jose`, NOT `jsonwebtoken`. The `jsonwebtoken` package is also installed but only used for token signing in some auth flows.
4. **No migrations system** - Database schema changes are done manually against PostgreSQL. No ORM.
5. **No CI/CD** - No automated tests or deployment pipeline. Be extra careful with changes.
6. **No shared package manager** - Backend and website both use npm. No monorepo tooling.
7. **`.claudeignore` excludes `project.pbxproj`** - This is intentional. Never ask to read it.

## Code Style

- No linter/formatter configured for backend. Follow existing patterns.
- Website has ESLint (`pnpm lint`).
- iOS: follow existing SwiftUI patterns, no SwiftLint.

## Claude Skills & Agents

This repo includes custom Claude Code skills and agents in `.claude/`:

### Skills (invoke with `/skill-name`)
- `/new-endpoint` — Scaffold a backend endpoint (route + controller + service)
- `/api-test` — Test an API endpoint with curl
- `/deploy-check` — Run all build/lint checks before deploying
- `/new-view` — Scaffold a new SwiftUI view (MVVM pattern)
- `/db-query` — Run SQL queries against the database

### Agents (used automatically by Claude for subagent tasks)
- `backend-explorer` — Fast read-only backend search (runs on Haiku)
- `swift-explorer` — Fast read-only iOS codebase search (runs on Haiku)
- `sql-reviewer` — SQL query review for correctness/performance (runs on Sonnet)

### MCP servers (`.mcp.json`, tracked)
- **`context7`** — library/framework docs (Express 5, Next.js 16, React 19, SwiftUI, Tailwind 4). Use whenever you'd otherwise rely on training-data recall.
- **`postgres`** — direct DB access. Reads `${DATABASE_URL}` from your shell env, so set that before launching Claude (e.g. `export DATABASE_URL=postgres://…`).

## Workflow commands (cc-optimize, global)

Available on top of the project skills above:

- `/spec <feature>` — Spec-Driven Development entry point
- `/ship` — final gate (Codex review + tests + UI polish + criteria check)
- `/learn` — sweep session corrections into `.claude/references/gotchas.md`
- `/remember "rule"` — capture a single rule mid-session
- `/maintain` — periodic sweep (re-tune perms, regenerate INSTALLED.md, audit cost)
- `/batch <files>` — fan-out migration orchestrator (one implementer agent per slice)
- `/rollout N` — test-time compute scaling — runs same task N times in parallel; ~6–8x cost
- `/loop-until <criteria>` — Ralph Wiggum auto-retry, capped at $3 / 100k tokens / 5 iters
- `/cc-export` — bundle this setup as a single MD for sharing

⚠ `/rollout` and `/loop-until` are cost-multiplier commands. Invoke deliberately, not by reflex.

## References

- **`.claude/rules/{backend,ios,website}.md`** — area-specific conventions (existing, kept under 60 lines each)
- **`.claude/references/conventions.md`** — cross-cutting conventions (package manager, secrets, cross-area changes)
- **`.claude/references/gotchas.md`** — learned mistakes (grows via `/learn` and `/remember`)
- **`.claude/references/decisions.md`** — ADR-style architectural records
- **`~/.claude/references/{behavior,workflow-overrides,security,skill-catalog}.md`** — workflow-wide rules from cc-optimize (loaded at SessionStart and after PostCompact)

## Self-Maintenance

These Claude files (CLAUDE.md and .claude/rules/*.md) are living documents. Update them as you work:

**When to add an entry:**
- You hit a bug or build error caused by a non-obvious project quirk
- You discover a pattern or convention not yet documented that you'd get wrong next time
- A gotcha cost you a retry or wrong approach

**When to update or remove:**
- A documented convention no longer matches the code
- A gotcha has been fixed and is no longer relevant
- Information is redundant with what you can derive from reading the code

**Rules for edits:**
- Add to the relevant rules file (.claude/rules/backend.md, ios.md, website.md) not CLAUDE.md, unless it's cross-cutting
- Keep entries specific and actionable — "Use X, not Y" not "be careful with X"
- Each file must stay under 60 lines. If a file is getting long, remove the least useful entries first
- Never add obvious language conventions, code that speaks for itself, or vague advice
- After updating, briefly mention what you added/changed so the user is aware
