import SwiftUI
import UIKit
import QuartzCore

/// Launch experience for Mile A Day: split-flap, then a real reveal.
///
/// Three flap tiles fold through numbers like a departures board and land,
/// one after another, on M · A · D; they merge into the app icon. Then:
/// - **Returning users** (`AppStateManager.splashOverlay`): the home screen
///   is built UNDER the splash (`mountMain()`, once the splash is showing).
///   When the dashboard reports through `SplashGate` that its data has loaded
///   (plus a short settle), the icon flies into the real "Mile A Day" title
///   and the splash's background fades away, revealing the actual dashboard.
///   Capped at `revealCap` if the dashboard never reports.
/// - **New users / sign-in**: "Mile A Day" rises under the icon and the
///   splash hands off with `completeSplash()`.
///
/// Everything moves with Core Animation (`SplashLayerView`): every fold, the
/// merge and the reveal are scheduled up front as `CAAnimation`s and drawn by
/// the render server. A SwiftUI `TimelineView` re-renders on the main thread,
/// and launch is when the main thread is busiest (building the tab view,
/// loading HealthKit), so the first version dropped to ~20fps exactly while
/// the flaps were flipping and the icon was flying. Render-server animations
/// keep their frame rate even while the app's main thread is blocked.
struct SplashView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var gate = SplashGate.shared
    @StateObject private var driver = SplashDriver()

    var body: some View {
        SplashLayerRepresentable(driver: driver, reduceMotion: reduceMotion)
            .ignoresSafeArea()
            .allowsHitTesting(!driver.revealing)
            .onReceive(gate.$ready) { ready in
                if ready { driver.dashboardReady() }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Mile A Day")
    }
}

// MARK: - Timeline

/// Seconds after the splash's first frame.
enum SplashBeat {
    static let tilesIn: Double = 0.35
    /// Tile i lands at `firstLanding + i * landingGap`.
    static let firstLanding: Double = 1.1
    static let landingGap: Double = 0.35
    /// The soft red glow a tile gives as it lands.
    static let flash: Double = 0.35
    static let mergeStart: Double = 2.3
    static let mergeEnd: Double = 2.85
    static let wordmarkIn: Double = 2.8
    static let taglineIn: Double = 3.05
    static let textSettle: Double = 0.5
    /// Flap changes per second while a tile is searching.
    static let flipRate: Double = 9
    /// When the home screen starts building under the splash: the tiles are
    /// on screen and animating on the render server by then, so the build's
    /// main-thread work can't show.
    static let mountMain: Double = 0.5
    /// New users: hand off after the wordmark.
    static let wordmarkHandoff: Double = 3.7
    /// Returning users: never reveal before the icon has landed and rested.
    static let earliestReveal: Double = 3.1
    /// After the dashboard reports ready, let its first data pass settle.
    static let readySettle: Double = 0.35
    /// Reveal anyway if the dashboard hasn't reported by then.
    static let revealCap: Double = 6.0
    static let revealDuration: Double = 0.9
}

// MARK: - Driver

/// Owns the splash's lifecycle on the main thread: when it started, when to
/// build the home screen, when to reveal, when to hand off. The motion
/// itself lives in `SplashLayerView`.
@MainActor
final class SplashDriver: ObservableObject {
    @Published private(set) var revealing = false

    fileprivate weak var view: SplashLayerView?
    private var startedAt: Date?
    private var overApp = false
    private var readyAt: Date?
    private var revealScheduled = false
    private var reduceMotion = false

    /// The layer view has put its first frame on screen.
    fileprivate func started(overApp: Bool, reduceMotion: Bool) {
        guard startedAt == nil else { return }
        startedAt = Date()
        self.overApp = overApp
        self.reduceMotion = reduceMotion

        if !reduceMotion { scheduleHaptics() }

        if overApp {
            after(reduceMotion ? 0.1 : SplashBeat.mountMain) { AppStateManager.shared.mountMain() }
            after(SplashBeat.revealCap) { [weak self] in self?.scheduleReveal() }
            if readyAt != nil { scheduleReveal() }
        } else {
            after(reduceMotion ? 0.9 : SplashBeat.wordmarkHandoff) { AppStateManager.shared.completeSplash() }
        }
    }

