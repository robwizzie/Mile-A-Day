import Foundation
import HealthKit

/// Service for handling workout-related API operations
@MainActor
class WorkoutService: ObservableObject {

    // MARK: - Published Properties
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var lastUploadStatus: String?

    // MARK: - Private Properties
    private let baseURL = "https://mad.mindgoblin.tech"
    private var authToken: String?
    private let healthStore = HKHealthStore()

    // MARK: - Initialization
    init() {
        // Load auth token from UserDefaults
        self.authToken = UserDefaults.standard.string(forKey: "authToken")
    }

    // MARK: - Authentication
    func setAuthToken(_ token: String) {
        self.authToken = token
        UserDefaults.standard.set(token, forKey: "authToken")
    }

    func clearAuthToken() {
        self.authToken = nil
        UserDefaults.standard.removeObject(forKey: "authToken")
    }

    // MARK: - Workout Upload
    /// Upload workouts to the backend
    func uploadWorkouts(_ workouts: [HKWorkout]) async throws {
        guard let currentUserId = getCurrentUserId() else {
            throw WorkoutServiceError.notAuthenticated
        }

        isLoading = true
        errorMessage = nil

        do {
            // Transform HKWorkout objects to backend format
            let workoutData = try await transformWorkoutsForBackend(workouts)

            // Debug: Print the full request data
            let requestBody = try JSONSerialization.data(withJSONObject: workoutData)
            if let requestString = String(data: requestBody, encoding: .utf8) {
                print("[WorkoutService] 📤 Full request body: \(requestString)")
            }

            // Make the API request
            let response: WorkoutUploadResponse = try await makeRequest(
                endpoint: "/workouts/\(currentUserId)/upload",
                method: .POST,
                body: requestBody,
                responseType: WorkoutUploadResponse.self
            )

            lastUploadStatus = response.message
            print("[WorkoutService] ✅ Successfully uploaded \(workouts.count) workouts")

        } catch {
            errorMessage = error.localizedDescription
            print("[WorkoutService] ❌ Upload failed: \(error)")
            throw error
        }

        isLoading = false
    }

    // MARK: - Private Helper Methods
    private func makeRequest<T: Decodable>(
        endpoint: String,
        method: HTTPMethod = .GET,
        body: Data? = nil,
        responseType: T.Type
    ) async throws -> T {
        do {
            return try await APIClient.fancyFetch(
                endpoint: endpoint,
                method: method,
                body: body,
                responseType: responseType
            )
        } catch let error as APIError {
            // Map APIError to WorkoutServiceError
            switch error {
            case .invalidURL:
                throw WorkoutServiceError.invalidURL
            case .invalidResponse:
                throw WorkoutServiceError.invalidResponse
            case .notAuthenticated:
                throw WorkoutServiceError.notAuthenticated
            case .unauthorized:
                throw WorkoutServiceError.unauthorized
            case .badRequest(let message):
                throw WorkoutServiceError.apiError(message)
            case .serverError(let code):
                throw WorkoutServiceError.serverError(code)
            case .tokenRefreshFailed:
                throw WorkoutServiceError.notAuthenticated
            case .networkError(let message):
                throw WorkoutServiceError.networkError(message)
            case .notFound:
                throw WorkoutServiceError.invalidResponse
            }
        } catch {
            throw WorkoutServiceError.networkError(error.localizedDescription)
        }
    }

    /// Transform HKWorkout objects to backend format
    private func transformWorkoutsForBackend(_ workouts: [HKWorkout]) async throws -> [[String:
        Any]]
    {
        var workoutData: [[String: Any]] = []

        for workout in workouts {
            // Get split data for this workout
            let splits = await getSplitTimes(for: workout)

            // Convert splits to dictionaries for JSON serialization
            let splitsData = splits.map { split -> [String: Any] in
                [
                    "splitNumber": split.splitNumber,
                    "distance": split.distance,
                    "duration": split.duration,
                    "pace": split.pace
                ]
            }

            // Calculate timezone offset
            let timezoneOffset = TimeZone.current.secondsFromGMT() / 60

            // Format local date
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.timeZone = TimeZone.current
            let localDate = formatter.string(from: workout.startDate)

            // Format device end date
            let isoFormatter = ISO8601DateFormatter()
            let deviceEndDate = isoFormatter.string(from: workout.endDate)

            // Determine workout type
            let workoutType = getWorkoutType(from: workout.workoutActivityType)

            let calories = await activeEnergyKilocalories(for: workout)

            let workoutDict: [String: Any] = [
                "workoutId": workout.uuid.uuidString,
                "distance": distanceInMiles(from: workout),
                "localDate": localDate,
                "date": localDate,  // Add date field for database compatibility
                "timezoneOffset": timezoneOffset,
                "workoutType": workoutType,
                "deviceEndDate": deviceEndDate,
                "calories": calories,
                "totalDuration": workout.duration,
                "splits": splitsData,
            ]

            // Debug: Print the workout data being sent with detailed split information
            print("[WorkoutService] 📤 Sending workout data:")
            print("  - Workout ID: \(workout.uuid.uuidString)")
            print("  - Distance: \(distanceInMiles(from: workout)) mi")
            print("  - Splits Count: \(splits.count)")
            if !splits.isEmpty {
                print("  - Detailed Splits:")
                for split in splits {
                    print(
                        "    Split \(split.splitNumber): \(split.formattedPace)/mile (\(String(format: "%.2f", split.distance)) mi in \(String(format: "%.0f", split.duration))s)"
                    )
                }
            } else {
                print("  - Splits: [] (empty)")
            }
            print("[WorkoutService] 📤 Full workout dict: \(workoutDict)")

            workoutData.append(workoutDict)
        }

        return workoutData
    }

