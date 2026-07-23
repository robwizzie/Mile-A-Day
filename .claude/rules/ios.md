---
globs: app/**
---

# iOS App Conventions

## Architecture
- MVVM with SwiftUI
- `Views/` - SwiftUI views, organized by feature in subdirectories
- `Models/` - Data models, managers (UserManager, HealthKitManager, etc.)
- `Services/` - API service layer (network calls to backend)
- `Core/State/` - App-level state management (AppStateManager)
- `Core/Theme/` - `MADTheme` for colors and styling constants
- `Widgets/` - WidgetKit widgets (streak count, today progress)

## API Client
- All network calls go through `APIClient.fancyFetch()` - handles token refresh automatically.
- Base URL hardcoded to `https://mad.mindgoblin.tech` in `APIClient.swift`.
- Tokens stored in UserDefaults, managed by TokenRefreshService.

## HealthKit
- `HealthKitManager` is split across multiple files via extensions:
  - `HealthKitManager.swift` (core)
  - `+DataFetching.swift`, `+PersonalRecords.swift`, `+StreakCalculation.swift`, `+WorkoutIndex.swift`
- Workout sync: HealthKit -> WorkoutProcessor -> WorkoutSyncService -> Backend API
- HealthKit queries ERROR when the device is locked (protected data). Never treat a query error as "0 miles" — only a successful empty result is a real zero. Writing 0 on error randomly reset widgets.
- Feed route maps are read from HKWorkoutRoute at sync time. In-app tracked workouts must write their GPS trace via `HKWorkoutRouteBuilder.finishRoute` after `finishWorkout` (and `HKSeriesType.workoutRoute()` must be in the SHARE auth set) — points buffered in InProgressWorkoutStore alone never reach the backend.
- WidgetKit renders statically: `.onAppear`-driven `@State` animations never play in widget views — render entry values directly. `WidgetDataStore` data is day-stamped; `load()` returns zeros for a stale day, and saves skip no-op writes (widget reloads are budgeted per day).
- Widget timeline policies are fallbacks (the app reloads on every data write). Never request sub-15-min refreshes: a 60s policy drained the ~40-70/day budget by morning and iOS then silently dropped ALL reloads — widgets froze on stale data while the app was correct.
- Background HealthKit reads must gate on `hasLoadedInitialData`, not a fixed sleep — on a locked device queries error, `retroactiveStreak` reads 0, and `updateFromHealthKit` persists it unconditionally (streak 0 stuck in widgets).
- WorkoutIndex incremental updates need the 48h lookback + record-id dedup: querying strictly from `lastUpdated` permanently drops workouts that reached HealthKit late (Watch sync), leaving a `qualifyingDays` hole — `activeStreak()` stops there and the dashboard flashes a tiny streak until the backend rescue lands. Backend-streak ≫ local triggers a debounced rebuild (`repairWorkoutIndexIfStale`).
- The displayed streak (`currentUser.streak`) is quarantine-gated: `UserManager.vettedHealthKitStreak` refuses 2+ day drops from local recomputes unless the backend (48h-fresh, recomputed server-side every `getUserStats`) agrees or a same-day full index rebuild confirms. Never write `hk.retroactiveStreak` raw to UI/widgets/watch — it flaps on index holes; route through `updateUserWithHealthKitData` / push `max(hk, user.streak)`.

## Key Patterns
- Use `@Observable` (iOS 17+ Observation framework) for new view models.
- Feature views live in `Views/<FeatureName>/` subdirectories.
- Shared UI components in `Views/Components/`.
- Watch app is a separate target at `Mile A Day Watch App/`.
- fullScreenCover gotchas (post composer): pass tap-selected content via `.fullScreenCover(item:)` (isPresented + separate @State races to a stale nil), guard onAppear side effects with a one-shot flag (onAppear RE-FIRES when a cover dismisses — an auto-opened camera re-traps the user), and attach two covers to two different nodes or one drops.
- Celebrations: `CelebrationContainerView` hosts ONCE at MainTabView root (a Dashboard-hosted overlay played invisibly whenever another tab was selected) and one-shot flags (goal-shown-today, per-workout photo prompt) stamp at DISMISSAL (`markConsumed`), never on display. `hasFreshTodaysDistance` must flip in the SAME main.async block that publishes todaysDistance/todaysWorkouts — a separate earlier dispatch let celebration checks read stale values and eat the flame/photo prompt/fresh window.
- iOS 26 auto-wraps custom `ToolbarItem` views in a shared glass capsule. For a custom-styled pill, apply `.sharedBackgroundVisibility(.hidden)` to the `ToolbarItem` itself (it's on `CustomizableToolbarContent`, NOT a `View` modifier; gate with `#available(iOS 26)`) or it renders pill-inside-a-pill. Also `.fixedSize()` toolbar HStacks — leading items truncate `Text` to zero width otherwise.

## Entitlements
- Adding a capability by hand-editing a `.entitlements` file (e.g. `com.apple.developer.associated-domains`) WITHOUT enabling it in Signing & Capabilities / on the App ID makes the app build + install but get killed by AMFI at launch: `Thread 1: abort with payload or reason` (`__abort_with_payload`, generic reason). The build succeeding is not proof the entitlement is provisioned — the kill is at launch, not build.

## Do NOT
- Modify the Xcode project file (`project.pbxproj`) - it's excluded via .claudeignore.
- Change the API base URL without coordinating both client and server.
- Worry about pbxproj when CREATING .swift files in the MAIN app (incl. `Widgets/`, `Shared/`) — synchronized folders pick up files on disk automatically. EXCEPTION: the Watch target ("Mile A Day Watch Watch App/") is NOT synchronized (its files were pbxproj-registered) — modify existing watch files only, never create new ones from CLI.

## App Store Review Compliance
Every change must pass App Review. Check BEFORE proposing and AFTER implementing. Flag any borderline item explicitly.

- **Private APIs / SPI**: no underscored AppKit/UIKit selectors, no `dlopen` of system frameworks, no swizzling Apple classes. (Guideline 2.5.1)
- **Permissions & purpose strings**: any new HealthKit/Location/Notifications/Contacts/Camera/Photos use needs a clear `NSUsageDescription` in Info.plist explaining *why*. Don't request data you don't use. (5.1.1)
- **HealthKit specifics**: don't store HK data in iCloud, don't use HK data for advertising, request only the read/share types actually used. (5.1.3)
- **Background modes & BGTask**: only declare modes the feature actually needs. No keeping the app alive for tracking.
- **Account/data deletion**: if we add account creation, in-app deletion must exist (5.1.1(v)).
- **Sign in with Apple**: required as an option if we add any third-party social login (4.8).
- **Payments**: any digital goods/subscriptions = StoreKit/IAP only. No external payment links for in-app digital content. Physical goods/services = Apple Pay or other. (3.1.1, 3.1.3)
- **Push notifications**: not for ads/marketing without explicit opt-in. Friend hype/notifications must be user-controllable. (4.5.4)
- **User-generated content / social**: competitions + friend features need reporting, blocking, and a moderation/EUA path if users can send each other content. (1.2)
- **Health & safety claims**: don't claim medical/health benefits in copy or marketing without basis. "Mile a day" framing is fine; avoid medical guarantees. (1.4.1)
- **Kids / age**: app is not in Kids Category; don't add behaviors that target under-13s.
- **Web views & external links**: avoid linking out to purchase flows; in-app browsers must be SFSafariViewController or WKWebView with clear UX.
- **Entitlements**: don't add capabilities (iCloud, Game Center, Associated Domains, etc.) without a shipping feature that uses them. Don't remove entitlements an existing feature depends on.
- **Copy & metadata**: no mentions of beta/test, no placeholder text in user-visible strings, no references to other platforms.
- **Assets**: icons/screenshots must match shipped UI; no Apple trademarks or hardware mockups in icons.
- **Privacy manifest (`PrivacyInfo.xcprivacy`)**: if we add a new SDK or new data collection, update the manifest and required-reason API declarations.

When in doubt: cite the guideline number, propose the compliant path, and ask before shipping.
