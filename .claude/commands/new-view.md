Create a new SwiftUI view for the iOS app.

Follow these project patterns exactly:
- Use `MADTheme.Colors`, `MADTheme.Typography`, `MADTheme.Spacing`, `MADTheme.CornerRadius`, `MADTheme.Animation` — never hardcode colors, fonts, or spacing
- Receive shared managers via `@ObservedObject` (e.g., `healthManager`, `userManager`)
- Use `@StateObject` only for lightweight services created by this view
- Use `@State private var` for local UI state (sheets, loading, search text)
- Use `async/await` for any data loading — no Combine
- Place in the appropriate `Views/` subdirectory based on feature area
- Check nearby views in the same feature area and match their style

View name or description: $ARGUMENTS
