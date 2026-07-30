# Architecture Decisions

ADR-style records for choices that shape how the codebase works. One entry per decision; concise.

<!-- Format:
## ADR-NNN: <Title>
**Date**: YYYY-MM-DD
**Status**: accepted | superseded by ADR-NNN
**Context**: what problem are we solving
**Decision**: what we chose
**Consequences**: tradeoffs we accepted
-->

## ADR-001: ESM with .js extensions on backend imports
**Date**: pre-2026-01 (existing pattern, recorded here for posterity)
**Status**: accepted
**Context**: Backend uses `"type": "module"` in package.json. TypeScript compiles `.ts` files but Node resolves `.js` paths at runtime.
**Decision**: All local imports MUST end with `.js`, even when source is `.ts`. Enforced by `.claude/hooks/` (extension check on Write/Edit).
**Consequences**: Looks redundant in source but matches Node's resolution. Switching to `tsx` for dev but `node` for prod requires this.

## ADR-002: No ORM, raw SQL with parameterized queries
**Date**: pre-2026-01
**Status**: superseded — Drizzle ORM + drizzle-kit migrations now coexist with raw SQL on the same pool (see `.claude/rules/backend.md`)
**Context**: Backend interacts with PostgreSQL via `pg`.
**Decision**: No Prisma, no Drizzle. `PostgresService` singleton wraps `pg.Pool`. All queries are raw parameterized SQL.
**Consequences**: More boilerplate per query; full control over SQL. Requires manual schema management (no migrations system).

## ADR-003: Website on npm (not pnpm)
**Date**: ~2026-04 (commit e3601af)
**Status**: accepted
**Context**: Website was originally on pnpm; backend always on npm. Mismatch caused friction in shared tooling.
**Decision**: Website moved to npm. Both projects now use npm exclusively.
**Consequences**: Slightly larger node_modules; consistent tooling.

## ADR-004: Streak Assist rescue window is 2 days, including the bridged miss
**Date**: 2026-07-30
**Status**: accepted (owner-confirmed after reviewing a live example)
**Context**: A friend profile showed "Save Streak" for a miss two days back (missed Mon, ran Tue, viewed Wed), which looked like a bug — the assumption was assists should only cover *yesterday's* miss.
**Decision**: Keep `ASSIST_RESCUE_WINDOW_DAYS = 2` (streakFeatureService) and the bridged-miss branch in `getLiveAssistableBreak` (`ok(d1) && !ok(d2) && ok(d3)`). A miss two days back stays rescuable when every day since is intact, because one coverage token fully reconnects the chain; `gap_too_wide` already blocks anything a single token can't repair.
**Consequences**: Friends get an extra day to notice a break (plus timezone slack), and a friend who already resumed on their own can still be saved. This is intended behavior — do not narrow it to yesterday-only without a new decision here.
