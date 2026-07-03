import SwiftUI
import UIKit

// Shared media plumbing for the feed: a cached image view (so signed URLs and
// scroll-recycling don't re-download), Instagram-style pinch-to-zoom that
// floats the image over the whole UI, and the double-tap hype burst.

// MARK: - Image cache

/// In-memory image cache for feed media. Keyed by the URL *path* — signed
/// media URLs rotate their query string every few days, and a query-keyed
/// cache would re-download every photo on rotation.
enum FeedImageCache {
    private static let cache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = 120
        return c
    }()

    static func key(for url: URL) -> NSString {
        NSString(string: "\(url.host ?? "")\(url.path)")
    }

    static func image(for url: URL) -> UIImage? { cache.object(forKey: key(for: url)) }
    static func store(_ image: UIImage, for url: URL) { cache.setObject(image, forKey: key(for: url)) }
}

/// Feed media image backed by `FeedImageCache`. Same visual states as the old
/// AsyncImage treatment (spinner → fill image → broken-photo placeholder), but
/// exposes the loaded `UIImage` so the zoom overlay can float a copy of it.
struct FeedImageView: View {
    let url: URL?
    @Binding var loadedImage: UIImage?

    @State private var failed = false

    var body: some View {
        ZStack {
            if let image = loadedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if failed || url == nil {
                Color.white.opacity(0.05)
                Image(systemName: "photo").foregroundColor(.white.opacity(0.3))
            } else {
                Color.white.opacity(0.05)
                ProgressView().tint(.white)
            }
        }
        .task(id: url) { await load() }
    }

    private func load() async {
        guard let url else { return }
        if let cached = FeedImageCache.image(for: url) {
            loadedImage = cached
            return
        }
        // Recycled row with a new url: drop the previous photo instead of
        // showing someone else's image while the right one downloads.
        loadedImage = nil
        failed = false
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let image = UIImage(data: data) else {
                failed = true
                return
            }
            FeedImageCache.store(image, for: url)
            loadedImage = image
        } catch {
            failed = true
        }
    }
}

// MARK: - Instagram-style pinch zoom

/// Pinch-to-zoom exactly like Instagram: the image lifts out of its card onto
/// a window-level overlay (so it floats over neighboring cards, the tab bar —
/// everything), scales and pans with the two fingers, dims the rest of the
/// screen, and springs back into place on release. No modal, no tap needed.
///
/// Implemented in UIKit because the paging TabView clips SwiftUI-scaled
/// content to the slide bounds and can't render above siblings; a window
/// overlay side-steps all of that. One- finger gestures (paging, scrolling)
/// are untouched — the pinch needs two fingers.
struct InstagramZoomModifier: ViewModifier {
    let image: UIImage?
    var cornerRadius: CGFloat = MADTheme.CornerRadius.medium
    var onDoubleTap: (() -> Void)? = nil

    @State private var isZooming = false

    func body(content: Content) -> some View {
        content
            // The floating copy replaces the in-card image while zooming so
            // there's exactly one visible instance.
            .opacity(isZooming ? 0 : 1)
            .overlay(
                ZoomGestureHost(
                    image: image,
                    cornerRadius: cornerRadius,
                    isZooming: $isZooming,
                    onDoubleTap: onDoubleTap
                )
            )
    }
}

extension View {
    /// Instagram-style in-place pinch zoom + optional double-tap action.
    func instagramZoomable(
        image: UIImage?,
        cornerRadius: CGFloat = MADTheme.CornerRadius.medium,
        onDoubleTap: (() -> Void)? = nil
    ) -> some View {
        modifier(InstagramZoomModifier(image: image, cornerRadius: cornerRadius, onDoubleTap: onDoubleTap))
    }
}

private struct ZoomGestureHost: UIViewRepresentable {
    let image: UIImage?
    let cornerRadius: CGFloat
    @Binding var isZooming: Bool
    let onDoubleTap: (() -> Void)?

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear

