Add a new API endpoint to the backend.

Follow the existing three-layer pattern exactly:
1. **Route** — Add to appropriate `backend/src/routes/` file. Use `requireSelfAccess()` middleware if the endpoint accesses user-owned data. Use higher-order handler factories if creating accept/decline style paired endpoints.
2. **Controller** — Add to `backend/src/controllers/`. Validate with `hasRequiredKeys()` for early return. Catch errors with `instanceof BadRequestError` → 400, else → 500.
3. **Service** — Add to `backend/src/services/`. Use `PostgresService.getInstance()` for DB access. Throw `BadRequestError` for validation failures. Use parameterized queries (`$1`, `$2`) — never string interpolation. Use `db.transaction()` for multi-query operations.
4. **Types** — Add to `backend/src/types/`. Use `snake_case` field names matching PostgreSQL columns. Use union types for enums.

Reference existing endpoints for patterns (workouts, competitions, friendships).

Endpoint description: $ARGUMENTS
