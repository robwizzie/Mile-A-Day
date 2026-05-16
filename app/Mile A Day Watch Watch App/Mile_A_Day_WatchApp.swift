import SwiftUI
import HealthKit

@main
struct Mile_A_Day_Watch_Watch_AppApp: App {
    @StateObject private var healthManager = HealthKitManager.shared
    @StateObject private var userManager = UserManager.shared

    init() {
        // Activate WCSession early so the cached iOS snapshot (streak, today's
        // distance, goal) is available the moment ContentView appears, instead
        // of after a delegate round-trip.
        MADWatchBridge.shared.activate()
        MADWatchBridge.shared.hydrateFromCachedContext()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(healthManager)
                .environmentObject(userManager)
                .preferredColorScheme(.dark)
                .onAppear {
                    healthManager.requestAuthorization { authorized in
                        if !authorized {
                            print("HealthKit authorization denied on Apple Watch")
                        }
                    }
                }
        }
    }
}
