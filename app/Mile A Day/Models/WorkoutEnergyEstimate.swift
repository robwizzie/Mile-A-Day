import Foundation
import HealthKit

/// Active energy for a phone-tracked workout.
///
/// `HKWorkoutBuilder` computes nothing on its own — it only aggregates the
/// samples handed to it, and the tracker hands it distance. (The Watch gets
/// real calories because `HKLiveWorkoutDataSource` collects them from sensors
/// this app doesn't have.) So an in-app walk arrived in Apple Fitness with a
/// blank calorie figure, sitting next to Watch workouts that show one.
///
/// The estimate is the ACSM level-ground metabolic equations, minus rest:
///
///     walking   VO₂ = 0.1 · S + 3.5        running   VO₂ = 0.2 · S + 3.5
///
/// (mL O₂/kg/min, S in m/min. The 3.5 is resting metabolism, which is exactly
/// what ACTIVE energy excludes, so it drops out.) At 5 kcal per litre of O₂ the
/// speed term cancels against duration and the whole thing collapses to
/// distance × mass:
///
///     kcal = 0.005 · c · metres · kg          c = 0.1 walking, 0.2 running
///
/// Worked, for a 155 lb (70.3 kg) person covering one mile: ~57 kcal walking at
/// 3 mph, ~113 kcal running at 6 mph — the familiar rules of thumb, and close
/// to what a Watch measures over the same mile.
///
/// Deliberately NOT modelled: grade, wind, heart rate, running economy. Each
/// needs data this workout doesn't carry, and none of them move the number as
/// much as body mass does.
enum WorkoutEnergyEstimate {
    /// ACSM's two equations are each invalid inside the gap between them
    /// (walking holds to ~3.7 mph, running from ~5.0 mph). Blending across it
    /// beats picking a side: a 4.5 mph jog is honestly neither, and a hard
    /// threshold would make one tenth of a mph worth a doubling in calories.
    private static let walkingCeilingMetersPerMinute = 99.2   // 3.7 mph
    private static let runningFloorMetersPerMinute = 134.1    // 5.0 mph

    /// Health holds no weight for plenty of people — it is part of no required
    /// setup — and a walk showing no calories at all is worse than one showing
    /// a typical-adult estimate. 70.3 kg is 155 lb.
    static let fallbackBodyMassKilograms = 70.3

    /// Active kilocalories, or nil when there is nothing to base one on.
    ///
    /// `activeSeconds` must be pause-excluded (the tracker's `recapDuration`),
    /// matching the duration HealthKit derives from the workout's pause events
    /// — a wall-clock figure would make a walk with a long break read as slow
    /// enough to switch equations.
    static func activeKilocalories(
        meters: Double,
        activeSeconds: TimeInterval,
        bodyMassKilograms: Double?
    ) -> Double? {
        guard meters > 0, activeSeconds > 0 else { return nil }
        let kilograms = bodyMassKilograms.map { $0 > 0 ? $0 : fallbackBodyMassKilograms }
            ?? fallbackBodyMassKilograms
        let metersPerMinute = meters / (activeSeconds / 60)
        let gapPosition = (metersPerMinute - walkingCeilingMetersPerMinute)
            / (runningFloorMetersPerMinute - walkingCeilingMetersPerMinute)
        let blend = min(max(gapPosition, 0), 1)
        let coefficient = 0.1 + 0.1 * blend
        return 0.005 * coefficient * meters * kilograms
    }

    /// The sample to hand `HKWorkoutBuilder`, spanning the whole workout the way
    /// the distance sample does. One sample, not one per pause segment: the
    /// builder sums them either way, and Apple Fitness reads the total.
    static func sample(
        meters: Double,
        activeSeconds: TimeInterval,
        bodyMassKilograms: Double?,
        start: Date,
        end: Date
    ) -> HKQuantitySample? {
        guard end > start,
              let energyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned),
              let kilocalories = activeKilocalories(
                  meters: meters,
                  activeSeconds: activeSeconds,
                  bodyMassKilograms: bodyMassKilograms
              ),
              kilocalories > 0,
              // The sample shares an `add` batch with distance, and a batch is
              // rejected as a unit — so a NaN or infinity reaching HealthKit
              // would cost the walk its distance, not just its calories.
              kilocalories.isFinite
        else { return nil }

        return HKQuantitySample(
            type: energyType,
            quantity: HKQuantity(unit: .kilocalorie(), doubleValue: kilocalories),
            start: start,
            end: end
        )
    }
}
