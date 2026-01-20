//
//  WorkoutSplit.swift
//  Mile A Day
//
//  Model representing a single mile split from a workout
//

import Foundation

struct WorkoutSplit: Codable {
    let splitNumber: Int
    let distance: Double // in miles
    let duration: TimeInterval // in seconds
    let pace: Double // in seconds per mile (duration / distance)

    var paceMinutesPerMile: Double {
        pace / 60.0
    }

    var formattedPace: String {
        let minutes = Int(pace / 60)
        let seconds = Int(pace.truncatingRemainder(dividingBy: 60))
        return String(format: "%d:%02d", minutes, seconds)
    }
}
