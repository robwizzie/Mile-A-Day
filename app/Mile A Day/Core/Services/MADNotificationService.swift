import Foundation
import UserNotifications
import UIKit

extension Notification.Name {
    static let didReceivePushNotification = Notification.Name("didReceivePushNotification")
    static let didTapPushNotification = Notification.Name("didTapPushNotification")
}

/// A singleton that centralises all notification related logic for MAD.
///
/// - Handles permission requests
/// - Schedules and updates local notifications
/// - Registers and manages remote push notifications
/// - Prevents duplicate notifications
///
/// Always access through `MADNotificationService.shared`.
final class MADNotificationService: NSObject, ObservableObject {
    // MARK: - Singleton
    static let shared = MADNotificationService()

    private let center = UNUserNotificationCenter.current()

    // Expose authorisation status to SwiftUI views
    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    
    // Stores notification type from a tap when the app was not yet fully loaded
    @Published var pendingNotificationType: String?

    // Track when we last sent a completion notification to prevent duplicates
    private var lastCompletionNotificationDate: Date?
    private let userDefaults = UserDefaults.standard
    private let lastNotificationKey = "lastCompletionNotificationDate"

    // MARK: - Init
    private override init() {
        super.init()
        center.delegate = self
        registerCategories()

        // Load last notification date
        if let lastDate = userDefaults.object(forKey: lastNotificationKey) as? Date {
            lastCompletionNotificationDate = lastDate
        }

        Task {
            await refreshAuthorizationStatus()
        }
    }

    /// Registers UNNotificationCategories for actionable pushes.
    /// FRIEND_ACTIVITY: a friend completed their mile — recipient can tap "🔥 Hype".
    /// FRIEND_REQUEST: incoming request — recipient can Accept/Decline in place.
    private func registerCategories() {
        let hypeAction = UNNotificationAction(
            identifier: "HYPE_ACTION",
            title: "🔥 Hype",
            options: []
        )
        let friendActivity = UNNotificationCategory(
            identifier: "FRIEND_ACTIVITY",
            actions: [hypeAction],
            intentIdentifiers: [],
            options: []
        )

        // Neither action is .foreground: resolving the request without opening
        // the app is the whole point. A request the user answers from the
        // banner can't get lost behind a missed notification.
        let acceptAction = UNNotificationAction(
            identifier: "FRIEND_ACCEPT_ACTION",
            title: "Accept",
            options: []
        )
        let declineAction = UNNotificationAction(
            identifier: "FRIEND_DECLINE_ACTION",
            title: "Decline",
            options: [.destructive]
        )
        let friendRequest = UNNotificationCategory(
            identifier: "FRIEND_REQUEST",
            actions: [acceptAction, declineAction],
            intentIdentifiers: [],
            options: []
        )

        // setNotificationCategories REPLACES the whole set — FRIEND_ACTIVITY
        // must stay in this array or the Hype button silently disappears.
        center.setNotificationCategories([friendActivity, friendRequest])
    }

    // MARK: - Public API

    /// Requests notification permission from the user.
    @MainActor
    func requestAuthorization() async {
        do {
            let options: UNAuthorizationOptions = [.alert, .sound, .badge]
            let granted = try await center.requestAuthorization(options: options)
            authorizationStatus = granted ? .authorized : .denied
        } catch {
            authorizationStatus = .denied
        }
    }

    /// Refreshes the cached notification authorization status.
    @MainActor
    func refreshAuthorizationStatus() async {
        let settings = await center.notificationSettings()
        authorizationStatus = settings.authorizationStatus
    }

    // MARK: - Scheduling Helpers

    /// Immediately sends a local notification celebrating mile completion.
    /// Prevents duplicate notifications for the same day.
    func sendMileCompletedNotification() {
        // Respect user preferences
        let prefs = NotificationPreferences.load()
        guard prefs.mileCompletedEnabled else { return }
        
        // Check if we already sent a notification today
        if let lastDate = lastCompletionNotificationDate,
           Calendar.current.isDate(lastDate, inSameDayAs: Date()) {
            return
        }
        
        let content = UNMutableNotificationContent()
        content.title = "Way to go!"
        content.body = "Great job completing your mile today. Keep the streak alive!"
        content.sound = .default
        
        schedule(content: content, trigger: .none, identifier: Identifier.mileCompleted)
        
        // Track that we sent a notification today
        lastCompletionNotificationDate = Date()
        userDefaults.set(lastCompletionNotificationDate, forKey: lastNotificationKey)
    }

