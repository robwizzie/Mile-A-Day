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
        
        // Initialize live workout monitoring for real-time updates
        Task { @MainActor in
            LiveWorkoutManager.shared.startLiveWorkoutMonitoring()
        }
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
