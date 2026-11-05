import SwiftUI
import UIKit

/// Launch experience for Mile A Day: split-flap, then a real reveal.
///
/// Three red flap tiles rattle through numbers like a departures board and
/// land, one after another, on M · A · D (a tick each). They merge into the
/// app icon with a thump. Then:
/// - **Returning users** (`AppStateManager.splashOverlay`): the app is
///   already running UNDER the splash. The splash waits until the dashboard
///   reports, through `SplashGate`, that its data has loaded and where its
///   real "Mile A Day" title sits on screen. Then the icon flies into that
///   title and dissolves while the splash's own background fades away,
///   revealing the actual home screen. There is no fake skeleton: what shows
///   through is the real dashboard. If the dashboard never reports (another
///   tab restored, a stuck load), the reveal starts anyway at `revealCap`.
/// - **New users / sign-in** (no dashboard yet): "Mile A Day" rises under
///   the icon and the splash hands off at `wordmarkHandoffDelay`.
///
/// Every frame is a pure function of time (`TimelineView`), never a chain of
/// `withAnimation` / `asyncAfter` state flips, so a first frame before
/// `onAppear`, a safe-area settle or a slow launch can't leave one layer out
/// of step with another.
struct SplashView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var gate = SplashGate.shared

    @State private var start: Date?
    /// Decided once on appear: is the app running underneath?
    @State private var overApp = false
    /// When the dissolve into the dashboard starts (overlay mode only).
    @State private var revealAt: Date?

    private static let wordmarkHandoffDelay: TimeInterval = 3.7
    private static let reducedHandoffDelay: TimeInterval = 0.9
    /// Reveal anyway if the dashboard hasn't reported ready by then.
    private static let revealCap: TimeInterval = 6.0
    private static let revealDuration: TimeInterval = 0.9
    /// Flap changes per second while a tile is still searching. Fast enough
    /// to read as a departures board, slow enough that each fold is seen
    /// (28/s read as flicker).
    private static let flipRate: Double = 9

    // MARK: - Timeline (seconds after appear)
    private enum Beat {
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
    }

    private static let letters: [Character] = ["M", "A", "D"]
    private static let digits: [Character] = Array("0123456789")

    // MARK: - Palette (the app's own: dark ember background, madRed)
    private let red = MADTheme.Colors.madRed
    private let tileFill = Color(red: 0.165, green: 0.09, blue: 0.114)
    private let seam = Color(red: 0.05, green: 0.02, blue: 0.04)

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation(minimumInterval: nil, paused: start == nil)) { context in
                let t = start.map { context.date.timeIntervalSince($0) } ?? 0
                let r = revealAt.map { context.date.timeIntervalSince($0) / Self.revealDuration } ?? 0
                frame(at: reduceMotion ? 10 : t,
                      reveal: Self.easeInOut(Self.clamp(r)),
                      size: geo.size,
                      origin: geo.frame(in: .global).origin)
                    .opacity(reduceMotion ? Self.progress(t, 0, 0.3) : 1)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(revealAt == nil)
        .onAppear(perform: begin)
        .onReceive(gate.$ready) { ready in
            if ready { scheduleReveal() }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Mile A Day")
    }

    // MARK: - Frame

    private func frame(at t: Double, reveal: Double, size: CGSize, origin: CGPoint) -> some View {
        let width = min(size.width, 440)
        let tileWidth = width * 0.2
        let tileHeight = width * 0.27
        let gap = width * 0.03
        let iconSize = width * 0.27
        let center = CGPoint(x: size.width / 2, y: size.height * 0.42)

        let merge = Self.easeInOut(Self.progress(t, Beat.mergeStart, Beat.mergeEnd))

        // Where the real title is, in this view's coordinates (fallback: the
        // header's usual spot under the status bar).
        let target: CGPoint = gate.titleAnchor.map { CGPoint(x: $0.x - origin.x, y: $0.y - origin.y) }
            ?? CGPoint(x: MADTheme.Spacing.md + 14, y: 70)
        let iconX = center.x + (target.x - center.x) * CGFloat(reveal)
        let iconY = center.y + (target.y - center.y) * CGFloat(reveal)
        // Shrink to about the title's cap height, fading out over the second
        // half so it reads as becoming the title underneath.
        let landed = 0.6 + 0.4 * Self.easeOutBack(merge)
        let iconScale = landed * (1 - (1 - 26 / Double(iconSize)) * reveal)
        let iconOpacity = merge * (1 - Self.progress(reveal, 0.4, 1))

        return ZStack {
            // The splash's own background: fades away to show the app.
            MADTheme.Colors.appBackgroundGradient
                .opacity(1 - reveal)

            RadialGradient(colors: [red.opacity(0.22 * merge * (1 - reveal)), .clear],
                           center: UnitPoint(x: 0.5, y: center.y / max(size.height, 1)),
                           startRadius: 0, endRadius: width * 0.7)

            // The flaps, sliding together and fading as they merge.
            ForEach(0..<3, id: \.self) { i in
                tile(i, at: t, width: tileWidth, height: tileHeight)
                    .position(x: center.x + CGFloat(i - 1) * (tileWidth + gap) * CGFloat(1 - merge),
                              y: center.y)
                    .opacity(Self.progress(t, 0, Beat.tilesIn) * (1 - merge))
            }

            Image("mad-logo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: iconSize, height: iconSize)
                .clipShape(RoundedRectangle(cornerRadius: iconSize * 0.23, style: .continuous))
                .scaleEffect(CGFloat(iconScale))
                .opacity(iconOpacity)
                .position(x: iconX, y: iconY)

            if !overApp {
                wordmark(at: t)
                    .position(x: center.x, y: center.y + iconSize / 2 + width * 0.16)
            }
        }
        .frame(width: size.width, height: size.height)
    }

    /// One flap tile. Each change is a fold: the face eases shut (vertical
    /// scale cos→0), the next character swaps in at the fold, and it eases
    /// open, so nothing ever jumps. It searches through digits until its
    /// landing, folds once more onto its letter, then glows softly red.
    private func tile(_ i: Int, at t: Double, width: CGFloat, height: CGFloat) -> some View {
        let landing = Beat.firstLanding + Double(i) * Beat.landingGap
        // Fold phase: whole numbers are "open", .5 is fully folded. Tiles
        // are offset so they don't fold in lockstep. Frozen open after the
        // landing fold completes.
        let raw = t * Self.flipRate + Double(i) * 0.33
        let landingRaw = (landing * Self.flipRate + Double(i) * 0.33).rounded(.up)
        let phase = min(raw, landingRaw)
        let landed = raw >= landingRaw - 0.5
        let character: Character = landed
            ? Self.letters[i]
            : Self.digits[(Int((phase + 0.5).rounded(.down)) * 7 + i * 3) % Self.digits.count]
        let fold = abs(cos(Double.pi * phase.truncatingRemainder(dividingBy: 1)))
        let open = raw >= landingRaw ? 1 : fold
        let flash = t >= landing
            ? 0.55 * max(0, 1 - (t - landing) / Beat.flash)
            : 0

        return ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(tileFill)
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(red.opacity(flash))
            Text(String(character))
                .font(.system(size: height * 0.62, weight: .black, design: .rounded))
                .foregroundColor(.white.opacity(landed ? 1 : 0.8))
                .scaleEffect(x: 1, y: CGFloat(max(0.04, open)))
            Rectangle()
                .fill(seam)
                .frame(height: 2)
        }
        .frame(width: width, height: height)
    }

    private func wordmark(at t: Double) -> some View {
        let title = Self.easeOut(Self.progress(t, Beat.wordmarkIn, Beat.wordmarkIn + Beat.textSettle))
        let line = Self.easeOut(Self.progress(t, Beat.taglineIn, Beat.taglineIn + Beat.textSettle))
        return VStack(spacing: MADTheme.Spacing.sm) {
            Text("Mile A Day")
                .font(.system(size: 38, weight: .black, design: .rounded))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .opacity(title)
                .offset(y: CGFloat(10 * (1 - title)))
            Text("Day 1 starts today.")
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.6))
                .lineLimit(1)
                .opacity(line)
                .offset(y: CGFloat(8 * (1 - line)))
        }
        .padding(.horizontal, 32)
    }

    // MARK: - Lifecycle

    private func begin() {
        guard start == nil else { return }
        overApp = AppStateManager.shared.splashOverlay
        start = Date()

        if !reduceMotion {
            let tick = UIImpactFeedbackGenerator(style: .light)
            let thump = UIImpactFeedbackGenerator(style: .heavy)
            tick.prepare()
            thump.prepare()
            for i in 0..<3 {
                DispatchQueue.main.asyncAfter(deadline: .now() + Beat.firstLanding + Double(i) * Beat.landingGap) {
                    tick.impactOccurred(intensity: 0.6)
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + Beat.mergeStart + 0.1) {
                thump.impactOccurred(intensity: 0.9)
            }
        }

        if overApp {
            // The dashboard may already be ready; otherwise wait for it, capped.
            if gate.ready { scheduleReveal() }
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.revealCap) { scheduleReveal() }
        } else {
            let handoff = reduceMotion ? Self.reducedHandoffDelay : Self.wordmarkHandoffDelay
            DispatchQueue.main.asyncAfter(deadline: .now() + handoff) {
                AppStateManager.shared.completeSplash()
            }
        }
    }

    /// Start the dissolve: never before the icon has landed, once only.
    private func scheduleReveal() {
        guard overApp, revealAt == nil, let start else { return }
        let earliest = start.addingTimeInterval(reduceMotion ? 0.3 : Beat.mergeEnd + 0.25)
        let at = max(Date(), earliest)
        revealAt = at
        let finish = at.timeIntervalSinceNow + Self.revealDuration + 0.05
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, finish)) {
            AppStateManager.shared.finishSplashOverlay()
        }
    }

    // MARK: - Easing (pure functions of t)

    private static func clamp(_ x: Double) -> Double { min(max(x, 0), 1) }

    /// 0→1 as `t` goes from `from` to `to`, clamped.
    private static func progress(_ t: Double, _ from: Double, _ to: Double) -> Double {
        guard to > from else { return t >= to ? 1 : 0 }
        return clamp((t - from) / (to - from))
    }

    private static func easeOut(_ x: Double) -> Double { 1 - pow(1 - x, 3) }

    private static func easeInOut(_ x: Double) -> Double {
        x < 0.5 ? 4 * x * x * x : 1 - pow(-2 * x + 2, 3) / 2
    }

    /// Overshoots a touch then settles: the icon landing (gentle; a bigger
    /// overshoot read as a jump).
    private static func easeOutBack(_ x: Double) -> Double {
        let c1 = 1.1, c3 = c1 + 1
        return 1 + c3 * pow(x - 1, 3) + c1 * pow(x - 1, 2)
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