    /// Sends a local push announcing a friend's mile completion.
    /// - Parameter friendName: The friend's display name.
    func sendFriendCompletedNotification(friendName: String) {
        // Respect user preferences
        let prefs = NotificationPreferences.load()
        guard prefs.friendCompletedEnabled else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "\(friendName) just ran a mile!"
        content.body = "Send a high-five and keep each other motivated."
        content.sound = .default
        schedule(content: content, trigger: .none, identifier: Identifier.friendCompleted(friendName))
    }

    /// Daily "Mile still waiting…" reminders are now sent by the backend as
    /// push notifications, gated on the authoritative server-side completion
    /// state (see `backend/src/services/dailyReminderService.ts`). The previous
    /// local-notification implementation baked the "still waiting" vs.
    /// "completed" text in at schedule time and couldn't be re-evaluated when
    /// the app was backgrounded — so finishing your mile on the watch (or any
    /// path that didn't wake the iPhone app before 6 PM) would still fire the
    /// stale "still waiting" notification.
    ///
    /// This stub is kept so existing call sites compile and so any legacy local
    /// reminder still pending in `UNUserNotificationCenter` from older app
    /// versions is cleared on next run. Preferences (`dailyReminderEnabled`,
    /// `dailyReminderHour`) are now synced to the backend via
    /// `syncDailyReminderPrefsToBackend()`.
    func updateDailyReminder(isCompleted: Bool, currentMiles: Double = 0, goalMiles: Double = 1.0, at hour: Int? = nil) {
        center.removePendingNotificationRequests(withIdentifiers: [Identifier.dailyReminder])
    }

