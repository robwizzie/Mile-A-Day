//
//  AppLaunchSyncHandler.swift
//  Mile A Day
//
//  Handles automatic workout syncing when the app launches or comes to foreground
//

import Foundation
import SwiftUI

/// Handles automatic workout sync on app launch and foreground transitions
@MainActor
class AppLaunchSyncHandler: ObservableObject {

    // MARK: - Singleton
    static let shared = AppLaunchSyncHandler()

    // MARK: - Published Properties
    @Published var isSyncing = false
    @Published var showSyncProgress = false

    // MARK: - Private Properties
    private let syncService = WorkoutSyncService.shared
    private let silentSyncThreshold = 50 // If more than 50 workouts, show progress UI

    // MARK: - Initialization
    private init() {}

    // MARK: - Public API

    /// Check and sync workouts on app launch
    func checkAndSyncOnLaunch() async {
        // Only sync if user is authenticated
        guard UserDefaults.standard.bool(forKey: "MAD_IsAuthenticated") else {
            print("[AppLaunchSyncHandler] Skipping sync - user not authenticated")
            return
        }

        guard !isSyncing else {
            print("[AppLaunchSyncHandler] Sync already in progress")
            return
        }

        print("[AppLaunchSyncHandler] Checking for new workouts to sync...")

        do {
            let unsyncedCount = await syncService.getUnsyncedCount()

            guard unsyncedCount > 0 else {
                print("[AppLaunchSyncHandler] No new workouts to sync")
                return
            }

            print("[AppLaunchSyncHandler] Found \(unsyncedCount) unsynced workouts")

            if unsyncedCount > silentSyncThreshold {
                // Show progress UI for large syncs
                await MainActor.run {
                    showSyncProgress = true
                }
                try await syncService.syncNewWorkouts()
                await MainActor.run {
                    showSyncProgress = false
                }
            } else {
                // Silent background sync for small updates
                try await performSilentSync()
            }

            print("[AppLaunchSyncHandler] ✅ Launch sync complete")

        } catch {
            print("[AppLaunchSyncHandler] ❌ Launch sync failed: \(error)")
        }
    }

    /// Check and sync workouts when app enters foreground
    func checkAndSyncOnForeground() async {
        // Only sync if it's been a while since last sync
        guard shouldSyncOnForeground() else {
            print("[AppLaunchSyncHandler] Skipping foreground sync (too soon since last sync)")
            return
        }

        await checkAndSyncOnLaunch()
    }

    /// Perform a silent background sync (for small number of workouts)
    func performSilentSync() async throws {
        guard !isSyncing else {
            print("[AppLaunchSyncHandler] Sync already in progress")
            return
        }

        isSyncing = true
        defer { isSyncing = false }

        print("[AppLaunchSyncHandler] Performing silent background sync...")

        try await syncService.syncNewWorkouts()

        print("[AppLaunchSyncHandler] ✅ Silent sync complete")
    }

    // MARK: - Private Helpers

    /// Determine if we should sync on foreground (avoid syncing too frequently)
    private func shouldSyncOnForeground() -> Bool {
        guard let lastSync = syncService.lastSyncDate else {
            // Never synced before
            return true
        }

        // Only sync if it's been at least 5 minutes since last sync
        let timeSinceLastSync = Date().timeIntervalSince(lastSync)
        let minimumInterval: TimeInterval = 5 * 60 // 5 minutes

        return timeSinceLastSync >= minimumInterval
    }
}

/// SwiftUI View Modifier for automatic sync on app launch
struct AutoSyncOnLaunchModifier: ViewModifier {
    @StateObject private var syncHandler = AppLaunchSyncHandler.shared

    func body(content: Content) -> some View {
        content
            .task {
                await syncHandler.checkAndSyncOnLaunch()
            }
            .sheet(isPresented: $syncHandler.showSyncProgress) {
                SyncProgressView(onComplete: {
                    syncHandler.showSyncProgress = false
                })
                .interactiveDismissDisabled()
            }
    }
}

extension View {
    /// Automatically sync workouts when this view appears
    func autoSyncOnLaunch() -> some View {
        modifier(AutoSyncOnLaunchModifier())
    }
}