    /// Get distance in miles from a workout
    private func distanceInMiles(from workout: HKWorkout) -> Double {
        guard let distance = workout.totalDistance else { return 0 }
        return distance.doubleValue(for: HKUnit.mile())
    }

    /// Get split data for a workout using cumulative distance with overflow interpolation
    private func getSplitTimes(for workout: HKWorkout) async -> [WorkoutSplit] {
        return await withCheckedContinuation { continuation in
            guard HKHealthStore.isHealthDataAvailable() else {
                print("[WorkoutService] ⚠️ HealthKit not available for split times")
                continuation.resume(returning: [])
                return
            }

            guard
                let distanceType = HKQuantityType.quantityType(
                    forIdentifier: .distanceWalkingRunning)
            else {
                print("[WorkoutService] ⚠️ Distance type not available for split times")
                continuation.resume(returning: [])
                return
            }

            print("[WorkoutService] 🔍 Starting split calculation for workout \(workout.uuid)")

            let healthStore = HKHealthStore()
            let workoutPredicate = HKQuery.predicateForObjects(from: workout)
            let sortDescriptor = NSSortDescriptor(
                key: HKSampleSortIdentifierStartDate, ascending: true)

            let query = HKSampleQuery(
                sampleType: distanceType,
                predicate: workoutPredicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
            ) { _, results, error in
                if let error = error {
                    print(
                        "[WorkoutService] ⚠️ Error fetching split times: \(error.localizedDescription)"
                    )
                    continuation.resume(returning: [])
                    return
                }

                guard let distanceSamples = results as? [HKQuantitySample], !distanceSamples.isEmpty
                else {
                    print(
                        "[WorkoutService] ℹ️ No distance samples found for workout \(workout.uuid)")
                    continuation.resume(returning: [])
                    return
                }

                print("[WorkoutService] 📊 Found \(distanceSamples.count) distance samples")

                // Filter out bad samples: negative distance or inhumane pace (> 13.4 m/s ≈ 2:00/mile)
                let maxHumanSpeed = 13.4 // meters per second, faster than Usain Bolt's 100m average
                let validSamples = distanceSamples.filter { sample in
                    let dist = sample.quantity.doubleValue(for: HKUnit.meter())
                    let dur = sample.endDate.timeIntervalSince(sample.startDate)
                    if dist <= 0 { return false }
                    if dur <= 0 { return false }
                    let speed = dist / dur
                    return speed <= maxHumanSpeed
                }

                guard !validSamples.isEmpty else {
                    print("[WorkoutService] ℹ️ No valid distance samples after filtering for workout \(workout.uuid)")
                    continuation.resume(returning: [])
                    return
                }

                let filteredCount = distanceSamples.count - validSamples.count
                if filteredCount > 0 {
                    print("[WorkoutService] ⚠️ Filtered out \(filteredCount) bad sample(s)")
                }

                // Use timestamp-based durations anchored to workout start
                let mileInMeters = 1609.34
                var splits: [WorkoutSplit] = []
                var cumulativeDistance = 0.0
                var currentSplitDuration = 0.0
                var previousEndDate = workout.startDate

                for sample in validSamples {
                    let sampleDistance = sample.quantity.doubleValue(for: HKUnit.meter())
                    let sampleDuration = sample.endDate.timeIntervalSince(previousEndDate)
                    cumulativeDistance += sampleDistance
                    previousEndDate = sample.endDate

                    // Track how much of this sample's time is still unassigned
                    var remainingDuration = sampleDuration

                    // Loop to handle samples that cross multiple mile boundaries
                    while cumulativeDistance >= Double(splits.count + 1) * mileInMeters {
                        let nextFullMile = Double(splits.count + 1) * mileInMeters
                        let extraMeters = cumulativeDistance - nextFullMile
                        let overflowRatio = sampleDistance > 0 ? extraMeters / sampleDistance : 0
                        let durationForThisMile = remainingDuration - (sampleDuration * overflowRatio)
                        currentSplitDuration += durationForThisMile
                        remainingDuration = sampleDuration * overflowRatio

                        let split = WorkoutSplit(
                            splitNumber: splits.count + 1,
                            distance: 1.0,
                            duration: currentSplitDuration,
                            pace: currentSplitDuration
                        )
                        splits.append(split)

                        print(
                            "[WorkoutService] ✅ Split \(split.splitNumber): \(split.formattedPace)/mile (\(String(format: "%.0f", split.duration))s)"
                        )

                        currentSplitDuration = 0
                    }

                    currentSplitDuration += remainingDuration
                }

                // Add incomplete final split if there's remaining time
                if currentSplitDuration > 0 {
                    let remainingMeters = cumulativeDistance.truncatingRemainder(dividingBy: mileInMeters)
                    let distanceInMiles = remainingMeters / mileInMeters
                    let pace = distanceInMiles > 0 ? (mileInMeters / remainingMeters) * currentSplitDuration : 0

                    let split = WorkoutSplit(
                        splitNumber: splits.count + 1,
                        distance: distanceInMiles,
                        duration: currentSplitDuration,
                        pace: pace
                    )
                    splits.append(split)

                    print(
                        "[WorkoutService] ✅ Partial Split \(split.splitNumber): \(split.formattedPace)/mile (\(String(format: "%.2f", split.distance)) mi in \(String(format: "%.0f", split.duration))s)"
                    )
                }

                print("[WorkoutService] ✅ Total splits calculated: \(splits.count)")
                continuation.resume(returning: splits)
            }

            healthStore.execute(query)
        }
    }

