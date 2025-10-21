//
//  WorkoutProcessor.swift
//  Mile A Day
//
//  Created by AI Assistant
//  Processes workouts and applies timezone corrections ONCE
//

import Foundation
import HealthKit

/// Processes HKWorkouts and applies timezone corrections
/// Results are cached in WorkoutIndex so corrections only happen once per workout
class WorkoutProcessor {
    
    private let calendar = Calendar.current
    
    // MARK: - Public API
    
    /// Process a workout and determine its local date (timezone-corrected)
    /// This is the ONLY place timezone logic runs - result is cached forever
    func processWorkout(_ workout: HKWorkout) -> WorkoutRecord {
        let (localDate, offset) = determineLocalDateWithOffset(for: workout)
        return WorkoutRecord(from: workout, timezoneCorrectedDate: localDate, timezoneOffset: offset)
    }
    
    /// Process multiple workouts efficiently
    func processWorkouts(_ workouts: [HKWorkout]) -> [WorkoutRecord] {
        print("[WorkoutProcessor] Processing \(workouts.count) workouts...")
        var records: [WorkoutRecord] = []
        var correctionCount = 0
        
        for workout in workouts {
            let (localDate, offset) = determineLocalDateWithOffset(for: workout)
            
            if offset != 0 {
                correctionCount += 1
            }
            
            records.append(WorkoutRecord(from: workout, timezoneCorrectedDate: localDate, timezoneOffset: offset))
        }
        
        if correctionCount > 0 {
            print("[WorkoutProcessor] 🌍 Applied \(correctionCount) timezone corrections")
        }
        
        return records
    }
    
    // MARK: - Timezone Correction Logic
    
    /// Determine the local date where workout was performed WITH timezone offset
    /// Returns (correctedDate, timezoneOffsetInHours)
    /// Uses intelligent timezone detection for workouts at unusual hours
    private func determineLocalDateWithOffset(for workout: HKWorkout) -> (Date, Int) {
        let deviceDate = workout.endDate
        let deviceStartOfDay = calendar.startOfDay(for: deviceDate)
        let hour = calendar.component(.hour, from: deviceDate)
        
        // Most workouts are done in reasonable hours (6 AM - 10 PM)
        // These don't need timezone correction
        if hour >= 6 && hour <= 22 {
            return (deviceStartOfDay, 0)
        }
        
        // Workout at unusual hour (10 PM - 6 AM) - might be timezone shifted
        print("[WorkoutProcessor] 🌍 Workout at unusual hour \(hour):00, checking timezones...")
        
        // Try timezone offsets from -6 to +6 hours
        let possibleOffsets = [-6, -5, -4, -3, -2, -1, 1, 2, 3, 4, 5, 6]
        
        for offset in possibleOffsets {
            guard let correctedDate = calendar.date(byAdding: .hour, value: offset, to: deviceDate) else {
                continue
            }
            
            let correctedHour = calendar.component(.hour, from: correctedDate)
            
            // If this results in a reasonable workout time (6 AM - 10 PM local)
            if correctedHour >= 6 && correctedHour <= 22 {
                let correctedDay = calendar.startOfDay(for: correctedDate)
                
                // Only apply if it changes the day
                if correctedDay != deviceStartOfDay {
                    let formatter = DateFormatter()
                    formatter.dateFormat = "M/d"
                    print("[WorkoutProcessor] ✅ Timezone correction: \(formatter.string(from: deviceStartOfDay)) → \(formatter.string(from: correctedDay)) (offset: \(offset)h, \(correctedHour):00 local)")
                    
                    return (correctedDay, offset)
                }
            }
        }
        
        // No reasonable correction found, use device date
        return (deviceStartOfDay, 0)
    }
    
    // MARK: - Streak Calculation
    
    /// Calculate current streak from workout records
    /// This is pre-computed and cached in the index
    /// CRITICAL: Must match HealthKitManager.calculateRetroactiveStreak() logic exactly
    func calculateStreak(from records: [WorkoutRecord]) -> Int {
        // Group by date and calculate miles per day
        var milesByDate: [Date: Double] = [:]
        
        for record in records {
            let date = record.localDate
            milesByDate[date, default: 0] += record.distance
        }
        
        // Find days with qualifying workouts (>= 0.95 miles)
        let qualifyingDays = Set(milesByDate.filter { $0.value >= 0.95 }.keys)
        
        guard !qualifyingDays.isEmpty else {
            print("[WorkoutProcessor] No qualifying workout days found")
            return 0
        }
        
        print("[WorkoutProcessor] Found \(qualifyingDays.count) days with qualifying workouts")
        
        // Calculate streak from today backwards
        let today = calendar.startOfDay(for: Date())
        var currentStreak = 0
        
        // Check if TODAY has qualifying workout
        if qualifyingDays.contains(today) {
            currentStreak += 1
            print("[WorkoutProcessor] Today has qualifying workout - streak: \(currentStreak)")
        }
        
        // Check PREVIOUS days starting from yesterday
        guard var checkDate = calendar.date(byAdding: .day, value: -1, to: today) else {
            return currentStreak
        }
        
        while true {
            if qualifyingDays.contains(checkDate) {
                currentStreak += 1
                print("[WorkoutProcessor] Day has qualifying workout - streak: \(currentStreak)")
                
                // Move to previous day
                guard let previousDay = calendar.date(byAdding: .day, value: -1, to: checkDate) else {
                    break
                }
                checkDate = previousDay
            } else {
                print("[WorkoutProcessor] Day has NO qualifying workout - streak ends at: \(currentStreak)")
                break
            }
            
            // Safety limit
            if currentStreak > 1000 {
                print("[WorkoutProcessor] ⚠️ Streak exceeded 1000 days, stopping calculation")
                break
            }
        }
        
        print("[WorkoutProcessor] Final calculated streak: \(currentStreak)")
        return currentStreak
    }
    
    /// Get set of qualifying days (for quick lookup)
    func qualifyingDays(from records: [WorkoutRecord]) -> Set<Date> {
        var milesByDate: [Date: Double] = [:]
        
        for record in records {
            milesByDate[record.localDate, default: 0] += record.distance
        }
        
        return Set(milesByDate.filter { $0.value >= 0.95 }.keys)
    }
}

