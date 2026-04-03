//
//  Mile_A_DayApp.swift
//  Mile A Day
//
//  Created by Robert Wiscount on 6/7/25.
//

import SwiftUI
import UIKit
import BackgroundTasks

@main
struct Mile_A_DayApp: App {
    
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    init() {
        // Register background tasks when app launches
        MADBackgroundService.shared.registerBackgroundTasks()
    }
    
    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
                    // Schedule background refresh when app enters background
                    MADBackgroundService.shared.appDidEnterBackground()
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                    // Handle app returning to foreground
                    MADBackgroundService.shared.appWillEnterForeground()
                    // Register for push notifications (handles first-time + token rotation)
                    if AppStateManager.shared.isAuthenticated {
                        Task {
                            await MADNotificationService.shared.requestAuthorization()
                            MADNotificationService.shared.registerForRemoteNotifications()
                        }
                    }
                }
                .onOpenURL { url in
                    // Handle deep links from Live Activities / widgets
                    if url.scheme == "mileaday", url.host == "workout" {
                        NotificationCenter.default.post(
                            name: NSNotification.Name("MAD_OpenWorkoutFromLiveActivity"),
                            object: nil
                        )
                    }
                }
        }
    }
}
