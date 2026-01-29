import SwiftUI
import HealthKit
#if canImport(UIKit)
import UIKit
#endif

// MARK: - HTTP Methods

enum HTTPMethod: String {
    case GET = "GET"
    case POST = "POST"
    case PUT = "PUT"
    case PATCH = "PATCH"
    case DELETE = "DELETE"
}

// We're now using the auto-generated color extensions from the asset catalog

// MARK: - Color Extension for Hex Support

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
    
    func toHex() -> String? {
        #if canImport(UIKit)
        let uic = UIColor(self)
        guard let components = uic.cgColor.components, components.count >= 3 else {
            return nil
        }
        let r = Float(components[0])
        let g = Float(components[1])
        let b = Float(components[2])
        return String(format: "#%02lX%02lX%02lX", lroundf(r * 255), lroundf(g * 255), lroundf(b * 255))
        #else
        return nil
        #endif
    }
}

// View extension for common modifiers
extension View {
    // Card style for uniform appearance with dark mode support - now with liquid glass
    func cardStyle() -> some View {
        self
            .liquidGlassCard()
    }
    
    // Streak badge style
    func streakBadge() -> some View {
        self
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color("appPrimary"))
            .foregroundColor(.white)
            .cornerRadius(12)
            .shadow(color: Color.primary.opacity(0.1), radius: 3, x: 0, y: 1)
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

// TimeInterval (minutes per mile) → "M:SS" pace string
extension TimeInterval {
    /// Format pace as "M:SS" (e.g. 7.5 → "7:30") for minutes per mile.
    var paceFormatted: String {
        guard self > 0, self < 60 else { return "—" }
        let totalSeconds = Int(self * 60)
        let m = totalSeconds / 60
        let s = totalSeconds % 60
        return String(format: "%d:%02d", m, s)
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
    
    var formattedShortDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
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
    
    /// Returns the workout date formatted in its original timezone (if available)
    /// Falls back to device timezone if location data unavailable
    func formattedDateInOriginalTimezone(completion: @escaping (String) -> Void) {
        // Try to get the workout's original timezone
        if let healthKitManager = getHealthKitManagerInstance() {
            healthKitManager.getLocalCalendarForWorkout(self) { calendar in
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                formatter.timeStyle = .short
                formatter.timeZone = calendar.timeZone
                
                let formattedString = formatter.string(from: self.endDate)
                let timezoneInfo = calendar.timeZone.identifier
                
                DispatchQueue.main.async {
                    completion("\(formattedString) (\(timezoneInfo))")
                }
            }
        } else {
            // Fallback to device timezone
            completion(formattedDate)
        }
    }
    
    /// Synchronous version that shows device timezone with note if location-aware is enabled
    var formattedDateWithTimezoneInfo: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        let deviceTimeString = formatter.string(from: endDate)
        
        // Add timezone identifier to show this is device timezone
        let timezoneAbbrev = TimeZone.current.abbreviation() ?? TimeZone.current.identifier
        return "\(deviceTimeString) (\(timezoneAbbrev) - device timezone)"
    }
    
    var pace: String {
        guard let distance = totalDistance,
              distance.doubleValue(for: HKUnit.mile()) > 0 else { return "N/A" }
        
        let miles = distance.doubleValue(for: HKUnit.mile())
        
        // For the average pace display, we use the workout's total duration and distance
        // This gives us the average pace for the entire workout, which is appropriate for workout summaries
        // NOTE: For fastest mile calculations, use HealthKitManager.getWorkoutSplitTimes() to get per-mile splits
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

// MARK: - Timezone Utilities for UI

/// Helper function to get HealthKitManager instance from the environment
/// This is a simplified approach - in production you'd want proper dependency injection
private func getHealthKitManagerInstance() -> HealthKitManager? {
    // For now, return nil to use fallback behavior
    // TODO: Implement proper dependency injection to access HealthKitManager
    return nil
} 