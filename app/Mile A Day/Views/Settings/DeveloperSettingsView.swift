//
//  DeveloperSettingsView.swift
//  Mile A Day
//
//  Developer tools for testing and debugging
//  Includes cache clearing, sync reset, and testing utilities
//

import SwiftUI

struct DeveloperSettingsView: View {
    @StateObject private var syncService = WorkoutSyncService.shared
    @StateObject private var workoutService = WorkoutService()
    @StateObject private var healthManager = HealthKitManager()
    @StateObject private var userManager = UserManager()
    @State private var showClearCacheConfirmation = false
    @State private var showResetSyncConfirmation = false
    @State private var showForceSync = false
    @State private var syncStatus: String = "Loading..."
    @State private var showSuccessAlert = false
    @State private var successMessage = ""
    @State private var showCelebration = false
    @State private var showWorkoutUploadAlert = false

    var body: some View {
        List {
            // Quick Test Actions Section
            Section(header: Text("Quick Test Actions"), footer: Text("Testing utilities for rapid development")) {
                Button(action: {
                    showCelebration = true
                }) {
                    HStack {
                        Image(systemName: "star.fill")
                            .foregroundColor(.yellow)
                        Text("Test Celebration Animation")
                        Spacer()
                        Image(systemName: "wand.and.stars")
                            .foregroundColor(.secondary)
                    }
                }

                Button(action: {
                    Task {
                        await uploadWorkouts()
                    }
                }) {
                    HStack {
                        Image(systemName: "arrow.up.circle.fill")
                            .foregroundColor(.green)
                        Text("Upload Recent Workouts")
                        Spacer()
                        if workoutService.isLoading {
                            ProgressView()
                        }
                    }
                }
                .disabled(workoutService.isLoading)

                Button(action: {
                    Task {
                        await uploadAllWorkouts()
                    }
                }) {
                    HStack {
                        Image(systemName: "arrow.up.circle")
                            .foregroundColor(.blue)
                        Text("Upload ALL Workouts")
                        Spacer()
                        if workoutService.isLoading {
                            ProgressView()
                        }
                    }
                }
                .disabled(workoutService.isLoading)
            }

            // Sync Status Section
            Section(header: Text("Sync Status")) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Last Sync:")
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(lastSyncText)
                            .fontWeight(.medium)
                    }

                    HStack {
                        Text("Unsynced Workouts:")
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(syncStatus)
                            .fontWeight(.medium)
                    }

                    HStack {
                        Text("Syncing:")
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(syncService.isSyncing ? "Yes" : "No")
                            .fontWeight(.medium)
                            .foregroundColor(syncService.isSyncing ? .orange : .green)
                    }
                }
                .padding(.vertical, 4)
            }

            // Sync Actions Section
            Section(header: Text("Sync Actions")) {
                Button(action: {
                    Task {
                        await refreshSyncStatus()
                    }
                }) {
                    Label("Refresh Sync Status", systemImage: "arrow.clockwise")
                }

                Button(action: {
                    showForceSync = true
                }) {
                    Label("Force Full Sync", systemImage: "icloud.and.arrow.up")
                }
                .disabled(syncService.isSyncing)

                Button(action: {
                    showResetSyncConfirmation = true
                }) {
                    Label("Reset Sync State", systemImage: "arrow.counterclockwise")
                }
                .foregroundColor(.orange)
            }

            // Cache Management Section
            Section(header: Text("Cache Management")) {
                Button(action: {
                    showClearCacheConfirmation = true
                }) {
                    Label("Clear All Cache", systemImage: "trash")
                }
                .foregroundColor(.red)

                Button(action: {
                    clearWorkoutIndex()
                }) {
                    Label("Clear Workout Index", systemImage: "list.bullet.rectangle")
                }
                .foregroundColor(.orange)

                Button(action: {
                    clearWidgetData()
                }) {
                    Label("Clear Widget Data", systemImage: "widget.small")
                }
                .foregroundColor(.orange)
            }

            // Storage Info Section
            Section(header: Text("Storage Info")) {
                VStack(alignment: .leading, spacing: 8) {
                    storageInfoRow(label: "Workout Index", key: "com.mileaday.workoutIndex.v1")
                    storageInfoRow(label: "Auth Token", key: "authToken", sensitive: true)
                    storageInfoRow(label: "Backend User ID", key: "backendUserId")
                    storageInfoRow(label: "Last Synced Date", key: "lastSyncedWorkoutDate")
                    storageInfoRow(label: "Uploaded IDs", key: "uploadedWorkoutIds")
                }
            }

            // Background Tasks Section
            Section(header: Text("Background Tasks")) {
                Button(action: {
                    Task {
                        await simulateBackgroundSync()
                    }
                }) {
                    Label("Simulate Background Sync", systemImage: "arrow.up.circle")
                }
                .disabled(syncService.isSyncing)

                Button(action: {
                    Task {
                        await simulateForegroundSync()
                    }
                }) {
                    Label("Simulate Foreground Sync", systemImage: "arrow.up.forward")
                }
                .disabled(syncService.isSyncing)
            }
        }
        .navigationTitle("Developer Settings")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            Task {
                await refreshSyncStatus()
            }
        }
        .sheet(isPresented: $showForceSync) {
            SyncProgressView(onComplete: {
                showForceSync = false
                Task {
                    await refreshSyncStatus()
                }
            })
        }
        .alert("Clear All Cache?", isPresented: $showClearCacheConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Clear", role: .destructive) {
                clearAllCache()
            }
        } message: {
            Text("This will clear all cached data including workout index, widget data, and sync state. This cannot be undone.")
        }
        .alert("Reset Sync State?", isPresented: $showResetSyncConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Reset", role: .destructive) {
                resetSyncState()
            }
        } message: {
            Text("This will reset the sync state, causing the next sync to upload all workouts again. Previously synced workouts will be re-uploaded (backend handles duplicates).")
        }
        .alert("Success", isPresented: $showSuccessAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(successMessage)
        }
        .alert("Workout Upload", isPresented: $showWorkoutUploadAlert) {
            Button("OK") { }
        } message: {
            if let status = workoutService.lastUploadStatus {
                Text(status)
            } else if let error = workoutService.errorMessage {
                Text("Error: \(error)")
            } else {
                Text("Upload completed")
            }
        }
        .confetti(isShowing: $showCelebration)
    }

    // MARK: - Subviews

    private func storageInfoRow(label: String, key: String, sensitive: Bool = false) -> some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
                .font(.caption)
            Spacer()
            if UserDefaults.standard.object(forKey: key) != nil {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.caption)
                if !sensitive {
                    Text("Exists")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            } else {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
                    .font(.caption)
                Text("Not set")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var lastSyncText: String {
        if let lastSync = syncService.lastSyncDate {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .abbreviated
            return formatter.localizedString(for: lastSync, relativeTo: Date())
        } else {
            return "Never"
        }
    }

    // MARK: - Actions

    private func refreshSyncStatus() async {
        let count = await syncService.getUnsyncedCount()
        await MainActor.run {
            syncStatus = "\(count)"
        }
    }

    private func clearAllCache() {
        // Clear workout index
        WorkoutIndex.clear()

        // Clear widget data
        WidgetDataStore.clearAll()

        // Clear sync state
        syncService.resetSyncState()

        // Clear other cached data
        UserDefaults.standard.removeObject(forKey: "com.mileaday.workoutIndex.v1")

        successMessage = "All cache cleared successfully"
        showSuccessAlert = true

        Task {
            await refreshSyncStatus()
        }
    }

    private func clearWorkoutIndex() {
        WorkoutIndex.clear()
        successMessage = "Workout index cleared successfully"
        showSuccessAlert = true
    }

    private func clearWidgetData() {
        WidgetDataStore.clearAll()
        successMessage = "Widget data cleared successfully"
        showSuccessAlert = true
    }

    private func resetSyncState() {
        syncService.resetSyncState()
        successMessage = "Sync state reset successfully"
        showSuccessAlert = true

        Task {
            await refreshSyncStatus()
        }
    }

    private func simulateBackgroundSync() async {
        do {
            try await syncService.syncNewWorkouts()
            await MainActor.run {
                successMessage = "Background sync completed successfully"
                showSuccessAlert = true
            }
        } catch {
            await MainActor.run {
                successMessage = "Background sync failed: \(error.localizedDescription)"
                showSuccessAlert = true
            }
        }

        await refreshSyncStatus()
    }

    private func simulateForegroundSync() async {
        await AppLaunchSyncHandler.shared.checkAndSyncOnForeground()
        await MainActor.run {
            successMessage = "Foreground sync completed"
            showSuccessAlert = true
        }

        await refreshSyncStatus()
    }

    private func uploadWorkouts() async {
        do {
            let user = userManager.currentUser
            let workouts = healthManager.recentWorkouts

            let workoutRecords = workouts.map { workout in
                WorkoutRecord(from: workout, user: user)
            }

            try await workoutService.uploadWorkouts(workoutRecords, for: user.id)

            await MainActor.run {
                showWorkoutUploadAlert = true
            }
        } catch {
            await MainActor.run {
                showWorkoutUploadAlert = true
            }
        }
    }

    private func uploadAllWorkouts() async {
        do {
            try await workoutService.uploadAllWorkouts(for: userManager.currentUser.id, healthManager: healthManager)

            await MainActor.run {
                showWorkoutUploadAlert = true
            }
        } catch {
            await MainActor.run {
                showWorkoutUploadAlert = true
            }
        }
    }
}

// MARK: - Widget Data Store Extension

extension WidgetDataStore {
    static func clearAll() {
        let sharedDefaults = UserDefaults(suiteName: "group.mileaday.shared")
        sharedDefaults?.removeObject(forKey: "today_miles_completed")
        sharedDefaults?.removeObject(forKey: "daily_goal")
        sharedDefaults?.removeObject(forKey: "streak_count")
        sharedDefaults?.removeObject(forKey: "streak_completed_today")
    }
}

// MARK: - Preview

struct DeveloperSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            DeveloperSettingsView()
        }
    }
}
