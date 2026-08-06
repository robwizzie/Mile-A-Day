import SwiftUI

/// Where a workout came from, and whether it's counting — in one place.
///
/// A user's mile total is assembled from whatever wrote into Apple Health, which
/// on a phone with Google Health or Strava connected can be several apps at
/// once. Two things follow, and the app got both wrong:
///
///  1. **Nothing said where a workout came from.** Every row looked identical
///     whether Mile A Day recorded it, a watch did, or a third-party app wrote
///     it from somewhere else entirely.
///  2. **Duplicate exclusion was silent.** The same walk recorded by two apps
///     is genuinely one walk, and counting it twice is wrong — but taking a
///     workout out of someone's total without telling them is worse than the
///     bad number. It's their record of something they actually did.
///
/// So attribution is shown, and exclusion is *stated* with a one-tap way to
/// overrule it. Mile A Day's own workouts and Apple's are deliberately quiet:
/// those are the expected, first-party sources, and badging them would turn a
/// useful signal into wallpaper. Anything else is named.
struct WorkoutAttribution: Equatable {
    let bundleId: String?
    /// True when this is a walk Mile A Day or Apple itself recorded — the
    /// sources a user already expects to be there.
    var isFirstParty: Bool {
        guard let bundleId, !bundleId.isEmpty else { return true }
        let lower = bundleId.lowercased()
        return lower.contains("mileaday") || lower.contains("mile-a-day")
            || FitnessSourceCatalog.isAppleSource(bundleIdentifier: bundleId)
    }

    /// "Google Health", "Strava"… or nil when there's nothing worth saying.
    var displayName: String? {
        guard let bundleId, !bundleId.isEmpty, !isFirstParty else { return nil }
        if let platform = FitnessSourceCatalog.match(
            bundleIdentifier: bundleId, sourceName: ""
        ) {
            return platform.name
        }
        // An app we don't have a catalog entry for still gets named rather than
        // shown as a raw reverse-DNS string: "com.acme.runner" → "Runner".
        let leaf = bundleId.split(separator: ".").last.map(String.init) ?? bundleId
        return leaf.prefix(1).uppercased() + leaf.dropFirst()
    }

    var symbol: String {
        guard let bundleId, !isFirstParty,
            let platform = FitnessSourceCatalog.match(
                bundleIdentifier: bundleId, sourceName: "")
        else { return "app.badge" }
        return platform.symbol
    }

    var tint: Color {
        guard let bundleId, !isFirstParty,
            let platform = FitnessSourceCatalog.match(
                bundleIdentifier: bundleId, sourceName: "")
        else { return MADTheme.Colors.madWhite.opacity(0.6) }
        return platform.tint
    }
}

/// A small "from Strava" chip. Renders nothing for first-party sources.
struct WorkoutSourceChip: View {
    let attribution: WorkoutAttribution

    var body: some View {
        if let name = attribution.displayName {
            HStack(spacing: 4) {
                Image(systemName: attribution.symbol)
                    .font(.system(size: 9, weight: .bold))
                Text(name)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .lineLimit(1)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(attribution.tint.opacity(0.18)))
            .foregroundStyle(attribution.tint)
            .fixedSize()
        }
    }
}

/// "Not counted — same walk as your Mile A Day walk", with the way out.
///
/// The whole point is that this is never a surprise. It states what happened,
/// why, and offers the reversal in the same breath — and the reversal is
/// durable, because the server stores the answer on the workout and both the
/// release and exclude passes read it. A later sync cannot quietly undo it.
struct DuplicateNoticeView: View {
    let attribution: WorkoutAttribution
    /// Nil while no request is in flight.
    var isBusy: Bool = false
    let onCountAnyway: () -> Void

    private var sourceLabel: String {
        attribution.displayName ?? "another app"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(MADTheme.Colors.warning)
                Text("Not counted toward your miles")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(MADTheme.Colors.madWhite)
                Spacer(minLength: 0)
            }

            Text(
                "\(sourceLabel) recorded this at the same time as another walk, "
                    + "so it looks like the same one written twice. We're counting it once."
            )
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(MADTheme.Colors.madWhite.opacity(0.65))
            .fixedSize(horizontal: false, vertical: true)

            Button(action: onCountAnyway) {
                Group {
                    if isBusy {
                        ProgressView().tint(MADTheme.Colors.madWhite)
                    } else {
                        Text("This was a separate walk — count it")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 34)
                .background(Capsule().fill(MADTheme.Colors.madWhite.opacity(0.14)))
                .foregroundStyle(MADTheme.Colors.madWhite)
            }
            .buttonStyle(.plain)
            .disabled(isBusy)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium, style: .continuous)
                .fill(MADTheme.Colors.warning.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium, style: .continuous)
                .strokeBorder(MADTheme.Colors.warning.opacity(0.35), lineWidth: 1)
        )
    }
}

/// Client for the per-workout duplicate decision.
enum DuplicateDecisionService {
    /// `decision` is "count", "exclude", or nil to hand it back to detection.
    static func set(userId: String, workoutId: String, decision: String?) async throws {
        struct Body: Encodable { let decision: String? }
        struct Response: Decodable { let ok: Bool }
        let body = try JSONEncoder().encode(Body(decision: decision))
        _ = try await APIClient.fancyFetch(
            endpoint: "/workouts/\(userId)/duplicates/\(workoutId)",
            method: .POST,
            body: body,
            responseType: Response.self
        )
    }
}
