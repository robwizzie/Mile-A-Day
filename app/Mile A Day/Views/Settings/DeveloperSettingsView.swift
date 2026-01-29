//
//  DeveloperSettingsView.swift
//  Mile A Day
//
//  Developer tools for testing and debugging
//  Includes cache clearing, sync reset, and testing utilities
//

import SwiftUI
import HealthKit

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
    @State private var workoutIdInput = ""
    @State private var showDistanceSamplesSheet = false
    @State private var distanceSamplesLog = ""

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

            // Workout Debugging Section
            Section(header: Text("Workout Debugging"), footer: Text("Analyze distance samples for split calculation issues")) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Workout ID")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    TextField("Enter workout UUID", text: $workoutIdInput)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                }

                Button(action: {
                    Task {
                        await logDistanceSamples()
                    }
                }) {
                    HStack {
                        Image(systemName: "doc.text.magnifyingglass")
                            .foregroundColor(.purple)
                        Text("Log Distance Samples")
                        Spacer()
                    }
                }
                .disabled(workoutIdInput.isEmpty)
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
        .sheet(isPresented: $showDistanceSamplesSheet) {
            NavigationStack {
                ScrollView {
                    Text(distanceSamplesLog)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .padding()
                }
                .navigationTitle("Distance Samples JSON")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button(action: {
                            UIPasteboard.general.string = distanceSamplesLog
                        }) {
                            Label("Copy", systemImage: "doc.on.doc")
                        }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") {
                            showDistanceSamplesSheet = false
                        }
                    }
                }
            }
        }
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
            let workouts = healthManager.recentWorkouts

            try await workoutService.uploadWorkouts(workouts)

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
        // Use WorkoutSyncService for batched upload with retry logic
        for await progress in syncService.performInitialSync() {
            if case .complete = progress.phase {
                await MainActor.run {
                    showWorkoutUploadAlert = true
                }
            } else if case .error(let message) = progress.phase {
                await MainActor.run {
                    workoutService.errorMessage = message
                    showWorkoutUploadAlert = true
                }
            }
        }
    }

    private func logDistanceSamples() async {
        guard !workoutIdInput.isEmpty, let workoutUUID = UUID(uuidString: workoutIdInput) else {
            await MainActor.run {
                distanceSamplesLog = "{\"error\": \"Invalid workout UUID\"}"
                showDistanceSamplesSheet = true
            }
            return
        }

        await MainActor.run {
            distanceSamplesLog = "{\"status\": \"Fetching workout and distance samples...\"}"
            showDistanceSamplesSheet = true
        }

        // Fetch the workout from HealthKit
        guard let workout = await fetchWorkoutByUUID(workoutUUID) else {
            await MainActor.run {
                distanceSamplesLog = "{\"error\": \"Workout not found in HealthKit\"}"
            }
            return
        }

        // Fetch distance samples
        let samples = await fetchDistanceSamples(for: workout)

        // Build JSON structure
        var json: [String: Any] = [:]

        // Workout metadata
        let isoFormatter = ISO8601DateFormatter()
        json["workoutId"] = workout.uuid.uuidString
        json["workoutType"] = workout.workoutActivityType.rawValue
        json["totalDistance"] = workout.totalDistance?.doubleValue(for: .mile()) ?? 0
        json["totalDistanceMeters"] = workout.totalDistance?.doubleValue(for: .meter()) ?? 0
        json["duration"] = workout.duration
        json["startDate"] = isoFormatter.string(from: workout.startDate)
        json["endDate"] = isoFormatter.string(from: workout.endDate)

        // Distance samples
        var samplesArray: [[String: Any]] = []
        var cumulativeDistance = 0.0

        for (index, sample) in samples.enumerated() {
            let distance = sample.quantity.doubleValue(for: .meter())
            let distanceMiles = distance / 1609.34
            cumulativeDistance += distance

            let duration = sample.endDate.timeIntervalSince(sample.startDate)
            let pace = distanceMiles > 0 ? duration / distanceMiles / 60.0 : 0 // minutes per mile

            let sampleDict: [String: Any] = [
                "sampleNumber": index + 1,
                "startDate": isoFormatter.string(from: sample.startDate),
                "endDate": isoFormatter.string(from: sample.endDate),
                "durationSeconds": duration,
                "distanceMiles": distanceMiles,
                "distanceMeters": distance,
                "paceMinutesPerMile": pace,
                "cumulativeDistanceMiles": cumulativeDistance / 1609.34,
                "cumulativeDistanceMeters": cumulativeDistance
            ]

            samplesArray.append(sampleDict)
        }

        json["sampleCount"] = samples.count
        json["samples"] = samplesArray

        // Summary
        let workoutTotalDistanceMiles = workout.totalDistance?.doubleValue(for: .mile()) ?? 0
        let workoutTotalDistanceMeters = workout.totalDistance?.doubleValue(for: .meter()) ?? 0
        let discrepancyMiles = (cumulativeDistance / 1609.34) - workoutTotalDistanceMiles

        json["summary"] = [
            "totalDistanceFromSamplesMiles": cumulativeDistance / 1609.34,
            "totalDistanceFromSamplesMeters": cumulativeDistance,
            "workoutTotalDistanceMiles": workoutTotalDistanceMiles,
            "workoutTotalDistanceMeters": workoutTotalDistanceMeters,
            "discrepancyMiles": discrepancyMiles
        ]

        // Convert to JSON string
        if let jsonData = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            await MainActor.run {
                distanceSamplesLog = jsonString
            }
        } else {
            await MainActor.run {
                distanceSamplesLog = "{\"error\": \"Failed to serialize JSON\"}"
            }
        }
    }

    private func fetchWorkoutByUUID(_ uuid: UUID) async -> HKWorkout? {
        return await withCheckedContinuation { continuation in
            guard HKHealthStore.isHealthDataAvailable() else {
                continuation.resume(returning: nil)
                return
            }

            let healthStore = HKHealthStore()
            let predicate = HKQuery.predicateForObject(with: uuid)

            let query = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: predicate,
                limit: 1,
                sortDescriptors: nil
            ) { _, samples, error in
                if let error = error {
                    print("[Dev] Error fetching workout: \(error)")
                    continuation.resume(returning: nil)
                    return
                }

                continuation.resume(returning: samples?.first as? HKWorkout)
            }

            healthStore.execute(query)
        }
    }

    private func fetchDistanceSamples(for workout: HKWorkout) async -> [HKQuantitySample] {
        return await withCheckedContinuation { continuation in
            guard HKHealthStore.isHealthDataAvailable(),
                  let distanceType = HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning) else {
                continuation.resume(returning: [])
                return
            }

            let healthStore = HKHealthStore()
            let workoutPredicate = HKQuery.predicateForObjects(from: workout)
            let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

            let query = HKSampleQuery(
                sampleType: distanceType,
                predicate: workoutPredicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
            ) { _, results, error in
                if let error = error {
                    print("[Dev] Error fetching distance samples: \(error)")
                    continuation.resume(returning: [])
                    return
                }

                continuation.resume(returning: (results as? [HKQuantitySample]) ?? [])
            }

            healthStore.execute(query)
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
