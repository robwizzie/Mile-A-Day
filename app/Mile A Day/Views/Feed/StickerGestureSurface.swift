import SwiftUI
import UIKit
import Observation

// MARK: - Live edit
//
// How stickers move, Instagram-style: ONE gesture surface over the whole
// photo, not a gesture on each sticker. A drag starts on a sticker; a pinch
// or twist can start anywhere, with the fingers on or around it, and scales
// and turns the sticker about the point BETWEEN the fingers (so it stays
// under them, which is what made the old per-sticker pinch feel clunky: it
// scaled about the sticker's own centre, and needed both fingers on a
// sticker that might be smaller than two fingertips).
//
// UIKit recognizers rather than SwiftUI gestures because three of them have
// to run at once and hand over cleanly as fingers land and lift: a second
// finger joining a drag, a twist starting mid-pinch, one finger lifting off.
// Each hand-over REBASES (`StickerGestureSurface.Coordinator.rebase`), so
// nothing ever jumps.
//
// Nothing here is clamped differently live and on release: the transform the
// finger sees is the one that's committed, so a release never snaps.

/// The sticker under the fingers right now, mid-gesture. Observed only by the
/// sticker layers and the editing overlay, so a drag never re-renders the
/// rest of the composer.
@MainActor
@Observable
final class StickerLiveEdit {
    struct Live: Equatable {
        let id: UUID
        /// Normalized canvas centre.
        var center: CGPoint
        var scale: CGFloat
        var rotation: Angle
    }

    var live: Live?
    /// The finger, in canvas points, during a one-finger drag — what the
    /// bin is judged by.
    var finger: CGPoint?
    var overBin = false
    var snappedX = false
    var snappedY = false

    var isActive: Bool { live != nil }

    /// Every sticker's measured, untransformed size, for hit-testing and
    /// size-aware limits. Written by the layers as they lay out; read only
    /// by the gesture coordinator, never by a view body.
    @ObservationIgnored var naturalSizes: [UUID: CGSize] = [:]

    func reset() {
        live = nil
        finger = nil
        overBin = false
        snappedX = false
        snappedY = false
    }
}

/// Limits every sticker transform obeys, live and committed alike.
enum StickerLimits {
    /// Fingertip-sized at the small end, never more than twice the photo's
    /// width at the big end, and always inside StickerConfig.scaleRange.
    static func scaleRange(natural: CGSize?, canvas: CGSize) -> ClosedRange<CGFloat> {
        let base = StickerConfig.scaleRange
        guard let natural, natural.width > 0, natural.height > 0, canvas.width > 0 else { return base }
        let longest = max(natural.width, natural.height)
        let lower = max(base.lowerBound, 44 / longest)
        let upper = min(base.upperBound, canvas.width * 2 / longest)
        return lower <= upper ? lower...upper : lower...lower
    }

    /// The bin: above the bottom hint pill, centred — where every photo
    /// editor people already know puts it.
    static func binCenter(in canvas: CGSize) -> CGPoint {
        CGPoint(x: canvas.width / 2, y: canvas.height - 64)
    }
    static let binRadius: CGFloat = 24
    /// How near the finger has to come: wider than the bin, because you're
    /// aiming with a sticker under your thumb.
    static let binReach: CGFloat = 46
    /// Points within which the centre locks to the middle of the photo.
    static let centerSnap: CGFloat = 7
    /// Degrees within which a twist locks to straight.
    static let angleSnap: Double = 4
}

// MARK: - Surface

struct StickerGestureSurface: UIViewRepresentable {
    let stickers: [PlacedSticker]
    let canvas: CGSize
    let edit: StickerLiveEdit
    /// The sticker a pinch or twist that starts off every sticker applies to.
    let focusedId: UUID?
    let onBegin: (UUID) -> Void
    let onCommit: (UUID, CGPoint, CGFloat, Angle) -> Void
    let onRemove: (UUID) -> Void
    let onTap: (UUID) -> Void
    let onTapEmpty: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isMultipleTouchEnabled = true
        view.isAccessibilityElement = false