    /// Pushes the user's daily-reminder preferences + current UTC offset to the
    /// backend so the server cron knows when (and whether) to fire the daily
    /// "Mile still waiting…" push.
    ///
    /// Safe to call repeatedly. No-ops if the user isn't authenticated.
    @MainActor
    func syncDailyReminderPrefsToBackend() async {
        guard UserDefaults.standard.string(forKey: "authToken") != nil else { return }

        let prefs = NotificationPreferences.load()
        let tzOffsetMinutes = TimeZone.current.secondsFromGMT() / 60

        struct DailyReminderPrefs: Codable {
            let daily_reminder_enabled: Bool
            let daily_reminder_hour: Int
            let timezone_offset_minutes: Int
        }
        let payload = DailyReminderPrefs(
            daily_reminder_enabled: prefs.dailyReminderEnabled,
            daily_reminder_hour: prefs.dailyReminderHour,
            timezone_offset_minutes: tzOffsetMinutes
        )

        do {
            let body = try JSONEncoder().encode(payload)
            let _: NotificationSettingsResponse = try await APIClient.fancyFetch(
                endpoint: "/notifications/preferences",
                method: .PUT,
                body: body,
                responseType: NotificationSettingsResponse.self
            )
        } catch {
            print("[Notifications] Failed to sync daily reminder prefs: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Smart Notification Logic
    
    /// Checks if we should send a completion notification based on current progress
    /// - Parameters:
    ///   - currentMiles: Current miles completed
    ///   - goalMiles: Daily goal in miles
    ///   - previousMiles: Previous miles count (to detect when goal was just reached)
    /// - Returns: True if notification should be sent
    func shouldSendCompletionNotification(currentMiles: Double, goalMiles: Double, previousMiles: Double) -> Bool {
        // Only send if:
        // 1. Current miles meets or exceeds goal
        // 2. Previous miles was below goal (just completed)
        // 3. Haven't sent notification today already
        
        let justCompleted = ProgressCalculator.isGoalCompleted(current: currentMiles, goal: goalMiles)
            && !ProgressCalculator.isGoalCompleted(current: previousMiles, goal: goalMiles)
        let alreadySentToday = lastCompletionNotificationDate != nil && 
                             Calendar.current.isDate(lastCompletionNotificationDate!, inSameDayAs: Date())
        
        let shouldSend = justCompleted && !alreadySentToday
        
        return shouldSend
    }
    
    /// Sends a notification when a new friend request is received.
    /// Intended to be called on the device that detects a new incoming request.
    /// - Parameter fromName: Display name of the user who sent the request.
    func sendFriendRequestReceivedNotification(fromName: String) {
        let prefs = NotificationPreferences.load()
        guard prefs.friendRequestReceivedEnabled else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "New friend request"
        content.body = "\(fromName) just sent you a friend request."
        content.sound = .default
        
        schedule(content: content, trigger: .none, identifier: Identifier.friendRequestReceived(fromName))
    }
    
    /// Sends a notification when a friendship is created (a request is accepted).
    /// This can be triggered on whichever device first sees the new friendship.
    /// - Parameter friendName: Display name of the new friend.
    func sendFriendRequestAcceptedNotification(friendName: String) {
        let prefs = NotificationPreferences.load()
        guard prefs.friendRequestAcceptedEnabled else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "You're now friends!"
        content.body = "You and \(friendName) are now friends."
        content.sound = .default
        
        schedule(content: content, trigger: .none, identifier: Identifier.friendRequestAccepted(friendName))
    }
    
    /// Resets the daily notification tracking (call at midnight or app launch)
    func resetDailyNotificationTracking() {
        if let lastDate = lastCompletionNotificationDate,
           !Calendar.current.isDate(lastDate, inSameDayAs: Date()) {
            lastCompletionNotificationDate = nil
            userDefaults.removeObject(forKey: lastNotificationKey)
        }
    }

    // MARK: - Remote Notifications

    /// The current APNs device token (hex string), kept in memory for unregister on sign-out.
    private(set) var currentDeviceToken: String?

    /// Registers with APNs for remote pushes. Call after auth + notification permission granted.
    func registerForRemoteNotifications() {
        UIApplication.shared.registerForRemoteNotifications()
    }

    /// Sends the device token to the backend. Called from AppDelegate when APNs returns a token.
    @MainActor
    func sendDeviceTokenToBackend(_ token: String) async {
        currentDeviceToken = token
        UserDefaults.standard.set(token, forKey: "apnsDeviceToken")

        guard UserDefaults.standard.string(forKey: "authToken") != nil else {
            print("[Notifications] No auth token, skipping device token registration")
            return
        }

        do {
            struct RegisterRequest: Codable {
                let device_token: String
                let environment: String
            }
            let body = try JSONEncoder().encode(RegisterRequest(
                device_token: token,
                environment: AppEnvironment.apnsEnvironment
            ))
            let _: [String: String] = try await APIClient.fancyFetch(
                endpoint: "/devices/register",
                method: .POST,
                body: body,
                responseType: [String: String].self
            )
            print("[Notifications] Device token registered with backend")
        } catch {
            print("[Notifications] Failed to register device token: \(error.localizedDescription)")
        }
    }

    /// Unregisters the device token from the backend. Call on sign-out.
    @MainActor
    func unregisterDeviceToken() async {
        let token = currentDeviceToken ?? UserDefaults.standard.string(forKey: "apnsDeviceToken")
        guard let token else { return }

        do {
            struct UnregisterRequest: Codable { let device_token: String }
            let body = try JSONEncoder().encode(UnregisterRequest(device_token: token))
            let _: [String: String] = try await APIClient.fancyFetch(
                endpoint: "/devices/unregister",
                method: .DELETE,
                body: body,
                responseType: [String: String].self
            )
            print("[Notifications] Device token unregistered from backend")
        } catch {
            print("[Notifications] Failed to unregister device token: \(error.localizedDescription)")
        }

        currentDeviceToken = nil
        UserDefaults.standard.removeObject(forKey: "apnsDeviceToken")
    }

    /// Checks if a remote notification type is enabled in user preferences.
    private func isRemoteNotificationEnabled(type: String) -> Bool {
        let prefs = NotificationPreferences.load()
        switch type {
        case "friend_request": return prefs.friendRequestReceivedEnabled
        case "friend_request_reminder": return prefs.friendRequestReminderEnabled
        case "friend_request_accepted": return prefs.friendRequestAcceptedEnabled
        case "friend_nudge": return prefs.friendNudgeEnabled
        case "friend_activity": return prefs.friendCompletedEnabled
        case "friend_post": return prefs.friendPostsEnabled
        case "competition_invite": return prefs.competitionInviteEnabled
        case "competition_accepted": return prefs.competitionAcceptedEnabled
        case "competition_started", "competition_updates": return prefs.competitionStartEnabled
        case "competition_finished": return prefs.competitionFinishEnabled
        case "competition_nudge": return prefs.competitionNudgeEnabled
        case "competition_flex": return prefs.competitionFlexEnabled
        case "competition_milestone": return prefs.competitionMilestonesEnabled
        default: return true
        }
    }

    // MARK: - Private helpers

    private func schedule(content: UNMutableNotificationContent, trigger: TriggerType, identifier: String) {
        let notificationTrigger: UNNotificationTrigger?
        switch trigger {
        case .none:
            notificationTrigger = nil
        case .calendar(let cal):
            notificationTrigger = cal
        case .timeInterval(let interval, let repeats):
            notificationTrigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: repeats)
        }

        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: notificationTrigger)

        center.add(request) { error in
            // Notification scheduling completed
        }
    }
}

// MARK: - Identifiers & Helpers
extension MADNotificationService {
    enum TriggerType {
        case none
        case calendar(UNCalendarNotificationTrigger)
        case timeInterval(TimeInterval, repeats: Bool)
    }

