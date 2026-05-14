# Competition Name on Create — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let users name a competition when creating one, with a 50-character cap enforced both in the iOS create UI and on the backend.

**Architecture:** Add a TextField at the top of `CreateCompetitionView` whose placeholder shows the live auto-generated name; truncate user input and trim on submit. On the backend, add a `validateCompetitionName` helper to `competitionService.ts` and call it from both `createCompetition` and `updateCompetition` service functions. Cap is duplicated between iOS (`CompetitionLimits.nameMaxLength`) and backend (`COMPETITION_NAME_MAX_LENGTH`) with cross-referenced "keep in sync" comments because there is no shared package.

**Tech Stack:** Swift / SwiftUI (iOS 17+ Observation), TypeScript / Express 5.1 / `pg`, PostgreSQL.

**Spec:** `docs/superpowers/specs/2026-05-14-competition-name-on-create-design.md`

**Test infrastructure note:** Neither the iOS target nor the backend has an automated test runner (per `CLAUDE.md`). TDD steps are replaced with explicit manual verification using Xcode for iOS and `curl` for backend. The backend has `npm run build` for type-check; iOS builds via Xcode only.

---

## File Structure

| Path | Action | Responsibility |
|---|---|---|
| `app/Mile A Day/Models/CompetitionLimits.swift` | Create | Single iOS constant for the name length cap |
| `app/Mile A Day/Views/Competitions/CreateCompetitionView.swift` | Modify | Add `nameSection`, `autoCompetitionName` computed prop, truncation `onChange`, trim before submit |
| `backend/src/services/competitionService.ts` | Modify | Add `COMPETITION_NAME_MAX_LENGTH` + `validateCompetitionName`; call from `createCompetition` and `updateCompetition` |

No changes to: routes, controllers, types, DB schema, models, or any shared code.

---

## Task 1: Add iOS `CompetitionLimits` constant

**Files:**
- Create: `app/Mile A Day/Models/CompetitionLimits.swift`

- [ ] **Step 1: Create the file with the limits enum**

Write the following to `app/Mile A Day/Models/CompetitionLimits.swift`:

```swift
import Foundation

enum CompetitionLimits {
    /// Maximum length, in characters, of a user-supplied competition name.
    /// Keep in sync with COMPETITION_NAME_MAX_LENGTH in
    /// backend/src/services/competitionService.ts
    static let nameMaxLength = 50
}
```

- [ ] **Step 2: Commit**

```bash
cd /Users/david/dev/Mile-A-Day/.claude/worktrees/competition-rename-on-create
git add "app/Mile A Day/Models/CompetitionLimits.swift"
git commit -m "Add CompetitionLimits.nameMaxLength constant"
```