    func dashboardReady() {
        guard readyAt == nil else { return }
        readyAt = Date()
        if startedAt != nil { scheduleReveal() }
    }

    private func scheduleReveal() {
        guard overApp, !revealScheduled, let startedAt else { return }
        revealScheduled = true
        let earliest = startedAt.addingTimeInterval(reduceMotion ? 0.3 : SplashBeat.earliestReveal)
        let settled = (readyAt ?? Date()).addingTimeInterval(readyAt == nil ? 0 : SplashBeat.readySettle)
        let at = max(Date(), earliest, settled)
        after(at.timeIntervalSinceNow) { [weak self] in self?.reveal() }
    }

    private func reveal() {
        revealing = true
        guard let view else {
            AppStateManager.shared.finishSplashOverlay()
            return
        }
        // The real title, in this view's coordinates (fallback: where the
        // header's title sits under the status bar).
        let target = SplashGate.shared.titleAnchor.map { view.convert($0, from: nil) }
            ?? CGPoint(x: MADTheme.Spacing.md + 14, y: view.safeAreaInsets.top + MADTheme.Spacing.sm + 16)
        view.reveal(to: target, flying: !reduceMotion) {
            AppStateManager.shared.finishSplashOverlay()
        }
    }

    private func scheduleHaptics() {
        let tick = UIImpactFeedbackGenerator(style: .light)
        let thump = UIImpactFeedbackGenerator(style: .heavy)
        tick.prepare()
        thump.prepare()
        for i in 0..<3 {
            after(SplashBeat.firstLanding + Double(i) * SplashBeat.landingGap) {
                tick.impactOccurred(intensity: 0.6)
            }
        }
        after(SplashBeat.mergeStart + 0.1) { thump.impactOccurred(intensity: 0.9) }
    }

    private func after(_ seconds: Double, _ work: @escaping @MainActor () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, seconds)) {
            MainActor.assumeIsolated { work() }
        }
    }
}

// MARK: - SwiftUI bridge

private struct SplashLayerRepresentable: UIViewRepresentable {
    let driver: SplashDriver
    let reduceMotion: Bool

    func makeUIView(context: Context) -> SplashLayerView {
        let overApp = AppStateManager.shared.splashOverlay
        let view = SplashLayerView(endsOnWordmark: !overApp, reduceMotion: reduceMotion)
        view.onFirstFrame = { [weak driver] in
            driver?.started(overApp: overApp, reduceMotion: reduceMotion)
        }
        driver.view = view
        // Backstop: if the splash somehow never gets a size (so never
        // reports its first frame), build the app anyway after a second
        // rather than leaving the launch blank until the 8s fallback.
        if overApp {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                AppStateManager.shared.mountMain()
            }
        }
        return view
    }

    func updateUIView(_ uiView: SplashLayerView, context: Context) {}
}

// MARK: - Core Animation splash

/// The splash's drawing. Builds its layers once it has a size, then adds
/// every animation in one go with `beginTime`s relative to that moment, so
/// the render server plays the whole sequence no matter what the main thread
/// is doing.
final class SplashLayerView: UIView {
    var onFirstFrame: (@MainActor () -> Void)?

    private let endsOnWordmark: Bool
    private let reduceMotion: Bool
    private var built = false

    private let background = CAGradientLayer()
    private let glow = CAGradientLayer()
    private let icon = CALayer()
    private var tiles: [CALayer] = []
    private var iconSize: CGFloat = 100

    private static let red = UIColor(MADTheme.Colors.madRed)
    private static let tileFill = UIColor(red: 0.165, green: 0.09, blue: 0.114, alpha: 1)
    private static let seam = UIColor(red: 0.05, green: 0.02, blue: 0.04, alpha: 1)
    private static let letters: [Character] = ["M", "A", "D"]
    private static let digits: [Character] = Array("0123456789")

