import SwiftUI
import HealthKit

@main
struct Mile_A_Day_Watch_Watch_AppApp: App {
    @StateObject private var healthManager = HealthKitManager.shared
    @StateObject private var userManager = UserManager.shared

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
