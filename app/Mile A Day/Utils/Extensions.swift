import SwiftUI
import HealthKit

// We're now using the auto-generated color extensions from the asset catalog

// View extension for common modifiers
extension View {
    // Card style for uniform appearance
    func cardStyle() -> some View {
        self
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(15)
            .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
    }
    
    // Streak badge style
    func streakBadge() -> some View {
        self
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color("appPrimary"))
            .foregroundColor(.white)
            .cornerRadius(12)
            .shadow(color: Color.black.opacity(0.1), radius: 3, x: 0, y: 1)
    }
}

// Formatter for distance values
extension Double {
    // Format miles with appropriate decimal places
    var milesFormatted: String {
        if self >= 1.0 {
            return String(format: "%.2f mi", self)
        } else {
            return String(format: "%.2f mi", self)
        }
    }
    
    var kmFormatted: String {
        let km = self * 1.60934
        return String(format: "%.2f km", km)
    }
    
    var metersFormatted: String {
        let meters = self * 1609.34
        return String(format: "%.0f m", meters)
    }
}

// Date extension for formatting
extension Date {
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: self)
    }
    
    var formattedTime: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: self)
    }
}

// Identifiable wrapper for HKWorkout
struct IdentifiableWorkout: Identifiable {
    let workout: HKWorkout
    
    var id: UUID {
        return workout.uuid
    }
}

// HKWorkout extension for easier data access
extension HKWorkout {
    var formattedDistance: String {
        guard let distance = totalDistance else { return "Unknown" }
        let miles = distance.doubleValue(for: HKUnit.mile())
        return miles.milesFormatted
    }
    
    var formattedDuration: String {
        let hours = Int(duration) / 3600
        let minutes = Int(duration) % 3600 / 60
        let seconds = Int(duration) % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
    
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: endDate)
    }
    
    var pace: String {
        guard let distance = totalDistance,
              distance.doubleValue(for: HKUnit.mile()) > 0 else { return "N/A" }
        
        let miles = distance.doubleValue(for: HKUnit.mile())
        
        // For the average pace display, we use the workout's total duration and distance
        // This gives us the average pace for the entire workout, which is appropriate for workout summaries
        let minutesPerMile = duration / 60.0 / miles
        
        guard minutesPerMile > 0 && minutesPerMile < 60 else { return "N/A" } // Sanity check
        
        let minutes = Int(minutesPerMile)
        let seconds = Int((minutesPerMile - Double(minutes)) * 60)
        
        return String(format: "%d:%02d /mi", minutes, seconds)
    }
}

// MARK: - Progress Calculation Utilities

/// Unified progress calculation system to ensure 1-to-1 synchronization
/// between Apple Fitness tracking and MAD tracking
struct ProgressCalculator {
    
    /// Calculates progress percentage, ensuring it never exceeds 100%
    /// - Parameters:
    ///   - current: Current distance completed
    ///   - goal: Goal distance
    /// - Returns: Progress value between 0.0 and 1.0
    static func calculateProgress(current: Double, goal: Double) -> Double {
        guard goal > 0 else { return 0.0 }
        return min(current / goal, 1.0)
    }
    
    /// Determines if the goal has been completed
    /// - Parameters:
    ///   - current: Current distance completed
    ///   - goal: Goal distance
    /// - Returns: True if goal is completed (current >= goal)
    static func isGoalCompleted(current: Double, goal: Double) -> Bool {
        return current >= goal
    }
    
    /// Calculates remaining distance to goal
    /// - Parameters:
    ///   - current: Current distance completed
    ///   - goal: Goal distance
    /// - Returns: Remaining distance (0 if goal is completed)
    static func remainingDistance(current: Double, goal: Double) -> Double {
        return max(goal - current, 0.0)
    }
    
    /// Formats progress percentage for display
    /// - Parameter progress: Progress value between 0.0 and 1.0
    /// - Returns: Formatted percentage string
    static func formatProgress(_ progress: Double) -> String {
        let percentage = Int(progress * 100)
        return "\(percentage)%"
    }
} 