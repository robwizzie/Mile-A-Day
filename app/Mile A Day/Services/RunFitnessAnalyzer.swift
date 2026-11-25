import Foundation

/// Computes the compact Run Plans fitness profile from HealthKit on the phone.
@MainActor
final class RunFitnessAnalyzer {
    static let shared = RunFitnessAnalyzer()

    func refreshIfStale() {}
    func invalidate() {}
}
