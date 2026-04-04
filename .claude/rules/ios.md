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

## Key Patterns
- Use `@Observable` (iOS 17+ Observation framework) for new view models.
- Feature views live in `Views/<FeatureName>/` subdirectories.
- Shared UI components in `Views/Components/`.
- Watch app is a separate target at `Mile A Day Watch App/`.

## Do NOT
- Modify the Xcode project file (`project.pbxproj`) - it's excluded via .claudeignore.
- Change the API base URL without coordinating both client and server.
