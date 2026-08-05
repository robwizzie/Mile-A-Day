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

    /// "Connected" and "not connected" aren't enough states.
    ///
    /// An app that IS wired up but hasn't sent anything in weeks looks broken
    /// under a green check — the user reads "connected" and then can't find
    /// their workouts. Saying "quiet" instead tells them the connection is fine
    /// and the missing data is the thing to chase.
    var status: FitnessSourceStatus {
        let age = Date().timeIntervalSince(lastWorkoutDate)
        return age <= 30 * 24 * 60 * 60 ? .active : .quiet
    }
}

enum FitnessSourceStatus {
    case active
    case quiet

    var label: String {
        switch self {
        case .active: return "Sending"
        case .quiet: return "No recent workouts"
        }
    }

    var symbol: String {
        switch self {
        case .active: return "checkmark.circle.fill"
        // Plain clock, not one of the badged variants — those are SF Symbols 5+
        // and render as a blank box on the iOS 17 deployment target.
        case .quiet: return "clock.fill"
        }
    }

    var tint: Color {
        switch self {
        case .active: return MADTheme.Colors.success
        case .quiet: return MADTheme.Colors.warning
        }
    }
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
    /// The app's App Store product page — the ONLY destination this screen
    /// ever opens for a partner app.
    ///
    /// Two earlier versions of this were wrong in instructive ways:
    ///
    /// 1. A `?term=` SEARCH url. `apps.apple.com/search` carries no storefront
    ///    segment and doesn't resolve to the App Store app at all, so every
    ///    button that reached it was a dead end.
    /// 2. A custom URL scheme tried first as a shortcut into the installed app
    ///    (`fitbit://` and friends). Custom schemes are first-come-first-served
    ///    and unverifiable, so a wrong one does NOT fail — it opens whichever
    ///    other app registered it. Tapping Google Health opened an unrelated
    ///    fitness app. Handing someone to a stranger's software is a much worse
    ///    failure than one extra tap, and nothing inside this app can detect
    ///    it, so there is no safe way to keep a guessed scheme.
    ///
    /// An App Store id resolves to exactly one app and shows OPEN when it's
    /// already installed, so the shortcut was buying very little anyway. Do not
    /// reintroduce a scheme without a way to prove it belongs to the vendor.
    ///
    /// `itms-apps:` first, `https:` as the backstop: the itms scheme is handled
    /// by the App Store app itself, so it can't land in Safari the way an https
    /// universal link can when link handling is off. Uses
    /// `open(_:options:completionHandler:)` and never `canOpenURL`, which would
    /// need `LSApplicationQueriesSchemes` in an Info.plist generated from the
    /// off-limits project file.
    static func openAppStore(for platform: FitnessSourcePlatform) {
        let path = "apps.apple.com/app/id\(platform.appStoreId)"
        guard let storeURL = URL(string: "itms-apps://\(path)") else { return }

        UIApplication.shared.open(storeURL, options: [:]) { opened in
            guard !opened, let webURL = URL(string: "https://\(path)") else { return }
            UIApplication.shared.open(webURL)
        }
    }

    /// The Apple Health app, where every one of these connections ultimately
    /// lands. Matches the existing "Health Data" row in settings.
    static func openAppleHealth() {
        guard let url = URL(string: "x-apple-health://") else { return }
        UIApplication.shared.open(url)
    }
}
