//
//  AppDelegate.swift
//  Mile A Day
//
//  Created by AI on 1/28/26.
//

import UIKit

class AppDelegate: NSObject, UIApplicationDelegate {

    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        // Force the app to stay in portrait only
        return .portrait
    }

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        print("[AppDelegate] APNs device token: \(token.prefix(8))...")
        Task {
            await MADNotificationService.shared.sendDeviceTokenToBackend(token)
        }
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("[AppDelegate] Failed to register for remote notifications: \(error.localizedDescription)")
    }
}

