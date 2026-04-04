---
name: new-endpoint
description: Scaffold a new backend API endpoint following the Routes → Controllers → Services architecture. Use when the user wants to add a new API endpoint or route.
---

# Scaffold a New Backend Endpoint

The user wants to create a new backend endpoint. Use `$ARGUMENTS` for context on what the endpoint should do.

Follow this exact process, using the existing patterns in the codebase:

## 1. Service (`backend/src/services/`)

- Create or add to an existing service file
- Get DB instance: `const db = PostgresService.getInstance();`
- Import from `'./DbService.js'`
- Use raw parameterized SQL (`$1, $2, ...`)
- No Express types here — plain TypeScript functions
- Export each function individually (named exports)

## 2. Controller (`backend/src/controllers/`)

- Create or add to an existing controller file
- Import `{ Request, Response }` from `'express'`
- Import service functions from `'../services/<name>Service.js'`
- Use `hasRequiredKeys` for param validation when applicable
- Wrap in try/catch, return JSON responses
- Parse params from `req.params`, body from `req.body`, query from `req.query`

## 3. Route (`backend/src/routes/`)

- Create or add to an existing route file
- `import { Router } from 'express'`
- Import controller functions from `'../controllers/<name>Controller.js'`
- Use `requireSelfAccess('paramName')` for user-owned resources
- Export `default router`

## 4. Register in `server.ts` (only if new route file)

- Import the router at the top of `backend/src/server.ts`
- Mount it AFTER `app.use(authenticateToken)` if it needs auth (most routes)
- Mount it BEFORE `authenticateToken` if it should be public (rare)

## Critical Rules

- **ALL local imports MUST use `.js` extension** (e.g., `import { foo } from './services/fooService.js'`)
- Backend is ESM (`"type": "module"`)
- Follow the exact patterns from existing files like `workoutRoutes.ts`, `workoutController.ts`, `workoutService.ts`
- Use `PostgresService.getInstance()` for DB access, never import `pg` directly
