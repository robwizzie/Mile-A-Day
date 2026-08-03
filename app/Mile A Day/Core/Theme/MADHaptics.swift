import UIKit

/// The app's haptic vocabulary — one meaning per pattern so interactions feel
/// consistent everywhere:
/// - `tap`      → light impact: navigation, toggles, pickers, expanding rows
/// - `action`   → medium impact: doing something meaningful (hype, share, snap)
/// - `emphasis` → heavy impact: big rhythm beats (countdowns, landings)
/// - `success`  → something completed or was confirmed
/// - `warning`  → blocked, rate-limited, or needs attention
///
/// Rhythm-critical sequences that pre-`prepare()` their generators (splash,
/// the goal celebration) keep their own instances; everything else goes
/// through here.
///
/// Generators are CACHED AND KEPT WARM. Building a fresh
/// `UIImpactFeedbackGenerator` per call and firing it immediately — which this
/// used to do — means the Taptic Engine is cold every single time, and iOS
/// spins it up before the tap is felt. That lag reads as the whole UI being
/// slow to respond, most visibly on screens with several taps in a row like the
/// buddy-walk setup. `prepare()` after each fire leaves the engine warm for the
/// next one (iOS keeps it ready for a few seconds, then powers down on its own).
enum MADHaptics {
    // UIFeedbackGenerator is documented as main-thread-only and every caller
    // here is a UI action, so `nonisolated(unsafe)` is accurate rather than a
    // shortcut: it keeps this callable from existing call sites without forcing
    // an isolation change through the whole app.
    nonisolated(unsafe) private static let lightImpact: UIImpactFeedbackGenerator = {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        return generator
    }()

    nonisolated(unsafe) private static let mediumImpact: UIImpactFeedbackGenerator = {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.prepare()
        return generator
    }()

    nonisolated(unsafe) private static let heavyImpact: UIImpactFeedbackGenerator = {
        let generator = UIImpactFeedbackGenerator(style: .heavy)
        generator.prepare()
        return generator
    }()

    nonisolated(unsafe) private static let notification = UINotificationFeedbackGenerator()

    static func tap() {
        lightImpact.impactOccurred()
        lightImpact.prepare()
    }

    static func action() {
        mediumImpact.impactOccurred()
        mediumImpact.prepare()
    }

    static func emphasis() {
        heavyImpact.impactOccurred()
        heavyImpact.prepare()
    }

    static func success() {
        notification.notificationOccurred(.success)
        notification.prepare()
    }

    static func warning() {
        notification.notificationOccurred(.warning)
        notification.prepare()
    }

    static func error() {
        notification.notificationOccurred(.error)
        notification.prepare()
    }

    /// Warm the engine ahead of a screen the user is about to tap through, so
    /// even the FIRST tap is instant. Cheap and idempotent.
    static func warmUp() {
        lightImpact.prepare()
        mediumImpact.prepare()
    }
}
