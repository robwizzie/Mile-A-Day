# Competition Name on Create — Design

**Date:** 2026-05-14
**Status:** Approved
**Scope:** iOS create-competition UI + backend validation

## Problem

`CreateCompetitionView` already has a `competitionName` state field and `createCompetition()` already falls back to an auto-generated name when blank, but there is no UI input control for the user to set a custom name. The backend accepts `competition_name` on both create and update without any length or content validation, so any string that passes through the iOS client (and any third-party caller) is stored as-is and later interpolated into push-notification bodies.

## Goals

1. Let the user optionally set a custom competition name during the create flow.
2. Make the auto-generated default visible at edit time so the user knows what they'll get if they leave it blank.
3. Enforce a length cap on both client and server so notification bodies stay readable and the field cannot be abused.

## Non-Goals

- Renaming an existing/already-created competition through new UI. (The backend `updateCompetition` endpoint already accepts `competition_name`; we add validation to it defensively, but no new client surface for editing post-create is added.)
- Backfilling or truncating existing competitions whose names exceed the new cap. Read paths are unaffected.
- Sharing the limit constant between iOS and backend via codegen or a shared package — there is no shared package today and adding one is out of scope. The two constants are kept in sync via cross-referenced code comments.
- Localizing the auto-name template (it stays English).

## The Limit: 50 Characters

The competition name appears verbatim in push-notification body templates such as:

- `"$accepterName joined $name"`
- `"$senderName in $name: \"$message\""`
- `"$name has begun!"` / `"$name has finished!"`

APNS soft-truncates lock-screen notification bodies near ~178 characters. With a typical display name (~15 chars) plus a verb wrapper (~15-25 chars), 50 characters of name leaves comfortable headroom and avoids mid-word truncation. It's long enough for expressive names ("Marathon training crew - April") and short enough to keep the rendered notification readable.

## iOS Changes

All changes are in `app/Mile A Day/Views/Competitions/CreateCompetitionView.swift` plus one constant added to the theme/limits file.

### 1. New constant

A name-length cap is a domain limit, not a styling/theme value, so it doesn't belong in `MADTheme`. Add a new file `app/Mile A Day/Models/CompetitionLimits.swift` colocated with `Competition.swift`:

```swift
enum CompetitionLimits {
    /// Keep in sync with COMPETITION_NAME_MAX_LENGTH in backend/src/services/competitionService.ts
    static let nameMaxLength = 50
}
```

All iOS references in the rest of this spec use `CompetitionLimits.nameMaxLength`.

### 2. Extract auto-name into a computed property

Today, `createCompetition()` builds the auto-name inline:

```swift
let friendNames = selectedFriends.prefix(2).map { $0.displayName }.joined(separator: " & ")
let autoName = "\(selectedType.displayName) with \(friendNames)"
```

Hoist this into a computed property on the view so the placeholder and submit fallback share one definition:

```swift
var autoCompetitionName: String {
    if selectedFriends.isEmpty {
        return "\(selectedType.displayName) Competition"
    }
    let friendNames = selectedFriends.prefix(2).map { $0.displayName }.joined(separator: " & ")
    return "\(selectedType.displayName) with \(friendNames)"
}
```

The empty-friends branch is new — needed because the placeholder is visible before the user picks anyone.

### 3. New `nameSection`

Placed at the top of the form, above `challengersSection` (currently the first child of the `VStack` at line 116-150).

- Section header `"Competition Name"` styled like other section headers (subheadline, `.white.opacity(0.6)`, leading-aligned, `MADTheme.Spacing.sm` horizontal padding).
- A `TextField("", text: $competitionName, prompt: Text(autoCompetitionName))` (or equivalent SwiftUI prompt API) so the placeholder reflects the live auto-name.
- Container styled with the existing glass-morphism pattern: `.ultraThinMaterial`, `RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)`, `Color.white.opacity(0.1)` stroke.
- Modifiers: `.textInputAutocapitalization(.words)`, `.submitLabel(.done)`, `.foregroundColor(.white)`.
- `.onChange(of: competitionName) { _, newValue in if newValue.count > CompetitionLimits.nameMaxLength { competitionName = String(newValue.prefix(CompetitionLimits.nameMaxLength)) } }`

