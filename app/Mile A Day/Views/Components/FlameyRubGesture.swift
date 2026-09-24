import SwiftUI
import UIKit

extension View {
    /// Fires `onRub` when a finger rubs back and forth across this view —
    /// a horizontal-DOMINANT drag that reverses direction twice. Built so the
    /// dashboard around it keeps working:
    ///   - it never begins on a vertical drag, so the page scrolls as ever
    ///     (iOS 18+: a pan recognizer whose `gestureRecognizerShouldBegin`
    ///     refuses anything not clearly sideways; iOS 17: a SIMULTANEOUS drag,
    ///     which observes without claiming the touch);
    ///   - taps and long-presses never move far enough to start it;
    ///   - it is attached to his hit area only.
    func flameyRubGesture(_ onRub: @escaping () -> Void) -> some View {
        modifier(FlameyRubModifier(onRub: onRub))
    }
}

/// Counts direction reversals of a horizontal drag. A leg counts once it has
/// travelled `minLeg` points; vertical travel past `maxVertical` disqualifies
/// the whole gesture (that's a scroll that started sideways).
final class FlameyRubTracker {
    private let minLeg: CGFloat = 10
    private let maxVertical: CGFloat = 36
    private var legStartX: CGFloat = 0
    private var direction: CGFloat = 0
    private var reversals = 0
    private var fired = false
    private var disqualified = false

    func reset() {
        legStartX = 0
        direction = 0
        reversals = 0
        fired = false
        disqualified = false
    }

    /// Feed cumulative translation; returns true exactly once per gesture.
    func update(x: CGFloat, y: CGFloat) -> Bool {
        guard !fired, !disqualified else { return false }
        if abs(y) > maxVertical { disqualified = true; return false }
        let delta = x - legStartX
        guard abs(delta) >= minLeg else { return false }
        let sign: CGFloat = delta > 0 ? 1 : -1
        if direction != 0, sign != direction { reversals += 1 }
        direction = sign
        legStartX = x
        if reversals >= 2 {
            fired = true
            return true
        }
        return false
    }
}

private struct FlameyRubModifier: ViewModifier {
    let onRub: () -> Void
    @State private var tracker = FlameyRubTracker()

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.gesture(FlameyRubRecognizer(onRub: onRub))
        } else {
            content.simultaneousGesture(
                DragGesture(minimumDistance: 12)
                    .onChanged { value in
                        if tracker.update(x: value.translation.width, y: value.translation.height) { onRub() }
                    }
                    .onEnded { _ in tracker.reset() }
            )
        }
    }
}

@available(iOS 18.0, *)
private struct FlameyRubRecognizer: UIGestureRecognizerRepresentable {
    let onRub: () -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator()
    }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer()
        pan.delegate = context.coordinator
        pan.maximumNumberOfTouches = 1
        return pan
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        let tracker = context.coordinator.tracker
        switch recognizer.state {
        case .began:
            tracker.reset()
        case .changed:
            let t = recognizer.translation(in: recognizer.view)
            if tracker.update(x: t.x, y: t.y) { onRub() }
        default:
            tracker.reset()
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        let tracker = FlameyRubTracker()

        /// Only a clearly sideways drag may begin — a vertical one fails
        /// here and belongs to the scroll view.
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return false }
            let v = pan.velocity(in: pan.view)
            return abs(v.x) > abs(v.y) * 1.5
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }
    }
}
