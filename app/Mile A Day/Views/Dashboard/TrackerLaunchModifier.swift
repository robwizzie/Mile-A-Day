import SwiftUI
import HealthKit

/// The activity the user last STARTED a tracked workout with, so "Start my
/// mile" from Siri / the Action Button / Control Center can skip the
/// walk-or-run question. Written by the tracker at start; absent ⇒ walk.
enum TrackerLaunchPreference {
    private static let key = "lastTrackedActivityV1"

    static var lastActivity: HKWorkoutActivityType? {
        switch UserDefaults.standard.string(forKey: key) {
        case "running": return .running
        case "walking": return .walking
        default: return nil
        }
    }

    static func record(_ activity: HKWorkoutActivityType?) {
        switch activity {
        case .running: UserDefaults.standard.set("running", forKey: key)
        case .walking: UserDefaults.standard.set("walking", forKey: key)
        default: break
        }
    }
}

extension MileActivityOption {
    var workoutActivityType: HKWorkoutActivityType {
        switch self {
        case .walk: return .walking
        case .run: return .running
        }
    }
}

/// Drains `DeepLinkRouter.pendingTrackerLaunch` into the Dashboard's tracker
/// cover. One node on the dashboard's chain (its body is at the
/// type-checker's limit — see BuddyFlowModifier).
///
/// The in-progress guard is the whole point: a workout already recording is
/// REOPENED, never replaced — "am I walking" is the persisted store, never
/// `showWorkoutView`, because the tracker cover is destroyed every time the
/// user peeks at the dashboard. With nothing recording, the tracker opens on
/// its wizard with the activity step pre-answered; the wizard still asks
/// indoor/outdoor, which picks the instrument (GPS vs pedometer) and is the
/// one answer a guess can get badly wrong.
struct TrackerLaunchModifier: ViewModifier {
    @ObservedObject var router: DeepLinkRouter
    @Binding var showWorkoutView: Bool
    @Binding var preselectedActivity: HKWorkoutActivityType?

    /// A request older than this was made before a sign-in or a long launch;
    /// opening a tracker minutes later would read as the app acting on its own.
    private static let maxAge: TimeInterval = 120

    func body(content: Content) -> some View {
        content
            .onAppear { consume() }
            .onReceive(router.$pendingTrackerLaunch.compactMap { $0 }) { _ in
                consume()
            }
    }

    private func consume() {
        guard let request = router.pendingTrackerLaunch else { return }
        router.pendingTrackerLaunch = nil
        guard Date().timeIntervalSince(request.requestedAt) < Self.maxAge else { return }

        if InProgressWorkoutStore.load()?.isActive == true {
            // The tracker's own onAppear recovery restores the workout; a
            // preselection would be ignored there anyway.
            preselectedActivity = nil
            showWorkoutView = true
            return
        }

        // Already on the tracker's wizard: leave whatever step they're on.
        guard !showWorkoutView else { return }
        preselectedActivity = request.activity?.workoutActivityType
            ?? TrackerLaunchPreference.lastActivity
            ?? .walking
        showWorkoutView = true
    }
}
