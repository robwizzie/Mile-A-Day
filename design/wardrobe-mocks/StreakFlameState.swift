import SwiftUI

// Widget-target copy of the dashboard's flame burn-down math, so the widget
// flame shrinks and recolors in lock-step with the in-app hero.
// KEEP IN SYNC with app/Mile A Day/Views/Components/StreakFlameState.swift.

enum StreakFlameClock {
    static let dayLength: TimeInterval = 24 * 60 * 60

    /// Perceptual size of a burning flame — a near-linear descent that tracks
    /// the fraction of the day remaining. Mirrors the dashboard exactly.
    static func flameScale(vigor: Double) -> CGFloat {
        let v = min(max(vigor, 0), 1)
        let minScale = 0.08
        return CGFloat(minScale + (1 - minScale) * pow(v, 0.9))
    }
}

/// Continuous flame coloring: rich golden-orange with a full day ahead,
/// deepening toward starving ember-red as midnight nears. Always fully
/// saturated and opaque — a live flame only shrinks, never washes out.
enum FlamePalette {
    static func lerp(_ a: (Double, Double, Double), _ b: (Double, Double, Double), _ t: Double) -> Color {
        let clamped = min(max(t, 0), 1)
        return Color(
            red: a.0 + (b.0 - a.0) * clamped,
            green: a.1 + (b.1 - a.1) * clamped,
            blue: a.2 + (b.2 - a.2) * clamped
        )
    }

    static func outer(vigor: CGFloat) -> [Color] {
        let t = 1 - Double(min(max(vigor, 0), 1))
        return [
            lerp((1.00, 0.95, 0.32), (1.00, 0.66, 0.16), t),
            lerp((1.00, 0.58, 0.00), (0.97, 0.34, 0.10), t),
            lerp((1.00, 0.22, 0.10), (0.55, 0.08, 0.10), t)
        ]
    }

    static func inner(vigor: CGFloat) -> [Color] {
        let t = 1 - Double(min(max(vigor, 0), 1))
        return [
            lerp((1.00, 0.98, 0.44), (1.00, 0.78, 0.26), t),
            lerp((1.00, 0.65, 0.12), (0.92, 0.32, 0.10), t)
        ]
    }
}
