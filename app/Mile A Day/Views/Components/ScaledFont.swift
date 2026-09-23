//
//  ScaledFont.swift
//  Mile A Day
//
//  Dynamic Type for a design system written in fixed point sizes.
//

import SwiftUI
import UIKit

// MARK: - Scaling

/// Scales a fixed design size the way `@ScaledMetric` does, but against a
/// Dynamic Type size that honours `madTypeCap`.
///
/// Why not `@ScaledMetric` directly: its only ceiling is
/// `.dynamicTypeSize(...X)`, and that REWRITES the environment for the whole
/// subtree — every `.font(.body)` label inside (which scales to AX5 today) and
/// every sheet the subtree presents (sheets inherit the environment) would be
/// capped along with the one dense row that needed it. `madTypeCap` only
/// limits text that opted in through `madFont`/`MADScaledMetric`, so capping a
/// fixed-geometry hero can never take scaling away from anything else.
///
/// At the DEFAULT size (`.large`) `UIFontMetrics` returns the base value
/// exactly, so every conversion is pixel-identical for anyone who never
/// touched the setting — the invariant the whole rollout rests on.
enum MADTypeScale {
    /// The text style a fixed design size scales WITH. Apple's styles grow at
    /// different rates (`.caption2` more than doubles by AX5, `.largeTitle`
    /// gains far less), so a 10pt label and a 34pt number must not share one
    /// factor. Deriving it from the size means a converted call site scales
    /// like the system style it most resembles without anyone picking one.
    static func style(forDesignSize size: CGFloat) -> Font.TextStyle {
        switch size {
        case ..<11.5: return .caption2
        case ..<12.5: return .caption
        case ..<13.5: return .footnote
        case ..<15.5: return .subheadline
        case ..<16.5: return .callout
        case ..<17.5: return .body
        case ..<20.5: return .title3
        case ..<24.5: return .title2
        case ..<30.5: return .title
        default: return .largeTitle
        }
    }

    static func scaled(
        _ base: CGFloat,
        relativeTo style: Font.TextStyle,
        size: DynamicTypeSize,
        cap: DynamicTypeSize
    ) -> CGFloat {
        let effective = min(size, cap)
        guard effective != .large else { return base }
        let traits = UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(effective))
        return UIFontMetrics(forTextStyle: uiStyle(style)).scaledValue(for: base, compatibleWith: traits)
    }

    private static func uiStyle(_ style: Font.TextStyle) -> UIFont.TextStyle {
        switch style {
        case .largeTitle: return .largeTitle
        case .title: return .title1
        case .title2: return .title2
        case .title3: return .title3
        case .headline: return .headline
        case .subheadline: return .subheadline
        case .callout: return .callout
        case .footnote: return .footnote
        case .caption: return .caption1
        case .caption2: return .caption2
        default: return .body
        }
    }
}

// MARK: - Surface caps

private struct MADTypeCapKey: EnvironmentKey {
    static let defaultValue: DynamicTypeSize = .accessibility5
}

extension EnvironmentValues {
    /// The largest Dynamic Type size `madFont` text in this subtree will
    /// follow. Only ever tightened (see `madTypeCap(_:)`).
    var madTypeCap: DynamicTypeSize {
        get { self[MADTypeCapKey.self] }
        set { self[MADTypeCapKey.self] = newValue }
    }
}

/// Named ceilings, so every surface states its cap the same way and a later
/// tuning pass can grep for them.
extension DynamicTypeSize {
    /// Fixed-geometry chrome: the dashboard heroes' stat frames, half-width
    /// tiles, the tracker's control bar. Text grows ~15–35% at most.
    static let madFixedChromeCap: DynamicTypeSize = .xxLarge
    /// Cards whose rows wrap or re-arrange (feed cards, dashboard cards below
    /// the hero, inbox rows). Text grows up to ~1.8x at the small end.
    static let madCardCap: DynamicTypeSize = .accessibility2
    /// Plain lists of text (Settings): grows as far as a list honestly holds.
    static let madListCap: DynamicTypeSize = .accessibility3
}