> **Note on Xcode project file:** `project.pbxproj` is excluded via `.claudeignore` (CLAUDE.md gotcha #7) and must NOT be edited from Claude. The user will need to add `CompetitionLimits.swift` to the "Mile A Day" target in Xcode (drag-into-Models or "Add Files to…") before the next iOS build will compile. Note this in the task PR/commit description so the reviewer remembers.

---

## Task 2: Hoist auto-name into a computed property

This is a no-behavior-change refactor that lets Task 3's placeholder and the existing submit-fallback share one definition.

**Files:**
- Modify: `app/Mile A Day/Views/Competitions/CreateCompetitionView.swift` (around lines 41-44 for the new property, lines 1010-1012 + 1031 for the call sites)

- [ ] **Step 1: Add the `autoCompetitionName` computed property**

Find the existing `firstSelectedFriend` computed property (currently at lines 41-43):

```swift
    var firstSelectedFriend: BackendUser? {
        selectedFriends.first
    }
```

Add immediately after it:

```swift
    /// Auto-generated competition name used as the placeholder in the name
    /// field and as the submit-time fallback when the user leaves the field
    /// blank.
    var autoCompetitionName: String {
        if selectedFriends.isEmpty {
            return "\(selectedType.displayName) Competition"
        }
        let friendNames = selectedFriends.prefix(2).map { $0.displayName }.joined(separator: " & ")
        return "\(selectedType.displayName) with \(friendNames)"
    }
```

- [ ] **Step 2: Replace the inline auto-name in `createCompetition()`**

Find this block in `createCompetition()` (currently around lines 1010-1012):

```swift
        // Generate competition name based on type and participants
        let friendNames = selectedFriends.prefix(2).map { $0.displayName }.joined(separator: " & ")
        let autoName = "\(selectedType.displayName) with \(friendNames)"
```

Replace with:

```swift
        // Use auto-generated fallback name when the user leaves the name field blank
        let autoName = autoCompetitionName
```

The `name:` argument passed to `createCompetition` (currently `competitionName.isEmpty ? autoName : competitionName`) stays the same in this task; whitespace trimming is added in Task 3.

- [ ] **Step 3: Manual verification in Xcode**

This is a refactor; existing behavior must be unchanged.

1. Open the project in Xcode.
2. Build the "Mile A Day" target. Expect: build succeeds, no new warnings.
3. Run the app, open Create Competition, pick a type and 1–2 friends, tap Create.
4. Confirm the created competition appears in the lobby list with the same name format as before: `"<Type> with <FriendName>"` or `"<Type> with <A> & <B>"`.

- [ ] **Step 4: Commit**

```bash
cd /Users/david/dev/Mile-A-Day/.claude/worktrees/competition-rename-on-create
git add "app/Mile A Day/Views/Competitions/CreateCompetitionView.swift"
git commit -m "Hoist auto-generated competition name into computed property"
```

---

## Task 3: Add the name input section with truncation and submit-trim

**Files:**
- Modify: `app/Mile A Day/Views/Competitions/CreateCompetitionView.swift`
  - Add `nameSection` (new `var`)
  - Insert it as the first child of the main form `VStack` (currently the first child is `challengersSection` at line 118)
  - Add a truncation `.onChange(of: competitionName)` modifier
  - In `createCompetition()`, trim whitespace from `competitionName` before the empty-check / submit

- [ ] **Step 1: Add the `nameSection` computed view**

Find the `// MARK: - Competitors Section` line (currently at line 259). Insert the following BEFORE that mark, immediately after the closing brace of the `body` property:

```swift
    // MARK: - Name Section

    var nameSection: some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
            Text("Competition Name")
                .font(MADTheme.Typography.subheadline)
                .foregroundColor(.white.opacity(0.6))
                .padding(.horizontal, MADTheme.Spacing.sm)

            TextField(
                "",
                text: $competitionName,
                prompt: Text(autoCompetitionName)
                    .foregroundColor(.white.opacity(0.4))
            )
            .font(MADTheme.Typography.headline)
            .foregroundColor(.white)
            .textInputAutocapitalization(.words)
            .submitLabel(.done)
            .padding(MADTheme.Spacing.lg)
            .background(
                RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
            )
            .padding(.horizontal, MADTheme.Spacing.sm)
            .onChange(of: competitionName) { _, newValue in
                if newValue.count > CompetitionLimits.nameMaxLength {
                    competitionName = String(newValue.prefix(CompetitionLimits.nameMaxLength))
                }
            }
        }
    }
```

- [ ] **Step 2: Insert `nameSection` at the top of the form**

Find this block in `body` (currently around lines 116-118):

```swift
                ScrollView {
                    VStack(spacing: MADTheme.Spacing.xl) {
                        // Challengers Section
                        challengersSection
```

Replace with:

```swift
                ScrollView {
                    VStack(spacing: MADTheme.Spacing.xl) {
                        // Name Section
                        nameSection

                        // Challengers Section
                        challengersSection
```

- [ ] **Step 3: Trim whitespace before submit in `createCompetition()`**

Find this line in `createCompetition()` (currently around line 1031):

```swift
                    name: competitionName.isEmpty ? autoName : competitionName,
```

Replace with:

```swift
                    name: {
                        let trimmed = competitionName.trimmingCharacters(in: .whitespacesAndNewlines)
                        return trimmed.isEmpty ? autoName : trimmed
                    }(),
```

- [ ] **Step 4: Manual verification in Xcode**

1. Build the target. Expect: success, no new warnings.
2. Run the app and open Create Competition. Confirm the "Competition Name" section appears at the very top, above "Competitors".
3. With no friends selected and Apex (default) type: placeholder reads `"Apex Competition"`.
4. Pick a type (e.g. Race) and 1 friend (e.g. "Alice"): placeholder updates to `"Race with Alice"`.
5. Pick a 2nd friend ("Bob"): placeholder becomes `"Race with Alice & Bob"`.
6. Pick a 3rd friend ("Cara"): placeholder stays `"Race with Alice & Bob"` (the `prefix(2)` truncation is intentional and pre-existing).
7. Type 60 characters into the field. Confirm input freezes at 50 characters.
8. Clear the field, tap Create. Confirm the new competition uses the auto-name in the lobby.
9. Type a custom name ("Sunday long run"), tap Create. Confirm the new competition uses that exact name in the lobby.
10. Type only spaces ("    "), tap Create. Confirm the new competition uses the auto-name (not all spaces) in the lobby.

- [ ] **Step 5: Commit**

```bash
cd /Users/david/dev/Mile-A-Day/.claude/worktrees/competition-rename-on-create
git add "app/Mile A Day/Views/Competitions/CreateCompetitionView.swift"
git commit -m "Add competition name input field to create flow"
```

---

## Task 4: Add backend `validateCompetitionName` helper

**Files:**
- Modify: `backend/src/services/competitionService.ts` (after the existing top-level constants around lines 8-12, before the first exported function)

- [ ] **Step 1: Add the constant and helper**

Find this block near the top of `backend/src/services/competitionService.ts` (currently lines 8-12):

```typescript
const WORKOUT_TYPE_MAP: Record<string, string> = { run: 'running', walk: 'walking', running: 'running', walking: 'walking' };

const db = PostgresService.getInstance();

const ET_DATE_FORMATTER = new Intl.DateTimeFormat('en-CA', { timeZone: 'America/New_York' });
```

Add the following AFTER the `ET_DATE_FORMATTER` line (before any function definitions):

```typescript
/**
 * Maximum length, in characters, of a user-supplied competition name.
 * Keep in sync with CompetitionLimits.nameMaxLength in
 * app/Mile A Day/Models/CompetitionLimits.swift
 */
export const COMPETITION_NAME_MAX_LENGTH = 50;

function validateCompetitionName(name: unknown): string {
	if (typeof name !== 'string') {
		throw new BadRequestError('competition_name must be a string');
	}
	const trimmed = name.trim();
	if (trimmed.length === 0) {
		throw new BadRequestError('competition_name cannot be empty');
	}
	if (trimmed.length > COMPETITION_NAME_MAX_LENGTH) {
		throw new BadRequestError(
			`competition_name cannot exceed ${COMPETITION_NAME_MAX_LENGTH} characters`
		);
	}
	return trimmed;
}
```

- [ ] **Step 2: Type-check**

Run:

```bash
cd /Users/david/dev/Mile-A-Day/.claude/worktrees/competition-rename-on-create/backend
npm run build
```

Expected: exit code 0, no TS errors.

- [ ] **Step 3: Commit**

```bash
cd /Users/david/dev/Mile-A-Day/.claude/worktrees/competition-rename-on-create
git add backend/src/services/competitionService.ts
git commit -m "Add competition name length validator"
```

---

## Task 5: Apply validator in `createCompetition` (backend service)

**Files:**
- Modify: `backend/src/services/competitionService.ts` — `createCompetition` function (currently around lines 47-72)

- [ ] **Step 1: Validate and use the trimmed name in the INSERT**

Find this block in `createCompetition` (currently around lines 47-60):

```typescript
export async function createCompetition(params: CreateCompetitionParams) {
	checkKeys(params);

	const { competition_name, start_date, end_date, workouts = ['run', 'walk'], type, options, owner } = params;

	const [competition] = await db.query(
		`INSERT INTO competitions (
            competition_name, start_date, end_date,
            workouts, type, options, owner
        ) VALUES (
			$1, $2, $3, $4, $5, $6, $7
		) RETURNING *;`,
		[competition_name, start_date || null, end_date || null, JSON.stringify(workouts), type, JSON.stringify(options), owner]
	);
```

Replace with:

```typescript
export async function createCompetition(params: CreateCompetitionParams) {
	checkKeys(params);

	const { competition_name, start_date, end_date, workouts = ['run', 'walk'], type, options, owner } = params;
	const validatedName = validateCompetitionName(competition_name);

	const [competition] = await db.query(
		`INSERT INTO competitions (
            competition_name, start_date, end_date,
            workouts, type, options, owner
        ) VALUES (
			$1, $2, $3, $4, $5, $6, $7
		) RETURNING *;`,
		[validatedName, start_date || null, end_date || null, JSON.stringify(workouts), type, JSON.stringify(options), owner]
	);
```

- [ ] **Step 2: Type-check**

```bash
cd /Users/david/dev/Mile-A-Day/.claude/worktrees/competition-rename-on-create/backend
npm run build
```

Expected: exit code 0.

- [ ] **Step 3: Manual `curl` verification against the dev server**

Start the dev server in one terminal:

```bash
cd /Users/david/dev/Mile-A-Day/.claude/worktrees/competition-rename-on-create/backend
npm run dev
```

In another terminal, get a valid auth token (the existing dev/login flow — refer to `routes/dev*` if unsure how to mint one in this environment) and export it:

```bash
export TOKEN="<paste-jwt-here>"
export API="http://localhost:3000"   # adjust if your dev port differs
```

Run each case and confirm the expected status + body:

```bash
# Case 1: oversized (51 chars) — expect 400 with length error
curl -sS -o /tmp/r.json -w "%{http_code}\n" -X POST "$API/competitions" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d "$(jq -n --arg n "$(printf 'x%.0s' {1..51})" '{competition_name:$n,type:"apex",options:{unit:"miles",interval:"day",duration_hours:168}}')"
cat /tmp/r.json

# Case 2: empty string — expect 400 "cannot be empty"
curl -sS -o /tmp/r.json -w "%{http_code}\n" -X POST "$API/competitions" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"competition_name":"","type":"apex","options":{"unit":"miles","interval":"day","duration_hours":168}}'
cat /tmp/r.json

# Case 3: whitespace-only — expect 400 "cannot be empty"
curl -sS -o /tmp/r.json -w "%{http_code}\n" -X POST "$API/competitions" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"competition_name":"   ","type":"apex","options":{"unit":"miles","interval":"day","duration_hours":168}}'
cat /tmp/r.json

# Case 4: non-string — expect 400 "must be a string"
curl -sS -o /tmp/r.json -w "%{http_code}\n" -X POST "$API/competitions" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"competition_name":123,"type":"apex","options":{"unit":"miles","interval":"day","duration_hours":168}}'
cat /tmp/r.json

# Case 5 (regression): valid name — expect 200 with competition_id
curl -sS -o /tmp/r.json -w "%{http_code}\n" -X POST "$API/competitions" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"competition_name":"Sunday long run","type":"apex","options":{"unit":"miles","interval":"day","duration_hours":168}}'
cat /tmp/r.json
```

If your dev environment's competition-create payload requires additional `options` keys to satisfy `checkKeys`, adjust each request body accordingly — the validator runs AFTER `checkKeys`, so make sure the validator-failure cases (1–4) still get past `checkKeys` to actually hit the validator. If `checkKeys` returns 400 first, add the missing required option keys.

- [ ] **Step 4: Commit**

```bash
cd /Users/david/dev/Mile-A-Day/.claude/worktrees/competition-rename-on-create
git add backend/src/services/competitionService.ts
git commit -m "Validate competition name on create"
```

---

## Task 6: Apply validator in `updateCompetition` (backend service)

**Files:**
- Modify: `backend/src/services/competitionService.ts` — `updateCompetition` function (currently around lines 271-309)

- [ ] **Step 1: Validate when `competition_name` is provided**

Find this block in `updateCompetition` (currently around lines 271-295):

```typescript
export async function updateCompetition(params: UpdateCompetitionParams): Promise<Competition> {
	const { competitionId, options, ...updateFields } = params;

	const existingCompetition = await getCompetition(competitionId);

	if (!existingCompetition) {
		throw new BadRequestError(`Competition with id ${competitionId} not found`);
	}

	const updates: string[] = [];
	const values: any[] = [];
	let paramIndex = 1;

	for (const [key, value] of Object.entries(updateFields)) {
		if (value !== undefined) {
			if (key === 'workouts') {
				updates.push(`${key} = $${paramIndex}`);
				values.push(JSON.stringify(value));
			} else {
				updates.push(`${key} = $${paramIndex}`);
				values.push(value);
			}
			paramIndex++;
		}
	}
```

Replace with:

```typescript
export async function updateCompetition(params: UpdateCompetitionParams): Promise<Competition> {
	const { competitionId, options, ...updateFields } = params;

	const existingCompetition = await getCompetition(competitionId);

	if (!existingCompetition) {
		throw new BadRequestError(`Competition with id ${competitionId} not found`);
	}

	if (updateFields.competition_name !== undefined) {
		updateFields.competition_name = validateCompetitionName(updateFields.competition_name);
	}

	const updates: string[] = [];
	const values: any[] = [];
	let paramIndex = 1;

	for (const [key, value] of Object.entries(updateFields)) {
		if (value !== undefined) {
			if (key === 'workouts') {
				updates.push(`${key} = $${paramIndex}`);
				values.push(JSON.stringify(value));
			} else {
				updates.push(`${key} = $${paramIndex}`);
				values.push(value);
			}
			paramIndex++;
		}
	}
```

The validator returns the trimmed string, so the loop below picks up the cleaned value automatically.

- [ ] **Step 2: Type-check**

```bash
cd /Users/david/dev/Mile-A-Day/.claude/worktrees/competition-rename-on-create/backend
npm run build
```

Expected: exit code 0.

- [ ] **Step 3: Manual `curl` verification**

Reusing the dev server and `$TOKEN`, `$API`, plus a `competitionId` for a competition you own that has NOT yet started (the controller blocks updates to started competitions):

```bash
export COMP_ID="<id-of-your-test-competition>"

# Case 1: oversized name — expect 400 with length error
curl -sS -o /tmp/r.json -w "%{http_code}\n" -X PUT "$API/competitions/$COMP_ID" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d "$(jq -n --arg n "$(printf 'x%.0s' {1..51})" '{competition_name:$n}')"
cat /tmp/r.json

# Case 2: name omitted — expect 200 (validator skipped, no other fields changed)
curl -sS -o /tmp/r.json -w "%{http_code}\n" -X PUT "$API/competitions/$COMP_ID" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{}'
cat /tmp/r.json

# Case 3 (regression): valid rename — expect 200
curl -sS -o /tmp/r.json -w "%{http_code}\n" -X PUT "$API/competitions/$COMP_ID" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"competition_name":"Renamed thing"}'
cat /tmp/r.json
```

- [ ] **Step 4: Commit**

```bash
cd /Users/david/dev/Mile-A-Day/.claude/worktrees/competition-rename-on-create
git add backend/src/services/competitionService.ts
git commit -m "Validate competition name on update"
```

---

## Done

All work complete. After Task 6, hand off to `superpowers:finishing-a-development-branch` to merge / open a PR.
