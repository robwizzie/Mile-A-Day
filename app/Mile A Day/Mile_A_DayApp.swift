//
//  Mile_A_DayApp.swift
//  Mile A Day
//
//  Created by Robert Wiscount on 6/7/25.
//

//
//  Mile_A_DayApp.swift
//  Mile A Day
//
//  Created by Robert Wiscount on 6/7/25.
//

import SwiftUI
import BackgroundTasks

@main
struct Mile_A_DayApp: App {
    
    init() {
        // Register background tasks when app launches
        MADBackgroundService.shared.registerBackgroundTasks()
        
        // Validate and repair widget data on startup
        let wasRepaired = WidgetDataStore.validateAndRepair()
        if wasRepaired {
            print("[App] 🔧 Widget data was repaired on startup")
        }
        
        print("[App] 🚀 Mile A Day app initialized")
    }
    
    var body: some Scene {
        WindowGroup {
            MainTabView()
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
                    // Schedule background refresh when app enters background
                    MADBackgroundService.shared.appDidEnterBackground()
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                    // Handle app returning to foreground
                    MADBackgroundService.shared.appWillEnterForeground()
                }
        }
    }
}
