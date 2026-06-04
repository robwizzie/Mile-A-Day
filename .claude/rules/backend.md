---
globs: backend/**
---

# Backend Conventions

## Architecture: Routes -> Controllers -> Services
- `routes/` - Express Router definitions. Thin: just wire HTTP verbs to controller functions + middleware.
- `controllers/` - Request/response handling. Parse params/body, call services, format responses.
- `services/` - Business logic and DB queries. No Express types (Request/Response) here.
- `types/` - TypeScript interfaces for domain objects.
- `cron/` - Scheduled jobs (competitions, notifications).

## Database
- `PostgresService` is a singleton wrapping `pg.Pool`. Get it via `PostgresService.getInstance()`.
- Raw SQL queries only (no ORM). Use parameterized queries (`$1, $2, ...`).
- Connection string from `DATABASE_URL` env var.
- Services instantiate `PostgresService.getInstance()` at module top-level. `server.ts` MUST `import 'dotenv/config'` as its first line — if dotenv loads after the route imports, the Pool gets `connectionString: undefined` and falls back to OS user (error: `no pg_hba.conf entry for host ..., user "<osuser>", database "<osuser>"`).

## Auth Pattern
- Public routes (`/auth/*`, `/dev/*`, `/status`) are mounted BEFORE `authenticateToken` middleware in server.ts.
- Protected routes are mounted AFTER. `req.userId` is set by auth middleware (see `AuthenticatedRequest` type).
- Use `requireSelfAccess('paramName')` middleware when a route should only allow users to access their own resources.

## Adding a New Endpoint
1. Add service function in `services/` (DB queries + business logic)
2. Add controller function in `controllers/` (req/res handling)
3. Add route in `routes/` (wire to controller)
4. If new route file, register in `server.ts` (before or after `authenticateToken` depending on auth needs)

## Competition Resolution
- Standings are recomputed LIVE on every read (`getUserScores` in `getCompetition`) — even for finished comps. So a competition's stored `end_date` directly bounds which days count (scoring includes `local_date <= end_date`; `local_date` = workout START date in user tz).
- When resolving EARLY (target/goal/duration hit, not a preset end_date), set `end_date` to the last COMPLETED interval (`lastCompletedIntervalEnd`), NOT the resolution day. Resolution scoring excludes the current interval, so stamping `end_date = todayStr` makes the live recompute fold that day back in once the calendar advances → phantom points/placement drift.

## ESM Reminder
All imports MUST end with `.js` extension:
```typescript
import { foo } from './services/fooService.js';
```