        let pinch = UIPinchGestureRecognizer(
            target: context.coordinator, action: #selector(Coordinator.handlePinch(_:)))
        pinch.delegate = context.coordinator
        view.addGestureRecognizer(pinch)

        if onDoubleTap != nil {
            let doubleTap = UITapGestureRecognizer(
                target: context.coordinator, action: #selector(Coordinator.handleDoubleTap(_:)))
            doubleTap.numberOfTapsRequired = 2
            view.addGestureRecognizer(doubleTap)
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.parent = self
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: ZoomGestureHost

        private var dimView: UIView?
        private var floatingImageView: UIImageView?
        private var sourceFrame: CGRect = .zero
        private var startCentroid: CGPoint = .zero

        init(parent: ZoomGestureHost) { self.parent = parent }

        // Let the feed keep scrolling if the user's second finger lands late —
        // the pinch takes over smoothly instead of fighting the scroll view.
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool { true }

        @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            parent.onDoubleTap?()
        }

        @objc func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            guard let hostView = gesture.view, let window = hostView.window else { return }

            switch gesture.state {
            case .began:
                guard parent.image != nil, floatingImageView == nil else { return }
                sourceFrame = hostView.convert(hostView.bounds, to: window)
                startCentroid = gesture.location(in: window)

                let dim = UIView(frame: window.bounds)
                dim.backgroundColor = .black
                dim.alpha = 0
                window.addSubview(dim)
                dimView = dim

                let iv = UIImageView(image: parent.image)
                iv.frame = sourceFrame
                iv.contentMode = .scaleAspectFill
                iv.clipsToBounds = true
                iv.layer.cornerRadius = parent.cornerRadius
                iv.layer.cornerCurve = .continuous
                window.addSubview(iv)
                floatingImageView = iv

                DispatchQueue.main.async { self.parent.isZooming = true }

            case .changed:
                guard let iv = floatingImageView else { return }
                let scale = max(1.0, gesture.scale)
                let centroid = gesture.location(in: window)
                // Pan with the fingers, and scale about the point the pinch
                // started on (not the image center) — the spot under the
                // fingers stays under the fingers, like Instagram.
                let pan = CGPoint(x: centroid.x - startCentroid.x, y: centroid.y - startCentroid.y)
                let anchor = CGPoint(x: startCentroid.x - sourceFrame.midX, y: startCentroid.y - sourceFrame.midY)
                iv.transform = CGAffineTransform(
                    translationX: pan.x + anchor.x * (1 - scale),
                    y: pan.y + anchor.y * (1 - scale)
                ).scaledBy(x: scale, y: scale)
                // Rounded corners melt away as the image grows past its card.
                iv.layer.cornerRadius = parent.cornerRadius * max(0, 2 - scale)
                dimView?.alpha = min(0.75, (scale - 1) * 0.9)

            case .ended, .cancelled, .failed:
                guard let iv = floatingImageView else { return }
                let dim = dimView
                floatingImageView = nil
                dimView = nil
                UIView.animate(
                    withDuration: 0.35, delay: 0,
                    usingSpringWithDamping: 0.82, initialSpringVelocity: 0.4
                ) {
                    iv.transform = .identity
                    iv.layer.cornerRadius = self.parent.cornerRadius
                    dim?.alpha = 0
                } completion: { _ in
                    iv.removeFromSuperview()
                    dim?.removeFromSuperview()
                    self.parent.isZooming = false
                }

            default:
                break
            }
        }
    }
}

// MARK: - Double-tap hype burst

/// Instagram's big-heart moment, in Mile A Day's language: a huge clap bursts
/// from the center of the photo with a spring, mini claps radiate outward,
/// then everything floats up and fades. Fire it by incrementing `trigger`.
struct HypeBurstView: View {
    let trigger: Int

    @State private var mainScale: CGFloat = 0
    @State private var mainRotation: Double = -14
    @State private var mainOpacity: Double = 0
    @State private var rise: CGFloat = 0
    @State private var particlesOut = false

    private let particleAngles: [Double] = [-150, -105, -70, -30, 20, 155]

    var body: some View {
        ZStack {
            // Radiating mini claps
            ForEach(Array(particleAngles.enumerated()), id: \.offset) { index, angle in
                Image(systemName: "hands.clap.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.orange.opacity(0.9))
                    .rotationEffect(.degrees(Double(index.isMultiple(of: 2) ? -18 : 14)))
                    .offset(particleOffset(angle: angle, distance: particlesOut ? 84 : 12))
                    .opacity(particlesOut ? 0 : 0.9)
                    .scaleEffect(particlesOut ? 0.6 : 1)
            }

            // The hero clap
            Image(systemName: "hands.clap.fill")
                .font(.system(size: 88, weight: .bold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color(red: 1.0, green: 0.72, blue: 0.25), .orange],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .shadow(color: .orange.opacity(0.55), radius: 22)
                .shadow(color: .black.opacity(0.35), radius: 8, y: 4)
                .scaleEffect(mainScale)
                .rotationEffect(.degrees(mainRotation))
                .opacity(mainOpacity)
                .offset(y: rise)
        }
        .allowsHitTesting(false)
        .onChange(of: trigger) { _, _ in play() }
    }

    private func particleOffset(angle degrees: Double, distance: CGFloat) -> CGSize {
        let radians = degrees * .pi / 180
        return CGSize(width: cos(radians) * distance, height: sin(radians) * distance)
    }

    private func play() {
        // Reset instantly (a rapid re-double-tap replays from the start).
        mainScale = 0.2
        mainRotation = -14
        mainOpacity = 0
        rise = 0
        particlesOut = false

        withAnimation(.spring(response: 0.32, dampingFraction: 0.55)) {
            mainScale = 1.12
            mainRotation = 0
            mainOpacity = 1
        }
        withAnimation(.easeOut(duration: 0.7).delay(0.05)) {
            particlesOut = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
            withAnimation(.easeIn(duration: 0.35)) {
                mainOpacity = 0
                rise = -60
                mainScale = 0.8
            }
        }
    }
}
