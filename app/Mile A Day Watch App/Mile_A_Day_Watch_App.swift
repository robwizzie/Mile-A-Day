import SwiftUI
import HealthKit

@main
struct Mile_A_Day_Watch_App: App {
    @StateObject private var healthManager = HealthKitManager.shared
    @StateObject private var userManager = UserManager.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(healthManager)
                .environmentObject(userManager)
                .onAppear {
                    // Request HealthKit authorization on app launch
                    healthManager.requestAuthorization { authorized in
                        if authorized {
                            print("HealthKit authorized on Apple Watch")
                        } else {
                            print("HealthKit authorization denied on Apple Watch")
                        }
                    }
                }
        }
    }
}
