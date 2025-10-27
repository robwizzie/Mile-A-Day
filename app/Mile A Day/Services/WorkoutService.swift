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
        
        guard let token = authToken else {
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
    
    /// Upload all workouts from HealthKit (for testing purposes)
    func uploadAllWorkouts() async throws {
        guard let currentUserId = getCurrentUserId() else {
            throw WorkoutServiceError.notAuthenticated
        }
        
        guard let token = authToken else {
            throw WorkoutServiceError.notAuthenticated
        }
        
        isLoading = true
        errorMessage = nil
        
        do {
            // Fetch all workouts directly from HealthKit
            let allWorkouts = try await fetchAllWorkoutsFromHealthKit()
            
            if allWorkouts.isEmpty {
                await MainActor.run {
                    workoutService.errorMessage = "No workouts found to upload"
                }
                return
            }
            
            // Transform and upload
            let workoutData = try await transformWorkoutsForBackend(allWorkouts)
            
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
            print("[WorkoutService] ✅ Successfully uploaded \(allWorkouts.count) workouts")
            
        } catch {
            errorMessage = error.localizedDescription
            print("[WorkoutService] ❌ Upload failed: \(error)")
            throw error
        }
        
        isLoading = false
    }
    
    // MARK: - Private Helper Methods
    private func makeRequest<T: Codable>(
        endpoint: String,
        method: HTTPMethod = .GET,
        body: Data? = nil,
        responseType: T.Type
    ) async throws -> T {
        guard let url = URL(string: "\(baseURL)\(endpoint)") else {
            throw WorkoutServiceError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(authToken!)", forHTTPHeaderField: "Authorization")
        
        if let body = body {
            request.httpBody = body
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw WorkoutServiceError.invalidResponse
            }
            
            print("[WorkoutService] 📊 Response status code: \(httpResponse.statusCode)")
            if let responseString = String(data: data, encoding: .utf8) {
                print("[WorkoutService] 📦 Response body: \(responseString)")
            }
            
            // Handle different status codes
            switch httpResponse.statusCode {
            case 200...299:
                break
            case 401:
                print("[WorkoutService] ❌ Unauthorized (401)")
                throw WorkoutServiceError.unauthorized
            case 400:
                // Try to parse error message from response
                if let errorData = try? JSONDecoder().decode([String: String].self, from: data),
                   let errorMessage = errorData["error"] {
                    print("[WorkoutService] ❌ Bad request (400): \(errorMessage)")
                    throw WorkoutServiceError.apiError(errorMessage)
                }
                print("[WorkoutService] ❌ Bad request (400)")
                throw WorkoutServiceError.badRequest
            default:
                print("[WorkoutService] ❌ Server error (\(httpResponse.statusCode))")
                throw WorkoutServiceError.serverError(httpResponse.statusCode)
            }
            
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            
            return try decoder.decode(T.self, from: data)
            
        } catch let error as WorkoutServiceError {
            throw error
        } catch {
            throw WorkoutServiceError.networkError(error.localizedDescription)
        }
    }
    
    /// Transform HKWorkout objects to backend format
    private func transformWorkoutsForBackend(_ workouts: [HKWorkout]) async throws -> [[String: Any]] {
        var workoutData: [[String: Any]] = []
        
        for workout in workouts {
            // Get split times for this workout
            let splitTimes = await getSplitTimes(for: workout)
            
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
            
            // Also create ISO date format for potential database compatibility
            let isoDateFormatter = ISO8601DateFormatter()
            let isoDate = isoDateFormatter.string(from: workout.startDate)
            
            // Determine workout type
            let workoutType = getWorkoutType(from: workout.workoutActivityType)
            
            // Get calories (convert from kilocalories to calories if needed)
            let calories = workout.totalEnergyBurned?.doubleValue(for: HKUnit.kilocalorie()) ?? 0
            
            let workoutDict: [String: Any] = [
                "workoutId": workout.uuid.uuidString,
                "distance": distanceInMiles(from: workout),
                "localDate": localDate,
                "date": localDate, // Add date field for database compatibility
                "timezoneOffset": timezoneOffset,
                "workoutType": workoutType,
                "deviceEndDate": deviceEndDate,
                "calories": calories,
                "totalDuration": workout.duration,
                "splitTimes": splitTimes
            ]
            
            // Debug: Print the workout data being sent
            print("[WorkoutService] 📤 Sending workout data: \(workoutDict)")
            
            workoutData.append(workoutDict)
        }
        
        return workoutData
    }
    
    /// Get distance in miles from a workout
    private func distanceInMiles(from workout: HKWorkout) -> Double {
        guard let distance = workout.totalDistance else { return 0 }
        return distance.doubleValue(for: HKUnit.mile())
    }
    
    /// Get split times for a workout
    private func getSplitTimes(for workout: HKWorkout) async -> [Double] {
        return await withCheckedContinuation { continuation in
            // For now, return empty array - we can enhance this later
            // to actually calculate split times from workout samples
            continuation.resume(returning: [])
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
    
    /// Fetch all workouts from HealthKit (for testing purposes)
    private func fetchAllWorkoutsFromHealthKit() async throws -> [HKWorkout] {
        return await withCheckedThrowingContinuation { continuation in
            guard HKHealthStore.isHealthDataAvailable() else {
                continuation.resume(throwing: WorkoutServiceError.networkError("HealthKit not available"))
                return
            }
            
            let healthStore = HKHealthStore()
            
            // Look for both running and walking workouts
            let runningPredicate = HKQuery.predicateForWorkouts(with: .running)
            let walkingPredicate = HKQuery.predicateForWorkouts(with: .walking)
            let compoundPredicate = NSCompoundPredicate(orPredicateWithSubpredicates: [runningPredicate, walkingPredicate])
            
            let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
            
            let query = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: compoundPredicate,
                limit: HKObjectQueryNoLimit, // No limit - fetch all workouts
                sortDescriptors: [sortDescriptor]
            ) { query, samples, error in
                if let error = error {
                    continuation.resume(throwing: WorkoutServiceError.networkError(error.localizedDescription))
                    return
                }
                
                guard let workouts = samples as? [HKWorkout] else {
                    continuation.resume(returning: [])
                    return
                }
                
                continuation.resume(returning: workouts)
            }
            
            healthStore.execute(query)
        }
    }
    
    /// Get current user ID from UserDefaults
    private func getCurrentUserId() -> String? {
        return UserDefaults.standard.string(forKey: "backendUserId")
    }
}

// MARK: - Response Models
struct WorkoutUploadResponse: Codable {
    let message: String
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