    /// Compute active energy for a workout using HealthKit statistics queries.
    private func activeEnergyKilocalories(for workout: HKWorkout) async -> Double {
        if #available(iOS 18.0, *) {
            guard HKHealthStore.isHealthDataAvailable(),
                let energyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)
            else {
                return 0
            }

            return await withCheckedContinuation { continuation in
                let predicate = HKQuery.predicateForObjects(from: workout)
                let query = HKStatisticsQuery(
                    quantityType: energyType,
                    quantitySamplePredicate: predicate,
                    options: .cumulativeSum
                ) { _, statistics, error in
                    if let error = error {
                        print(
                            "[WorkoutService] ⚠️ Active energy query failed: \(error.localizedDescription)"
                        )
                    }

                    let value =
                        statistics?.sumQuantity()?.doubleValue(for: HKUnit.kilocalorie()) ?? 0
                    continuation.resume(returning: value)
                }

                healthStore.execute(query)
            }
        } else {
            return workout.totalEnergyBurned?.doubleValue(for: HKUnit.kilocalorie()) ?? 0
        }
    }

    /// Convert HKWorkoutActivityType to string
    private func getWorkoutType(from activityType: HKWorkoutActivityType) -> String {
        switch activityType {
        case .running:
            return "running"
        case .walking:
            return "walking"
        case .cycling:
            return "cycling"
        case .hiking:
            return "hiking"
        default:
            return "other"
        }
    }

    /// Get current user ID from UserDefaults
    private func getCurrentUserId() -> String? {
        return UserDefaults.standard.string(forKey: "backendUserId")
    }

    // MARK: - Recent Workouts
    /// Get recent workouts for a user
    /// - Parameters:
    ///   - userId: The ID of the user to get recent workouts for
    ///   - limit: Maximum number of workouts to return (default: 10)
    /// - Returns: Array of recent workouts
    func getRecentWorkouts(userId: String, limit: Int = 10) async throws -> [RecentWorkout] {
        let endpoint = "/workouts/\(userId)/recent?limit=\(limit)"

        do {
            let workouts: [RecentWorkout] = try await makeRequest(
                endpoint: endpoint,
                method: .GET,
                responseType: [RecentWorkout].self
            )

            // Only log summary, detailed logs are in UserProfileDetailView
            return workouts

        } catch {
            throw error
        }
    }

    // MARK: - Streak
    /// Get workout streak for a user
    /// - Parameter userId: The ID of the user to get streak for
    /// - Returns: The user's current workout streak
    func getStreak(userId: String) async throws -> Int {
        let endpoint = "/workouts/\(userId)/streak"

        do {
            let response: StreakResponse = try await makeRequest(
                endpoint: endpoint,
                method: .GET,
                responseType: StreakResponse.self
            )

            return response.streak

        } catch {
            throw error
        }
    }

    // MARK: - User Stats
    /// Get aggregated workout stats for a user
    /// - Parameters:
    ///   - userId: The ID of the user
    ///   - currentStreakOnly: If true, limits stats to current streak period
    func getUserStats(userId: String, currentStreakOnly: Bool = false) async throws
        -> UserStatsAPIResponse
    {
        let param = currentStreakOnly ? "?current_streak=true" : ""
        let endpoint = "/workouts/\(userId)/stats\(param)"
        return try await makeRequest(
            endpoint: endpoint, method: .GET, responseType: UserStatsAPIResponse.self)
    }
}

