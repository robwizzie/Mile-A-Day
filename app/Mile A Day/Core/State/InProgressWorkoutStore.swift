import Foundation
import HealthKit

/// Lightweight, persistent representation of an in‑progress workout.
/// This ensures we can always restore the user's active workout UI/state
/// after app backgrounding, relaunch, or when opening from a Live Activity.
struct InProgressWorkoutState: Codable {
    var isActive: Bool
    var startTime: Date
    var elapsedTime: TimeInterval
    var currentDistance: Double
    var startingDistance: Double
    var totalDailyDistance: Double
    var goalDistance: Double
    var activityType: String // "Running" or "Walking"
    var locationTypeRawValue: Int // HKWorkoutSessionLocationType.rawValue
}

enum InProgressWorkoutStore {
    private static let storageKey = "MAD_InProgressWorkoutState"

    /// Save the current in‑progress workout snapshot.
    static func save(_ state: InProgressWorkoutState) {
        guard state.isActive else {
            clear()
            return
        }

        do {
            let data = try JSONEncoder().encode(state)
            UserDefaults.standard.set(data, forKey: storageKey)
        } catch {
            print("[InProgressWorkoutStore] ❌ Failed to save state: \(error)")
        }
    }

    /// Load the last in‑progress workout snapshot if it exists.
    static func load() -> InProgressWorkoutState? {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else {
            return nil
        }

        do {
            let state = try JSONDecoder().decode(InProgressWorkoutState.self, from: data)
            return state
        } catch {
            print("[InProgressWorkoutStore] ❌ Failed to decode state: \(error)")
            return nil
        }
    }

    /// Clear any persisted in‑progress workout.
    static func clear() {
        UserDefaults.standard.removeObject(forKey: storageKey)
    }
}


