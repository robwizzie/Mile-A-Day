import Foundation
import HealthKit
import UIKit

/// One line on the Health Access screen: a kind of health data and what we can
/// honestly say about our access to it.
struct HealthDataKind: Identifiable, Equatable {
    let id: String
    let title: String
    let purpose: String
    let icon: String
    /// Whether this is one of the types the app WRITES. Only write access has
    /// a status Apple will tell us (see `HealthAccessMonitor`).
    let isWritable: Bool
    /// `.sharingDenied` / `.sharingAuthorized` / `.notDetermined` for a
    /// writable type; always `.notDetermined` for a read-only one, where the
    /// value would be meaningless.
    var writeStatus: HKAuthorizationStatus

    var isBlocked: Bool { isWritable && writeStatus == .sharingDenied }
}

/// What we can determine about the app's Health permissions — and, just as
/// importantly, what we can't.
///
/// Apple deliberately hides READ authorization: a denied read returns an empty
/// result, indistinguishable from a day with no walks, and there is no API that
/// reports it. So this only ever makes a claim it can back up:
///
///  - WRITE access is reported exactly (`authorizationStatus(for:)`), and it is
///    the half that breaks loudly — Workouts denied means an in-app walk never
///    saves, Route denied means it saves with no map, in Apple Fitness and in
///    our own feed alike, with no error anywhere.
///  - "Has every type been ANSWERED at all" is reported exactly
///    (`getRequestStatusForAuthorization`). This is the case that catches an
///    app update adding a type the user granted nothing for — they granted
///    access once, months ago, and have no reason to suspect a new switch.
///  - READ access is reported as unknown, in those words, with a way into the
///    Health app to check. Guessing would be worse than saying so: "we think
///    your reads are off" on a user who simply hasn't walked yet is a scary,
///    wrong message about their private data.
enum HealthAccessState: Equatable {
    /// No HealthKit on this device (iPad, some regions). Nothing to fix.
    case unavailable
    /// At least one type has never been answered — the sheet can still be
    /// shown, so this one is fixable without leaving the app.
    case needsRequest
    /// Every type answered, but the app is blocked from writing some of them.
    case someWritesDenied
    /// Everything we can check is granted. Says nothing about reads.
    case granted

    var needsAttention: Bool {
        self == .needsRequest || self == .someWritesDenied
    }
}

/// Watches the app's Health permissions and publishes a state the UI can lead
/// with, so a half-granted install stops being silent.
///
/// The failure this exists for: HealthKit reports nothing when it's turned off.
/// A user who denied (or later revoked) access sees a streak that won't move,
/// a dashboard reading 0.00, and widgets stuck on yesterday — with no error,
/// anywhere, because from the app's side "permission denied" and "you haven't
/// walked" are the same empty array.
@MainActor
final class HealthAccessMonitor: ObservableObject {
    static let shared = HealthAccessMonitor()

    @Published private(set) var state: HealthAccessState = .granted
    @Published private(set) var kinds: [HealthDataKind] = []
    /// Set once a refresh has actually run, so nothing draws a "you're fine"
    /// (or a warning) before anything has been checked.
    @Published private(set) var hasChecked = false

    private let healthStore = HKHealthStore()

    private init() {}

    /// The types we ask for, in the order the screen lists them. Titles match
    /// the rows Apple's own Health app shows, so "Workouts" here is the same
    /// word the user will be looking for over there.
    private static let catalog: [(id: String, title: String, purpose: String, icon: String)] = [
        (HKObjectType.workoutType().identifier,
         "Workouts",
         "Counting your walks and runs, wherever they were recorded",
         "figure.run"),
        (HKQuantityTypeIdentifier.distanceWalkingRunning.rawValue,
         "Walking + Running Distance",
         "The miles behind your streak, goals and records",
         "ruler"),
        (HKQuantityTypeIdentifier.activeEnergyBurned.rawValue,
         "Active Energy",
         "Calories on your workout cards",
         "flame"),
        (HKSeriesType.workoutRoute().identifier,
         "Route",
         "The map on a walk you tracked in the app",
         "map"),
        (HKQuantityTypeIdentifier.stepCount.rawValue,
         "Steps",
         "Your daily step count and step goal",
         "shoeprints.fill"),
    ]

