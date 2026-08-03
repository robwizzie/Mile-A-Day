//
//  Mile_A_DayApp.swift
//  Mile A Day
//
//  Created by Robert Wiscount on 6/7/25.
//

import SwiftUI
import UIKit

@main
struct Mile_A_DayApp: App {
    
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
                .task {
                    await verifyAppleCredentialIfNeeded()
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
                    // Schedule background refresh when app enters background
                    MADBackgroundService.shared.appDidEnterBackground()
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                    // Handle app returning to foreground
                    MADBackgroundService.shared.appWillEnterForeground()
                    // Re-check Apple Sign In credential — if the user revoked
                    // access while the app was backgrounded, sign them out.
                    Task { await verifyAppleCredentialIfNeeded() }
                    // Register for push notifications (handles first-time + token rotation)
                    if AppStateManager.shared.isAuthenticated {
                        Task {
                            // Proactively refresh the access token if it's within
                            // 1 day of expiry. This avoids first-request races on
                            // cold start (where the token check passes but the
                            // server has the token marked stale).
                            await refreshTokenIfNeededOnForeground()
                            await MADNotificationService.shared.requestAuthorization()
                            MADNotificationService.shared.registerForRemoteNotifications()
                            await MADNotificationService.shared.syncDailyReminderPrefsToBackend()
                            await DailyStepsSyncService.shared.syncNow(force: true)
                            // Streak-tokens enrollment stamp (idempotent; covers
                            // users who authed on an older build).
                            StreakFeatureService.enrollIfNeeded()
                        }
                    }
                }
                .onOpenURL { url in
                    // Shared post links (mileaday.run/p/<id> and its in-app
                    // scheme). Parked, not presented here, for the same reason
                    // as profile links: on a cold launch nothing that can show
                    // a post is mounted yet. MainTabView presents it.
                    if PostDeepLink.shared.handle(url) { return }

                    // In-app profile links (mileaday://u/<username>) park their
                    // username on DeepLinkRouter so the Friends tab can resolve
                    // it whenever it's ready — covers cold launches where the
                    // tab UI doesn't exist yet.
                    // Buddy Walk invite links (mileaday://b/<CODE>, or the web
                    // form). Parked like the others — a cold launch has no
                    // Dashboard yet, and the Dashboard drains this in both
                    // .task and .onReceive.
                    if DeepLinkRouter.shared.handleBuddyLink(url) {
                        NotificationCenter.default.post(
                            name: NSNotification.Name("MAD_SwitchTab"),
                            object: nil,
                            userInfo: ["tab": 0]
                        )
                        return
                    }

                    if DeepLinkRouter.shared.handleProfileLink(url) {
                        NotificationCenter.default.post(
                            name: NSNotification.Name("MAD_SwitchTab"),
                            object: nil,
                            userInfo: ["tab": 3]
                        )
                        return
                    }

                    // Handle deep links from Live Activities / widgets
                    guard url.scheme == "mileaday" else { return }
                    switch url.host {
                    case "dashboard":
                        // mileaday://dashboard — passive widget tap
                        NotificationCenter.default.post(
                            name: NSNotification.Name("MAD_SwitchTab"),
                            object: nil,
                            userInfo: ["tab": 0]
                        )
                    case "workout":
                        // Covers mileaday://workout (Live Activity tap) and
                        // mileaday://workout/start (widget Start Mile button)
                        NotificationCenter.default.post(
                            name: NSNotification.Name("MAD_OpenWorkoutFromLiveActivity"),
                            object: nil
                        )
                    case "buddy":
                        // mileaday://buddy/<CODE> — a shared join code. Switch to
                        // the dashboard first, since that's where the buddy flow
                        // is hosted, then hand the code over.
                        let code = url.pathComponents
                            .first { $0 != "/" }?
                            .uppercased()
                        NotificationCenter.default.post(
                            name: NSNotification.Name("MAD_SwitchTab"),
                            object: nil,
                            userInfo: ["tab": 0]
                        )
                        if let code, !code.isEmpty {
                            DeepLinkRouter.shared.requestOpenBuddySession(code: code)
                        }
                    case "compete":
                        NotificationCenter.default.post(
                            name: NSNotification.Name("MAD_SwitchTab"),
                            object: nil,
                            userInfo: ["tab": 1]
                        )
                    case "friends":
                        // mileaday://friends — Daily Leaderboard widget tap
                        NotificationCenter.default.post(
                            name: NSNotification.Name("MAD_SwitchTab"),
                            object: nil,
                            userInfo: ["tab": 3]
                        )
                    case "competition":
                        // mileaday://competition/<id> — land on that comp's detail
                        NotificationCenter.default.post(
                            name: NSNotification.Name("MAD_SwitchTab"),
                            object: nil,
                            userInfo: ["tab": 1]
                        )
                        let id = url.lastPathComponent
                        if !id.isEmpty, id != "competition" {
                            NotificationCenter.default.post(
                                name: NSNotification.Name("MAD_OpenCompetition"),
                                object: nil,
                                userInfo: ["competitionId": id]
                            )
                        }
                    default:
                        break
                    }
                }
        }
    }

    /// Apple requires Sign in with Apple apps to detect when the user has
    /// revoked their credential (Settings → Apple ID → Password & Security
    /// → Apps Using Apple ID → Mile A Day → Stop Using). If revoked, sign
    /// them out so they're returned to the auth screen on next launch.
    private func verifyAppleCredentialIfNeeded() async {
        guard AppStateManager.shared.isAuthenticated else { return }

        // Catch a wrong-account session before any request goes out. Note this
        // is NOT redundant with the credential check below: two people sharing
        // one Apple account both report `.authorized` for the same Apple id, so
        // `getCredentialState` can never tell their sessions apart — only the
        // token's `sub` can.
        if await MainActor.run(body: { SessionIdentity.enforce() }) { return }

        guard let appleId = UserManager.shared.currentUser.appleId,
              !appleId.isEmpty
        else { return }

        let isValid = await AppleSignInManager.isCredentialValid(forUserID: appleId)
        if !isValid {
            await MainActor.run {
                AppStateManager.shared.signOut()
            }
        }
    }
}

/// On foreground, refresh the access token if it's within 1 day of expiry.
/// 30-day access tokens mean this rarely fires, but it ensures the first
/// post-foreground API call doesn't race a stale token against the server.
@MainActor
private func refreshTokenIfNeededOnForeground() async {
    guard let access = TokenStore.accessToken else { return }
    // 86_400s = 1 day buffer — refresh if expiring within this window.
    guard TokenUtils.isTokenExpired(access, bufferSeconds: 86_400) else { return }
    guard let refresh = TokenStore.refreshToken else { return }
    do {
        let (newAccess, newRefresh) = try await TokenRefreshService.refreshAccessToken(refreshToken: refresh)
        UserManager.shared.setTokens(accessToken: newAccess, refreshToken: newRefresh)
        MADWatchBridge.shared.pushSnapshotIfReady()
        print("[Mile_A_DayApp] ✅ Foreground token refresh succeeded")
    } catch {
        print("[Mile_A_DayApp] ⚠️ Foreground token refresh failed: \(error). Will rely on next request to retry/sign out.")
    }
}
