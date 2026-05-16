import Foundation
import HealthKit

/// watchOS-only. Uploads a finished workout straight to the backend so it lands
/// on the server immediately, instead of waiting for the iPhone's HealthKit
/// sync. Best-effort: any failure is logged and dropped — the iPhone's sync is
/// the backstop, and the upload endpoint is idempotent on workout id.
enum WatchWorkoutUploader {

    private static let baseURL = "https://mad.mindgoblin.tech"

    static func upload(_ workout: HKWorkout) async {
        guard let token = UserDefaults.standard.string(forKey: "authToken"), !token.isEmpty,
              let userId = UserDefaults.standard.string(forKey: "backendUserId"), !userId.isEmpty
        else {
            print("[WatchWorkoutUploader] No auth token / user id on watch — skipping direct upload")
            return
        }

        let splits = await SplitCalculator.calculateSplits(for: workout)
        let calories = await activeEnergyKilocalories(for: workout)

        let splitsData: [[String: Any]] = splits.map { split in
            [
                "splitNumber": split.splitNumber,
                "distance": split.distance,
                "duration": split.duration,
                "pace": split.pace
            ]
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.timeZone = TimeZone.current
        let localDate = dateFormatter.string(from: workout.startDate)

        let isoFormatter = ISO8601DateFormatter()
        let deviceEndDate = isoFormatter.string(from: workout.endDate)

        let distance = workout.totalDistance?.doubleValue(for: .mile()) ?? 0
        let timezoneOffset = TimeZone.current.secondsFromGMT() / 60

        let workoutDict: [String: Any] = [
            "workoutId": workout.uuid.uuidString,
            "distance": distance,
            "localDate": localDate,
            "date": localDate,
            "timezoneOffset": timezoneOffset,
            "workoutType": workoutType(from: workout.workoutActivityType),
            "deviceEndDate": deviceEndDate,
            "calories": calories,
            "totalDuration": workout.duration,
            "splits": splitsData,
            "source": "healthkit"
        ]

        guard let url = URL(string: "\(baseURL)/workouts/\(userId)/upload"),
              let body = try? JSONSerialization.data(withJSONObject: [workoutDict])
        else {
            print("[WatchWorkoutUploader] Failed to build upload request")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = body

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                print("[WatchWorkoutUploader] No HTTP response")
                return
            }
            if (200...299).contains(http.statusCode) {
                print("[WatchWorkoutUploader] ✅ Uploaded workout \(workout.uuid.uuidString)")
            } else {
                print("[WatchWorkoutUploader] ⚠️ Upload failed (status \(http.statusCode)) — iPhone sync will retry")
            }
        } catch {
            print("[WatchWorkoutUploader] ⚠️ Upload failed: \(error.localizedDescription) — iPhone sync will retry")
        }
    }

    private static func workoutType(from activityType: HKWorkoutActivityType) -> String {
        switch activityType {
        case .running: return "running"
        case .walking: return "walking"
        case .cycling: return "cycling"
        case .hiking: return "hiking"
        default: return "other"
        }
    }

    private static func activeEnergyKilocalories(for workout: HKWorkout) async -> Double {
        guard HKHealthStore.isHealthDataAvailable(),
              let energyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)
        else {
            return 0
        }
        let healthStore = HKHealthStore()
        return await withCheckedContinuation { continuation in
            let predicate = HKQuery.predicateForObjects(from: workout)
            let query = HKStatisticsQuery(
                quantityType: energyType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, statistics, _ in
                let value = statistics?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
                continuation.resume(returning: value)
            }
            healthStore.execute(query)
        }
    }
}
