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
    /// Resolved at pinch-BEGIN, not stored: photo slides hand back their
    /// already-loaded image for free, while composite slides (route maps,
    /// stats cards) render their floating copy on demand — nothing is baked
    /// eagerly or retained per-card for a gesture most cards never receive.
    let imageProvider: () -> UIImage?
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
                    imageProvider: imageProvider,
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
        modifier(InstagramZoomModifier(
            imageProvider: { image }, cornerRadius: cornerRadius, onDoubleTap: onDoubleTap))
    }

    /// Variant for slides whose floating copy is composed on demand.
    func instagramZoomable(
        imageProvider: @escaping () -> UIImage?,
        cornerRadius: CGFloat = MADTheme.CornerRadius.medium,
        onDoubleTap: (() -> Void)? = nil
    ) -> some View {
        modifier(InstagramZoomModifier(
            imageProvider: imageProvider, cornerRadius: cornerRadius, onDoubleTap: onDoubleTap))
    }
}

private struct ZoomGestureHost: UIViewRepresentable {
    let imageProvider: () -> UIImage?
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

        // Always installed — the callback is resolved at fire time via the
        // coordinator's current `parent`. Gating installation on the closure
        // captured at CREATION time left slides created without a handler
        // (or recycled across identities) permanently deaf to double-taps.
        let doubleTap = UITapGestureRecognizer(
            target: context.coordinator, action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        doubleTap.delegate = context.coordinator
        view.addGestureRecognizer(doubleTap)
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
                guard floatingImageView == nil, let image = parent.imageProvider() else { return }
                sourceFrame = hostView.convert(hostView.bounds, to: window)
                startCentroid = gesture.location(in: window)

                let dim = UIView(frame: window.bounds)
                dim.backgroundColor = .black
                dim.alpha = 0
                window.addSubview(dim)
                dimView = dim

                let iv = UIImageView(image: image)
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

// MARK: - Workout card slide

/// The run/walk as a branded 4:5 card, rendered live from a post's stats —
/// the "workout" second slide of a photo post when the run has no GPS route to
/// show instead. Same visual language as the baked RunStatsCardView, but
/// responsive so it fills the feed slide on any screen size.
struct FeedWorkoutCard: View {
    let stats: PostStats
    let workoutType: String?

    private var accent: Color { ActivityCardView.color(workoutType) }
    private var icon: String { ActivityCardView.icon(workoutType) }
    private var verb: String { ActivityCardView.verb(workoutType) }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.09, green: 0.09, blue: 0.12), .black],
                startPoint: .top, endPoint: .bottom
            )
            RadialGradient(colors: [accent.opacity(0.4), .clear],
                           center: .init(x: 0.5, y: 0.32), startRadius: 8, endRadius: 220)

            VStack(spacing: 0) {
                HStack {
                    HStack(spacing: 5) {
                        Image(systemName: icon).font(.system(size: 12, weight: .bold))
                        Text(verb.uppercased())
                            .font(.system(size: 11, weight: .heavy, design: .rounded))
                            .tracking(1.4)
                    }
                    .foregroundColor(accent)
                    .padding(.horizontal, 11).padding(.vertical, 6)
                    .background(Capsule().fill(accent.opacity(0.15)))
                    Spacer()
                    if let date = stats.date, !date.isEmpty {
                        Text(date)
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundColor(.white.opacity(0.55))
                    }
                }

                Spacer(minLength: 8)

                Text(String(format: "%.2f", stats.distance ?? 0))
                    .font(.system(size: 76, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .monospacedDigit()
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .shadow(color: .black.opacity(0.4), radius: 6, y: 3)
                Text("MILES")
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .tracking(7)
                    .foregroundColor(.white.opacity(0.6))

                Spacer(minLength: 8)

                let tiles = statTiles
                if !tiles.isEmpty {
                    VStack(spacing: 8) {
                        ForEach(Array(stride(from: 0, to: tiles.count, by: 2)), id: \.self) { row in
                            HStack(spacing: 8) {
                                tileView(tiles[row])
                                if row + 1 < tiles.count { tileView(tiles[row + 1]) }
                            }
                        }
                    }
                }

                MADLogoMark(size: 28, opacity: 0.9)
                .padding(.top, 14)
            }
            .padding(18)
            // This card renders inside the paging carousel, whose page dots
            // occupy the slide's bottom edge — keep the brand row above them.
            .padding(.bottom, 16)
        }
        .aspectRatio(4.0 / 5.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium, style: .continuous))
    }

    private struct Tile { let icon: String; let label: String; let value: String; var tint: Color = .white }

    private var statTiles: [Tile] {
        var out: [Tile] = []
        if let p = stats.pace, p > 0 {
            out.append(Tile(icon: "speedometer", label: "PACE", value: "\(RunStatsStickerView.paceText(p)) /mi"))
        }
        if let d = stats.duration, d > 0 {
            out.append(Tile(icon: "clock.fill", label: "TIME", value: RunStatsStickerView.durationText(d)))
        }
        if let c = stats.calories, c > 0 {
            out.append(Tile(icon: "bolt.fill", label: "CALORIES", value: "\(Int(c.rounded()))"))
        } else if let s = stats.steps, s > 0 {
            out.append(Tile(icon: "shoeprints.fill", label: "STEPS", value: s.formatted(.number.grouping(.automatic))))
        }
        if let s = stats.streak, s > 0 {
            out.append(Tile(icon: "flame.fill", label: "STREAK", value: "\(s) days", tint: .orange))
        }
        return out
    }

    private func tileView(_ tile: Tile) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: tile.icon)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(tile.tint == .white ? accent : tile.tint)
                Text(tile.label)
                    .font(.system(size: 9, weight: .heavy, design: .rounded))
                    .tracking(1)
                    .foregroundColor(.white.opacity(0.5))
            }
            Text(tile.value)
                .font(.system(size: 18, weight: .black, design: .rounded))
                .monospacedDigit()
                .foregroundColor(tile.tint)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.07)))
    }
}

