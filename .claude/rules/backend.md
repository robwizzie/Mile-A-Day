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

## Auth Pattern
- Public routes (`/auth/*`, `/dev/*`, `/status`) are mounted BEFORE `authenticateToken` middleware in server.ts.
- Protected routes are mounted AFTER. `req.userId` is set by auth middleware (see `AuthenticatedRequest` type).
- Use `requireSelfAccess('paramName')` middleware when a route should only allow users to access their own resources.

## Adding a New Endpoint
1. Add service function in `services/` (DB queries + business logic)
2. Add controller function in `controllers/` (req/res handling)
3. Add route in `routes/` (wire to controller)
4. If new route file, register in `server.ts` (before or after `authenticateToken` depending on auth needs)

## ESM Reminder
All imports MUST end with `.js` extension:
```typescript
import { foo } from './services/fooService.js';
```
