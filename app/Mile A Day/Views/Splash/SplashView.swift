import SwiftUI
import UIKit

/// Launch experience for Mile A Day: split-flap into the app.
///
/// Three red flap tiles rattle through numbers like a departures board and
/// land, one after another, on M · A · D (a tick each). They merge into the
/// app icon with a thump. Then:
/// - heading into the app, the icon flies up into the dashboard's real
///   header (`MADTabHeader`: "Mile A Day", today's date, bell + gear) and
///   dissolves into its title while the home screen's flat cards fade in, so
///   the splash becomes the dashboard it hands off to (the dashboard has no
///   icon of its own; the title IS the brand there);
/// - heading into onboarding or sign-in (no dashboard yet), "Mile A Day"
///   rises under the icon instead.
///
/// Every frame is a pure function of the time since the view appeared
/// (`TimelineView` + `frame(at:)`), never a chain of `withAnimation` /
/// `asyncAfter` state flips, so a first frame before `onAppear`, a safe-area
/// settle or a slow launch can't leave one layer out of step with another.
/// The splash owns its own exit (`handoffDelay`); `AppStateManager` keeps a
/// later fallback in case the view never appears.
struct SplashView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var start: Date?
    /// Decided once on appear: does the splash end on the dashboard?
    @State private var intoApp = false

    static let handoffDelay: TimeInterval = 2.05
    private static let wordmarkHandoffDelay: TimeInterval = 1.9
    private static let reducedHandoffDelay: TimeInterval = 0.9

    // MARK: - Timeline (seconds after appear)
    private enum Beat {
        static let tilesIn: Double = 0.15
        /// Tile i lands at `firstLanding + i * landingGap`.
        static let firstLanding: Double = 0.55
        static let landingGap: Double = 0.15
        static let flash: Double = 0.12
        static let mergeStart: Double = 1.05
        static let mergeEnd: Double = 1.35
        static let riseStart: Double = 1.45
        static let riseEnd: Double = 2.0
        static let wordmarkIn: Double = 1.3
        static let taglineIn: Double = 1.45
        static let textSettle: Double = 0.35
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
                frame(at: reduceMotion ? 10 : t, size: geo.size)
                    .opacity(reduceMotion ? Self.progress(t, 0, 0.3) : 1)
            }
        }
        .background(MADTheme.Colors.appBackgroundGradient.ignoresSafeArea())
        .onAppear(perform: begin)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Mile A Day")
    }

    // MARK: - Frame

    private func frame(at t: Double, size: CGSize) -> some View {
        let width = min(size.width, 440)
        let tileWidth = width * 0.2
        let tileHeight = width * 0.27
        let gap = width * 0.03
        let iconSize = width * 0.27
        let center = CGPoint(x: size.width / 2, y: size.height * 0.42)

        let merge = Self.easeInOut(Self.progress(t, Beat.mergeStart, Beat.mergeEnd))
        let rise = intoApp ? Self.easeInOut(Self.progress(t, Beat.riseStart, Beat.riseEnd)) : 0
        // Fly to where the header's title sits (16pt in, ~23pt down: its
        // padding + half the 26pt line) and shrink to about the title's
        // height, fading out over the second half as the title fades in.
        let target = CGPoint(x: MADTheme.Spacing.md + 18, y: MADTheme.Spacing.sm + 15)
        let iconX = center.x + (target.x - center.x) * CGFloat(rise)
        let iconY = center.y + (target.y - center.y) * CGFloat(rise)
        let iconScale = (0.6 + 0.4 * Self.easeOutBack(merge)) * (1 - 0.87 * rise)
        let iconOpacity = merge * (1 - Self.progress(rise, 0.45, 1))

        return ZStack {
            // Soft red light behind the mark; fades as the app takes over.
            RadialGradient(colors: [red.opacity(0.22 * merge * (1 - rise)), .clear],
                           center: UnitPoint(x: 0.5, y: center.y / max(size.height, 1)),
                           startRadius: 0, endRadius: width * 0.7)

            if intoApp && rise > 0 {
                appPreview(size: size, opacity: rise)
            }

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

            if !intoApp {
                wordmark(at: t)
                    .position(x: center.x, y: center.y + iconSize / 2 + width * 0.16)
            }
        }
        .frame(width: size.width, height: size.height)
    }

    /// One flap tile: cycles digits until its landing, then shows its letter
    /// with a short red flash. The flip is a vertical squash on each change.
    private func tile(_ i: Int, at t: Double, width: CGFloat, height: CGFloat) -> some View {
        let landing = Beat.firstLanding + Double(i) * Beat.landingGap
        let landed = t >= landing
        let character: Character
        let flip: Double
        if landed {
            character = Self.letters[i]
            flip = max(0, 1 - (t - landing) * 8)
        } else {
            let k = Int(t * 28) + i * 3
            character = Self.digits[(k * 7 + i) % Self.digits.count]
            flip = (t * 28).truncatingRemainder(dividingBy: 1)
        }
        let flash = landed ? max(0, 1 - (t - landing) / Beat.flash) : 0

        return ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(tileFill)
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(red.opacity(flash))
            Text(String(character))
                .font(.system(size: height * 0.62, weight: .black, design: .rounded))
                .foregroundColor(.white.opacity(landed ? 1 : 0.85))
                .scaleEffect(x: 1, y: CGFloat(1 - flip * 0.5))
            Rectangle()
                .fill(seam)
                .frame(height: 2)
        }
        .frame(width: width, height: height)
    }

    /// The top of the home screen: its real header (same component, title,
    /// date and bell + gear as `DashboardView`) over flat cards in
    /// `DashboardCardSurface`'s fill and radius, so the hand-off lands on it.
    private func appPreview(size: CGSize, opacity: Double) -> some View {
        let card = Color.white.opacity(0.045)
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        let gap: CGFloat = 12
        return VStack(spacing: gap) {
            MADTabHeader(
                title: "Mile A Day",
                subtitle: Self.headerDateFormatter.string(from: Date()),
                actions: [
                    MADHeaderAction(id: "bell", systemImage: "bell.fill", style: .notification(count: 0)) {},
                    MADHeaderAction(id: "settings", systemImage: "gearshape.fill") {}
                ]
            )
            Group {
                shape.fill(card).frame(height: size.height * 0.3)
                HStack(spacing: gap) {
                    shape.fill(card)
                    shape.fill(card)
                }
                .frame(height: size.height * 0.13)
                shape.fill(card).frame(height: size.height * 0.1)
                Capsule().fill(red).frame(height: 54)
            }
            .padding(.horizontal, MADTheme.Spacing.md)
            .offset(y: CGFloat(1 - opacity) * 20)
            Spacer(minLength: 0)
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .opacity(opacity)
        .allowsHitTesting(false)
    }

    /// The dashboard's header date format ("Tuesday, July 21").
    private static let headerDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMMM d"
        return f
    }()

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
        intoApp = AppStateManager.shared.splashLeadsToMain
        start = Date()

        let handoff = reduceMotion
            ? Self.reducedHandoffDelay
            : (intoApp ? Self.handoffDelay : Self.wordmarkHandoffDelay)
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
        DispatchQueue.main.asyncAfter(deadline: .now() + handoff) {
            AppStateManager.shared.completeSplash()
        }
    }

    // MARK: - Easing (pure functions of t)

    /// 0→1 as `t` goes from `from` to `to`, clamped.
    private static func progress(_ t: Double, _ from: Double, _ to: Double) -> Double {
        guard to > from else { return t >= to ? 1 : 0 }
        return min(max((t - from) / (to - from), 0), 1)
    }

    private static func easeOut(_ x: Double) -> Double { 1 - pow(1 - x, 3) }

    private static func easeInOut(_ x: Double) -> Double {
        x < 0.5 ? 4 * x * x * x : 1 - pow(-2 * x + 2, 3) / 2
    }

    /// Overshoots slightly then settles: the icon landing.
    private static func easeOutBack(_ x: Double) -> Double {
        let c1 = 1.70158, c3 = c1 + 1
        return 1 + c3 * pow(x - 1, 3) + c1 * pow(x - 1, 2)
    }
}

#Preview {
    SplashView()
}
