import Foundation

/// Run Plans v2 AI Coach on Apple's models (Private Cloud Compute for plan
/// decisions, on-device for short replies). Filled in below the interface.
@MainActor
final class AppleCoach {
    static let shared = AppleCoach()

    /// True when this phone can run Apple's model right now.
    static var isAvailable: Bool { false }

    /// After a run / first open / nightly: look at the plan, propose changes.
    func runAdjustPass(trigger: RunPlanV2AICallTrigger) async {}
}
