import SwiftUI
import UIKit

// MARK: - The two frames

/// Both halves of a FRONT & BACK capture, in the order they were shot.
///
/// The camera takes whatever it is pointed at FIRST and the other lens right
/// after, so "primary" is always the frame the user deliberately framed — the
/// view on a run, or their face if they'd already flipped. That is the one
/// that leads, and it is the only ordering rule the feature has.
struct DualCapture: Equatable {
    /// The shot the user framed and triggered.
    let primary: UIImage
    /// The other camera, caught a beat later.
    let secondary: UIImage
    /// True when the deliberate shot was the selfie camera, so copy can say
    /// which way round it happened without guessing.
    let primaryWasFront: Bool
}

// MARK: - Geometry

/// WHERE the small picture sits, defined exactly once.
///
/// Three things have to agree about this rectangle or the feature breaks in a
/// way that is hard to even see: the live editor draws it, `ImageRenderer`
/// BAKES it into both uploaded images, and the feed card puts an invisible tap
/// target over it to swap them. The card is reading a region of a photograph
/// it did not draw — so if any one of the three drifts, the tap lands next to
/// the thing it is supposed to hit and the whole interaction quietly stops
/// working. One definition, normalized to the canvas, used by all three.
///
/// TOP-TRAILING, not BeReal's top-left: a photo slide already badges its
/// top-LEFT corner with the crew member's name (or "Stats" on an auto card),
/// and stacking the inset on that is the one collision available on the photo
/// face. The bottom belongs to the route face's baked stats band.
enum DualPhotoLayout {
    /// Inset width as a fraction of the canvas width.
    static let widthFraction: CGFloat = 0.30
    /// Gap from the canvas edges, also as a fraction of its WIDTH — so the
    /// margin stays visually square rather than stretching with the 4:5.
    static let marginFraction: CGFloat = 0.038
    /// The inset keeps the canvas's own 4:5 portrait shape.
    static let aspect: CGFloat = 4.0 / 5.0

    /// The inset's frame inside a canvas of `size`.
    static func insetRect(in size: CGSize) -> CGRect {
        let width = size.width * widthFraction
        let height = width / aspect
        let margin = size.width * marginFraction
        return CGRect(
            x: size.width - margin - width,
            y: margin,
            width: width,
            height: height
        )
    }

    /// Hit area for the swap tap — the visible rect, grown so a thumb that
    /// lands just outside the corner still counts. Purely a hit target; the
    /// drawn rectangle is never padded.
    static func tapRect(in size: CGSize) -> CGRect {
        insetRect(in: size).insetBy(dx: -10, dy: -10)
    }

    static func cornerRadius(forInsetWidth width: CGFloat) -> CGFloat {
        max(6, width * 0.13)
    }

    static func borderWidth(forInsetWidth width: CGFloat) -> CGFloat {
        max(1.5, width * 0.022)
    }

    static func swapGlyphDiameter(in size: CGSize) -> CGFloat {
        max(20, insetRect(in: size).width * 0.30)
    }

    /// The ⇄ disc straddles the inset's bottom-outer corner, so it reads as
    /// belonging to the small picture without covering any of it.
    static func swapGlyphCenter(in size: CGSize) -> CGPoint {
        let rect = insetRect(in: size)
        return CGPoint(x: rect.minX, y: rect.maxY)
    }
}

// MARK: - The composed picture

/// One FRONT & BACK photo: the big frame full-bleed with the other inset in
/// the corner.
///
/// This is both the live editor preview AND what `ImageRenderer` bakes, for
/// the same reason `PostCanvas` is shared — what you arrange is what gets
/// uploaded, pixel for pixel.
struct DualPhotoView: View {
    let big: UIImage
    let small: UIImage

    var body: some View {
        GeometryReader { geo in
            let rect = DualPhotoLayout.insetRect(in: geo.size)
            let radius = DualPhotoLayout.cornerRadius(forInsetWidth: rect.width)
            let border = DualPhotoLayout.borderWidth(forInsetWidth: rect.width)

            ZStack {
                Image(uiImage: big)
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()

                Image(uiImage: small)
                    .resizable()
                    .scaledToFill()
                    .frame(width: rect.width, height: rect.height)
                    .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.92), lineWidth: border)
                    )
                    // The drop shadow is what stops the inset reading as a hole
                    // punched in the photo — it has to sit ON the picture.
                    .shadow(color: .black.opacity(0.45), radius: rect.width * 0.06,
                            x: 0, y: rect.width * 0.02)
                    .position(x: rect.midX, y: rect.midY)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
    }
}

/// Tap the small picture to swap which one is large.
///
/// The inset is BAKED into the photograph, so this is a hit area laid over a
/// region of an image nobody drew at runtime — which is exactly why the
/// rectangle lives in `DualPhotoLayout` and nowhere else. Used by the
/// composer's editor and by the feed card, so the gesture is learned once, on
/// your own photo, before anyone meets it on someone else's.
struct DualSwapTapTarget: View {
    /// The 4:5 box the photo is drawn in.
    let canvas: CGSize
    var action: () -> Void

    var body: some View {
        let tap = DualPhotoLayout.tapRect(in: canvas)
        let glyphCenter = DualPhotoLayout.swapGlyphCenter(in: canvas)
        ZStack {
            Color.clear
            DualSwapGlyph(diameter: DualPhotoLayout.swapGlyphDiameter(in: canvas))
                .position(glyphCenter)
                .allowsHitTesting(false)
            Button(action: action) {
                Color.clear
                    .frame(width: tap.width, height: tap.height)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .position(x: tap.midX, y: tap.midY)
            .accessibilityLabel("Swap front and back photo")
        }
        .frame(width: canvas.width, height: canvas.height)
    }
}

/// The little ⇄ disc that says the inset is tappable.
///
/// Never baked into an upload — it is an affordance, not part of the picture,
/// and a swap arrow frozen into someone's photo forever would be the kind of
/// watermark nobody asked for. Drawn live by the editor and by the feed card.
struct DualSwapGlyph: View {
    var diameter: CGFloat = 26

    var body: some View {
        Image(systemName: "arrow.triangle.2.circlepath")
            .font(.system(size: diameter * 0.52, weight: .black))
            .foregroundColor(.black.opacity(0.85))
            .frame(width: diameter, height: diameter)
            .background(Circle().fill(Color.white.opacity(0.95)))
            .overlay(Circle().strokeBorder(Color.black.opacity(0.12), lineWidth: 1))
            .shadow(color: .black.opacity(0.35), radius: diameter * 0.12, y: 1)
            .accessibilityHidden(true)
    }
}