// MARK: - Response Models
struct WorkoutUploadResponse: Codable {
    let message: String
}

// MARK: - Stats API Models
// Note: RecentWorkout and StreakResponse are defined in FriendComponents.swift
struct UserStatsAPIResponse: Decodable {
    struct BestMilesDay: Decodable {
        let localDate: String
        let totalDistance: Double

        enum CodingKeys: String, CodingKey {
            case localDate = "local_date"
            case totalDistance = "total_distance"
        }
    }

    struct DynamicCodingKeys: CodingKey {
        var stringValue: String
        init?(stringValue: String) { self.stringValue = stringValue }
        var intValue: Int?
        init?(intValue: Int) { return nil }
    }

    let streak: Int
    let startDate: String
    let totalMiles: Double
    let bestMilesDay: BestMilesDay?
    let bestSplitTimeSeconds: Double?
    let recentWorkouts: [RecentWorkout]
    let todayMiles: Double?
    let goalMiles: Double?

    enum CodingKeys: String, CodingKey {
        case streak
        case startDate = "start_date"
        case totalMiles = "total_miles"
        case bestMilesDay = "best_miles_day"
        case bestSplitTime = "best_split_time"
        case recentWorkouts = "recent_workouts"
        case todayMiles = "today_miles"
        case goalMiles = "goal_miles"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.streak = try container.decode(Int.self, forKey: .streak)
        self.startDate = try container.decode(String.self, forKey: .startDate)
        self.totalMiles = try container.decode(Double.self, forKey: .totalMiles)
        self.bestMilesDay = try? container.decode(BestMilesDay.self, forKey: .bestMilesDay)

        // best_split_time may be a number, null, or an object like {"workout":{}}; capture only if it's a number
        // Try to decode as Double first
        if let numeric = try? container.decode(Double.self, forKey: .bestSplitTime) {
            self.bestSplitTimeSeconds = numeric
        } else if container.contains(.bestSplitTime) {
            // If the key exists but isn't a number, try to decode as a nested dictionary {"workout":{}}
            // This pattern matches the API response structure
            do {
                let nestedContainer = try container.nestedContainer(
                    keyedBy: DynamicCodingKeys.self, forKey: .bestSplitTime)
                // If we got here, it's an object - check if it has a "workout" key
                if let workoutKey = DynamicCodingKeys(stringValue: "workout"),
                    nestedContainer.contains(workoutKey)
                {
                    self.bestSplitTimeSeconds = nil
                } else {
                    self.bestSplitTimeSeconds = nil
                }
            } catch {
                // If decoding fails, just set to nil
                self.bestSplitTimeSeconds = nil
            }
        } else {
            self.bestSplitTimeSeconds = nil
        }

        self.recentWorkouts =
            (try? container.decode([RecentWorkout].self, forKey: .recentWorkouts)) ?? []
        self.todayMiles = try? container.decode(Double.self, forKey: .todayMiles)
        self.goalMiles = try? container.decode(Double.self, forKey: .goalMiles)
    }

    /// Calculates if the user has completed their goal today
    var hasCompletedGoalToday: Bool {
        guard let today = todayMiles, let goal = goalMiles else { return false }
        return today >= goal && goal > 0
    }
}

// MARK: - Error Types
enum WorkoutServiceError: LocalizedError {
    case invalidURL
    case invalidResponse
    case notAuthenticated
    case unauthorized
    case badRequest
    case serverError(Int)
    case networkError(String)
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .invalidResponse:
            return "Invalid response from server"
        case .notAuthenticated:
            return "User not authenticated"
        case .unauthorized:
            return "Unauthorized access"
        case .badRequest:
            return "Bad request"
        case .serverError(let code):
            return "Server error: \(code)"
        case .networkError(let message):
            return "Network error: \(message)"
        case .apiError(let message):
            return message
        }
    }
}
