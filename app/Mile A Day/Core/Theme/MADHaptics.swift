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
/// Generators are CACHED. Building a fresh `UIImpactFeedbackGenerator` per call
/// and firing it immediately — which this used to do — means the Taptic Engine
/// is cold every single time, and iOS spins it up before the tap is felt. That
/// lag reads as the whole UI being slow, most visibly on screens with several
/// taps in a row like the buddy-walk setup.
///
/// They are NOT held permanently warm. Calling `prepare()` after every fire
/// (which an earlier pass did) forces the engine to stay spun up, which Apple
/// warns costs battery — and when the system tears it down anyway, the pending
/// player logs `CoreHaptics -4805 "Player was not running"`. Instead:
/// `warmUp()` prepares once when a tap-heavy screen appears, and each
/// `impactOccurred()` naturally keeps the engine ready for the next tap that
/// follows within a second or two. First tap fast, subsequent taps fast, engine
/// free to idle down when the user stops.
enum MADHaptics {
    // No `nonisolated(unsafe)`: UIFeedbackGenerator subclasses are Sendable, so
    // a plain `static let` is already concurrency-safe.
    private static let lightImpact = UIImpactFeedbackGenerator(style: .light)
    private static let mediumImpact = UIImpactFeedbackGenerator(style: .medium)
    private static let heavyImpact = UIImpactFeedbackGenerator(style: .heavy)
    private static let notification = UINotificationFeedbackGenerator()

    static func tap() {
        lightImpact.impactOccurred()
    }

    static func action() {
        mediumImpact.impactOccurred()
    }

    static func emphasis() {
        heavyImpact.impactOccurred()
    }

    static func success() {
        notification.notificationOccurred(.success)
    }

    static func warning() {
        notification.notificationOccurred(.warning)
    }

    static func error() {
        notification.notificationOccurred(.error)
    }

    /// Warm the engine ahead of a screen the user is about to tap through, so
    /// even the FIRST tap is instant. Cheap, idempotent, and short-lived — iOS
    /// idles the engine back down on its own.
    static func warmUp() {
        lightImpact.prepare()
        mediumImpact.prepare()
    }
}
