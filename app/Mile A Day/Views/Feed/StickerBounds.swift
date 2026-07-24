import SwiftUI

/// Natural (untransformed) size of a sticker, reported up from a `GeometryReader`
/// placed UNDER any `scaleEffect`/`rotationEffect`. Because the probe sits below the
/// transforms, the value it reports is constant for a given style + config, so it
/// settles once instead of firing every gesture frame.
///
/// iOS 17 deployment target — `onGeometryChange` is iOS 18+, so measurement goes
/// through a preference key (same pattern as `RoadDateMarkerPreferenceKey`).
struct StickerNaturalSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        // A zero from a sibling/placeholder must never clobber a real measurement.
        if next != .zero { value = next }
    }
}

/// Position ranges that keep a sticker's ROTATED bounding box inside the canvas.
///
/// `StickerConfig.posXRange` / `posYRange` clamp the sticker's CENTER only, with no
/// idea how big the sticker is — so a wide style (`stacked` has `minWidth: 180`) at
/// max pinch (`StickerConfig.scaleRange` tops out at 1.9) dragged to the edge gets
/// chopped by the canvas `.clipped()`. Those static ranges stay exactly as they are:
/// they remain the coarse decode-time sanitizer for persisted values and the
/// fallback when nothing has been measured yet. THIS is the live, size-aware truth
/// that the editor actually clamps against.
enum StickerBounds {
    /// A few points of deliberate bleed so a sticker can kiss the canvas edge
    /// instead of always floating with a hairline gap.
    static let bleed: CGFloat = 4

    /// Pinch range narrowed so the sticker can never grow wider or taller than the
    /// canvas in the first place.
    ///
    /// `StickerConfig.scaleRange` tops out at 1.9, but a Card sticker's natural
    /// width is already ~210pt — 1.9× is ~399pt on a ~360pt canvas, i.e. bigger
    /// than the photo it sits on. No amount of position clamping can rescue that;
    /// the size itself has to be bounded. Measured against the UNROTATED footprint
    /// on purpose: deriving the cap from the rotated bounding box would make the
    /// sticker shrink as you twist it, which feels broken.
    static func scaleRange(natural: CGSize, canvas: CGSize) -> ClosedRange<CGFloat> {
        let base = StickerConfig.scaleRange
        guard natural.width > 0, natural.height > 0,
              canvas.width > 0, canvas.height > 0 else { return base }
        let fits = min((canvas.width - bleed * 2) / natural.width,
                       (canvas.height - bleed * 2) / natural.height)
        // Never let the cap fall below the floor — a sticker with no room at all
        // still needs a valid (degenerate) range rather than an inverted one.
        let upper = max(base.lowerBound, min(base.upperBound, fits))
        return base.lowerBound...upper
    }

    /// Legal normalized center ranges for a sticker of `natural` size drawn at
    /// `scale` and `rotation` on a `canvas`.
    static func ranges(
        natural: CGSize,
        scale: CGFloat,
        rotation: Angle,
        canvas: CGSize
    ) -> (x: ClosedRange<CGFloat>, y: ClosedRange<CGFloat>) {
        guard natural.width > 0, natural.height > 0,
              canvas.width > 0, canvas.height > 0 else {
            return (StickerConfig.posXRange, StickerConfig.posYRange)
        }

        // Axis-aligned bounding box of the rotated sticker.
        let c = abs(cos(rotation.radians))
        let s = abs(sin(rotation.radians))
        let boxW = (natural.width * c + natural.height * s) * scale
        let boxH = (natural.width * s + natural.height * c) * scale

        return (x: range(half: boxW / 2, span: canvas.width),
                y: range(half: boxH / 2, span: canvas.height))
    }

    /// One axis. A sticker larger than the canvas has no legal interval, so it is
    /// pinned dead center — handing `clamped(to:)` an inverted range would trap.
    private static func range(half: CGFloat, span: CGFloat) -> ClosedRange<CGFloat> {
        let margin = max(0, (half - bleed) / span)
        return margin >= 0.5 ? 0.5...0.5 : margin...(1 - margin)
    }
}
