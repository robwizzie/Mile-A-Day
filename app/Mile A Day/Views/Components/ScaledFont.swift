//
//  ScaledFont.swift
//  Mile A Day
//
//  Dynamic Type for a design system written in fixed point sizes.
//

import SwiftUI

/// The text style a fixed design size scales WITH.
///
/// Apple's text styles grow at different rates — `.caption2` roughly doubles
/// by `.accessibility5` while `.largeTitle` gains far less — so a 10pt label
/// and a 34pt number must not be multiplied by the same factor. Deriving the
/// style from the size means a converted call site scales like the system
/// style it most resembles without anyone having to pick one.
enum MADTextStyleMapping {
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
}

/// `.font(.system(size:weight:design:))`, but the size follows the user's
/// Dynamic Type setting.
///
/// At the DEFAULT text size (`.large`) `@ScaledMetric` returns its base value
/// exactly, so converting a call site is pixel-identical for everyone who
/// never touched the setting — that is the invariant every conversion rests on.
///
/// Two ceilings, and they compose:
/// - `maxScale` caps THIS text at `size * maxScale` — for a glyph inside a
///   fixed circle, or a number in a fixed-height tile.
/// - `.dynamicTypeSize(...DynamicTypeSize.xxxLarge)` on a CONTAINER caps
///   everything inside it (the scaled metric reads the environment), which is
///   the right tool for a dense surface with fixed geometry (the dashboard
///   heroes' 258pt stat frame, the 168pt tiles).
///
/// Never shrinks below the design size (`minScale` 1): the design sizes are
/// already small (9–11pt labels are common) and the smaller settings would
/// take them past legible.
///
/// NEVER use this on anything rendered into an image (`ImageRenderer`, share
/// cards, the baked route card): a picture must not depend on the poster's
/// text-size setting. Those keep `.font(.system(size:))`.
struct MADScaledFont: ViewModifier {
    @ScaledMetric private var scaled: CGFloat
    private let base: CGFloat
    private let weight: Font.Weight?
    private let design: Font.Design?
    private let maxScale: CGFloat
    private let monospacedDigit: Bool

    init(
        size: CGFloat,
        weight: Font.Weight?,
        design: Font.Design?,
        relativeTo textStyle: Font.TextStyle?,
        maxScale: CGFloat,
        monospacedDigit: Bool
    ) {
        _scaled = ScaledMetric(
            wrappedValue: size,
            relativeTo: textStyle ?? MADTextStyleMapping.style(forDesignSize: size)
        )
        self.base = size
        self.weight = weight
        self.design = design
        self.maxScale = maxScale
        self.monospacedDigit = monospacedDigit
    }

    private var resolvedSize: CGFloat {
        min(max(scaled, base), base * max(maxScale, 1))
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
            relativeTo: textStyle,
            maxScale: maxScale,
            monospacedDigit: monospacedDigit
        ))
    }
}

/// Named Dynamic Type ceilings, so every surface states its cap the same way
/// and a later tuning pass can grep for them.
extension DynamicTypeSize {
    /// Fixed-geometry chrome: hero stat frames, fixed-height tiles, pills,
    /// the tracker's control bar. Grows ~30% at most.
    static let madFixedChromeCap: DynamicTypeSize = .xxLarge
    /// Dense cards whose rows can wrap or re-arrange (feed cards, dashboard
    /// cards below the hero, inbox rows).
    static let madCardCap: DynamicTypeSize = .accessibility1
    /// Plain lists of text (Settings): grows as far as a list honestly holds.
    static let madListCap: DynamicTypeSize = .accessibility3
}
