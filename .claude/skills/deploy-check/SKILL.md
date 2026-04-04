---
name: deploy-check
description: Run build and lint checks across backend and website before deploying. Use when the user wants to verify everything builds cleanly.
---

# Pre-Deploy Verification

Run all build and lint checks to verify the project is in a deployable state. Since there is no CI/CD pipeline, this is the safety net.

## Checks to Run

Run these in parallel where possible:

### Backend
```bash
cd backend && npm run build
```
- TypeScript compilation must succeed with zero errors
- If it fails, show the errors and suggest fixes

### Website
```bash
cd website && pnpm build
```
```bash
cd website && pnpm lint
```
- Next.js build must succeed
- ESLint must pass with zero errors (warnings are OK)
- If either fails, show the errors and suggest fixes

## Report

After all checks complete, give a summary:

```
Deploy Check Results:
  Backend build:  ✓ / ✗
  Website build:  ✓ / ✗
  Website lint:   ✓ / ✗
```

If everything passes, say it's safe to deploy. If anything fails, list what needs fixing.
