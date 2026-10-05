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

// MARK: - Where the small one sits

/// Which corner the inset occupies.
///
/// FOUR CORNERS, not a free position, and that is the whole design. The inset
/// is BAKED into both uploaded pictures, so wherever the poster leaves it the
/// feed card has to be told — it lays an invisible tap target over a region
/// of a photograph it did not draw. A free x/y would mean shipping a
/// coordinate pair and trusting two renderers to agree on it forever; a
/// corner is four values, is impossible to leave half off the edge or
/// overlapping the stats sticker's usual spot, and answers the only question
/// anyone actually has — "get it off HER face" is always solved by another
/// corner.
///
/// Raw values ride the wire (`posts.dual_inset_corner`). Absent or
/// unrecognised means `.topTrailing`, which is where every photo posted
/// before this sat, so nothing already published moves.
enum DualInsetCorner: String, CaseIterable {
    case topTrailing = "tr"
    case topLeading = "tl"
    case bottomLeading = "bl"
    case bottomTrailing = "br"

    var isTop: Bool { self == .topTrailing || self == .topLeading }
    var isLeading: Bool { self == .topLeading || self == .bottomLeading }

    /// Tolerant by construction: an unknown string from a newer client is
    /// the default corner, never a crash or an inset in the wrong place.
    static func parse(_ raw: String?) -> DualInsetCorner {
        guard let raw, let known = DualInsetCorner(rawValue: raw) else { return .topTrailing }
        return known
    }
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
/// TOP-TRAILING by default, not BeReal's top-left: a photo slide already
/// badges its top-LEFT corner with the crew member's name (or "Stats" on an
/// auto card), and stacking the inset on that is the one collision available
/// on the photo face. The bottom belongs to the route face's baked stats band.
/// The poster can move it — see `DualInsetCorner`.
enum DualPhotoLayout {
    /// Inset width as a fraction of the canvas width.
    static let widthFraction: CGFloat = 0.30
    /// Gap from the canvas edges, also as a fraction of its WIDTH — so the
    /// margin stays visually square rather than stretching with the 4:5.
    static let marginFraction: CGFloat = 0.038
    /// The inset keeps the canvas's own 4:5 portrait shape.
    static let aspect: CGFloat = 4.0 / 5.0

    /// The inset's frame inside a canvas of `size`.
    static func insetRect(in size: CGSize, corner: DualInsetCorner = .topTrailing) -> CGRect {
        let width = size.width * widthFraction
        let height = width / aspect
        let margin = size.width * marginFraction
        return CGRect(
            x: corner.isLeading ? margin : size.width - margin - width,
            y: corner.isTop ? margin : size.height - margin - height,
            width: width,
            height: height
        )
    }

    /// Hit area for the swap tap — the visible rect, grown so a thumb that
    /// lands just outside the corner still counts. Purely a hit target; the
    /// drawn rectangle is never padded.
    static func tapRect(in size: CGSize, corner: DualInsetCorner = .topTrailing) -> CGRect {
        insetRect(in: size, corner: corner).insetBy(dx: -10, dy: -10)
    }

    /// The corner a dragged inset should land in — whichever quadrant its
    /// CENTRE ended up in. Centre, not the finger: a drag is judged by where
    /// the picture is, which is what the user is actually looking at.
    static func nearestCorner(toCentre point: CGPoint, in size: CGSize) -> DualInsetCorner {
        guard size.width > 0, size.height > 0 else { return .topTrailing }
        let top = point.y < size.height / 2
        let leading = point.x < size.width / 2
        switch (top, leading) {
        case (true, true): return .topLeading
        case (true, false): return .topTrailing
        case (false, true): return .bottomLeading
        case (false, false): return .bottomTrailing
        }
    }

    static func cornerRadius(forInsetWidth width: CGFloat) -> CGFloat {
        max(6, width * 0.13)
    }

