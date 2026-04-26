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
**Status**: accepted
**Context**: Backend interacts with PostgreSQL via `pg`.
**Decision**: No Prisma, no Drizzle. `PostgresService` singleton wraps `pg.Pool`. All queries are raw parameterized SQL.
**Consequences**: More boilerplate per query; full control over SQL. Requires manual schema management (no migrations system).

## ADR-003: Website on npm (not pnpm)
**Date**: ~2026-04 (commit e3601af)
**Status**: accepted
**Context**: Website was originally on pnpm; backend always on npm. Mismatch caused friction in shared tooling.
**Decision**: Website moved to npm. Both projects now use npm exclusively.
**Consequences**: Slightly larger node_modules; consistent tooling.