    func refresh() {
        guard HKHealthStore.isHealthDataAvailable() else {
            state = .unavailable
            kinds = []
            hasChecked = true
            return
        }

        let manager = HealthKitManager.shared
        let writeTypes = manager.healthKitWriteTypes
        let writeIds = Set(writeTypes.map(\.identifier))

        // Write status is synchronous and exact.
        let resolved: [HealthDataKind] = Self.catalog.map { entry in
            let writable = writeIds.contains(entry.id)
            var status = HKAuthorizationStatus.notDetermined
            if writable, let type = writeTypes.first(where: { $0.identifier == entry.id }) {
                status = healthStore.authorizationStatus(for: type)
            }
            return HealthDataKind(
                id: entry.id,
                title: entry.title,
                purpose: entry.purpose,
                icon: entry.icon,
                isWritable: writable,
                writeStatus: status
            )
        }
        kinds = resolved

        // ...whether everything has been ASKED is not, so the state settles a
        // beat later. Denials are decided first so a definite problem is never
        // downgraded to "we're still checking".
        let anyDenied = resolved.contains { $0.isBlocked }
        healthStore.getRequestStatusForAuthorization(
            toShare: writeTypes,
            read: manager.healthKitReadTypes
        ) { [weak self] requestStatus, _ in
            Task { @MainActor in
                guard let self else { return }
                if anyDenied {
                    self.state = .someWritesDenied
                } else if requestStatus == .shouldRequest {
                    self.state = .needsRequest
                } else {
                    self.state = .granted
                }
                self.hasChecked = true
            }
        }
    }

    /// Re-show Apple's permission sheet. It only appears for types that have
    /// never been answered — a type the user explicitly turned OFF can only be
    /// changed in the Health app, which is why the screen offers both doors and
    /// says which is which.
    func requestMissingPermissions(completion: (() -> Void)? = nil) {
        HealthKitManager.shared.requestAuthorization { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
                completion?()
            }
        }
    }

    /// The blocked types, for the message.
    var blockedTitles: [String] { kinds.filter(\.isBlocked).map(\.title) }
}

/// Getting the user to the right page of the Health app.
enum HealthAppLink {
    /// Health ▸ Sharing ▸ Apps, which is one tap from this app's own page.
    ///
    /// There is no public deep link to a specific app's Health permissions —
    /// Apple has never shipped one, and the request has sat unanswered on the
    /// developer forums since 2018. `Sources/` is the closest the system gets,
    /// and it degrades safely: an unrecognised path opens Health on Summary,
    /// which is exactly where the plain `x-apple-health://` used to dump people
    /// with no idea where to go next. So this is strictly better and never
    /// worse. Its scheme belongs to Apple's own Health app, so unlike a guessed
    /// third-party scheme there is no other app that can claim it.
    ///
    /// `canOpenURL` is not consulted deliberately: it needs the scheme declared
    /// in `LSApplicationQueriesSchemes`, which lives in an Info.plist generated
    /// from the Xcode project file, and it would answer false regardless.
    /// `open`'s completion handler tells us what actually happened instead.
    static func openHealthSources() {
        guard let sources = URL(string: "x-apple-health://Sources/"),
              let root = URL(string: "x-apple-health://") else { return }
        UIApplication.shared.open(sources, options: [:]) { opened in
            if !opened { UIApplication.shared.open(root) }
        }
    }

    /// The app's own page in Settings. Not where Health permissions live (those
    /// are only in the Health app) — this is for Notifications, Location and
    /// Motion, which do appear there.
    static func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