    struct Identifier {
        static let mileCompleted = "mileCompleted"
        static let dailyReminder = "dailyReminder"
        static func friendCompleted(_ friend: String) -> String { "friendCompleted_\(friend)" }
        static func friendRequestReceived(_ from: String) -> String { "friendRequestReceived_\(from)" }
        static func friendRequestAccepted(_ friend: String) -> String { "friendRequestAccepted_\(friend)" }
    }
}

// MARK: - UNUserNotificationCenterDelegate
extension MADNotificationService: UNUserNotificationCenterDelegate {
    @MainActor
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        // For daily reminders, do a last-second check: if the content says
        // "Mile still waiting" but the user has actually completed their goal,
        // suppress it. This catches the edge case where HealthKit data arrived
        // after the notification was scheduled but before it fired.
        if notification.request.identifier == Identifier.dailyReminder {
            let widgetData = WidgetDataStore.load()
            let isCompleted = widgetData.miles >= widgetData.goal
            let isReminderContent = notification.request.content.title.contains("waiting")
            if isCompleted && isReminderContent {
                center.removePendingNotificationRequests(withIdentifiers: [Identifier.dailyReminder])
                return []
            }
        }

        // For remote notifications, check user preferences
        let userInfo = notification.request.content.userInfo
        if let type = userInfo["type"] as? String {
            if !isRemoteNotificationEnabled(type: type) {
                return []
            }

            // Check DND schedule
            let prefs = NotificationPreferences.load()
            if prefs.dndEnabled {
                let hour = Calendar.current.component(.hour, from: Date())
                let inDND: Bool
                if prefs.dndStartHour > prefs.dndEndHour {
                    // Spans midnight (e.g., 22 to 8)
                    inDND = hour >= prefs.dndStartHour || hour < prefs.dndEndHour
                } else {
                    inDND = hour >= prefs.dndStartHour && hour < prefs.dndEndHour
                }
                if inDND {
                    return [] // Suppress banner during DND
                }
            }

            // Notify the app so badge counts can refresh while in foreground
            let data = userInfo["data"] as? [String: String] ?? [:]
            NotificationCenter.default.post(
                name: .didReceivePushNotification,
                object: nil,
                userInfo: ["type": type, "data": data]
            )
        }

        // Present our own branded, tappable in-app banner instead of Apple's
        // generic foreground banner. We still return `.list` so it lands in
        // Notification Center, and `.sound`, but drop `.banner` to avoid a
        // double banner. (Background/locked delivery is unaffected.)
        let content = notification.request.content
        InAppBannerManager.shared.show(
            title: content.title,
            body: content.body,
            type: userInfo["type"] as? String,
            data: userInfo["data"] as? [String: String] ?? [:]
        )
        return [.list, .sound]
    }

    @MainActor
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let userInfo = response.notification.request.content.userInfo

        // Action-button taps before generic tap routing.
        if response.actionIdentifier == "HYPE_ACTION" {
            await handleHypeAction(userInfo: userInfo)
            return
        }
        if response.actionIdentifier == "FRIEND_ACCEPT_ACTION" {
            await handleFriendRequestAction(userInfo: userInfo, accept: true)
            return
        }
        if response.actionIdentifier == "FRIEND_DECLINE_ACTION" {
            await handleFriendRequestAction(userInfo: userInfo, accept: false)
            return
        }

        guard let type = userInfo["type"] as? String else { return }
        let data = userInfo["data"] as? [String: String] ?? [:]

        // Store for cold-launch case (MainTabView may not be mounted yet)
        pendingNotificationType = type

