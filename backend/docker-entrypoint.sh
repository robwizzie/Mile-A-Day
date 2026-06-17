#!/bin/sh
# Apply pending DB migrations, then start the server. `set -e` makes a failed
# migration abort startup with a non-zero exit so the container never serves
# against a half-migrated schema — Coolify then keeps the previous (healthy)
# container running instead of switching traffic to a broken one.
set -e

echo "[entrypoint] Applying database migrations (drizzle-kit migrate)..."
npm run db:migrate
echo "[entrypoint] Migrations applied. Starting server..."

# exec so node becomes PID 1 and receives SIGTERM/SIGINT directly for clean shutdown.
exec node dist/server.js