extension View {
    /// Caps how far `madFont` text in this subtree grows. Nested caps take
    /// the tighter one. Leaves system text styles and presented sheets alone
    /// (unlike `.dynamicTypeSize(...)`) — but a sheet whose own text uses
    /// `madFont` DOES inherit the cap, so attach it BELOW any `.sheet` /
    /// `.fullScreenCover` on the same node where you can.
    func madTypeCap(_ cap: DynamicTypeSize) -> some View {
        transformEnvironment(\.madTypeCap) { current in
            current = min(current, cap)
        }
    }
}

// MARK: - Font

/// `.font(.system(size:weight:design:))`, but the size follows the user's
/// Dynamic Type setting.
///
/// Two ceilings, and they compose: `maxScale` caps THIS text at
/// `size * maxScale` (a glyph inside a fixed circle, a number in a
/// fixed-height tile), and `madTypeCap` caps a whole surface.
///
/// Never shrinks below the design size: the design sizes are already small
/// (9–11pt labels are common) and the smaller settings would take them past
/// legible.
///
/// NEVER use this on anything rendered into an image (`ImageRenderer`, share
/// cards, the baked route card): a picture must not depend on the poster's
/// text-size setting. Those keep `.font(.system(size:))`.
struct MADScaledFont: ViewModifier {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.madTypeCap) private var cap

    let size: CGFloat
    let weight: Font.Weight?
    let design: Font.Design?
    let textStyle: Font.TextStyle?
    let maxScale: CGFloat
    let monospacedDigit: Bool

    private var resolvedSize: CGFloat {
        let scaled = MADTypeScale.scaled(
            size,
            relativeTo: textStyle ?? MADTypeScale.style(forDesignSize: size),
            size: dynamicTypeSize,
            cap: cap
        )
        return min(max(scaled, size), size * max(maxScale, 1))
    }

    func body(content: Content) -> some View {
        let font = Font.system(size: resolvedSize, weight: weight, design: design)
        return content.font(monospacedDigit ? font.monospacedDigit() : font)
    }
}

extension View {
    /// Scaled replacement for `.font(.system(size:weight:design:))`. See
    /// `MADScaledFont`. `maxScale` defaults to 2 — past that a fixed-size
    /// design stops being the same design; tighten it per use where the
    /// geometry around the text is fixed.
    func madFont(
        size: CGFloat,
        weight: Font.Weight? = nil,
        design: Font.Design? = nil,
        relativeTo textStyle: Font.TextStyle? = nil,
        maxScale: CGFloat = 2,
        monospacedDigit: Bool = false
    ) -> some View {
        modifier(MADScaledFont(
            size: size,
            weight: weight,
            design: design,
            textStyle: textStyle,
            maxScale: maxScale,
            monospacedDigit: monospacedDigit
        ))
    }
}

// MARK: - Metric

/// `@ScaledMetric` that honours `madTypeCap` — for a FRAME that has to grow
/// with the `madFont` text inside it (a fixed-height tile, a hero's stat
/// frame). Base value exactly at the default size; never below it.
@propertyWrapper
struct MADScaledMetric: DynamicProperty {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.madTypeCap) private var cap

    private let base: CGFloat
    private let textStyle: Font.TextStyle
    private let maxScale: CGFloat

    /// Note the cap is read from the environment the DECLARING view sits in,
    /// so a `madTypeCap` applied inside that view's own body doesn't reach
    /// it — `maxScale` (default 2, matching `madFont`) is the backstop.
    init(wrappedValue: CGFloat, relativeTo textStyle: Font.TextStyle = .body, maxScale: CGFloat = 2) {
        self.base = wrappedValue
        self.textStyle = textStyle
        self.maxScale = maxScale
    }

    var wrappedValue: CGFloat {
        let scaled = MADTypeScale.scaled(base, relativeTo: textStyle, size: dynamicTypeSize, cap: cap)
        return min(max(base, scaled), base * max(maxScale, 1))
    }
}