    init(endsOnWordmark: Bool, reduceMotion: Bool) {
        self.endsOnWordmark = endsOnWordmark
        self.reduceMotion = reduceMotion
        super.init(frame: .zero)
        backgroundColor = .clear
        isOpaque = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard !built, bounds.width > 0, bounds.height > 0 else { return }
        built = true
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        build()
        CATransaction.commit()
        onFirstFrame?()
    }

    // MARK: Build

    private func build() {
        let size = bounds.size
        let width = min(size.width, 440)
        let tileW = width * 0.2
        let tileH = width * 0.27
        let gap = width * 0.03
        iconSize = width * 0.27
        let center = CGPoint(x: size.width / 2, y: size.height * 0.42)
        let scale = traitCollection.displayScale > 0 ? traitCollection.displayScale : 3
        // Offsets, not clock times: every animation is wrapped by `addTimed`
        // in a group that starts when this transaction reaches the render
        // server, so a main thread blocked before the first frame (a
        // logged-in launch loading data) delays the whole sequence evenly
        // instead of skipping its opening.
        let t0: CFTimeInterval = 0
        let total = SplashBeat.mergeEnd

        // Background: the app's own gradient.
        background.frame = bounds
        background.colors = [
            UIColor(red: 0.15, green: 0.08, blue: 0.10, alpha: 1).cgColor,
            UIColor(red: 0.12, green: 0.06, blue: 0.08, alpha: 1).cgColor,
            UIColor(red: 0.08, green: 0.04, blue: 0.06, alpha: 1).cgColor,
            UIColor(red: 0.05, green: 0.02, blue: 0.04, alpha: 1).cgColor
        ]
        layer.addSublayer(background)

        // Soft red light behind the mark, rising as it lands.
        glow.type = .radial
        glow.frame = bounds
        glow.colors = [Self.red.withAlphaComponent(0.22).cgColor, Self.red.withAlphaComponent(0).cgColor]
        glow.startPoint = CGPoint(x: 0.5, y: center.y / size.height)
        glow.endPoint = CGPoint(x: 0.5 + width * 0.7 / size.width, y: center.y / size.height + width * 0.7 / size.height)
        layer.addSublayer(glow)

        // The icon.
        icon.contents = UIImage(named: "mad-logo")?.cgImage
        icon.contentsGravity = .resizeAspect
        icon.bounds = CGRect(x: 0, y: 0, width: iconSize, height: iconSize)
        icon.position = center
        icon.cornerRadius = iconSize * 0.23
        icon.cornerCurve = .continuous
        icon.masksToBounds = true
        layer.addSublayer(icon)

        if reduceMotion {
            // The finished frame, faded in once.
            glow.opacity = 1
            icon.opacity = 1
            fade(layer: self.layer, from: 0, to: 1, at: t0, duration: 0.3)
            if endsOnWordmark { addWordmark(below: center, width: width, at: t0, animated: false) }
            return
        }

        // Glow and icon arrive with the merge.
        glow.opacity = 1
        addTimed(glow, keyframes("opacity", [0, 0, 1], times: [0, SplashBeat.mergeStart, total], total: total), at: t0)
        icon.opacity = 1
        addTimed(icon, keyframes("opacity", [0, 0, 1], times: [0, SplashBeat.mergeStart, total], total: total), at: t0)
        let landed = keyframes("transform.scale", [0.6, 0.6, 1.04, 1.0],
                               times: [0, SplashBeat.mergeStart, SplashBeat.mergeEnd - 0.15, total], total: total)
        landed.timingFunctions = [CAMediaTimingFunction(name: .linear),
                                  CAMediaTimingFunction(name: .easeOut),
                                  CAMediaTimingFunction(name: .easeInEaseOut)]
        addTimed(icon, landed, at: t0)

        // The three flaps.
        for i in 0..<3 {
            let tile = makeTile(i, width: tileW, height: tileH, scale: scale, t0: t0)
            let restX = center.x + CGFloat(i - 1) * (tileW + gap)
            tile.position = CGPoint(x: center.x, y: center.y)
            tile.opacity = 0
            layer.insertSublayer(tile, below: icon)
            tiles.append(tile)

            let slide = keyframes("position.x", [Double(restX), Double(restX), Double(center.x)],
                                  times: [0, SplashBeat.mergeStart, total], total: total)
            slide.timingFunctions = [CAMediaTimingFunction(name: .linear),
                                     CAMediaTimingFunction(name: .easeInEaseOut)]
            addTimed(tile, slide, at: t0)
            addTimed(tile, keyframes("opacity", [0, 1, 1, 0],
                                     times: [0, SplashBeat.tilesIn, SplashBeat.mergeStart, total], total: total), at: t0)
        }

        if endsOnWordmark { addWordmark(below: center, width: width, at: t0, animated: true) }
    }

