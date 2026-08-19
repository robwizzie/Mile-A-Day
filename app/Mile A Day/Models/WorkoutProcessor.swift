//
//  WorkoutProcessor.swift
//  Mile A Day
//
//  Created by AI Assistant
//  Processes workouts and applies timezone corrections ONCE
//

import Foundation
import HealthKit

#if !os(watchOS)

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

        for workout in workouts {
            // Skip workouts the user deleted in-app — Health still has them, but
            // they must not count toward streaks, totals, or the calendar.
            if DeletedWorkoutRegistry.contains(workout.uuid.uuidString) { continue }

            let (localDate, offset) = determineLocalDateWithOffset(for: workout)
            records.append(WorkoutRecord(from: workout, timezoneCorrectedDate: localDate, timezoneOffset: offset))
        }

        return records
    }
    
    // MARK: - Local Day

    /// The local calendar day a workout belongs to.
    ///
    /// This is `Calendar.current.startOfDay(for: workout.startDate)` and nothing
    /// else. `HKWorkout.startDate` is an absolute instant and `Calendar.current`
    /// already renders it in the device's real timezone, so there is nothing to
    /// "correct" — and it is the SAME rule the server files `local_date` under
    /// (start date, user timezone; see WorkoutSyncService's `localDate`). Client
    /// and server disagreeing about which day a walk happened on is what makes a
    /// day read empty while the streak that depends on it stays alive.
    ///
    /// What used to be here was a heuristic that assumed nobody works out
    /// between 10 PM and 6 AM, and "corrected" any workout at those hours by
    /// brute-forcing offsets from -6 to +6 until one landed in "reasonable"
    /// hours AND changed the calendar day. It tried -6 first, so a genuine
    /// 2:01 AM walk became 8:01 PM *the previous day* — every late-night mile
    /// silently filed itself under yesterday, blanking the day it was actually
    /// walked. It was never timezone logic: no travel, no `HKMetadataKeyTimeZone`
    /// and no location was ever consulted, and a real timezone change is already
    /// reflected in `Calendar.current`. The second return value stays for the
    /// persisted `WorkoutRecord.timezoneOffset` field and is always 0.
    private func determineLocalDateWithOffset(for workout: HKWorkout) -> (Date, Int) {
        (calendar.startOfDay(for: workout.startDate), 0)
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
        
        // Find days with qualifying workouts (>= 0.95 miles), plus any
        // token-covered days from the server (Streak Save / Double Down /
        // Assist) — a rescued day has no workout, so without the union this
        // walk would break there and diverge from the backend. Empty store
        // (feature off) leaves behavior identical.
        let qualifyingDays = Set(milesByDate.filter { $0.value >= 0.95 }.keys)
            .union(StreakCoverageStore.coveredDays)

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
#endif

