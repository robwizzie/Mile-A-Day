import Foundation
import HealthKit
import SwiftUI
import UIKit

/// One app that is actually writing running/walking workouts into Apple Health.
struct DetectedFitnessSource: Identifiable, Hashable {
    /// HealthKit's bundle identifier for the writing app.
    let id: String
    /// The name HealthKit reports ("Strava", "Garmin Connect", "Apple Watch").
    /// Always shown as-is, so an app missing from our catalog still reads right.
    let displayName: String
    let platform: FitnessSourcePlatform?
    let isApple: Bool
    let workoutCount: Int
    let totalMiles: Double
    let lastWorkoutDate: Date

    var symbol: String { platform?.symbol ?? (isApple ? "applelogo" : "app.badge") }
    var tint: Color { platform?.tint ?? MADTheme.Colors.madRed }
}

/// Discovers which apps are feeding Apple Health, so the Connections screen can
/// show what's already working instead of asking the user to guess.
///
/// Nothing here connects anything: the connection is the partner app's own
/// "write to Apple Health" toggle. This just reads what HealthKit already has,
/// which is why it needs **no new permission** — workout read access is granted
/// at onboarding and this uses exactly that.
@Observable
final class FitnessSourceService {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        /// A FAILED query is not "nothing is connected" — see `refresh()`.
        case failed(String)
    }

    private(set) var state: LoadState = .idle
    private(set) var sources: [DetectedFitnessSource] = []

    /// How far back to look. Long enough that a lapsed-but-connected app still
    /// shows up, short enough that the query stays cheap.
    private static let lookbackDays = 90

    private let healthStore = HealthKitManager.shared.healthStore

    /// Detected sources that map to a known platform, plus unknown third-party
    /// ones. Apple's own sources are separated out — there's nothing to connect.
    var thirdPartySources: [DetectedFitnessSource] { sources.filter { !$0.isApple } }
    var appleSources: [DetectedFitnessSource] { sources.filter { $0.isApple } }

    /// Catalog entries with nothing writing to Health yet — the "connect these"
    /// list. Anything already detected drops out.
    var availablePlatforms: [FitnessSourcePlatform] {
        let connected = Set(sources.compactMap { $0.platform?.id })
        return FitnessSourceCatalog.all.filter { !connected.contains($0.id) }
    }

    @MainActor
    func refresh() async {
        if case .loading = state { return }
        state = .loading

        do {
            let detected = try await queryWorkoutSources()
            sources = detected
            state = .loaded
        } catch {
            // Critical: HealthKit queries ERROR when the device is locked
            // (protected data), and an error is not a measurement. Rendering
            // "nothing connected" here would tell a user with Strava wired up
            // that their setup is broken. Keep whatever we last knew and say so.
            state = .failed(error.localizedDescription)
        }
    }

    private func queryWorkoutSources() async throws -> [DetectedFitnessSource] {
        let runningPredicate = HKQuery.predicateForWorkouts(with: .running)
        let walkingPredicate = HKQuery.predicateForWorkouts(with: .walking)
        let typePredicate = NSCompoundPredicate(
            orPredicateWithSubpredicates: [runningPredicate, walkingPredicate])

        let start = Calendar.current.date(
            byAdding: .day, value: -Self.lookbackDays, to: Date()) ?? Date()
        let datePredicate = HKQuery.predicateForSamples(
            withStart: start, end: nil, options: .strictEndDate)
        let predicate = NSCompoundPredicate(
            andPredicateWithSubpredicates: [typePredicate, datePredicate])

        let workouts: [HKWorkout] = try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: (samples as? [HKWorkout]) ?? [])
            }
            healthStore.execute(query)
        }

        return Self.group(workouts)
    }

    /// Group by writing app. Split out for testability and because the grouping
    /// key — bundle id — is the same key the backend dedupes on.
    static func group(_ workouts: [HKWorkout]) -> [DetectedFitnessSource] {
        var byBundle: [String: (name: String, count: Int, miles: Double, last: Date)] = [:]

        for workout in workouts {
            let source = workout.sourceRevision.source
            let bundle = source.bundleIdentifier
            let miles = workout.totalDistance?.doubleValue(for: HKUnit.mile()) ?? 0

            if var existing = byBundle[bundle] {
                existing.count += 1
                existing.miles += miles
                existing.last = max(existing.last, workout.endDate)
                byBundle[bundle] = existing
            } else {
                byBundle[bundle] = (source.name, 1, miles, workout.endDate)
            }
        }

        return byBundle.map { bundle, agg in
            DetectedFitnessSource(
                id: bundle,
                displayName: agg.name,
                platform: FitnessSourceCatalog.match(
                    bundleIdentifier: bundle, sourceName: agg.name),
                isApple: FitnessSourceCatalog.isAppleSource(bundleIdentifier: bundle),
                workoutCount: agg.count,
                totalMiles: agg.miles,
                lastWorkoutDate: agg.last
            )
        }
        .sorted { $0.lastWorkoutDate > $1.lastWorkoutDate }
    }
}

/// Opens a partner app so the user can flip its Apple Health toggle.
enum FitnessSourceLauncher {
    /// Try the app's own URL scheme, fall back to the App Store.
    ///
    /// Deliberately uses `open(_:options:completionHandler:)` and NEVER
    /// `canOpenURL`. `canOpenURL` requires every scheme to be declared in
    /// `LSApplicationQueriesSchemes`, and this target's Info.plist is generated
    /// from the Xcode project file, which is off-limits. `open` needs no
    /// declaration and reports failure in its handler — so a scheme that is
    /// wrong, missing, or changed by the vendor costs nothing: it just falls
    /// through to the store. No single point of failure.
    static func open(_ platform: FitnessSourcePlatform) {
        guard let scheme = platform.urlScheme, let url = URL(string: scheme) else {
            openAppStore(for: platform)
            return
        }
        UIApplication.shared.open(url, options: [:]) { opened in
            if !opened { openAppStore(for: platform) }
        }
    }

    /// A SEARCH url rather than a hardcoded App Store id: ids differ by
    /// storefront and get retired when a vendor re-publishes (Fitbit → Google
    /// Health did exactly that), and a wrong id sends someone to the wrong app.
    /// A search term stays correct everywhere.
    private static func openAppStore(for platform: FitnessSourcePlatform) {
        let term =
            platform.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
            ?? platform.name
        guard let url = URL(string: "https://apps.apple.com/search?term=\(term)") else { return }
        UIApplication.shared.open(url)
    }

    /// The Apple Health app, where every one of these connections ultimately
    /// lands. Matches the existing "Health Data" row in settings.
    static func openAppleHealth() {
        guard let url = URL(string: "x-apple-health://") else { return }
        UIApplication.shared.open(url)
    }
}
