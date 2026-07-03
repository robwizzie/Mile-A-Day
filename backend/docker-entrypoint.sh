#!/bin/sh
# Apply pending DB migrations, then start the server. `set -e` makes a failed
# migration abort startup with a non-zero exit so the container never serves
# against a half-migrated schema — Coolify then keeps the previous (healthy)
# container running instead of switching traffic to a broken one.
#
# Migrations run through the statement-level idempotent applier (NOT strict
# `drizzle-kit migrate`): production's bookkeeping predates drizzle in places,
# and the strict migrator dies on objects that already exist — which quietly
# pinned every deploy to the old container while the schema stayed behind the
# code. The applier converges any additive-schema state and only exits
# non-zero on a real failure.
set -e

echo "[entrypoint] Applying database migrations (idempotent applier)..."
node dist/db/migrateCli.js
echo "[entrypoint] Migrations applied. Starting server..."

# exec so node becomes PID 1 and receives SIGTERM/SIGINT directly for clean shutdown.
exec node dist/server.js
