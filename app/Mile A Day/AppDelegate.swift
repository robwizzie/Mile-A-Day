//
//  AppDelegate.swift
//  Mile A Day
//
//  Created by AI on 1/28/26.
//

import UIKit
import BackgroundTasks

class AppDelegate: NSObject, UIApplicationDelegate {

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // Apple requires BGTask registration before the app finishes launching.
        MADBackgroundService.shared.registerBackgroundTasks()

        // Ensure the notification delegate is set before the system delivers
        // a pending notification response on cold launch.
        _ = MADNotificationService.shared

        // HealthKit step-count observer — start after UIApplication is ready.
        DailyStepsSyncService.shared.start()

        // MetricKit crash/hang reports. Subscribe early so a payload iOS
        // delivers on this launch isn't missed; the upload itself is deferred
        // off-main and never blocks launch.
        DiagnosticsReporter.shared.start()

        // If iOS launched us in the background (no UI scene), kick off a sync immediately.
        // For UI launches, the scene lifecycle in Mile_A_DayApp handles the sync.
        if application.applicationState == .background {
            print("[AppDelegate] Launched in background — triggering performBackgroundSync")
            Task {
                await MADBackgroundService.shared.performBackgroundSync(reason: .backgroundLaunch)
            }
        }

        // On cold launches for already-authenticated users (no auth flow runs),
        // re-register APNs too. This refreshes the backend's token environment
        // after installing a local DEBUG build, without requiring a foreground
        // cycle or fresh login.
        if UserDefaults.standard.bool(forKey: "MAD_IsAuthenticated") {
            Task {
                await MADNotificationService.shared.requestAuthorization()
                MADNotificationService.shared.registerForRemoteNotifications()
                await MADNotificationService.shared.syncDailyReminderPrefsToBackend()
            }
        }

        return true
    }

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

    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        // Only handle our silent pushes here (widget_refresh, background_sync). Other push types
        // are visible alerts and are handled by UNUserNotificationCenterDelegate.
        let aps = userInfo["aps"] as? [String: Any]
        let contentAvailable = (aps?["content-available"] as? Int) ?? 0
        let type = userInfo["type"] as? String

        // A friend moved something one of our widgets shows (competition
        // standings, today's head-to-head, the friends leaderboard). Refetch
        // that snapshot and reload only its widget kind. Hard-capped well
        // inside iOS's ~30s allowance: whichever of the refresh and the
        // deadline finishes first calls the handler, exactly once.
        if contentAvailable == 1, type == "widget_refresh" {
            let data = userInfo["data"] as? [String: Any]
            let reason = data?["reason"] as? String
            let latch = OneShotLatch()
            let work = Task { @MainActor in
                let result = await WidgetLiveRefresh.handleRefreshPush(reason: reason)
                if latch.claim() { completionHandler(result) }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + WidgetLiveRefresh.pushBudgetSeconds) {
                if latch.claim() {
                    work.cancel()
                    completionHandler(.failed)
                }
            }
            return
        }

        guard contentAvailable == 1, type == "background_sync" else {
            completionHandler(.noData)
            return
        }

        print("[AppDelegate] Received background_sync silent push")
        Task {
            let didWork = await MADBackgroundService.shared.performBackgroundSync(reason: .silentPush)
            completionHandler(didWork ? .newData : .noData)
        }
    }
}