    /// One flap tile: a card, a red landing glow, the character (folding by
    /// `transform.scale.y`, swapping its picture at each fold), and a seam.
    private func makeTile(_ i: Int, width: CGFloat, height: CGFloat, scale: CGFloat, t0: CFTimeInterval) -> CALayer {
        let tile = CALayer()
        tile.bounds = CGRect(x: 0, y: 0, width: width, height: height)
        tile.backgroundColor = Self.tileFill.cgColor
        tile.cornerRadius = 10
        tile.cornerCurve = .continuous

        let flash = CALayer()
        flash.frame = tile.bounds
        flash.backgroundColor = Self.red.cgColor
        flash.cornerRadius = 10
        flash.cornerCurve = .continuous
        flash.opacity = 0
        tile.addSublayer(flash)

        let glyph = CALayer()
        glyph.frame = tile.bounds
        glyph.contentsGravity = .center
        glyph.contentsScale = scale
        tile.addSublayer(glyph)

        let seam = CALayer()
        seam.frame = CGRect(x: 0, y: height / 2 - 1, width: width, height: 2)
        seam.backgroundColor = Self.seam.cgColor
        tile.addSublayer(seam)

        // Fold phase in "flip units": whole numbers are open, .5 is shut.
        // Tiles are offset a third of a flip so they don't fold in lockstep.
        let rate = SplashBeat.flipRate
        let offset = Double(i) * 0.33
        let landing = SplashBeat.firstLanding + Double(i) * SplashBeat.landingGap
        let landingRaw = (landing * rate + offset).rounded(.up)
        let end = (landingRaw - offset) / rate
        let time: (Double) -> Double = { raw in (raw - offset) / rate }

        // Pictures swap at each fold; the letter arrives on the last one.
        let fontSize = height * 0.62
        func digit(at raw: Double) -> Character {
            Self.digits[(Int((raw + 0.5).rounded(.down)) * 7 + i * 3) % Self.digits.count]
        }
        var images: [Any] = [Self.glyph(digit(at: offset), size: fontSize, alpha: 0.8, scale: scale)]
        var imageTimes: [Double] = [0]
        var n = (offset - 0.5).rounded(.up) + 0.5
        while n < landingRaw - 0.5 {
            images.append(Self.glyph(digit(at: n + 0.5), size: fontSize, alpha: 0.8, scale: scale))
            imageTimes.append(time(n))
            n += 1
        }
        let letter = Self.glyph(Self.letters[i], size: fontSize, alpha: 1, scale: scale)
        images.append(letter)
        imageTimes.append(time(landingRaw - 0.5))
        glyph.contents = letter
        let swap = CAKeyframeAnimation(keyPath: "contents")
        swap.values = images
        swap.keyTimes = imageTimes.map { NSNumber(value: $0 / end) }
        swap.calculationMode = .discrete
        swap.duration = end
        addTimed(glyph, swap, at: t0)

        // The fold: |cos(π · phase)|, sampled 8 times a flip.
        var folds: [Double] = []
        var foldTimes: [Double] = []
        var raw = offset
        while raw < landingRaw {
            folds.append(max(0.04, abs(cos(Double.pi * raw.truncatingRemainder(dividingBy: 1)))))
            foldTimes.append(time(raw))
            raw += 0.125
        }
        folds.append(1)
        foldTimes.append(end)
        let fold = CAKeyframeAnimation(keyPath: "transform.scale.y")
        fold.values = folds
        fold.keyTimes = foldTimes.map { NSNumber(value: $0 / end) }
        fold.duration = end
        addTimed(glyph, fold, at: t0)

        // A soft red glow as it lands.
        let glowEnd = landing + SplashBeat.flash
        addTimed(flash, keyframes("opacity", [0, 0, 0.55, 0], times: [0, landing, landing + 0.001, glowEnd], total: glowEnd), at: t0)

        return tile
    }

