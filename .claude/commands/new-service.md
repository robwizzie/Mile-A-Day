Create a new iOS service class that communicates with the backend API.

Follow the existing service pattern exactly:
- Make it `@MainActor class` conforming to `ObservableObject`
- Add `@Published var isLoading = false` and `@Published var errorMessage: String?`
- Use `APIClient.fancyFetch()` for all network requests — it handles token refresh automatically
- Create a service-specific error enum (e.g., `MyServiceError: LocalizedError`) that maps from `APIError`
- Use `async throws` functions — no Combine, no completion handlers
- Place in `app/Mile A Day/Services/`
- Reference `WorkoutService.swift` or `FriendService.swift` for the exact pattern

Service description: $ARGUMENTS