No "clear" button is added — SwiftUI shows the standard one when text is non-empty.

### 4. `createCompetition()` change

Replace the inline auto-name with the new computed property and trim user input:

```swift
let trimmedName = competitionName.trimmingCharacters(in: .whitespacesAndNewlines)
let finalName = trimmedName.isEmpty ? autoCompetitionName : trimmedName
```

Pass `finalName` to `competitionService.createCompetition(name:...)`. No other behavior changes.

## Backend Changes

All changes are in `backend/src/services/competitionService.ts`. Controllers (`createComp`, `updateComp`) already catch `BadRequestError` and return HTTP 400, so they need no changes.

### 1. Constant + validator

At the top of `competitionService.ts`:

```ts
// Keep in sync with CompetitionLimits.nameMaxLength in app/Mile A Day/Models/CompetitionLimits.swift
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

### 2. Apply in `createCompetition`

At the top of the function body, replace direct use of `competition_name` with the validated/trimmed value:

```ts
const validatedName = validateCompetitionName(competition_name);
// ...use validatedName in the INSERT...
```

### 3. Apply in `updateCompetition`

`competition_name` is optional on update. Only validate when present:

```ts
const validatedName =
    competition_name !== undefined ? validateCompetitionName(competition_name) : undefined;
// ...use validatedName in the UPDATE...
```

### 4. Database

The `competitions.competition_name` column stays `TEXT`. The project has no migrations system (per CLAUDE.md gotcha #4), and the service-layer validator is the enforcement point. This is consistent with existing backend conventions.

## Error Handling

| Condition | Response |
|---|---|
| iOS: user types past 50 chars | TextField truncates silently (no error) |
| iOS: user submits empty/whitespace name | Falls back to `autoCompetitionName`, request succeeds |
| Backend: name missing entirely | Existing `hasRequiredKeys` check returns 400 (unchanged) |
| Backend: name not a string | New validator returns 400 `"competition_name must be a string"` |
| Backend: name empty after trim | New validator returns 400 `"competition_name cannot be empty"` |
| Backend: name > 50 chars after trim | New validator returns 400 `"competition_name cannot exceed 50 characters"` |

The iOS client cannot trigger the >50 case in normal flow because of the TextField truncation, but the server validates anyway because non-iOS callers exist (and may grow).

## Testing

No automated test infrastructure exists for either target (per CLAUDE.md). Manual verification:

**iOS (in Xcode):**
1. Open Create flow — confirm "Competition Name" section appears at top with empty TextField.
2. Confirm placeholder shows `"<Type> Competition"` before any friends are picked.
3. Pick a type and 1-2 friends — confirm placeholder updates to `"<Type> with <Friend>"` / `"<Type> with <A> & <B>"`.
4. Type 60 characters — confirm input stops at 50.
5. Leave field blank, submit — confirm competition is created with the auto-name (check via Lobby title).
6. Type a custom name, submit — confirm competition is created with that name.
7. Type only spaces, submit — confirm fallback to auto-name (no all-whitespace name persisted).

**Backend (curl):**
1. POST `/competitions` with `competition_name: "x".repeat(51)` → expect 400 with the length error.
2. POST with `competition_name: ""` → expect 400 with the empty error.
3. POST with `competition_name: "   "` → expect 400 with the empty error (trim then length check).
4. POST with `competition_name: 123` → expect 400 with the type error.
5. POST with valid name → expect 200 (regression).
6. PUT update endpoint with oversized name → expect 400; with name omitted → expect 200 (validator skipped).

## Files Touched

- `app/Mile A Day/Views/Competitions/CreateCompetitionView.swift` — add `nameSection`, `autoCompetitionName`, truncation `onChange`, trim in `createCompetition()`.
- `app/Mile A Day/Models/CompetitionLimits.swift` — new file with the `nameMaxLength` constant.
- `backend/src/services/competitionService.ts` — add constant, validator, call sites in `createCompetition` and `updateCompetition`.

No changes to controllers, routes, types, DB schema, or shared code.
