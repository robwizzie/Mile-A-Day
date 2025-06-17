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
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 0
        
        if let formattedValue = formatter.string(from: NSNumber(value: self)) {
            return "\(formattedValue) \(self == 1.0 ? "mile" : "miles")"
        }
        
        return "\(self) miles"
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
        let minutesPerMile = duration / 60 / miles
        
        let minutes = Int(minutesPerMile)
        let seconds = Int((minutesPerMile - Double(minutes)) * 60)
        
        return String(format: "%d:%02d /mi", minutes, seconds)
    }
} 