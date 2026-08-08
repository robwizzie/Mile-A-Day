import HealthKit
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
    ///
    /// Delegates to `WorkoutDedup` rather than testing the bundle id again
    /// here: the same predicate decides which copy of a duplicated walk
    /// SURVIVES, so a second implementation could badge a workout as
    /// third-party while the arithmetic treated it as ours.
    var isFirstParty: Bool { WorkoutDedup.isFirstParty(bundleId: bundleId) }

    /// The catalog entry behind this workout, when we recognise the writer.
    /// Carries the App Store id the chip uses to show the app's real icon.
    var platform: FitnessSourcePlatform? {
        guard let bundleId, !bundleId.isEmpty, !isFirstParty else { return nil }
        return FitnessSourceCatalog.match(bundleIdentifier: bundleId, sourceName: "")
    }

    /// "Google Health", "Strava"… or nil when there's nothing worth saying.
    var displayName: String? {
        guard let bundleId, !bundleId.isEmpty, !isFirstParty else { return nil }
        if let platform = platform {
            return platform.name
        }
        // An app we don't have a catalog entry for still gets named rather than
        // shown as a raw reverse-DNS string: "com.acme.runner" → "Runner".
        let leaf = bundleId.split(separator: ".").last.map(String.init) ?? bundleId
        return leaf.prefix(1).uppercased() + leaf.dropFirst()
    }

    var symbol: String {
        platform?.symbol ?? "app.badge"
    }

    var tint: Color {
        platform?.tint ?? MADTheme.Colors.madWhite.opacity(0.6)
    }
}

extension WorkoutAttribution {
    /// The app that wrote a workout, named the way a sentence needs it.
    ///
    /// `displayName` is deliberately nil for Mile A Day and Apple — a chip
    /// naming them would be wallpaper — but "same walk as your ___ recording"
    /// still has to fill that blank, so fall back to HealthKit's own source
    /// name ("Mile A Day", "Apple Watch", "Health").
    static func sourceLabel(for workout: HKWorkout) -> String {
        let source = workout.sourceRevision.source
        return WorkoutAttribution(bundleId: source.bundleIdentifier).displayName
            ?? source.name
    }
}

/// A small "from Strava" chip. Renders nothing for first-party sources.
struct WorkoutSourceChip: View {
    let attribution: WorkoutAttribution
    @ObservedObject private var artwork = FitnessSourceArtwork.shared

    /// The writing app's real icon, from Apple's storefront — see
    /// `FitnessSourceArtwork` for why it isn't a bundled asset.
    private var iconURL: URL? {
        guard let platform = attribution.platform else { return nil }
        return artwork.url(forAppStoreId: platform.appStoreId)
    }

    var body: some View {
        if let name = attribution.displayName {
            HStack(spacing: 4) {
                // The symbol holds the slot at the same size, so artwork
                // arriving later swaps in place instead of reflowing the row.
                Group {
                    if let iconURL = iconURL {
                        AsyncImage(url: iconURL) { image in
                            image.resizable().scaledToFill()
                        } placeholder: {
                            Image(systemName: attribution.symbol)
                                .font(.system(size: 9, weight: .bold))
                        }
                        .frame(width: 12, height: 12)
                        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                    } else {
                        Image(systemName: attribution.symbol)
                            .font(.system(size: 9, weight: .bold))
                            .frame(width: 12, height: 12)
                    }
                }
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