// MARK: - Double-tap hype burst

/// Instagram's big-heart moment, in Mile A Day's language: a huge clap bursts
/// from the center of the photo with a spring, mini claps radiate outward,
/// then everything floats up and fades. Fire it by incrementing `trigger`.
///
/// Fully invisible at rest — every element's opacity is gated on `playing`,
/// not just animation phase. (The particles used to key opacity solely off
/// `particlesOut`, which is false at rest too, so six claps sat permanently
/// on every card that had never been double-tapped.)
struct HypeBurstView: View {
    let trigger: Int

    /// True only while a burst is on screen. Also generation-guards the
    /// delayed cleanup so a rapid re-double-tap isn't cut short by the
    /// previous burst's teardown.
    @State private var playing = false
    @State private var generation = 0

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
                    .opacity(playing && !particlesOut ? 0.9 : 0)
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
                .opacity(playing ? mainOpacity : 0)
                .offset(y: rise)
        }
        .allowsHitTesting(false)
        .onChange(of: trigger) { _, _ in play() }
    }

    private func particleOffset(angle degrees: Double, distance: CGFloat) -> CGSize {
        let radians = degrees * .pi / 180
        return CGSize(width: CGFloat(cos(radians)) * distance, height: CGFloat(sin(radians)) * distance)
    }

    private func play() {
        generation += 1
        let gen = generation

        // Reset instantly (a rapid re-double-tap replays from the start).
        var reset = Transaction()
        reset.disablesAnimations = true
        withTransaction(reset) {
            playing = true
            mainScale = 0.2
            mainRotation = -14
            mainOpacity = 0
            rise = 0
            particlesOut = false
        }

        // Pop in with an Instagram-style overshoot spring…
        withAnimation(.spring(response: 0.32, dampingFraction: 0.55)) {
            mainScale = 1.12
            mainRotation = 0
            mainOpacity = 1
        }
        withAnimation(.easeOut(duration: 0.7).delay(0.05)) {
            particlesOut = true
        }
        // …hold a beat, then float up and fade out.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
            guard gen == generation else { return }
            withAnimation(.easeIn(duration: 0.35)) {
                mainOpacity = 0
                rise = -60
                mainScale = 0.8
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.95) {
            guard gen == generation else { return }
            playing = false
        }
    }
}
