---
name: new-view
description: Scaffold a new SwiftUI view following the MVVM pattern. Use when the user wants to create a new iOS screen or feature view.
---

# Scaffold a New SwiftUI View

Create a new iOS view following the project's MVVM architecture. Use `$ARGUMENTS` for context on what the view should do.

## Steps

### 1. Create the View

- Location: `app/Mile A Day/Views/<FeatureName>/`
- Create a subdirectory if this is a new feature
- Use SwiftUI with the project's existing patterns
- Import and use `MADTheme` for colors and styling (defined in `Core/Theme/`)
- Follow patterns from existing views in the `Views/` directory

### 2. Create the ViewModel (if needed)

- Use `@Observable` (iOS 17+ Observation framework) — NOT `ObservableObject`
- Place in the same feature directory as the view
- Handle API calls through `APIClient.fancyFetch()` for network requests
- Keep business logic in the ViewModel, views should be declarative

### 3. Wire Up Navigation

- If this view needs to be reachable from an existing screen, update the parent view's navigation
- Use `NavigationLink` or sheet/fullScreenCover as appropriate

## Key Patterns

- `@Observable` class for ViewModels (not `ObservableObject` + `@Published`)
- `APIClient.fancyFetch()` for all network calls (handles token refresh)
- `MADTheme` for consistent colors/styling
- Shared components live in `Views/Components/`
- Feature views live in `Views/<FeatureName>/` subdirectories

## Do NOT

- Modify `project.pbxproj` — it's excluded via .claudeignore. New files must be added to Xcode manually.
- Change the API base URL in `APIClient.swift`
- Tell the user to add files to Xcode — just mention that new files need to be added to the Xcode project
