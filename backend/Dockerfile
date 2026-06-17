# syntax=docker/dockerfile:1

# Mile A Day backend — production image.
#
# Migrations run automatically at container startup (see docker-entrypoint.sh)
# BEFORE the HTTP server binds its port / becomes healthy. Combined with
# Coolify health-check-gated (zero-downtime) deploys, the OLD container keeps
# serving traffic the entire time the NEW container migrates + boots, so there
# is no downtime window.
#
# IMPORTANT: this only stays zero-downtime if every migration is
# backwards-compatible (additive / nullable). During the deploy overlap the old
# code runs against the already-migrated schema, so never drop/rename/retype a
# column the currently-shipped code reads in the same deploy — split those into
# an expand step (deploy 1) and a contract step (deploy 2).

# ---- Builder: install all deps + compile TypeScript ----
FROM node:24-slim AS builder
WORKDIR /app

COPY package*.json ./
RUN npm ci

COPY . .
RUN npm run build

# ---- Runner: minimal runtime that migrates then serves ----
FROM node:24-slim AS runner
ENV NODE_ENV=production
WORKDIR /app

# Reuse the builder's resolved node_modules. We keep the FULL tree (not
# --omit=dev) on purpose: `drizzle-kit migrate` runs at startup and drizzle-kit
# is a devDependency. Copying from the builder is deterministic and avoids a
# second install. (All deps here are pure-JS, so no native rebuild concerns.)
COPY --from=builder /app/node_modules ./node_modules

# Compiled server.
COPY --from=builder /app/dist ./dist

# Everything drizzle-kit needs at runtime: the config + the migrations folder
# (`out` in drizzle.config.ts = ./src/db/drizzle, holds the .sql files + meta).
COPY --from=builder /app/package.json ./package.json
COPY --from=builder /app/drizzle.config.ts ./drizzle.config.ts
COPY --from=builder /app/src/db/drizzle ./src/db/drizzle

COPY docker-entrypoint.sh ./docker-entrypoint.sh
RUN chmod +x docker-entrypoint.sh

# Container listens on PORT (defaults to 3000 in server.ts). Expose only — do
# NOT publish a fixed host port in Coolify; let the Traefik proxy route the
# domain to this port so old + new containers can run side by side on deploy.
EXPOSE 3000

# Health check on the public /status route. start-period covers migrate + boot
# so a slow first start doesn't get marked unhealthy. Coolify uses this to gate
# the traffic switch (keep old alive until new is healthy).
HEALTHCHECK --interval=15s --timeout=5s --start-period=90s --retries=5 \
	CMD node -e "fetch('http://127.0.0.1:'+(process.env.PORT||3000)+'/status').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"

ENTRYPOINT ["./docker-entrypoint.sh"]