    static func borderWidth(forInsetWidth width: CGFloat) -> CGFloat {
        max(1.5, width * 0.022)
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
    var corner: DualInsetCorner = .topTrailing
    /// Live drag translation while the poster is moving the inset. Never set
    /// by anything that renders for upload.
    var offset: CGSize = .zero

    var body: some View {
        GeometryReader { geo in
            let rect = DualPhotoLayout.insetRect(in: geo.size, corner: corner)
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
                    // `offset` is the LIVE drag only — the editor moving the
                    // inset under a finger. It is always .zero at bake time,
                    // so what gets uploaded is the settled corner and never a
                    // half-finished gesture.
                    .position(x: rect.midX + offset.width, y: rect.midY + offset.height)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
    }
}

/// One captured photo, drawn as ONE picture — the pair composed when there is
/// a pair, the single frame otherwise. Fills the frame it is given, like
/// `.resizable().scaledToFill()`, so it drops into an existing thumbnail or
/// card without changing its layout.
///
/// Exists so every surface that shows a stashed snap shows the SAME thing:
/// before this, a mid-walk front-and-back looked like an ordinary photo of
/// whichever way the phone was pointing right up until it was published, and
/// the second frame appeared out of nowhere on the card.
struct DualPhotoFill: View {
    let big: UIImage
    let small: UIImage?
    var corner: DualInsetCorner = .topTrailing

    @ViewBuilder
    var body: some View {
        if let small {
            DualPhotoView(big: big, small: small, corner: corner)
        } else {
            Image(uiImage: big)
                .resizable()
                .scaledToFill()
        }
    }
}

/// Flatten a pair into ONE picture, outside the post composer.
///
/// The composer bakes its own composite through `PostCanvas` because the
/// sticker has to land in the same render. This is for the places that have
/// two frames and no canvas — the camera roll copy of a mid-walk snap, which
/// is the user's own keepsake of a photo they took in one press and would
/// otherwise arrive as either half of it or two separate pictures.
///
/// Uses the same `DualPhotoView` as everything else, so the corner it lands in
/// is the corner the feed card taps.
enum DualPhotoComposite {
    @MainActor
    static func render(
        big: UIImage,
        small: UIImage,
        corner: DualInsetCorner = .topTrailing,
        maxWidth: CGFloat = 1440
    ) -> UIImage? {
        guard big.size.width > 0, big.size.height > 0 else { return nil }
        // The primary's OWN aspect, not the feed's 4:5: this is a copy of the
        // photograph they took, and re-cropping someone's keepsake to a shape
        // they never chose is a worse outcome than a tall picture.
        let width = min(maxWidth, max(1, big.size.width))
        let height = width * (big.size.height / big.size.width)
        let renderer = ImageRenderer(
            content: DualPhotoView(big: big, small: small, corner: corner)
                .frame(width: width, height: height)
        )
        renderer.scale = 1
        return renderer.uiImage
    }
}

/// Tap the small picture to swap which one is large.
///
/// The inset is BAKED into the photograph, so this is a hit area laid over a
/// region of an image nobody drew at runtime — which is exactly why the
/// rectangle lives in `DualPhotoLayout` and nowhere else. Used by the
/// composer's editor and by the feed card, so the gesture is learned once, on
/// your own photo, before anyone meets it on someone else's.
///
/// NOTHING IS DRAWN. It carried a ⇄ disc straddling the inset's corner, on
/// the theory that a tap target nobody can see is a tap target nobody finds
/// — but the inset is already the universal "tap me" of this kind of photo,
/// the disc sat ON somebody's picture in every feed, and it had to be kept
/// out of the baked upload, so the one badge in the app that could never be
/// part of the image was also the most prominent thing on it. The affordance
/// is the small picture. The composer teaches the gesture in words, and
/// gives the poster a labelled control besides.
struct DualSwapTapTarget: View {
    /// The 4:5 box the photo is drawn in.
    let canvas: CGSize
    /// Where the inset was BAKED. Wrong here and the tap lands on nothing,
    /// which is the whole reason the corner travels with the post.
    var corner: DualInsetCorner = .topTrailing
    var action: () -> Void

    var body: some View {
        let tap = DualPhotoLayout.tapRect(in: canvas, corner: corner)
        ZStack {
            Color.clear
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

/// Move the inset, or tap it to swap — the composer's half of the gesture.
///
/// Drag it anywhere on the photo and it follows your finger; let go and it
/// settles into whichever corner it ended up nearest. That snap is not a
/// limitation dressed up as polish: the corner is what travels with the post
/// so the feed card can find the inset again, and a free coordinate would
/// mean trusting two renderers, a wire format and every future surface to
/// agree on a pair of floats forever. Four corners cannot land half off the
/// edge, cannot cover the middle of the photo, and answer the actual
/// question — "it's over her face" is always fixed by a different corner.
///
/// Tap and drag on one target: the drag has a minimum distance, so a tap
/// that doesn't travel still swaps.
struct DualInsetMover: View {
    /// The box the photo is drawn in.
    let canvas: CGSize
    /// Where the inset is right now.
    let corner: DualInsetCorner
    var onSwap: () -> Void
    /// Live translation, so the canvas can draw the inset under the finger.
    var onDragChanged: (CGSize) -> Void
    /// Where it settled.
    var onDrop: (DualInsetCorner) -> Void

    @State private var live: CGSize = .zero

    var body: some View {
        let rect = DualPhotoLayout.insetRect(in: canvas, corner: corner)
        let tap = DualPhotoLayout.tapRect(in: canvas, corner: corner)
        ZStack {
            Color.clear
            Color.clear
                .frame(width: tap.width, height: tap.height)
                .contentShape(Rectangle())
                .position(x: tap.midX + live.width, y: tap.midY + live.height)
                .gesture(
                    DragGesture(minimumDistance: 8)
                        .onChanged { value in
                            live = value.translation
                            onDragChanged(value.translation)
                        }
                        .onEnded { value in
                            // Judged by where the PICTURE ended up, not the
                            // finger: the inset is what the eye is following.
                            let centre = CGPoint(
                                x: rect.midX + value.translation.width,
                                y: rect.midY + value.translation.height
                            )
                            let settled = DualPhotoLayout.nearestCorner(
                                toCentre: centre, in: canvas)
                            live = .zero
                            onDragChanged(.zero)
                            onDrop(settled)
                        }
                )
                .onTapGesture { onSwap() }
                .accessibilityLabel("Front and back inset")
                .accessibilityHint("Double tap to swap which photo is big")
                // A drag is not available to VoiceOver, and moving the inset
                // off somebody's face is the whole point of it being movable
                // — so each corner is a named action as well as a gesture.
                .accessibilityAction(named: "Move to top left") {
                    onDrop(.topLeading)
                }
                .accessibilityAction(named: "Move to top right") {
                    onDrop(.topTrailing)
                }
                .accessibilityAction(named: "Move to bottom left") {
                    onDrop(.bottomLeading)
                }
                .accessibilityAction(named: "Move to bottom right") {
                    onDrop(.bottomTrailing)
                }
        }
        .frame(width: canvas.width, height: canvas.height)
    }
}