        let c = context.coordinator
        let pan = UIPanGestureRecognizer(target: c, action: #selector(Coordinator.transform(_:)))
        pan.maximumNumberOfTouches = 2
        let pinch = UIPinchGestureRecognizer(target: c, action: #selector(Coordinator.transform(_:)))
        let rotate = UIRotationGestureRecognizer(target: c, action: #selector(Coordinator.transform(_:)))
        let tap = UITapGestureRecognizer(target: c, action: #selector(Coordinator.tap(_:)))
        for g in [pan, pinch, rotate, tap] as [UIGestureRecognizer] {
            g.delegate = c
            view.addGestureRecognizer(g)
        }
        c.pan = pan
        c.pinch = pinch
        c.rotate = rotate
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        context.coordinator.parent = self
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: StickerGestureSurface
        weak var pan: UIPanGestureRecognizer?
        weak var pinch: UIPinchGestureRecognizer?
        weak var rotate: UIRotationGestureRecognizer?

        private struct Transform {
            var center: CGPoint      // canvas points
            var scale: CGFloat
            var rotation: CGFloat    // radians
        }

        private var target: UUID?
        private var base = Transform(center: .zero, scale: 1, rotation: 0)
        private var current = Transform(center: .zero, scale: 1, rotation: 0)
        /// The point the fingers were at when the gesture was last rebased.
        private var anchor: CGPoint = .zero
        private var touchCount = 0
        private var active = Set<ObjectIdentifier>()

        init(parent: StickerGestureSurface) { self.parent = parent }

        // MARK: Delegate

        func gestureRecognizer(_ g: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }

        /// A transform only starts on a sticker (or, for a pinch or twist,
        /// the focused one), so a drag across empty photo does nothing and
        /// the composer's scroll and the inset keep their touches.
        func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
            if g is UITapGestureRecognizer { return true }
            if target != nil { return true }
            return pickTarget(for: g) != nil
        }

        // MARK: Tap

        @objc func tap(_ g: UITapGestureRecognizer) {
            guard g.state == .ended, target == nil else { return }
            if let id = hit(g.location(in: g.view)) {
                parent.onTap(id)
            } else {
                parent.onTapEmpty()
            }
        }

        // MARK: Transform

        @objc func transform(_ g: UIGestureRecognizer) {
            switch g.state {
            case .began:
                if target == nil {
                    guard let id = pickTarget(for: g),
                          let sticker = parent.stickers.first(where: { $0.id == id }) else { return }
                    target = id
                    base = Transform(
                        center: CGPoint(x: sticker.pos.x * parent.canvas.width,
                                        y: sticker.pos.y * parent.canvas.height),
                        scale: sticker.scale,
                        rotation: CGFloat(sticker.rotation.radians))
                    current = base
                    parent.onBegin(id)
                }
                active.insert(ObjectIdentifier(g))
                rebase()
                step()
            case .changed:
                guard target != nil else { return }
                if let pan, active.contains(ObjectIdentifier(pan)), pan.numberOfTouches != touchCount {
                    // A finger landed or lifted: carry on from where the
                    // sticker IS, about wherever the fingers are now.
                    rebase()
                }
                step()
            case .ended, .cancelled, .failed:
                guard target != nil else { return }
                active.remove(ObjectIdentifier(g))
                if active.isEmpty {
                    finish()
                } else {
                    rebase()
                }
            default:
                break
            }
        }

        private func isActive(_ g: UIGestureRecognizer?) -> Bool {
            guard let g else { return false }
            return active.contains(ObjectIdentifier(g))
        }

        /// Fold everything so far into `base` and restart the deltas from the
        /// fingers' current position. Called on every hand-over.
        private func rebase() {
            base = current
            anchor = fingerCentroid()
            if let view = pan?.view { pan?.setTranslation(.zero, in: view) }
            pinch?.scale = 1
            rotate?.rotation = 0
            touchCount = pan?.numberOfTouches ?? 0
        }

        private func fingerCentroid() -> CGPoint {
            for g in [pan, pinch, rotate] as [UIGestureRecognizer?] {
                if let g, isActive(g), g.numberOfTouches > 0, let view = g.view {
                    return g.location(in: view)
                }
            }
            return current.center
        }

        private func step() {
            guard let id = target, let view = pan?.view ?? pinch?.view else { return }
            let canvas = parent.canvas
            let translation = isActive(pan) ? (pan?.translation(in: view) ?? .zero) : .zero
            let rawScale = isActive(pinch) ? (pinch?.scale ?? 1) : 1
            let twist = isActive(rotate) ? (rotate?.rotation ?? 0) : 0

            let range = StickerLimits.scaleRange(natural: parent.edit.naturalSizes[id], canvas: canvas)
            let scale = (base.scale * rawScale).clamped(to: range)
            let s = base.scale > 0 ? scale / base.scale : 1

            // Scale and turn about the anchor, then follow the fingers.
            let v = CGPoint(x: base.center.x - anchor.x, y: base.center.y - anchor.y)
            let rotated = CGPoint(x: (v.x * cos(twist) - v.y * sin(twist)) * s,
                                  y: (v.x * sin(twist) + v.y * cos(twist)) * s)
            var center = CGPoint(x: anchor.x + translation.x + rotated.x,
                                 y: anchor.y + translation.y + rotated.y)

            // Straight up (or any quarter turn) within a few degrees.
            var rotation = base.rotation + twist
            let quarter = CGFloat.pi / 2
            let nearest = (rotation / quarter).rounded() * quarter
            let angleLocked = abs(rotation - nearest) < CGFloat(StickerLimits.angleSnap * .pi / 180)
            if angleLocked { rotation = nearest }

            // The photo's centre lines.
            let lockX = abs(center.x - canvas.width / 2) < StickerLimits.centerSnap
            let lockY = abs(center.y - canvas.height / 2) < StickerLimits.centerSnap
            if lockX { center.x = canvas.width / 2 }
            if lockY { center.y = canvas.height / 2 }

            // The centre stays on the photo; the sticker may hang off it.
            center.x = center.x.clamped(to: 0...max(canvas.width, 1))
            center.y = center.y.clamped(to: 0...max(canvas.height, 1))

            current = Transform(center: center, scale: scale, rotation: rotation)

            let edit = parent.edit
            if lockX != edit.snappedX { edit.snappedX = lockX; if lockX { MADHaptics.tap() } }
            if lockY != edit.snappedY { edit.snappedY = lockY; if lockY { MADHaptics.tap() } }
            if angleLocked, isActive(rotate), abs(twist) > 0.03, abs(base.rotation - nearest) > 0.001 {
                MADHaptics.tap()
            }

            // The bin is for one-finger drags: two fingers are resizing.
            if isActive(pan), let pan, pan.numberOfTouches == 1 {
                let finger = pan.location(in: view)
                edit.finger = finger
                let bin = StickerLimits.binCenter(in: canvas)
                let over = hypot(finger.x - bin.x, finger.y - bin.y) < StickerLimits.binReach
                if over != edit.overBin { edit.overBin = over; if over { MADHaptics.tap() } }
            } else {
                edit.finger = nil
                edit.overBin = false
            }

            edit.live = StickerLiveEdit.Live(
                id: id,
                center: CGPoint(x: center.x / max(canvas.width, 1), y: center.y / max(canvas.height, 1)),
                scale: scale,
                rotation: .radians(Double(rotation)))
        }

        private func finish() {
            guard let id = target else { return }
            let edit = parent.edit
            let canvas = parent.canvas
            if edit.overBin {
                MADHaptics.success()
                parent.onRemove(id)
            } else {
                parent.onCommit(
                    id,
                    CGPoint(x: current.center.x / max(canvas.width, 1),
                            y: current.center.y / max(canvas.height, 1)),
                    current.scale,
                    .radians(Double(current.rotation)))
            }
            // Same turn as the commit, so the layer swaps the live transform
            // for an identical committed one without a frame in between.
            edit.reset()
            target = nil
            active.removeAll()
        }

        // MARK: Hit-testing

        private func pickTarget(for g: UIGestureRecognizer) -> UUID? {
            guard let view = g.view else { return nil }
            var points = [g.location(in: view)]
            for i in 0..<g.numberOfTouches { points.append(g.location(ofTouch: i, in: view)) }
            for p in points { if let id = hit(p) { return id } }
            // A pinch or twist off every sticker works the focused one, the
            // way Instagram lets you resize with your fingers beside it.
            if !(g is UIPanGestureRecognizer), let focused = parent.focusedId,
               parent.stickers.contains(where: { $0.id == focused }) {
                return focused
            }
            return nil
        }

        /// The TOPMOST sticker whose (rotated, scaled) rectangle contains
        /// `point`, with a fingertip of slack round it.
        private func hit(_ point: CGPoint) -> UUID? {
            let canvas = parent.canvas
            for sticker in parent.stickers.reversed() {
                let size = parent.edit.naturalSizes[sticker.id] ?? CGSize(width: 120, height: 60)
                let center = CGPoint(x: sticker.pos.x * canvas.width, y: sticker.pos.y * canvas.height)
                let dx = point.x - center.x, dy = point.y - center.y
                let a = CGFloat(-sticker.rotation.radians)
                let lx = (dx * cos(a) - dy * sin(a)) / max(sticker.scale, 0.01)
                let ly = (dx * sin(a) + dy * cos(a)) / max(sticker.scale, 0.01)
                let slack = 14 / max(sticker.scale, 0.01)
                if abs(lx) <= size.width / 2 + slack, abs(ly) <= size.height / 2 + slack {
                    return sticker.id
                }
            }
            return nil
        }
    }
}

// MARK: - Overlay

/// The centre guides and the bin, drawn once over the photo while a sticker
/// is moving. Never hit-testable.
struct StickerEditingOverlay: View {
    let edit: StickerLiveEdit
    let canvas: CGSize

    var body: some View {
        ZStack {
            if edit.isActive {
                if edit.snappedX {
                    Rectangle().fill(MADTheme.Colors.madRed)
                        .frame(width: 1, height: canvas.height)
                        .position(x: canvas.width / 2, y: canvas.height / 2)
                }
                if edit.snappedY {
                    Rectangle().fill(MADTheme.Colors.madRed)
                        .frame(width: canvas.width, height: 1)
                        .position(x: canvas.width / 2, y: canvas.height / 2)
                }
            }
            if edit.finger != nil {
                let hot = edit.overBin
                ZStack {
                    Circle().fill(hot ? MADTheme.Colors.error : Color.black.opacity(0.55))
                    Circle().strokeBorder(Color.white.opacity(hot ? 0 : 0.7), lineWidth: 1.5)
                    Image(systemName: "trash.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                }
                .frame(width: StickerLimits.binRadius * 2, height: StickerLimits.binRadius * 2)
                .scaleEffect(hot ? 1.18 : 1)
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: hot)
                .position(StickerLimits.binCenter(in: canvas))
                .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
        .frame(width: canvas.width, height: canvas.height)
        .animation(.easeOut(duration: 0.15), value: edit.finger != nil)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Fades the photo's own controls out while a sticker is being moved, the
/// way Instagram clears its chrome so you can see where you're putting it.
struct HiddenWhileEditing: ViewModifier {
    let edit: StickerLiveEdit

    func body(content: Content) -> some View {
        content
            .opacity(edit.isActive ? 0 : 1)
            .animation(.easeOut(duration: 0.15), value: edit.isActive)
            .allowsHitTesting(!edit.isActive)
    }
}