        // Post a tap-specific notification so the app can navigate to the right screen
        NotificationCenter.default.post(
            name: .didTapPushNotification,
            object: nil,
            userInfo: ["type": type, "data": data]
        )
    }

    /// Handles the 🔥 Hype action button on a friend_activity push.
    /// Runs in the background (app may be suspended); calls /hype and shows a
    /// brief local notification with the result.
    private func handleHypeAction(userInfo: [AnyHashable: Any]) async {
        let data = userInfo["data"] as? [String: String]
        guard let targetUserId = data?["user_id"], !targetUserId.isEmpty else {
            await postLocalToast(title: "Couldn't send hype", body: "Try opening the app.")
            return
        }

        do {
            // Send the SAME mile-hype context the feed and notifications inbox use
            // (target:localDate) so this hype dedupes against them. A context-less
            // hype has no run identity and lets the same daily mile be hyped twice
            // (once here, once in the app). friend_activity pushes carry the
            // runner's local_date; the sympathetic "streak broken" variant isn't
            // hypeable, so fall back to a context-less hype there.
            let response: HypeResponse
            if data?["kind"] != "streak_broken",
               let localDate = data?["local_date"], !localDate.isEmpty {
                let context = HypeContext(
                    contextType: "mile",
                    contextId: "\(targetUserId):\(localDate)",
                    contextLabel: "today's mile"
                )
                response = try await HypeService.sendHype(targetUserId: targetUserId, context: context)
            } else {
                response = try await HypeService.sendHype(targetUserId: targetUserId)
            }
            let remaining = response.hypes_remaining
            let body: String
            if response.unlimited == true {
                body = "Hype sent!"
            } else {
                switch remaining {
                case 0:  body = "Hype sent! That was your last one today."
                case 1:  body = "Hype sent! 1 left today."
                default: body = "Hype sent! \(remaining) left today."
                }
            }
            await postLocalToast(title: "🔥 Hype sent", body: body)
        } catch let error as APIError where error.isRateLimited {
            await postLocalToast(title: "Out of hypes", body: "You're out of hypes for today.")
        } catch let error as APIError {
            // Already hyped this run from the feed/inbox — the dedupe caught it.
            if case .conflict = error {
                await postLocalToast(title: "Already hyped", body: "You already hyped this one 🔥")
            } else {
                await postLocalToast(title: "Couldn't send hype", body: "Try opening the app.")
            }
        } catch {
            await postLocalToast(title: "Couldn't send hype", body: "Try opening the app.")
        }
    }

    /// Handles the Accept / Decline buttons on a friend_request push.
    ///
    /// Runs while the app may be suspended, so it must NOT reach for the
    /// FriendService owned by MainTabView — that view may not exist. A throwaway
    /// instance is safe and cheap: its init only reads the auth token out of
    /// UserDefaults, no network.
    @MainActor
    private func handleFriendRequestAction(
        userInfo: [AnyHashable: Any],
        accept: Bool
    ) async {
        let data = userInfo["data"] as? [String: String]
        guard let requesterId = data?["user_id"], !requesterId.isEmpty else {
            await postLocalToast(
                title: "Couldn't respond",
                body: "Open the app to answer this request."
            )
            return
        }

        let service = FriendService()
        // Only the id travels in the push payload, so resolve the row to get a
        // BackendUser for the service call. If it's already gone, the request
        // was answered elsewhere (another device, or in-app).
        await service.loadFriendRequests()
        guard let user = service.friendRequests.first(where: { $0.user_id == requesterId }) else {
            await postLocalToast(
                title: "Already handled",
                body: "That request was already answered."
            )
            await setAppBadge(service.friendRequests.count)
            return
        }

        do {
            if accept {
                // acceptFriendRequest posts its own "You're now friends!" local
                // notification, so adding a toast here would double-notify.
                try await service.acceptFriendRequest(from: user)
            } else {
                try await service.declineFriendRequest(from: user)
                await postLocalToast(
                    title: "Request declined",
                    body: "You won't hear about this one again."
                )
            }
            await setAppBadge(service.friendRequests.count)
        } catch {
            await postLocalToast(
                title: accept ? "Couldn't accept" : "Couldn't decline",
                body: "Try opening the app."
            )
        }
    }

    /// Sets the app icon badge.
    ///
    /// The badge counts PENDING FRIEND REQUESTS ONLY. That keeps its meaning
    /// unambiguous — "something is blocked on you" — and it self-clears the
    /// moment the user accepts or declines. Folding in inbox unread would make
    /// it permanently red (every hype, friend post and activity push feeds that
    /// count), which trains the user to ignore it.
    ///
    /// `.badge` is already part of the authorization request, so this needs no
    /// new permission prompt. It silently no-ops if badges were denied, which
    /// is the correct behavior — don't try to detect it.
    func setAppBadge(_ count: Int) async {
        try? await center.setBadgeCount(max(0, count))
    }

    /// Schedules an immediate local notification used as a lightweight toast
    /// from the action handler (the app may be suspended at this point).
    private func postLocalToast(title: String, body: String) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = nil
        let request = UNNotificationRequest(
            identifier: "hype-toast-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        do {
            try await center.add(request)
        } catch {
            print("[Hype] Failed to post toast: \(error.localizedDescription)")
        }
    }
}
