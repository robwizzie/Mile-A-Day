# Gotchas

Learned mistakes — things that bit us once and shouldn't bite us again. Grows via `/learn` (post-feature sweep) and `/remember "rule"` (mid-session).

Each entry: one-line rule + brief why.

<!-- Format:
## <Topic>
**Rule**: <one-line actionable rule>
**Why**: <the incident or constraint that produced this rule>
**Source**: <commit hash, PR number, or "session 2026-04-26">
-->

## SwiftUI conditional view identity in presentation closures
**Rule**: Never branch between two initializers of the same view type inside a `fullScreenCover`/`sheet` content closure — compute the differing parameters and create ONE view.
**Why**: `if/else` branches have distinct structural identity. The dashboard's workout cover branched on `InProgressWorkoutStore.load()?.isActive`; when the workout finished and the store cleared, the branch flipped, SwiftUI rebuilt `WorkoutTrackingView` with fresh `@State`, and the post-workout recap was silently replaced by the activity-selection screen.
**Source**: session 2026-06-11

When you correct Claude on something non-obvious, run `/remember "rule"` to add it. After a feature ships, run `/learn` to sweep corrections from the session into here.
