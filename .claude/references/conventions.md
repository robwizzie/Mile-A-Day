# Repo Conventions

Cross-cutting conventions for Mile A Day. Area-specific rules live in `.claude/rules/{backend,ios,website}.md`.

## Package manager
- **npm** everywhere (backend + website). Never `pnpm`, `yarn`, or `bun`. Commit `e3601af` switched the website off pnpm — don't reintroduce.
- iOS uses Xcode + Swift Package Manager (project file managed via Xcode UI; do not edit `project.pbxproj`).

## Commits
- No `Co-Authored-By: Claude` lines. Author is the human.
- Conventional-ish prefixes used loosely: `Add`, `Fix`, `Refactor`, `Update`, `Remove`. Match what `git log --oneline -10` shows.

## Code style
- Backend: no formatter. Match existing patterns. ESM imports MUST end with `.js` (enforced by hook).
- Website: ESLint via `npm run lint`. No Prettier config.
- iOS: SwiftUI + MVVM. No SwiftLint. Follow `.claude/rules/ios.md`.

## Cross-area changes
When a feature touches the API contract between iOS and backend:
1. Update backend (`backend/src/routes/`, `controllers/`, `services/`, `types/`)
2. Update iOS service layer (`app/Mile A Day/Services/`)
3. Run `cd backend && npm run build` and verify Xcode builds before committing
4. Update `Mile-A-Day-Complete-APIs.postman_collection.json` if the endpoint shape changed

## Database
- No migrations system. Schema changes are manual SQL against PostgreSQL.
- Use parameterized queries (`$1, $2, ...`) — never string-interpolate user input.
- `PostgresService.getInstance()` is a singleton; don't construct new pools.

## Secrets
- Backend reads from `backend/.env` (gitignored). Website reads from `website/.env.local` (gitignored).
- `.mcp.json` is gitignored because the postgres MCP needs `DATABASE_URL`. Don't commit it.
- APNs key lives in `backend/certs/` (gitignored).