    /// "Mile A Day" and the tagline under the icon (new users).
    private func addWordmark(below center: CGPoint, width: CGFloat, at t0: CFTimeInterval, animated: Bool) {
        let scale = traitCollection.displayScale > 0 ? traitCollection.displayScale : 3
        let titleY = center.y + iconSize / 2 + width * 0.16
        let lines: [(String, UIFont, CGFloat, Double, Double)] = [
            ("Mile A Day", Self.rounded(38, .black), 1.0, SplashBeat.wordmarkIn, -12),
            ("Day 1 starts today.", Self.rounded(16, .medium), 0.6, SplashBeat.taglineIn, 22)
        ]
        for (text, font, alpha, start, dy) in lines {
            let label = CATextLayer()
            label.string = NSAttributedString(string: text, attributes: [
                .font: font,
                .foregroundColor: UIColor.white.withAlphaComponent(alpha)
            ])
            label.alignmentMode = .center
            label.contentsScale = scale
            label.bounds = CGRect(x: 0, y: 0, width: bounds.width - 64, height: font.lineHeight + 4)
            label.position = CGPoint(x: bounds.width / 2, y: titleY + CGFloat(dy))
            label.opacity = 1
            layer.addSublayer(label)
            guard animated else { continue }
            let rise = CABasicAnimation(keyPath: "position.y")
            rise.fromValue = label.position.y + 10
            rise.toValue = label.position.y
            let show = CABasicAnimation(keyPath: "opacity")
            show.fromValue = 0
            show.toValue = 1
            let both = CAAnimationGroup()
            both.animations = [rise, show]
            both.duration = SplashBeat.textSettle
            both.timingFunction = CAMediaTimingFunction(name: .easeOut)
            addTimed(label, both, at: t0 + start)
        }
    }

    // MARK: Reveal

    /// Fly the icon into the real title and fade the splash away, all on the
    /// render server. `completion` runs once it's fully transparent.
    func reveal(to target: CGPoint, flying: Bool, completion: @escaping () -> Void) {
        let duration = SplashBeat.revealDuration
        CATransaction.begin()
        CATransaction.setCompletionBlock(completion)
        CATransaction.setDisableActions(true)

        let ease = CAMediaTimingFunction(name: .easeInEaseOut)
        for faded in [background, glow] {
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = faded.presentation()?.opacity ?? 1
            fade.toValue = 0
            fade.duration = duration
            fade.timingFunction = ease
            faded.opacity = 0
            faded.add(fade, forKey: "reveal")
        }

        let iconFade = CAKeyframeAnimation(keyPath: "opacity")
        iconFade.values = [1, 1, 0]
        iconFade.keyTimes = [0, 0.4, 1]
        iconFade.duration = duration
        icon.opacity = 0

        if flying {
            let move = CABasicAnimation(keyPath: "position")
            move.fromValue = NSValue(cgPoint: icon.position)
            move.toValue = NSValue(cgPoint: target)
            let shrink = CABasicAnimation(keyPath: "transform.scale")
            shrink.fromValue = 1
            shrink.toValue = 26 / iconSize
            let group = CAAnimationGroup()
            group.animations = [move, shrink, iconFade]
            group.duration = duration
            group.timingFunction = ease
            icon.position = target
            icon.transform = CATransform3DMakeScale(26 / iconSize, 26 / iconSize, 1)
            icon.add(group, forKey: "reveal")
        } else {
            icon.add(iconFade, forKey: "reveal")
        }
        CATransaction.commit()
    }

    // MARK: Helpers

