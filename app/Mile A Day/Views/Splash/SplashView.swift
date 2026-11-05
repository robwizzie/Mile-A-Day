import SwiftUI
import UIKit

/// Launch experience for Mile A Day.
///
/// One lap, one mark: a ring draws itself around the centre like a mile being
/// run (a glowing comet leads the stroke), and the moment the lap closes the
/// MAD mark springs in with a pulse, a burst of embers and a haptic thump.
/// "Mile A Day" and a rotating tagline rise in underneath, then the splash
/// hands off on its own.
///
/// Every frame is a pure function of the time since the view appeared
/// (`TimelineView` + `frame(at:)`), never a chain of `withAnimation` /
/// `asyncAfter` state flips. That is what keeps the entrance glitch-free: a
/// first frame rendered before `onAppear`, a safe-area settle or a slow launch
/// can't leave one layer mid-animation while another restarts, because there
/// is no animation state to get out of step. The splash also owns its own
/// exit (`handoffDelay`), so it can't be cut off mid-animation by a timer
/// that started before it was on screen. `AppStateManager` keeps a later
/// fallback in case the view never appears.
struct SplashView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var start: Date?
    @State private var tagline: String = SplashView.taglines.randomElement() ?? "One day, one mile."

    /// When the splash hands off to the next screen (seconds after appear).
    static let handoffDelay: TimeInterval = 1.75
    private static let reducedHandoffDelay: TimeInterval = 0.9

    private static let taglines = [
        "One mile closer.",
        "Every mile counts.",
        "Today's mile awaits.",
        "Lace up. Let's move.",
        "One day, one mile.",
        "Chase the streak."
    ]

    // MARK: - Timeline (seconds after appear)
    private enum Beat {
        static let lapStart: Double = 0.10
        static let lapClose: Double = 0.80
        static let markIn: Double = 0.68
        static let markSettled: Double = 1.12
        static let burstEnd: Double = 1.35
        static let titleIn: Double = 1.00
        static let taglineIn: Double = 1.15
        static let textSettled: Double = 0.38
    }

    // MARK: - Layout (fixed so every device gets the same composition)
    private let ringSize: CGFloat = 148
    private let ringWidth: CGFloat = 7
    private let logoSize: CGFloat = 88
    private let sparkCount = 10

    // MARK: - Palette
    private var isDark: Bool { colorScheme == .dark }
    private let red = MADTheme.Colors.madRed
    private let orange = Color(red: 1.0, green: 0.55, blue: 0.24)
    private var background: Color {
        isDark ? Color(red: 0.05, green: 0.03, blue: 0.04) : Color(red: 0.98, green: 0.97, blue: 0.97)
    }
    private var titleColor: Color { isDark ? .white : Color(red: 0.11, green: 0.11, blue: 0.13) }
    private var subtitleColor: Color { isDark ? .white.opacity(0.6) : Color(red: 0.42, green: 0.40, blue: 0.44) }
    private var trackColor: Color { isDark ? .white.opacity(0.08) : .black.opacity(0.06) }

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: start == nil)) { context in
            let t = start.map { context.date.timeIntervalSince($0) } ?? 0
            frame(at: t)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(background.ignoresSafeArea())
        .onAppear(perform: begin)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Mile A Day")
    }

    // MARK: - Frame

    @ViewBuilder
    private func frame(at t: Double) -> some View {
        if reduceMotion {
            // No motion: the finished composition, faded in once.
            composition(at: 10)
                .opacity(Self.progress(t, 0, 0.3))
        } else {
            composition(at: t)
        }
    }

    private func composition(at t: Double) -> some View {
        VStack(spacing: 36) {
            lap(at: t)
            text(at: t)
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(glow(at: t))
    }

    /// Warm light behind the mark, brightening as the lap runs.
    private func glow(at t: Double) -> some View {
        let p = Self.easeOut(Self.progress(t, 0, Beat.lapClose))
        return RadialGradient(
            colors: [red.opacity((isDark ? 0.30 : 0.12) * p), .clear],
            center: .center, startRadius: 0, endRadius: 260
        )
        .offset(y: -40)
        .ignoresSafeArea()
    }

    // MARK: - Lap + mark

    private func lap(at t: Double) -> some View {
        let lap = Self.easeInOut(Self.progress(t, Beat.lapStart, Beat.lapClose))
        let burst = Self.easeOut(Self.progress(t, Beat.lapClose, Beat.burstEnd))
        let closed = t >= Beat.lapClose
        let mark = Self.progress(t, Beat.markIn, Beat.markSettled)
        let radius = ringSize / 2

        return ZStack {
            // Track
            Circle()
                .stroke(trackColor, lineWidth: ringWidth)
                .opacity(Self.progress(t, 0, 0.25))

            // The lap being run
            Circle()
                .trim(from: 0, to: lap)
                .stroke(
                    AngularGradient(colors: [red, orange, red], center: .center),
                    style: StrokeStyle(lineWidth: ringWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            // Comet head leading the stroke; fades as the lap closes
            Circle()
                .fill(.white)
                .frame(width: ringWidth + 3, height: ringWidth + 3)
                .shadow(color: orange, radius: 8)
                .offset(y: -radius)
                .rotationEffect(.degrees(360 * lap))
                .opacity(lap > 0 ? 1 - Self.progress(t, Beat.lapClose - 0.08, Beat.lapClose + 0.1) : 0)

            // Pulse ring when the lap closes
            Circle()
                .stroke(orange, lineWidth: 2)
                .scaleEffect(1 + 0.32 * burst)
                .opacity(closed ? 0.8 * (1 - burst) : 0)

            // Ember burst
            ForEach(0..<sparkCount, id: \.self) { i in
                let angle = Angle.degrees(Double(i) * 360 / Double(sparkCount) + 18)
                let distance = radius + 10 + 34 * CGFloat(burst)
                Circle()
                    .fill(i.isMultiple(of: 2) ? orange : red)
                    .frame(width: 5, height: 5)
                    .scaleEffect(1 - 0.6 * burst)
                    .offset(x: CGFloat(cos(angle.radians)) * distance, y: CGFloat(sin(angle.radians)) * distance)
                    .opacity(closed ? 1 - burst : 0)
            }

            // The mark springs in as the lap closes
            Image("mad-logo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: logoSize, height: logoSize)
                .clipShape(RoundedRectangle(cornerRadius: logoSize * 0.22, style: .continuous))
                .scaleEffect(0.4 + 0.6 * Self.easeOutBack(mark))
                .opacity(Self.progress(t, Beat.markIn, Beat.markIn + 0.14))
        }
        .frame(width: ringSize, height: ringSize)
    }

    // MARK: - Text

    private func text(at t: Double) -> some View {
        let title = Self.easeOut(Self.progress(t, Beat.titleIn, Beat.titleIn + Beat.textSettled))
        let line = Self.easeOut(Self.progress(t, Beat.taglineIn, Beat.taglineIn + Beat.textSettled))

        return VStack(spacing: MADTheme.Spacing.sm) {
            Text("Mile A Day")
                .font(.system(size: 38, weight: .black, design: .rounded))
                .foregroundColor(titleColor)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .opacity(title)
                .offset(y: 12 * (1 - title))

            Text(tagline)
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundColor(subtitleColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .opacity(line)
                .offset(y: 10 * (1 - line))
        }
        .multilineTextAlignment(.center)
    }

    // MARK: - Lifecycle

    private func begin() {
        guard start == nil else { return }
        start = Date()

        let handoff = reduceMotion ? Self.reducedHandoffDelay : Self.handoffDelay
        if !reduceMotion {
            let thump = UIImpactFeedbackGenerator(style: .heavy)
            let tick = UIImpactFeedbackGenerator(style: .light)
            thump.prepare()
            tick.prepare()
            DispatchQueue.main.asyncAfter(deadline: .now() + Beat.lapClose) {
                thump.impactOccurred(intensity: 0.9)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + Beat.titleIn + 0.1) {
                tick.impactOccurred(intensity: 0.5)
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

    /// Overshoots slightly then settles: the "spring" of the mark landing.
    private static func easeOutBack(_ x: Double) -> Double {
        let c1 = 1.70158, c3 = c1 + 1
        return 1 + c3 * pow(x - 1, 3) + c1 * pow(x - 1, 2)
    }
}

#Preview("Dark") {
    SplashView()
        .preferredColorScheme(.dark)
}

#Preview("Light") {
    SplashView()
        .preferredColorScheme(.light)
}
