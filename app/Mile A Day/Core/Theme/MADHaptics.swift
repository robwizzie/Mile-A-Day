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
enum MADHaptics {
    static func tap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func action() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    static func emphasis() {
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
    }

    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    static func error() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }
}