    private func keyframes(_ keyPath: String, _ values: [Double], times: [Double], total: Double) -> CAKeyframeAnimation {
        let animation = CAKeyframeAnimation(keyPath: keyPath)
        animation.values = values
        animation.keyTimes = times.map { NSNumber(value: $0 / total) }
        animation.duration = total
        return animation
    }

    /// Add an animation `offset` seconds into the sequence. It sits in a
    /// group whose `beginTime` is 0, which Core Animation stamps with the
    /// moment the transaction is committed to the render server, so every
    /// layer shares one start: the first frame actually on screen. Before
    /// its offset it holds its first value (`.backwards`), so the model
    /// value (the END state) never flashes.
    private func addTimed(_ target: CALayer, _ animation: CAAnimation, at offset: CFTimeInterval) {
        animation.beginTime = offset
        animation.fillMode = .backwards
        let clock = CAAnimationGroup()
        clock.animations = [animation]
        clock.duration = offset + animation.duration
        clock.fillMode = .backwards
        target.add(clock, forKey: nil)
    }

    private func fade(layer target: CALayer, from: Float, to: Float, at t0: CFTimeInterval, duration: Double) {
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = from
        animation.toValue = to
        animation.duration = duration
        animation.beginTime = t0
        animation.fillMode = .backwards
        target.opacity = to
        target.add(animation, forKey: nil)
    }

    private static func rounded(_ size: CGFloat, _ weight: UIFont.Weight) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        guard let descriptor = base.fontDescriptor.withDesign(.rounded) else { return base }
        return UIFont(descriptor: descriptor, size: size)
    }

    private static var glyphCache: [String: CGImage] = [:]

    /// A transparent pixel, should a glyph ever fail to render.
    private static let blank: CGImage = {
        let context = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        return context!.makeImage()!
    }()

    /// One character as a picture, drawn once and reused.
    private static func glyph(_ character: Character, size: CGFloat, alpha: CGFloat, scale: CGFloat) -> CGImage {
        let key = "\(character)-\(Int(size))-\(alpha)"
        if let cached = glyphCache[key] { return cached }
        let font = rounded(size, .black)
        let text = NSAttributedString(string: String(character), attributes: [
            .font: font,
            .foregroundColor: UIColor.white.withAlphaComponent(alpha)
        ])
        let textSize = text.size()
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        let image = UIGraphicsImageRenderer(size: textSize, format: format).image { _ in
            text.draw(at: .zero)
        }
        let cgImage = image.cgImage ?? blank
        glyphCache[key] = cgImage
        return cgImage
    }
}

// MARK: - Dashboard → splash handshake

/// What the launch splash needs from the real dashboard: that its data has
/// loaded (`ready`) and where its "Mile A Day" title sits on screen
/// (`titleAnchor`, global coordinates), so the icon can dissolve into it.
@MainActor
final class SplashGate: ObservableObject {
    static let shared = SplashGate()
    @Published private(set) var ready = false
    @Published private(set) var titleAnchor: CGPoint?

    func report(anchor: CGPoint, ready isReady: Bool) {
        if titleAnchor != anchor { titleAnchor = anchor }
        if isReady && !ready { ready = true }
    }
}

/// Placed behind the dashboard's `MADTabHeader`: reports the title's spot
/// (16pt in, half the 26pt title line below the header's 8pt top padding)
/// and whether the home screen has its first data.
struct SplashRevealBeacon: View {
    let isReady: Bool

    var body: some View {
        GeometryReader { geo in
            let frame = geo.frame(in: .global)
            let anchor = CGPoint(x: frame.minX + MADTheme.Spacing.md + 13,
                                 y: frame.minY + MADTheme.Spacing.sm + 16)
            Color.clear
                .onAppear { SplashGate.shared.report(anchor: anchor, ready: isReady) }
                .onChange(of: isReady) { _, ready in
                    SplashGate.shared.report(anchor: anchor, ready: ready)
                }
                .onChange(of: anchor) { _, newAnchor in
                    SplashGate.shared.report(anchor: newAnchor, ready: isReady)
                }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

#Preview {
    SplashView()
}
